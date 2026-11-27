import 'package:primitives/primitives.dart';

import 'network_garage_key.dart';
import 'p2p_failure.dart';
import 'trade_record.dart';

/// The robot the next trade of a Garage Key would get, from what a new trade may use of that key: the one computation that `InterimTradeRobots.robotForNewTrade` reserves and that the Garage shows as « the fresh robot » without reserving it (#251, design note `docs/design/phase-3-fresh-robot.md` § 4.1), so that the two can never disagree.
abstract final class NextTradeRobot {
  /// The first usable robot of [key] whose index [standing] does not hold in use, strictly above the floor of the key's recovery note when one was read ([NewTradeStanding.noteFloor], #81), as `NetworkGarageKey.firstUsableRobot` finds it (an index whose token or nickname a coordinator would refuse is skipped); a key with no usable index left is a [GarageRobotUnavailableFailure], the last index as floor included.
  ///
  /// Every key gives robots for new trades, whatever its origin: a key drawn here, a key of the wallet's words, a key imported (decided on 2026-11-26, #81).
  ///
  /// It reads nothing and reserves nothing: the robot is free when [standing] was read, and a reservation made since may have taken it.
  static Result<NetworkRobot, P2pFailure> of(
    NetworkGarageKey key,
    NewTradeStanding standing,
  ) => firstFreeAmong(
    standing.indexesInUse,
    key.firstUsableRobot,
    (robot) => robot.accountIndex,
    from: switch (standing.noteFloor) {
      final floor? => floor + 1,
      null => 0,
    },
  );

  /// The first robot [firstUsable] gives from an index at or above [from] whose index, read by [indexOf], is not in [inUse]: [of] over any robots, which the tests play by their indexes, no Garage Key being known whose first usable robot from a free index is one in use.
  static Result<R, F> firstFreeAmong<R, F extends Failure>(
    Set<int> inUse,
    Result<R, F> Function(int fromIndex) firstUsable,
    int Function(R robot) indexOf, {
    int from = 0,
  }) {
    var next = from;
    while (true) {
      while (inUse.contains(next)) {
        next++;
      }
      switch (firstUsable(next)) {
        case Ok(:final value) when inUse.contains(indexOf(value)):
          // A skipped index led to one in use: go on after it.
          next = indexOf(value) + 1;
        case final found:
          return found;
      }
    }
  }
}
