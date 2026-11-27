import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import 'robot_binding.dart';

/// The side of a trade this device's robot is on, fixed at the take from the type of the public order: taking a sell order makes a buyer.
enum TradeRole { buyer, seller }

/// How a trade came to be recorded on this device: taken here, made here, or taken over after recovery found it (design note `docs/design/phase-2-taking-an-order.md` § 3.3, § 3.5; `docs/design/phase-3-making-an-order.md` § 3.2).
enum TradeOrigin {
  /// Written as a pending take by the path of the take, before its request leaves, for a robot the robot layer reserved for a new trade.
  ///
  /// Only `TradeRecordRepository.recordPendingTake` writes it, and only the take use case calls that (#87).
  /// It is a fact about the trade: a robot of a pasted key may finish an order it already holds, as a `recovered` trade, but never starts one (#79).
  takenHere,

  /// Written as a pending make by the path of the make, before its request leaves, for a robot the robot layer reserved for a new trade (schema 8, #176).
  ///
  /// Only `TradeRecordRepository.recordPendingMake` writes it, and only the make use case is to call that (#179); no file calls it yet.
  /// A make is a [TradeRecord] only once confirmed with its order id (`TradeRecordRepository.confirmMake`): until then it is a [PendingMake], so that no user of a [TradeRecord] meets a trade without an order.
  madeHere,

  /// Written when the user explicitly took over a trade that recovery found holding an order: this device did not take it.
  ///
  /// Only `TradeRecordRepository.recordRecoveredTrade` writes it, and only the recovery use case is to call that (#79).
  recovered,
}

/// A trade of a robot of this device, as the feature's database records it: which robot, on which coordinator, which order, which side, how it came here, and whether it is still pending, taken or closed.
///
/// One robot holds at most one trade record, ever: a robot is never used for a second trade, and the database refuses a second record of one robot.
/// What the coordinator says of the order (its status, amounts, invoices, the peer) is not recorded: it is read again from the coordinator.
/// A record is never deleted, and the only changes are the ones its state allows: a pending take is confirmed or closed, a taken trade is closed, a closed record never changes.
///
/// Only the repository of the trade records makes one, from a row it has just read: `test/trade_record_test.dart` pins that no other library of the feature calls this constructor, so that no code holds a record of origin `takenHere` that the take did not write.
/// It holds no token and no key, but the fingerprint of the robot's key, which is never printed.
@immutable
final class TradeRecord {
  /// The robot of the trade: its key's fingerprint, its index, and the network, which is the network of the robot's binding and of the coordinator.
  final RobotSlot robot;

  /// The short alias of the coordinator, as the robot's binding recorded it.
  final String coordinatorAlias;

  /// The onion origin of the coordinator's instance on [network], as the robot's binding recorded it.
  final String coordinatorOnion;

  /// The id of the order on that coordinator: always known, a make whose order id is not known yet being a [PendingMake] instead.
  final int orderId;

  final TradeRole role;

  final TradeOrigin origin;

  /// When the record was written: before the take's request for a trade taken here, at the user's take-over for a recovered one.
  final DateTime takenAt;

  /// When the coordinator's answer showed that this robot took the order, or `null` while the take is pending; a recovered trade is confirmed when it is recorded.
  final DateTime? confirmedAt;

  /// When the trade ended (a terminal status was read, or the pending take turned out not to have happened), or `null` while it is active.
  final DateTime? closedAt;

  const TradeRecord({
    required this.robot,
    required this.coordinatorAlias,
    required this.coordinatorOnion,
    required this.orderId,
    required this.role,
    required this.origin,
    required this.takenAt,
    required this.confirmedAt,
    required this.closedAt,
  });

  /// The network of the trade: the network of the robot's binding, never chosen apart from it.
  RobosatsNetwork get network => robot.network;

  /// Whether the take's request may have left without its answer being known: the record is neither confirmed nor closed.
  ///
  /// The next read of the order tells whether the robot is its taker; a pending take that the coordinator does not show as this robot's once the time to lock the taker bond is over is closed (design note § 4.5).
  bool get isPendingTake => confirmedAt == null && closedAt == null;

  /// Whether the trade is still active: pending or taken, not closed.
  bool get isActive => closedAt == null;

  @override
  bool operator ==(Object other) =>
      other is TradeRecord &&
      other.robot == robot &&
      other.coordinatorAlias == coordinatorAlias &&
      other.coordinatorOnion == coordinatorOnion &&
      other.orderId == orderId &&
      other.role == role &&
      other.origin == origin &&
      other.takenAt == takenAt &&
      other.confirmedAt == confirmedAt &&
      other.closedAt == closedAt;

  @override
  int get hashCode => Object.hash(
    robot,
    coordinatorAlias,
    coordinatorOnion,
    orderId,
    role,
    origin,
    takenAt,
    confirmedAt,
    closedAt,
  );

  /// The robot without its key's fingerprint, the coordinator's alias, the order and the state.
  @override
  String toString() =>
      'TradeRecord($robot, $coordinatorAlias, $orderId, ${role.name}, ${origin.name}, ${switch ((confirmedAt, closedAt)) {
        (_, _?) => 'closed',
        (_?, null) => 'taken',
        (null, null) => 'pending',
      }})';
}

