// Ways to reach a robot request, a robot credential, a raw network client, a binding or the work on a robot's key pair that a check reading method-call names alone misses, for `test/robot_bindings_architecture_test.dart`: each one must be found, in the declaration it is in.
// The placements of the reviews of #60 are among them: a tear-off, an extension, a raw request with the token hash, and a call through an explicit `as dynamic` cast, which `avoid_dynamic_calls` lets through (it refuses a call on an implicitly dynamic value only).
// Never imported by the feature; the analyzer resolves it in that test only.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:primitives/primitives.dart';
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

/// A robot request in an extension of the client.
extension ReviewPeek on CoordinatorClient {
  Future<Result<UnprovenCoordinatorRobot, CoordinatorFailure>> reviewPeek(
    Coordinator coordinator,
    NetworkRobot robot,
  ) => fetchKnownRobot(coordinator, robot.network, identity: robot.identity);
}

/// The token hash sent over a raw HTTP client, with no member of the coordinator client.
Future<Object?> rawRequest(NetworkRobot robot, String onion) =>
    Dio().get<Object?>(
      '$onion/api/robot/',
      options: Options(
        headers: {'Authorization': 'Token ${robot.identity.tokenSha256Base91}'},
      ),
    );

/// The other credentials of a robot, read.
List<Object> credentials(RobotIdentity identity) => [
  identity.token,
  identity.tokenSha256Hex,
  identity.token.reveal(),
];

/// The call of the second review of #60, through an explicit `as dynamic` cast: no member is resolved, and the lint lets it through.
Future<Object?> dynamicCall(
  Object client,
  Coordinator coordinator,
  NetworkRobot robot,
) async => await (client as dynamic).fetchKnownRobot(
  coordinator,
  robot.network,
  identity: robot.identity,
);

/// The HTTP client of `dart:io`, declared in `dart:_http` (third review of #60).
Future<void> rawHttpClient(String onion) async {
  final client = HttpClient();
  await (await client.getUrl(Uri.parse('$onion/api/robot/'))).close();
}

/// The websocket of `dart:io`, declared in `dart:_http`: the route of the chat to come.
Future<Object> rawWebSocket(String onion) =>
    WebSocket.connect('$onion/ws/chat/');

/// A socket of `dart:io`.
Future<Object> rawSocket(String host) => Socket.connect(host, 80);

/// A process that could send the request itself.
Future<Object> rawProcess(String url) => Process.run('curl', [url]);

/// A raw request to a coordinator, which could carry either header.
Object sendRaw(CoordinatorTransport transport, CoordinatorRequest request) =>
    transport.send(request);

/// A binding, torn off.
Object bindByTearOff(RobotBindingRepository bindings) => bindings.bind;

/// The acknowledgement of a key's unknown history, torn off.
Object acknowledgeByTearOff(RobotBindingRepository bindings) =>
    bindings.recordAcknowledgedKey;

/// A robot proven on the calling isolate, torn off.
Object proveByTearOff(UnprovenCoordinatorRobot robot) => robot.prove;

/// A pair made on the calling isolate, torn off.
Object generateByTearOff() => RobotPgpKey.generate;
