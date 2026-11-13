import 'package:drift/drift.dart';

// The tables of `p2p.sqlite` (`P2pDatabase`), apart from the database so that `trades.drift`, which the database includes, can import them.

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
/// The triggers of `trades.drift` refuse any other change and any delete, whatever the code that writes.
/// Its robot is bound, on the trade's network, to the coordinator it records (a foreign key to `robot_bindings`), and its network and coordinator are copied from that binding by the statement that writes it.
@DataClassName('TradeRow')
class Trades extends Table {
  /// The network of the robot's binding, `mainnet` or `testnet`.
  TextColumn get network => text()();

  /// The `GarageKeyFingerprint` of the robot's key, 64 lowercase hexadecimal characters.
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
    "CHECK (length(key_fingerprint) = 64 AND key_fingerprint NOT GLOB '*[^0-9a-f]*')",
    'CHECK (robot_index BETWEEN 0 AND 2147483647)',
    'CHECK (length(coordinator_alias) > 0)',
    'CHECK (length(coordinator_onion) > 0)',
    'CHECK (order_id > 0)',
    "CHECK (role IN ('buyer', 'seller'))",
    "CHECK (origin IN ('takenHere', 'recovered'))",
    // A recovered trade is held by its robot when it is recorded: it is never a pending take.
    "CHECK (origin = 'takenHere' OR confirmed_at IS NOT NULL)",
    // Times of the records this code writes: never before the epoch.
    'CHECK (taken_at >= 0)',
    'CHECK (confirmed_at IS NULL OR confirmed_at >= 0)',
    'CHECK (closed_at IS NULL OR closed_at >= 0)',
    // The robot's binding, on the trade's network: the unique index `robot_bindings_network` (trades.drift) is its parent key.
    'FOREIGN KEY (key_fingerprint, robot_index, network) REFERENCES robot_bindings (key_fingerprint, robot_index, network)',
  ];
}
