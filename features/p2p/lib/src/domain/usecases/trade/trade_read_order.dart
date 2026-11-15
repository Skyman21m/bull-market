import 'dart:async';

import '../../robot_binding.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';

/// The times of one request that gives a status of a trade: its rank when it really left and its rank when its answer arrived, among the events of this process ([TradeReadOrder]).
///
/// Made by `TradeReader.request`, filled by `TradeReader` itself, inside the closure handed to the request limiter: at each attempt (a busy answer is sent again, behind newer requests), so that the ranks are those of the attempt whose answer is kept.
final class RequestTimes {
  int? _left;
  int? _arrived;
  DateTime? _leftAt;
  bool _heldBack = false;

  RequestTimes._();

  /// This device's time when the request last left; `null` before it left.
  DateTime? get leftAt => _leftAt;

  /// Whether the answer of the request arrived (its ranks are both taken).
  bool get answered => _left != null && _arrived != null;

  /// Whether the request was not sent, because an action of its trade was running ([TradeReadOrder.actionRunning]): the watch's reads only.
  bool get heldBack => _heldBack;

  @override
  String toString() => 'RequestTimes(left: $_left, arrived: $_arrived)';
}

/// The order of what the requests of the trades did in this process: what keeps an answer from replacing a status it cannot be known to be newer than (#141).
///
/// The request limiter lets two requests of a robot be in flight at once, and the coordinator may serve them in either order, whatever order they left and their answers arrived in; the state machine allows edges back (10 → 9), and an answer read along no edge is recorded as a breach of trust. So:
/// - every request that gives a status is ranked when it really leaves and when its answer arrives ([send]), on one counter, so that the ranks of all requests compare;
/// - an answer replaces the stored status only if its request left after the stored status's answer arrived ([claim]): two requests whose flights overlap cannot be ordered by their times, so the later answer of such a pair is superseded, whichever left first; the claim is made at once, before anything is written, so that an answer that arrives while another is being written is judged against it;
/// - the watch sends no read while an action of the trade runs ([duringAction], [actionRunning]): actions of a trade run one at a time (`TradeTakeLocks`), and the requests of an action follow one another, so the only overlap left is a watch's read that left before the action began.
/// So every answer that is accepted left after the previous accepted one arrived: the accepted answers are in the order the coordinator served them, and a race can neither replace a newer status nor record a breach. What it costs: a status can be shown one read later than it could have been.
/// The ranks are this process's own, not the device's clock: a clock that moves back changes nothing here. It holds no robot and no key: for each trade, the rank of the newest accepted answer's arrival, and the status stored from it with its record; in memory only, since a request in flight lives in this process, and every request of a run leaves after what an earlier run stored.
/// One for the feature (a lazy singleton of the composition), shared by every `TradeReader`.
final class TradeReadOrder {
  int _rank = 0;
  final Map<RobotSlot, _Newest> _newest = {};
  final Map<RobotSlot, int> _actions = {};
  final Map<RobotSlot, List<Completer<void>>> _ended = {};

  /// The times of a new request, filled when it is sent through [send].
  RequestTimes request() => RequestTimes._();

  /// [call], the request itself, run now: ranked when it leaves, at [now] on this device's clock, and when its answer arrives, at once, before anything else runs.
  Future<T> send<T>(
    RequestTimes times,
    DateTime now,
    Future<T> Function() call,
  ) async {
    times
      .._left = ++_rank
      .._arrived = null
      .._leftAt = now;
    final answer = await call();
    times._arrived = ++_rank;
    return answer;
  }

  /// Whether the answer of [times] may replace the status stored for [robot]'s trade: `null` when it may, the place claimed for it at once; otherwise it is superseded, and the newest status stored, with its record (both `null` while none was stored in this process), is what the trade stands at.
  TradeSuperseded? claim(RobotSlot robot, RequestTimes times) {
    final left = times._left;
    final arrived = times._arrived;
    if (left == null || arrived == null) {
      throw StateError('a status from a request not sent through TradeReader');
    }
    final newest = _newest[robot];
    if (newest != null && left <= newest.arrived) {
      return TradeSuperseded._(newest.record, newest.seen);
    }
    if (newest == null) {
      _newest[robot] = _Newest(arrived);
    } else {
      newest.arrived = arrived;
    }
    return null;
  }

  /// [seen] was stored for [record]'s trade, from the answer claimed last.
  void stored(TradeRecord record, TradeSeen seen) {
    final newest = _newest[record.robot] ??= _Newest(0);
    newest
      ..seen = seen
      ..record = _furthest(newest.record, record);
  }

  /// [record] as a step of its trade left it: kept when it is further on (confirmed, then closed) than the one known, so that a superseded answer never hands back an older record.
  void noted(TradeRecord record) {
    final newest = _newest[record.robot];
    if (newest != null) newest.record = _furthest(newest.record, record);
  }

  /// [body], an action of [robot]'s trade: while it runs, the watch sends no read of the trade.
  Future<T> duringAction<T>(RobotSlot robot, Future<T> Function() body) async {
    _actions[robot] = (_actions[robot] ?? 0) + 1;
    try {
      return await body();
    } finally {
      final left = (_actions[robot] ?? 1) - 1;
      if (left > 0) {
        _actions[robot] = left;
      } else {
        _actions.remove(robot);
        for (final ended in _ended.remove(robot) ?? const <Completer<void>>[]) {
          ended.complete();
        }
      }
    }
  }

  /// [times]'s request was not sent: an action of its trade was running.
  void heldBack(RequestTimes times) => times._heldBack = true;

  /// Whether an action of [robot]'s trade runs.
  bool actionRunning(RobotSlot robot) => _actions.containsKey(robot);

  /// Completes once no action of [robot]'s trade runs.
  Future<void> actionEnded(RobotSlot robot) {
    if (!actionRunning(robot)) return Future.value();
    final ended = Completer<void>();
    (_ended[robot] ??= []).add(ended);
    return ended.future;
  }

  static TradeRecord? _furthest(TradeRecord? known, TradeRecord record) {
    if (known == null) return record;
    int stage(TradeRecord r) => r.closedAt != null
        ? 2
        : r.confirmedAt != null
        ? 1
        : 0;
    return stage(record) >= stage(known) ? record : known;
  }
}

/// An answer superseded ([TradeReadOrder.claim]): the newest status stored for the trade in this process, with its record; `null` while none was stored.
final class TradeSuperseded {
  final TradeRecord? record;
  final TradeSeen? seen;

  const TradeSuperseded._(this.record, this.seen);
}

final class _Newest {
  int arrived;
  TradeRecord? record;
  TradeSeen? seen;

  _Newest(this.arrived);
}
