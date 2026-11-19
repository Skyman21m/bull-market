import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../../network_garage_key.dart';
import '../../p2p_failure.dart';
import '../../robot_binding.dart';
import '../../trade/active_trade.dart';
import '../../trade/trade_edges.dart';
import '../../trade_record.dart';

/// `ListActiveTradesUsecase.execute`, the device's trades not closed with where their stored trail says they stand, which the locator gives the use case.
typedef ActiveTradesOf =
    Stream<Result<List<ActiveTrade>, P2pFailure>> Function(
      RobosatsNetwork network,
    );

/// `ListLastOrdersUsecase.execute`, the read of the « Last order #N » lines, which the locator gives the use case.
typedef LastOrdersOf =
    Stream<Result<List<TradeRecord>, P2pFailure>> Function(
      RobosatsNetwork network,
    );

/// The robot the Garage shows of the orders made here (#227): the robot of the newest order made with the Garage Key in use whose bond this device saw locked, when the Garage opens, then the robot of each such order whose bond it sees locked while the Garage is shown. Read from the device only, nothing sent.
///
/// The same rule for a creation and a renewal (the owner's decisions of 2026-11-19): never while an order waits for its bond ([TradePosition.makerBondLocked]: public, paused, or further). Close to the reference, whose Garage shows the robot that made the order (`models/Garage.model.ts:547-558`, the robot shown makes it).
/// When none is locked, the Garage opens on the robot of the « Last order #N » line shown under it (`_lastOrderRobot`, review of #229, C1), so that the robot and the line go together from the opening, as in the reference, where they always do and an order expired or cancelled keeps its robot shown (`models/Slot.model.ts:293-310`).
/// An order of another Garage Key or network is none of them ([NetworkGarageKey.robotOf]). Among the orders of one key, the newest is the one of the highest index, a fresh robot always taking an index above every robot used before (`TradeRobots.robotForNewTrade`): the order of the makes, where the time a record was written is the device's clock, which may have been set back or forward (security review of #220, C2), and the made histories carry no time.
///
/// An order counts while it is in progress and only then: its record not closed (`ListActiveTradesUsecase`, over `TradeRecordRepository.watchActiveTrades`), the very complement of what the « Last order #N » line may show, a record closed after its order was confirmed (`ListLastOrdersUsecase.lastOrdersOf`), so that no order falls between the two (review of #229, C3): an order at 13 or 15, its buyer's payment under way or failed, still counts; an order over counts only through the line.
final class FollowMadeOrdersUsecase {
  final ActiveTradesOf _activeTrades;
  final LastOrdersOf _lastOrders;

  const FollowMadeOrdersUsecase(this._activeTrades, this._lastOrders);

  /// First, once, the robot to open the Garage on: that of the newest order made here with [key] whose bond was locked and which is still in progress (an order over passing only through the line, review of #229, C3), else that of the first « Last order #N » line when it is of [key], or `null` when there is neither or the records cannot be read. Then the robot of each order made with [key] whose bond is seen locked after the first list read (never one closed), the newest when several are seen locked at once, never one already seen.
  ///
  /// A plain transform of the records' stream, so that cancelling it cancels their watch at once.
  Stream<RobotSlot?> execute(NetworkGarageKey key) {
    var opening = true;
    return _follow(key).asyncMap((robot) async {
      if (!opening) return robot;
      opening = false;
      return robot ?? await _lastOrderRobot(key);
    });
  }

  /// The robot of the first « Last order #N » line, the device's last finished order (#216), from the very read of the lines, when it is of [key]: the rule of the opening when no order made here is locked (review of #229, C1), kept here alone.
  Future<RobotSlot?> _lastOrderRobot(NetworkGarageKey key) async =>
      switch (await _lastOrders(key.network).first) {
        Ok(value: [final last, ...]) when key.robotOf(last.robot) != null =>
          last.robot,
        _ => null,
      };

  /// [execute] without the « Last order #N » line: the newest order locked, or `null`, then each one seen locked.
  Stream<RobotSlot?> _follow(NetworkGarageKey key) {
    var started = false;
    // The robots of the orders seen locked, from the first list read; `null` until a list could be read.
    Set<RobotSlot>? seen;
    return _activeTrades(key.network).expand((result) {
      switch (result) {
        case Err():
          if (started) return const <RobotSlot?>[];
          started = true;
          return const <RobotSlot?>[null];
        case Ok(value: final trades):
          final locked = lockedOf(trades, key);
          final known = seen;
          if (known == null) {
            seen = locked.toSet();
            if (started) return const <RobotSlot?>[];
            started = true;
            return [locked.lastOrNull];
          }
          final fresh = [
            for (final robot in locked)
              if (!known.contains(robot)) robot,
          ];
          known.addAll(fresh);
          if (fresh.lastOrNull case final robot?) return [robot];
          return const <RobotSlot?>[];
      }
    });
  }

  /// The robots of the orders of [trades], all of them not closed, made here with [key], whose stored trail shows their bond locked once ([TradePosition.makerBondLocked]), the oldest first (by index).
  static List<RobotSlot> lockedOf(
    List<ActiveTrade> trades,
    NetworkGarageKey key,
  ) {
    final locked = [
      for (final ActiveTrade(:record, :standing) in trades)
        if (record.origin == TradeOrigin.madeHere &&
            record.closedAt == null &&
            standing is ActiveTradeAt &&
            standing.position.makerBondLocked &&
            key.robotOf(record.robot) != null)
          record.robot,
    ]..sort((a, b) => a.accountIndex.compareTo(b.accountIndex));
    return locked;
  }
}
