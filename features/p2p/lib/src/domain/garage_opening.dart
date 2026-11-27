import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import 'network_garage_key.dart';
import 'order_history.dart';
import 'p2p_failure.dart';
import 'robot_binding.dart';
import 'trade/active_trade.dart';
import 'trade/trade_edges.dart';
import 'trade_record.dart';
import 'usecases/trade/list_last_orders_usecase.dart';

/// What the Garage reads of the device's records of one network for the robot it shows (#251, design note `docs/design/phase-3-fresh-robot.md` § 4.1): read from the device only, nothing sent.
///
/// It holds no token and no key: robots are held as their [RobotSlot].
@immutable
final class GarageRecords {
  /// The trades of the network not closed, with where their stored trail says they stand (`ListActiveTradesUsecase`).
  final List<ActiveTrade> inProgress;

  /// The closed records of the network that have an order id, each with the last position of its stored trail (`TradeRecordRepository.watchClosedTrades`).
  final List<ClosedTrade> closed;

  /// The robot the next trade of the key would reserve ([NextTradeRobot.of] over the same standing), or `null` when there is none: no usable index left.
  final RobotSlot? fresh;

  /// The robot the key's recovery note names, the last robot used for the key as the relays told this device ([NewTradeStanding.noteFloor], #81), or `null` when no note was read: the robot the Garage opens on when the device knows nothing better, as the official client opens on it (design note `docs/design/garage-key-from-the-words.md` § 3).
  final RobotSlot? noted;

  GarageRecords({
    required Iterable<ActiveTrade> inProgress,
    required Iterable<ClosedTrade> closed,
    required this.fresh,
    this.noted,
  }) : inProgress = List.unmodifiable(inProgress),
       closed = List.unmodifiable(closed);

  /// The orders (coordinator's short alias, order id) of [robot] that this device holds finished with an end that has not served ([OrderEnd.served]): an expiry, or a take that never started. The Garage's sentence on a robot involved in a trade is not said for such a last order (§ 4.1, « What the Garage says »).
  Set<(String, int)> ordersNotServedOf(RobotSlot robot) => {
    for (final ClosedTrade(:record, :lastPosition) in closed)
      if (record.robot == robot &&
          record.confirmedAt != null &&
          !OrderEnd.served(lastPosition))
        (record.coordinatorAlias, record.orderId),
  };

  /// The record not closed of [robot], made or taken here, if any: the one the Garage may read once when it opens (§ 4.1, step 0).
  TradeRecord? openRecordOf(RobotSlot robot) {
    for (final ActiveTrade(:record) in inProgress) {
      if (record.robot == robot &&
          record.closedAt == null &&
          record.origin != TradeOrigin.recovered) {
        return record;
      }
    }
    return null;
  }

  @override
  String toString() =>
      'GarageRecords(${inProgress.length} in progress, ${closed.length} closed, fresh: $fresh, noted: $noted)';
}

/// The robot the Garage opens on and moves to by itself (#251, design note `docs/design/phase-3-fresh-robot.md` § 4.1, steps 1 to 3): a pure function of the device's records, nothing asked of a coordinator.
///
/// As the reference's `Garage.ensureReusableSlot` (`models/Garage.model.ts:233-298`, commit babf62e): the robot of a trade in progress stays; a robot that has served gives way to the next one; a robot whose last order expired stays. The next one is here the robot the next trade would reserve ([GarageRecords.fresh]), never a robot sent anywhere.
abstract final class GarageOpening {
  /// The robot to show of [key] by [records], or `null` for the first usable robot from index 0:
  ///
  /// 1. a trade of the key in progress here whose bond this device saw locked ([TradePosition.makerBondLocked]: for a taker from 6 on), made or taken here: the robot of the newest (highest index); never one waiting for its bond, a pending take or a pre-take;
  /// 2. else the newest finished trade, the first « Last order #N » line (`ListLastOrdersUsecase.lastOrdersOf`), when it is of the key: its robot when it has not served ([OrderEnd.served]: an expiry, a take that never started), else the fresh robot, or its own robot when there is none;
  /// 3. else the robot the key's recovery note names ([GarageRecords.noted], #81), as the official client opens on the note's robot;
  /// 4. else `null`.
  ///
  /// Every key follows this rule, whatever its origin, since every key trades here (decided on 2026-11-26, #81).
  static RobotSlot? of(NetworkGarageKey key, GarageRecords records) {
    if (lockedOf(key, records).lastOrNull case final robot?) return robot;
    final line = lastOrderOf(records);
    if (line == null || !_isOf(key, line.record.robot)) {
      return switch (records.noted) {
        final noted? when _isOf(key, noted) => noted,
        _ => null,
      };
    }
    if (!OrderEnd.served(line.lastPosition)) return line.record.robot;
    return records.fresh ?? line.record.robot;
  }

  /// The robots of the trades of [key] in progress here whose bond this device saw locked, the oldest first (by index): step 1 of [of]. A trade made or taken here counts; a trade recovered never does.
  static List<RobotSlot> lockedOf(NetworkGarageKey key, GarageRecords records) {
    final locked = [
      for (final ActiveTrade(:record, :standing) in records.inProgress)
        if ((record.origin == TradeOrigin.madeHere ||
                record.origin == TradeOrigin.takenHere) &&
            record.closedAt == null &&
            standing is ActiveTradeAt &&
            standing.position.makerBondLocked &&
            _isOf(key, record.robot))
          record.robot,
    ]..sort((a, b) => a.accountIndex.compareTo(b.accountIndex));
    return locked;
  }

