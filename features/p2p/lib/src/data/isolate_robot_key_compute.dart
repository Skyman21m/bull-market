import 'dart:isolate';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show
        CoordinatorRobot,
        PgpClockOutOfRange,
        RobotIdentity,
        RobotPgpKey,
        RobotPgpKeyNotProven,
        UnprovenCoordinatorRobot;

import '../domain/p2p_failure.dart';
import '../domain/robot_key_compute_port.dart';

/// Runs the work on the key pair of a robot in a short-lived isolate of its own (`Isolate.run`), so that the UI isolate never does the hashing.
///
/// The isolate receives a copy of what the work needs, the robot's identity with its token included, and ends as soon as the work is done: the passphrase and the secret values a proof unlocks are wiped in it before it ends, and only the locked pair comes back.
/// An isolate started so belongs to the group of the app's isolates and shares their heap: running elsewhere keeps the screens fluid, it does not keep the token or the unlocked values apart in memory.
/// Each closure handed to `Isolate.run` is made in a static method, where it can hold nothing but its one argument, so that nothing else of the feature is copied to the isolate.
/// An isolate that cannot be started is a [RobotKeyComputeFailure]; an [Error] of the work is a bug and reaches the caller, as rule 11 of AGENTS.md wants.
final class IsolateRobotKeyCompute implements RobotKeyComputePort {
  const IsolateRobotKeyCompute();

  @override
  Future<Result<RobotPgpKey, RobotKeyComputeFailure>> generate(
    RobotIdentity identity,
  ) async => switch (await _generateApart(identity)) {
    Ok(value: Ok(:final value)) => Ok(value),
    // The clock is outside the dates an OpenPGP key can hold.
    Ok(value: Err()) || Err() => const Err(RobotKeyComputeFailure()),
  };

  @override
  Future<
    Result<
      Result<CoordinatorRobot, RobotPgpKeyNotProven>,
      RobotKeyComputeFailure
    >
  >
  prove(UnprovenCoordinatorRobot robot) => _proveApart(robot);

  static Future<
    Result<Result<RobotPgpKey, PgpClockOutOfRange>, RobotKeyComputeFailure>
  >
  _generateApart(RobotIdentity identity) =>
      _run(() => RobotPgpKey.generate(identity));

  static Future<
    Result<
      Result<CoordinatorRobot, RobotPgpKeyNotProven>,
      RobotKeyComputeFailure
    >
  >
  _proveApart(UnprovenCoordinatorRobot robot) => _run(robot.prove);

  /// The result of [work], computed in a new isolate.
  static Future<Result<T, RobotKeyComputeFailure>> _run<T>(
    T Function() work,
  ) async {
    try {
      return Ok(await Isolate.run(work, debugName: 'robot key'));
    } on IsolateSpawnException {
      return const Err(RobotKeyComputeFailure());
    }
  }
}
