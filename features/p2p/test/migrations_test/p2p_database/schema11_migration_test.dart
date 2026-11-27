import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:test/test.dart';

import 'generated/schema_v10.dart' as v10;
import 'generated/schema_v8.dart' as v8;
import 'schema8_rows.dart';

/// The step from schema 10 to schema 11 of `p2p.sqlite` (#81, design note `docs/design/garage-key-from-the-words.md` § 3, « As PR 3 built it »): one new table, what this device read of the recovery notes, and its three triggers; no row of schema 10 copied, changed or deleted, and no row written.
///
/// The file of schema 10 holds a row in each of its thirteen tables: the file of `schema8_rows.dart`, stepped by the app's own steps, with a key of the words activated and selected, then made a file of schema 10 as an APK of schema 10 leaves it. Every row is compared before and after, value and storage class.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('p2p-schema11-');
  });

  tearDown(() => directory.delete(recursive: true));

  /// The tables of [database], but drift's and SQLite's own.
  Future<List<String>> tablesOf(GeneratedDatabase database) async => [
    for (final row
        in await database
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
            )
            .get())
      row.read<String>('name'),
  ];

  /// Every row of [table] in [database], ordered by its rowid, each column as its storage class and its value quoted.
  Future<List<String>> rowsOf(GeneratedDatabase database, String table) async {
    final columns = [
      for (final row
          in await database
              .customSelect(
                'SELECT name FROM pragma_table_info(?) ORDER BY cid',
                variables: [Variable.withString(table)],
              )
              .get())
        row.read<String>('name'),
    ];
    return [
      for (final row
          in await database
              .customSelect(
                'SELECT ${[for (final column in columns) "typeof($column) || ':' || quote($column)"].join(" || ' | ' || ")} AS line '
                'FROM $table ORDER BY rowid',
              )
              .get())
        row.read<String>('line'),
    ];
  }

  Future<Set<String>> namesOf(GeneratedDatabase database) async => {
    for (final row
        in await database
            .customSelect(
              "SELECT type || ' ' || name AS name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
            )
            .get())
      row.read<String>('name'),
  };

  Future<int> versionOf(GeneratedDatabase database) async =>
      (await database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version');

  /// A file of schema 10 holding a row in every table, its objects of schema 11 removed and its version set back to 10; checked against the generated schema 10.
  Future<File> schema10File() async {
    final file = File('${directory.path}/ten.sqlite');
    final eight = v8.DatabaseAtV8(NativeDatabase(file));
    for (final statement in schema8Rows) {
      await eight.customStatement(statement);
    }
    await eight.close();
    final stepped = P2pDatabase.forTesting(NativeDatabase(file));
    expect(await versionOf(stepped), P2pDatabase.schema);
    await stepped.customStatement(
      "INSERT INTO derived_garage_keys (network, key_index, key_fingerprint, activated_at) VALUES ('mainnet', 0, '${'ab' * 32}', 5)",
    );
    await stepped.customStatement(
      "INSERT INTO selected_garage_keys (network, key_index, last_internal_index) VALUES ('mainnet', 0, 0)",
    );
    await stepped.close();
    final ten = v10.DatabaseAtV10(
      NativeDatabase(
        file,
        setup: (raw) {
          for (final statement in [
            'DROP TRIGGER garage_recovery_notes_never_deleted',
            'DROP TRIGGER garage_recovery_notes_inserted_once',
            'DROP TRIGGER garage_recovery_notes_forward',
            'DROP TABLE garage_recovery_notes',
            'PRAGMA user_version = 10',
          ]) {
            raw.execute(statement);
          }
        },
      ),
    );
    expect(await versionOf(ten), 10);
    await ten.validateDatabaseSchema();
    await ten.close();
    return file;
  }

  test(
    'a file of schema 10 with a row in every table keeps every row, value and storage class, and gains the table of a new file, empty',
    () async {
      final file = await schema10File();
      final before = v10.DatabaseAtV10(NativeDatabase(file));
      final kept = {
        for (final table in await tablesOf(before))
          table: await rowsOf(before, table),
      };
      await before.close();
      expect(kept.keys, hasLength(13));
      for (final MapEntry(key: table, value: rows) in kept.entries) {
        expect(rows, isNotEmpty, reason: table);
      }

      final migrated = P2pDatabase.forTesting(NativeDatabase(file));
      expect(await versionOf(migrated), 11);
      await migrated.validateDatabaseSchema();
      for (final MapEntry(key: table, value: rows) in kept.entries) {
        expect(await rowsOf(migrated, table), rows, reason: table);
      }
      expect(await rowsOf(migrated, 'garage_recovery_notes'), isEmpty);
      expect(
        await tablesOf(migrated),
        [...kept.keys, 'garage_recovery_notes']..sort(),
      );
      final fresh = P2pDatabase.forTesting(NativeDatabase.memory());
      expect(await namesOf(migrated), await namesOf(fresh));
      await fresh.close();
      await migrated.close();
    },
  );

  test('the step run again over a file it left changes nothing', () async {
    final file = await schema10File();
    final first = P2pDatabase.forTesting(NativeDatabase(file));
    final once = {
      for (final table in await tablesOf(first))
        table: await rowsOf(first, table),
    };
    await first.close();
    final again = P2pDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (raw) => raw.execute('PRAGMA user_version = 10'),
      ),
    );
    expect(await versionOf(again), 11);
    for (final MapEntry(key: table, value: rows) in once.entries) {
      expect(await rowsOf(again, table), rows, reason: table);
    }
    await again.close();
  });

  test(
    'the floor only goes up, a reading recorded stays, a row is written once, even by INSERT OR REPLACE, and never deleted',
    () async {
      final database = P2pDatabase.forTesting(NativeDatabase.memory());
      final key = 'cd' * 32;
      await database.customStatement(
        "INSERT INTO garage_recovery_notes VALUES ('mainnet', '$key', 5, 100)",
      );
      for (final change in [
        'account_floor = 4',
        'account_floor = NULL',
        'read_at = NULL',
        'read_at = 200',
        "network = 'testnet'",
        "key_fingerprint = '${'ef' * 32}'",
      ]) {
        await expectLater(
          database.customStatement('UPDATE garage_recovery_notes SET $change'),
          throwsA(isA<Exception>()),
          reason: change,
        );
      }
      await database.customStatement(
        'UPDATE garage_recovery_notes SET account_floor = 9',
      );
      await expectLater(
        database.customStatement('DELETE FROM garage_recovery_notes'),
        throwsA(isA<Exception>()),
      );
      // A second insert of the row writes nothing, `INSERT OR REPLACE` included, whose delete fires no trigger (review of #302): the floor and the reading stay.
      for (final insert in [
        'INSERT OR REPLACE INTO',
        'REPLACE INTO',
        'INSERT OR IGNORE INTO',
        'INSERT INTO',
      ]) {
        await database.customStatement(
          "$insert garage_recovery_notes VALUES ('mainnet', '$key', NULL, NULL)",
        );
      }
      for (final row in [
        "('mainnet', '${'0' * 63}', NULL, NULL)",
        "('mainnet', '${'A' * 64}', NULL, NULL)",
        "('signet', '${'1' * 64}', NULL, NULL)",
        "('mainnet', '${'2' * 64}', -1, NULL)",
        "('mainnet', '${'3' * 64}', 2147483648, NULL)",
      ]) {
        await expectLater(
          database.customStatement(
            'INSERT INTO garage_recovery_notes VALUES $row',
          ),
          throwsA(isA<Exception>()),
          reason: row,
        );
      }
      expect(await rowsOf(database, 'garage_recovery_notes'), [
        "text:'mainnet' | text:'$key' | integer:9 | integer:100",
      ]);
      await database.close();
    },
  );
}
