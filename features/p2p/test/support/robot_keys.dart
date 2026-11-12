import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_key_compute_port.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// The key work of a robot done on the test's own isolate, with every call kept: the stand-in for `IsolateRobotKeyCompute`.
///
/// `generate` gives [pair], a pair the test made once, since making one hashes 32 MiB, or [generateFailure]; `prove` proves as the package proves, or gives [proveFailure].
final class RecordingRobotKeys implements RobotKeyComputePort {
  final RobotPgpKey pair;
  final List<RobotIdentity> generated = [];
  final List<UnprovenCoordinatorRobot> proved = [];
  RobotKeyComputeFailure? generateFailure;
  RobotKeyComputeFailure? proveFailure;

  /// Runs as each pair is asked for, before it is given.
  void Function()? onGenerate;

  RecordingRobotKeys(this.pair);

  @override
  Future<Result<RobotPgpKey, RobotKeyComputeFailure>> generate(
    RobotIdentity identity,
  ) async {
    generated.add(identity);
    onGenerate?.call();
    return switch (generateFailure) {
      final failure? => Err(failure),
      null => Ok(pair),
    };
  }

  @override
  Future<
    Result<
      Result<CoordinatorRobot, RobotPgpKeyNotProven>,
      RobotKeyComputeFailure
    >
  >
  prove(UnprovenCoordinatorRobot robot) async {
    proved.add(robot);
    return switch (proveFailure) {
      final failure? => Err(failure),
      null => Ok(robot.prove()),
    };
  }
}
