import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';

import '../network_garage_key.dart';
import '../p2p_failure.dart';
import '../repositories/robot_binding_repository.dart';
import '../robot_binding.dart';

/// Where a robot of this device stands, read from the feature's database only: the coordinator its index is bound to, with the provenance of that binding, or none, and the history of its key on the robot's network.
///
/// It is the Garage's local read of a robot, at each display: it sends nothing and writes nothing.
final class ReadRobotStandingUsecase {
  final RobotBindingRepository _bindings;

  const ReadRobotStandingUsecase(this._bindings);

  /// The standing of [robot], on the network of the key it was derived from, which [robot] carries with the key's fingerprint and never gives apart.
  ///
  /// The standing holds none of the robot's token, key or fingerprint.
  /// A database that cannot be read is a [P2pStorageFailure].
  @useResult
  Future<Result<RobotStanding, P2pFailure>> execute(NetworkRobot robot) =>
      _bindings.standingOf(robot.slot);
}
