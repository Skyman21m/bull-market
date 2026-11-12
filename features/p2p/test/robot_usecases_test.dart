import 'dart:convert';

import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/domain/coordinator_sessions_port.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/usecases/close_robot_sessions_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/robot_bindings.dart';

/// A coordinator that answers every request with [answer], or the transport [failure], and keeps what it received; [onSend] runs as each request leaves.
final class _RobotTransport implements CoordinatorTransport {
  final List<CoordinatorRequest> requests = [];
  CoordinatorResponse answer;
  CoordinatorTransportFailure? failure;
  Future<void> Function()? onSend;

  _RobotTransport(this.answer);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    await onSend?.call();
    requests.add(request);
    return switch (failure) {
      final failure? => Err(failure),
      null => Ok(answer),
    };
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
    late RobotBindingRepositoryImpl bindings;
    late FetchRobotUsecase usecase;

    setUp(() async {
      transport = _RobotTransport(_json(200, robot()));
      bindings = bindingsInMemory();
      usecase = FetchRobotUsecase(CoordinatorClient(transport), bindings);
      // The test key, as if this device had drawn it for both networks.
      for (final network in RobosatsNetwork.values) {
        expect(
          await bindings.recordGeneratedKey(
            network,
            networkRobot.keyFingerprint,
          ),
          isA<Ok<void, P2pFailure>>(),
        );
      }
    });

    Future<Result<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure>>
    execute({
      required bool createIfUnknown,
      Coordinator? to,
      NetworkRobot? as,
    }) => usecase.execute(
      to ?? temple,
      as ?? networkRobot,
      pgpKey: pgpKey,
      createIfUnknown: createIfUnknown,
    );

