import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import '../../support/fakes.dart';
import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

/// The schema of `p2p.sqlite` against its snapshots (`lib/src/data/schemas/`, written by `make drift-migrations`), and the step from each version to the next over a file that holds rows.
///
/// A change to the tables without a new version and its snapshot fails here; once a version ships, its snapshot never changes, and every later version adds an idempotent step from it.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the version of the database is its last snapshot', () {
    expect(GeneratedHelper.versions.last, P2pDatabase.schema);
  });

  test('the tables of the database are those of its snapshot', () async {
    final schema = await verifier.schemaAt(P2pDatabase.schema);
    final database = P2pDatabase.forTesting(schema.newConnection());

    await verifier.migrateAndValidate(database, P2pDatabase.schema);
    await database.close();
  });

  // Each step from every older snapshot to every newer one, with no data.
  const versions = GeneratedHelper.versions;
  for (final (i, from) in versions.indexed) {
    for (final to in versions.skip(i + 1)) {
      test('migrates from $from to $to', () async {
        final schema = await verifier.schemaAt(from);
        final database = P2pDatabase.forTesting(schema.newConnection());

        await verifier.migrateAndValidate(database, to);
        await database.close();
      });
    }
  }

  test('a new database is created with the tables it declares', () async {
    final database = P2pDatabase.forTesting(NativeDatabase.memory());

    await database.validateDatabaseSchema();
    await database.close();
  });

  group('a file of schema 1 with rows', () {
    const testnet = RobosatsNetwork.testnet;
    const mainnet = RobosatsNetwork.mainnet;

    // Fixed test bytes: not keys anyone uses.
    GarageKeyFingerprint fingerprintOf(int first) =>
        switch (GarageKey.fromBytes(
          Uint8List.fromList(List<int>.generate(32, (i) => first + i)),
        )) {
          Ok(value: final key) => switch (GarageKeyFingerprint.of(key)) {
            Ok(:final value) => value,
            Err(:final failure) => throw StateError('$failure'),
          },
          Err(:final failure) => throw StateError('$failure'),
        };
    final fingerprintA = fingerprintOf(1);
    final fingerprintB = fingerprintOf(2);

    CoordinatorIdentity identityOf(String alias, RobosatsNetwork network) =>
        switch (CoordinatorIdentity.of(coordinator(alias), network)) {
          final identity? => identity,
          null => throw StateError('$alias is not on $network'),
        };
    final templeTestnet = identityOf('temple', testnet);
    final lakeMainnet = identityOf('lake', mainnet);
    final templeMainnet = identityOf('temple', mainnet);

    // What schema 1 held: keys drawn here and imported, on both networks, and bindings on both networks.
    final histories = [
      (testnet, fingerprintA, 'generated', 1),
      (mainnet, fingerprintA, 'imported', 2),
      (testnet, fingerprintB, 'imported', 3),
      (mainnet, fingerprintB, 'generated', 4),
    ];
    final bindings = [
      (fingerprintA, 0, templeTestnet, 10),
      (fingerprintA, 3, lakeMainnet, 11),
      (fingerprintB, 1, lakeMainnet, 12),
    ];

    late Directory directory;
    late File file;

    /// Writes [file] as the tables of schema 1 make it, with [histories] and [bindings], then closes it.
    Future<void> writeSchema1() async {
      final old = v1.DatabaseAtV1(NativeDatabase(file));
      for (final (network, fingerprint, origin, at) in histories) {
        await old
            .into(old.garageKeyHistories)
            .insert(
              v1.GarageKeyHistoriesCompanion.insert(
                network: network.name,
                keyFingerprint: fingerprint.hex,
                origin: origin,
                recordedAt: at,
              ),
            );
      }
      for (final (fingerprint, index, coordinator, at) in bindings) {
        await old
            .into(old.robotBindings)
            .insert(
              v1.RobotBindingsCompanion.insert(
                network: coordinator.network.name,
                keyFingerprint: fingerprint.hex,
                robotIndex: index,
                coordinatorAlias: coordinator.alias,
                coordinatorOnion: coordinator.onion,
                coordinatorNodeKeys: coordinator.nodeKeys.join(','),
                coordinatorNostrKey: coordinator.nostrKey,
                boundAt: at,
              ),
            );
      }
      expect(await versionOf(old), 1);
      await old.close();
    }

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('p2p-migration-');
      file = File('${directory.path}/${P2pDatabase.fileName}');
    });

    tearDown(() => directory.delete(recursive: true));

    /// Checks that [database] holds the rows of schema 1 as they were, every binding with the provenance `generated`.
    Future<void> expectRowsKept(P2pDatabase database) async {
      expect(
        {
          for (final row
              in await database.select(database.garageKeyHistories).get())
            (row.network, row.keyFingerprint, row.origin, row.recordedAt),
        },
        {
          for (final (network, fingerprint, origin, at) in histories)
            (network.name, fingerprint.hex, origin, at),
        },
      );
      expect(
        {
          for (final row in await database.select(database.robotBindings).get())
            (
              row.network,
              row.keyFingerprint,
              row.robotIndex,
              row.coordinatorAlias,
              row.coordinatorOnion,
              row.coordinatorNodeKeys,
              row.coordinatorNostrKey,
              row.boundAt,
              row.provenance,
            ),
        },
        {
          for (final (fingerprint, index, coordinator, at) in bindings)
            (
              coordinator.network.name,
              fingerprint.hex,
              index,
              coordinator.alias,
              coordinator.onion,
              coordinator.nodeKeys.join(','),
              coordinator.nostrKey,
              at,
              'generated',
            ),
        },
      );
    }

    test(
      'keeps every row, gives each binding the provenance of a key drawn here, and is not migrated again',
      () async {
        await writeSchema1();

        final first = P2pDatabase.open(() async => directory);
        await expectRowsKept(first);
        expect(await versionOf(first), P2pDatabase.schema);
        await first.validateDatabaseSchema();
        await first.close();

        // Opened a second time: nothing to migrate, the same rows.
        final second = P2pDatabase.open(() async => directory);
        expect(await versionOf(second), P2pDatabase.schema);
        await expectRowsKept(second);
        await second.validateDatabaseSchema();
        await second.close();
      },
    );

    test('its keys and bindings follow the rules of schema 2 once migrated', () async {
      await writeSchema1();
      final database = P2pDatabase.open(() async => directory);
      final repository = RobotBindingRepositoryImpl(
        database,
        clock: () => testNow,
      );
      final passes = isA<Ok<void, P2pFailure>>();

      // A binding of schema 1 stands as made under a key drawn here.
      expect(
        await repository.standingOf(RobotSlot(testnet, fingerprintA, 0)),
        isA<Ok<RobotStanding, P2pFailure>>().having(
          (ok) => ok.value,
          'standing',
          RobotStanding(
            network: testnet,
            binding: RobotBinding(
              templeTestnet,
              DateTime.fromMillisecondsSinceEpoch(10, isUtc: true),
              BindingProvenance.drawnHere,
            ),
            history: GarageKeyHistory.drawnHere,
          ),
        ),
      );
      // The imported key on mainnet: refused, then acknowledged and bound with that provenance.
      expect(
        await repository.bind(
          RobotSlot(mainnet, fingerprintA, 7),
          templeMainnet,
        ),
        isA<Err<void, P2pFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<RobotHistoryUnknownFailure>(),
        ),
      );
      expect(
        await repository.recordAcknowledgedKey(mainnet, fingerprintA),
        passes,
      );
      expect(
        await repository.bind(
          RobotSlot(mainnet, fingerprintA, 7),
          templeMainnet,
        ),
        passes,
      );
      // The key drawn here on testnet keeps that history.
      expect(
        await repository.recordAcknowledgedKey(testnet, fingerprintA),
        passes,
      );
      expect(
        await repository.bind(
          RobotSlot(testnet, fingerprintA, 8),
          templeTestnet,
        ),
        passes,
      );
      final provenances = {
        for (final row in await database.select(database.robotBindings).get())
          (row.keyFingerprint, row.robotIndex): row.provenance,
      };
      expect(provenances[(fingerprintA.hex, 7)], 'acknowledged');
      expect(provenances[(fingerprintA.hex, 8)], 'generated');
      expect(provenances[(fingerprintA.hex, 0)], 'generated');

      // The widened constraints take `acknowledged` and still refuse what no version writes, for a key and an index that have no row.
      for (final (sql, refused) in [
        (
          'INSERT INTO garage_key_histories (network, key_fingerprint, origin, recorded_at) VALUES (?, ?, ?, 0)',
          'elsewhere',
        ),
        (
          'INSERT INTO robot_bindings (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, coordinator_node_keys, coordinator_nostr_key, bound_at, provenance) VALUES (?, ?, 9, \'temple\', \'http://temple.onion\', \'\', \'nostr\', 0, ?)',
          'imported',
        ),
      ]) {
        List<Variable<Object>> row(String fingerprint, String value) => [
          Variable.withString('testnet'),
          Variable.withString(fingerprint),
          Variable.withString(value),
        ];
        await expectLater(
          database.customInsert(sql, variables: row('c' * 64, refused)),
          // The connection runs in its own isolate, and the error it sends back carries SQLite's: 275 is a failed CHECK, not the primary key.
          throwsA(
            predicate((error) => '$error'.contains('SqliteException(275)')),
          ),
          reason: refused,
        );
        await database.customInsert(
          sql,
          variables: row('d' * 64, 'acknowledged'),
        );
      }
      await database.close();
    });

    test(
      'every commit is still synced to disk, in write-ahead logging',
      () async {
        await writeSchema1();
        final database = P2pDatabase.open(() async => directory);

        expect(await versionOf(database), P2pDatabase.schema);
        expect(
          (await database.customSelect('PRAGMA synchronous').getSingle())
              .data
              .values
              .single,
          2,
        );
        expect(
          (await database.customSelect('PRAGMA journal_mode').getSingle())
              .data
              .values
              .single,
          'wal',
        );
        await database.close();
      },
    );

    test('a step that stopped halfway runs again over the file it left', () async {
      // Stopped after the column was added, before the version was written; then stopped after the histories were rebuilt.
      for (final halfway in [
        'ALTER TABLE robot_bindings ADD COLUMN provenance TEXT NOT NULL DEFAULT \'generated\' CHECK (provenance IN (\'generated\', \'acknowledged\'))',
        'CREATE TABLE garage_key_histories_widened (network TEXT NOT NULL, key_fingerprint TEXT NOT NULL, origin TEXT NOT NULL, recorded_at INTEGER NOT NULL, PRIMARY KEY (network, key_fingerprint), CHECK (network IN (\'mainnet\', \'testnet\')), CHECK (length(key_fingerprint) = 64), CHECK (origin IN (\'generated\', \'imported\', \'acknowledged\')))',
      ]) {
        for (final name in [
          P2pDatabase.fileName,
          '${P2pDatabase.fileName}-wal',
          '${P2pDatabase.fileName}-shm',
        ]) {
          final leftover = File('${directory.path}/$name');
          if (leftover.existsSync()) leftover.deleteSync();
        }
        await writeSchema1();
        final raw = NativeDatabase(file);
        final half = v1.DatabaseAtV1(raw);
        if (halfway.startsWith('CREATE')) {
          await half.customStatement(halfway);
          await half.customStatement(
            'INSERT INTO garage_key_histories_widened SELECT * FROM garage_key_histories',
          );
          await half.customStatement('DROP TABLE garage_key_histories');
          await half.customStatement(
            'ALTER TABLE garage_key_histories_widened RENAME TO garage_key_histories',
          );
        } else {
          await half.customStatement(halfway);
        }
        expect(await versionOf(half), 1);
        await half.close();

        final database = P2pDatabase.open(() async => directory);
        await expectRowsKept(database);
        expect(await versionOf(database), P2pDatabase.schema);
        await database.validateDatabaseSchema();
        await database.close();
      }
    });
  });

  group('a file of schema 2 with rows', () {
    const testnet = RobosatsNetwork.testnet;
    const mainnet = RobosatsNetwork.mainnet;

    // Fixed test bytes: not keys anyone uses.
    GarageKeyFingerprint fingerprintOf(int first) =>
        switch (GarageKey.fromBytes(
          Uint8List.fromList(List<int>.generate(32, (i) => first + i)),
        )) {
          Ok(value: final key) => switch (GarageKeyFingerprint.of(key)) {
            Ok(:final value) => value,
            Err(:final failure) => throw StateError('$failure'),
          },
          Err(:final failure) => throw StateError('$failure'),
        };
    final drawn = fingerprintOf(1);
    final pasted = fingerprintOf(2);
    final both = fingerprintOf(3);

    CoordinatorIdentity identityOf(String alias, RobosatsNetwork network) =>
        switch (CoordinatorIdentity.of(coordinator(alias), network)) {
          final identity? => identity,
          null => throw StateError('$alias is not on $network'),
        };
    final templeTestnet = identityOf('temple', testnet);
    final lakeTestnet = identityOf('lake', testnet);
    final lakeMainnet = identityOf('lake', mainnet);

    // What schema 2 holds: keys of every origin on both networks, and bindings of both provenances on both networks.
    final histories = [
      (testnet, drawn, 'generated', 1),
      (mainnet, drawn, 'generated', 2),
      (testnet, pasted, 'acknowledged', 3),
      (mainnet, pasted, 'imported', 4),
      (testnet, both, 'generated', 5),
      (mainnet, both, 'acknowledged', 6),
    ];
    final bindings = [
      (drawn, 0, templeTestnet, 10, 'generated'),
      (drawn, 2, lakeMainnet, 11, 'generated'),
      (pasted, 0, templeTestnet, 12, 'acknowledged'),
      (pasted, 5, lakeTestnet, 13, 'acknowledged'),
      (both, 1, lakeMainnet, 14, 'acknowledged'),
      (both, 4, templeTestnet, 15, 'generated'),
    ];

    late Directory directory;
    late File file;

    /// Writes [file] as the tables of schema 2 make it, with [histories] and [bindings], then closes it.
    Future<void> writeSchema2() async {
      for (final name in [
        P2pDatabase.fileName,
        '${P2pDatabase.fileName}-wal',
        '${P2pDatabase.fileName}-shm',
      ]) {
        final leftover = File('${directory.path}/$name');
        if (leftover.existsSync()) leftover.deleteSync();
      }
      final old = v2.DatabaseAtV2(NativeDatabase(file));
      for (final (network, fingerprint, origin, at) in histories) {
        await old
            .into(old.garageKeyHistories)
            .insert(
              v2.GarageKeyHistoriesCompanion.insert(
                network: network.name,
                keyFingerprint: fingerprint.hex,
                origin: origin,
                recordedAt: at,
              ),
            );
      }
      for (final (fingerprint, index, coordinator, at, provenance)
          in bindings) {
        await old
            .into(old.robotBindings)
            .insert(
              v2.RobotBindingsCompanion.insert(
                network: coordinator.network.name,
                keyFingerprint: fingerprint.hex,
                robotIndex: index,
                coordinatorAlias: coordinator.alias,
                coordinatorOnion: coordinator.onion,
                coordinatorNodeKeys: coordinator.nodeKeys.join(','),
                coordinatorNostrKey: coordinator.nostrKey,
                boundAt: at,
                provenance: Value(provenance),
              ),
            );
      }
      expect(await versionOf(old), 2);
      await old.close();
    }

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('p2p-migration-');
      file = File('${directory.path}/${P2pDatabase.fileName}');
    });

    tearDown(() => directory.delete(recursive: true));

    /// Every row of [database], every table, as SQLite gives it.
    Future<Map<String, List<Map<String, Object?>>>> rowsOf(
      GeneratedDatabase database,
    ) async => {
      for (final table in ['garage_key_histories', 'robot_bindings', 'trades'])
        table: [
          for (final row
              in await database
                  .customSelect('SELECT * FROM $table ORDER BY rowid')
                  .get())
            row.data,
        ],
    };

    /// The schema of [database] as SQLite stores it: each table, index and trigger with its SQL.
    Future<List<Map<String, Object?>>> schemaOf(
      GeneratedDatabase database,
    ) async => [
      for (final row
          in await database
              .customSelect(
                'SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY name',
              )
              .get())
        row.data,
    ];

    /// Checks that [database] holds the rows of schema 2 as they were, and no trade.
    Future<void> expectRowsKept(P2pDatabase database) async {
      expect(
        {
          for (final row
              in await database.select(database.garageKeyHistories).get())
            (row.network, row.keyFingerprint, row.origin, row.recordedAt),
        },
        {
          for (final (network, fingerprint, origin, at) in histories)
            (network.name, fingerprint.hex, origin, at),
        },
      );
      expect(
        {
          for (final row in await database.select(database.robotBindings).get())
            (
              row.network,
              row.keyFingerprint,
              row.robotIndex,
              row.coordinatorAlias,
              row.coordinatorOnion,
              row.coordinatorNodeKeys,
              row.coordinatorNostrKey,
              row.boundAt,
              row.provenance,
            ),
        },
        {
          for (final (fingerprint, index, coordinator, at, provenance)
              in bindings)
            (
              coordinator.network.name,
              fingerprint.hex,
              index,
              coordinator.alias,
              coordinator.onion,
              coordinator.nodeKeys.join(','),
              coordinator.nostrKey,
              at,
              provenance,
            ),
        },
      );
      expect(await database.select(database.trades).get(), isEmpty);
    }

    test(
      'keeps every row, adds an empty table of trades, and is not migrated again',
      () async {
        await writeSchema2();

        final first = P2pDatabase.open(() async => directory);
        await expectRowsKept(first);
        expect(await versionOf(first), 3);
        await first.validateDatabaseSchema();
        await first.close();

        final second = P2pDatabase.open(() async => directory);
        expect(await versionOf(second), 3);
        await expectRowsKept(second);
        await second.validateDatabaseSchema();
        await second.close();
      },
    );

    test(
      'a file of schema 3 opened again is unchanged, rows and schema alike',
      () async {
        await writeSchema2();
        final first = P2pDatabase.open(() async => directory);
        final trades = TradeRecordRepositoryImpl(first, clock: () => testNow);
        expect(
          await trades.reserveForNewTrade(
            RobotSlot(testnet, drawn, 1),
            templeTestnet,
          ),
          isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'bound', isTrue),
        );
        final pending = await trades.recordPendingTake(
          RobotSlot(testnet, drawn, 1),
          templeTestnet,
          orderId: 42,
          role: TradeRole.buyer,
        );
        expect(pending, isA<Ok<TradeRecord, P2pFailure>>());
        final rows = await rowsOf(first);
        final schema = await schemaOf(first);
        await first.close();

        final second = P2pDatabase.open(() async => directory);
        expect(await versionOf(second), 3);
        expect(await rowsOf(second), rows);
        expect(await schemaOf(second), schema);
        expect(rows['trades'], hasLength(1));
        await second.close();
      },
    );

    test('its keys and bindings follow the rules of schema 3 once migrated', () async {
      await writeSchema2();
      final database = P2pDatabase.open(() async => directory);
      final trades = TradeRecordRepositoryImpl(database, clock: () => testNow);
      Matcher refusedWith<T>() => isA<Err<Object?, P2pFailure>>().having(
        (err) => err.failure,
        'failure',
        isA<T>(),
      );

      // The foreign keys hold on the migrated file.
      expect(
        (await database.customSelect('PRAGMA foreign_keys').getSingle())
            .data
            .values
            .single,
        1,
      );
      // A key drawn here on both networks: its free indexes go to new trades, its bound ones never.
      expect(
        await trades.newTradeStandingOf(testnet, drawn),
        isA<Ok<NewTradeStanding, P2pFailure>>().having(
          (ok) => ok.value,
          'standing',
          NewTradeStanding(keyDrawnHereOnly: true, indexesInUse: [0, 2]),
        ),
      );
      for (final (index, bound) in [(0, false), (2, false), (1, true)]) {
        expect(
          await trades.reserveForNewTrade(
            RobotSlot(testnet, drawn, index),
            lakeTestnet,
          ),
          isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'bound', bound),
          reason: '$index',
        );
      }
      // A binding of schema 2 under a key drawn here takes a pending take; one of an acknowledged key, only a recovered trade.
      expect(
        await trades.recordPendingTake(
          RobotSlot(testnet, drawn, 0),
          templeTestnet,
          orderId: 1,
          role: TradeRole.buyer,
        ),
        isA<Ok<TradeRecord, P2pFailure>>(),
      );
      expect(
        await trades.recordPendingTake(
          RobotSlot(testnet, pasted, 0),
          templeTestnet,
          orderId: 2,
          role: TradeRole.buyer,
        ),
        refusedWith<RobotNotForNewTradeFailure>(),
      );
      expect(
        await trades.recordRecoveredTrade(
          RobotSlot(testnet, pasted, 0),
          templeTestnet,
          orderId: 2,
          role: TradeRole.seller,
        ),
        isA<Ok<TradeRecord, P2pFailure>>(),
      );
      // Keys from elsewhere, on either network, give no robot for a new trade.
      for (final key in [pasted, both]) {
        expect(
          await trades.reserveForNewTrade(
            RobotSlot(testnet, key, 9),
            templeTestnet,
          ),
          isA<Ok<bool, P2pFailure>>().having(
            (ok) => ok.value,
            'bound',
            isFalse,
          ),
        );
      }
      // A trade's robot needs its binding.
      await expectLater(
        database.customInsert(
          "INSERT INTO trades VALUES ('testnet', ?, 7, 'temple', 'o', 3, 'buyer', 'recovered', 0, 0, NULL, NULL, NULL, NULL)",
          variables: [Variable.withString(both.hex)],
        ),
        throwsA(
          predicate((error) => '$error'.contains('SqliteException(787)')),
        ),
      );
      await database.close();
    });

    test(
      'a step that stopped after the table was made runs again over the file it left',
      () async {
        await writeSchema2();
        // Stopped after the table was created, before the version was written.
        final half = v2.DatabaseAtV2(NativeDatabase(file));
        await half.customStatement(
          'CREATE TABLE trades (network TEXT NOT NULL, key_fingerprint TEXT NOT NULL, robot_index INTEGER NOT NULL, coordinator_alias TEXT NOT NULL, coordinator_onion TEXT NOT NULL, order_id INTEGER NOT NULL, role TEXT NOT NULL, origin TEXT NOT NULL, taken_at INTEGER NOT NULL, confirmed_at INTEGER NULL, closed_at INTEGER NULL, payment_hash TEXT NULL, payment_started_at INTEGER NULL, payment_swap_id TEXT NULL, PRIMARY KEY (key_fingerprint, robot_index), CHECK (network IN (\'mainnet\', \'testnet\')), CHECK (length(key_fingerprint) = 64), CHECK (robot_index BETWEEN 0 AND 2147483647), CHECK (length(coordinator_alias) > 0), CHECK (length(coordinator_onion) > 0), CHECK (order_id > 0), CHECK (role IN (\'buyer\', \'seller\')), CHECK (origin IN (\'takenHere\', \'recovered\')), CHECK (origin = \'takenHere\' OR confirmed_at IS NOT NULL), CHECK (payment_hash IS NULL OR (length(payment_hash) = 64 AND payment_hash NOT GLOB \'*[^0-9a-f]*\')), CHECK ((payment_hash IS NULL) = (payment_started_at IS NULL)), CHECK (payment_swap_id IS NULL OR (payment_started_at IS NOT NULL AND length(payment_swap_id) BETWEEN 1 AND 128)), FOREIGN KEY (key_fingerprint, robot_index) REFERENCES robot_bindings (key_fingerprint, robot_index))',
        );
        expect(await versionOf(half), 2);
        await half.close();

        final database = P2pDatabase.open(() async => directory);
        await expectRowsKept(database);
        expect(await versionOf(database), 3);
        await database.validateDatabaseSchema();
        await database.close();
      },
    );
  });
}

/// The `user_version` of [database], the schema version drift wrote.
Future<int> versionOf(GeneratedDatabase database) async =>
    (await database.customSelect('PRAGMA user_version').getSingle()).read<int>(
      'user_version',
    );
