import 'dart:async';

import 'package:primitives/primitives.dart';

import '../../robot_binding.dart';
import '../../trade/trade_pause.dart';
import '../../trade_record.dart';

/// The pauses and unpauses this process is sending now (#184, after its functional review, R1), one for the feature, as `BondPaymentsInFlight` for the payments: a trade screen opened again while a pause of its order runs (its earlier screen closed, the pause going on) shows the button busy instead of offering a tap that would wait for the first and then read an order already moved, and says what the running pause gives once it ends.
///
/// In memory only: a request left by an earlier run of the app is the reads' to tell.
final class PausesInFlight {
  final Map<RobotSlot, PauseInFlight> _running = {};

  /// The pause of [record]'s order running now, `null` when none runs.
  PauseInFlight? running(TradeRecord record) => _running[record.robot];

  /// Runs [pause], what the user asked being [wanted], known as running for [record]'s order until it ends, whatever it gave.
  Future<Result<PauseOutcome, PauseRefusal>> run(
    TradeRecord record,
    PauseWanted wanted,
    Future<Result<PauseOutcome, PauseRefusal>> Function() pause,
  ) {
    final key = record.robot;
    final result = pause();
    final running = PauseInFlight._(wanted, result);
    _running[key] = running;
    void forget() {
      if (identical(_running[key], running)) _running.remove(key);
    }

    return result.whenComplete(forget);
  }
}

/// A pause running now: what the user asked, and what it will give.
final class PauseInFlight {
  final PauseWanted wanted;
  final Future<Result<PauseOutcome, PauseRefusal>> result;

  const PauseInFlight._(this.wanted, this.result);
}
