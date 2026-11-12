import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../network_garage_key.dart';
import '../p2p_failure.dart';
import '../repositories/robot_binding_repository.dart';
import '../robot_binding.dart';
import '../robot_key_compute_port.dart';

/// Makes a robot of this device known to a coordinator, or reads it back, and checks that the coordinator describes that very robot, only if the robot is bound to that coordinator.
///
/// The rule « one robot, one coordinator » of AGENTS.md is checked here, at every request, never in a screen: the token hash is the whole credential of a robot and the same on every coordinator.
final class FetchRobotUsecase {
  final CoordinatorClient _client;
  final RobotBindingRepository _bindings;
  final RobotKeyComputePort _keys;

  const FetchRobotUsecase(this._client, this._bindings, this._keys);

  /// `/api/robot/` of [coordinator] for [robot], on the network of the key it was derived from.
  ///
  /// The network and the key are read from [robot] and never given apart, so a robot of the testnet key cannot be sent to a mainnet coordinator, nor checked against the bindings of another key.
  /// A robot index has one binding whatever the network, since its token hash is the same on both.
  ///
  /// Before anything is sent, the binding of the robot is read, and written when the robot has none and its key was drawn on this device; the request leaves only once the binding is on disk.
  /// Both kinds of request send the token hash, so both bind.
  /// A refusal is the outer [Err], a [P2pFailure], and nothing was sent: a robot bound to another coordinator, on either network, or to one whose onion address or keys changed since, or without a binding while its key's history is unknown, or a database that cannot be read.
  /// An [Error] from the database or from the directory the shell gave, a bug by rule 11 of AGENTS.md, is not caught: the call throws, and nothing is sent either.
  /// A coordinator without an onion address on the network of the robot gets nothing, binding included, and gives a [CoordinatorNotOnNetwork].
  /// Otherwise the inner result is what the coordinator answered, checked.
  ///
  /// A binding is never undone, whatever the request gives: the token hash may have reached the coordinator even when the request failed.
  /// A crash between the write and the request leaves a binding to a coordinator that has no such robot yet, which only restricts the robot to that coordinator.
  /// A [RobotNicknameTaken] (error 7004) leaves the robot bound to [coordinator]: as `CoordinatorClient.fetchRobot` says, the caller asks again later, then moves on to the next index for that coordinator, so a coordinator that answers it for ever only uses up indexes bound to itself.
  ///
  /// With [createIfUnknown], the request is a first contact: once the binding is on disk, a new OpenPGP key pair is made for [robot] away from the UI isolate, and a coordinator that does not know the robot creates it with that pair and the Nostr key of the official client.
  /// The caller never gives the pair, so a first contact can only send a pair this use case has just made for this very robot, locked by its token.
  /// Without [createIfUnknown], no key is sent and a coordinator that does not know the robot answers with a [RobotUnknown] failure.
  ///
  /// Either way the answer must be the robot of this device: another hash id or nickname is a [RobotMismatchFailure], found before any key is read.
  /// The robot comes back with the key pair the coordinator holds, still locked: the pair this first contact sent, taken as it is, or any other pair, which is taken only once the robot's token has proved it, away from the UI isolate, and is a [RobotPgpKeyNotProven] otherwise; a read sends no pair, so its pair is always proven.
  /// Nothing of a pair is ever adopted without that proof, and nothing is stored: the token is enough to read the robot back later.
  /// When the pair cannot be made, or the proof cannot be run, the outer [Err] is a [RobotKeyComputeFailure]: before a first contact nothing was sent; after an answer to prove, the request was sent and its answer is dropped.
  Future<Result<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure>>
  execute(
    Coordinator coordinator,
    NetworkRobot robot, {
    required bool createIfUnknown,
  }) async {
    final identity = CoordinatorIdentity.of(coordinator, robot.network);
    if (identity == null) return const Ok(Err(CoordinatorNotOnNetwork()));
    if (await _bindings.bind(robot.slot, identity) case Err(:final failure)) {
      return Err(failure);
    }
    final Result<CoordinatorRobotAnswer, CoordinatorFailure> answer;
    if (createIfUnknown) {
      final RobotPgpKey pgpKey;
      switch (await _keys.generate(robot.identity)) {
        case Ok(:final value):
          pgpKey = value;
        case Err(:final failure):
          return Err(failure);
      }
      answer = await _client.fetchRobot(
        coordinator,
        robot.network,
        identity: robot.identity,
        pgpKey: pgpKey,
      );
    } else {
      answer = await _client.fetchKnownRobot(
        coordinator,
        robot.network,
        identity: robot.identity,
      );
    }
    return switch (answer) {
      Err(:final failure) => Ok(Err(failure)),
      Ok(value: final CoordinatorRobot sent) => Ok(Ok(sent)),
      Ok(value: final UnprovenCoordinatorRobot unproven) => switch (await _keys
          .prove(unproven)) {
        Ok(value: Ok(value: final proven)) => Ok(Ok(proven)),
        Ok(value: Err(:final failure)) => Ok(Err(failure)),
        Err(:final failure) => Err(failure),
      },
    };
  }
}
