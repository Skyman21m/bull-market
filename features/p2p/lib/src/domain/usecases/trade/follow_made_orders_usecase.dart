import 'package:primitives/primitives.dart';

import '../../network_garage_key.dart';
import '../../repositories/trade_trail_repository.dart';
import '../../robot_binding.dart';
import '../../trade/trade_edges.dart';

/// The robot the Garage shows of the orders made here (#227): the robot of the newest order made with the Garage Key in use whose bond this device saw locked, when the Garage opens, then the robot of each such order whose bond it sees locked while the Garage is shown. Read from the device only, nothing sent.
///
/// The same rule for a creation and a renewal (the owner's decisions of 2026-11-19): never while an order waits for its bond ([TradePosition.makerBondLocked]: public, paused, or further). Close to the reference, whose Garage shows the robot that made the order (`models/Garage.model.ts:547-558`, the robot shown makes it).
/// An order of another Garage Key or network is none of them ([NetworkGarageKey.robotOf]). Among the orders of one key, the newest is the one of the highest index, a fresh robot always taking an index above every robot used before (`TradeRobots.robotForNewTrade`), never the device's clock.
final class FollowMadeOrdersUsecase {
  final TradeTrailRepository _trails;

  const FollowMadeOrdersUsecase(this._trails);

  /// First, once, the robot to open the Garage on: that of the newest order made here with [key] whose bond was seen locked, or `null` when there is none or the records cannot be read. Then the robot of each order made with [key] whose bond is seen locked after the first list read, the newest when several are seen locked at once, never one already seen.
  ///
  /// A plain transform of the records' stream, so that cancelling it cancels their watch at once.
  Stream<RobotSlot?> execute(NetworkGarageKey key) {
    var started = false;
    // The robots of the orders seen locked, from the first list read; `null` until a list could be read.
    Set<RobotSlot>? seen;
    return _trails.watchMadeHistories(key.network).expand((result) {
      switch (result) {
        case Err():
          if (started) return const <RobotSlot?>[];
          started = true;
          return const <RobotSlot?>[null];
        case Ok(value: final histories):
          final locked = lockedOf(histories, key);
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

  /// The robots of the orders of [histories] made with [key] whose stored trail shows their bond locked, the oldest first (by index).
  static List<RobotSlot> lockedOf(
    Map<RobotSlot, StoredMadeHistory> histories,
    NetworkGarageKey key,
  ) {
    final locked = [
      for (final MapEntry(key: robot, value: history) in histories.entries)
        if (TradePosition.values
                    .where(
                      (position) => position.name == history.trail?.position,
                    )
                    .firstOrNull
                    ?.makerBondLocked ==
                true &&
            key.robotOf(robot) != null)
          robot,
    ]..sort((a, b) => a.accountIndex.compareTo(b.accountIndex));
    return locked;
  }
}
