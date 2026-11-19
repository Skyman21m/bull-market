import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../p2p_failure.dart';
import '../trade/trade_status.dart';
import '../trade/trade_payment.dart';
import '../trade_record.dart';

/// The payments of a trade's invoices asked of the wallet, kept so that a restart finds a payment again and nothing pays an invoice twice (#100, design note § 3.5).
///
/// One payment per trade, step and contract (the trail's `take`, schema 8: 0 for every payment of a taker and for a bond; one more for a maker seller's escrow of each later contract, #187). It is written before the wallet is asked to pay ([recordStart]) and completed once the wallet gives the payment's id ([recordWalletPayment]); it is never deleted, and its payment hash never changes: the database's triggers refuse anything else, and a payment is written only for an open trade whose trail is recorded.
/// Each method is one statement that commits on its own; never call it inside a database transaction.
/// It holds no secret: payment hashes, times and the wallet's local ids.
abstract interface class TradePaymentRepository {
  /// The payment of [trade]'s invoice of [step] in its contract [take], `null` when none was ever asked from this device.
  ///
  /// A database that cannot be read, or a row this code never writes, is a [P2pStorageFailure].
  @useResult
  Future<Result<TradePaymentRecord?, P2pFailure>> paymentOf(
    TradeRecord trade,
    InvoiceStep step, {
    int take = 0,
  });

  /// Every payment recorded for [trade], whatever its step and contract, ordered by contract then step (bond first): what a maker seller's escrow is checked against before this wallet pays it (#187: the escrows of the order's other contracts, and every payment hash the trade already holds), and what follows an escrow paid for a contract the trail has moved on from.
  ///
  /// A database that cannot be read, or a row this code never writes, is a [P2pStorageFailure].
  @useResult
  Future<Result<List<TradePaymentRecord>, P2pFailure>> paymentsOfTrade(
    TradeRecord trade,
  );

  /// Records, before the wallet is asked, that an attempt to pay the invoice of [paymentHash] for [trade]'s [step] starts at [at]: the payment when there was none, or a new attempt of the same invoice (its start moved to [at] unless already later, the id of the earlier attempt kept until the wallet gives a new one).
  ///
  /// `false`: nothing was written, since [trade]'s payment of [step] in contract [take] is of another invoice. A first attempt for a closed or never read trade, for a contract its trail is not at, or of a payment hash another payment of any trade, step or contract holds, is refused by the database ([P2pStorageFailure]); a new attempt of the same invoice is written whether the trade is still open or not, the caller paying only from a status it has just read and stored. Either way the wallet is not asked unless this is `true`.
  @useResult
  Future<Result<bool, P2pFailure>> recordStart(
    TradeRecord trade,
    InvoiceStep step, {
    required String paymentHash,
    required DateTime at,
    int take = 0,
  });

  /// Records [walletPaymentId], the wallet's local id of the swap that pays the invoice of [paymentHash] for [trade]'s [step] in contract [take]; `false` when no such payment is recorded.
  @useResult
  Future<Result<bool, P2pFailure>> recordWalletPayment(
    TradeRecord trade,
    InvoiceStep step, {
    required String paymentHash,
    required String walletPaymentId,
    int take = 0,
  });
}
