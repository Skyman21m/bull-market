import 'package:meta/meta.dart';
import 'package:p2p/p2p.dart';

/// The payments of invoices the wallet started, read from the wallet's records of its swap orders: nothing here creates, changes or refreshes an order.
abstract interface class WalletPaymentRepository {
  /// The note of every order this feature creates: a fixed text, which the wallet makes a label of the funding transaction once the order completes, and by which [find] and [watch] know this feature's orders. No order id, no hash.
  static const note = 'RoboSats';

  /// Whether the wallet's records hold any swap order that pays [invoice], in any state: an order of any kind and of any wallet whose destination is the invoice's text (in either case), or an order of this feature for an invoice with the same payment hash.
  ///
  /// [P2pWalletUnavailable] when the records cannot be read.
  @useResult
  Future<Result<bool, P2pWalletRefusal>> holdsPaymentOf(
    CheckedBolt11Invoice invoice,
  );

  /// The latest order of this feature that pays an invoice of [paymentHash], with its progress, or `null`.
  ///
  /// [P2pWalletUnavailable] when the records cannot be read.
  @useResult
  Future<Result<P2pWalletPaymentFound?, P2pWalletRefusal>> find(
    String paymentHash,
  );

  /// The progress of [payment], at once and after each change of its record; it ends with [P2pWalletUnavailable] when the record cannot be read or is not an order of this feature for that payment hash.
  Stream<Result<P2pWalletPaymentProgress, P2pWalletRefusal>> watch(
    P2pWalletPayment payment,
  );
}
