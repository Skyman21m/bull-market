import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/trade_payment_repository_impl.dart';
import 'package:p2p/src/data/trade_payout_repository_impl.dart';
import 'package:p2p/src/data/trade_trail_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/payout_trace.dart';
import 'package:p2p/src/domain/trade/trade_payment.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;
import 'package:test/test.dart';

import 'generated/schema_v8.dart' as v8;
import 'schema8_rows.dart';

/// The step from schema 8 to schema 9 of `p2p.sqlite` (#204, #231, #233; design note `docs/design/phase-3-making-an-order.md` § 3.5 bis) over a file of schema 8 that holds every shape of row a user's file of the APKs given out can hold: trades open and closed, taken, made and recovered, a pending take and a pending make, the terms of both sides, trails with and without hashes, a maker's next contract with its earlier escrow, payments of bonds and of escrows of contracts 0 and 1, the pins of a chat, bindings and histories.
///
/// Schema 8 is frozen: its snapshot and generated schema are pinned by their bytes. Every row is compared before and after, column by column, value and storage class; the new columns are empty, the marks of the buyers' contracts under way are written and nothing else; the step is stopped after each of its statements and run again to the very file of a step run at once; a file migrated has a new file's tables and triggers in a new file's order; and after the step the records say « unknown » where schema 8 kept nothing, never « zero » nor « given elsewhere ».
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('p2p-schema9-');
  });

  tearDown(() => directory.delete(recursive: true));

  /// A file of schema 8 at [name] in the test's directory, written by the generated schema 8 itself, its rows written in the order the app writes them, through schema 8's own triggers.
  Future<File> schema8File([String name = 'eight.sqlite']) async {
    final file = File('${directory.path}/$name');
    final old = v8.DatabaseAtV8(NativeDatabase(file));
    expect(await _versionOf(old), 8);
    for (final statement in _schema8Rows) {
      await old.customStatement(statement);
    }
    expect(await _versionOf(old), 8);
    await old.close();
    return file;
  }

  File copyOf(File file, String name) =>
      file.copySync('${directory.path}/$name');

  test(
    'schema 8 is frozen: its snapshot and its generated schema keep their bytes',
    () {
      // The APKs given out carry schema 8 with real trades in them (#204, #231, #233): any change to these files changes what the step from 8 starts from.
      expect(
        sha256
            .convert(
              File(
                'lib/src/data/schemas/p2p_database/drift_schema_v8.json',
              ).readAsBytesSync(),
            )
            .toString(),
        '88490508e770203fb70ac34bacfc6e3a8894d7f16830040560668aedbe7ef63c',
      );
      expect(
        sha256
            .convert(
              File(
                'test/migrations_test/p2p_database/generated/schema_v8.dart',
              ).readAsBytesSync(),
            )
            .toString(),
        '89a7118736437443f31487d1f1d3f2ca9687dd24cd8f471c0c658df9328fdd3e',
      );
    },
  );

  test(
    'the file of schema 8 holds every shape of row the step must keep',
    () async {
      final file = await schema8File();
      final old = v8.DatabaseAtV8(NativeDatabase(file));
      final rows = await _rowsOf(old, _schema8Columns);
      await old.close();
      expect(
        {for (final MapEntry(:key, :value) in rows.entries) key: value.length},
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
        },
      );
    },
  );

  test(
    'keeps every row, every value and its storage class, leaves the new columns empty, marks the buyers\' contracts under way only, and is not migrated again',
    () async {
      final file = await schema8File();
      final old = v8.DatabaseAtV8(NativeDatabase(file));
      final before = await _rowsOf(old, _schema8Columns);
      await old.close();

      final migrated = P2pDatabase.forTesting(NativeDatabase(file));
      expect(await _versionOf(migrated), P2pDatabase.schema);
      // Schema 10 (#81) adds two tables after this step, which changes no row of it: `schema10_migration_test.dart` plays it.
      expect(P2pDatabase.schema, 10);
      await migrated.validateDatabaseSchema();
      expect(await _rowsOf(migrated, _schema8Columns), before);
      // The new columns of every older row: empty, « unknown » and « no trace recorded », never 0.
      expect(
        await _rowsOf(migrated, {
          'trade_trails': [
            'terms_changed_at',
            'terms_changed_premium_low',
            'terms_changed_premium_high',
          ],
          'trade_payments': ['confirmed_sats'],
        }),
        {
          'trade_trails': List.filled(8, [
            'null',
            null,
            'null',
            null,
            'null',
            null,
          ]),
          'trade_payments': List.filled(7, ['null', null]),
        },
      );
      // The marks: a buyer's contract the trail stands at, from a position where its payout may have been given; never a seller's, a pending take's, an order still before its first take.
      expect(await _rowsOf(migrated, _schema9Columns), {
        ..._schema9Columns.map((key, _) => MapEntry(key, <List<Object?>>[])),
        'trade_payouts': [
          for (final (index, take) in [(1, 0), (6, 1), (8, 0), (9, 0)])
            [
              'text',
              _key,
              'integer',
              index,
              'integer',
              take,
              'text',
              'unrecorded',
              'null',
              null,
              'null',
              null,
            ],
        ],
      });
      expect(
        await migrated.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      final objects = await _objectsOf(migrated);
      final rows = await _rowsOf(migrated, {
        ..._schema8Columns,
        ..._schema9Columns,
      });
      await migrated.close();

      // Its tables, indexes and triggers are a new file's, as written, in a new file's order.
      final freshDirectory = await Directory.systemTemp.createTemp(
        'p2p-fresh-',
      );
      addTearDown(() => freshDirectory.delete(recursive: true));
      final fresh = P2pDatabase.open(() async => freshDirectory);
      expect(objects, await _objectsOf(fresh));
      await fresh.close();

      // Opened again: nothing moves.
      final again = P2pDatabase.forTesting(NativeDatabase(file));
      expect(await _versionOf(again), P2pDatabase.schema);
      expect(
        await _rowsOf(again, {..._schema8Columns, ..._schema9Columns}),
        rows,
      );
      expect(await _objectsOf(again), objects);
      await again.close();
    },
  );

  test(
    'stopped after any of its statements, the step runs again over the file it left to the very file of a step that ran at once',
    () async {
      final first = await schema8File();
      final reference = copyOf(first, 'reference.sqlite');
      final recorder = _StopAfter(null);
      final once = P2pDatabase.forTesting(
        NativeDatabase(reference).interceptWith(recorder),
      );
      expect(await _versionOf(once), P2pDatabase.schema);
      final columns = {..._schema8Columns, ..._schema9Columns};
      final expectedRows = await _rowsOf(once, columns);
      final expectedObjects = await _objectsOf(once);
      await once.close();
      final statements = recorder.statements;
      expect(statements.map(_kindOf).toList(), _stepKinds);
      // The statements of this step only: a stop in the step to schema 10 leaves a file of schema 9, which `schema10_migration_test.dart` runs again.
      final ownStatements = _stepKinds.indexOf('create derived_garage_keys');

      for (var stop = 0; stop < ownStatements; stop++) {
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
        final left = v8.DatabaseAtV8(NativeDatabase(file));
        expect(await _versionOf(left), 8, reason: '$stop');
        await left.close();

        final again = P2pDatabase.forTesting(NativeDatabase(file));
        expect(await _versionOf(again), P2pDatabase.schema, reason: '$stop');
        expect(await _rowsOf(again, columns), expectedRows, reason: '$stop');
        expect(await _objectsOf(again), expectedObjects, reason: '$stop');
        await again.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'done to its last statement but its version not written, the step runs again and changes nothing',
    () async {
      final file = await schema8File();
      final migrated = P2pDatabase.forTesting(NativeDatabase(file));
      expect(await _versionOf(migrated), P2pDatabase.schema);
      final columns = {..._schema8Columns, ..._schema9Columns};
      final rows = await _rowsOf(migrated, columns);
      final objects = await _objectsOf(migrated);
      await migrated.customStatement('PRAGMA user_version = 8');
      await migrated.close();

      final again = P2pDatabase.forTesting(NativeDatabase(file));
      expect(await _versionOf(again), P2pDatabase.schema);
      expect(await _rowsOf(again, columns), rows);
      expect(await _objectsOf(again), objects);
      await again.close();
    },
  );

  group('after the step, the records of schema 8', () {
    late P2pDatabase database;

    setUp(() async {
      final file = await schema8File();
      database = P2pDatabase.forTesting(NativeDatabase(file));
      expect(await _versionOf(database), P2pDatabase.schema);
    });

    tearDown(() => database.close());

    test(
      'an escrow paid before schema 9 has an unknown amount, never 0, and a new attempt of it leaves it unknown (#233)',
      () async {
        final payments = TradePaymentRepositoryImpl(database);
        final seller = _record(7, TradeRole.seller, TradeOrigin.madeHere, 108);
        final recorded = switch (await payments.paymentsOfTrade(seller)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(
          [
            for (final payment in recorded)
              (payment.step, payment.take, payment.confirmedSats),
          ],
          [
            (InvoiceStep.bond, 0, null),
            (InvoiceStep.escrow, 0, null),
            (InvoiceStep.escrow, 1, null),
          ],
        );
        // A new attempt of contract 1's escrow, the same invoice: its start moves, its amount stays unknown.
        expect(
          await payments.recordStart(
            seller,
            InvoiceStep.escrow,
            paymentHash: _escrowOfSevenNext,
            at: DateTime.fromMicrosecondsSinceEpoch(3000000, isUtc: true),
            sats: Sats.fromInt(200000),
            take: 1,
          ),
          isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'value', isTrue),
        );
        final again = switch (await payments.paymentOf(
          seller,
          InvoiceStep.escrow,
          take: 1,
        )) {
          Ok(:final value?) => value,
          final other => fail('$other'),
        };
        expect(again.confirmedSats, isNull);
        expect(again.startedAt.microsecondsSinceEpoch, 3000000);
        // The database refuses to give it a figure, whatever the code.
        await expectLater(
          database.customStatement(
            "UPDATE trade_payments SET confirmed_sats = 5 WHERE robot_index = 7 AND take = 1 AND key_fingerprint = '$_key'",
          ),
          throwsA(
            predicate(
              (error) =>
                  '$error'.contains('the amount of a payment never goes down'),
            ),
          ),
        );
      },
    );

    test(
      'a buyer\'s contract under way before schema 9 reads « unknown », one with no mark « not given here », and a payout given since replaces the mark, never the reverse (#204)',
      () async {
        final payouts = TradePayoutRepositoryImpl(database);
        final taken = _record(1, TradeRole.buyer, TradeOrigin.takenHere, 101);
        final made = _record(6, TradeRole.buyer, TradeOrigin.madeHere, 107);
        final pending = _record(0, TradeRole.buyer, TradeOrigin.takenHere, 100);
        Future<PayoutTrace> traceOf(TradeRecord record, int take) async =>
            switch (await payouts.traceOf(record, take: take)) {
              Ok(:final value) => value,
              Err(:final failure) => fail('$failure'),
            };
        expect(await traceOf(taken, 0), const PayoutUnrecorded());
        expect(await traceOf(made, 1), const PayoutUnrecorded());
        // Contract 0 of the made order is over: no mark, never « unknown » read as « given here ».
        expect(await traceOf(made, 0), const PayoutNotGivenHere());
        expect(await traceOf(pending, 0), const PayoutNotGivenHere());
        final at = DateTime.fromMicrosecondsSinceEpoch(4000000, isUtc: true);
        expect(
          await payouts.recordPayout(
            taken,
            take: 0,
            source: PayoutTraceSource.thisWallet,
            kind: PayoutTraceKind.invoice,
            at: at,
          ),
          isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'value', isTrue),
        );
        expect(
          await traceOf(taken, 0),
          PayoutFromThisWallet(PayoutTraceKind.invoice, at),
        );
        await expectLater(
          database.customStatement(
            "UPDATE trade_payouts SET source = 'unrecorded', kind = NULL, submitted_at = NULL WHERE robot_index = 1",
          ),
          throwsA(
            predicate(
              (error) => '$error'.contains('a payout only moves forward'),
            ),
          ),
        );
        // A mark is the step's alone.
        await expectLater(
          database.customStatement(
            "INSERT INTO trade_payouts VALUES ('$_key', 9, 1, 'unrecorded', NULL, NULL)",
          ),
          throwsA(
            predicate(
              (error) => '$error'.contains('a payout of no open trade'),
            ),
          ),
        );
      },
    );

    test(
      'a trail of schema 8 has no trace of terms shown otherwise, and gains one only with its read\'s own time, then keeps it (#231)',
      () async {
        final trails = TradeTrailRepositoryImpl(database);
        final taken = _record(1, TradeRole.buyer, TradeOrigin.takenHere, 101);
        final trail = switch (await trails.historyOf(taken)) {
          Ok(:final value) => value.trail ?? fail('no trail'),
          Err(:final failure) => fail('$failure'),
        };
        expect(trail.termsChangedAtMicros, isNull);
        expect(trail.termsChangedPremiumLow, isNull);
        expect(trail.termsChangedPremiumHigh, isNull);
        await _termsTraceRules(database);
      },
    );

    test(
      'an amount out of its bounds read back from a file changed outside the app is records unreadable, never a figure (security review of schema 9, R2)',
      () async {
        final payments = TradePaymentRepositoryImpl(database);
        final seller = _record(7, TradeRole.seller, TradeOrigin.madeHere, 108);
        await database.customStatement(
          'DROP TRIGGER trade_payments_sats_forward',
        );
        await database.customStatement('PRAGMA ignore_check_constraints = ON');
        for (final amount in [-5, 0, 2100000000000001]) {
          await database.customStatement(
            "UPDATE trade_payments SET confirmed_sats = $amount WHERE robot_index = 7 AND take = 0 AND step = 'escrow' AND key_fingerprint = '$_key'",
          );
          expect(
            await payments.paymentsOfTrade(seller),
            isA<Err<List<TradePaymentRecord>, P2pFailure>>(),
            reason: '$amount',
          );
          expect(
            await payments.paymentOf(seller, InvoiceStep.escrow),
            isA<Err<TradePaymentRecord?, P2pFailure>>(),
            reason: '$amount',
          );
        }
        await database.customStatement(
          "UPDATE trade_payments SET confirmed_sats = 2100000000000000 WHERE robot_index = 7 AND take = 0 AND step = 'escrow' AND key_fingerprint = '$_key'",
        );
        expect(
          await payments.paymentOf(seller, InvoiceStep.escrow),
          isA<Ok<TradePaymentRecord?, P2pFailure>>(),
        );
      },
    );
  });

  test(
    'on a new file, the trigger keeps the trace as on a migrated one (security verification of schema 9, R8)',
    () async {
      final fresh = P2pDatabase.forTesting(NativeDatabase.memory());
      expect(await _versionOf(fresh), P2pDatabase.schema);
      // The same trails, written as schema 9 writes them (its three new columns empty); the payments, which schema 9 never starts without an amount, are not needed here.
      for (final statement in _schema8Rows) {
        if (statement.startsWith(_payments)) continue;
        await fresh.customStatement(
          statement.startsWith(_trails)
              ? '${statement.substring(0, statement.length - 1)}, NULL, NULL, NULL)'
              : statement,
        );
      }
      await _termsTraceRules(fresh);
      await fresh.close();
    },
  );
}

/// The record of robot [index] of the rows' key on testnet with temple.
TradeRecord _record(int index, TradeRole role, TradeOrigin origin, int order) =>
    TradeRecord(
      robot: RobotSlot(
        RobosatsNetwork.testnet,
        GarageKeyFingerprint.stored(_key) ?? fail('no fingerprint'),
        index,
      ),
      coordinatorAlias: 'temple',
      coordinatorOnion: 'http://temple.onion',
      orderId: order,
      role: role,
      origin: origin,
      takenAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      confirmedAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      closedAt: null,
    );

/// What a stop of the step throws, in place of the statement it stops before.
final class _Stopped implements Exception {
  const _Stopped();
}

/// Runs the statements of a step as written and records them, and, given [stopAfter], lets that many run and throws in place of the next, as an app killed there would leave the file (no statement of the step runs in a transaction).
final class _StopAfter extends QueryInterceptor {
  final int? stopAfter;
  final List<String> statements = [];

  _StopAfter(this.stopAfter);

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      executor.ensureOpen(_OpenedThrough(user, this));

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

/// The database opening, its steps run through [_interceptor].
final class _OpenedThrough implements QueryExecutorUser {
  final QueryExecutorUser _user;
  final QueryInterceptor _interceptor;

  _OpenedThrough(this._user, this._interceptor);

  @override
  int get schemaVersion => _user.schemaVersion;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) =>
      _user.beforeOpen(executor.interceptWith(_interceptor), details);
}

/// The rule of the trigger `trade_trails_terms_trace` over [database], migrated or new, holding the trails of [_schema8Rows] (security verification of schema 9, R8): the time set once, with its read's own; the lowest premium only going down, the highest only up, neither cleared; widening taken, a premium in between moving nothing.
Future<void> _termsTraceRules(GeneratedDatabase database) async {
  Future<void> change(String set, int robot) => database.customStatement(
    "UPDATE trade_trails SET $set WHERE robot_index = $robot AND key_fingerprint = '$_key'",
  );
  Future<void> refused(String set, int robot) => expectLater(
    change(set, robot),
    throwsA(
      predicate(
        (error) =>
            '$error'.contains('the trace of terms shown otherwise is kept'),
      ),
    ),
    reason: set,
  );
  await refused('terms_changed_at = 5', 1);
  await change(
    'read_at = 1300000, terms_changed_at = 1300000, terms_changed_premium_low = 7.0, terms_changed_premium_high = 7.0',
    1,
  );
  for (final set in [
    'terms_changed_at = NULL, terms_changed_premium_low = NULL, terms_changed_premium_high = NULL',
    'terms_changed_premium_low = NULL, terms_changed_premium_high = NULL',
    'terms_changed_premium_low = 8.0, terms_changed_premium_high = 8.0',
    'terms_changed_premium_high = 6.0, terms_changed_premium_low = 6.0',
    'read_at = 1400000, terms_changed_at = 1400000',
  ]) {
    await refused(set, 1);
  }
  // Widening, below then above: taken.
  await change('terms_changed_premium_low = -3.0', 1);
  await change('terms_changed_premium_high = 9.0', 1);
  // A premium in between: nothing moves, and the same values are taken.
  await change(
    'terms_changed_premium_low = -3.0, terms_changed_premium_high = 9.0',
    1,
  );
  await refused('terms_changed_premium_low = -2.0', 1);
  await refused('terms_changed_premium_high = 8.0', 1);
  await refused('terms_changed_premium_low = NULL', 1);
  await refused('terms_changed_premium_high = NULL', 1);
  final kept = await database
      .customSelect(
        "SELECT terms_changed_at, terms_changed_premium_low, terms_changed_premium_high FROM trade_trails WHERE robot_index = 1 AND key_fingerprint = '$_key'",
      )
      .getSingle();
  expect(kept.data, {
    'terms_changed_at': 1300000,
    'terms_changed_premium_low': -3.0,
    'terms_changed_premium_high': 9.0,
  });
  // Another term first, then premiums.
  await change('read_at = 1800000, terms_changed_at = 1800000', 6);
  await change(
    'terms_changed_premium_low = 5.0, terms_changed_premium_high = 5.0',
    6,
  );
  await change('terms_changed_premium_low = -8.0', 6);
  await refused('terms_changed_premium_high = 4.0', 6);
  await refused(
    'terms_changed_premium_low = NULL, terms_changed_premium_high = NULL',
    6,
  );
}

/// The kind of a statement of the step: what it does, and to what.
String _kindOf(String statement) {
  final words = statement
      .replaceAll('"', '')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  return switch (words) {
    ['ALTER', 'TABLE', final table, 'ADD', 'COLUMN', final column, ...] =>
      'add $table.$column',
    ['CREATE', 'TABLE', 'IF', 'NOT', 'EXISTS', final name, ...] =>
      'create $name',
    ['CREATE', 'TRIGGER', 'IF', 'NOT', 'EXISTS', final name, ...] =>
      'trigger $name',
    ['DROP', 'TRIGGER', 'IF', 'EXISTS', final name] => 'drop trigger $name',
    ['INSERT', 'INTO', final name, ...] => 'mark $name',
    _ => statement,
  };
}

/// The statements of the step over a file of schema 8, by kind, in their order: nothing dropped but the new table's own triggers, nothing copied.
const _stepKinds = [
  'add trade_payments.confirmed_sats',
  'add trade_trails.terms_changed_at',
  'add trade_trails.terms_changed_premium_low',
  'add trade_trails.terms_changed_premium_high',
  'create trade_payouts',
  'drop trigger trade_payouts_never_deleted',
  'drop trigger trade_payouts_forward',
  'drop trigger trade_payouts_of_their_trade',
  'drop trigger trade_payouts_inserted_once',
  'mark trade_payouts',
  'trigger trade_payouts_never_deleted',
  'trigger trade_payouts_forward',
  'trigger trade_payouts_of_their_trade',
  'trigger trade_payouts_inserted_once',
  'trigger trade_trails_terms_trace',
  'trigger trade_payments_sats_known',
  'trigger trade_payments_sats_forward',
  // Then the step to schema 10 (#81), which the file runs right after: three tables and their triggers, no row of an older table touched, and « Your Garage Keys » made due in its own new table.
  'create derived_garage_keys',
  'create selected_garage_keys',
  'trigger derived_garage_keys_never_deleted',
  'trigger derived_garage_keys_never_changed',
  'trigger derived_garage_keys_in_order',
  'trigger derived_garage_keys_inserted_once',
  'create garage_notices',
  'trigger garage_notices_shown_once',
  'trigger garage_notices_never_deleted',
  'mark garage_notices',
];

Future<int> _versionOf(GeneratedDatabase database) async =>
    (await database.customSelect('PRAGMA user_version').getSingle()).read<int>(
      'user_version',
    );

/// Every table, index and trigger of [database], table by table and, within a table, in the order SQLite made them (the order it fires the triggers of one event in, newest first), each as its table, its name and its text without quotes and white space.
Future<List<String>> _objectsOf(GeneratedDatabase database) async => [
  for (final row
      in await database
          .customSelect(
            "SELECT tbl_name, name, sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY tbl_name, rowid",
          )
          .get())
    '${row.read<String>('tbl_name')} ${row.read<String>('name')} ${row.read<String>('sql').replaceAll('"', '').replaceAll(RegExp(r'\s+'), '')}',
];

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
                'FROM $table ORDER BY ${_keys[table]}',
              )
              .get())
        row.data.values.toList(),
    ],
};

