import 'dart:async';
import 'dart:convert';

import 'package:p2p/src/data/isolate_robot_key_compute.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/domain/coordinator_sessions_port.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/usecases/close_robot_sessions_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/robot_bindings.dart';
import 'support/robot_keys.dart';

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
  // Another pair of the same robot, as a second device would make.
  final otherPgpKey = switch (RobotPgpKey.generate(identity)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  // The pair of the next robot, locked by its token.
  final otherRobotPgpKey = switch (RobotPgpKey.generate(_identityAt(1))) {
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
    late RecordingRobotKeys keys;
    late FetchRobotUsecase usecase;

    setUp(() async {
      transport = _RobotTransport(_json(200, robot()));
      bindings = bindingsInMemory();
      keys = RecordingRobotKeys(pgpKey);
      usecase = FetchRobotUsecase(CoordinatorClient(transport), bindings, keys);
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
        // The pair sent is the one the use case had made for this robot, and it came back as sent: no proof ran.
        expect(keys.generated, [identity]);
        expect(parts[1], 'Public ${pgpArmorToWire(pgpKey.publicKey.armored)}');
        expect(
          parts[2],
          'Private ${pgpArmorToWire(pgpKey.encryptedPrivateKeyArmored)}',
        );
        expect(keys.proved, isEmpty);
        final robot = switch (result) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(robot.pgpKey, same(pgpKey));
        expect(robot.pgpKeyProven, isFalse);
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

    test(
      'reads a known robot without creating it, with nothing held: its pair is proven',
      () async {
        final result = answered(await execute(createIfUnknown: false));

        final robot = switch (result) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        // No pair is made or sent for a read, and the pair the coordinator holds went through the port to be proven.
        expect(keys.generated, isEmpty);
        expect(keys.proved, hasLength(1));
        expect(keys.proved.single.hashId, identity.hashId);
        expect(robot.pgpKeyProven, isTrue);
        expect(robot.pgpKey, pgpKey);
      },
    );

    test(
      'a first contact answered with another pair of the robot is proven, through the port',
      () async {
        // The robot existed with the pair `pgpKey`; this first contact sends another one, which the coordinator ignores.
        keys = RecordingRobotKeys(otherPgpKey);
        usecase = FetchRobotUsecase(
          CoordinatorClient(transport),
          bindings,
          keys,
        );

        final result = answered(await execute(createIfUnknown: true));

        expect(keys.generated, [identity]);
        expect(keys.proved, hasLength(1));
        expect(
          result,
          isA<Ok<CoordinatorRobot, CoordinatorFailure>>()
              .having((ok) => ok.value.pgpKey, 'pgpKey', pgpKey)
              .having((ok) => ok.value.pgpKeyProven, 'pgpKeyProven', isTrue),
        );
      },
    );

    test(
      'gives a pair its token does not prove as a failure, never the robot',
      () async {
        // The pair of the next robot, under the hash id and nickname of this one: locked by another token.
        transport.answer = _json(200, {
          ...robot(),
          'public_key': otherRobotPgpKey.publicKey.armored,
          'encrypted_private_key': otherRobotPgpKey.encryptedPrivateKeyArmored,
        });

        for (final createIfUnknown in [true, false]) {
          expect(
            answered(await execute(createIfUnknown: createIfUnknown)),
            isA<Err<CoordinatorRobot, CoordinatorFailure>>().having(
              (err) => err.failure,
              'failure',
              isA<RobotPgpKeyNotProven>(),
            ),
            reason: 'createIfUnknown: $createIfUnknown',
          );
        }
        expect(keys.proved, hasLength(2));
      },
    );

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
      // Refused on the hash id, before any key of the answer is read: nothing goes to be proven.
      expect(keys.proved, isEmpty);
    });

    group('the key work:', () {
      test(
        'the pair of a first contact is made after the binding and before the request',
        () async {
          final order = <String>[];
          final recording = RecordingBindings();
          final ordered = FetchRobotUsecase(
            CoordinatorClient(transport),
            _OrderedBindings(recording, order),
            keys,
          );
          keys.onGenerate = () => order.add('generate');
          transport.onSend = () async => order.add('send');

          answered(
            await ordered.execute(temple, networkRobot, createIfUnknown: true),
          );
          answered(
            await ordered.execute(temple, networkRobot, createIfUnknown: false),
          );

          expect(order, ['bind', 'generate', 'send', 'bind', 'send']);
        },
      );

      test('a robot refused by its binding costs no key work', () async {
        final refusing = FetchRobotUsecase(
          CoordinatorClient(transport),
          RecordingBindings(failure: const RobotHistoryUnknownFailure()),
          keys,
        );

        for (final createIfUnknown in [true, false]) {
          expect(
            await refusing.execute(
              temple,
              networkRobot,
              createIfUnknown: createIfUnknown,
            ),
            refusedWith<RobotHistoryUnknownFailure>(),
          );
        }
        expect(keys.generated, isEmpty);
        expect(keys.proved, isEmpty);
        expect(transport.requests, isEmpty);
      });

      test(
        'a pair that cannot be made sends nothing, and the binding stays',
        () async {
          keys.generateFailure = const RobotKeyComputeFailure();

          expect(
            await execute(createIfUnknown: true),
            refusedWith<RobotKeyComputeFailure>(),
          );
          expect(transport.requests, isEmpty);
          expect(
            await execute(createIfUnknown: true, to: coordinator('lake')),
            refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
          );
        },
      );

      test(
        'a proof that cannot run drops the answer, which was received',
        () async {
          keys.proveFailure = const RobotKeyComputeFailure();

          expect(
            await execute(createIfUnknown: false),
            refusedWith<RobotKeyComputeFailure>(),
          );
          expect(transport.requests, hasLength(1));
          expect(keys.proved, hasLength(1));
        },
      );
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
            keys,
          );

          for (final createIfUnknown in [true, false]) {
            expect(
              await refusing.execute(
                temple,
                networkRobot,
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
            keys,
          );

          await expectLater(
            broken.execute(temple, networkRobot, createIfUnknown: true),
            throwsA(isA<StateError>()),
          );
          expect(transport.requests, isEmpty);
          expect(keys.generated, isEmpty);
        },
      );

      test('a database that fails sends nothing', () async {
        final failing = FetchRobotUsecase(
          CoordinatorClient(transport),
          RecordingBindings(failure: const P2pStorageFailure()),
          keys,
        );

        expect(
          await failing.execute(temple, networkRobot, createIfUnknown: true),
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
            keys,
          );

          final result = await checked.execute(
            coordinator('bazaar'),
            networkRobot,
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

  group('IsolateRobotKeyCompute', () {
    const compute = IsolateRobotKeyCompute();

    /// What [work] gives, and the ticks a timer of this isolate made meanwhile: work done on this isolate would leave it none.
    Future<(T, int)> ticking<T>(Future<T> Function() work) async {
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => ticks++,
      );
      try {
        return (await work(), ticks);
      } finally {
        timer.cancel();
      }
    }

    Future<UnprovenCoordinatorRobot> unprovenWith(RobotPgpKey pair) async {
      final client = CoordinatorClient(
        _RobotTransport(
          _json(200, {
            ...robot(),
            'public_key': pair.publicKey.armored,
            'encrypted_private_key': pair.encryptedPrivateKeyArmored,
          }),
        ),
      );
      return switch (await client.fetchKnownRobot(
        temple,
        network,
        identity: identity,
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
    }

    test(
      'makes a pair of the robot, locked by its token, in another isolate',
      () async {
        final (generated, ticks) = await ticking(
          () => compute.generate(identity),
        );

        final pair = switch (generated) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(ticks, greaterThan(5));
        expect(pair.isNamedAfter(identity), isTrue);
        expect(pair, isNot(pgpKey));
        // Its token proves it.
        expect(
          await compute.prove(await unprovenWith(pair)),
          isA<Ok<Result<CoordinatorRobot, RobotPgpKeyNotProven>, P2pFailure>>()
              .having(
                (ok) => ok.value,
                'proof',
                isA<Ok<CoordinatorRobot, RobotPgpKeyNotProven>>(),
              ),
        );
      },
    );

    test(
      'proves a pair in another isolate, and gives the robot back',
      () async {
        final unproven = await unprovenWith(pgpKey);

        final (proof, ticks) = await ticking(() => compute.prove(unproven));

        expect(ticks, greaterThan(5));
        expect(
          proof,
          isA<Ok<Result<CoordinatorRobot, RobotPgpKeyNotProven>, P2pFailure>>()
              .having(
                (ok) => ok.value,
                'proof',
                isA<Ok<CoordinatorRobot, RobotPgpKeyNotProven>>()
                    .having((ok) => ok.value.pgpKey, 'pgpKey', pgpKey)
                    .having((ok) => ok.value.hashId, 'hashId', identity.hashId)
                    .having((ok) => ok.value.pgpKeyProven, 'proven', isTrue),
              ),
        );
      },
    );

    test('refuses there a pair its token does not unlock', () async {
      final unproven = await unprovenWith(otherRobotPgpKey);

      expect(
        await compute.prove(unproven),
        isA<Ok<Result<CoordinatorRobot, RobotPgpKeyNotProven>, P2pFailure>>()
            .having(
              (ok) => ok.value,
              'proof',
              isA<Err<CoordinatorRobot, RobotPgpKeyNotProven>>(),
            ),
      );
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

/// Bindings that note each `bind` in [order] before they bind.
final class _OrderedBindings implements RobotBindingRepository {
  final RobotBindingRepository _bindings;
  final List<String> order;

  _OrderedBindings(this._bindings, this.order);

  @override
  Future<Result<void, P2pFailure>> bind(
    RobotSlot robot,
    CoordinatorIdentity coordinator,
  ) {
    order.add('bind');
    return _bindings.bind(robot, coordinator);
  }

  @override
  Future<Result<void, P2pFailure>> recordGeneratedKey(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) => _bindings.recordGeneratedKey(network, key);

  @override
  Future<Result<void, P2pFailure>> recordImportedKey(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) => _bindings.recordImportedKey(network, key);

  @override
  Future<Result<GarageKeyExposure, P2pFailure>> exposureOf(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) => _bindings.exposureOf(network, key);
}
