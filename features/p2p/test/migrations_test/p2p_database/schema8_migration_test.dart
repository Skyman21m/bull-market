import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:test/test.dart';

import 'generated/schema_v7.dart' as v7;

/// The step from schema 7 to schema 8 of `p2p.sqlite` (#176; design note `docs/design/phase-3-making-an-order.md` § 3.5) over a file of schema 7 that holds every shape of row a user's file can hold: open and closed trades, a pending take never sent, a recovered trade, two open trades of one order, terms, trails with and without the hashes of a bond and an escrow, payments of a bond and of an escrow (two of them of one payment hash), the PGP and Nostr pins of a chat, bindings with and without a trade, and the histories of two keys.
///
/// Every row is compared before and after, column by column, value and storage class; the step is stopped after each of its statements and run again; it refuses a connection whose foreign keys are on, and stops at schema 7, its copies kept, on a file with an orphan row.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('p2p-schema8-');
  });

  tearDown(() => directory.delete(recursive: true));

  /// A file of schema 7 at [name] in the test's directory, written by the generated schema 7 itself, its rows written in the order the app writes them, through schema 7's own triggers.
  Future<File> schema7File([String name = 'seven.sqlite']) async {
    final file = File('${directory.path}/$name');
    final old = v7.DatabaseAtV7(NativeDatabase(file));
    expect(await _versionOf(old), 7);
    for (final statement in _schema7Rows) {
      await old.customStatement(statement);
    }
    // Two open trades of one order, which no version wrote after schema 3 but a file of schema 3 could hold (the step from 3 kept them): the trigger that refuses a second one is set aside, then made again from its own text.
    final trigger = await old
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE name = 'trades_one_open_per_order'",
        )
        .getSingle();
    await old.customStatement('DROP TRIGGER trades_one_open_per_order');
    await old.customStatement(
      "INSERT INTO trades VALUES ('testnet', '$_key', 7, 'temple', 'http://temple.onion', 101, 'buyer', 'takenHere', 1700, NULL, NULL)",
    );
    await old.customStatement(trigger.read<String>('sql'));
    expect(await _versionOf(old), 7);
    await old.close();
    return file;
  }

  /// The copy of [file] at [name], for a second run over the same rows.
  File copyOf(File file, String name) =>
      file.copySync('${directory.path}/$name');

  test(
    'the file of schema 7 holds every shape of row the step must keep',
    () async {
      final file = await schema7File();
      final old = v7.DatabaseAtV7(NativeDatabase(file));
      final rows = await _rowsOf(old, _schema7Columns);
      await old.close();
      expect({for (final MapEntry(:key, :value) in rows.entries) key: value.length}, {
        'garage_key_histories': 3,
        'robot_bindings': 10,
        'trades': 8,
        'trade_terms': 6,
        'trade_trails': 6,
        'trade_payments': 6,
        'trade_chat_pins': 2,
        'trade_chat_nostr_pins': 2,
      });
    },
  );

  test(
    'keeps every row, every value and its storage class, gives the new columns their defaults, and is not migrated again',
    () async {
      final file = await schema7File();
      final old = v7.DatabaseAtV7(NativeDatabase(file));
      final before = await _rowsOf(old, _schema7Columns);
      await old.close();

      final migrated = P2pDatabase.forTesting(NativeDatabase(file));
      expect(await _versionOf(migrated), P2pDatabase.schema);
      await migrated.validateDatabaseSchema();
      expect(await _rowsOf(migrated, _schema7Columns), before);
      // The contract of a maker, which no trade of schema 7 has: 0 and nothing else, on every trail and every payment.
      expect(
        await _rowsOf(migrated, {
          'trade_trails': [
            'take',
            'take_deadline',
            'taker_hash_id',
            'taken_amount',
          ],
          'trade_payments': ['take'],
        }),
        {
          'trade_trails': List.filled(6, [
            'integer',
            0,
            'null',
            null,
            'null',
            null,
            'null',
            null,
          ]),
          'trade_payments': List.filled(6, ['integer', 0]),
        },
      );
      expect(
        await migrated.customSelect('SELECT * FROM maker_terms').get(),
        isEmpty,
      );
      // The copies are gone, the foreign keys hold and are on.
      expect(await _namesOf(migrated), isNot(contains(endsWith('_of_schema7'))));
      expect(
        await migrated.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      expect(
        (await migrated.customSelect('PRAGMA foreign_keys').getSingle())
            .data
            .values
            .single,
        1,
      );
      final objects = await _objectsOf(migrated);
      final rows = await _rowsOf(migrated, _schema8Columns);
      await migrated.close();

      // Its tables, indexes and triggers are a new file's, as written.
      final freshDirectory = await Directory.systemTemp.createTemp(
        'p2p-fresh-',
      );
      addTearDown(() => freshDirectory.delete(recursive: true));
      final fresh = P2pDatabase.open(() async => freshDirectory);
      expect(objects, await _objectsOf(fresh));
      await fresh.close();

      // Opened again: nothing is rebuilt, nothing moves.
      final again = P2pDatabase.forTesting(NativeDatabase(file));
      expect(await _versionOf(again), P2pDatabase.schema);
      expect(await _rowsOf(again, _schema8Columns), rows);
      expect(await _objectsOf(again), objects);
      await again.close();
    },
  );

  test(
    'the two payments of one hash and the two open trades of one order are kept, and a third of either is refused',
    () async {
      final file = await schema7File();
      final database = P2pDatabase.forTesting(NativeDatabase(file));
      expect(
        await database
            .customSelect(
              "SELECT robot_index FROM trade_payments WHERE payment_hash = '$_bondOfOne' ORDER BY robot_index",
            )
            .map((row) => row.read<int>('robot_index'))
            .get(),
        [1, 6],
      );
      expect(
        await database
            .customSelect(
              'SELECT robot_index FROM trades WHERE order_id = 101 AND closed_at IS NULL ORDER BY robot_index',
            )
            .map((row) => row.read<int>('robot_index'))
            .get(),
        [1, 7],
      );
      // A third pending take of order 101, by a robot bound with no trade.
      await expectLater(
        database.customStatement(
          "INSERT INTO trades VALUES ('testnet', '$_key', 8, 'temple', 'http://temple.onion', 101, 'buyer', 'takenHere', 1800, NULL, NULL)",
        ),
        throwsA(
          predicate((error) => '$error'.contains('an order has one open trade')),
        ),
      );
      // The hash of robot 1's bond, paid again as robot 2's escrow of its open trade.
      await expectLater(
        database.customStatement(
          "INSERT INTO trade_payments (key_fingerprint, robot_index, step, payment_hash, started_at) VALUES ('$_key', 2, 'bond', '$_bondOfOne', 9000)",
        ),
        throwsA(
          predicate((error) => '$error'.contains('an invoice is paid once')),
        ),
      );
      await database.close();
    },
  );

  test(
    'stopped after any of its statements, the step runs again over the file it left to the very file of a step that ran at once',
    () async {
      final first = await schema7File();
      final reference = copyOf(first, 'reference.sqlite');
      final recorder = _StopAfter(null);
      final once = P2pDatabase.forTesting(
        NativeDatabase(reference).interceptWith(recorder),
      );
      expect(await _versionOf(once), P2pDatabase.schema);
      final expectedRows = await _rowsOf(once, _schema8Columns);
      final expectedObjects = await _objectsOf(once);
      await once.close();
      final statements = recorder.statements;
      // Each statement of the step, in its order, every one of them a write the step makes: the copies, the drops, the tables, the copies back, the triggers and their drops, and the drops of the copies at the very end.
      expect(statements.map(_kindOf).toList(), _stepKinds);

      final states = <Set<String>>[];
      for (var stop = 0; stop < statements.length; stop++) {
        final file = copyOf(first, 'stop-$stop.sqlite');
        final stopped = P2pDatabase.forTesting(
          NativeDatabase(file).interceptWith(_StopAfter(stop)),
        );
        await expectLater(
          _versionOf(stopped),
          throwsA(isA<_Stopped>()),
          reason: '$stop',
        );
        await stopped.close();
        // What the stop left: schema 7 still, part of the step done.
        final left = v7.DatabaseAtV7(NativeDatabase(file));
        expect(await _versionOf(left), 7, reason: '$stop');
        states.add(await _namesOf(left));
        await left.close();

        final again = P2pDatabase.forTesting(NativeDatabase(file));
        expect(await _versionOf(again), P2pDatabase.schema, reason: '$stop');
        expect(
          await _rowsOf(again, _schema8Columns),
          expectedRows,
          reason: '$stop',
        );
        expect(await _objectsOf(again), expectedObjects, reason: '$stop');
        await again.close();
      }
      // Among the files the stops left, one with the copy of the trades and no table of them.
      expect(
        states,
        contains(
          allOf(contains('trades_of_schema7'), isNot(contains('trades'))),
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'done to its last statement but its version not written, the step runs again and changes nothing',
    () async {
      final file = await schema7File();
      final migrated = P2pDatabase.forTesting(NativeDatabase(file));
      expect(await _versionOf(migrated), P2pDatabase.schema);
      final rows = await _rowsOf(migrated, _schema8Columns);
      final objects = await _objectsOf(migrated);
      await migrated.customStatement('PRAGMA user_version = 7');
      await migrated.close();

      final again = P2pDatabase.forTesting(NativeDatabase(file));
      expect(await _versionOf(again), P2pDatabase.schema);
      expect(await _rowsOf(again, _schema8Columns), rows);
      expect(await _objectsOf(again), objects);
      await again.close();
    },
  );

  test(
    'refuses a connection whose foreign keys are on, before it changes anything, at every opening',
    () async {
      final file = await schema7File();
      final old = v7.DatabaseAtV7(NativeDatabase(file));
      final rows = await _rowsOf(old, _schema7Columns);
      final objects = await _objectsOf(old);
      await old.close();

      for (var turn = 0; turn < 2; turn++) {
        final on = P2pDatabase.forTesting(
          NativeDatabase(
            file,
            setup: (database) => database.execute('PRAGMA foreign_keys = ON'),
          ),
        );
        await expectLater(
          _versionOf(on),
          throwsA(
            isA<P2pSchemaStepRefused>().having(
              (refusal) => refusal.check,
              'check',
              'foreign keys on',
            ),
          ),
        );
        await on.close();
        final left = v7.DatabaseAtV7(NativeDatabase(file));
        expect(await _versionOf(left), 7);
        expect(await _rowsOf(left, _schema7Columns), rows);
        expect(await _objectsOf(left), objects);
        await left.close();
      }

      // The app's own connection, whose foreign keys are off during a step, migrates it.
      final migrated = P2pDatabase.forTesting(NativeDatabase(file));
      expect(await _versionOf(migrated), P2pDatabase.schema);
      expect(await _rowsOf(migrated, _schema7Columns), rows);
      await migrated.close();
    },
  );

  test(
    'stops at schema 7 on a file with an orphan row, its copies kept with every row, at every opening, and ends once the row has its parent',
    () async {
      final file = await schema7File();
      final old = v7.DatabaseAtV7(NativeDatabase(file));
      // A trade of a robot with no binding: the foreign keys were off on this connection, as on any connection of a test.
      await old.customStatement(
        "INSERT INTO trades VALUES ('testnet', '$_key', 20, 'temple', 'http://temple.onion', 120, 'buyer', 'takenHere', 1900, NULL, NULL)",
      );
      final rows = await _rowsOf(old, _schema7Columns);
      await old.close();

      for (var turn = 0; turn < 2; turn++) {
        final stopped = P2pDatabase.forTesting(NativeDatabase(file));
        await expectLater(
          _versionOf(stopped),
          throwsA(
            isA<P2pSchemaStepRefused>().having(
              (refusal) => refusal.check,
              'check',
              'foreign key check',
            ),
          ),
          reason: '$turn',
        );
        await stopped.close();
        final left = v7.DatabaseAtV7(NativeDatabase(file));
        expect(await _versionOf(left), 7, reason: '$turn');
        // Each copy holds its table's rows as they were at schema 7, every value and storage class.
        expect(
          await _rowsOf(left, {
            for (final table in ['trades', 'trade_trails', 'trade_payments'])
              '${table}_of_schema7': ?_schema7Columns[table],
          }),
          {
            for (final table in ['trades', 'trade_trails', 'trade_payments'])
              '${table}_of_schema7': rows[table],
          },
          reason: '$turn',
        );
        // And the rebuilt tables hold them too.
        expect(await _rowsOf(left, _schema7Columns), rows, reason: '$turn');
        await left.close();
      }

      // The robot bound, the step ends: every row kept, the copies dropped.
      final fixed = v7.DatabaseAtV7(NativeDatabase(file));
      await fixed.customStatement(
        "INSERT INTO robot_bindings VALUES ('testnet', '$_key', 20, 'temple', 'http://temple.onion', '', 'nostr', 10, 'generated')",
      );
      final withBinding = await _rowsOf(fixed, _schema7Columns);
      await fixed.close();
      final migrated = P2pDatabase.forTesting(NativeDatabase(file));
      expect(await _versionOf(migrated), P2pDatabase.schema);
      expect(await _rowsOf(migrated, _schema7Columns), withBinding);
      expect(await _namesOf(migrated), isNot(contains(endsWith('_of_schema7'))));
      await migrated.close();
    },
  );
}

/// What a stop of the step throws, in place of the statement it stops before.
final class _Stopped implements Exception {
  const _Stopped();
}

/// Runs the statements of a step as written and records them, and, given [stopAfter], lets that many run and throws in place of the next, as an app killed there would leave the file (no statement of the step runs in a transaction).
///
/// The version drift writes after the step and the foreign keys turned on after it are neither counted nor stopped.
final class _StopAfter extends QueryInterceptor {
  final int? stopAfter;
  final List<String> statements = [];

  _StopAfter(this.stopAfter);

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    final lower = statement.toLowerCase();
    if (!lower.startsWith('pragma user_version') &&
        !lower.startsWith('pragma foreign_keys = on')) {
      if (stopAfter case final stop? when statements.length >= stop) {
        throw const _Stopped();
      }
      statements.add(statement);
    }
    return super.runCustom(executor, statement, args);
  }
}

/// The kind of a statement of the step: what it does, and to what.
String _kindOf(String statement) {
  final words = statement
      .replaceAll('"', '')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  return switch (words) {
    ['CREATE', 'TABLE', 'IF', 'NOT', 'EXISTS', final name, ...] =>
      'create $name',
    ['CREATE', 'TABLE', final name, 'AS', ...] => 'copy to $name',
    ['CREATE', 'TRIGGER', 'IF', 'NOT', 'EXISTS', final name, ...] =>
      'trigger $name',
    ['DROP', 'TABLE', 'IF', 'EXISTS', final name] => 'drop if any $name',
    ['DROP', 'TABLE', final name] => 'drop $name',
    ['DROP', 'TRIGGER', 'IF', 'EXISTS', final name] => 'drop trigger $name',
    ['INSERT', 'INTO', final name, ...] => 'restore $name',
    _ => statement,
  };
}

/// The statements of the step over a file of schema 7, by kind, in their order.
const _stepKinds = [
  'drop if any trades_of_schema7',
  'copy to trades_of_schema7',
  'drop trades',
  'create trades',
  'restore trades',
  'drop if any trade_trails_of_schema7',
  'copy to trade_trails_of_schema7',
  'drop trade_trails',
  'create trade_trails',
  'restore trade_trails',
  'drop if any trade_payments_of_schema7',
  'copy to trade_payments_of_schema7',
  'drop trade_payments',
  'create trade_payments',
  'restore trade_payments',
  'create maker_terms',
  'trigger trades_never_deleted',
  'drop trigger trades_set_once',
  'trigger trades_set_once',
  'trigger trades_inserted_once',
  'trigger trades_one_open_per_order',
  'trigger trades_one_open_per_order_update',
  'trigger maker_terms_never_deleted',
  'trigger maker_terms_set_once',
  'trigger maker_terms_inserted_once',
  'trigger maker_terms_of_their_make',
  'drop trigger trade_terms_of_their_trade',
  'trigger trade_terms_of_their_trade',
  'trigger trade_trails_never_deleted',
  'trigger trade_trails_inserted_once',
  'drop trigger trade_trails_of_their_trade',
  'trigger trade_trails_of_their_trade',
  'trigger trade_trails_closed',
  'drop trigger trade_trails_forward',
  'trigger trade_trails_forward',
  'trigger trade_payments_never_deleted',
  'drop trigger trade_payments_inserted_once',
  'trigger trade_payments_inserted_once',
  'drop trigger trade_payments_of_their_trade',
  'trigger trade_payments_of_their_trade',
  'drop trigger trade_payments_forward',
  'trigger trade_payments_forward',
  'trigger trade_payments_hash_once',
  'drop if any trades_of_schema7',
  'drop if any trade_trails_of_schema7',
  'drop if any trade_payments_of_schema7',
];

/// The `user_version` of [database], the schema version drift wrote.
Future<int> _versionOf(GeneratedDatabase database) async =>
    (await database.customSelect('PRAGMA user_version').getSingle()).read<int>(
      'user_version',
    );

/// The names of the tables, indexes and triggers of [database].
Future<Set<String>> _namesOf(GeneratedDatabase database) async => {
  for (final row
      in await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
          )
          .get())
    row.read<String>('name'),
};

/// Every table, index and trigger of [database], by name, its text without quotes and white space (drift quotes names when it creates a file only).
Future<Map<String, String>> _objectsOf(GeneratedDatabase database) async => {
  for (final row
      in await database
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'",
          )
          .get())
    row.read<String>('name'): row
        .read<String>('sql')
        .replaceAll('"', '')
        .replaceAll(RegExp(r'\s+'), ''),
};

