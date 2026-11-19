import 'dart:async';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../../../public/p2p_wallet_port.dart';
import '../../p2p_failure.dart';
import '../../repositories/trade_payment_repository.dart';
import '../../robot_request_limiter.dart';
import '../../trade/bond_payment.dart';
import '../../trade/escrow_contract.dart';
import '../../trade/trade_answer.dart';
import '../../trade/trade_payment.dart';
import '../../trade/trade_status.dart';
import '../../trade/trade_terms.dart';
import '../../trade/trade_watch.dart';
import '../../trade/wallet_payment.dart';
import '../../trade/wallet_rate_check.dart';
import '../../trade_record.dart';
import 'bond_payments_in_flight.dart';
import 'escrow_amounts.dart';
import 'trade_reader.dart';
import 'trade_take_locks.dart';

/// Pays a trade's bond (#100, W4), or a seller's escrow (#97), from the wallet's Instant Payments wallet, inside the trade screen: the only caller of [P2pWalletPort.payInvoice] (`wallet_port_architecture_test.dart`).
///
/// One instance per [step], the same code for both: the bond is paid from a stored `WaitingForTakerBond` within [TradeTerms.bondCeiling], or for an order made here from a stored `WaitingForMakerBond` within the same getter, which is then `MakerTerms.bondCeiling` (#180); the escrow from a stored `WaitingForBoth` or `WaitingForEscrow`, a taker seller's within [TradeTerms.escrowCeiling], a maker seller's (#187) under the owner's payment rule of 2026-11-17 and, for a retaken order, after an alert of the earlier escrows not back yet (the owner's decision of 2026-11-19, below); the methods keep the bond's names, the step it was written for first.
///
/// A maker seller's escrow (#187, design note `docs/design/phase-3-making-an-order.md` § 3.3, § 4.3, § 6 row 13): no ceiling (the owner's rule replaced it), but the exact agreements the state machine checks (the invoice equal to `escrow_satoshis` and `trade_satoshis`, the implied fee within the announced one), any warning of which forbids the wallet (`walletPaymentFor`); the comparison with the contract's amount at the wallet's own price ([rateOfBond]), information and a warning only; the contract the confirmation states ([escrowContractOf]: a new contract after the order's first take, the earlier escrows of the order this wallet was asked to pay with their sats and case, what is not back yet and what will be out with this one, those the coordinator kept: an alert, never a refusal, the owner's decision of 2026-11-19), which [payBond] takes back, checks against the trail read again under the payment's lock, and has confirmed again when more is out by then ([BondPayConfirmAgain]); never an escrow whose payment hash was presented before ([BondPayEscrowSeenBefore]). Each escrow is recorded under its contract (`trade_payments.take`), and followed under it ([followBond] for the current one, [followEscrows] for every one, after the trade's end too).
///
/// - [watchBalance]: what the Instant Payments wallet can spend, as the wallet reads it.
/// - [quoteBond]: on the user's tap of « Pay with this wallet » only, the swap service's quote for the invoice the status shown offers (`walletPaymentFor`, at most the bond the take's or the make's terms imply, [TradeTerms.bondCeiling]); nothing is created at the service.
/// - [rateOfBond]: for an order made here, once the quote is given and before the confirmation is shown, how the bond quoted compares with the bond at the wallet's own price of a bitcoin ([WalletRateCheck], the owner's payment rule of 2026-11-17); `null` for a take, whose rule is the take's. Information and a warning for the confirmation: it never refuses, and [payBond] never reads it.
/// - [payBond]: on the user's confirmation of that quote only, one action of the order at a time ([TradeTakeLocks], shared with the take and the payout). It reads the order again with the trade's robot, keeps what the read gives, and pays only when the status it now stores is [step]'s and `walletPaymentFor` offers the very invoice quoted; the payment is recorded ([TradePaymentRepository.recordStart]) before the wallet is asked, and the wallet's id of it after.
/// - [followBond]: where the payment recorded for the trade stands, from the wallet's records ([P2pWalletPort.findPayment], then [P2pWalletPort.watchPayment]); it pays nothing.
///
/// Nothing here retries a payment or pays by itself: a poll, a reopen or a follow never reaches [payBond]. Every refusal of the wallet but [P2pWalletBroadcastUnknown] means nothing left the wallet.
final class PayBondFromWalletUsecase {
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final TradePaymentRepository _payments;
  final P2pWalletPort _wallet;
  final TradeTakeLocks _locks;
  final BondPaymentsInFlight _inFlight;

