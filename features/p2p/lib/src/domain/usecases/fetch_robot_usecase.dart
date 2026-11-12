import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../network_garage_key.dart';
import '../p2p_failure.dart';
import '../repositories/robot_binding_repository.dart';
import '../robot_binding.dart';

/// Makes a robot of this device known to a coordinator, or reads it back, and checks that the coordinator describes that very robot, only if the robot is bound to that coordinator.
///
/// The rule « one robot, one coordinator » of AGENTS.md is checked here, at every request, never in a screen: the token hash is the whole credential of a robot and the same on every coordinator.
final class FetchRobotUsecase {
  final CoordinatorClient _client;
  final RobotBindingRepository _bindings;

  const FetchRobotUsecase(this._client, this._bindings);

  /// `/api/robot/` of [coordinator] for [robot], on the network of the key it was derived from, whose OpenPGP key pair on this device is [pgpKey].
  ///
  /// The network and the key are read from [robot] and never given apart, so a robot of the testnet key cannot be sent to a mainnet coordinator, nor checked against the bindings of another key.
  ///
  /// Before anything is sent, the binding of the robot is read, and written when the robot has none and its key was drawn on this device; the request leaves only once the binding is on disk.
  /// Both kinds of request send the token hash, so both bind.
  /// A refusal is the outer [Err], a [P2pFailure], and nothing was sent: a robot bound to another coordinator, or to one whose onion address or keys changed since, or without a binding while its key's history is unknown, or a database that cannot be read.
  /// A coordinator without an onion address on the network of the robot gets nothing, binding included, and gives a [CoordinatorNotOnNetwork].
  /// Otherwise the inner result is what the coordinator answered.
  ///
  /// A binding is never undone, whatever the request gives: the token hash may have reached the coordinator even when the request failed.
  /// A crash between the write and the request leaves a binding to a coordinator that has no such robot yet, which only restricts the robot to that coordinator.
  /// A [RobotNicknameTaken] (error 7004) leaves the robot bound to [coordinator]: as `CoordinatorClient.fetchRobot` says, the caller asks again later, then moves on to the next index for that coordinator, so a coordinator that answers it for ever only uses up indexes bound to itself.
  ///
  /// With [createIfUnknown], the request is a first contact: a coordinator that does not know the robot creates it, with [pgpKey] and the Nostr key of the official client.
  /// Without it, no key is sent and a coordinator that does not know the robot answers with a [RobotUnknown] failure.
  /// Either way the answer must be the robot of this device: another hash id, nickname or key pair is a [RobotMismatchFailure].
  Future<Result<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure>>
  execute(
    Coordinator coordinator,
    NetworkRobot robot, {
    required RobotPgpKey pgpKey,
    required bool createIfUnknown,
  }) async {
    final identity = CoordinatorIdentity.of(coordinator, robot.network);
    if (identity == null) return const Ok(Err(CoordinatorNotOnNetwork()));
    if (await _bindings.bind(robot.slot, identity) case Err(:final failure)) {
      return Err(failure);
    }
    return Ok(
      await (createIfUnknown
          ? _client.fetchRobot(
              coordinator,
              robot.network,
              identity: robot.identity,
              pgpKey: pgpKey,
            )
          : _client.fetchKnownRobot(
              coordinator,
              robot.network,
              identity: robot.identity,
              pgpKey: pgpKey,
            )),
    );
  }
}