    /// The answer of the coordinator, once the binding let the request leave.
    Result<CoordinatorRobot, CoordinatorFailure> answered(
      Result<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure> result,
    ) => switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => fail('refused before any request: $failure'),
    };

    Matcher refusedWith<T>() =>
        isA<Err<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure>>()
            .having((err) => err.failure, 'failure', isA<T>());

    test(
      'makes a first contact, with the Nostr key of the official client',
      () async {
        final result = answered(await execute(createIfUnknown: true));

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

      final result = answered(await execute(createIfUnknown: false));

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
        answered(
          await execute(createIfUnknown: createIfUnknown, as: mainnetRobot),
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
      final result = answered(await execute(createIfUnknown: false));

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
          answered(await execute(createIfUnknown: createIfUnknown)),
          isA<Err<CoordinatorRobot, CoordinatorFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<RobotMismatchFailure>(),
          ),
        );
      }
    });

    group('one robot, one coordinator:', () {
      final lake = coordinator('lake');

      test(
        'the binding is on disk before the request leaves, and for every kind of request',
        () async {
          for (final (index, createIfUnknown) in [(0, true), (1, false)]) {
            final robot = _robotAt(index, network);
            transport.onSend = () async {
              // A second coordinator is refused from inside the first request: the binding is already written.
              expect(
                await bindings.bind(
                  robot.slot,
                  CoordinatorIdentity.of(lake, network) ??
                      fail('lake is not on testnet'),
                ),
                isA<Err<void, P2pFailure>>().having(
                  (err) => err.failure,
                  'failure',
                  isA<RobotBoundToAnotherCoordinatorFailure>(),
                ),
              );
            };
            await execute(createIfUnknown: createIfUnknown, as: robot);
          }

          expect(transport.requests, hasLength(2));
        },
      );

      test(
        'a robot bound to a coordinator never reaches another one',
        () async {
          answered(await execute(createIfUnknown: true));
          transport.requests.clear();

          for (final createIfUnknown in [true, false]) {
            expect(
              await execute(createIfUnknown: createIfUnknown, to: lake),
              refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
            );
          }
          expect(transport.requests, isEmpty);
          // Its coordinator still gets it, and the next robot is free.
          answered(await execute(createIfUnknown: false));
          answered(
            await execute(
              createIfUnknown: true,
              to: lake,
              as: _robotAt(1, network),
            ),
          );
          expect(transport.requests.map((request) => request.url.host), [
            hostOf('temple', network),
            hostOf('lake', network),
          ]);
        },
      );

      test(
        'two first contacts at once to two coordinators: one request leaves',
        () async {
          final results = await Future.wait([
            execute(createIfUnknown: true),
            execute(createIfUnknown: true, to: lake),
          ]);

          expect(transport.requests, hasLength(1));
          expect(
            results.whereType<Err<Object, P2pFailure>>().single.failure,
            isA<RobotBoundToAnotherCoordinatorFailure>(),
          );
        },
      );

      test(
        'a robot of a key whose history is unknown is neither bound nor sent',
        () async {
          final unknown = bindingsInMemory();
          final refusing = FetchRobotUsecase(
            CoordinatorClient(transport),
            unknown,
          );

          for (final createIfUnknown in [true, false]) {
            expect(
              await refusing.execute(
                temple,
                networkRobot,
                pgpKey: pgpKey,
                createIfUnknown: createIfUnknown,
              ),
              refusedWith<RobotHistoryUnknownFailure>(),
            );
          }
          expect(transport.requests, isEmpty);
        },
      );

      test(
        'a database whose directory throws an Error: the call throws, and nothing is sent',
        () async {
          // An Error is a bug (AGENTS.md, rule 11): it is not turned into a failure, and the request never leaves.
          final broken = FetchRobotUsecase(
            CoordinatorClient(transport),
            bindingsInMemory(
              database: P2pDatabase.open(
                () async => throw StateError('no directory'),
              ),
            ),
          );

          await expectLater(
            broken.execute(
              temple,
              networkRobot,
              pgpKey: pgpKey,
              createIfUnknown: true,
            ),
            throwsA(isA<StateError>()),
          );
          expect(transport.requests, isEmpty);
        },
      );

      test('a database that fails sends nothing', () async {
        final failing = FetchRobotUsecase(
          CoordinatorClient(transport),
          RecordingBindings(failure: const P2pStorageFailure()),
        );

        expect(
          await failing.execute(
            temple,
            networkRobot,
            pgpKey: pgpKey,
            createIfUnknown: true,
          ),
          refusedWith<P2pStorageFailure>(),
        );
        expect(transport.requests, isEmpty);
      });

      test(
        'a coordinator that is not on the network gets nothing, binding included',
        () async {
          final recording = RecordingBindings();
          final checked = FetchRobotUsecase(
            CoordinatorClient(transport),
            recording,
          );

          final result = await checked.execute(
            coordinator('bazaar'),
            networkRobot,
            pgpKey: pgpKey,
            createIfUnknown: true,
          );

          expect(
            answered(result),
            isA<Err<CoordinatorRobot, CoordinatorFailure>>().having(
              (err) => err.failure,
              'failure',
              isA<CoordinatorNotOnNetwork>(),
            ),
          );
          expect(recording.calls, isEmpty);
          expect(transport.requests, isEmpty);
        },
      );

      test(
        'a nickname taken (7004) leaves the robot bound to that coordinator',
        () async {
          transport.answer = _json(409, {
            'error_code': 7004,
            'bad_request': 'This nickname is already taken',
          });

          expect(
            answered(await execute(createIfUnknown: true)),
            isA<Err<CoordinatorRobot, CoordinatorFailure>>().having(
              (err) => err.failure,
              'failure',
              isA<RobotNicknameTaken>(),
            ),
          );
          final sent = transport.requests.length;

          expect(
            await execute(createIfUnknown: true, to: lake),
            refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
          );
          expect(transport.requests, hasLength(sent));
        },
      );

      test('a request that failed leaves the binding as well', () async {
        transport.failure = const CoordinatorUnreachable();

        expect(
          answered(await execute(createIfUnknown: true)),
          isA<Err<CoordinatorRobot, CoordinatorFailure>>(),
        );
        expect(
          await execute(createIfUnknown: true, to: lake),
          refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
        );
      });
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
