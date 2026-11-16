import 'dart:async';

import '../../robot_binding.dart';
import '../../trade/trade_status.dart';
import '../../trade_record.dart';

/// The payments of a bond or an escrow this process is making now (#100, #97), one for the feature: a trade screen opened again while a payment runs (its earlier screen closed, the payment going on) says « Sending the payment… » instead of offering to pay again, and follows the payment once it ends.
///
/// Each trade's step is known apart: a payment of the bond never shows as one of the escrow, nor the reverse.
/// In memory only: a payment left by an earlier run of the app is the wallet's records' to tell (`P2pWalletPort.findPayment`).
final class BondPaymentsInFlight {
  final Map<(RobotSlot, InvoiceStep), Future<void>> _running = {};

  /// When the payment of [step] of [record] running now ends, `null` when none runs.
  Future<void>? running(TradeRecord record, InvoiceStep step) =>
      _running[(record.robot, step)];

  /// Runs [payment] of [step] of [record], known as running until it ends, whatever it gave.
  Future<T> run<T>(
    TradeRecord record,
    InvoiceStep step,
    Future<T> Function() payment,
  ) async {
    final key = (record.robot, step);
    final done = Completer<void>();
    _running[key] = done.future;
    try {
      return await payment();
    } finally {
      if (identical(_running[key], done.future)) _running.remove(key);
      done.complete();
    }
  }
}
