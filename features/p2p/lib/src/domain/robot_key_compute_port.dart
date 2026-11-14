import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show
        CoordinatorRobot,
        PgpFailure,
        RobotIdentity,
        RobotPgpKey,
        RobotPgpKeyNotProven,
        UnlockedRobotPgpKey,
        UnprovenCoordinatorRobot;

import 'p2p_failure.dart';

/// Runs the work on the OpenPGP key pair of a robot that costs seconds of CPU, away from the UI isolate: tests replace it.
///
/// Making a pair, proving one and unlocking one each hash 32 MiB of SHA-256 for a key of the official client or of Troc, and proving a pair a coordinator made up can cost up to `PgpLimits.proofHashedBytes`: on the UI isolate, that would freeze the screens.
abstract interface class RobotKeyComputePort {
  /// A new key pair for [identity], as `RobotPgpKey.generate` makes it: locked by its token, dated a day back.
  ///
  /// Fails with [RobotKeyComputeFailure] when the clock of the device is outside the dates an OpenPGP key can hold, or when the work could not be started.
  Future<Result<RobotPgpKey, RobotKeyComputeFailure>> generate(
    RobotIdentity identity,
  );

  /// [robot] proven by its token, as `UnprovenCoordinatorRobot.prove` proves it, which is the inner result.
  ///
  /// The outer [RobotKeyComputeFailure] when the work could not be started: the pair was then neither proven nor refused.
  Future<
    Result<
      Result<CoordinatorRobot, RobotPgpKeyNotProven>,
      RobotKeyComputeFailure
    >
  >
  prove(UnprovenCoordinatorRobot robot);

  /// [key], the proven pair of the robot [identity], unlocked with its token, as `RobotPgpKey.unlock` unlocks it, which is the inner result: the key of a trade's robot, for the payout's signature (#90, design note § 3.4).
  ///
  /// The unlocked key holds the robot's secret values: only `TradeKeyring` asks for it, and keeps it no longer than its rules say.
  /// The outer [RobotKeyComputeFailure] when the work could not be started: nothing was unlocked.
  Future<
    Result<Result<UnlockedRobotPgpKey, PgpFailure>, RobotKeyComputeFailure>
  >
  unlock(RobotPgpKey key, RobotIdentity identity);
}