/// The rows of each table of [columns] in [database], ordered by their primary key, each as the storage class and the value of each of its columns, in the order given.
Future<Map<String, List<List<Object?>>>> _rowsOf(
  GeneratedDatabase database,
  Map<String, List<String>> columns,
) async => {
  for (final MapEntry(key: table, value: names) in columns.entries)
    table: [
      for (final row
          in await database
              .customSelect(
                'SELECT ${[for (final name in names) 'typeof($name), $name'].join(', ')} '
                'FROM $table ORDER BY ${_keys[table.replaceAll('_of_schema7', '')]}',
              )
              .get())
        row.data.values.toList(),
    ],
};

/// The primary key of each table, by which its rows are compared.
const _keys = {
  'garage_key_histories': 'network, key_fingerprint',
  'robot_bindings': 'key_fingerprint, robot_index',
  'trades': 'key_fingerprint, robot_index',
  'trade_terms': 'key_fingerprint, robot_index',
  'trade_trails': 'key_fingerprint, robot_index',
  'trade_payments': 'key_fingerprint, robot_index, step',
  'trade_chat_pins': 'key_fingerprint, robot_index',
  'trade_chat_nostr_pins': 'key_fingerprint, robot_index',
  'maker_terms': 'key_fingerprint, robot_index',
};