  /// The sats of each maker seller's escrow this run asked the wallet to pay (#187), one for the feature in the composition: what the confirmation of a next contract says of the earlier escrows.
  final EscrowAmounts _amounts;

  /// The invoice this instance pays: the taker's bond, or the seller's escrow.
  final InvoiceStep step;

  PayBondFromWalletUsecase(
    this._reader,
    this._limiter,
    this._payments,
    this._wallet,
    this._locks,
    this._inFlight, {
    this.step = InvoiceStep.bond,
    EscrowAmounts? amounts,
  }) : _amounts = amounts ?? EscrowAmounts();

  /// When the payment of [record]'s [step] this process is making now ends, `null` when none runs: a screen opened meanwhile says the payment is being sent.
  Future<void>? bondPaymentRunning(TradeRecord record) =>
      _inFlight.running(record, step);

  /// What the Instant Payments wallet on [network] can spend, at once and after each sync of it; a refusal ends the stream.
  Stream<Result<Sats, P2pWalletRefusal>> watchBalance(
    RobosatsNetwork network,
  ) => _wallet.instantBalance(network);

  /// Whether the wallet may be offered for the bond of [record] at [seen], without asking anything of the swap service: the invoice `walletPaymentFor` offers, or why not.
  Future<Result<WalletPaymentOffered, BondPayRefusal>> checkBond(
    TradeRecord record,
    TradeSeen seen,
  ) async {
    if (!seen.stored || !_atStep(seen.status)) {
      return const Err(BondPayNotAtBondStep());
    }
    final TradeTerms terms;
    switch (await _reader.open(record)) {
      case TradeOpened(:final trade):
        terms = trade.terms;
      case TradeNotRestorable() || TradeTakeNeverSent():
        return const Err(BondPayNotAtBondStep());
      case TradeNotOpened(:final failure):
        return Err(BondPayRecordsUnreadable(failure));
    }
    final WalletPaymentOffered offered;
    switch (_offered(terms, seen.status)) {
      case Ok(:final value):
        offered = value;
      case Err(:final failure):
        return Err(failure);
    }
    // A maker seller's escrow (#187): never for a payment hash the trade, or another trade, saw before; earlier escrows not back are the confirmation's alert, never a refusal (the owner's decision of 2026-11-19).
    if (_isMakerEscrow(terms)) {
      switch (await _contractOf(
        record,
        take: offered.take,
        paymentHash: offered.walletInvoice.paymentHash,
        escrow: offered.walletInvoice.amount,
        earlierEscrows: seen.status.trail.earlierEscrows,
      )) {
        case Ok():
          break;
        case Err(:final failure):
          return Err(failure);
      }
    }
    return Ok(offered);
  }

  /// The swap service's quote for the bond of [record] as [seen] shows it, on the tap of « Pay with this wallet »: the quote is what the confirmation states, and what [payBond] pays within.
  Future<Result<P2pWalletQuote, BondPayRefusal>> quoteBond(
    TradeRecord record,
    TradeSeen seen,
  ) async {
    final WalletPaymentOffered offered;
    switch (await checkBond(record, seen)) {
      case Ok(:final value):
        offered = value;
      case Err(:final failure):
        return Err(failure);
    }
    return switch (await _wallet.quote(offered.walletInvoice)) {
      Ok(:final value) => Ok(value),
      Err(:final failure) => Err(BondPayWalletRefused(failure)),
    };
  }

