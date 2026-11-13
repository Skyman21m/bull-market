import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/interim_trade_robots.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/key_output.dart';
import 'support/robot_bindings.dart';
import 'support/two_connections.dart';

/// The vault as the robot layer reads it: the key of each network, or the failure given for it.
final class _Vault implements GarageKeyRepository {
  final Map<RobosatsNetwork, Result<NetworkGarageKey, P2pFailure>> slots;

  _Vault(this.slots);

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> read(
    RobosatsNetwork network,
  ) async => slots[network] ?? const Err(GarageKeyMissingFailure());

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> create(
    RobosatsNetwork network,
  ) => throw UnimplementedError('the robot layer never draws a key');

  @override
  Future<Result<void, P2pFailure>> import(
    RobosatsNetwork network,
    GarageKey key,
  ) => throw UnimplementedError('the robot layer never imports a key');

  @override
  Future<Result<bool, P2pFailure>> exists(RobosatsNetwork network) =>
      throw UnimplementedError('the robot layer reads the key itself');

  @override
  Future<Result<NetworkRobot, P2pFailure>> firstUsableRobot(
    RobosatsNetwork network,
  ) => throw UnimplementedError('the robot layer derives from the key itself');

  @override
  Future<Result<void, P2pFailure>> delete(RobosatsNetwork network) =>
      throw UnimplementedError('the robot layer never deletes a key');
}

