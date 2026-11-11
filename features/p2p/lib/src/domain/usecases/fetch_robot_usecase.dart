import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// Makes a robot of this device known to a coordinator, or reads it back, and checks that the coordinator describes that very robot.
final class FetchRobotUsecase {
  final CoordinatorClient _client;

  const FetchRobotUsecase(this._client);

  /// `/api/robot/` of [coordinator] on [network] for the robot [identity], whose OpenPGP key pair on this device is [pgpKey].
  ///
  /// With [createIfUnknown], the request is a first contact: a coordinator that does not know the robot creates it, with [pgpKey] and the Nostr key of the official client.
  /// Without it, no key is sent and a coordinator that does not know the robot answers with a [RobotUnknown] failure.
  /// Either way the answer must be the robot of this device: another hash id, nickname or key pair is a [RobotMismatchFailure].
  Future<Result<CoordinatorRobot, CoordinatorFailure>> execute(
    Coordinator coordinator,
    RobosatsNetwork network, {
    required RobotIdentity identity,
    required RobotPgpKey pgpKey,
    required bool createIfUnknown,
  }) => createIfUnknown
      ? _client.fetchRobot(
          coordinator,
          network,
          identity: identity,
          pgpKey: pgpKey,
        )
      : _client.fetchKnownRobot(
          coordinator,
          network,
          identity: identity,
          pgpKey: pgpKey,
        );
}
