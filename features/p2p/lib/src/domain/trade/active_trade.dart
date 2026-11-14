import 'package:meta/meta.dart';

import '../trade_record.dart';
import 'trade_edges.dart';
import 'trade_storable.dart';

/// One line of the « Active trades » list (#88): a trade of this device that is not closed, and where it stands as its stored trail says, with no text of a coordinator.
@immutable
final class ActiveTrade {
  final TradeRecord record;
  final ActiveTradeStanding standing;

  const ActiveTrade(this.record, this.standing);

  @override
  bool operator ==(Object other) =>
      other is ActiveTrade &&
      other.record == record &&
      other.standing == standing;

  @override
  int get hashCode => Object.hash(record, standing);

  @override
  String toString() => 'ActiveTrade($record, $standing)';
}

/// Where an active trade stands, from its stored records only (nothing is read from a coordinator for the list).
@immutable
sealed class ActiveTradeStanding {
  const ActiveTradeStanding();
}

/// The trade's position at its last read, the deadline that read gave, and whether a breach of trust or an unknown history is recorded on it; [ActiveTradeAt.position] is `TradePosition.start` for a take whose answer is awaited.
final class ActiveTradeAt extends ActiveTradeStanding {
  final TradePosition position;
  final DateTime? deadline;
  final bool breached;
  final bool historyUnknown;

  const ActiveTradeAt(
    this.position, {
    required this.deadline,
    required this.breached,
    required this.historyUnknown,
  });

  @override
  bool operator ==(Object other) =>
      other is ActiveTradeAt &&
      other.position == position &&
      other.deadline == deadline &&
      other.breached == breached &&
      other.historyUnknown == historyUnknown;

  @override
  int get hashCode => Object.hash(position, deadline, breached, historyUnknown);

  @override
  String toString() => 'ActiveTradeAt(${position.name}, breached: $breached)';
}

/// A pending take whose terms or first trail were never written: its request never left, and the watch of the trade closes it at once.
final class ActiveTradeTakeNeverSent extends ActiveTradeStanding {
  const ActiveTradeTakeNeverSent();

  @override
  bool operator ==(Object other) => other is ActiveTradeTakeNeverSent;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'ActiveTradeTakeNeverSent';
}

/// The trade's records cannot be restored: shown as such, read-only.
final class ActiveTradeUnrestorable extends ActiveTradeStanding {
  final TradeRecordRefusal reason;

  const ActiveTradeUnrestorable(this.reason);

  @override
  bool operator ==(Object other) =>
      other is ActiveTradeUnrestorable &&
      other.reason.runtimeType == reason.runtimeType;

  @override
  int get hashCode => reason.runtimeType.hashCode;

  @override
  String toString() => 'ActiveTradeUnrestorable(${reason.runtimeType})';
}