/// The robot of a new trade and of a recorded one, over the real records in a database, and the vault faked.
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

  CoordinatorIdentity identityOf(String alias, RobosatsNetwork network) =>
      switch (CoordinatorIdentity.of(coordinator(alias), network)) {
        final identity? => identity,
        null => throw StateError('$alias is not on $network'),
      };
  final temple = coordinator('temple');
  final lake = coordinator('lake');
  final templeTestnet = identityOf('temple', testnet);

  Matcher refusedWith<T>() => isA<Err<Object?, P2pFailure>>().having(
    (err) => err.failure,
    'failure',
    isA<T>(),
  );
  NetworkRobot robotOf(Result<NetworkRobot, P2pFailure> result) =>
      switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
  TradeRecord recordOf(Result<TradeRecord, P2pFailure> result) =>
      switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };

  late P2pDatabase database;
  late RobotBindingRepositoryImpl bindings;
  late TradeRecordRepositoryImpl trades;
  late _Vault vault;
  late InterimTradeRobots robots;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = P2pDatabase.forTesting(NativeDatabase.memory());
    bindings = bindingsInMemory(database: database);
    trades = TradeRecordRepositoryImpl(database, clock: () => testNow);
    vault = _Vault({
      testnet: Ok(NetworkGarageKey(testnet, keyA)),
      mainnet: Ok(NetworkGarageKey(mainnet, keyB)),
    });
    robots = InterimTradeRobots(vault, trades);
  });

  tearDown(() => database.close());

  Future<List<RobotBindingRow>> bindingRows() =>
      database.select(database.robotBindings).get();

  group('the robot for a new trade', () {
    setUp(() async {
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), isA<Ok>());
    });

    test(
      'is the first free robot of the key, bound to the coordinator before it is returned',
      () async {
        final robot = robotOf(await robots.robotForNewTrade(testnet, temple));

        expect(robot.slot, RobotSlot(testnet, fingerprintA, 0));
        expect(
          robot,
          robotOf(NetworkGarageKey(testnet, keyA).firstUsableRobot(0)),
        );
        expect(
          await bindings.standingOf(robot.slot),
          isA<Ok<RobotStanding, P2pFailure>>().having(
            (ok) => ok.value.binding,
            'binding',
            RobotBinding(templeTestnet, testNow, BindingProvenance.drawnHere),
          ),
        );
        expect(await database.select(database.trades).get(), isEmpty);
      },
    );

    test('is never returned twice, and skips every robot already bound or recorded', () async {
      // The Garage put robot 1 on lake; robot 3 was bound on the other network.
      expect(await bindings.bind(RobotSlot(testnet, fingerprintA, 1), identityOf('lake', testnet)), isA<Ok>());
      expect(await bindings.recordGeneratedKey(mainnet, fingerprintA), isA<Ok>());
      expect(
        await bindings.bind(
          RobotSlot(mainnet, fingerprintA, 3),
          identityOf('temple', mainnet),
        ),
        isA<Ok>(),
      );

      final given = <int>[];
      for (var i = 0; i < 6; i++) {
        final robot = robotOf(
          await robots.robotForNewTrade(testnet, i.isEven ? temple : lake),
        );
        given.add(robot.accountIndex);
        // Half of them get a trade, which is closed: a robot that ever had a record is never returned again.
        if (i.isEven) {
          final record = recordOf(
            await trades.recordPendingTake(
              robot.slot,
              templeTestnet,
              orderId: 100 + i,
              role: TradeRole.buyer,
            ),
          );
          expect(await trades.closeTrade(record), isA<Ok>());
        }
      }

      expect(given, [0, 2, 4, 5, 6, 7]);
      expect(await bindingRows(), hasLength(8));
    });

    test('two calls at once on one connection get two robots', () async {
      final results = await Future.wait([
        for (var i = 0; i < 10; i++) robots.robotForNewTrade(testnet, temple),
      ]);

      expect(
        {for (final result in results) robotOf(result).accountIndex},
        {for (var i = 0; i < 10; i++) i},
      );
      expect(await bindingRows(), hasLength(10));
    });

    test('a coordinator without an instance on the network is refused, and nothing is written', () async {
      // freeport has no testnet instance.
      expect(
        await robots.robotForNewTrade(testnet, coordinator('freeport')),
        refusedWith<TradeCoordinatorNotOnNetworkFailure>(),
      );
      expect(await bindingRows(), isEmpty);
    });

    test('a vault without the key, or that refuses it, gives its failure, and nothing is written', () async {
      for (final failure in const <P2pFailure>[
        GarageKeyMissingFailure(),
        GarageKeyLockedFailure(),
        GarageKeyUnreadableFailure(),
        GarageKeyUnusableFailure(),
      ]) {
        vault.slots[testnet] = Err(failure);
        final result = await robots.robotForNewTrade(testnet, temple);
        expect(
          result,
          isA<Err<NetworkRobot, P2pFailure>>().having(
            (err) => err.failure,
            'failure',
            same(failure),
          ),
        );
      }
      vault.slots.remove(testnet);
      expect(
        await robots.robotForNewTrade(testnet, temple),
        refusedWith<GarageKeyMissingFailure>(),
      );
      expect(await bindingRows(), isEmpty);
    });
  });

  group('a key from elsewhere never gives a robot for a new trade', () {
    for (final (label, records) in <(String, List<String>)>[
      ('no record of its draw', []),
      ('imported', ['imported testnet']),
      ('acknowledged', ['imported testnet', 'acknowledged testnet']),
      ('drawn here, then pasted into the other slot', ['generated testnet', 'imported mainnet']),
      ('drawn here, and acknowledged in the other slot', ['generated testnet', 'acknowledged mainnet']),
      ('drawn here, then imported again', ['generated testnet', 'imported testnet']),
    ]) {
      test(label, () async {
        for (final record in records) {
          final [origin, networkName] = record.split(' ');
          final network = RobosatsNetwork.values.byName(networkName);
          final written = switch (origin) {
            'generated' => await bindings.recordGeneratedKey(network, fingerprintA),
            'imported' => await bindings.recordImportedKey(network, fingerprintA),
            _ => await bindings.recordAcknowledgedKey(network, fingerprintA),
          };
          expect(written, isA<Ok>());
        }

        expect(
          await robots.robotForNewTrade(testnet, temple),
          refusedWith<GarageKeyNotForTradesFailure>(),
        );
        expect(await bindingRows(), isEmpty);
      });
    }

    test('nor a robot of a pasted key that the Garage bound', () async {
      expect(await bindings.recordImportedKey(testnet, fingerprintA), isA<Ok>());
      expect(await bindings.recordAcknowledgedKey(testnet, fingerprintA), isA<Ok>());
      expect(await bindings.bind(RobotSlot(testnet, fingerprintA, 0), templeTestnet), isA<Ok>());

      expect(
        await robots.robotForNewTrade(testnet, temple),
        refusedWith<GarageKeyNotForTradesFailure>(),
      );
      expect(
        await trades.recordPendingTake(
              RobotSlot(testnet, fingerprintA, 0),
          templeTestnet,
          orderId: 1,
          role: TradeRole.buyer,
        ),
        refusedWith<RobotNotForNewTradeFailure>(),
      );
    });
  });

  group('killed between the binding and the pending take', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('p2p-trade-robots-');
    });

    tearDown(() => directory.delete(recursive: true));

    test(
      'the next call takes the next robot: the one bound stays bound to its coordinator, without a trade, and is never returned again',
      () async {
        final first = P2pDatabase.open(() async => directory);
        expect(
          await bindingsInMemory(database: first).recordGeneratedKey(
            testnet,
            fingerprintA,
          ),
          isA<Ok>(),
        );
        final before = InterimTradeRobots(
          vault,
          TradeRecordRepositoryImpl(first, clock: () => testNow),
        );
        final orphan = robotOf(await before.robotForNewTrade(testnet, temple));
        // The app is killed here: no pending take was written.
        await first.close();

        final reopened = P2pDatabase.open(() async => directory);
        final records = TradeRecordRepositoryImpl(reopened, clock: () => testNow);
        final after = InterimTradeRobots(vault, records);
        final next = robotOf(await after.robotForNewTrade(testnet, lake));
        expect(next.accountIndex, orphan.accountIndex + 1);
        final record = recordOf(
          await records.recordPendingTake(
              next.slot,
            identityOf('lake', testnet),
            orderId: 5,
            role: TradeRole.buyer,
          ),
        );
        expect(record.isPendingTake, isTrue);
        // The orphan: bound to temple for good, as every binding is, with no record, and skipped by every later call.
        expect(
          await bindingsInMemory(database: reopened).standingOf(orphan.slot),
          isA<Ok<RobotStanding, P2pFailure>>().having(
            (ok) => ok.value.binding?.coordinator,
            'coordinator',
            templeTestnet,
          ),
        );
        expect(
          robotOf(await after.robotForNewTrade(testnet, temple)).accountIndex,
          next.accountIndex + 1,
        );
        expect(
          [
            for (final row in await reopened.select(reopened.trades).get())
              row.robotIndex,
          ],
          [next.accountIndex],
        );
        await reopened.close();
      },
    );

    test(
      'two connections asking at once never get the same robot',
      () async {
        final databases = [
          P2pDatabase.open(() async => directory),
          P2pDatabase.open(() async => directory),
        ];
        await openInTurn(databases);
        expect(
          await bindingsInMemory(database: databases.first).recordGeneratedKey(
            testnet,
            fingerprintA,
          ),
          isA<Ok>(),
        );
        final layers = [
          for (final database in databases)
            InterimTradeRobots(
              vault,
              TradeRecordRepositoryImpl(database, clock: () => testNow),
            ),
        ];
        final asked = [temple, lake];

        // Eight calls on each connection, all started together; a call that gave up on SQLite's busy timeout is asked again.
        final calls = [
          for (var i = 0; i < 8; i++)
            for (var c = 0; c < 2; c++)
              (
                coordinator: asked[c].shortAlias,
                result: untilNotBusy(
                  () => layers[c].robotForNewTrade(testnet, asked[c]),
                ),
              ),
        ];
        final results = [
          for (final call in calls)
            (coordinator: call.coordinator, robot: robotOf(await call.result)),
        ];
        for (final database in databases) {
          await database.close();
        }

        final indexes = [for (final r in results) r.robot.accountIndex];
        expect(indexes.toSet(), hasLength(16), reason: '$indexes');
        final reopened = P2pDatabase.open(() async => directory);
        final stored = {
          for (final row in await reopened.select(reopened.robotBindings).get())
            row.robotIndex: row.coordinatorAlias,
        };
        await reopened.close();
        expect(stored, hasLength(16));
        for (final r in results) {
          expect(stored[r.robot.accountIndex], r.coordinator);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('the robot of a recorded trade', () {
    late TradeRecord record;

    setUp(() async {
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), isA<Ok>());
      final robot = robotOf(await robots.robotForNewTrade(testnet, temple));
      robotOf(await robots.robotForNewTrade(testnet, temple));
      final second = robotOf(await robots.robotForNewTrade(testnet, temple));
      expect(robot.accountIndex, 0);
      record = recordOf(
        await trades.recordPendingTake(
              second.slot,
          templeTestnet,
          orderId: 9,
          role: TradeRole.buyer,
        ),
      );
    });

    test('is derived from the key the vault holds for its network', () async {
      expect(
        robotOf(await robots.robotOfTrade(record)),
        robotOf(NetworkGarageKey(testnet, keyA).firstUsableRobot(2)),
      );
    });

    test('is refused when the vault holds another key, or none', () async {
      vault.slots[testnet] = Ok(NetworkGarageKey(testnet, keyB));
      expect(
        await robots.robotOfTrade(record),
        refusedWith<TradeKeyMissingFailure>(),
      );
      vault.slots.remove(testnet);
      expect(
        await robots.robotOfTrade(record),
        refusedWith<TradeKeyMissingFailure>(),
      );
      vault.slots[testnet] = const Err(GarageKeyLockedFailure());
      expect(
        await robots.robotOfTrade(record),
        refusedWith<GarageKeyLockedFailure>(),
      );
    });

    test('the active trades are the records\'', () async {
      expect(
        await robots.activeTrades(testnet).first,
        isA<Ok<List<TradeRecord>, P2pFailure>>().having(
          (ok) => ok.value,
          'active',
          [record],
        ),
      );
    });
  });

  test('nothing printed or logged on these paths holds a key, a token or a fingerprint', () async {
    late NetworkRobot robot;
    final output = await captureKeyOutput(() async {
      expect(await bindings.recordGeneratedKey(testnet, fingerprintA), isA<Ok>());
      robot = robotOf(await robots.robotForNewTrade(testnet, temple));
      final record = recordOf(
        await trades.recordPendingTake(
              robot.slot,
          templeTestnet,
          orderId: 9,
          role: TradeRole.buyer,
        ),
      );
      expect(await trades.confirmTake(record), isA<Ok>());
      expect(await robots.robotOfTrade(record), isA<Ok>());
      expect(await trades.closeTrade(record), isA<Ok>());
      vault.slots[testnet] = Ok(NetworkGarageKey(testnet, keyB));
      expect(await robots.robotOfTrade(record), isA<Err>());
      vault.slots[testnet] = const Err(GarageKeyLockedFailure());
      expect(await robots.robotForNewTrade(testnet, temple), isA<Err>());
    });

    expectNoKeyIn(output, [keyA, keyB]);
    for (final (index, secret) in [
      fingerprintA.hex,
      robot.identity.token.reveal(),
      robot.identity.tokenSha256Hex,
      robot.identity.tokenSha256Base91,
    ].indexed) {
      expect(output.contains(secret), isFalse, reason: 'form $index');
    }
  });
}