/// An order this device asked a coordinator to make, recorded before the make's request leaves, whose order id is not known yet (schema 8, #176; design note `docs/design/phase-3-making-an-order.md` § 3.4): a row of `trades` of origin `madeHere` with no order id.
///
/// The read that shows its robot as the maker of an order confirms it with that order's id (`TradeRecordRepository.confirmMake`), which turns it into a [TradeRecord]; a make that turned out not to have happened is closed (`TradeRecordRepository.closePendingMake`).
/// Only the repository of the trade records makes one, from a row it has just read: `test/trade_record_test.dart` pins that no other library of the feature calls this constructor, as for [TradeRecord].
/// It holds no token and no key, but the fingerprint of the robot's key, which is never printed.
@immutable
final class PendingMake {
  /// The robot of the make: its key's fingerprint, its index, and the network, which is the network of the robot's binding and of the coordinator.
  final RobotSlot robot;

  /// The short alias of the coordinator, as the robot's binding recorded it.
  final String coordinatorAlias;

  /// The onion origin of the coordinator's instance, as the robot's binding recorded it.
  final String coordinatorOnion;

  /// The side the order makes: the maker of a buy order buys.
  final TradeRole role;

  /// When the pending make was written, before the make's request.
  final DateTime writtenAt;

  /// When the make turned out not to have happened, or `null` while it is pending.
  final DateTime? closedAt;

  const PendingMake({
    required this.robot,
    required this.coordinatorAlias,
    required this.coordinatorOnion,
    required this.role,
    required this.writtenAt,
    required this.closedAt,
  });

  /// The network of the make: the network of the robot's binding, never chosen apart from it.
  RobosatsNetwork get network => robot.network;

  /// Whether the make is still pending: not closed.
  bool get isActive => closedAt == null;

  @override
  bool operator ==(Object other) =>
      other is PendingMake &&
      other.robot == robot &&
      other.coordinatorAlias == coordinatorAlias &&
      other.coordinatorOnion == coordinatorOnion &&
      other.role == role &&
      other.writtenAt == writtenAt &&
      other.closedAt == closedAt;

  @override
  int get hashCode => Object.hash(
    robot,
    coordinatorAlias,
    coordinatorOnion,
    role,
    writtenAt,
    closedAt,
  );

  /// The robot without its key's fingerprint, the coordinator's alias, the side and the state.
  @override
  String toString() =>
      'PendingMake($robot, $coordinatorAlias, ${role.name}, ${closedAt == null ? 'pending' : 'closed'})';
}

/// A robot that the repository of the trade records has just bound to a coordinator for a new trade, in one statement that found its index free: the proof a pending take, or a pending make, needs (`TradeRecordRepository.recordPendingTake`, `TradeRecordRepository.recordPendingMake`).
///
/// Only that repository makes one, when its reservation wrote the binding: `test/trade_record_test.dart` pins that no other library of the feature calls this constructor, and nothing extends or implements it.
/// So a robot that the Garage bound, or that a reservation lost to another call, never takes a pending take.
/// It lives in memory only: a reservation not followed by a pending take, as when the app is killed in between, leaves its robot bound to that coordinator, without a trade, and never returned again.
/// It holds no token and no key, but the fingerprint of the robot's key, which is never printed.
@immutable
final class TradeReservation {
  /// The robot reserved, with its key's network, which is the network of the trade.
  final RobotSlot robot;

  /// The coordinator the robot was bound to.
  final CoordinatorIdentity coordinator;

  const TradeReservation(this.robot, this.coordinator);

  /// The network of the trade: the robot's, which is the coordinator's.
  RobosatsNetwork get network => robot.network;

  @override
  bool operator ==(Object other) =>
      other is TradeReservation &&
      other.robot == robot &&
      other.coordinator == coordinator;

  @override
  int get hashCode => Object.hash(robot, coordinator);

  @override
  String toString() => 'TradeReservation($robot, $coordinator)';
}

/// What a new trade may use of one Garage Key on one network, read in one statement: the indexes already used.
///
/// Where the key comes from no longer decides whether its robots may start a trade (decided on 2026-11-26, #81): a key drawn here, a key of the wallet's words and a key imported trade alike; what stands in for a robot already used elsewhere is the refusal of a robot the coordinator of the trade already knows (`RobotOnCoordinatorFace.alreadyExisted`).
@immutable
final class NewTradeStanding {
  /// The robot indexes of the key that are bound to a coordinator, on either network, or have a trade record: a new trade never uses one of them.
  final Set<int> indexesInUse;

  /// The robot index the key's recovery note said, at its highest over what this device read on the relays (#81, design note `docs/design/garage-key-from-the-words.md` § 3): a new trade takes a robot strictly above it; `null` when no note was read.
  final int? noteFloor;

  NewTradeStanding({required Iterable<int> indexesInUse, this.noteFloor})
    : indexesInUse = Set.unmodifiable(indexesInUse);

  /// The highest robot index this device knows was used for the key: its own robots in use and the note's floor; `null` when it knows none.
  int? get highestKnown {
    int? highest = noteFloor;
    for (final index in indexesInUse) {
      if (highest == null || index > highest) highest = index;
    }
    return highest;
  }

  @override
  bool operator ==(Object other) =>
      other is NewTradeStanding &&
      other.noteFloor == noteFloor &&
      other.indexesInUse.length == indexesInUse.length &&
      other.indexesInUse.containsAll(indexesInUse);

  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(indexesInUse), noteFloor);

  @override
  String toString() =>
      'NewTradeStanding(${indexesInUse.length} in use, floor: $noteFloor)';
}
