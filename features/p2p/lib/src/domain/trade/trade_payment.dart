import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import 'trade_status.dart';

/// A payment of a trade's invoice this device asked the wallet for (#100): the invoice's payment hash, when the last attempt started, and the wallet's local id of the swap that pays it, once the wallet gave one.
///
/// It holds no secret: the payment hash is part of the invoice, which the coordinator shows the robot; since schema 9 (#233), the total the user confirmed for it.
@immutable
final class TradePaymentRecord {
  final InvoiceStep step;

  /// The payment hash of the invoice paid, 64 lowercase hexadecimal characters.
  final String paymentHash;

  /// When the last attempt was about to call the wallet.
  final DateTime startedAt;

  /// The wallet's local id of the swap that pays the invoice, `null` until the wallet gave one (an attempt killed before, or one the wallet refused with nothing sent).
  final String? walletPaymentId;

  /// The contract of the invoice (schema 8): 0 for a bond and for every payment of a taker.
  final int take;

  /// What the payment takes out of the wallet, the total of the quote the user confirmed (the invoice, the swap service's fee and the network fee), written with its start, before the wallet was asked (schema 9, #233); `null` for a payment recorded before schema 9, whose amount was never kept: unknown, never zero.
  final Sats? confirmedSats;

  const TradePaymentRecord({
    required this.step,
    required this.paymentHash,
    required this.startedAt,
    this.walletPaymentId,
    this.take = 0,
    this.confirmedSats,
  });

  @override
  bool operator ==(Object other) =>
      other is TradePaymentRecord &&
      other.step == step &&
      other.paymentHash == paymentHash &&
      other.startedAt == startedAt &&
      other.walletPaymentId == walletPaymentId &&
      other.take == take &&
      other.confirmedSats == confirmedSats;

  @override
  int get hashCode => Object.hash(
    step,
    paymentHash,
    startedAt,
    walletPaymentId,
    take,
    confirmedSats,
  );

  /// The step only: no hash and no id.
  @override
  String toString() => 'TradePaymentRecord(${step.name})';
}
