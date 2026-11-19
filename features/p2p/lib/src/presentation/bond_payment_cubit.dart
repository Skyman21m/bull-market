import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../public/p2p_wallet_port.dart';
import '../domain/trade/bond_payment.dart';
import '../domain/trade/escrow_contract.dart';
import '../domain/trade/trade_status.dart';
import '../domain/trade/trade_watch.dart';
import '../domain/trade/wallet_payment.dart';
import '../domain/trade/wallet_rate_check.dart';
import '../domain/trade_record.dart';
import '../domain/usecases/trade/pay_bond_from_wallet_usecase.dart';

/// [PayBondFromWalletUsecase.watchBalance], which the locator gives the cubit.
typedef BondBalanceReader =
    Stream<Result<Sats, P2pWalletRefusal>> Function(RobosatsNetwork network);

/// [PayBondFromWalletUsecase.checkBond].
typedef BondOfferChecker =
    Future<Result<WalletPaymentOffered, BondPayRefusal>> Function(
      TradeRecord record,
      TradeSeen seen,
    );

/// [PayBondFromWalletUsecase.quoteBond].
typedef BondQuoter =
    Future<Result<P2pWalletQuote, BondPayRefusal>> Function(
      TradeRecord record,
      TradeSeen seen,
    );

/// [PayBondFromWalletUsecase.rateOfBond].
typedef BondRateChecker =
    Future<Result<WalletRateCheck?, BondPayRefusal>> Function(
      TradeRecord record,
      P2pWalletQuote walletQuote,
    );

/// [PayBondFromWalletUsecase.escrowContractOf]: for a maker seller's escrow (#187), the contract the confirmation of a quote states.
typedef EscrowContractReader =
    Future<Result<EscrowContract?, BondPayRefusal>> Function(
      TradeRecord record,
      P2pWalletQuote walletQuote,
    );

/// [PayBondFromWalletUsecase.payBond].
typedef BondPayer =
    Future<Result<P2pWalletPayment, BondPayRefusal>> Function(
      TradeRecord record, {
      required P2pWalletQuote accepted,
      EscrowContract? contract,
    });

/// [PayBondFromWalletUsecase.followEscrows].
typedef EscrowsFollower =
    Stream<EscrowPaymentsWatch> Function(TradeRecord record);

/// [PayBondFromWalletUsecase.followBond].
typedef BondFollower = Stream<BondPaymentWatch> Function(TradeRecord record);

/// [PayBondFromWalletUsecase.bondPaymentRunning].
typedef BondPaymentRunning = Future<void>? Function(TradeRecord record);

/// What the panel of « Pay with this wallet » shows of one trade's bond (#100): the Instant Payments balance, whether the wallet is offered for the invoice shown, and where a payment stands.
@immutable
final class BondPaymentState {
  /// The Instant Payments balance, `null` until the wallet answers.
  final Result<Sats, P2pWalletRefusal>? balance;

  /// Whether the wallet is offered for the invoice shown, `null` until checked.
  final Result<void, BondPayRefusal>? offer;

  final BondPayStep step;

  /// For a maker seller's escrow (#188), where every escrow this wallet was asked to pay for the order stands, contract by contract (`followEscrows`); `null` until read, and for every other payment.
  final EscrowPaymentsWatch? escrows;

  /// The contract whose escrow [step] follows (`TradeTrail.take` when the follow started): the escrows of the other contracts are said apart ([escrows]).
  final int followedTake;

  /// The escrows whose refund was pending and which a later state of the wallet's records shows held again or kept (security review of #187, C2): by contract, with the state that followed; an alert for the page's life.
  final Map<int, P2pWalletPaymentProgress> refundsUndone;

  const BondPaymentState({
    this.balance,
    this.offer,
    this.step = const BondPayLooking(),
    this.escrows,
    this.followedTake = 0,
    this.refundsUndone = const {},
  });

  BondPaymentState _with({
    Result<Sats, P2pWalletRefusal>? balance,
    Result<void, BondPayRefusal>? offer,
    BondPayStep? step,
    EscrowPaymentsWatch? escrows,
    int? followedTake,
    Map<int, P2pWalletPaymentProgress>? refundsUndone,
  }) => BondPaymentState(
    balance: balance ?? this.balance,
    offer: offer ?? this.offer,
    step: step ?? this.step,
    escrows: escrows ?? this.escrows,
    followedTake: followedTake ?? this.followedTake,
    refundsUndone: refundsUndone ?? this.refundsUndone,
  );
}

