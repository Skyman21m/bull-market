import '../../robot_binding.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';

/// The order in which the requests of the trades left, in this process: what keeps a read overtaken in flight from replacing a newer one (#141).
///
/// The request limiter lets two requests of a robot be in flight at once, so a read sent before another (the watch's, before an action and the read after it) can be answered after it; the trail orders reads by when they were answered, and the state machine allows edges back (10 → 9), so such a read could otherwise be stored and shown, or, along no edge, recorded as a breach of trust.
/// [TradeReader] dates every request that gives a status when it leaves ([leaving]), and keeps a status only when no status of a request that left later is stored already ([newerThan]); the times are this device's own, and never go back within the process, whatever the device's clock does.
/// It holds no robot and no key: for each trade, the time and the status of the newest stored answer, and its record. It is in memory only: a request in flight lives in this process too, and every request of this process left after any status a previous run stored.
/// One for the feature (a lazy singleton of the composition), shared by every [TradeReader].
final class TradeReadOrder {
  DateTime? _lastLeft;
  final Map<RobotSlot, _Newest> _newest = {};

  /// When a request leaves at [now]: [now], or a microsecond after the last request that left when the device's clock did not move on (or moved back), so that a request that leaves later is always dated later.
  DateTime leaving(DateTime now) {
    final last = _lastLeft;
    final left = last != null && !now.isAfter(last)
        ? last.add(const Duration(microseconds: 1))
        : now;
    _lastLeft = left;
    return left;
  }

  /// The newest stored status of [robot]'s trade, with its record, when the request it comes from left after [sentAt]: what a status of a request that left at [sentAt] gives way to; `null` when there is none.
  (TradeRecord, TradeSeen)? newerThan(RobotSlot robot, DateTime sentAt) {
    final newest = _newest[robot];
    if (newest == null || !sentAt.isBefore(newest.sentAt)) return null;
    return (newest.record, newest.seen);
  }

  /// [seen] was stored for [record]'s trade, from a request that left at [sentAt]: kept unless a status of a request that left later is kept already.
  void stored(TradeRecord record, TradeSeen seen, DateTime sentAt) {
    final newest = _newest[record.robot];
    if (newest != null && sentAt.isBefore(newest.sentAt)) return;
    _newest[record.robot] = _Newest(sentAt, record, seen);
  }
}

final class _Newest {
  final DateTime sentAt;
  final TradeRecord record;
  final TradeSeen seen;

  const _Newest(this.sentAt, this.record, this.seen);
}
