import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:test/test.dart';

import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;
import 'schema8_rows.dart';

/// The step from schema 9 to schema 10 of `p2p.sqlite` (#81, design note `docs/design/garage-key-from-the-words.md` § 2, § 8): three new tables and their triggers, and no row of schema 9 copied, changed or deleted: nothing is erased, and the records of the key the vault kept before #81, the external Garage Key since, stay under its fingerprint. That its trade in progress goes on after the update is played in `test/garage_key_repository_test.dart`.
///
/// The file of schema 9 holds a row in each of its ten tables (review of #292, C-mig): the file of `schema8_rows.dart` (trades open and closed, taken, made and recovered, a bond and an escrow paid, a chat's pins, a maker's terms), stepped to schema 9 by the app's own step, which marks the payouts of the buyers' contracts under way, then made a file of schema 9 as an APK of schema 9 leaves it. Every row is compared before and after, value and storage class.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('p2p-schema10-');
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

  /// A file of schema 9 holding a row in every table: the file of schema 8 of [schema8Rows], stepped to schema 9 by the app, its objects of schema 10 and 11 removed and its version set back to 9, as an APK of schema 9 leaves it; checked against the generated schema 9.
  Future<File> schema9File() async {
    final file = File('${directory.path}/nine.sqlite');
    final eight = v8.DatabaseAtV8(NativeDatabase(file));
    for (final statement in schema8Rows) {
      await eight.customStatement(statement);
    }
    await eight.close();
    final stepped = P2pDatabase.forTesting(NativeDatabase(file));
    expect(await versionOf(stepped), P2pDatabase.schema);
    await stepped.close();
    final nine = v9.DatabaseAtV9(
      NativeDatabase(
        file,
        setup: (raw) {
          for (final statement in [
            'DROP TRIGGER derived_garage_keys_never_deleted',
            'DROP TRIGGER derived_garage_keys_never_changed',
            'DROP TRIGGER derived_garage_keys_in_order',
            'DROP TRIGGER derived_garage_keys_inserted_once',
            'DROP TRIGGER garage_notices_shown_once',
            'DROP TRIGGER garage_notices_never_deleted',
            'DROP TRIGGER garage_recovery_notes_never_deleted',
            'DROP TRIGGER garage_recovery_notes_forward',
            'DROP TABLE garage_recovery_notes',
            'DROP TABLE derived_garage_keys',
            'DROP TABLE selected_garage_keys',
            'DROP TABLE garage_notices',
            'PRAGMA user_version = 9',
          ]) {
            raw.execute(statement);
          }
        },
      ),
    );
    expect(await versionOf(nine), 9);
    await nine.validateDatabaseSchema();
    await nine.close();
    return file;
  }

  test(
    'a file of schema 9 with a row in every table keeps every row, value and storage class, gains the tables of a new file, empty, and erases nothing',
    () async {
      final file = await schema9File();
      final before = v9.DatabaseAtV9(NativeDatabase(file));
      final kept = {
        for (final table in await tablesOf(before))
          table: await rowsOf(before, table),
      };
      await before.close();
      expect(kept.keys, hasLength(10));
      expect(
        {for (final MapEntry(:key, :value) in kept.entries) key: value.length},
        {
          'garage_key_histories': 2,
          'robot_bindings': 12,
          'trades': 10,
          'trade_terms': 5,
          'trade_trails': 8,
          'trade_payments': 7,
          'trade_chat_pins': 1,
          'trade_chat_nostr_pins': 1,
          'maker_terms': 4,
          'trade_payouts': 4,
        },
      );

      final migrated = P2pDatabase.forTesting(NativeDatabase(file));
      expect(await versionOf(migrated), P2pDatabase.schema);
      await migrated.validateDatabaseSchema();
      for (final MapEntry(key: table, value: rows) in kept.entries) {
        expect(await rowsOf(migrated, table), rows, reason: table);
      }
      for (final table in [
        'derived_garage_keys',
        'selected_garage_keys',
        'garage_recovery_notes',
      ]) {
        expect(await rowsOf(migrated, table), isEmpty, reason: table);
      }
      // The one row the step writes, in its own new table: « Your Garage Keys » due, since this is an update.
      expect(await rowsOf(migrated, 'garage_notices'), [
        "text:'externalKeyNamed' | integer:0",
      ]);
      expect(
        await tablesOf(migrated),
        [
          ...kept.keys,
          'derived_garage_keys',
          'garage_notices',
          'garage_recovery_notes',
          'selected_garage_keys',
        ]..sort(),
      );
      final fresh = P2pDatabase.forTesting(NativeDatabase.memory());
      expect(await namesOf(migrated), await namesOf(fresh));
      await fresh.close();
      await migrated.close();
    },
  );

  test('the step run again over a file it left changes nothing', () async {
    final file = await schema9File();
    final first = P2pDatabase.forTesting(NativeDatabase(file));
    final once = {
      for (final table in await tablesOf(first))
        table: await rowsOf(first, table),
    };
    await first.close();
    // Back to version 9 as the connection opens, as a run killed before drift wrote the version leaves it.
    final again = P2pDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (raw) => raw.execute('PRAGMA user_version = 9'),
      ),
    );
    expect(await versionOf(again), P2pDatabase.schema);
    for (final MapEntry(key: table, value: rows) in once.entries) {
      expect(await rowsOf(again, table), rows, reason: table);
    }
    await again.close();
  });

  test(
    'a new file of schema 10 has the same tables and triggers as a migrated one, empty',
    () async {
      final fresh = P2pDatabase.forTesting(NativeDatabase.memory());
      expect(await versionOf(fresh), P2pDatabase.schema);
      for (final table in [
        'derived_garage_keys',
        'selected_garage_keys',
        'garage_notices',
      ]) {
        expect(await rowsOf(fresh, table), isEmpty, reason: table);
      }
      expect(
        await namesOf(fresh),
        containsAll([
          'table selected_garage_keys',
          'table garage_notices',
          'trigger garage_notices_shown_once',
          'trigger garage_notices_never_deleted',
        ]),
      );
      await fresh.close();
    },
  );
}