const _keys = {
  'garage_key_histories': 'network, key_fingerprint',
  'robot_bindings': 'key_fingerprint, robot_index',
  'trades': 'key_fingerprint, robot_index',
  'trade_terms': 'key_fingerprint, robot_index',
  'trade_trails': 'key_fingerprint, robot_index',
  'trade_payments': 'key_fingerprint, robot_index, step, take',
  'trade_chat_pins': 'key_fingerprint, robot_index',
  'trade_chat_nostr_pins': 'key_fingerprint, robot_index',
  'maker_terms': 'key_fingerprint, robot_index',
  'trade_payouts': 'key_fingerprint, robot_index, take',
};

/// Every column of every table of schema 8, in the order of its table.
const _schema8Columns = {
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
    'take',
    'take_deadline',
    'taker_hash_id',
    'taken_amount',
    'earlier_escrows',
    'seen_late',
  ],
  'trade_payments': [
    'key_fingerprint',
    'robot_index',
    'step',
    'payment_hash',
    'started_at',
    'wallet_payment_id',
    'take',
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
  'maker_terms': [
    'key_fingerprint',
    'robot_index',
    'version',
    'network',
    'coordinator_alias',
    'role',
    'order_type',
    'currency_id',
    'amount',
    'min_amount',
    'max_amount',
    'premium_percent',
    'payment_method',
    'bond_size_percent',
    'public_seconds',
    'escrow_seconds',
    'description',
    'has_password',
    'latitude',
    'longitude',
    'created_price',
    'maker_fee',
  ],
};

/// The table schema 9 adds.
const _schema9Columns = {
  'trade_payouts': [
    'key_fingerprint',
    'robot_index',
    'take',
    'source',
    'kind',
    'submitted_at',
  ],
};

/// The rows of the file of schema 8 and the text they share with the checks above: `schema8_rows.dart`, which `schema10_migration_test.dart` steps to schema 10 too.
final _key = schema8Key;
final _escrowOfSevenNext = schema8EscrowOfSevenNext;
const _trails = schema8Trails;
const _payments = schema8Payments;
final _schema8Rows = schema8Rows;
