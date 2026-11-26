import 'package:meta/meta.dart';

import 'garage_key_fingerprint.dart';
import 'trade/trade_edges.dart';
import 'trade_record.dart';

/// How a finished order ended, as the history of the Garage says it (#253, design note `docs/design/phase-3-order-history.md` § 3): an addition of Bull Market, the reference having no history.
enum OrderEnd {
  /// 14: the trade went through.
  traded,

  /// 5: the order expired, at whatever step.
  expired,

  /// Error 1043: the order was cancelled, by one side or by both.
  cancelled,

  /// 17 or 18: the order ended by a dispute's resolution, whoever won it; a dispute the coordinator ends by giving everything back is [cancelled], one it settles as a trade [traded].
  dispute,

  /// Not known: this robot dropped out of the order (public again without it, or no longer shown to it), or the records do not say (no trail, a trail this code does not read back, a position that is no end).
  unknown;

  /// The end the last position of a finished order's stored trail says, [lastPosition] being `null` when no trail is stored or the one stored is not read back as that order's.
  ///
  /// Only the five ends that say how the order ended are given a word that affirms it; `publicAgain` and `notAvailable`, where only this robot's own part is known to have ended, are [unknown], as every position that is no end.
  static OrderEnd of(TradePosition? lastPosition) => switch (lastPosition) {
    TradePosition.succeeded => traded,
    TradePosition.expired => expired,
    TradePosition.cancelled => cancelled,
    TradePosition.makerLostDispute || TradePosition.takerLostDispute => dispute,
    TradePosition.publicAgain ||
    TradePosition.notAvailable ||
    TradePosition.start ||
    TradePosition.makerBondStep ||
    TradePosition.public ||
    TradePosition.paused ||
    TradePosition.bondStep ||
    TradePosition.preTakeUnavailable ||
    TradePosition.waitingForBoth ||
    TradePosition.waitingForEscrow ||
    TradePosition.waitingForPayout ||
    TradePosition.chatting ||
    TradePosition.fiatSent ||
    TradePosition.inDispute ||
    TradePosition.sendingSats ||
    TradePosition.routingFailed ||
    TradePosition.waitingDisputeResolution ||
    null => unknown,
  };

  /// Whether the robot of a finished order whose stored trail stops at [lastPosition] has served, so that the Garage moves away from it (#251, design note `docs/design/phase-3-fresh-robot.md` § 3): as the reference's `Slot.isReusable` reads it (`models/Slot.model.ts:293-309`, commit babf62e), a trade, a dispute, a cancellation or an end not known serves, an expiry does not.
  ///
  /// The one distinction [of] does not make: `publicAgain` and `notAvailable`, a take that never started (a pre-take that ran out, was cancelled, or lost to another taker), have not served, as the reference leaves no last order on a pre-taker (`api/logics.py:1205-1219`, `:1326`); every other [unknown] has. Nothing the history shows depends on it.
  static bool served(TradePosition? lastPosition) => switch (of(lastPosition)) {
    traded || cancelled || dispute => true,
    expired => false,
    unknown =>
      lastPosition != TradePosition.publicAgain &&
          lastPosition != TradePosition.notAvailable,
  };
}

/// A closed record of the trades with an order id, and the last position of its stored trail, as `TradeRecordRepository.watchClosedTrades` reads them in one statement.
@immutable
final class ClosedTrade {
  final TradeRecord record;

  /// The position of the stored trail, or `null` when none is stored or the one stored is not read back as the trail of [record]'s order (another type than this code writes, a version or position it does not know, another order, coordinator, network or role).
  final TradePosition? lastPosition;

  const ClosedTrade(this.record, this.lastPosition);

  @override
  bool operator ==(Object other) =>
      other is ClosedTrade &&
      other.record == record &&
      other.lastPosition == lastPosition;

  @override
  int get hashCode => Object.hash(record, lastPosition);

  /// Its type only: never the order's number, its coordinator or its robot (design note § 6).
  @override
  String toString() => 'ClosedTrade';
}

/// An order of the history: its record, closed after its order was confirmed, and how it ended.
@immutable
final class FinishedOrder {
  final TradeRecord record;
  final OrderEnd end;

  /// When this device read the end: the record's time of closing, which may be later than the time the coordinator ended the order.
  final DateTime endedAt;

  const FinishedOrder._(this.record, this.end, this.endedAt);

  @override
  bool operator ==(Object other) =>
      other is FinishedOrder &&
      other.record == record &&
      other.end == end &&
      other.endedAt == endedAt;

  @override
  int get hashCode => Object.hash(record, end, endedAt);

  /// Its type only: never the order's number, its coordinator or its robot (design note § 6).
  @override
  String toString() => 'FinishedOrder';
}

/// The history of finished orders of one Garage Key on one network (#253), from the device's records only.
abstract final class OrderHistory {
  /// How many lines the history shows when it opens, and how many more « See more » adds.
  static const int page = 10;

  /// Of [closed], the finished orders of every key of the network, or of the key of [key] when it is given, the newest end first (since #81 the Garage's history covers every key, its lines saying each one's key): each record closed after its order was confirmed, made here or taken here, as the « Last order #N » lines take them (`ListLastOrdersUsecase.lastOrdersOf`); a take or a make that never happened (never confirmed) is no order, and a trade recovered from a pasted key is neither made nor taken here.
  ///
  /// Equal ends are ordered by the higher order number, then the higher robot index, so that the order of the lines never depends on the order of the rows.
  static List<FinishedOrder> of(
    Iterable<ClosedTrade> closed, [
    GarageKeyFingerprint? key,
  ]) {
    final orders = <FinishedOrder>[
      for (final ClosedTrade(:record, :lastPosition) in closed)
        if ((record.closedAt, record.confirmedAt) case (final endedAt?, _?)
            when (key == null || record.robot.keyFingerprint == key) &&
                record.origin != TradeOrigin.recovered)
          FinishedOrder._(record, OrderEnd.of(lastPosition), endedAt),
    ];
    orders.sort((a, b) {
      final byEnd = b.endedAt.compareTo(a.endedAt);
      if (byEnd != 0) return byEnd;
      final byOrder = b.record.orderId.compareTo(a.record.orderId);
      if (byOrder != 0) return byOrder;
      return b.record.robot.accountIndex.compareTo(a.record.robot.accountIndex);
    });
    return List.unmodifiable(orders);
  }
}
