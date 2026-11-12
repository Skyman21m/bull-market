// Ways to reach a robot request, a robot credential or a binding that a check reading method-call names alone misses, for `test/robot_bindings_architecture_test.dart`: each one must be found.
// Never imported by the feature; the analyzer resolves it in that test only.
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:robosats/robosats.dart' as robosats;
import 'package:robosats/robosats.dart';

/// The tear-off of the review of #60: a request that no binding precedes, called through a variable.
Object fetchByTearOff(CoordinatorClient client) => client.fetchKnownRobot;

/// A first contact in a cascade.
Object fetchInCascade(
  CoordinatorClient client,
  Coordinator coordinator,
  NetworkRobot robot,
  RobotPgpKey pgpKey,
) => client
  ..fetchRobot(
    coordinator,
    robot.network,
    identity: robot.identity,
    pgpKey: pgpKey,
  );

/// The credential of a robot, torn off through a prefixed type.
Object headerByTearOff(robosats.RobotIdentity identity) =>
    identity.authorizationHeader;

/// The credential of a first contact, torn off.
Object firstContactByTearOff(RobotIdentity identity) =>
    identity.firstContactAuthorizationHeader;

/// A raw request to a coordinator, which could carry either header.
Object sendRaw(CoordinatorTransport transport, CoordinatorRequest request) =>
    transport.send(request);

/// A binding, torn off.
Object bindByTearOff(RobotBindingRepository bindings) => bindings.bind;
