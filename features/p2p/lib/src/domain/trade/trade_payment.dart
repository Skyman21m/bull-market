import 'package:meta/meta.dart';

import 'checked_invoice.dart';

/// A payment of a trade's invoice this device asked the wallet for (#100): the invoice's payment hash, when the last attempt started, and the wallet's local id of the swap that pays it, once the wallet gave one.
///
/// It holds no secret and no amount: the payment hash is part of the invoice, which the coordinator shows the robot.
@immutable
final class TradePaymentRecord {
  final InvoiceStep step;

  /// The payment hash of the invoice paid, 64 lowercase hexadecimal characters.
  final String paymentHash;

  /// When the last attempt was about to call the wallet.
  final DateTime startedAt;

  /// The wallet's local id of the swap that pays the invoice, `null` until the wallet gave one (an attempt killed before, or one the wallet refused with nothing sent).
  final String? walletPaymentId;

  const TradePaymentRecord({
    required this.step,
    required this.paymentHash,
    required this.startedAt,
    this.walletPaymentId,
  });

  @override
  bool operator ==(Object other) =>
      other is TradePaymentRecord &&
      other.step == step &&
      other.paymentHash == paymentHash &&
      other.startedAt == startedAt &&
      other.walletPaymentId == walletPaymentId;

  @override
  int get hashCode =>
      Object.hash(step, paymentHash, startedAt, walletPaymentId);

  /// The step only: no hash and no id.
  @override
  String toString() => 'TradePaymentRecord(${step.name})';
}
