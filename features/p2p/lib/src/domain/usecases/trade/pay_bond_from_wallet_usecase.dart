import 'dart:async';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../../../public/p2p_wallet_port.dart';
import '../../p2p_failure.dart';
import '../../repositories/trade_payment_repository.dart';
import '../../robot_request_limiter.dart';
import '../../trade/bond_payment.dart';
import '../../trade/trade_answer.dart';
import '../../trade/trade_status.dart';
import '../../trade/trade_terms.dart';
import '../../trade/trade_watch.dart';
import '../../trade/wallet_payment.dart';
import '../../trade/wallet_rate_check.dart';
import '../../trade_record.dart';
import 'bond_payments_in_flight.dart';
import 'trade_reader.dart';
import 'trade_take_locks.dart';

/// Pays a trade's bond (#100, W4), or a seller's escrow (#97), from the wallet's Instant Payments wallet, inside the trade screen: the only caller of [P2pWalletPort.payInvoice] (`wallet_port_architecture_test.dart`).
///
/// One instance per [step], the same code for both: the bond is paid from a stored `WaitingForTakerBond` within [TradeTerms.bondCeiling], or for an order made here from a stored `WaitingForMakerBond` within the same getter, which is then `MakerTerms.bondCeiling` (#180); the escrow from a stored `WaitingForBoth` or `WaitingForEscrow` within [TradeTerms.escrowCeiling], a taker's only (a maker seller's escrow is #187's, refused here whatever its status); the methods keep the bond's names, the step it was written for first.
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

  /// The invoice this instance pays: the taker's bond, or the seller's escrow.
  final InvoiceStep step;

  const PayBondFromWalletUsecase(
    this._reader,
    this._limiter,
    this._payments,
    this._wallet,
    this._locks,
    this._inFlight, {
    this.step = InvoiceStep.bond,
  });

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
    return _offered(terms, seen.status);
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

  /// For an order made here, how the bond of [quote] (the swap service's quote [quoteBond] gave) compares with the bond the order implies at the wallet's own price of a bitcoin, read now through the wallet's port (the owner's payment rule of 2026-11-17, design note `docs/design/phase-3-making-an-order.md` § 3.3); `null` for a take, and for the escrow's step, whose rules are their own (#187).
  ///
  /// Asked once the quote is given, before the confirmation is shown: the price is the one of the moment of paying. The amount compared is the quote's invoice's, the one the wallet pays. It refuses nothing: a bond beyond the owner's threshold is shown in red, and [payBond] still pays what the user confirms. The wallet's price is asked only for a maker's bond, never at a take.
  Future<Result<WalletRateCheck?, BondPayRefusal>> rateOfBond(
    TradeRecord record,
    P2pWalletQuote quote,
  ) async {
    if (step != InvoiceStep.bond) return const Ok(null);
    final TradeTerms terms;
    switch (await _reader.open(record)) {
      case TradeOpened(:final trade):
        terms = trade.terms;
      case TradeNotRestorable() || TradeTakeNeverSent():
        return const Err(BondPayNotAtBondStep());
      case TradeNotOpened(:final failure):
        return Err(BondPayRecordsUnreadable(failure));
    }
    switch (terms.side) {
      case TakenSide():
        return const Ok(null);
      case MadeSide(:final maker):
        final rate = await _wallet.bitcoinRate(maker.network, maker.currency);
        return Ok(
          WalletRateCheck.ofMakerBond(maker, asked: quote.amount, wallet: rate),
        );
    }
  }

  /// Pays the [step] of [record] within [accepted], the quote the user confirmed.
  ///
  /// The order is read again first, with the trade's robot through its places in [RobotRequestLimiter], and kept as every read is; the payment goes on only when the status now stored is [step]'s and `walletPaymentFor` offers the invoice of [accepted] (same text and payment hash): a status that moved on, an invoice replaced or too little time left refuse it, with nothing paid.
  /// Then the payment's start is written; only once it is written is the wallet asked. The wallet's id of the payment is written as soon as the wallet gives one (paid, or a refusal that carries a payment: broadcast unknown, interrupted, or a payment that already exists).
  Future<Result<P2pWalletPayment, BondPayRefusal>> payBond(
    TradeRecord record, {
    required P2pWalletQuote accepted,
  }) => _inFlight.run(record, step, () => _payBond(record, accepted: accepted));

  Future<Result<P2pWalletPayment, BondPayRefusal>> _payBond(
    TradeRecord record, {
    required P2pWalletQuote accepted,
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
      switch (await _payments.recordStart(
        record,
        step,
        paymentHash: invoice.paymentHash,
        at: _reader.now(),
      )) {
        case Ok(value: true):
          break;
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
        );
      }
      return switch (paid) {
        Ok(:final value) => Ok(value),
        Err(:final failure) => Err(BondPayWalletRefused(failure)),
      };
    });
  }

  /// Where the payment of [record]'s bond stands: none when none was recorded from this device or the wallet has none for its invoice, then the wallet's progress of it at once and at each change it records.
  Stream<BondPaymentWatch> followBond(TradeRecord record) async* {
    final recorded = await _payments.paymentOf(record, step);
    final String hash;
    final String? id;
    switch (recorded) {
      case Err(:final failure):
        yield BondPaymentUnreadable(failure);
        return;
      case Ok(value: null):
        yield const BondPaymentNone();
        return;
      case Ok(value: final payment?):
        hash = payment.paymentHash;
        id = payment.walletPaymentId;
    }
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
      // An order made here: its maker bond at 0 only (#180), within `MakerTerms.bondCeiling` (`TradeTerms.bondCeiling` of a maker's side), the bond at the creation's price with the state machine's tolerance; the owner's payment rule then compares the quote with the wallet's own price ([rateOfBond]). A maker seller's escrow at 6 and 7 is paid under its own rules from #187: until then nothing is offered for it, whatever its status.
      if (step != InvoiceStep.bond || status is! WaitingForMakerBond) {
        return const Err(BondPayNotAtBondStep());
      }
      accepted = terms.bondCeiling;
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
}