  /// For an order made here, how the bond or the escrow of [quote] (the swap service's quote [quoteBond] gave) compares with what the order implies at the wallet's own price of a bitcoin, read now through the wallet's port (the owner's payment rule of 2026-11-17, design note `docs/design/phase-3-making-an-order.md` § 3.3): for the maker bond, the bond of the order's largest amount ([WalletRateCheck.ofMakerBond], #180); for a maker seller's escrow, the sats of the contract's amount kept in the trail, the fixed amount or a range's amount its take chose ([WalletRateCheck.ofMakerEscrow], #187). `null` for a take, whose rules are the take's.
  ///
  /// Asked once the quote is given, before the confirmation is shown: the price is the one of the moment of paying. The amount compared is the quote's invoice's, the one the wallet pays. It refuses nothing for the price: an amount beyond the owner's threshold is shown in red, and [payBond] still pays what the user confirms. For the escrow, a quote of another invoice than the escrow the trail pins is [BondPayInvoiceChanged], and a contract's amount the trail does not give (a range without one kept, which the state machine never stores at 6 or 7) [BondPayNotAtBondStep]. The wallet's price is asked only for an order made here, never at a take.
  Future<Result<WalletRateCheck?, BondPayRefusal>> rateOfBond(
    TradeRecord record,
    P2pWalletQuote quote,
  ) async {
    final OpenTrade trade;
    switch (await _reader.open(record)) {
      case TradeOpened(trade: final opened):
        trade = opened;
      case TradeNotRestorable() || TradeTakeNeverSent():
        return const Err(BondPayNotAtBondStep());
      case TradeNotOpened(:final failure):
        return Err(BondPayRecordsUnreadable(failure));
    }
    final terms = trade.terms;
    switch ((terms.side, step)) {
      case (TakenSide(), _):
        return const Ok(null);
      case (MadeSide(:final maker), InvoiceStep.bond):
        final rate = await _wallet.bitcoinRate(maker.network, maker.currency);
        return Ok(
          WalletRateCheck.ofMakerBond(maker, asked: quote.amount, wallet: rate),
        );
      case (MadeSide(:final maker), InvoiceStep.escrow):
        if (!_isMakerEscrow(terms)) return const Ok(null);
        final trail = trade.seen.status.trail;
        if (trail.escrowHash != quote.invoice.paymentHash) {
          return const Err(BondPayInvoiceChanged());
        }
        final kept = trail.takenAmount;
        final amount = maker.contractAmount(
          kept == null ? null : FiatAmount.tryCreate(kept),
        );
        if (amount == null) return const Err(BondPayNotAtBondStep());
        final rate = await _wallet.bitcoinRate(maker.network, maker.currency);
        return Ok(
          WalletRateCheck.ofMakerEscrow(
            maker,
            amount: amount,
            asked: quote.amount,
            wallet: rate,
          ),
        );
    }
  }

  /// For a maker seller's escrow (#187), what the confirmation of [quote] says of its contract ([EscrowContract]): the contract the trail stands at (a new contract when above 0), each escrow this wallet was asked to pay for the order's other contracts with its case and its sats when this run knows them, the sats of those not back yet and what will be out of the wallet with this one, and those the coordinator kept; `null` for the bond's instance and for a taker. An earlier escrow not back, or kept, is an alert of the confirmation, never a refusal (the owner's decision of 2026-11-19). [payBond] takes it back, pays only for that very contract, and asks a new confirmation when more is out by then.
  ///
  /// [BondPayEscrowSeenBefore] for a payment hash the trade, or another trade, saw before, [BondPayInvoiceChanged] for a quote of another invoice than the escrow the trail pins. It reads the device's records and the wallet's, and asks nothing of the coordinator or the swap service.
  Future<Result<EscrowContract?, BondPayRefusal>> escrowContractOf(
    TradeRecord record,
    P2pWalletQuote quote,
  ) async {
    if (step != InvoiceStep.escrow) return const Ok(null);
    final OpenTrade trade;
    switch (await _reader.open(record)) {
      case TradeOpened(trade: final opened):
        trade = opened;
      case TradeNotRestorable() || TradeTakeNeverSent():
        return const Err(BondPayNotAtBondStep());
      case TradeNotOpened(:final failure):
        return Err(BondPayRecordsUnreadable(failure));
    }
    if (!_isMakerEscrow(trade.terms)) return const Ok(null);
    final trail = trade.seen.status.trail;
    final hash = quote.invoice.paymentHash;
    if (trail.escrowHash != hash) return const Err(BondPayInvoiceChanged());
    return switch (await _contractOf(
      record,
      take: trail.take,
      paymentHash: hash,
      escrow: quote.total,
      earlierEscrows: trail.earlierEscrows,
    )) {
      Ok(:final value) => Ok(value),
      Err(:final failure) => Err(failure),
    };
  }

