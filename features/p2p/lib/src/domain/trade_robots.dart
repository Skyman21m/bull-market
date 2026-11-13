import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show Coordinator, RobosatsNetwork;

import 'network_garage_key.dart';
import 'p2p_failure.dart';
import 'trade_record.dart';

/// What the trades need from the robot layer (design note `docs/design/phase-2-taking-an-order.md` § 3.3): a fresh robot for each new trade, the robot of a recorded trade, and the active trades.
///
/// `InterimTradeRobots` implements it until the robot layer of #79 and #81 lands.
///
/// Never call it inside a database transaction: a robot reserved there is unbound again if the transaction rolls back, after it may have been sent to the coordinator, and could then go to a second one (`TradeRecordRepository` throws a `StateError` there).
/// `findTradesOfKey(NetworkGarageKey)`, which finds the trades a key's robots hold by reading them back from coordinators, is not declared yet: it needs the participant's order of #84 and the search of #79, and an implementation that could not read would have to lie or fail on every call.
abstract interface class TradeRobots {
  /// A robot of the Garage Key of [network] that never had a trade and was never bound to a coordinator, of a key drawn on this device and never imported or acknowledged on any network, bound to [coordinator] before it is returned, by one statement that also reserves it: two calls at once never get the same robot, and a robot returned once is never returned again.
  ///
  /// The robot is returned only once its binding is on disk, with the [TradeReservation] that its pending take needs; nothing is sent to the coordinator.
  /// The reservation is in memory: a robot whose pending take is never written stays bound to that coordinator, without a trade, and is never returned again.
  /// The calls of one connection are reserved one at a time: more than `InterimTradeRobots.maxReservationAttempts` calls at once can make the last ones fail with a [P2pStorageFailure], which a later call does not.
  /// No key for [network] is a [GarageKeyMissingFailure], a vault that refuses the read gives the vault's failure, a key from elsewhere is a [GarageKeyNotForTradesFailure], a coordinator without an onion address on [network] a [TradeCoordinatorNotOnNetworkFailure], and a key with no usable index left a [GarageRobotUnavailableFailure].
  @useResult
  Future<Result<ReservedRobot, P2pFailure>> robotForNewTrade(
    RobosatsNetwork network,
    Coordinator coordinator,
  );

  /// The robot of [record], derived from the Garage Key the vault holds for the record's network.
  ///
  /// A vault with no key there, or with another key, is a [TradeKeyMissingFailure]; a vault that refuses the read gives the vault's failure.
  @useResult
  Future<Result<NetworkRobot, P2pFailure>> robotOfTrade(TradeRecord record);

  /// The active trades of [network], pending takes included, oldest first: a new list after each write of the records, never a closed trade.
  Stream<Result<List<TradeRecord>, P2pFailure>> activeTrades(
    RobosatsNetwork network,
  );
}

/// A robot of this device and the reservation that bound it for a new trade: the robot for the requests of the take, the reservation for its pending take.
@immutable
final class ReservedRobot {
  /// The robot, with its token: keep it no longer than the requests of the take.
  final NetworkRobot robot;

  /// The reservation of that very robot, which `TradeRecordRepository.recordPendingTake` takes.
  final TradeReservation reservation;

  const ReservedRobot._(this.robot, this.reservation);

  /// [robot] with [reservation], or `null` when the reservation is not of that robot: the two always name the same robot.
  static ReservedRobot? of(NetworkRobot robot, TradeReservation reservation) =>
      robot.slot == reservation.robot ? ReservedRobot._(robot, reservation) : null;

  @override
  String toString() => 'ReservedRobot($reservation)';
}
