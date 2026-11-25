import 'package:primitives/primitives.dart';

import 'network_garage_key.dart';
import 'p2p_failure.dart';
import 'trade_record.dart';

/// The robot the next trade of a Garage Key would get, from what a new trade may use of that key: the one computation that `InterimTradeRobots.robotForNewTrade` reserves and that the Garage shows as « the fresh robot » without reserving it (#251, design note `docs/design/phase-3-fresh-robot.md` § 4.1), so that the two can never disagree.
abstract final class NextTradeRobot {
  /// The first usable robot of [key] whose index [standing] does not hold in use, as `NetworkGarageKey.firstUsableRobot` finds it (an index whose token or nickname a coordinator would refuse is skipped); a key whose history does not let its robots start a trade is a [GarageKeyNotForTradesFailure], and a key with no usable index left a [GarageRobotUnavailableFailure].
  ///
  /// It reads nothing and reserves nothing: the robot is free when [standing] was read, and a reservation made since may have taken it.
  static Result<NetworkRobot, P2pFailure> of(
    NetworkGarageKey key,
    NewTradeStanding standing,
  ) {
    if (!standing.keyDrawnHereOnly) {
      return const Err(GarageKeyNotForTradesFailure());
    }
    return firstFreeAmong(
      standing.indexesInUse,
      key.firstUsableRobot,
      (robot) => robot.accountIndex,
    );
  }

  /// The first robot [firstUsable] gives from an index whose index, read by [indexOf], is not in [inUse]: [of] over any robots, which the tests play by their indexes, no Garage Key being known whose first usable robot from a free index is one in use.
  static Result<R, F> firstFreeAmong<R, F extends Failure>(
    Set<int> inUse,
    Result<R, F> Function(int fromIndex) firstUsable,
    int Function(R robot) indexOf,
  ) {
    var from = 0;
    while (true) {
      while (inUse.contains(from)) {
        from++;
      }
      switch (firstUsable(from)) {
        case Ok(:final value) when inUse.contains(indexOf(value)):
          // A skipped index led to one in use: go on after it.
          from = indexOf(value) + 1;
        case final found:
          return found;
      }
    }
  }
}
