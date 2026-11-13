import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import 'robot_binding.dart';

/// The side of a trade this device's robot is on, fixed at the take from the type of the public order: taking a sell order makes a buyer.
enum TradeRole { buyer, seller }

/// How a trade came to be recorded on this device: taken here, or taken over after recovery found it (design note `docs/design/phase-2-taking-an-order.md` § 3.3, § 3.5).
enum TradeOrigin {
  /// Written as a pending take by the path of the take, before its request leaves, for a robot the robot layer reserved for a new trade.
  ///
  /// Only `TradeRecordRepository.recordPendingTake` writes it, and only the take use case calls that (#87).
  /// It is a fact about the trade: a robot of a pasted key may finish an order it already holds, as a `recovered` trade, but never starts one (#79).
  takenHere,

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

  /// The id of the order on that coordinator.
  final int orderId;

  final TradeRole role;

  final TradeOrigin origin;

  /// When the record was written: before the take's request for a trade taken here, at the user's take-over for a recovered one.
  final DateTime takenAt;

  /// When the coordinator's answer showed that this robot took the order, or `null` while the take is pending; a recovered trade is confirmed when it is recorded.
  final DateTime? confirmedAt;

  /// When the trade ended (a terminal status was read, or the pending take turned out not to have happened), or `null` while it is active.
  final DateTime? closedAt;

  /// The payment hash of a payment of this trade started from this wallet, 64 lowercase hexadecimal characters, or `null` when none was started; never printed.
  ///
  /// Nothing writes it yet: the pull request that adds « Pay with this wallet » does, with [paymentStartedAt], before it asks the wallet to pay, so that the app never pays a trade twice (design note § 3.5, § 4.5).
  final String? paymentHash;

  /// When that payment was started: present exactly when [paymentHash] is.
  final DateTime? paymentStartedAt;

  /// The id of the wallet's swap that pays it, once the wallet returned it: present only with [paymentHash].
  final String? paymentSwapId;

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
    this.paymentHash,
    this.paymentStartedAt,
    this.paymentSwapId,
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
      other.closedAt == closedAt &&
      other.paymentHash == paymentHash &&
      other.paymentStartedAt == paymentStartedAt &&
      other.paymentSwapId == paymentSwapId;

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
    paymentHash,
    paymentStartedAt,
    paymentSwapId,
  );

  /// The robot without its key's fingerprint, the coordinator's alias, the order and the state; nothing of a payment.
  @override
  String toString() =>
      'TradeRecord($robot, $coordinatorAlias, $orderId, ${role.name}, ${origin.name}, ${switch ((confirmedAt, closedAt)) {
        (_, _?) => 'closed',
        (_?, null) => 'taken',
        (null, null) => 'pending',
      }})';
}

/// What a new trade may use of one Garage Key on one network, read in one statement: whether the key's history lets its robots start a trade, and the indexes already used.
@immutable
final class NewTradeStanding {
  /// Whether the key is recorded as drawn on this device for the network, and recorded as nothing else on any network: neither imported nor acknowledged, so that none of its robots can live on a coordinator from elsewhere.
  final bool keyDrawnHereOnly;

  /// The robot indexes of the key that are bound to a coordinator, on either network, or have a trade record: a new trade never uses one of them.
  final Set<int> indexesInUse;

  NewTradeStanding({
    required this.keyDrawnHereOnly,
    required Iterable<int> indexesInUse,
  }) : indexesInUse = Set.unmodifiable(indexesInUse);

  @override
  bool operator ==(Object other) =>
      other is NewTradeStanding &&
      other.keyDrawnHereOnly == keyDrawnHereOnly &&
      other.indexesInUse.length == indexesInUse.length &&
      other.indexesInUse.containsAll(indexesInUse);

  @override
  int get hashCode =>
      Object.hash(keyDrawnHereOnly, Object.hashAllUnordered(indexesInUse));

  @override
  String toString() =>
      'NewTradeStanding($keyDrawnHereOnly, ${indexesInUse.length} in use)';
}