/// Where the user stands with the wallet's payment of the bond.
@immutable
sealed class BondPayStep {
  const BondPayStep();
}

/// Looking in the records and the wallet's for a payment of the bond made earlier: nothing is offered meanwhile.
final class BondPayLooking extends BondPayStep {
  const BondPayLooking();
}

/// Nothing paid from this wallet: « Pay with this wallet » is offered when [BondPaymentState.offer] allows it; [refused] says why the last attempt did not pay (nothing left the wallet).
final class BondPayIdle extends BondPayStep {
  final BondPayRefusal? refused;

  const BondPayIdle({this.refused});
}

/// The swap service is being asked for its quote, after the user's tap.
final class BondPayQuoting extends BondPayStep {
  const BondPayQuoting();
}

/// The quote, which the user confirms or cancels.
final class BondPayConfirming extends BondPayStep {
  final P2pWalletQuote walletQuote;

  /// For an order made here, how the bond or the escrow quoted compares with what the order implies at the wallet's own price (#180, #188, the owner's payment rule of 2026-11-17): shown in the confirmation, a red warning beyond the owner's threshold; `null` for a take.
  final WalletRateCheck? rate;

  /// For a maker seller's escrow (#188), the contract the confirmation states, built from [walletQuote] itself, the quote « Pay » pays (security review of #187, C4, point (a) of #188): a new contract, the earlier escrows not back or kept; the payment takes it back. `null` for every other payment.
  final EscrowContract? contract;

  /// Whether the wallet's price is being read again ([BondPaymentCubit.retryRate]), the comparison being [WalletRateUnverified] meanwhile: « Pay » stays offered.
  final bool retrying;

  /// Whether this confirmation is asked again ([BondPayConfirmAgain]): more was out under the payment's lock than the confirmation before showed, nothing was paid, and [contract] holds the figures now.
  final bool again;

  /// Whether the order was taken again since this confirmation opened (#188): its contract is no longer the trail's, its « Pay » would pay nothing ([BondPayContractNotConfirmed]), and the panel says so.
  final bool stale;

  const BondPayConfirming(
    this.walletQuote, {
    this.rate,
    this.contract,
    this.retrying = false,
    this.again = false,
    this.stale = false,
  });

  BondPayConfirming _with({
    WalletRateCheck? rate,
    bool? retrying,
    bool? stale,
  }) => BondPayConfirming(
    walletQuote,
    rate: rate ?? this.rate,
    contract: contract,
    retrying: retrying ?? this.retrying,
    again: again,
    stale: stale ?? this.stale,
  );
}

/// The payment is being made, after the user's confirmation, or by this process while the screen was away; [slow] once it has run for [BondPaymentCubit.stillWaitingAfter].
final class BondPaySending extends BondPayStep {
  final bool slow;

  const BondPaySending({this.slow = false});
}

/// A payment of the bond by this wallet exists, and stands at [progress].
final class BondPayFollowing extends BondPayStep {
  final P2pWalletPaymentProgress progress;

  const BondPayFollowing(this.progress);
}

/// The wallet holds a payment of the invoice made by its own screens, which this feature does not follow: [progress] says whether its funds may have left the wallet (then « This wallet already paid this invoice. », nothing more offered) or not (interrupted before it was sent: the other wallet only).
final class BondPayPaidElsewhere extends BondPayStep {
  final P2pWalletPaymentProgress progress;

  const BondPayPaidElsewhere(this.progress);
}

/// The records, or the wallet's, could not be read: nothing is offered, since a payment may exist.
final class BondPayUnreadable extends BondPayStep {
  /// Whether a payment of the bond was answered or found before: then the other wallet offers no QR code nor copy, and a cancel at 3 says a payment may be on its way.
  final bool paymentMayExist;

  const BondPayUnreadable({this.paymentMayExist = false});
}

