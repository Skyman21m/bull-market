import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
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
