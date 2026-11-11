import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show GarageRobot, RobosatsNetwork;

import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';

/// The first robot of the Garage Key stored for a network that a coordinator can be contacted with.
///
/// It holds the token of that robot: keep it no longer than the requests made for it, and never in the state of a cubit.
final class DeriveFirstRobotUsecase {
  final GarageKeyRepository _repository;

  const DeriveFirstRobotUsecase(this._repository);

  @useResult
  Future<Result<GarageRobot, P2pFailure>> execute(RobosatsNetwork network) =>
      _repository.firstUsableRobot(network);
}
