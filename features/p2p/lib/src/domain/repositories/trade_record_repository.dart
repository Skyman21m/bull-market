import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../garage_key_fingerprint.dart';
import '../order_history.dart' show ClosedTrade;
import '../p2p_failure.dart';
import '../robot_binding.dart';
import '../trade_record.dart';

/// The trades of this device's robots, kept so that a trade survives the app being killed, and the binding that reserves a fresh robot for a new trade (design note `docs/design/phase-2-taking-an-order.md` § 3.3, § 3.5, § 4.5).
///
/// A robot has at most one trade record, ever, and only a robot bound to a coordinator, on the trade's network, has one: the database refuses anything else.
/// A record is never deleted; a pending take is confirmed or closed, a pending make is confirmed with its order id or closed, a taken or made trade is closed, a closed record never changes: the database's triggers refuse anything else.
/// Every write is synced to disk before its future completes, as the bindings are.
/// It holds no secret: networks, key fingerprints, robot indexes, coordinators, order ids, sides, origins and times.
///
/// Never call it inside a database transaction (`transaction(…)`): a reservation, a record or a change that answered success there is undone if the transaction rolls back, after its robot may have been sent to the coordinator, and a robot whose binding was undone could go to a second coordinator.
/// Each method is one statement that commits on its own; `robot_bindings_architecture_test.dart` pins that nothing in the feature opens a transaction (drift gives no public way to tell, at run time, that a call runs inside one).
abstract interface class TradeRecordRepository {
  /// What a new trade on [network] may use of the key of [key]: its robot indexes already bound, on either network, or recorded with a trade, and the floor the key's recovery note gave, read on either network's relays (schema 11, #81). Where the key comes from does not matter (decided on 2026-11-26, #81).
  ///
  /// It reads only, in one statement: a database that cannot be read, or a row this code never writes, is a [P2pStorageFailure].
  @useResult
  Future<Result<NewTradeStanding, P2pFailure>> newTradeStandingOf(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  );

  /// The keys that have a robot bound on [network], or recorded with a trade there, by fingerprint: the keys whose recovery note is written again at each opening of the app (#81).
  ///
  /// It reads only, in one statement: a database that cannot be read, or a row this code never writes, is a [P2pStorageFailure].
  @useResult
  Future<Result<Set<GarageKeyFingerprint>, P2pFailure>> keysInUse(
    RobosatsNetwork network,
  );

  /// Binds [robot] to [coordinator] for a new trade, in one statement, and gives the [TradeReservation] a pending take needs when this call bound it.
  ///
  /// It writes the binding only when the robot's index has no binding, on either network, and no trade record, whatever the history of its key (decided on 2026-11-26, #81); the binding's provenance is `generated`, which marks a binding made for a new trade (or under a key drawn here).
  /// `null`: nothing was written, because the robot was already bound or recorded; the caller reads [newTradeStandingOf] again and goes on to the next free index.
  /// So no other call, on this connection or another, gets a reservation of the same robot.
  /// [coordinator] must be on the robot's network, or it is a [RobotNotForNewTradeFailure] and nothing is written.
  @useResult
  Future<Result<TradeReservation?, P2pFailure>> reserveForNewTrade(
    RobotSlot robot,
    CoordinatorIdentity coordinator,
  );

  /// Records the pending take of order [orderId], as [role], by the robot of [reservation] on its coordinator, of origin `takenHere`: written before the take's request leaves, so that a lost answer is recoverable.
  ///
  /// It is the only write of a trade taken here, and only the take use case is to call it (#87), with the reservation the robot layer has just given.
  /// It writes, in one statement, only when the robot has no trade record and is still bound to that coordinator on the reservation's network, by a reservation (provenance `generated`): a robot bound by « Select Host » after « Robots from elsewhere » never takes one; where its key comes from does not matter (decided on 2026-11-26, #81).
  /// The record's network and coordinator are copied from that binding by the same statement.
  /// A robot that already has a record is a [TradeAlreadyRecordedFailure]; a binding that no longer names that coordinator, as after a lost file, the failure of `RobotBinding.admits`; any other refusal a [RobotNotForNewTradeFailure].
  @useResult
  Future<Result<TradeRecord, P2pFailure>> recordPendingTake(
    TradeReservation reservation, {
    required int orderId,
    required TradeRole role,
  });

  /// Records the pending make of an order of side [role] by the robot of [reservation] on its coordinator, of origin `madeHere`, with no order id: written before the make's request leaves, so that a lost answer is recoverable (schema 8, #176; design note `docs/design/phase-3-making-an-order.md` § 3.4).
  ///
  /// It is the only write of a trade made here, and only the make use case is to call it (#179), with the reservation the robot layer has just given; no file calls it yet.
  /// It writes under the very conditions of [recordPendingTake], in one statement, and refuses as it does: a robot that already has a record is a [TradeAlreadyRecordedFailure], a binding that no longer names that coordinator the failure of `RobotBinding.admits`, any other refusal a [RobotNotForNewTradeFailure].
  @useResult
  Future<Result<PendingMake, P2pFailure>> recordPendingMake(
    TradeReservation reservation, {
    required TradeRole role,
  });

