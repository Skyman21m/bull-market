import 'dart:async';

import '../../robot_binding.dart';
import '../../trade_record.dart';

/// The payments of a bond this process is making now (#100), one for the feature: a trade screen opened again while a payment runs (its earlier screen closed, the payment going on) says « Sending the payment… » instead of offering to pay again, and follows the payment once it ends.
///
/// In memory only: a payment left by an earlier run of the app is the wallet's records' to tell (`P2pWalletPort.findPayment`).
final class BondPaymentsInFlight {
  final Map<RobotSlot, Future<void>> _running = {};

  /// When the payment of [record]'s bond running now ends, `null` when none runs.
  Future<void>? running(TradeRecord record) => _running[record.robot];

  /// Runs [payment] of [record]'s bond, known as running until it ends, whatever it gave.
  Future<T> run<T>(TradeRecord record, Future<T> Function() payment) async {
    final done = Completer<void>();
    _running[record.robot] = done.future;
    try {
      return await payment();
    } finally {
      if (identical(_running[record.robot], done.future)) {
        _running.remove(record.robot);
      }
      done.complete();
    }
  }
}