  /// Pays the [step] of [record] within [accepted], the quote the user confirmed.
  ///
  /// The order is read again first, with the trade's robot through its places in [RobotRequestLimiter], and kept as every read is; the payment goes on only when the status now stored is [step]'s and `walletPaymentFor` offers the invoice of [accepted] (same text and payment hash): a status that moved on, an invoice replaced or too little time left refuse it, with nothing paid.
  /// For a maker seller's escrow (#187), also only for [contract], the one its confirmation stated ([escrowContractOf]): [BondPayContractNotConfirmed] when none was given or the trail, read again from the records under the payment's lock, stands at another contract or pins another escrow; then, still under that lock, every payment recorded for the trade is read again with the wallet's records of each: the payment is refused for a payment hash seen before ([BondPayEscrowSeenBefore]), and asks a new confirmation ([BondPayConfirmAgain]) when the earlier escrows are more out than the confirmation showed ([EscrowContract.needsNewConfirmation]: more sats not back, or an escrow kept since); as much or less out, it pays. [contract] is not looked at for any other payment.
  /// Then the payment's start is written, under the contract of the status read ([WalletPaymentOffered.take], equal to the trail's for a maker seller's escrow, 0 otherwise); only once it is written is the wallet asked. The wallet's id of the payment is written as soon as the wallet gives one (paid, or a refusal that carries a payment: broadcast unknown, interrupted, or a payment that already exists).
  Future<Result<P2pWalletPayment, BondPayRefusal>> payBond(
    TradeRecord record, {
    required P2pWalletQuote accepted,
    EscrowContract? contract,
  }) => _inFlight.run(
    record,
    step,
    () => _payBond(record, accepted: accepted, contract: contract),
  );