/// The wallet's payment of one trade's bond, as the trade screen shows it (#100): one per shown trade, which only the user's taps make pay.
///
/// [start] reads the balance and looks for a payment made earlier ([BondFollower]): a payment found is followed, never made again. [ask] asks the swap service for its quote, on the tap of « Pay with this wallet » only; [confirm] pays that quote, on the tap of its confirmation only; [dismiss] leaves the confirmation. A tap while a quote or a payment runs does nothing.
/// It names neither the wallet's port nor its payment: the functions of [PayBondFromWalletUsecase] are given by the locator.
class BondPaymentCubit extends Cubit<BondPaymentState> {
  /// After how long a payment being sent is said to be still waiting, as the take says it (`TakeOrderCubit.stillWaitingAfter`).
  static const stillWaitingAfter = Duration(seconds: 30);

  final TradeRecord record;
  final BondBalanceReader _balance;
  final BondOfferChecker _check;
  final BondQuoter _quoter;
  final BondPayer _payer;
  final BondFollower _follower;
  final BondPaymentRunning _running;
  final Duration _stillWaitingAfter;

  /// The comparison of a quote with the wallet's own price, for an order made here (#180, the escrow's since #188); `null` where the cubit was given none, and the confirmation then shows the quote alone, as before.
  final BondRateChecker? _rate;

  /// The contract of a maker seller's escrow (#188), `null` where the cubit was given none (the bond's).
  final EscrowContractReader? _contract;

  /// Every escrow of the trade, contract by contract (#188), `null` where the cubit was given none (the bond's).
  final EscrowsFollower? _escrowsFollower;
  StreamSubscription<EscrowPaymentsWatch>? _escrows;

  /// The progress of each escrow followed last, by contract: a refund pending that turns held or kept again is an alert ([BondPaymentState.refundsUndone]).
  final Map<int, P2pWalletPaymentProgress> _lastProgress = {};

  /// The invoice this cubit pays, the step of the use case whose functions it was given (the locator passes `PayBondFromWalletUsecase.step`): the panel offers the wallet only for a request of that step.
  final InvoiceStep step;
  Timer? _stillWaiting;

  StreamSubscription<Result<Sats, P2pWalletRefusal>>? _balances;
  StreamSubscription<BondPaymentWatch>? _follow;

  /// The status the last check was made for: a check is made again only for another invoice or another status.
  TradeSeen? _checked;

  BondPaymentCubit(
    this.record,
    this._balance,
    this._check,
    this._quoter,
    this._payer,
    this._follower,
    this._running, {
    this._stillWaitingAfter = BondPaymentCubit.stillWaitingAfter,
    this.step = InvoiceStep.bond,
    this._rate,
    this._contract,
    this._escrowsFollower,
  }) : super(const BondPaymentState());

  /// Reads the balance and looks for a payment of the bond made earlier: once. For a maker seller's escrow, every escrow of the trade is followed first (#188), before any check of the wallet's offer.
  void start() {
    if (isClosed || _balances != null) return;
    _followEscrows();
    _balances = _balance(record.network).listen((balance) {
      if (!isClosed) emit(state._with(balance: balance));
    });
    // A payment this process is making now, its earlier screen closed: said as being sent, then followed once it ends.
    final running = _running(record);
    if (running == null) {
      _followAgain();
      return;
    }
    _sending();
    unawaited(
      running.whenComplete(() {
        _stillWaiting?.cancel();
        if (!isClosed) _followAgain(leavesSending: true);
      }),
    );
  }

  void _sending() {
    emit(state._with(step: const BondPaySending()));
    _stillWaiting?.cancel();
    _stillWaiting = Timer(_stillWaitingAfter, () {
      if (!isClosed && state.step is BondPaySending) {
        emit(state._with(step: const BondPaySending(slow: true)));
      }
    });
  }

  /// Checks, without asking the swap service, whether the wallet is offered for the bond as [seen] shows it: once per status shown.
  ///
  /// A maker seller's order taken again (#188, a later contract in [seen]'s trail): every escrow is followed again (`followEscrows` reads the records once), the payment followed becomes the new contract's, and a confirmation open for the earlier contract is said stale (its « Pay » would pay nothing).
  Future<void> offerFor(TradeSeen seen) async {
    if (isClosed || identical(seen, _checked)) return;
    _checked = seen;
    if (!_contractMoved(seen.status.trail.take)) {
      // Each status shown reads the escrows again, as the check below reads them: a payment the wallet's records hold since is followed.
      _followEscrows();
    }
    final offer = await _check(record, seen);
    if (isClosed || !identical(seen, _checked)) return;
    emit(
      state._with(
        offer: switch (offer) {
          Ok() => const Ok(null),
          Err(:final failure) => Err(failure),
        },
      ),
    );
  }

