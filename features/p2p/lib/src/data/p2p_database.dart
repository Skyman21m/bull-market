import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'p2p_database.g.dart';

/// What this device knows of the history of each Garage Key, per network: absent, the history is unknown.
@DataClassName('GarageKeyHistoryRow')
class GarageKeyHistories extends Table {
  /// `mainnet` or `testnet`.
  TextColumn get network => text()();

  /// The `GarageKeyFingerprint` of the key, 64 hexadecimal characters.
  TextColumn get keyFingerprint => text()();

  /// `generated` for a key drawn on this device, `imported` for a key pasted in: only `generated` lets a robot of the key be bound to a coordinator for the first time.
  TextColumn get origin => text()();

  /// When the origin was recorded, in milliseconds since the epoch.
  IntColumn get recordedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {network, keyFingerprint};

  @override
  List<String> get customConstraints => const [
    "CHECK (network IN ('mainnet', 'testnet'))",
    'CHECK (length(key_fingerprint) = 64)',
    "CHECK (origin IN ('generated', 'imported'))",
  ];
}

/// The coordinator each robot index of each Garage Key is bound to, per network, as the federation list gave it at binding time.
///
/// A row is never changed or deleted.
@DataClassName('RobotBindingRow')
class RobotBindings extends Table {
  /// `mainnet` or `testnet`.
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

  @override
  Set<Column<Object>> get primaryKey => {network, keyFingerprint, robotIndex};

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

/// The P2P feature's own database, `p2p.sqlite`, apart from the wallet's: the bindings of the robots and the history of the Garage Keys.
///
/// It holds no secret, and lives where the shell says, which keeps it out of cloud backups.
/// Only the foreground composition of the app opens it: the WorkManager isolate is given no directory, so no background task opens or migrates it.
/// Every schema version a release ships stays a supported upgrade source; a change adds a version, an idempotent migration step and a schema snapshot (`make drift-migrations`).
@DriftDatabase(tables: [GarageKeyHistories, RobotBindings])
final class P2pDatabase extends _$P2pDatabase {
  static const int schema = 1;

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
}
