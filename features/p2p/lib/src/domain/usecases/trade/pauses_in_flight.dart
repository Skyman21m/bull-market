import 'dart:async';

import 'package:primitives/primitives.dart';

import '../../robot_binding.dart';
import '../../trade/trade_pause.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';

/// The pauses and unpauses this process is sending now (#184, after its functional review, R1), one for the feature, as `BondPaymentsInFlight` for the payments: a trade screen opened again while a pause of its order runs (its earlier screen closed, the pause going on) shows the button busy instead of offering a tap that would wait for the first and then read an order already moved, and says what the running pause gives once it ends.
///
/// It also keeps, per order, what stays uncertain after a pause or an unpause whose outcome was unknown ([PauseUncertainty], security review of #184, C1 and C2), for every screen of the order, until reads settle it.
/// In memory only: a request left by an earlier run of the app is the reads' to tell.
final class PausesInFlight {
  final Map<RobotSlot, PauseInFlight> _running = {};
  final Map<RobotSlot, PauseUncertainty> _uncertain = {};

  /// What stays uncertain for [record]'s order, `null` when nothing does.
  PauseUncertainty? uncertainty(TradeRecord record) => _uncertain[record.robot];

  /// A request of [record]'s order whose outcome is unknown left at [leftAt]; [seen], the status it gave, may already be a read sent after it.
  void unknown(TradeRecord record, DateTime leftAt, TradeSeen? seen) {
    final key = record.robot;
    final before = _uncertain[key];
    final now = before == null
        ? PauseUncertainty(leftAt)
        : before.after(leftAt);
    _uncertain[key] = now;
    if (seen != null) observe(record, seen);
  }

  /// [seen] was read for [record]'s order: what stays uncertain after it ([PauseUncertainty.observe]).
  PauseUncertainty? observe(TradeRecord record, TradeSeen seen) {
    final key = record.robot;
    final before = _uncertain[key];
    if (before == null) return null;
    final after = before.observe(seen);
    if (after == null) {
      _uncertain.remove(key);
    } else {
      _uncertain[key] = after;
    }
    return after;
  }

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
