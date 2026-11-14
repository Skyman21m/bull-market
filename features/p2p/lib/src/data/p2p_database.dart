import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'p2p_database.steps.dart';
import 'p2p_tables.dart';

part 'p2p_database.g.dart';

/// The P2P feature's own database, `p2p.sqlite`, apart from the wallet's: the bindings of the robots, the history of the Garage Keys, the trades of the robots and the terms and trail of each trade.
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
  ],
  include: {'trades.drift', 'trade_trails.drift'},
)
final class P2pDatabase extends _$P2pDatabase {
  static const int schema = 4;

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
  factory P2pDatabase.open(Future<Directory> Function() directory) =>
      P2pDatabase._(
        LazyDatabase(() async {
          final file = File.fromUri((await directory()).uri.resolve(fileName));
          return NativeDatabase.createInBackground(
            file,
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
    ),
    // Every connection, the app's and the tests', enforces the foreign key of the trades.
    beforeOpen: (details) => customStatement(_foreignKeysOn),
  );

  /// Whether [table] has a column named [column], read from SQLite's own description of the table.
  Future<bool> _hasColumn(String table, String column) async =>
      (await customSelect(
        'SELECT 1 FROM pragma_table_info(?) WHERE name = ?',
        variables: [Variable.withString(table), Variable.withString(column)],
      ).get()).isNotEmpty;
}