  /// The first « Last order #N » line of [records], with the last position of its trail: of the closed records, as `ListLastOrdersUsecase.lastOrdersOf` takes them from every record of the network, the oldest written first.
  static ClosedTrade? lastOrderOf(GarageRecords records) {
    final byTaking = [...records.closed]
      ..sort((a, b) {
        final byTime = a.record.takenAt.compareTo(b.record.takenAt);
        if (byTime != 0) return byTime;
        return a.record.robot.accountIndex.compareTo(
          b.record.robot.accountIndex,
        );
      });
    final first = ListLastOrdersUsecase.lastOrdersOf([
      for (final closed in byTaking) closed.record,
    ]).firstOrNull;
    if (first == null) return null;
    for (final closed in records.closed) {
      if (closed.record == first) return closed;
    }
    return null;
  }

  /// Whether [robot] is one of [key]'s: the same network and key fingerprint, read without deriving the robot, as every record of the key holds a robot the key gave.
  static bool _isOf(NetworkGarageKey key, RobotSlot robot) =>
      robot.network == key.network &&
      switch (key.fingerprint) {
        Ok(:final value) => robot.keyFingerprint == value,
        Err() => false,
      };

  /// The robots of the trades of [key] that ended in a trade or a dispute (14, 17, 18): the ends after which the reference forgets where the user left the Garage (`contexts/GarageContext.tsx:138-141`).
  static Set<RobotSlot> endedInTradeOf(
    NetworkGarageKey key,
    GarageRecords records,
  ) => {
    for (final ClosedTrade(:record, :lastPosition) in records.closed)
      if (record.confirmedAt != null &&
          _isOf(key, record.robot) &&
          switch (lastPosition) {
            TradePosition.succeeded ||
            TradePosition.makerLostDispute ||
            TradePosition.takerLostDispute => true,
            _ => false,
          })
        record.robot,
  };
}

/// Where the user left the Garage of each network by hand, with the arrows or a tap on « Last order #N » (#251, design note § 4.1, step 4): in memory only, one object for the feature, which the locator creates.
///
/// As the reference's `manualNavigationActive` (`models/Garage.model.ts:247-254`, commit babf62e; cleared at start, `contexts/GarageContext.tsx:100`, and when a trade ends at 14, 17 or 18, `:138-141`): the Garage stays on the robot left by hand for the run of the app, leaving the Garage and coming back included, until a trade of the key ends in a trade or a dispute after it was left there.
/// And until a trade of the key has its bond seen locked after it: the owner's decisions of 2026-11-19 (#227) show the robot of an order made or renewed here once its bond is locked, and a renewal is always opened from a « Last order #N » line, which leaves the Garage by hand; the reference comes to the same, its take and make using the robot shown. The design note's step 4 does not name this case: said in the pull request.
/// It reveals nothing by itself: robot slots, no token and no key; a restart forgets it.
final class GarageNavigation {
  final Map<RobosatsNetwork, _LeftByHand> _left = {};

  /// The robot the Garage shows of [key] by [records]: the robot left by hand when it is one of [key]'s and nothing since made it give way, else the rule's ([GarageOpening.of]), `null` for the first usable robot from index 0 or records that cannot be read.
  ///
  /// A robot left by hand that gives way is forgotten here.
  RobotSlot? robotOf(
    NetworkGarageKey key,
    Result<GarageRecords, P2pFailure> records,
  ) {
    final left = _left[key.network];
    if (left != null) {
      if (!GarageOpening._isOf(key, left.robot)) {
        _left.remove(key.network);
      } else if (records case Ok(:final value)) {
        if (left.givesWayTo(key, value)) {
          _left.remove(key.network);
        } else {
          return left.robot;
        }
      } else {
        return left.robot;
      }
    }
    return switch (records) {
      Ok(:final value) => GarageOpening.of(key, value),
      Err() => null,
    };
  }

  /// The robot left by hand on the Garage of [key]'s network, if any and still of [key].
  RobotSlot? leftByHand(NetworkGarageKey key) => switch (_left[key.network]) {
    final left? when GarageOpening._isOf(key, left.robot) => left.robot,
    _ => null,
  };

  /// The user moved the Garage of [key] to [robot] by hand, the records being [records] then (`null` when not read yet).
  void leave(
    NetworkGarageKey key,
    RobotSlot robot,
    Result<GarageRecords, P2pFailure>? records,
  ) {
    _left[key.network] = _LeftByHand(robot)..seen(key, records);
  }

  /// Forgets where the Garage of [network] was left: its key was deleted.
  void forget(RobosatsNetwork network) => _left.remove(network);
}

/// A robot left by hand, and what the records held when it was: the trades ended in a trade or a dispute, and the trades in progress whose bond was locked.
final class _LeftByHand {
  final RobotSlot robot;
  Set<RobotSlot>? _ended;
  Set<RobotSlot>? _locked;

  _LeftByHand(this.robot);

  /// Takes what [records] hold as what was known when the robot was left, unless it was taken already.
  void seen(NetworkGarageKey key, Result<GarageRecords, P2pFailure>? records) {
    if (_ended != null) return;
    if (records case Ok(:final value)) {
      _ended = GarageOpening.endedInTradeOf(key, value);
      _locked = GarageOpening.lockedOf(key, value).toSet();
    }
  }

  /// Whether [records] hold a trade ended in a trade or a dispute, or a trade whose bond was locked, that was not there when the robot was left; the first records read since it was left, when none were then, are taken as those.
  bool givesWayTo(NetworkGarageKey key, GarageRecords records) {
    final ended = _ended;
    final locked = _locked;
    if (ended == null || locked == null) {
      seen(key, Ok(records));
      return false;
    }
    return !ended.containsAll(GarageOpening.endedInTradeOf(key, records)) ||
        !locked.containsAll(GarageOpening.lockedOf(key, records));
  }
}