  Future<Result<P2pWalletPayment, BondPayRefusal>> _payBond(
    TradeRecord record, {
    required P2pWalletQuote accepted,
    required EscrowContract? contract,
  }) async {
    final OpenTrade trade;
    switch (await _reader.open(record)) {
      case TradeOpened(trade: final opened):
        trade = opened;
      case TradeNotRestorable() || TradeTakeNeverSent():
        return const Err(BondPayNotAtBondStep());
      case TradeNotOpened(:final failure):
        return Err(BondPayRecordsUnreadable(failure));
    }
    // One action of an order at a time in the process: its take, its payout and this payment (`TradeTakeLocks`, shared with the take and the payout); a second payment of the bond waits, reads the order again and finds the first.
    return _locks.run(record.network, trade.coordinator, record.orderId, () async {
      final requests = _limiter.open(trade.robot.identity.sessionKey);
      TradeStep advanced;
      try {
        // Its read is this action's only request to the coordinator: the watch sends no read while it runs, and a read superseded (one of the watch's, which left before, answered after it left) is read once more (#141).
        final read = await _reader.duringAction(record, () async {
          var current = trade;
          TradeStep? last;
          for (
            var reads = 0;
            reads < 2 && (last?.superseded ?? true);
            reads++
          ) {
            final times = _reader.request();
            final read = await _reader.readOrder(
              requests,
              record,
              current.robot,
              current.coordinator,
              times: times,
            );
            final answer = switch (read) {
              Ok(:final value) => TradeAnswer.ofRead(value),
              Err() => null,
            };
            if (answer == null) {
              return Err<TradeStep, BondPayRefusal>(
                BondPayTradeUnavailable(switch (read) {
                  Err(:final failure) => failure,
                  Ok(value: Err(:final failure)) => failure,
                  // An order this robot read, which every read gives an answer for: never here.
                  Ok(value: Ok()) => const P2pStorageFailure(),
                }),
              );
            }
            last = await _reader.advance(
              current,
              answer,
              at: _reader.now(),
              request: times,
            );
            current = last.trade;
          }
          return Ok<TradeStep, BondPayRefusal>(
            last ?? (throw StateError('no read')),
          );
        });
        switch (read) {
          case Err(:final failure):
            return Err(failure);
          case Ok(:final value):
            advanced = value;
        }
      } finally {
        requests.close();
      }
      if (advanced.superseded) return const Err(BondPayReadSuperseded());
      final status = advanced.trade.seen.status;
      if (!advanced.stored || !_atStep(status)) {
        return const Err(BondPayNotAtBondStep());
      }
      final WalletPaymentOffered offered;
      switch (_offered(advanced.trade.terms, status)) {
        case Ok(:final value):
          offered = value;
        case Err(:final failure):
          return Err(failure);
      }
      final invoice = offered.walletInvoice;
      if (invoice.paymentHash != accepted.invoice.paymentHash ||
          invoice.bolt11 != accepted.invoice.bolt11) {
        return const Err(BondPayInvoiceChanged());
      }
      if (_isMakerEscrow(advanced.trade.terms)) {
        switch (await _stillThisContract(record, offered, accepted, contract)) {
          case Ok():
            break;
          case Err(:final failure):
            return Err(failure);
        }
      }
      switch (await _payments.recordStart(
        record,
        step,
        paymentHash: invoice.paymentHash,
        at: _reader.now(),
        take: offered.take,
      )) {
        case Ok(value: true):
          // What this escrow takes out of the wallet, the quote confirmed's total (the invoice, the swap service's fee and the network fee), for the confirmation of a next contract (#187).
          if (_isMakerEscrow(advanced.trade.terms)) {
            _amounts.keep(invoice.paymentHash, accepted.total);
          }
        case Ok(value: false) || Err():
          return const Err(BondPayNotRecorded());
      }
      final paid = await _wallet.payInvoice(invoice, accepted: accepted);
      final payment = switch (paid) {
        Ok(:final value) => value,
        Err(failure: P2pWalletBroadcastUnknown(:final payment)) ||
        Err(failure: P2pWalletPaymentInterrupted(:final payment)) => payment,
        Err(failure: P2pWalletPaymentExists(:final payment?)) => payment,
        Err() => null,
      };
      if (payment != null) {
        // A failed write here loses nothing: the start is recorded, and [followBond] finds the payment by its hash and writes its id then.
        final _ = await _payments.recordWalletPayment(
          record,
          step,
          paymentHash: payment.paymentHash,
          walletPaymentId: payment.id,
          take: offered.take,
        );
      }
      return switch (paid) {
        Ok(:final value) => Ok(value),
        Err(:final failure) => Err(BondPayWalletRefused(failure)),
      };
    });
  }

  /// Where the payment of [record]'s bond stands: none when none was recorded from this device or the wallet has none for its invoice, then the wallet's progress of it at once and at each change it records.
  ///
  /// For a maker seller's escrow (#187), the payment of the contract the trail stands at when the follow starts (`trade_payments.take`): an escrow of an earlier contract is [followEscrows]'.
  Stream<BondPaymentWatch> followBond(TradeRecord record) async* {
    var take = 0;
    if (step == InvoiceStep.escrow && record.origin == TradeOrigin.madeHere) {
      switch (await _reader.open(record)) {
        case TradeOpened(:final trade):
          take = trade.seen.status.trail.take;
        case TradeNotOpened(:final failure):
          yield BondPaymentUnreadable(failure);
          return;
        case TradeNotRestorable() || TradeTakeNeverSent():
          yield const BondPaymentUnreadable(P2pStorageFailure());
          return;
      }
    }
    final recorded = await _payments.paymentOf(record, step, take: take);
    switch (recorded) {
      case Err(:final failure):
        yield BondPaymentUnreadable(failure);
      case Ok(value: null):
        yield const BondPaymentNone();
      case Ok(value: final payment?):
        yield* _follow(record, payment);
    }
  }

