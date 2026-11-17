import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../public/p2p_wallet_port.dart';
import '../domain/trade/bond_payment.dart';
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

/// [PayBondFromWalletUsecase.payBond].
typedef BondPayer =
    Future<Result<P2pWalletPayment, BondPayRefusal>> Function(
      TradeRecord record, {
      required P2pWalletQuote accepted,
    });

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

  const BondPaymentState({
    this.balance,
    this.offer,
    this.step = const BondPayLooking(),
  });

  BondPaymentState _with({
    Result<Sats, P2pWalletRefusal>? balance,
    Result<void, BondPayRefusal>? offer,
    BondPayStep? step,
  }) => BondPaymentState(
    balance: balance ?? this.balance,
    offer: offer ?? this.offer,
    step: step ?? this.step,
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

  /// For an order made here, how the bond quoted compares with the bond at the wallet's own price (#180, the owner's payment rule of 2026-11-17): shown in the confirmation, a red warning beyond the owner's threshold; `null` for a take.
  final WalletRateCheck? rate;

  /// Whether the wallet's price is being read again ([BondPaymentCubit.retryRate]), the comparison being [WalletRateUnverified] meanwhile: « Pay » stays offered.
  final bool retrying;

  const BondPayConfirming(this.walletQuote, {this.rate, this.retrying = false});
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

  /// The comparison of a quote with the wallet's own price, for an order made here (#180); `null` where the cubit was given none (the escrow's, until #187), and the confirmation then shows the quote alone, as before.
  final BondRateChecker? _rate;

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
  }) : super(const BondPaymentState());

  /// Reads the balance and looks for a payment of the bond made earlier: once.
  void start() {
    if (isClosed || _balances != null) return;
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
  Future<void> offerFor(TradeSeen seen) async {
    if (isClosed || identical(seen, _checked)) return;
    _checked = seen;
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

  /// Asks the swap service for its quote of the bond as [seen] shows it: on the tap of « Pay with this wallet » only; for an order made here, then compares the quote with the wallet's own price (#180) before the confirmation shows both.
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
    emit(state._with(step: BondPayConfirming(walletQuote, rate: rate)));
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
    final retrying = BondPayConfirming(
      step.walletQuote,
      rate: step.rate,
      retrying: true,
    );
    emit(state._with(step: retrying));
    final read = await rate(record, step.walletQuote);
    if (isClosed || !identical(state.step, retrying)) return;
    emit(
      state._with(
        step: switch (read) {
          Ok(:final value) => BondPayConfirming(step.walletQuote, rate: value),
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

  /// Pays the quote the confirmation shows: on its tap only, once.
  ///
  /// An [Error] of the payment is not caught (AGENTS.md, rule 11): the panel then says it cannot tell where the payment stands, and follows the wallet's records again, before the error goes on.
  Future<void> confirm() async {
    final step = state.step;
    if (isClosed || step is! BondPayConfirming) return;
    _sending();
    var answered = false;
    final Result<P2pWalletPayment, BondPayRefusal> paid;
    try {
      paid = await _payer(record, accepted: step.walletQuote);
      answered = true;
    } finally {
      _stillWaiting?.cancel();
      if (!answered && !isClosed) {
        emit(state._with(step: const BondPayUnreadable(paymentMayExist: true)));
        _followAgain(leavesSending: true, paymentExists: true);
      }
    }
    if (isClosed) return;
    switch (paid) {
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

  /// Follows the payment recorded for the bond. Its events never move the panel out of a quote or a confirmation, nor out of a payment being sent unless [leavesSending] (the follow started once that payment answered or ended); when [paymentExists], finding nothing keeps the payment shown, or says the records cannot tell where it stands.
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
    await _follow?.cancel();
    return super.close();
  }
}

/// The wallet's payment of a seller's escrow (#97): the same cubit, over the functions of the escrow's [PayBondFromWalletUsecase] and its [step], of a type of its own so that one trade page provides both.
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
  });
}
