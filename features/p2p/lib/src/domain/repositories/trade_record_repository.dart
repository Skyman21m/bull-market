import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../garage_key_fingerprint.dart';
import '../new_trade_permit.dart';
import '../p2p_failure.dart';
import '../robot_binding.dart';
import '../trade_record.dart';

/// The trades of this device's robots, kept so that a trade survives the app being killed, and the binding that reserves a fresh robot for a new trade (design note `docs/design/phase-2-taking-an-order.md` § 3.3, § 3.5, § 4.5).
///
/// A robot has at most one trade record, ever, and only a robot bound to a coordinator has one: the database refuses anything else.
/// A record is never deleted; a pending take is confirmed or closed, a taken trade is closed, a closed record never changes.
/// Every write is synced to disk before its future completes, as the bindings are.
/// It holds no secret: networks, key fingerprints, robot indexes, coordinators, order ids, sides, origins and times.
abstract interface class TradeRecordRepository {
  /// What a new trade on [network] may use of the key of [key]: whether the key's history lets its robots start a trade, and its robot indexes already bound, on either network, or recorded with a trade.
  ///
  /// It reads only, in one statement: a database that cannot be read, or a row this code never writes, is a [P2pStorageFailure].
  @useResult
  Future<Result<NewTradeStanding, P2pFailure>> newTradeStandingOf(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  );

  /// Binds [robot] to [coordinator] for a new trade, in one statement, and says whether this call bound it.
  ///
  /// It writes the binding only when the robot's index has no binding, on either network, and no trade record, and its key is recorded as drawn on this device for the robot's network and as nothing else on any network; the binding's provenance is then `generated`.
  /// `true`: this call wrote the binding, so no other call, on this connection or another, got this robot.
  /// `false`: nothing was written, because the robot was already bound or recorded, or because the key's history does not allow it; the caller reads [newTradeStandingOf] again to tell which.
  /// [coordinator] must be on the robot's network, or nothing is written.
  @useResult
  Future<Result<bool, P2pFailure>> reserveForNewTrade(
    RobotSlot robot,
    CoordinatorIdentity coordinator,
  );

  /// Records a pending take of order [orderId] on [coordinator] by [robot], as [role], of origin `takenHere`: written before the take's request leaves, so that a lost answer is recoverable.
  ///
  /// It is the only write of a trade taken here, and needs [permit], which only the money gate's yes for the network gives.
  /// It writes only when [robot] has no trade record and is bound to [coordinator], under a key drawn here (provenance `generated`), on [permit]'s network, which is also the robot's: the record's network and coordinator are copied from that binding by the same statement.
  /// A robot that already has a record is a [TradeAlreadyRecordedFailure]; a robot bound to another coordinator, or to one that changed, the failure of `RobotBinding.admits`; any other robot a [RobotNotForNewTradeFailure].
  @useResult
  Future<Result<TradeRecord, P2pFailure>> recordPendingTake(
    NewTradePermit permit,
    RobotSlot robot,
    CoordinatorIdentity coordinator, {
    required int orderId,
    required TradeRole role,
  });

  /// Records the trade of order [orderId] on [coordinator] that [robot] holds, as [role], of origin `recovered`, confirmed at once: only on the user's explicit take-over of a trade that recovery found.
  ///
  /// It writes only when [robot] has no trade record and is bound to [coordinator], whatever the provenance of its binding: a robot of a pasted key may finish the order it holds.
  /// The record's network and coordinator are copied from that binding by the same statement; the failures are those of [recordPendingTake], [RobotNotBoundFailure] for a robot without a binding, and [RobotBoundToAnotherCoordinatorFailure] for one bound on another network than the robot's.
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
  /// It returns the record as stored after the call; a record the database does not hold, as after the file was lost, is a [P2pStorageFailure].
  @useResult
  Future<Result<TradeRecord, P2pFailure>> confirmTake(TradeRecord record);

  /// Closes [record]: a terminal status was read, or its pending take turned out not to have happened once the time to lock the taker bond was over.
  ///
  /// A record already closed stays as it is, with its first time of closing; it returns the record as stored after the call, and a record the database does not hold is a [P2pStorageFailure].
  @useResult
  Future<Result<TradeRecord, P2pFailure>> closeTrade(TradeRecord record);

  /// The active trades of [network], pending takes included, oldest first: a new list after each write of the records, never a closed trade.
  ///
  /// A database that cannot be read, or a row this code never writes, gives a [P2pStorageFailure] in place of the list.
  Stream<Result<List<TradeRecord>, P2pFailure>> watchActiveTrades(
    RobosatsNetwork network,
  );
}