  /// The contract [take] shown, for a cubit that follows a maker seller's escrows: when it is not the one followed, every escrow is followed again and so is the payment of the new contract, unless a quote, a confirmation or a payment is under way (a confirmation then said stale, the payment's end following the new contract).
  ///
  /// Whether it moved.
  bool _contractMoved(int take) {
    if (_escrowsFollower == null || take == state.followedTake) return false;
    emit(state._with(followedTake: take));
    _followEscrows();
    switch (state.step) {
      case final BondPayConfirming confirming
          when confirming.contract?.take != take:
        emit(state._with(step: confirming._with(stale: true)));
      case BondPayQuoting() || BondPayConfirming() || BondPaySending():
        break;
      case _:
        // The earlier contract's payment is no longer the panel's: looked for again under the new contract, where finding none offers the wallet.
        emit(state._with(step: const BondPayLooking()));
        _followAgain(leavesSending: true);
    }
    return true;
  }

  /// Follows every escrow of the trade again (#188): `followEscrows` reads the records once, when it is listened to.
  void _followEscrows() {
    final follower = _escrowsFollower;
    if (follower == null || isClosed) return;
    unawaited(_escrows?.cancel());
    _escrows = follower(record).listen((watch) {
      if (isClosed) return;
      var undone = state.refundsUndone;
      if (watch case EscrowPaymentsFollowed(:final escrows)) {
        for (final escrow in escrows) {
          if (escrow.watch case BondPaymentFollowed(:final progress)) {
            final before = _lastProgress[escrow.take];
            _lastProgress[escrow.take] = progress;
            // A refund pending is not final in Bull's own code (security review of #187, C2): one that turns held or kept again is said.
            if (before is P2pWalletPaymentRefundPending &&
                (progress is P2pWalletPaymentPending ||
                    progress is P2pWalletPaymentPaid)) {
              undone = {...undone, escrow.take: progress};
            }
          }
        }
      }
      emit(state._with(escrows: watch, refundsUndone: undone));
    });
  }

  /// Asks the swap service for its quote of the bond as [seen] shows it: on the tap of « Pay with this wallet » only; for an order made here, then compares the quote with the wallet's own price (#180) before the confirmation shows both; for a maker seller's escrow, first the contract the confirmation states, built from that very quote (#188).
  ///
  /// The follow of an earlier payment stops here: from the quote to the end of the payment, no event of the wallet's records moves the panel (a preparation left by an earlier run that expires meanwhile would offer to pay again while this payment runs).
  Future<void> ask(TradeSeen seen) async {
    if (isClosed || state.step is! BondPayIdle) return;
    unawaited(_follow?.cancel());
    _follow = null;
    emit(state._with(step: const BondPayQuoting()));
    final quoted = await _quoter(record, seen);
    if (isClosed) return;
    final P2pWalletQuote walletQuote;
    switch (quoted) {
      case Ok(:final value):
        walletQuote = value;
      case Err(:final failure):
        emit(state._with(step: BondPayIdle(refused: failure)));
        return;
    }
    // The contract of a maker seller's escrow, from the quote « Pay » will pay (security review of #187, C4): never another quote's.
    final EscrowContract? contract;
    switch (await _contract?.call(record, walletQuote)) {
      case null || Ok(value: null):
        contract = null;
      case Ok(:final value?):
        contract = value;
      case Err(:final failure):
        if (!isClosed) emit(state._with(step: BondPayIdle(refused: failure)));
        return;
    }
    if (isClosed) return;
    final WalletRateCheck? rate;
    switch (await _rate?.call(record, walletQuote)) {
      case null || Ok(value: null):
        rate = null;
      case Ok(:final value?):
        rate = value;
      case Err(:final failure):
        if (!isClosed) emit(state._with(step: BondPayIdle(refused: failure)));
        return;
    }
    if (isClosed) return;
    emit(
      state._with(
        step: BondPayConfirming(
          walletQuote,
          rate: rate,
          contract: contract,
          // Taken again while the quote was asked: said at once.
          stale: contract != null && contract.take != state.followedTake,
        ),
      ),
    );
  }

