import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:test/test.dart';

import 'generated/schema_v9.dart' as v9;

/// The step from schema 9 to schema 10 of `p2p.sqlite` (#81, design note `docs/design/garage-key-from-the-words.md` § 2, § 8): two new tables and their triggers, the switch written `legacy`, and no row of schema 9 copied, changed or deleted by the step itself; the book is emptied only when the file opens with no trade in progress, which `test/garage_key_repository_test.dart` plays.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('p2p-schema10-');
  });

  tearDown(() => directory.delete(recursive: true));

  const fingerprint =
      'aa00000000000000000000000000000000000000000000000000000000000000';

  /// A file of schema 9 with a key drawn here, two robots bound, an open trade and a closed one.
  Future<File> schema9File() async {
    final file = File('${directory.path}/nine.sqlite');
    final old = v9.DatabaseAtV9(NativeDatabase(file));
    for (final statement in [
      "INSERT INTO garage_key_histories (network, key_fingerprint, origin, recorded_at) VALUES ('testnet', '$fingerprint', 'generated', 1)",
      "INSERT INTO robot_bindings (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, coordinator_node_keys, coordinator_nostr_key, bound_at, provenance) VALUES ('testnet', '$fingerprint', 0, 'temple', 'http://temple.onion', '', 'abc', 2, 'generated')",
      "INSERT INTO robot_bindings (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, coordinator_node_keys, coordinator_nostr_key, bound_at, provenance) VALUES ('testnet', '$fingerprint', 1, 'temple', 'http://temple.onion', '', 'abc', 2, 'generated')",
      "INSERT INTO trades (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at) VALUES ('testnet', '$fingerprint', 0, 'temple', 'http://temple.onion', 41, 'buyer', 'takenHere', 3, 4, 5)",
      "INSERT INTO trades (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at) VALUES ('testnet', '$fingerprint', 1, 'temple', 'http://temple.onion', 42, 'seller', 'takenHere', 6, 7, NULL)",
    ]) {
      await old.customStatement(statement);
    }
    await old.close();
    return file;
  }

  Future<List<String>> rowsOf(GeneratedDatabase database, String table) async =>
      [
        for (final row
            in await database
                .customSelect('SELECT * FROM $table ORDER BY rowid')
                .get())
          '${row.data}',
      ];

  Future<Set<String>> namesOf(GeneratedDatabase database) async => {
    for (final row
        in await database
            .customSelect(
              "SELECT type || ' ' || name AS name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
            )
            .get())
      row.read<String>('name'),
  };

  test(
    'a file of schema 9 with a trade in progress keeps every row, gains the tables of a new file, and its switch waits',
    () async {
      final file = await schema9File();
      final before = v9.DatabaseAtV9(NativeDatabase(file));
      final kept = {
        for (final table in [
          'garage_key_histories',
          'robot_bindings',
          'trades',
        ])
          table: await rowsOf(before, table),
      };
      await before.close();

      final migrated = P2pDatabase.forTesting(NativeDatabase(file));
      expect(
        (await migrated.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        10,
      );
      for (final MapEntry(key: table, value: rows) in kept.entries) {
        expect(await rowsOf(migrated, table), rows, reason: table);
      }
      expect(await rowsOf(migrated, 'garage_switch'), [
        '{id: 1, state: legacy}',
      ]);
      expect(await rowsOf(migrated, 'derived_garage_keys'), isEmpty);
      final fresh = P2pDatabase.forTesting(NativeDatabase.memory());
      expect(await rowsOf(fresh, 'garage_switch'), ['{id: 1, state: derived}']);
      expect(await namesOf(migrated), await namesOf(fresh));
      await fresh.close();
      await migrated.close();
    },
  );

  test('the step run again over a file it left changes nothing', () async {
    final file = await schema9File();
    final first = P2pDatabase.forTesting(NativeDatabase(file));
    final once = await rowsOf(first, 'trades');
    await first.close();
    // Back to version 9 as the connection opens, as a run killed before drift wrote the version leaves it.
    final again = P2pDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (raw) => raw.execute('PRAGMA user_version = 9'),
      ),
    );
    expect(await rowsOf(again, 'trades'), once);
    expect(await rowsOf(again, 'garage_switch'), ['{id: 1, state: legacy}']);
    await again.close();
  });
}