/// Every column of every table of schema 7, in the order of its table.
const _schema7Columns = {
  'garage_key_histories': [
    'network',
    'key_fingerprint',
    'origin',
    'recorded_at',
  ],
  'robot_bindings': [
    'network',
    'key_fingerprint',
    'robot_index',
    'coordinator_alias',
    'coordinator_onion',
    'coordinator_node_keys',
    'coordinator_nostr_key',
    'bound_at',
    'provenance',
  ],
  'trades': [
    'network',
    'key_fingerprint',
    'robot_index',
    'coordinator_alias',
    'coordinator_onion',
    'order_id',
    'role',
    'origin',
    'taken_at',
    'confirmed_at',
    'closed_at',
  ],
  'trade_terms': [
    'key_fingerprint',
    'robot_index',
    'version',
    'network',
    'coordinator_alias',
    'order_id',
    'role',
    'order_type',
    'currency_id',
    'amount',
    'is_range',
    'premium_percent',
    'explicit_satoshis',
    'bond_size_percent',
    'escrow_seconds',
    'book_price',
    'taker_fee',
  ],
  'trade_trails': [
    'key_fingerprint',
    'robot_index',
    'version',
    'network',
    'coordinator_alias',
    'order_id',
    'role',
    'position',
    'read_at',
    'bond_hash',
    'escrow_hash',
    'deadline',
    'bond_step_seen_at',
    'bond_step_deadline',
    'breached',
    'history_unknown',
  ],
  'trade_payments': [
    'key_fingerprint',
    'robot_index',
    'step',
    'payment_hash',
    'started_at',
    'wallet_payment_id',
  ],
  'trade_chat_pins': [
    'key_fingerprint',
    'robot_index',
    'primary_fingerprint',
    'subkey_fingerprint',
    'armored_key',
  ],
  'trade_chat_nostr_pins': [
    'key_fingerprint',
    'robot_index',
    'peer_key',
    'own_key',
  ],
};

