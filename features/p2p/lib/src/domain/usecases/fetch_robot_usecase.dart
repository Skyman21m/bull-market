import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../network_garage_key.dart';

/// Makes a robot of this device known to a coordinator, or reads it back, and checks that the coordinator describes that very robot.
final class FetchRobotUsecase {
  final CoordinatorClient _client;

  const FetchRobotUsecase(this._client);

  /// `/api/robot/` of [coordinator] for [robot], on the network of the key it was derived from, whose OpenPGP key pair on this device is [pgpKey].
  ///
  /// The network is read from [robot] and never given apart, so a robot of the testnet key cannot be sent to a mainnet coordinator.
  ///
  /// With [createIfUnknown], the request is a first contact: a coordinator that does not know the robot creates it, with [pgpKey] and the Nostr key of the official client.
  /// Without it, no key is sent and a coordinator that does not know the robot answers with a [RobotUnknown] failure.
  /// Either way the answer must be the robot of this device: another hash id, nickname or key pair is a [RobotMismatchFailure].
  Future<Result<CoordinatorRobot, CoordinatorFailure>> execute(
    Coordinator coordinator,
    NetworkRobot robot, {
    required RobotPgpKey pgpKey,
    required bool createIfUnknown,
  }) => createIfUnknown
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
        );
}