  /// Where every escrow this wallet was asked to pay for [record] stands, contract by contract (#187): each recorded payment of step `escrow`, whatever its contract, followed as [followBond] follows the current one, the list given again at each change of any of them; whether or not the trade is still open, so that an escrow paid for a contract the trail moved on from, or for a trade that ended, is still said. Nothing for the bond's instance.
  Stream<EscrowPaymentsWatch> followEscrows(TradeRecord record) {
    final follows = <StreamSubscription<BondPaymentWatch>>[];
    var cancelled = false;
    late final StreamController<EscrowPaymentsWatch> out;
    Future<void> start() async {
      if (step != InvoiceStep.escrow) {
        out.add(EscrowPaymentsFollowed(const []));
        await out.close();
        return;
      }
      final List<TradePaymentRecord> escrows;
      switch (await _payments.paymentsOfTrade(record)) {
        case Err(:final failure):
          if (!cancelled) out.add(EscrowPaymentsUnreadable(failure));
          await out.close();
          return;
        case Ok(:final value):
          escrows = [
            for (final payment in value)
              if (payment.step == InvoiceStep.escrow) payment,
          ];
      }
      if (cancelled) return;
      if (escrows.isEmpty) {
        out.add(EscrowPaymentsFollowed(const []));
        await out.close();
        return;
      }
      final latest = <int, BondPaymentWatch>{};
      var open = escrows.length;
      void give() {
        if (cancelled || latest.length < escrows.length) return;
        out.add(
          EscrowPaymentsFollowed([
            for (final payment in escrows)
              EscrowPaymentOfContract(
                payment.take,
                latest[payment.take] ?? const BondPaymentNone(),
              ),
          ]),
        );
      }

      for (final payment in escrows) {
        follows.add(
          _follow(record, payment).listen(
            (watch) {
              latest[payment.take] = watch;
              give();
            },
            onDone: () {
              open -= 1;
              if (open == 0 && !cancelled) unawaited(out.close());
            },
          ),
        );
      }
    }

    out = StreamController<EscrowPaymentsWatch>(
      onListen: () => unawaited(start()),
      // Not awaited: a follow waiting for the wallet's next change ends only at that change (an `async*` body stops at its next `yield`), as the panel's own follow is left (`BondPaymentCubit`).
      onCancel: () {
        cancelled = true;
        for (final follow in follows) {
          unawaited(follow.cancel());
        }
      },
    );
    return out.stream;
  }

  /// The wallet's progress of [payment], recorded for [record]'s [step]: none when the wallet has none for its invoice, then at once and at each change the wallet records; its wallet id written when the wallet's differs (an id the app was killed before writing).
  Stream<BondPaymentWatch> _follow(
    TradeRecord record,
    TradePaymentRecord payment,
  ) async* {
    final hash = payment.paymentHash;
    final id = payment.walletPaymentId;
    final P2pWalletPaymentFound found;
    switch (await _wallet.findPayment(hash)) {
      case Err(:final failure):
        yield BondPaymentUnreadable(failure);
        return;
      case Ok(value: null):
        yield const BondPaymentNone();
        return;
      case Ok(value: final value?):
        found = value;
    }
    if (found.payment.id != id) {
      final _ = await _payments.recordWalletPayment(
        record,
        step,
        paymentHash: hash,
        walletPaymentId: found.payment.id,
        take: payment.take,
      );
    }
    yield BondPaymentFollowed(found.payment, found.progress);
    await for (final progress in _wallet.watchPayment(found.payment)) {
      switch (progress) {
        case Ok(:final value):
          yield BondPaymentFollowed(found.payment, value);
        case Err(:final failure):
          yield BondPaymentUnreadable(failure);
          return;
      }
    }
  }

