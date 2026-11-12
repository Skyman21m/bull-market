import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart'
    show BooleanExpressionOperators, Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/robot_bindings.dart';

/// The bindings of the robots in the feature's database: one robot index, one coordinator, recorded before the first request and never changed.
void main() {
  const testnet = RobosatsNetwork.testnet;
  const mainnet = RobosatsNetwork.mainnet;

  // Fixed test bytes: not keys anyone uses.
  GarageKey keyOf(int first) => switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => first + i)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final keyA = keyOf(1);
  final keyB = keyOf(2);

  GarageKeyFingerprint fingerprintOf(GarageKey key) =>
      switch (GarageKeyFingerprint.of(key)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
  final fingerprintA = fingerprintOf(keyA);
  final fingerprintB = fingerprintOf(keyB);

  CoordinatorIdentity identityOf(String alias, RobosatsNetwork network) =>
      switch (CoordinatorIdentity.of(coordinator(alias), network)) {
        final identity? => identity,
        null => throw StateError('$alias is not on $network'),
      };
  final temple = identityOf('temple', testnet);
  final lake = identityOf('lake', testnet);

  Matcher refusedWith<T>() => isA<Err<void, P2pFailure>>().having(
    (err) => err.failure,
    'failure',
    isA<T>(),
  );
  final passes = isA<Ok<void, P2pFailure>>();

  late P2pDatabase database;
  late RobotBindingRepositoryImpl bindings;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = P2pDatabase.forTesting(NativeDatabase.memory());
    bindings = bindingsInMemory(database: database);
  });

  tearDown(() => database.close());

  Future<List<RobotBindingRow>> rows() =>
      database.select(database.robotBindings).get();

  group('a robot of a key drawn on this device', () {
    setUp(() async {
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);
    });

    test(
      'is bound at its first request, to the coordinator as the federation list gives it',
      () async {
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
          passes,
        );

        final row = (await rows()).single;
        expect(row.network, 'testnet');
        expect(row.keyFingerprint, fingerprintA.hex);
        expect(row.robotIndex, 0);
        expect(row.coordinatorAlias, 'temple');
        expect(row.coordinatorOnion, coordinator('temple').testnet.onion);
        expect(
          row.coordinatorNodeKeys.split(','),
          [...coordinator('temple').testnetNodesPubkeys]..sort(),
        );
        expect(row.coordinatorNostrKey, coordinator('temple').nostrHexPubkey);
        expect(row.boundAt, testNow.millisecondsSinceEpoch);
      },
    );

    test('goes to its coordinator again, and never to another', () async {
      final robot = RobotSlot(testnet, fingerprintA, 3);
      expect(await bindings.bind(robot, temple), passes);

      expect(await bindings.bind(robot, temple), passes);
      expect(
        await bindings.bind(robot, lake),
        refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
      );
      expect(await bindings.bind(robot, temple), passes);
      expect((await rows()).single.coordinatorAlias, 'temple');
    });

    test(
      'does not go to its coordinator once its onion address or keys changed',
      () async {
        final robot = RobotSlot(testnet, fingerprintA, 0);
        expect(await bindings.bind(robot, temple), passes);

        for (final changed in [
          CoordinatorIdentity(
            network: testnet,
            alias: temple.alias,
            onion: lake.onion,
            nodeKeys: temple.nodeKeys,
            nostrKey: temple.nostrKey,
          ),
          CoordinatorIdentity(
            network: testnet,
            alias: temple.alias,
            onion: temple.onion,
            nodeKeys: [...temple.nodeKeys, lake.nodeKeys.first],
            nostrKey: temple.nostrKey,
          ),
          CoordinatorIdentity(
            network: testnet,
            alias: temple.alias,
            onion: temple.onion,
            nodeKeys: const [],
            nostrKey: temple.nostrKey,
          ),
          CoordinatorIdentity(
            network: testnet,
            alias: temple.alias,
            onion: temple.onion,
            nodeKeys: temple.nodeKeys,
            nostrKey: lake.nostrKey,
          ),
          // Another alias on the same onion address: renamed, or another entry pointing at that server.
          CoordinatorIdentity(
            network: testnet,
            alias: 'renamed',
            onion: temple.onion,
            nodeKeys: temple.nodeKeys,
            nostrKey: temple.nostrKey,
          ),
        ]) {
          expect(
            await bindings.bind(robot, changed),
            refusedWith<RobotCoordinatorChangedFailure>(),
            reason: '$changed',
          );
        }
        // The order of the node keys is not a change.
        expect(
          await bindings.bind(
            robot,
            CoordinatorIdentity(
              network: testnet,
              alias: temple.alias,
              onion: temple.onion,
              nodeKeys: temple.nodeKeys.reversed,
              nostrKey: temple.nostrKey,
            ),
          ),
          passes,
        );
        expect(await rows(), hasLength(1));
      },
    );

    test(
      'is bound once for both networks, since its credential is the same on both, and under its own key only',
      () async {
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
          passes,
        );
        // The key in the mainnet slot too, as if this device had drawn it there.
        expect(
          await bindings.recordGeneratedKey(mainnet, fingerprintA),
          passes,
        );

        // Robot 0 has the same token hash on mainnet: no mainnet coordinator gets it, not even temple's mainnet instance.
        for (final alias in ['temple', 'lake']) {
          expect(
            await bindings.bind(
              RobotSlot(mainnet, fingerprintA, 0),
              identityOf(alias, mainnet),
            ),
            refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
            reason: alias,
          );
        }
        // Robot 1 is free on either network, and once bound on mainnet it is refused on testnet.
        expect(
          await bindings.bind(
            RobotSlot(mainnet, fingerprintA, 1),
            identityOf('lake', mainnet),
          ),
          passes,
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 1), lake),
          refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
        );
        // Robot 0 of another key drawn here goes elsewhere.
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintB),
          passes,
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintB, 0), lake),
          passes,
        );
        expect(
          {
            for (final row in await rows())
              (row.network, row.keyFingerprint, row.robotIndex),
          },
          {
            ('testnet', fingerprintA.hex, 0),
            ('mainnet', fingerprintA.hex, 1),
            ('testnet', fingerprintB.hex, 0),
          },
        );
      },
    );

    test(
      'drawn on mainnet and pasted into testnet: the other direction',
      () async {
        expect(
          await bindings.recordGeneratedKey(mainnet, fingerprintB),
          passes,
        );
        expect(await bindings.recordImportedKey(testnet, fingerprintB), passes);
        expect(
          await bindings.bind(
            RobotSlot(mainnet, fingerprintB, 0),
            identityOf('lake', mainnet),
          ),
          passes,
        );

        // The same alias on the other network is another coordinator.
        for (final alias in ['temple', 'lake']) {
          expect(
            await bindings.bind(
              RobotSlot(testnet, fingerprintB, 0),
              identityOf(alias, testnet),
            ),
            refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
            reason: alias,
          );
        }
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintB, 1), temple),
          refusedWith<RobotHistoryUnknownFailure>(),
        );
        expect(
          await bindings.bind(
            RobotSlot(mainnet, fingerprintB, 1),
            identityOf('temple', mainnet),
          ),
          passes,
        );
      },
    );

    test(
      'first contacts of one index on both networks at once: one binding',
      () async {
        expect(
          await bindings.recordGeneratedKey(mainnet, fingerprintA),
          passes,
        );

        final results = await Future.wait([
          bindings.bind(
            RobotSlot(mainnet, fingerprintA, 0),
            identityOf('lake', mainnet),
          ),
          bindings.bind(RobotSlot(testnet, fingerprintA, 0), lake),
        ]);

        expect(results.whereType<Ok<void, P2pFailure>>(), hasLength(1));
        expect(
          results.whereType<Err<void, P2pFailure>>().single.failure,
          isA<RobotBoundToAnotherCoordinatorFailure>(),
        );
        expect(await rows(), hasLength(1));
      },
    );

    test(
      'a robot without a binding follows the history of its key on its own network',
      () async {
        // Drawn on testnet only: on mainnet the same key has an unknown history.
        expect(
          await bindings.bind(
            RobotSlot(mainnet, fingerprintA, 0),
            identityOf('temple', mainnet),
          ),
          refusedWith<RobotHistoryUnknownFailure>(),
        );
        expect(await rows(), isEmpty);
      },
    );

    test(
      'two first requests at once to two coordinators: one is bound, the other refused',
      () async {
        final robot = RobotSlot(testnet, fingerprintA, 0);

        final results = await Future.wait([
          bindings.bind(robot, temple),
          bindings.bind(robot, lake),
        ]);

        expect(results.whereType<Ok<void, P2pFailure>>(), hasLength(1));
        expect(
          results.whereType<Err<void, P2pFailure>>().single.failure,
          isA<RobotBoundToAnotherCoordinatorFailure>(),
        );
        final bound = (await rows()).single.coordinatorAlias;
        expect(
          await bindings.bind(robot, bound == 'temple' ? temple : lake),
          passes,
        );
      },
    );

    test(
      'an index out of range is refused by the database, not taken for a key of unknown history',
      () async {
        for (final index in [-1, GarageKey.maxAccountIndex + 1]) {
          expect(
            await bindings.bind(
              RobotSlot(testnet, fingerprintA, index),
              temple,
            ),
            refusedWith<P2pStorageFailure>(),
          );
        }
        expect(await rows(), isEmpty);
      },
    );
  });

  group('a robot of a key whose history is unknown', () {
    test('is never bound when the key was not recorded', () async {
      expect(
        await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
        refusedWith<RobotHistoryUnknownFailure>(),
      );
      expect(await rows(), isEmpty);
    });

    test('is never bound when the key was imported', () async {
      expect(await bindings.recordImportedKey(testnet, fingerprintA), passes);

      expect(
        await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
        refusedWith<RobotHistoryUnknownFailure>(),
      );
      // A draw of the same key later does not make it new again.
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);
      expect(
        await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
        refusedWith<RobotHistoryUnknownFailure>(),
      );
      expect(await rows(), isEmpty);
    });

    test(
      'keeps the bindings made before the key was imported again, and binds no new index',
      () async {
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintA),
          passes,
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
          passes,
        );

        // The key was deleted, then pasted back from the user's copy.
        expect(await bindings.recordImportedKey(testnet, fingerprintA), passes);

        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
          passes,
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 0), lake),
          refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 1), temple),
          refusedWith<RobotHistoryUnknownFailure>(),
        );
        final histories = await database
            .select(database.garageKeyHistories)
            .get();
        expect(histories.single.origin, 'imported');
      },
    );
  });

  group('what a delete of the key reads', () {
    Matcher exposure(GarageKeyHistory history, {required bool hasBinding}) =>
        isA<Ok<GarageKeyExposure, P2pFailure>>().having(
          (ok) => ok.value,
          'value',
          GarageKeyExposure(history: history, hasBinding: hasBinding),
        );

    test(
      'a key never recorded has an unknown history and no binding',
      () async {
        expect(
          await bindings.exposureOf(testnet, fingerprintA),
          exposure(GarageKeyHistory.unknown, hasBinding: false),
        );
      },
    );

    test(
      'a key drawn here, with no robot bound, has none on a coordinator',
      () async {
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintA),
          passes,
        );

        final read = await bindings.exposureOf(testnet, fingerprintA);
        expect(read, exposure(GarageKeyHistory.drawnHere, hasBinding: false));
        expect(
          (read as Ok<GarageKeyExposure, P2pFailure>)
              .value
              .mayHaveRobotsOnCoordinators,
          isFalse,
        );
      },
    );

    test(
      'a key imported, or drawn then imported, has an unknown history',
      () async {
        expect(await bindings.recordImportedKey(testnet, fingerprintA), passes);
        expect(
          await bindings.exposureOf(testnet, fingerprintA),
          exposure(GarageKeyHistory.unknown, hasBinding: false),
        );

        expect(
          await bindings.recordGeneratedKey(mainnet, fingerprintB),
          passes,
        );
        expect(await bindings.recordImportedKey(mainnet, fingerprintB), passes);
        expect(
          await bindings.exposureOf(mainnet, fingerprintB),
          exposure(GarageKeyHistory.unknown, hasBinding: false),
        );
      },
    );

    test('the history is the one of the network asked', () async {
      expect(await bindings.recordGeneratedKey(mainnet, fingerprintA), passes);

      expect(
        await bindings.exposureOf(mainnet, fingerprintA),
        exposure(GarageKeyHistory.drawnHere, hasBinding: false),
      );
      expect(
        await bindings.exposureOf(testnet, fingerprintA),
        exposure(GarageKeyHistory.unknown, hasBinding: false),
      );
    });

    test('a robot bound on this network counts', () async {
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);
      expect(
        await bindings.bind(RobotSlot(testnet, fingerprintA, 4), temple),
        passes,
      );

      expect(
        await bindings.exposureOf(testnet, fingerprintA),
        exposure(GarageKeyHistory.drawnHere, hasBinding: true),
      );
    });

    test('a robot bound on the other network counts as well', () async {
      // The same key in both slots: drawn here on each network, robot 0 bound to a mainnet coordinator.
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);
      expect(await bindings.recordGeneratedKey(mainnet, fingerprintA), passes);
      expect(
        await bindings.bind(
          RobotSlot(mainnet, fingerprintA, 0),
          identityOf('lake', mainnet),
        ),
        passes,
      );

      expect(
        await bindings.exposureOf(testnet, fingerprintA),
        exposure(GarageKeyHistory.drawnHere, hasBinding: true),
      );
    });

    test('the bindings of another key do not count', () async {
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);
      expect(await bindings.recordGeneratedKey(testnet, fingerprintB), passes);
      expect(
        await bindings.bind(RobotSlot(testnet, fingerprintB, 0), temple),
        passes,
      );

      expect(
        await bindings.exposureOf(testnet, fingerprintA),
        exposure(GarageKeyHistory.drawnHere, hasBinding: false),
      );
    });

    test('reading writes nothing', () async {
      expect(
        await bindings.exposureOf(testnet, fingerprintA),
        isA<Ok<GarageKeyExposure, P2pFailure>>(),
      );

      expect(await rows(), isEmpty);
      expect(await database.select(database.garageKeyHistories).get(), isEmpty);
    });

    test('prints neither the key nor its fingerprint', () {
      const read = GarageKeyExposure(
        history: GarageKeyHistory.unknown,
        hasBinding: true,
      );
      expect('$read', 'GarageKeyExposure(unknown, true)');
    });

    test(
      'a key acknowledged may have robots on coordinators, from elsewhere',
      () async {
        expect(await bindings.recordImportedKey(testnet, fingerprintA), passes);
        expect(
          await bindings.recordAcknowledgedKey(testnet, fingerprintA),
          passes,
        );

        final read = await bindings.exposureOf(testnet, fingerprintA);
        expect(
          read,
          exposure(GarageKeyHistory.acknowledged, hasBinding: false),
        );
        expect(
          (read as Ok<GarageKeyExposure, P2pFailure>)
              .value
              .mayHaveRobotsOnCoordinators,
          isTrue,
        );
      },
    );
  });

  group('the history a binding is made under', () {
    Future<String?> originOf(
      RobosatsNetwork network,
      GarageKeyFingerprint key,
    ) async =>
        (await (database.select(database.garageKeyHistories)..where(
                  (row) =>
                      row.network.equals(network.name) &
                      row.keyFingerprint.equals(key.hex),
                ))
                .getSingleOrNull())
            ?.origin;

    test(
      'each history: drawn here and acknowledged bind with their provenance, the others bind nothing',
      () async {
        for (final (index, record, expected) in [
          (
            0,
            () => bindings.recordGeneratedKey(testnet, fingerprintA),
            'generated',
          ),
          (
            1,
            () => bindings.recordAcknowledgedKey(testnet, fingerprintA),
            'acknowledged',
          ),
          (2, () => bindings.recordImportedKey(testnet, fingerprintA), null),
          (3, () async => const Ok<void, P2pFailure>(null), null),
        ]) {
          // A fresh database for each history.
          await database.close();
          database = P2pDatabase.forTesting(NativeDatabase.memory());
          bindings = bindingsInMemory(database: database);
          expect(await record(), passes);

          final result = await bindings.bind(
            RobotSlot(testnet, fingerprintA, index),
            temple,
          );

          if (expected == null) {
            expect(result, refusedWith<RobotHistoryUnknownFailure>());
            expect(await rows(), isEmpty, reason: 'index $index');
          } else {
            expect(result, passes, reason: 'index $index');
            expect((await rows()).single.provenance, expected);
          }
        }
      },
    );

    test(
      'an acknowledgement records a key never recorded, and turns an imported one',
      () async {
        expect(
          await bindings.recordAcknowledgedKey(testnet, fingerprintA),
          passes,
        );
        expect(await bindings.recordImportedKey(mainnet, fingerprintA), passes);
        expect(
          await bindings.recordAcknowledgedKey(mainnet, fingerprintA),
          passes,
        );

        expect(await originOf(testnet, fingerprintA), 'acknowledged');
        expect(await originOf(mainnet, fingerprintA), 'acknowledged');
      },
    );

    test('an acknowledgement never turns a key drawn here', () async {
      var now = testNow;
      bindings = bindingsInMemory(database: database, clock: () => now);
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);

      now = testNow.add(const Duration(minutes: 5));
      expect(
        await bindings.recordAcknowledgedKey(testnet, fingerprintA),
        passes,
      );

      final history =
          (await database.select(database.garageKeyHistories).get()).single;
      expect(history.origin, 'generated');
      expect(history.recordedAt, testNow.millisecondsSinceEpoch);
      expect(
        await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
        passes,
      );
      expect((await rows()).single.provenance, 'generated');
    });

    test('two acknowledgements in a row keep the first', () async {
      var now = testNow;
      bindings = bindingsInMemory(database: database, clock: () => now);
      expect(await bindings.recordImportedKey(testnet, fingerprintA), passes);
      expect(
        await bindings.recordAcknowledgedKey(testnet, fingerprintA),
        passes,
      );

      now = testNow.add(const Duration(minutes: 5));
      expect(
        await bindings.recordAcknowledgedKey(testnet, fingerprintA),
        passes,
      );

      final history =
          (await database.select(database.garageKeyHistories).get()).single;
      expect(history.origin, 'acknowledged');
      expect(history.recordedAt, testNow.millisecondsSinceEpoch);
    });

    test(
      'a new import makes the history unknown again, and keeps the bindings made',
      () async {
        expect(
          await bindings.recordAcknowledgedKey(testnet, fingerprintA),
          passes,
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
          passes,
        );

        // The key was deleted, then pasted back: the copy may have travelled.
        expect(await bindings.recordImportedKey(testnet, fingerprintA), passes);

        expect(await originOf(testnet, fingerprintA), 'imported');
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 1), temple),
          refusedWith<RobotHistoryUnknownFailure>(),
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
          passes,
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 0), lake),
          refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
        );

        // Acknowledged again, the next index binds.
        expect(
          await bindings.recordAcknowledgedKey(testnet, fingerprintA),
          passes,
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 1), lake),
          passes,
        );
        expect(
          {for (final row in await rows()) row.robotIndex: row.provenance},
          {0: 'acknowledged', 1: 'acknowledged'},
        );
      },
    );

    test('an acknowledgement holds for its own network only', () async {
      expect(
        await bindings.recordAcknowledgedKey(testnet, fingerprintA),
        passes,
      );

      expect(
        await bindings.bind(
          RobotSlot(mainnet, fingerprintA, 0),
          identityOf('temple', mainnet),
        ),
        refusedWith<RobotHistoryUnknownFailure>(),
      );
      expect(await originOf(mainnet, fingerprintA), isNull);
      expect(await rows(), isEmpty);
    });

    test('the provenance of a binding never changes', () async {
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);
      expect(
        await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
        passes,
      );
      expect(await bindings.recordImportedKey(testnet, fingerprintA), passes);
      expect(
        await bindings.recordAcknowledgedKey(testnet, fingerprintA),
        passes,
      );

      expect(
        await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
        passes,
      );
      expect(
        await bindings.bind(RobotSlot(testnet, fingerprintA, 1), temple),
        passes,
      );
      expect(
        {for (final row in await rows()) row.robotIndex: row.provenance},
        {0: 'generated', 1: 'acknowledged'},
      );
    });

    test(
      'a bind and an acknowledgement at once: the order they reach the database decides',
      () async {
        expect(await bindings.recordImportedKey(testnet, fingerprintA), passes);

        // drift runs the statements of one connection in the order they are sent.
        final bindFirst = await Future.wait([
          bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
          bindings.recordAcknowledgedKey(testnet, fingerprintA),
        ]);
        expect(bindFirst.first, refusedWith<RobotHistoryUnknownFailure>());
        expect(bindFirst.last, passes);

        expect(await bindings.recordImportedKey(testnet, fingerprintA), passes);
        final acknowledgementFirst = await Future.wait([
          bindings.recordAcknowledgedKey(testnet, fingerprintA),
          bindings.bind(RobotSlot(testnet, fingerprintA, 1), temple),
        ]);
        expect(acknowledgementFirst, everyElement(passes));

        expect(
          {for (final row in await rows()) row.robotIndex: row.provenance},
          {1: 'acknowledged'},
        );
      },
    );
  });

  group('where a robot stands', () {
    final robot = RobotSlot(testnet, fingerprintA, 2);

    Future<RobotStanding> standing([RobotSlot? of]) async =>
        switch (await bindings.standingOf(of ?? robot)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };

    test(
      'a robot of a key never recorded is unbound, and needs an acknowledgement',
      () async {
        final read = await standing();

        expect(
          read,
          const RobotStanding(
            network: testnet,
            binding: null,
            history: GarageKeyHistory.unknown,
          ),
        );
        expect(read.needsAcknowledgement, isTrue);
        expect(read.isBoundOnOtherNetwork, isFalse);
      },
    );

    test('the history of its key on its network, while unbound', () async {
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);
      expect(await bindings.recordImportedKey(mainnet, fingerprintA), passes);

      final drawn = await standing();
      expect(drawn.history, GarageKeyHistory.drawnHere);
      expect(drawn.needsAcknowledgement, isFalse);
      final imported = await standing(RobotSlot(mainnet, fingerprintA, 2));
      expect(imported.history, GarageKeyHistory.unknown);
      expect(imported.needsAcknowledgement, isTrue);

      expect(
        await bindings.recordAcknowledgedKey(mainnet, fingerprintA),
        passes,
      );
      final acknowledged = await standing(RobotSlot(mainnet, fingerprintA, 2));
      expect(acknowledged.history, GarageKeyHistory.acknowledged);
      expect(acknowledged.needsAcknowledgement, isFalse);
      expect(acknowledged.binding, isNull);
    });

    test(
      'a bound robot: its coordinator as recorded, and the provenance of its binding',
      () async {
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintA),
          passes,
        );
        expect(await bindings.bind(robot, temple), passes);
        expect(
          await bindings.recordAcknowledgedKey(testnet, fingerprintB),
          passes,
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintB, 2), lake),
          passes,
        );

        expect(
          await standing(),
          RobotStanding(
            network: testnet,
            binding: RobotBinding(temple, testNow, BindingProvenance.drawnHere),
            history: GarageKeyHistory.drawnHere,
          ),
        );
        expect(
          await standing(RobotSlot(testnet, fingerprintB, 2)),
          RobotStanding(
            network: testnet,
            binding: RobotBinding(
              lake,
              testNow,
              BindingProvenance.acknowledged,
            ),
            history: GarageKeyHistory.acknowledged,
          ),
        );
        // Another index of the key, and the same index of a key without bindings, are unbound.
        expect(
          (await standing(RobotSlot(testnet, fingerprintA, 3))).binding,
          isNull,
        );
        expect(
          (await standing(
            RobotSlot(testnet, fingerprintOf(keyOf(3)), 2),
          )).binding,
          isNull,
        );
      },
    );

    test(
      'a robot bound on the other network is bound there, whatever its history here',
      () async {
        expect(
          await bindings.recordGeneratedKey(mainnet, fingerprintA),
          passes,
        );
        final lakeMainnet = identityOf('lake', mainnet);
        expect(
          await bindings.bind(RobotSlot(mainnet, fingerprintA, 2), lakeMainnet),
          passes,
        );

        final read = await standing();

        expect(read.binding?.coordinator, lakeMainnet);
        expect(read.isBoundOnOtherNetwork, isTrue);
        // Bound, so no acknowledgement is asked, though the key is unknown on testnet.
        expect(read.history, GarageKeyHistory.unknown);
        expect(read.needsAcknowledgement, isFalse);
        expect(
          (await standing(
            RobotSlot(mainnet, fingerprintA, 2),
          )).isBoundOnOtherNetwork,
          isFalse,
        );
      },
    );

    test('a bound robot whose key was imported again stays bound', () async {
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);
      expect(await bindings.bind(robot, temple), passes);
      expect(await bindings.recordImportedKey(testnet, fingerprintA), passes);

      final read = await standing();

      expect(read.binding?.provenance, BindingProvenance.drawnHere);
      expect(read.history, GarageKeyHistory.unknown);
      expect(read.needsAcknowledgement, isFalse);
    });

    test('reading writes nothing', () async {
      await standing();

      expect(await rows(), isEmpty);
      expect(await database.select(database.garageKeyHistories).get(), isEmpty);
    });

    test('a row this code did not write is a storage failure', () async {
      // Tables of schema 2 without their constraints, holding a provenance no version writes.
      final loose = P2pDatabase.forTesting(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute(
              'CREATE TABLE garage_key_histories (network TEXT NOT NULL, key_fingerprint TEXT NOT NULL, origin TEXT NOT NULL, recorded_at INTEGER NOT NULL, PRIMARY KEY (network, key_fingerprint))',
            );
            raw.execute(
              'CREATE TABLE robot_bindings (network TEXT NOT NULL, key_fingerprint TEXT NOT NULL, robot_index INTEGER NOT NULL, coordinator_alias TEXT NOT NULL, coordinator_onion TEXT NOT NULL, coordinator_node_keys TEXT NOT NULL, coordinator_nostr_key TEXT NOT NULL, bound_at INTEGER NOT NULL, provenance TEXT NOT NULL, PRIMARY KEY (key_fingerprint, robot_index))',
            );
            raw.execute('PRAGMA user_version = ${P2pDatabase.schema}');
          },
        ),
      );
      final repository = bindingsInMemory(database: loose);
      for (final (index, network, provenance) in [
        (0, 'testnet', 'elsewhere'),
        (1, 'signet', 'generated'),
      ]) {
        await loose
            .into(loose.robotBindings)
            .insert(
              RobotBindingsCompanion.insert(
                network: network,
                keyFingerprint: fingerprintA.hex,
                robotIndex: index,
                coordinatorAlias: 'temple',
                coordinatorOnion: temple.onion,
                coordinatorNodeKeys: temple.nodeKeys.join(','),
                coordinatorNostrKey: temple.nostrKey,
                boundAt: 0,
                provenance: Value(provenance),
              ),
            );
        expect(
          await repository.standingOf(RobotSlot(testnet, fingerprintA, index)),
          isA<Err<RobotStanding, P2pFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<P2pStorageFailure>(),
          ),
          reason: provenance,
        );
      }
      await loose.close();
    });

    test('prints neither the key nor its fingerprint', () {
      final read = RobotStanding(
        network: testnet,
        binding: RobotBinding(temple, testNow, BindingProvenance.acknowledged),
        history: GarageKeyHistory.acknowledged,
      );

      expect(
        '$read',
        'RobotStanding(testnet, RobotBinding(CoordinatorIdentity(testnet, temple), acknowledged), acknowledged)',
      );
      expect('$read', isNot(contains(fingerprintA.hex)));
    });
  });

  group('on disk', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('p2p-bindings-');
    });

    tearDown(() => directory.delete(recursive: true));

    test(
      'the file is p2p.sqlite in the directory given, made at the first query only',
      () async {
        var asked = 0;
        final onDisk = P2pDatabase.open(() async {
          asked++;
          return directory;
        });
        final repository = bindingsInMemory(database: onDisk);
        expect(asked, 0);
        expect(directory.listSync(), isEmpty);

        expect(
          await repository.recordGeneratedKey(testnet, fingerprintA),
          passes,
        );

        expect(asked, 1);
        expect(File('${directory.path}/p2p.sqlite').existsSync(), isTrue);
        await onDisk.close();
      },
    );

    test('every commit is synced to disk before a request can leave', () async {
      final onDisk = P2pDatabase.open(() async => directory);

      // 2 is FULL: with write-ahead logging, NORMAL could lose the last binding to a power cut.
      expect(
        (await onDisk.customSelect('PRAGMA synchronous').getSingle())
            .data
            .values
            .single,
        2,
      );
      expect(
        (await onDisk.customSelect('PRAGMA journal_mode').getSingle())
            .data
            .values
            .single,
        'wal',
      );
      await onDisk.close();
    });

    test(
      'a binding outlives its connection, and two connections bind a robot once',
      () async {
        final first = P2pDatabase.open(() async => directory);
        final second = P2pDatabase.open(() async => directory);
        final one = bindingsInMemory(database: first);
        final other = bindingsInMemory(database: second);
        expect(await one.recordGeneratedKey(testnet, fingerprintA), passes);

        for (var index = 0; index < 5; index++) {
          final robot = RobotSlot(testnet, fingerprintA, index);
          final results = await Future.wait([
            one.bind(robot, temple),
            other.bind(robot, lake),
          ]);
          expect(
            results.whereType<Ok<void, P2pFailure>>(),
            hasLength(1),
            reason: 'index $index',
          );
          expect(
            results.whereType<Err<void, P2pFailure>>().single.failure,
            isA<RobotBoundToAnotherCoordinatorFailure>(),
          );
        }
        await first.close();
        await second.close();

        final reopened = P2pDatabase.open(() async => directory);
        expect(
          await reopened.select(reopened.robotBindings).get(),
          hasLength(5),
        );
        await reopened.close();
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'binds while another connection acknowledges, then imports, the key: each binding carries the history it was made under',
      () async {
        final first = P2pDatabase.open(() async => directory);
        final second = P2pDatabase.open(() async => directory);
        final one = bindingsInMemory(database: first);
        final other = bindingsInMemory(database: second);
        expect(await one.recordImportedKey(testnet, fingerprintA), passes);

        // The binds of one connection run in order; the record of the other lands somewhere among them.
        // Two connections writing at once can make SQLite give up after its busy timeout, as in the test of three connections above: such a bind is a P2pStorageFailure that refuses the request, and a record that gave up is tried again.
        Future<List<Result<void, P2pFailure>>> bindDuring(
          Iterable<int> indexes,
          Future<Result<void, P2pFailure>> Function() record,
        ) async {
          final binds = [
            for (final index in indexes)
              one.bind(RobotSlot(testnet, fingerprintA, index), temple),
          ];
          Future<Result<void, P2pFailure>> recordUntilDone() async {
            var result = await record();
            for (var attempt = 0; attempt < 10 && result is! Ok; attempt++) {
              result = await record();
            }
            return result;
          }

          final recorded = recordUntilDone();
          final results = await Future.wait(binds);
          expect(await recorded, passes);
          return results;
        }

        bool bound(Result<void, P2pFailure> result) => result is Ok;
        bool refused(Result<void, P2pFailure> result) => switch (result) {
          Err(failure: RobotHistoryUnknownFailure()) => true,
          Ok() || Err(failure: P2pStorageFailure()) => false,
          Err(:final failure) => fail('$failure'),
        };

        final acknowledging = await bindDuring(
          List.generate(20, (i) => i),
          () => other.recordAcknowledgedKey(testnet, fingerprintA),
        );
        // Refused until the acknowledgement, never once it is recorded.
        final firstBound = acknowledging.indexWhere(bound);
        expect(
          acknowledging.skip(firstBound < 0 ? 20 : firstBound).any(refused),
          isFalse,
        );
        final importing = await bindDuring(
          List.generate(20, (i) => 20 + i),
          () => other.recordImportedKey(testnet, fingerprintA),
        );
        // Bound until the import, never once it is recorded.
        final firstRefused = importing.indexWhere(refused);
        expect(
          importing.skip(firstRefused < 0 ? 20 : firstRefused).any(bound),
          isFalse,
        );
        // A robot bound once the key is imported again would carry a provenance it does not have.
        expect(
          await one.bind(RobotSlot(testnet, fingerprintA, 40), temple),
          refusedWith<RobotHistoryUnknownFailure>(),
        );

        final stored = await first.select(first.robotBindings).get();
        final storedIndexes = {for (final row in stored) row.robotIndex};
        for (final (i, result) in [...acknowledging, ...importing].indexed) {
          if (bound(result)) expect(storedIndexes, contains(i));
          if (refused(result)) expect(storedIndexes, isNot(contains(i)));
        }
        expect(
          stored.map((row) => row.provenance),
          everyElement('acknowledged'),
        );
        await first.close();
        await second.close();
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('a lost database never frees a robot', () async {
      final first = P2pDatabase.open(() async => directory);
      final one = bindingsInMemory(database: first);
      expect(await one.recordGeneratedKey(testnet, fingerprintA), passes);
      expect(
        await one.bind(RobotSlot(testnet, fingerprintA, 0), temple),
        passes,
      );
      await first.close();
      for (final name in ['p2p.sqlite', 'p2p.sqlite-wal', 'p2p.sqlite-shm']) {
        final file = File('${directory.path}/$name');
        if (file.existsSync()) file.deleteSync();
      }

      // The record of the key went with the file: its history is unknown, and no index is bound again.
      final reopened = P2pDatabase.open(() async => directory);
      final again = bindingsInMemory(database: reopened);
      for (final index in [0, 1]) {
        expect(
          await again.bind(RobotSlot(testnet, fingerprintA, index), lake),
          refusedWith<RobotHistoryUnknownFailure>(),
        );
      }
      await reopened.close();
    });

    test(
      'three connections, 30 indexes and three coordinators at once: each index is bound to one coordinator',
      () async {
        // The app opens one connection, in the foreground only, and drift runs its statements one at a time, so none of this contention happens there.
        // Several connections writing at once can make SQLite give up after its busy timeout: the call fails with a P2pStorageFailure, which refuses the request, and binds nothing.
        final databases = [
          for (var i = 0; i < 3; i++) P2pDatabase.open(() async => directory),
        ];
        final repositories = [
          for (final database in databases)
            bindingsInMemory(database: database),
        ];
        expect(
          await repositories.first.recordGeneratedKey(mainnet, fingerprintA),
          passes,
        );
        // freeport has no testnet instance.
        const aliases = ['temple', 'lake', 'freeport'];
        final calls = [
          for (var index = 0; index < 30; index++)
            for (var c = 0; c < 3; c++)
              (
                index: index,
                alias: aliases[c],
                result: repositories[c].bind(
                  RobotSlot(mainnet, fingerprintA, index),
                  identityOf(aliases[c], mainnet),
                ),
              ),
        ];
        final results = [
          for (final call in calls)
            (index: call.index, alias: call.alias, result: await call.result),
        ];
        for (final database in databases) {
          await database.close();
        }

        final reopened = P2pDatabase.open(() async => directory);
        final stored = await reopened.select(reopened.robotBindings).get();
        await reopened.close();
        final boundTo = {
          for (final row in stored) row.robotIndex: row.coordinatorAlias,
        };
        for (var index = 0; index < 30; index++) {
          final passed = {
            for (final r in results)
              if (r.index == index && r.result is Ok) r.alias,
          };
          // At most one coordinator passed, and it is the one on disk.
          expect(passed.length, lessThanOrEqualTo(1), reason: 'index $index');
          if (passed.isNotEmpty) {
            expect(boundTo[index], passed.single, reason: 'index $index');
          }
          for (final r in results.where((r) => r.index == index)) {
            if (r.result case Err(:final failure)) {
              expect(
                failure,
                anyOf(
                  isA<RobotBoundToAnotherCoordinatorFailure>(),
                  isA<P2pStorageFailure>(),
                ),
              );
            }
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a file of the first shape of version 1, which no build shipped, refuses every binding',
      () async {
        // The tables of `drift_schema_v1.json` at 30c8578ac, where the network was part of the primary key of a binding.
        final file = File('${directory.path}/p2p.sqlite');
        final first = P2pDatabase.forTesting(
          NativeDatabase(
            file,
            setup: (database) {
              database.execute(
                'CREATE TABLE "garage_key_histories" ("network" TEXT NOT NULL, "key_fingerprint" TEXT NOT NULL, "origin" TEXT NOT NULL, "recorded_at" INTEGER NOT NULL, PRIMARY KEY ("network", "key_fingerprint"))',
              );
              database.execute(
                'CREATE TABLE "robot_bindings" ("network" TEXT NOT NULL, "key_fingerprint" TEXT NOT NULL, "robot_index" INTEGER NOT NULL, "coordinator_alias" TEXT NOT NULL, "coordinator_onion" TEXT NOT NULL, "coordinator_node_keys" TEXT NOT NULL, "coordinator_nostr_key" TEXT NOT NULL, "bound_at" INTEGER NOT NULL, PRIMARY KEY ("network", "key_fingerprint", "robot_index"))',
              );
              database.execute('PRAGMA user_version = 1');
            },
          ),
        );
        await first.customSelect('SELECT 1').get();
        await first.close();

        final opened = P2pDatabase.open(() async => directory);
        final repository = bindingsInMemory(database: opened);
        expect(
          await repository.recordGeneratedKey(testnet, fingerprintA),
          passes,
        );
        // Its primary key does not match the conflict target of a binding: every bind fails closed, on either network.
        expect(
          await repository.bind(RobotSlot(testnet, fingerprintA, 0), temple),
          refusedWith<P2pStorageFailure>(),
        );
        expect(
          await repository.bind(
            RobotSlot(mainnet, fingerprintA, 0),
            identityOf('lake', mainnet),
          ),
          refusedWith<P2pStorageFailure>(),
        );
        await opened.close();
      },
    );

    test('a database that cannot be opened refuses everything', () async {
      // A regular file where the directory should be: nothing can be created inside it.
      final occupied = File('${directory.path}/occupied')
        ..writeAsStringSync('');
      final broken = P2pDatabase.open(() async => Directory(occupied.path));
      final repository = bindingsInMemory(database: broken);

      expect(
        await repository.recordGeneratedKey(testnet, fingerprintA),
        refusedWith<P2pStorageFailure>(),
      );
      expect(
        await repository.recordImportedKey(testnet, fingerprintA),
        refusedWith<P2pStorageFailure>(),
      );
      expect(
        await repository.bind(RobotSlot(testnet, fingerprintA, 0), temple),
        refusedWith<P2pStorageFailure>(),
      );
      expect(
        await repository.exposureOf(testnet, fingerprintA),
        isA<Err<GarageKeyExposure, P2pFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<P2pStorageFailure>(),
        ),
      );
      expect(
        await repository.recordAcknowledgedKey(testnet, fingerprintA),
        refusedWith<P2pStorageFailure>(),
      );
      expect(
        await repository.standingOf(RobotSlot(testnet, fingerprintA, 0)),
        isA<Err<RobotStanding, P2pFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<P2pStorageFailure>(),
        ),
      );
      await broken.close();
    });

    test('a directory the shell cannot give refuses everything', () async {
      final broken = P2pDatabase.open(
        () async => throw const FileSystemException('no directory'),
      );
      final repository = bindingsInMemory(database: broken);

      expect(
        await repository.bind(RobotSlot(testnet, fingerprintA, 0), temple),
        refusedWith<P2pStorageFailure>(),
      );
      expect(
        await repository.recordImportedKey(testnet, fingerprintA),
        refusedWith<P2pStorageFailure>(),
      );
      expect(
        await repository.exposureOf(mainnet, fingerprintA),
        isA<Err<GarageKeyExposure, P2pFailure>>(),
      );
      expect(
        await repository.recordAcknowledgedKey(mainnet, fingerprintA),
        refusedWith<P2pStorageFailure>(),
      );
      expect(
        await repository.standingOf(RobotSlot(mainnet, fingerprintA, 0)),
        isA<Err<RobotStanding, P2pFailure>>(),
      );
    });
  });

  test('the database holds no secret of the robots it binds', () async {
    final key = NetworkGarageKey(testnet, keyA);
    expect(await bindings.recordGeneratedKey(testnet, fingerprintA), passes);
    final robots = [
      for (final index in [0, 1, 2])
        switch (key.firstUsableRobot(index)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        },
    ];
    for (final robot in robots) {
      expect(await bindings.bind(robot.slot, temple), passes);
    }

    final stored = [
      for (final row in await rows()) ...[
        row.network,
        row.keyFingerprint,
        '${row.robotIndex}',
        row.coordinatorAlias,
        row.coordinatorOnion,
        row.coordinatorNodeKeys,
        row.coordinatorNostrKey,
        '${row.boundAt}',
      ],
      for (final row
          in await database.select(database.garageKeyHistories).get()) ...[
        row.network,
        row.keyFingerprint,
        row.origin,
        '${row.recordedAt}',
      ],
    ].join('\n');
    for (final robot in robots) {
      final identity = robot.identity;
      for (final secret in [
        identity.token.reveal(),
        identity.tokenSha256Hex,
        identity.tokenSha256Base91,
      ]) {
        expect(stored.contains(secret), isFalse);
      }
      // Not credentials, but what a coordinator publishes about the robot: the database does not name them either.
      expect(stored.contains(identity.hashId.hex), isFalse);
      expect(stored.contains(identity.nickname), isFalse);
    }
    // The bytes of the key, in hexadecimal: the test made them, 0x01 to 0x20.
    final keyHex = [
      for (var i = 1; i <= 32; i++) i.toRadixString(16).padLeft(2, '0'),
    ].join();
    expect(stored.contains(keyHex), isFalse);
  });
}
