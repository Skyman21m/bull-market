import 'dart:convert';

import 'package:p2p/src/domain/coordinator_sessions_port.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/usecases/close_robot_sessions_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

/// A coordinator that answers every request with [answer], and keeps what it received.
final class _RobotTransport implements CoordinatorTransport {
  final List<CoordinatorRequest> requests = [];
  CoordinatorResponse answer;

  _RobotTransport(this.answer);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    requests.add(request);
    return Ok(answer);
  }
}

final class _RecordingSessions implements CoordinatorSessionsPort {
  final List<RobotSessionKey> closedRobots = [];
  int closedAll = 0;

  @override
  Future<void> closeSessions() async => closedAll++;

  @override
  Future<void> closeRobotSessions(RobotSessionKey robot) async =>
      closedRobots.add(robot);
}

CoordinatorResponse _json(int status, Object body) => CoordinatorResponse(
  statusCode: status,
  headers: const {'content-type': 'application/json'},
  body: utf8.encode(jsonEncode(body)),
);

/// A Garage Key made for these tests only.
final GarageKey _garageKey = switch (GarageKey.fromBytes(
  utf8.encode('a Garage Key of the p2p tests...'),
)) {
  Ok(:final value) => value,
  Err(:final failure) => throw StateError('$failure'),
};

NetworkRobot _robotAt(int index, RobosatsNetwork network) =>
    switch (NetworkGarageKey(network, _garageKey).firstUsableRobot(index)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };

RobotIdentity _identityAt(int index) =>
    _robotAt(index, RobosatsNetwork.testnet).identity;

void main() {
  const network = RobosatsNetwork.testnet;
  final temple = coordinator('temple');
  final networkRobot = _robotAt(0, network);
  final identity = networkRobot.identity;
  final pgpKey = switch (RobotPgpKey.generate(identity)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  Map<String, Object?> robot() => {
    'nickname': identity.nickname,
    'hash_id': identity.hashId.hex,
    'public_key': pgpKey.publicKey.armored,
    'encrypted_private_key': pgpKey.encryptedPrivateKeyArmored,
    'nostr_pubkey': identity.nostrKeyPair().publicKeyHex,
    'earned_rewards': 0,
    'wants_stealth': true,
  };

  group('FetchRobotUsecase', () {
    late _RobotTransport transport;
    late FetchRobotUsecase usecase;

    setUp(() {
      transport = _RobotTransport(_json(200, robot()));
      usecase = FetchRobotUsecase(CoordinatorClient(transport));
    });

    Future<Result<CoordinatorRobot, CoordinatorFailure>> execute({
      required bool createIfUnknown,
    }) => usecase.execute(
      temple,
      networkRobot,
      pgpKey: pgpKey,
      createIfUnknown: createIfUnknown,
    );

    test(
      'makes a first contact, with the Nostr key of the official client',
      () async {
        final result = await execute(createIfUnknown: true);

        expect(
          result,
          isA<Ok<CoordinatorRobot, CoordinatorFailure>>()
              .having((ok) => ok.value.hashId, 'hashId', identity.hashId)
              .having(
                (ok) => ok.value.nostrKeyDerivation,
                'nostrKeyDerivation',
                NostrKeyDerivation.currentFrontend,
              ),
        );
        final request = transport.requests.single;
        expect(request.url.host, hostOf('temple', network));
        expect(request.url.path, '/api/robot/');
        expect(request.robot, identity.sessionKey);
        final parts = (request.headers['Authorization'] ?? '').split(' | ');
        expect(parts, hasLength(4));
        expect(parts.first, identity.authorizationHeader());
        expect(parts.last, 'Nostr ${identity.nostrKeyPair().publicKeyHex}');
      },
    );

    test('sends no key when it must not create the robot', () async {
      transport.answer = _json(400, {
        'error_code': 7001,
        'bad_request': 'On the first request…',
      });

      final result = await execute(createIfUnknown: false);

      expect(
        result,
        isA<Err<CoordinatorRobot, CoordinatorFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<RobotUnknown>(),
        ),
      );
      final request = transport.requests.single;
      expect(request.headers['Authorization'], identity.authorizationHeader());
      expect(request.robot, identity.sessionKey);
    });

    test('asks on the network of the key the robot comes from', () async {
      // The same robot, derived from the same bytes kept as the mainnet key.
      final mainnetRobot = _robotAt(0, RobosatsNetwork.mainnet);
      expect(mainnetRobot.identity, identity);

      for (final createIfUnknown in [true, false]) {
        await usecase.execute(
          temple,
          mainnetRobot,
          pgpKey: pgpKey,
          createIfUnknown: createIfUnknown,
        );
      }

      expect(transport.requests.map((request) => request.url.host), [
        hostOf('temple', RobosatsNetwork.mainnet),
        hostOf('temple', RobosatsNetwork.mainnet),
      ]);
      expect(
        hostOf('temple', RobosatsNetwork.mainnet),
        isNot(hostOf('temple', network)),
      );
    });

    test('reads a known robot without creating it', () async {
      final result = await execute(createIfUnknown: false);

      expect(result, isA<Ok<CoordinatorRobot, CoordinatorFailure>>());
    });

    test('gives a mismatch as a failure, never the robot', () async {
      final other = _identityAt(1);
      transport.answer = _json(200, {
        ...robot(),
        'hash_id': other.hashId.hex,
        'nickname': other.nickname,
      });

      for (final createIfUnknown in [true, false]) {
        expect(
          await execute(createIfUnknown: createIfUnknown),
          isA<Err<CoordinatorRobot, CoordinatorFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<RobotMismatchFailure>(),
          ),
        );
      }
    });
  });

  group('CloseRobotSessionsUsecase', () {
    test('closes the sessions of that robot, and only those', () async {
      final sessions = _RecordingSessions();

      await CloseRobotSessionsUsecase(sessions).execute(identity);

      expect(sessions.closedRobots, [identity.sessionKey]);
      expect(sessions.closedRobots.single, isNot(_identityAt(1).sessionKey));
      expect(sessions.closedAll, 0);
    });
  });
}
