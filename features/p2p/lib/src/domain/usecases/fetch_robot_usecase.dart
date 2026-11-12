import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../network_garage_key.dart';
import '../p2p_failure.dart';
import '../repositories/robot_binding_repository.dart';
import '../robot_binding.dart';
import '../robot_key_compute_port.dart';

/// What one request of [FetchRobotUsecase] is for a robot: a first contact, which sends a key pair and creates the robot on a coordinator that does not know it, or a read back, which sends no key and creates nothing.
///
/// Creating a robot is always explicit: only a [RobotFirstContact] can.
sealed class RobotContact {
  const RobotContact();

  /// A first contact of [robot], whose key pair [FetchRobotUsecase] makes itself, once, and sends at every request made with this contact.
  static RobotFirstContact firstContact(NetworkRobot robot) =>
      RobotFirstContact._(robot);

  /// A read back of [robot], with the short header: no key is sent, and a coordinator that does not know the robot answers [RobotUnknown].
  static RobotReadBack readBack(NetworkRobot robot) => RobotReadBack._(robot);

  /// The robot the request is made for, with the network and the fingerprint of its key.
  NetworkRobot get robot;
}

/// A first contact of a robot: the request that sends the robot's key pair, and creates the robot on a coordinator that does not know it.
///
/// The pair is never given by a caller: [FetchRobotUsecase] makes it for this robot at the first request made with this contact, once the robot is bound, and sends that same pair at every later request made with it.
/// So a request sent again, after a busy answer, never hands the coordinator a second pair for the same robot, when the coordinator may have stored the first.
/// Use one contact for one request the user asked for, with its retries, and no longer: it holds the pair, locked by the robot's token.
final class RobotFirstContact extends RobotContact {
  @override
  final NetworkRobot robot;

  /// The pair being made, or made, for this contact, by [FetchRobotUsecase] only.
  Future<Result<RobotPgpKey, RobotKeyComputeFailure>>? _making;

  /// The pair this contact has sent, once it has.
  RobotPgpKey? _sent;

  RobotFirstContact._(this.robot);

  /// Whether [answer] carries the key pair this contact sent: its public key, compared by the fingerprints of its primary key and of its encryption subkey, since a coordinator returns it re-exported by GnuPG.
  ///
  /// A robot whose pair is another one existed on that coordinator before this first contact, as the coordinator says: made by another device or client, or by an earlier request whose answer was lost.
  /// It is false when this contact has sent no pair yet.
  bool sentThePairOf(CoordinatorRobot answer) =>
      _sent?.publicKey == answer.pgpKey.publicKey;
}

/// A read back of a robot, which sends no key and never creates it.
final class RobotReadBack extends RobotContact {
  @override
  final NetworkRobot robot;

  const RobotReadBack._(this.robot);
}

/// Makes a robot of this device known to a coordinator, or reads it back, and checks that the coordinator describes that very robot, only if the robot is bound to that coordinator.
///
/// The rule « one robot, one coordinator » of AGENTS.md is checked here, at every request, never in a screen: the token hash is the whole credential of a robot and the same on every coordinator.
/// Only `PutRobotOnCoordinatorUsecase` and `ReadRobotOnCoordinatorUsecase` call it, through the places of `RobotRequestLimiter`.
final class FetchRobotUsecase {
  final CoordinatorClient _client;
  final RobotBindingRepository _bindings;
  final RobotKeyComputePort _keys;

  const FetchRobotUsecase(this._client, this._bindings, this._keys);

  /// Whether [result], a result of [execute], is the transport's busy answer: it had no place for the request, which may be sent again later.
  static bool answeredBusy(
    Result<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure> result,
  ) => switch (result) {
    Ok(value: Err(failure: CoordinatorTransportBusy())) => true,
    _ => false,
  };

  /// `/api/robot/` of [coordinator] for the robot of [contact], on the network of the key it was derived from.
  ///
  /// The network and the key are read from the robot and never given apart, so a robot of the testnet key cannot be sent to a mainnet coordinator, nor checked against the bindings of another key.
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
  /// A [RobotFirstContact] is a first contact: once the binding is on disk, a new OpenPGP key pair is made for its robot away from the UI isolate, at the first request made with that contact only, and a coordinator that does not know the robot creates it with that pair and the Nostr key of the official client.
  /// The caller never gives the pair, so a first contact can only send a pair this use case has made for this very robot, locked by its token, and sends the same pair at each request made with the same contact.
  /// A [RobotReadBack] sends no key, and a coordinator that does not know the robot answers with a [RobotUnknown] failure.
  ///
  /// Either way the answer must be the robot of this device: another hash id or nickname is a [RobotMismatchFailure], found before any key is read.
  /// The robot comes back with the key pair the coordinator holds, still locked: the pair this first contact sent, taken as it is, or any other pair, which is taken only once the robot's token has proved it, away from the UI isolate, and is a [RobotPgpKeyNotProven] otherwise; a read sends no pair, so its pair is always proven.
  /// Nothing of a pair is ever adopted without that proof, and nothing is stored: the token is enough to read the robot back later.
  /// When the pair cannot be made, or the proof cannot be run, the outer [Err] is a [RobotKeyComputeFailure]: before a first contact nothing was sent; after an answer to prove, the request was sent and its answer is dropped.
  Future<Result<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure>>
  execute(Coordinator coordinator, RobotContact contact) async {
    final robot = contact.robot;
    final identity = CoordinatorIdentity.of(coordinator, robot.network);
    if (identity == null) return const Ok(Err(CoordinatorNotOnNetwork()));
    if (await _bindings.bind(robot.slot, identity) case Err(:final failure)) {
      return Err(failure);
    }
    final Result<CoordinatorRobotAnswer, CoordinatorFailure> answer;
    switch (contact) {
      case RobotFirstContact():
        final RobotPgpKey pgpKey;
        switch (await _pairOf(contact)) {
          case Ok(:final value):
            pgpKey = value;
          case Err(:final failure):
            return Err(failure);
        }
        contact._sent = pgpKey;
        answer = await _client.fetchRobot(
          coordinator,
          robot.network,
          identity: robot.identity,
          pgpKey: pgpKey,
        );
      case RobotReadBack():
        answer = await _client.fetchKnownRobot(
          coordinator,
          robot.network,
          identity: robot.identity,
        );
    }
    return switch (answer) {
      Err(:final failure) => Ok(Err(failure)),
      Ok(value: final CoordinatorRobot sent) => Ok(Ok(sent)),
      Ok(value: final UnprovenCoordinatorRobot unproven) => await _proven(
        unproven,
      ),
    };
  }

  /// The pair of [contact]: the one made for it at its first request, or a new one made now for its robot, away from the UI isolate.
  ///
  /// A pair that could not be made is not kept, so that a later request of the same contact tries again.
  Future<Result<RobotPgpKey, RobotKeyComputeFailure>> _pairOf(
    RobotFirstContact contact,
  ) async {
    final making = contact._making ??= _keys.generate(contact.robot.identity);
    final made = await making;
    if (made case Err() when identical(contact._making, making)) {
      contact._making = null;
    }
    return made;
  }

  /// The robot of [unproven] once its token has proved its pair, away from the UI isolate, as [execute] gives it.
  Future<Result<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure>>
  _proven(UnprovenCoordinatorRobot unproven) async =>
      switch (await _keys.prove(unproven)) {
        Ok(value: Ok(value: final proven)) => Ok(Ok(proven)),
        Ok(value: Err(:final failure)) => Ok(Err(failure)),
        Err(:final failure) => Err(failure),
      };
}