  /// Confirms [make] with the id of its order, [orderId]: a read of that order showed its robot as the maker.
  ///
  /// The order id and the confirmation are written together, once; the database refuses them unless the make's terms are recorded (`TradeTrailRepository.recordMakerTerms`) and no other open trade of the coordinator holds the order ([P2pStorageFailure], nothing written).
  /// A make already confirmed with [orderId] and still open is returned as it is; one closed is a [TradeClosedFailure]; one confirmed with another order, or a make the database does not hold as given, a [P2pStorageFailure].
  @useResult
  Future<Result<TradeRecord, P2pFailure>> confirmMake(
    PendingMake make, {
    required int orderId,
  });

  /// Closes [make]: its make turned out not to have happened, and it never will be confirmed.
  ///
  /// A make already closed stays as it is, with its first time of closing; one confirmed meanwhile is not closed by this call, which gives a [P2pStorageFailure] (its trade is closed as any other, with [closeTrade]).
  @useResult
  Future<Result<PendingMake, P2pFailure>> closePendingMake(PendingMake make);

  /// The pending makes of [network], oldest first: a new list after each write of the records, never a confirmed or closed one.
  ///
  /// A database that cannot be read, or a row this code never writes, gives a [P2pStorageFailure] in place of the list.
  Stream<Result<List<PendingMake>, P2pFailure>> watchPendingMakes(
    RobosatsNetwork network,
  );

  /// Records the trade of order [orderId] on [coordinator] that [robot] holds, as [role], of origin `recovered`, confirmed at once: only on the user's explicit take-over of a trade that recovery found.
  ///
  /// It writes only when [robot] has no trade record and is bound to [coordinator] on the robot's network, whatever the provenance of its binding: a robot of a pasted key may finish the order it holds.
  /// The record's network and coordinator are copied from that binding by the same statement; a robot that already has a record is a [TradeAlreadyRecordedFailure], one without a binding a [RobotNotBoundFailure], one bound to another coordinator or on another network a [RobotBoundToAnotherCoordinatorFailure], one bound to a coordinator that changed a [RobotCoordinatorChangedFailure].
  @useResult
  Future<Result<TradeRecord, P2pFailure>> recordRecoveredTrade(
    RobotSlot robot,
    CoordinatorIdentity coordinator, {
    required int orderId,
    required TradeRole role,
  });

  /// Confirms the pending take of [record]: the coordinator's answer showed that its robot took the order.
  ///
  /// A record already confirmed and still active stays as it is; a closed record is a [TradeClosedFailure], and nothing is written.
  /// It returns the record as stored after the call; a record the database does not hold as given, as after the file was lost, is a [P2pStorageFailure].
  @useResult
  Future<Result<TradeRecord, P2pFailure>> confirmTake(TradeRecord record);

  /// Closes [record]: a terminal status was read, or its pending take turned out not to have happened once the time to lock the taker bond was over.
  ///
  /// A record already closed stays as it is, with its first time of closing; it returns the record as stored after the call, and a record the database does not hold as given is a [P2pStorageFailure].
  @useResult
  Future<Result<TradeRecord, P2pFailure>> closeTrade(TradeRecord record);

  /// The active trades of [network], pending takes included, oldest first: a new list after each write of the records, never a closed trade nor a pending make, which has no order yet ([watchPendingMakes]).
  ///
  /// A database that cannot be read, or a row this code never writes, gives a [P2pStorageFailure] in place of the list.
  Stream<Result<List<TradeRecord>, P2pFailure>> watchActiveTrades(
    RobosatsNetwork network,
  );

  /// Every trade of [network] that has an order id, active or closed, oldest first: a new list after each write of the records, never a pending make (#216, #217). It reads only: the screens find there the last finished orders and the orders made since one was renewed.
  ///
  /// A database that cannot be read, or a row this code never writes, gives a [P2pStorageFailure] in place of the list.
  Stream<Result<List<TradeRecord>, P2pFailure>> watchTrades(
    RobosatsNetwork network,
  );

  /// Every closed record of [network] that has an order id, each with the last position of its stored trail, in one statement: a new list after each write of the records or of the trails (#253, design note `docs/design/phase-3-order-history.md` § 5). It reads only: the history of the Garage finds there the finished orders and how each ended.
  ///
  /// A database that cannot be read, or a record this code never writes, gives a [P2pStorageFailure] in place of the list; a trail it does not read back as the trail of its record's order gives that record with no position, never a failure of the whole list.
  Stream<Result<List<ClosedTrade>, P2pFailure>> watchClosedTrades(
    RobosatsNetwork network,
  );
}
