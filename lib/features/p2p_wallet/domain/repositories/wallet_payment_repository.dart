import 'package:meta/meta.dart';
import 'package:p2p/p2p.dart';

/// The payments of invoices the wallet started, read from the wallet's records of its swap orders: nothing here creates, changes or refreshes an order.
abstract interface class WalletPaymentRepository {
  /// The note of every order this feature creates: a fixed text, which the wallet makes the label of the funding transaction in its history once the order completes, and by which this repository knows this feature's orders. It says what the payment is (a RoboSats payment made from Bull Market's P2P tab) and is distinctive, so that a user does not type it by chance as the label of a send. No order id, no hash.
  static const note = 'RoboSats · Bull Market P2P';

  /// The earlier swap orders of the wallet's records that pay [invoice], when every one of them is provably unspent: their local ids (empty when there is none), so that the invoice may be paid (again).
  ///
  /// An order pays [invoice] when its destination is the invoice's text (in either case), whatever its kind and wallet, or when it is an order of this feature for an invoice with the same payment hash.
  /// [P2pWalletPaymentExists] when one of them is not provably unspent (signed, broadcast or after, a payin the service reports, or an open order of another feature), with where the latest such order stands; [P2pWalletUnavailable] when the records cannot be read (fail closed). An order whose invoice yields no payment hash is tied to the invoice by its text only.
  @useResult
  Future<Result<Set<String>, P2pWalletRefusal>> earlierAttemptsOf(
    CheckedBolt11Invoice invoice,
  );

  /// The latest order of this feature that pays an invoice of [paymentHash], with its progress, or `null`.
  ///
  /// It fails closed: [P2pWalletUnavailable] when the records cannot be read, never `null`. An order whose invoice yields no payment hash is not given.
  @useResult
  Future<Result<P2pWalletPaymentFound?, P2pWalletRefusal>> find(
    String paymentHash,
  );

  /// The progress of [payment], at once and after each change of its record; it ends with [P2pWalletUnavailable] when the record cannot be read or is not an order of this feature for that payment hash.
  Stream<Result<P2pWalletPaymentProgress, P2pWalletRefusal>> watch(
    P2pWalletPayment payment,
  );
}