  /// Whether [status] is the step of [step]: the bond's pre-take or, for an order made here, the maker bond at 0 (#180), or the statuses that await the seller's escrow (`walletPaymentFor` then offers only an escrow invoice, which a buyer's status never holds). Which of them the trade's own terms may be paid at, [_offered] says.
  bool _atStep(TradeStatus status) => switch (step) {
    InvoiceStep.bond =>
      status is WaitingForTakerBond || status is WaitingForMakerBond,
    InvoiceStep.escrow =>
      status is WaitingForBoth || status is WaitingForEscrow,
  };

  Result<WalletPaymentOffered, BondPayRefusal> _offered(
    TradeTerms terms,
    TradeStatus status,
  ) {
    final Sats accepted;
    if (terms is TradeTerms<TakenSide>) {
      // A taker is never at a maker's step: its terms are paid at its own steps only.
      if (status is WaitingForMakerBond) {
        return const Err(BondPayNotAtBondStep());
      }
      accepted = switch (step) {
        InvoiceStep.bond => terms.bondCeiling,
        InvoiceStep.escrow => terms.escrowCeiling,
      };
    } else {
      switch (step) {
        // An order made here: its maker bond at 0 only (#180), within `MakerTerms.bondCeiling` (`TradeTerms.bondCeiling` of a maker's side), the bond at the creation's price with the state machine's tolerance; the owner's payment rule then compares the quote with the wallet's own price ([rateOfBond]).
        case InvoiceStep.bond:
          if (status is! WaitingForMakerBond) {
            return const Err(BondPayNotAtBondStep());
          }
          accepted = terms.bondCeiling;
        // A maker seller's escrow at 6 and 7 (#187): no ceiling, the owner's rule of 2026-11-17 having replaced the factor of the creation's price (`makerEscrowFactor`, removed): the invoice the state machine checked against the contract's exact agreements (`EscrowAmountMismatch`, `MakerFeeAboveAnnounced`, the invoice's own checks), any warning of which forbids the wallet (`walletPaymentFor`); the comparison with the wallet's own price informs and warns ([rateOfBond]), never stops. The escrows of the order's other contracts are the caller's to check ([_contractOf]). A maker buyer locks no escrow.
        case InvoiceStep.escrow:
          if (terms.role != TradeRole.seller ||
              (status is! WaitingForBoth && status is! WaitingForEscrow)) {
            return const Err(BondPayNotAtBondStep());
          }
          final invoice = status.invoice;
          accepted = invoice is CheckedInvoice ? invoice.amount : Sats.zero;
      }
    }
    return switch (walletPaymentFor(
      accepted: accepted,
      status: status,
      step: step,
      now: _reader.now(),
    )) {
      final WalletPaymentOffered offered => Ok(offered),
      WalletPaymentRefused(:final reason) => Err(BondPayNotOffered(reason)),
    };
  }

  /// Whether [terms] are a maker seller's and this instance pays the escrow: the payment of #187.
  bool _isMakerEscrow(TradeTerms terms) =>
      step == InvoiceStep.escrow &&
      terms.side is MadeSide &&
      terms.role == TradeRole.seller;