  /// Reads the wallet's price again for the quote the confirmation shows, when its price could not be read ([WalletRateUnverified]): on the tap of « Retry » only, once at a time; the quote is kept, never asked again.
  ///
  /// The comparison it gives replaces the line, with or without the red warning, or still says « rate not checked ». A confirmation left meanwhile (« Go back », « Pay », a closed screen) is not touched: what the read gives then is dropped. A quote the wallet finds too old by the time « Pay » is tapped is refused by the wallet as any stale quote (`P2pWalletQuoteStale`), nothing paid, and « Pay with this wallet » asks a new quote and a new price.
  Future<void> retryRate() async {
    final step = state.step;
    final rate = _rate;
    if (isClosed ||
        rate == null ||
        step is! BondPayConfirming ||
        step.retrying ||
        step.rate is! WalletRateUnverified) {
      return;
    }
    final retrying = step._with(retrying: true);
    emit(state._with(step: retrying));
    final read = await rate(record, step.walletQuote);
    final now = state.step;
    if (isClosed || now is! BondPayConfirming || !identical(now, retrying)) {
      // A confirmation said stale meanwhile keeps its retry's end: the read is dropped, the line stays « not checked ».
      if (!isClosed && now is BondPayConfirming && now.retrying && now.stale) {
        emit(state._with(step: now._with(retrying: false)));
      }
      return;
    }
    emit(
      state._with(
        step: switch (read) {
          Ok(:final value) => BondPayConfirming(
            step.walletQuote,
            rate: value,
            contract: step.contract,
            again: step.again,
            stale: step.stale,
          ),
          Err(:final failure) => BondPayIdle(refused: failure),
        },
      ),
    );
  }

  /// Leaves the confirmation without paying.
  void dismiss() {
    if (isClosed || state.step is! BondPayConfirming) return;
    emit(state._with(step: const BondPayIdle()));
  }

  /// Pays the quote the confirmation shows: on its tap only, once. [shown] is the confirmation the tapped button was drawn for: a tap on a confirmation that is no longer the one on screen (a new one shown meanwhile, with other figures) pays nothing.
  ///
  /// For a maker seller's escrow the confirmation's contract goes with it (#188), built from that very quote; when more is out under the payment's lock ([BondPayConfirmAgain]), nothing is paid and the confirmation shows again with the contract the refusal carries, for the same quote, its next « Pay » paying.
  /// An [Error] of the payment is not caught (AGENTS.md, rule 11): the panel then says it cannot tell where the payment stands, and follows the wallet's records again, before the error goes on.
  Future<void> confirm({BondPayConfirming? shown}) async {
    final step = state.step;
    if (isClosed || step is! BondPayConfirming) return;
    if (shown != null && !identical(shown, step)) return;
    _sending();
    var answered = false;
    final Result<P2pWalletPayment, BondPayRefusal> paid;
    try {
      paid = await _payer(
        record,
        accepted: step.walletQuote,
        contract: step.contract,
      );
      answered = true;
    } finally {
      _stillWaiting?.cancel();
      if (!answered && !isClosed) {
        emit(state._with(step: const BondPayUnreadable(paymentMayExist: true)));
        _followAgain(leavesSending: true, paymentExists: true);
      }
      // A payment recorded or attempted: every escrow of the trade followed again, its record included (#188).
      if (!isClosed) _followEscrows();
    }
    if (isClosed) return;
    switch (paid) {
      case Err(failure: BondPayConfirmAgain(:final contract)):
        // More out than confirmed (the owner's decision of 2026-11-19): the confirmation again, with the figures now, for the very quote; the next « Pay » pays.
        emit(
          state._with(
            step: BondPayConfirming(
              step.walletQuote,
              rate: step.rate,
              contract: contract,
              again: true,
              stale: contract.take != state.followedTake,
            ),
          ),
        );
      case Ok():
        // The funding was broadcast: the payment is sent, whatever the records say next.
        emit(state._with(step: const BondPayFollowing(P2pWalletPaymentSent())));
        _followAgain(leavesSending: true, paymentExists: true);
      case Err(
        failure: BondPayWalletRefused(
          refusal: P2pWalletPaymentExists(payment: null, :final progress),
        ),
      ):
        // A payment of the invoice made by the wallet's own screens: never paid again from here.
        emit(state._with(step: BondPayPaidElsewhere(progress)));
      case Err(failure: BondPayWalletRefused(:final refusal))
          when _carriesPayment(refusal):
        // A payment exists for the invoice (made now or before): it is followed, never made again.
        _followAgain(leavesSending: true, paymentExists: true);
      case Err(:final failure):
        emit(state._with(step: BondPayIdle(refused: failure)));
    }
  }

