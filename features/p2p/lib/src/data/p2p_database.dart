import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'p2p_database.steps.dart';
import 'p2p_tables.dart';

part 'p2p_database.g.dart';

/// The P2P feature's own database, `p2p.sqlite`, apart from the wallet's: the bindings of the robots, the history of the Garage Keys, the trades of the robots, the terms and trail of each trade, the payments of its invoices asked of the wallet, and the keys of the peer its chat pinned (the PGP public key with its fingerprints, and the Nostr keys).
///
/// It holds no secret, and lives where the shell says, which keeps it out of cloud backups.
/// Only the foreground composition of the app opens it: the WorkManager isolate is given no directory, so no background task opens or migrates it.
/// Every schema version a release ships stays a supported upgrade source; a change adds a version, an idempotent migration step and a schema snapshot (`make drift-migrations`).
@DriftDatabase(
  tables: [
    GarageKeyHistories,
    RobotBindings,
    Trades,
    StoredTradeTerms,
    StoredTradeTrails,
    StoredTradePayments,
    StoredTradeChatPins,
    StoredTradeChatNostrPins,
  ],
  include: {
    'trades.drift',
    'trade_trails.drift',
    'trade_payments.drift',
    'trade_chat_pins.drift',
  },
)
final class P2pDatabase extends _$P2pDatabase {
  static const int schema = 7;

  /// Turns on SQLite's foreign keys for the connection, which are off by default: a trade's robot must be bound.
  ///
  /// It runs at each opening, after any migration step, outside a transaction, where SQLite takes it.
  static const String _foreignKeysOn = 'PRAGMA foreign_keys = ON';

  /// The name of the database file in the directory the shell gives.
  static const String fileName = 'p2p.sqlite';

  P2pDatabase._(super.executor);

  /// The database in the directory [directory] completes with, opened at the first query: creating it touches no file.
  ///
  /// Every commit is synced to disk (`synchronous = FULL`), so that a binding written survives a power cut before the request of its robot leaves.
  /// Prepared statements are not cached (#128): `package:sqlite3` leaves a statement whose step failed unreset until its next use, and a cached write that met `SQLITE_BUSY` stays active, so every later write of the connection, reported written, stays uncommitted under its write lock and is rolled back when that statement is reset: run again, evicted from drift's cache, or its connection closed. Each statement is finalized after its use instead, whatever it gave.
  factory P2pDatabase.open(Future<Directory> Function() directory) =>
      P2pDatabase._(
        LazyDatabase(() async {
          final file = File.fromUri((await directory()).uri.resolve(fileName));
          return NativeDatabase.createInBackground(
            file,
            cachePreparedStatements: false,
            setup: (database) {
              database.execute('PRAGMA busy_timeout = 2000;');
              database.execute('PRAGMA journal_mode = WAL;');
              database.execute('PRAGMA synchronous = FULL;');
            },
          );
        }),
      );

  factory P2pDatabase.forTesting(QueryExecutor executor) = P2pDatabase._;

  @override
  int get schemaVersion => schema;