  /// The contract of a maker seller's escrow of [paymentHash], [escrow] being what it takes out of the wallet (the quote's total; the invoice's amount where no quote was asked yet, `checkBond`), at contract [take], with the escrows of the order's other contracts this wallet was asked to pay (#187, design note § 6 row 13, the owner's decision of 2026-11-19): read from every payment recorded for the trade, whatever its contract, the maker bond's left aside, and the wallet's records of each ([EarlierEscrow.of]), their sats from [EscrowAmounts] when this run paid them.
  ///
  /// Refused only with [BondPayEscrowSeenBefore] when [paymentHash] is one of [earlierEscrows] (the trail's), the hash of another payment recorded for the trade (another contract's escrow, the bond), or of a payment recorded for another trade (which the database would refuse at `recordStart`, `trade_payments_hash_once`); with [BondPayRecordsUnreadable] when the records cannot be read. Earlier escrows not back, or kept, are never a refusal.
  Future<Result<EscrowContract, BondPayRefusal>> _contractOf(
    TradeRecord record, {
    required int take,
    required String paymentHash,
    required Sats escrow,
    required List<String> earlierEscrows,
  }) async {
    if (earlierEscrows.contains(paymentHash)) {
      return const Err(BondPayEscrowSeenBefore());
    }
    final List<TradePaymentRecord> payments;
    switch (await _payments.paymentsOfTrade(record)) {
      case Ok(:final value):
        payments = value;
      case Err(:final failure):
        return Err(BondPayRecordsUnreadable(failure));
    }
    final earlier = <EarlierEscrow>[];
    var own = false;
    for (final payment in payments) {
      // The attempts of this very escrow: a new attempt of the same invoice, which the wallet pays again only while every earlier order of it is provably unspent.
      if (payment.step == InvoiceStep.escrow && payment.take == take) {
        own = own || payment.paymentHash == paymentHash;
        continue;
      }
      if (payment.paymentHash == paymentHash) {
        return const Err(BondPayEscrowSeenBefore());
      }
      if (payment.step != InvoiceStep.escrow) continue;
      final found = await _wallet.findPayment(payment.paymentHash);
      // A wallet id never written (the app killed between the wallet's answer and its record), or written for an earlier attempt: written now, as the follow does.
      if (found case Ok(
        value: final known?,
      ) when known.payment.id != payment.walletPaymentId) {
        final _ = await _payments.recordWalletPayment(
          record,
          InvoiceStep.escrow,
          paymentHash: payment.paymentHash,
          walletPaymentId: known.payment.id,
          take: payment.take,
        );
      }
      earlier.add(
        EarlierEscrow.of(
          payment,
          found,
          sats: _amounts.of(payment.paymentHash),
        ),
      );
    }
    // An invoice recorded for another trade (security review of #187, R4): said as one presented before, rather than as records that could not be written.
    if (!own) {
      switch (await _payments.holdsPaymentHash(paymentHash)) {
        case Ok(value: true):
          return const Err(BondPayEscrowSeenBefore());
        case Ok(value: false):
          break;
        case Err(:final failure):
          return Err(BondPayRecordsUnreadable(failure));
      }
    }
    return Ok(EscrowContract(take: take, escrow: escrow, earlier: earlier));
  }

  /// Under the payment's lock, after the read just before a maker seller's escrow is paid (#187): the contract [confirmed] by the user is the one of the status read ([offered]) and of the trail read again from the records, which pins this very escrow; the payment hash was not seen before; and the earlier escrows, read again now ([_contractOf]), are not more out than [confirmed] showed, else [BondPayConfirmAgain] with what they are now (the owner's decision of 2026-11-19: a confirmation to make again, not a lock). `recordStart` takes a new attempt of an earlier contract's escrow as an update, which the database's contract rule does not see (#176): this is where a payment's contract is compared with the trail before any attempt.
  Future<Result<EscrowContract, BondPayRefusal>> _stillThisContract(
    TradeRecord record,
    WalletPaymentOffered offered,
    P2pWalletQuote accepted,
    EscrowContract? confirmed,
  ) async {
    if (confirmed == null || confirmed.take != offered.take) {
      return const Err(BondPayContractNotConfirmed());
    }
    final TradeTrail trail;
    switch (await _reader.open(record)) {
      case TradeOpened(:final trade):
        trail = trade.seen.status.trail;
      case TradeNotRestorable() || TradeTakeNeverSent():
        return const Err(BondPayNotAtBondStep());
      case TradeNotOpened(:final failure):
        return Err(BondPayRecordsUnreadable(failure));
    }
    final hash = offered.walletInvoice.paymentHash;
    if (trail.take != offered.take || trail.escrowHash != hash) {
      return const Err(BondPayContractNotConfirmed());
    }
    final EscrowContract now;
    switch (await _contractOf(
      record,
      take: offered.take,
      paymentHash: hash,
      escrow: accepted.total,
      earlierEscrows: trail.earlierEscrows,
    )) {
      case Ok(:final value):
        now = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (confirmed.needsNewConfirmation(now)) {
      return Err(BondPayConfirmAgain(now));
    }
    return Ok(now);
  }
}