  static bool _carriesPayment(P2pWalletRefusal refusal) => switch (refusal) {
    P2pWalletBroadcastUnknown() || P2pWalletPaymentInterrupted() => true,
    P2pWalletPaymentExists(:final payment) => payment != null,
    _ => false,
  };

  /// « Sending » while this process pays the bond now, followed again once that payment ends; `null` when it pays none.
  BondPayStep? _sendingUntilDone() {
    final running = _running(record);
    if (running == null) return null;
    unawaited(
      running.whenComplete(() {
        if (!isClosed) _followAgain(leavesSending: true);
      }),
    );
    return const BondPaySending();
  }

  /// Follows the payment recorded for the bond (for a maker seller's escrow, the contract's the trail stands at when the follow starts). Its events never move the panel out of a quote or a confirmation, nor out of a payment being sent unless [leavesSending] (the follow started once that payment answered or ended); when [paymentExists], finding nothing keeps the payment shown, or says the records cannot tell where it stands.
  void _followAgain({bool leavesSending = false, bool paymentExists = false}) {
    unawaited(_follow?.cancel());
    _follow = _follower(record).listen((watch) {
      if (isClosed) return;
      final current = state.step;
      if (current is BondPayQuoting || current is BondPayConfirming) return;
      if (current is BondPaySending && !leavesSending) return;
      emit(
        state._with(
          step: switch (watch) {
            BondPaymentNone() => switch (current) {
              // A payment the wallet started but whose record is not read yet stays as it was shown.
              final BondPayFollowing following => following,
              final BondPaySending sending when _running(record) != null =>
                sending,
              _ when paymentExists => const BondPayUnreadable(
                paymentMayExist: true,
              ),
              _ => const BondPayIdle(),
            },
            // A payment that moved nothing and is not left signed: being prepared by this process now, being sent; left by an earlier run, it may be tried again (the wallet pays it again only while it is provably unspent).
            BondPaymentFollowed(:final progress)
                when !progress.fundsMayHaveLeft &&
                    progress is! P2pWalletPaymentSigned =>
              _sendingUntilDone() ?? const BondPayIdle(),
            BondPaymentFollowed(:final progress) => BondPayFollowing(progress),
            BondPaymentUnreadable() => BondPayUnreadable(
              paymentMayExist:
                  paymentExists ||
                  current is BondPayFollowing ||
                  current is BondPaySending,
            ),
          },
        ),
      );
    });
  }

  @override
  Future<void> close() async {
    _stillWaiting?.cancel();
    await _balances?.cancel();
    // Not awaited: a follow waiting for the wallet's next change ends only at that change, as the payment's own follow (`PayBondFromWalletUsecase.followEscrows`).
    unawaited(_escrows?.cancel());
    await _follow?.cancel();
    return super.close();
  }
}

/// The wallet's payment of a seller's escrow (#97): the same cubit, over the functions of the escrow's [PayBondFromWalletUsecase] and its [step], of a type of its own so that one trade page provides both. For a maker seller's escrow (#188) it is also given the comparison with the wallet's own price, the contract the confirmation states, and the follow of every escrow of the trade, which give nothing for a taker.
final class EscrowPaymentCubit extends BondPaymentCubit {
  EscrowPaymentCubit(
    super.record,
    super.balance,
    super.check,
    super.quoter,
    super.payer,
    super.follower,
    super.running, {
    super.stillWaitingAfter,
    required super.step,
    super.rate,
    super.contract,
    super.escrowsFollower,
  });
}
