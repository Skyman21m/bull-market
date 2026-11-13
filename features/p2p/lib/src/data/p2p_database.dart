import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'p2p_database.steps.dart';

part 'p2p_database.g.dart';

/// What this device knows of the history of each Garage Key, per network: absent, the history is unknown.
@DataClassName('GarageKeyHistoryRow')
class GarageKeyHistories extends Table {
  /// `mainnet` or `testnet`.
  TextColumn get network => text()();

  /// The `GarageKeyFingerprint` of the key, 64 hexadecimal characters.
  TextColumn get keyFingerprint => text()();

  /// `generated` for a key drawn on this device, `imported` for a key pasted in, `acknowledged` (since schema 2) for a key of unknown history whose robots the user accepted to bind: only `generated` and `acknowledged` let a robot of the key be bound to a coordinator for the first time.
  TextColumn get origin => text()();

  /// When the origin was recorded, in milliseconds since the epoch.
  IntColumn get recordedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {network, keyFingerprint};

  @override
  List<String> get customConstraints => const [
    "CHECK (network IN ('mainnet', 'testnet'))",
    'CHECK (length(key_fingerprint) = 64)',
    "CHECK (origin IN ('generated', 'imported', 'acknowledged'))",
  ];
}

/// The coordinator each robot index of each Garage Key is bound to, as the federation list gave it at binding time.
///
/// One row per key fingerprint and robot index, whatever the network: a robot's token does not depend on the network (`GarageKey.deriveToken` takes none), so the same key in both slots gives the same credential on testnet and mainnet, and an index bound on one network is bound on the other too.
/// The network of the coordinator is a column of the row, recorded and checked like the rest.
/// A row is never changed or deleted.
@DataClassName('RobotBindingRow')
class RobotBindings extends Table {
  /// The network of the coordinator, `mainnet` or `testnet`.
  TextColumn get network => text()();

  /// The `GarageKeyFingerprint` of the key, 64 hexadecimal characters.
  TextColumn get keyFingerprint => text()();

  /// The index of the robot in its key, a hardened BIP32 child number.
  IntColumn get robotIndex => integer()();

  /// The short alias of the coordinator in the federation list.
  TextColumn get coordinatorAlias => text()();

  /// The onion origin of the coordinator's instance on the network.
  TextColumn get coordinatorOnion => text()();

  /// The public keys of the Lightning nodes of that instance, sorted and joined with commas.
  TextColumn get coordinatorNodeKeys => text()();

  /// The Nostr public key of the coordinator, in hexadecimal.
  TextColumn get coordinatorNostrKey => text()();

  /// When the binding was written, in milliseconds since the epoch.
  IntColumn get boundAt => integer()();

  /// The origin of the key on [network] when the robot was bound, copied from `garage_key_histories` by the statement that binds: `generated` or `acknowledged` (since schema 2).
  ///
  /// Its constraints are the column's own, so that schema 2 adds it to the table without rebuilding it; its default is for the bindings of schema 1, all made under a key drawn here.
  TextColumn get provenance => text().customConstraint(
    "NOT NULL DEFAULT 'generated' "
    "CHECK (provenance IN ('generated', 'acknowledged'))",
  )();

  @override
  Set<Column<Object>> get primaryKey => {keyFingerprint, robotIndex};

  @override
  List<String> get customConstraints => const [
    "CHECK (network IN ('mainnet', 'testnet'))",
    'CHECK (length(key_fingerprint) = 64)',
    'CHECK (robot_index BETWEEN 0 AND 2147483647)',
    'CHECK (length(coordinator_alias) > 0)',
    'CHECK (length(coordinator_onion) > 0)',
    'CHECK (length(coordinator_nostr_key) > 0)',
  ];
}

/// The trades of this device's robots, one row per robot that ever had one, so that a trade survives the app being killed (schema 3, #85; design note `docs/design/phase-2-taking-an-order.md` § 3.5, § 4.5).
///
/// A row is written before the take's request leaves, as a pending take, or on the user's take-over of a trade that recovery found; it is never deleted.
/// Its only changes are the times of its state, each set once: `confirmed_at` when the coordinator showed the robot as the taker, `closed_at` when the trade ended or the pending take turned out not to have happened.
/// Its robot is bound to the coordinator it records (a foreign key to `robot_bindings`), and its network and coordinator are copied from that binding by the statement that writes it.
@DataClassName('TradeRow')
class Trades extends Table {
  /// The network of the robot's binding, `mainnet` or `testnet`.
  TextColumn get network => text()();

  /// The `GarageKeyFingerprint` of the robot's key, 64 hexadecimal characters.
  TextColumn get keyFingerprint => text()();

  /// The index of the robot in its key.
  IntColumn get robotIndex => integer()();

  /// The short alias of the coordinator, as the robot's binding records it.
  TextColumn get coordinatorAlias => text()();

  /// The onion origin of the coordinator's instance, as the robot's binding records it.
  TextColumn get coordinatorOnion => text()();

  /// The id of the order on that coordinator.
  IntColumn get orderId => integer()();

  /// `buyer` or `seller`, fixed at the take.
  TextColumn get role => text()();

  /// `takenHere` for a take of this device, `recovered` for a trade the user took over after recovery found it.
  TextColumn get origin => text()();

  /// When the row was written, in milliseconds since the epoch.
  IntColumn get takenAt => integer()();

  /// When the coordinator showed this robot as the order's taker, in milliseconds since the epoch; absent while the take is pending.
  IntColumn get confirmedAt => integer().nullable()();

  /// When the trade ended, or its pending take turned out not to have happened, in milliseconds since the epoch; absent while it is active.
  IntColumn get closedAt => integer().nullable()();

  /// One trade per robot, ever: a robot is never used for a second trade.
  @override
  Set<Column<Object>> get primaryKey => {keyFingerprint, robotIndex};

  @override
  List<String> get customConstraints => const [
    "CHECK (network IN ('mainnet', 'testnet'))",
    'CHECK (length(key_fingerprint) = 64)',
    'CHECK (robot_index BETWEEN 0 AND 2147483647)',
    'CHECK (length(coordinator_alias) > 0)',
    'CHECK (length(coordinator_onion) > 0)',
    'CHECK (order_id > 0)',
    "CHECK (role IN ('buyer', 'seller'))",
    "CHECK (origin IN ('takenHere', 'recovered'))",
    // A recovered trade is held by its robot when it is recorded: it is never a pending take.
    "CHECK (origin = 'takenHere' OR confirmed_at IS NOT NULL)",
    'FOREIGN KEY (key_fingerprint, robot_index) REFERENCES robot_bindings (key_fingerprint, robot_index)',
  ];
}

/// The P2P feature's own database, `p2p.sqlite`, apart from the wallet's: the bindings of the robots, the history of the Garage Keys and the trades of the robots.
///
/// It holds no secret, and lives where the shell says, which keeps it out of cloud backups.
/// Only the foreground composition of the app opens it: the WorkManager isolate is given no directory, so no background task opens or migrates it.
/// Every schema version a release ships stays a supported upgrade source; a change adds a version, an idempotent migration step and a schema snapshot (`make drift-migrations`).
@DriftDatabase(tables: [GarageKeyHistories, RobotBindings, Trades])
final class P2pDatabase extends _$P2pDatabase {
  static const int schema = 3;

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
        // A new table: drift creates it only when it is missing, so a step that stopped before the version was written runs again over the file it left.
        // No binding and no history is touched.
        await m.createTable(schema.trades);
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
