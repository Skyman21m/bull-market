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
import '../../trade_record.dart';
import 'trade_reader.dart';
import 'trade_take_locks.dart';

/// Pays a trade's bond from the wallet's Instant Payments wallet, inside the trade screen (#100, W4): the only caller of [P2pWalletPort.payInvoice] (`wallet_port_architecture_test.dart`).
///
/// - [watchBalance]: what the Instant Payments wallet can spend, as the wallet reads it.
/// - [quoteBond]: on the user's tap of « Pay with this wallet » only, the swap service's quote for the invoice the status shown offers (`walletPaymentFor`, at most the bond the take's terms imply, [TradeTerms.bondCeiling]); nothing is created at the service.
/// - [payBond]: on the user's confirmation of that quote only, one action of the order at a time ([TradeTakeLocks], shared with the take and the payout). It reads the order again with the trade's robot, keeps what the read gives, and pays only when the status it now stores is the bond step and `walletPaymentFor` offers the very invoice quoted; the payment is recorded ([TradePaymentRepository.recordStart]) before the wallet is asked, and the wallet's id of it after.
/// - [followBond]: where the payment recorded for the trade stands, from the wallet's records ([P2pWalletPort.findPayment], then [P2pWalletPort.watchPayment]); it pays nothing.
///
/// Nothing here retries a payment or pays by itself: a poll, a reopen or a follow never reaches [payBond]. Every refusal of the wallet but [P2pWalletBroadcastUnknown] means nothing left the wallet.
final class PayBondFromWalletUsecase {
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final TradePaymentRepository _payments;
  final P2pWalletPort _wallet;
  final TradeTakeLocks _locks;

  const PayBondFromWalletUsecase(
    this._reader,
    this._limiter,
    this._payments,
    this._wallet,
    this._locks,
  );

  /// What the Instant Payments wallet on [network] can spend, at once and after each sync of it; a refusal ends the stream.
  Stream<Result<Sats, P2pWalletRefusal>> watchBalance(
    RobosatsNetwork network,
  ) => _wallet.instantBalance(network);

  /// Whether the wallet may be offered for the bond of [record] at [seen], without asking anything of the swap service: the invoice `walletPaymentFor` offers, or why not.
  Future<Result<WalletPaymentOffered, BondPayRefusal>> checkBond(
    TradeRecord record,
    TradeSeen seen,
  ) async {
    if (!seen.stored || seen.status is! WaitingForTakerBond) {
      return const Err(BondPayNotAtBondStep());
    }
    final TradeTerms terms;
    switch (await _reader.open(record)) {
      case TradeOpened(:final trade):
        terms = trade.terms;
      case TradeNotRestorable() || TradeTakeNeverSent():
        return const Err(BondPayNotAtBondStep());
      case TradeNotOpened(:final failure):
        return Err(BondPayTradeUnavailable(failure));
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

  /// Pays the bond of [record] within [accepted], the quote the user confirmed.
  ///
  /// The order is read again first, with the trade's robot through its places in [RobotRequestLimiter], and kept as every read is; the payment goes on only when the status now stored is the bond step and `walletPaymentFor` offers the invoice of [accepted] (same text and payment hash): a status that moved on, an invoice replaced or too little time left refuse it, with nothing paid.
  /// Then the payment's start is written; only once it is written is the wallet asked. The wallet's id of the payment is written as soon as the wallet gives one (paid, or a refusal that carries a payment: broadcast unknown, interrupted, or a payment that already exists).
  Future<Result<P2pWalletPayment, BondPayRefusal>> payBond(
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
        return Err(BondPayTradeUnavailable(failure));
    }
    // One action of an order at a time in the process: its take, its payout and this payment (`TradeTakeLocks`, shared with the take and the payout); a second payment of the bond waits, reads the order again and finds the first.
    return _locks.run(record.network, trade.coordinator, record.orderId, () async {
      final requests = _limiter.open(trade.robot.identity.sessionKey);
      final TradeStep step;
      try {
        final read = await _reader.readOrder(
          requests,
          record,
          trade.robot,
          trade.coordinator,
        );
        final answer = switch (read) {
          Ok(:final value) => TradeAnswer.ofRead(value),
          Err() => null,
        };
        if (answer == null) {
          return Err(
            BondPayTradeUnavailable(switch (read) {
              Err(:final failure) => failure,
              Ok(value: Err(:final failure)) => failure,
              // An order this robot read, which every read gives an answer for: never here.
              Ok(value: Ok()) => const P2pStorageFailure(),
            }),
          );
        }
        step = await _reader.advance(trade, answer, at: _reader.now());
      } finally {
        requests.close();
      }
      final status = step.trade.seen.status;
      if (!step.stored || status is! WaitingForTakerBond) {
        return const Err(BondPayNotAtBondStep());
      }
      final WalletPaymentOffered offered;
      switch (_offered(step.trade.terms, status)) {
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
        InvoiceStep.bond,
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
          InvoiceStep.bond,
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
    final recorded = await _payments.paymentOf(record, InvoiceStep.bond);
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
        InvoiceStep.bond,
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

  Result<WalletPaymentOffered, BondPayRefusal> _offered(
    TradeTerms terms,
    TradeStatus status,
  ) => switch (walletPaymentFor(
    accepted: terms.bondCeiling,
    status: status,
    step: InvoiceStep.bond,
    now: _reader.now(),
  )) {
    final WalletPaymentOffered offered => Ok(offered),
    WalletPaymentRefused(:final reason) => Err(BondPayNotOffered(reason)),
  };
}