  /// Each step brings a file from one version to the next, and can run again over a file it left halfway: the version is written only once the step is done.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        // `acknowledged` widens the CHECK of the histories, which SQLite cannot change in place: the table is rebuilt in one transaction, its rows copied as they are.
        // drift marks `TableMigration` experimental: that warning, and no other, is silenced on its line, as in the wallet's own migrations (`lib/core/storage/migrations/`).
        await m.alterTable(
          // ignore: experimental_member_use
          TableMigration(schema.garageKeyHistories),
        );
        // The bindings gain their provenance without a rebuild, so that no binding is ever copied or dropped: every binding of schema 1 was made under a key drawn here, the default.
        // A step that stopped after this column was added does not add it twice when it runs again.
        if (!await _hasColumn('robot_bindings', 'provenance')) {
          await m.addColumn(
            schema.robotBindings,
            schema.robotBindings.provenance,
          );
        }
      },
      from2To3: (m, schema) async {
        // A new table, the unique index its foreign key needs on the bindings, and the three triggers that keep its rows: each is created only when it is missing, so a step that stopped before the version was written runs again over the file it left.
        // The index adds no rule to the bindings, which the primary key (key fingerprint, robot index) already makes unique; no binding and no history is copied, changed or dropped.
        await m.createTable(schema.trades);
        await m.createIndex(schema.robotBindingsNetwork);
        await m.createTrigger(schema.tradesNeverDeleted);
        await m.createTrigger(schema.tradesSetOnce);
        await m.createTrigger(schema.tradesInsertedOnce);
      },
      from3To4: (m, schema) async {
        // Two new tables, the terms and the trail of each trade, the triggers that keep their rows, and one on the trades (one open trade per order): each is created only when it is missing, so a step that stopped before the version was written runs again over the file it left.
        // No row of an older table is copied, changed or dropped.
        await m.createTable(schema.tradeTerms);
        await m.createTable(schema.tradeTrails);
        await m.createTrigger(schema.tradesOneOpenPerOrder);
        await m.createTrigger(schema.tradeTermsNeverDeleted);
        await m.createTrigger(schema.tradeTermsSetOnce);
        await m.createTrigger(schema.tradeTermsInsertedOnce);
        await m.createTrigger(schema.tradeTermsOfTheirTrade);
        await m.createTrigger(schema.tradeTrailsNeverDeleted);
        await m.createTrigger(schema.tradeTrailsInsertedOnce);
        await m.createTrigger(schema.tradeTrailsOfTheirTrade);
        await m.createTrigger(schema.tradeTrailsClosed);
        await m.createTrigger(schema.tradeTrailsForward);
      },
      from4To5: (m, schema) async {
        // A new table, the payments of a trade's invoices asked of the wallet (#100), and the triggers that keep its rows: each is created only when it is missing, so a step that stopped before the version was written runs again over the file it left.
        // No row of an older table is copied, changed or dropped.
        await m.createTable(schema.tradePayments);
        await m.createTrigger(schema.tradePaymentsNeverDeleted);
        await m.createTrigger(schema.tradePaymentsInsertedOnce);
        await m.createTrigger(schema.tradePaymentsOfTheirTrade);
        await m.createTrigger(schema.tradePaymentsForward);
      },
      from5To6: (m, schema) async {
        // Two new tables, the peer's PGP public key each trade's chat pinned, with its fingerprints (#139), and the Nostr keys of its first Nostr copy (part of #159), and the triggers that keep their rows: each is created only when it is missing, so a step that stopped before the version was written runs again over the file it left.
        // No row of an older table is copied, changed or dropped; a trade of an older file has no pin, and its chat pins at its first read and its first Nostr copy as before.
        await m.createTable(schema.tradeChatPins);
        await m.createTrigger(schema.tradeChatPinsNeverDeleted);
        await m.createTrigger(schema.tradeChatPinsNeverChanged);
        await m.createTrigger(schema.tradeChatPinsInsertedOnce);
        await m.createTrigger(schema.tradeChatPinsOfTheirTrade);
        await m.createTable(schema.tradeChatNostrPins);
        await m.createTrigger(schema.tradeChatNostrPinsNeverDeleted);
        await m.createTrigger(schema.tradeChatNostrPinsNeverChanged);
        await m.createTrigger(schema.tradeChatNostrPinsInsertedOnce);
        await m.createTrigger(schema.tradeChatNostrPinsOfTheirTrade);
      },
      from6To7: (m, schema) async {
        // The payments gain the seller's escrow (#97): `escrow` widens the CHECK of their step, which SQLite cannot change in place. The table is rebuilt in one transaction: its rows are copied aside, the table dropped (its four triggers with it; a drop fires no trigger), made again with the new CHECK, its rows copied back as they are before its triggers exist (a payment of a trade closed since is kept, which the insert trigger would refuse), then its triggers made again.
        // A file whose table already allows the escrow (a step that stopped after the rebuild, before the version was written) is left as it is; one that stopped inside the transaction was rolled back to schema 6.
        if (await _paymentsAllowEscrow()) return;
        await transaction(() async {
          await customStatement(
            'DROP TABLE IF EXISTS trade_payments_of_schema6',
          );
          await customStatement(
            'CREATE TABLE trade_payments_of_schema6 AS SELECT * FROM trade_payments',
          );
          await customStatement('DROP TABLE trade_payments');
          await m.createTable(schema.tradePayments);
          await customStatement(
            'INSERT INTO trade_payments (key_fingerprint, robot_index, step, payment_hash, started_at, wallet_payment_id) '
            'SELECT key_fingerprint, robot_index, step, payment_hash, started_at, wallet_payment_id FROM trade_payments_of_schema6',
          );
          await customStatement('DROP TABLE trade_payments_of_schema6');
          await m.createTrigger(schema.tradePaymentsNeverDeleted);
          await m.createTrigger(schema.tradePaymentsInsertedOnce);
          await m.createTrigger(schema.tradePaymentsOfTheirTrade);
          await m.createTrigger(schema.tradePaymentsForward);
        });
      },
    ),
    // Every connection, the app's and the tests', enforces the foreign key of the trades.
    beforeOpen: (details) => customStatement(_foreignKeysOn),
  );

  /// Whether the payments' table already allows the escrow's step, read from SQLite's own text of the table.
  Future<bool> _paymentsAllowEscrow() async {
    final row = await customSelect(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'trade_payments'",
    ).getSingleOrNull();
    return row?.read<String>('sql').contains("'escrow'") ?? false;
  }

  /// Whether [table] has a column named [column], read from SQLite's own description of the table.
  Future<bool> _hasColumn(String table, String column) async =>
      (await customSelect(
        'SELECT 1 FROM pragma_table_info(?) WHERE name = ?',
        variables: [Variable.withString(table), Variable.withString(column)],
      ).get()).isNotEmpty;
}