/// Every column of every table of schema 7 and the columns schema 8 adds to them.
final _schema8Columns = {
  for (final MapEntry(:key, :value) in _schema7Columns.entries)
    key: [
      ...value,
      if (key == 'trade_trails') ...[
        'take',
        'take_deadline',
        'taker_hash_id',
        'taken_amount',
      ],
      if (key == 'trade_payments') 'take',
    ],
  'maker_terms': ['key_fingerprint', 'robot_index'],
};

/// A key fingerprint of the rows: fixed test text, not a key anyone uses.
final _key = 'ab' * 32;

/// A key fingerprint of a key acknowledged here.
final _otherKey = 'cd' * 32;

/// The payment hashes of the rows: fixed test text, none an invoice anyone paid.
final _bondOfOne = '1b' * 32;
final _bondOfTwo = '2b' * 32;
final _escrowOfTwo = '2e' * 32;
final _bondOfThree = '3b' * 32;
final _escrowOfThree = '3e' * 32;

/// An armored public key block as the pins hold one: fixed text, not a key.
const _armored = '-----BEGIN PGP PUBLIC KEY BLOCK-----\n\nnot a key';

/// The rows of the file of schema 7, written in the order the app writes them through schema 7's triggers: each trade, then its terms, its trail, its payments and its pins, then the trail moved on and the trade closed.
final _schema7Rows = [
  "INSERT INTO garage_key_histories VALUES ('testnet', '$_key', 'generated', 1)",
  "INSERT INTO garage_key_histories VALUES ('mainnet', '$_key', 'generated', 2)",
  "INSERT INTO garage_key_histories VALUES ('testnet', '$_otherKey', 'acknowledged', 3)",
  for (var index = 0; index <= 8; index++)
    "INSERT INTO robot_bindings VALUES ('testnet', '$_key', $index, 'temple', 'http://temple.onion', 'node1,node2', 'nostr$index', ${10 + index}, 'generated')",
  "INSERT INTO robot_bindings VALUES ('testnet', '$_otherKey', 0, 'lake', 'http://lake.onion', '', 'nostr', 30, 'acknowledged')",
  // Robot 0: a pending take with its terms and its first trail.
  "INSERT INTO trades VALUES ('testnet', '$_key', 0, 'temple', 'http://temple.onion', 100, 'buyer', 'takenHere', 1000, NULL, NULL)",
  "INSERT INTO trade_terms VALUES ('$_key', 0, 1, 'testnet', 'temple', 100, 'buyer', 1, 2, 100.0, 0, 2.0, NULL, 3.0, 10800, 93545.25, 0.00175)",
  "INSERT INTO trade_trails VALUES ('$_key', 0, 1, 'testnet', 'temple', 100, 'buyer', 'start', 1000000, NULL, NULL, NULL, NULL, NULL, 0, 0)",
  // Robot 1: a buyer's trade taken and confirmed, its bond paid from the wallet, waiting for its payout.
  "INSERT INTO trades VALUES ('testnet', '$_key', 1, 'temple', 'http://temple.onion', 101, 'buyer', 'takenHere', 1100, 1150, NULL)",
  "INSERT INTO trade_terms VALUES ('$_key', 1, 1, 'testnet', 'temple', 101, 'buyer', 1, 3, 123.45, 1, -1.5, NULL, 3.5, 7200, 87654.321, 0.002)",
  "INSERT INTO trade_trails VALUES ('$_key', 1, 1, 'testnet', 'temple', 101, 'buyer', 'bondStep', 1100000, '$_bondOfOne', NULL, 1400000000, 1100000, 1400000000, 0, 0)",
  "INSERT INTO trade_payments VALUES ('$_key', 1, 'bond', '$_bondOfOne', 1120000, 'swap-1')",
  "UPDATE trade_trails SET position = 'waitingForPayout', read_at = 1200000, deadline = 1900000000 WHERE robot_index = 1",
  // Robot 2: a seller's trade in its chat, bond and escrow paid, the peer's keys pinned.
  "INSERT INTO trades VALUES ('testnet', '$_key', 2, 'temple', 'http://temple.onion', 102, 'seller', 'takenHere', 1200, 1250, NULL)",
  "INSERT INTO trade_terms VALUES ('$_key', 2, 1, 'testnet', 'temple', 102, 'seller', 0, 1, 50.0, 0, 0.0, 21000, 2.0, 36000, 60000.5, 0.0)",
  "INSERT INTO trade_trails VALUES ('$_key', 2, 1, 'testnet', 'temple', 102, 'seller', 'bondStep', 1250000, '$_bondOfTwo', NULL, NULL, 1250000, NULL, 0, 0)",
  "INSERT INTO trade_payments VALUES ('$_key', 2, 'bond', '$_bondOfTwo', 1260000, NULL)",
  "UPDATE trade_trails SET position = 'waitingForEscrow', read_at = 1300000, escrow_hash = '$_escrowOfTwo', deadline = 2000000000 WHERE robot_index = 2",
  "INSERT INTO trade_payments VALUES ('$_key', 2, 'escrow', '$_escrowOfTwo', 1310000, 'swap-2')",
  "UPDATE trade_trails SET position = 'chatting', read_at = 1400000 WHERE robot_index = 2",
  "INSERT INTO trade_chat_pins VALUES ('$_key', 2, '${'A' * 40}', '${'B' * 40}', '$_armored')",
  "INSERT INTO trade_chat_nostr_pins VALUES ('$_key', 2, '${'a' * 64}', '${'b' * 64}')",
  // Robot 3: a seller's trade that succeeded and was closed, every record of it kept.
  "INSERT INTO trades VALUES ('testnet', '$_key', 3, 'temple', 'http://temple.onion', 103, 'seller', 'takenHere', 1300, 1350, NULL)",
  "INSERT INTO trade_terms VALUES ('$_key', 3, 1, 'testnet', 'temple', 103, 'seller', 0, 2, 75.5, 1, 999.0, NULL, 15.0, 1800, 0.000001, 0.01)",
  "INSERT INTO trade_trails VALUES ('$_key', 3, 1, 'testnet', 'temple', 103, 'seller', 'bondStep', 1350000, '$_bondOfThree', NULL, NULL, 1350000, 1360000, 0, 0)",
  "INSERT INTO trade_payments VALUES ('$_key', 3, 'bond', '$_bondOfThree', 1355000, 'swap-3')",
  "UPDATE trade_trails SET position = 'waitingForEscrow', read_at = 1360000, escrow_hash = '$_escrowOfThree' WHERE robot_index = 3",
  "INSERT INTO trade_payments VALUES ('$_key', 3, 'escrow', '$_escrowOfThree', 1365000, NULL)",
  "INSERT INTO trade_chat_pins VALUES ('$_key', 3, '${'C' * 40}', '${'D' * 40}', '$_armored 3')",
  "INSERT INTO trade_chat_nostr_pins VALUES ('$_key', 3, '${'c' * 64}', '${'d' * 64}')",
  "UPDATE trade_trails SET position = 'succeeded', read_at = 1500000 WHERE robot_index = 3",
  'UPDATE trades SET closed_at = 1500 WHERE robot_index = 3',
  // Robot 4: a pending take that never left, closed with no terms and no trail.
  "INSERT INTO trades VALUES ('testnet', '$_key', 4, 'temple', 'http://temple.onion', 104, 'buyer', 'takenHere', 1400, NULL, NULL)",
  'UPDATE trades SET closed_at = 1401 WHERE robot_index = 4',
  // Robot 0 of the acknowledged key: a trade recovered, its trail with no history, a breach recorded.
  "INSERT INTO trades VALUES ('testnet', '$_otherKey', 0, 'lake', 'http://lake.onion', 105, 'seller', 'recovered', 1500, 1500, NULL)",
  "INSERT INTO trade_terms VALUES ('$_otherKey', 0, 1, 'testnet', 'lake', 105, 'seller', 0, 5, 1.0, 0, 5.25, NULL, 2.5, 3600, 1.5, 0.001)",
  "INSERT INTO trade_trails VALUES ('$_otherKey', 0, 1, 'testnet', 'lake', 105, 'seller', 'start', 1500000, NULL, NULL, NULL, NULL, NULL, 0, 1)",
  "UPDATE trade_trails SET position = 'waitingForBoth', read_at = 1600000, breached = 1 WHERE key_fingerprint = '$_otherKey'",
  // Robot 6: a buyer's trade expired and closed, whose bond the wallet was asked to pay with the very hash of robot 1's (a coordinator serving one invoice twice: schema 7 kept both).
  "INSERT INTO trades VALUES ('testnet', '$_key', 6, 'temple', 'http://temple.onion', 106, 'buyer', 'takenHere', 1600, 1650, NULL)",
  "INSERT INTO trade_terms VALUES ('$_key', 6, 1, 'testnet', 'temple', 106, 'buyer', 1, 2, 9999999.99, 0, -99.99, NULL, 2.0, 1800, 999999999.0, 0.0001)",
  "INSERT INTO trade_trails VALUES ('$_key', 6, 1, 'testnet', 'temple', 106, 'buyer', 'bondStep', 1650000, '$_bondOfOne', NULL, 253402300799999999, 1650000, 0, 1, 0)",
  "INSERT INTO trade_payments VALUES ('$_key', 6, 'bond', '$_bondOfOne', 1660000, '${'w' * 256}')",
  "UPDATE trade_trails SET position = 'expired', read_at = 1700000 WHERE robot_index = 6",
  'UPDATE trades SET closed_at = 1700 WHERE robot_index = 6',
];
