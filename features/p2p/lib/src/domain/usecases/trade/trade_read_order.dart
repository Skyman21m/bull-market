import 'package:meta/meta.dart';

import '../../robot_binding.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';

/// When a request that gives a status of a trade left ([TradeReadOrder.leaving]): this device's time, which a status may keep ([TradeSeen.requestedAt]), and its rank among the requests of this process, which orders it.
@immutable
final class RequestLeft {
  /// This device's time when the request left.
  final DateTime at;

  /// The requests of this process are ranked as they leave, from 1: a later one has a higher rank, whatever the device's clock does.
  final int rank;

  const RequestLeft._(this.at, this.rank);

  /// Whether this request left before [other].
  bool isBefore(RequestLeft other) => rank < other.rank;

  @override
  String toString() => 'RequestLeft(#$rank)';
}

/// The order in which the requests of the trades left, in this process: what keeps a read overtaken in flight from replacing a newer one (#141).
///
/// The request limiter lets two requests of a robot be in flight at once, so a read sent before another (the watch's, before an action and the read after it) can be answered after it; the trail orders reads by when they were answered, and the state machine allows edges back (10 → 9), so such a read could otherwise be stored and shown, or, along no edge, recorded as a breach of trust.
/// `TradeReader` ranks every request that gives a status when it leaves ([leaving]), and keeps a status only when no status of a request that left later is stored already ([newerThan]). The rank, not the device's clock, orders them: a clock that moves back cannot make a later request look older, nor leave a trade on an old status.
/// It holds no robot and no key: for each trade, the rank and the status of the newest stored answer, and its record. It is in memory only: a request in flight lives in this process too, and every request of this process left after any status a previous run stored.
/// One for the feature (a lazy singleton of the composition), shared by every `TradeReader`.
final class TradeReadOrder {
  int _left = 0;
  final Map<RobotSlot, _Newest> _newest = {};

  /// A request leaves now, at [now] on this device's clock: its rank is the next one.
  RequestLeft leaving(DateTime now) => RequestLeft._(now, ++_left);

  /// The newest stored status of [robot]'s trade, with its record, when the request it comes from left after [sent]: what a status of [sent] gives way to; `null` when there is none.
  (TradeRecord, TradeSeen)? newerThan(RobotSlot robot, RequestLeft sent) {
    final newest = _newest[robot];
    if (newest == null || !sent.isBefore(newest.sent)) return null;
    return (newest.record, newest.seen);
  }

  /// [seen] was stored for [record]'s trade, from [sent]: kept unless a status of a request that left later is kept already.
  void stored(TradeRecord record, TradeSeen seen, RequestLeft sent) {
    final newest = _newest[record.robot];
    if (newest != null && sent.isBefore(newest.sent)) return;
    _newest[record.robot] = _Newest(sent, record, seen);
  }
}

final class _Newest {
  final RequestLeft sent;
  final TradeRecord record;
  final TradeSeen seen;

  const _Newest(this.sent, this.record, this.seen);
}
