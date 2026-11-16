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
/// The triggers of `trades.drift` refuse any other update, any delete and a second insert of a robot (`INSERT OR REPLACE` included), whatever the code that writes.
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
    // Times of the records this code writes: from the epoch to the last a `DateTime` holds.
    'CHECK (taken_at BETWEEN 0 AND 8640000000000000)',
    'CHECK (confirmed_at IS NULL OR confirmed_at BETWEEN 0 AND 8640000000000000)',
    'CHECK (closed_at IS NULL OR closed_at BETWEEN 0 AND 8640000000000000)',
    // The robot's binding, on the trade's network: the unique index `robot_bindings_network` (trades.drift) is its parent key.
    'FOREIGN KEY (key_fingerprint, robot_index, network) REFERENCES robot_bindings (key_fingerprint, robot_index, network)',
  ];
}

/// The terms each trade was taken with, `TradeTermsRecord` column for column, written once with the pending take and never changed nor deleted (schema 4, #87; design note § 3.5).
///
/// One row per trade, keyed as `trades` is (a foreign key to it); the triggers of `trade_trails.drift` refuse any update, any delete, a second insert (`INSERT OR REPLACE` included) and terms of no open trade or of another order, coordinator, network or role than the trade's, whatever the code that writes.
/// Read and written only by `TradeTrailRepositoryImpl`.
@DataClassName('TradeTermsRow')
class StoredTradeTerms extends Table {
  @override
  String get tableName => 'trade_terms';

  /// The trade's robot, as `trades` keys it.
  TextColumn get keyFingerprint => text()();
  IntColumn get robotIndex => integer()();

  /// `TradeTermsRecord.version`.
  IntColumn get version => integer()();

  /// The trade the terms belong to, which must be the trade of the row of `trades` they are keyed by: `RobosatsNetwork.name`, the coordinator's short alias, the order, `TradeRole.name`.
  TextColumn get network => text()();
  TextColumn get coordinatorAlias => text()();
  IntColumn get orderId => integer()();
  TextColumn get role => text()();

  /// `OrderType.wire`: 0 buy, 1 sell.
  IntColumn get orderType => integer()();
  IntColumn get currencyId => integer()();

  /// The fiat amount traded, in the order's currency.
  RealColumn get amount => real()();
  BoolColumn get isRange => boolean()();
  RealColumn get premiumPercent => real()();

  /// The sats of an order priced in sats, or absent.
  IntColumn get explicitSatoshis => integer().nullable()();
  RealColumn get bondSizePercent => real()();
  IntColumn get escrowSeconds => integer()();
  RealColumn get bookPrice => real()();
  RealColumn get takerFee => real()();

  @override
  Set<Column<Object>> get primaryKey => {keyFingerprint, robotIndex};

  @override
  List<String> get customConstraints => const [
    // The storage class of each column this code writes: SQLite keeps a value of another class in any column (a REAL in an INTEGER column, a text), which would read back as a record this code never wrote.
    "CHECK (typeof(key_fingerprint) = 'text' AND typeof(robot_index) = 'integer' AND typeof(version) = 'integer' AND typeof(network) = 'text' AND typeof(coordinator_alias) = 'text' AND typeof(order_id) = 'integer' AND typeof(role) = 'text' AND typeof(order_type) = 'integer' AND typeof(currency_id) = 'integer' AND typeof(is_range) = 'integer' AND (explicit_satoshis IS NULL OR typeof(explicit_satoshis) = 'integer') AND typeof(escrow_seconds) = 'integer')",
    "CHECK (length(key_fingerprint) = 64 AND key_fingerprint NOT GLOB '*[^0-9a-f]*')",
    'CHECK (robot_index BETWEEN 0 AND 2147483647)',
    'CHECK (version >= 1)',
    "CHECK (network IN ('mainnet', 'testnet'))",
    'CHECK (length(coordinator_alias) > 0)',
    'CHECK (order_id BETWEEN 1 AND 9007199254740992)',
    "CHECK (role IN ('buyer', 'seller'))",
    // Taking a sell order makes a buyer, taking a buy order a seller.
    "CHECK ((order_type = 1 AND role = 'buyer') OR (order_type = 0 AND role = 'seller'))",
    'CHECK (currency_id > 0)',
    // The doubles as `TradeTerms` holds them: real numbers, finite, in the bounds its checks give (a text or an infinity is refused; SQLite stores no NaN); the upper bound is written out, since drift's snapshot reads an exponent as 0.
    "CHECK (typeof(amount) = 'real' AND amount > 0 AND amount < 1000000000000000)",
    "CHECK (typeof(premium_percent) = 'real' AND premium_percent >= -100 AND premium_percent < 1000000000000000)",
    'CHECK (explicit_satoshis IS NULL OR explicit_satoshis BETWEEN 1 AND 2100000000000000)',
    "CHECK (typeof(bond_size_percent) = 'real' AND bond_size_percent BETWEEN 2 AND 15)",
    'CHECK (escrow_seconds BETWEEN 1800 AND 36000)',
    "CHECK (typeof(book_price) = 'real' AND book_price > 0 AND book_price < 1000000000000000)",
    "CHECK (typeof(taker_fee) = 'real' AND taker_fee BETWEEN 0 AND 0.01)",
    'FOREIGN KEY (key_fingerprint, robot_index) REFERENCES trades (key_fingerprint, robot_index)',
  ];
}

/// What the state machine remembers of each trade between two reads, `TradeTrailRecord` column for column: written with the pending take, then after each read (schema 4, #87; design note § 3.5, § 4.5).
///
/// One row per trade, keyed as `trades` is (a foreign key to it), never deleted.
/// The triggers of `trade_trails.drift` keep it monotonic whatever the code does: the trade it belongs to never changes, the version and the read never go back, a breach is never cleared, whether the history is known never changes, a pinned payment hash is never cleared or changed, the pre-take's last read is never cleared or moved back nor its deadline cleared, an end is never left, and the trail of a closed trade is never written again; a trail is written only for an open trade whose terms are recorded.
/// That the position moves only along the edges of the trade is `TradeTrailRecord.whyNotReplace`'s alone, which the repository asks before every write.
/// Read and written only by `TradeTrailRepositoryImpl`.
@DataClassName('TradeTrailRow')
class StoredTradeTrails extends Table {
  @override
  String get tableName => 'trade_trails';

  /// The trade's robot, as `trades` keys it.
  TextColumn get keyFingerprint => text()();
  IntColumn get robotIndex => integer()();

  /// `TradeTrailRecord.version`.
  IntColumn get version => integer()();

  /// The trade the trail belongs to: `RobosatsNetwork.name`, the coordinator's short alias, the order, `TradeRole.name`.
  TextColumn get network => text()();
  TextColumn get coordinatorAlias => text()();
  IntColumn get orderId => integer()();
  TextColumn get role => text()();

  /// `TradePosition.name` of the last status.
  TextColumn get position => text()();

  /// When the last status was read, in microseconds since the epoch.
  IntColumn get readAt => integer()();

  /// The payment hashes of the first bond and escrow invoices, 64 lowercase hexadecimal characters.
  TextColumn get bondHash => text().nullable()();
  TextColumn get escrowHash => text().nullable()();

  /// The deadline of the last order read, and the pre-take's last read and deadline, in microseconds since the epoch.
  IntColumn get deadline => integer().nullable()();
  IntColumn get bondStepSeenAt => integer().nullable()();
  IntColumn get bondStepDeadline => integer().nullable()();

  BoolColumn get breached => boolean()();
  BoolColumn get historyUnknown => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {keyFingerprint, robotIndex};

  @override
  List<String> get customConstraints => const [
    "CHECK (length(key_fingerprint) = 64 AND key_fingerprint NOT GLOB '*[^0-9a-f]*')",
    'CHECK (robot_index BETWEEN 0 AND 2147483647)',
    'CHECK (version >= 1)',
    "CHECK (network IN ('mainnet', 'testnet'))",
    'CHECK (length(coordinator_alias) > 0)',
    'CHECK (order_id BETWEEN 1 AND 9007199254740992)',
    "CHECK (role IN ('buyer', 'seller'))",
    // The storage class of each column this code writes, as for the terms.
    "CHECK (typeof(key_fingerprint) = 'text' AND typeof(robot_index) = 'integer' AND typeof(version) = 'integer' AND typeof(network) = 'text' AND typeof(coordinator_alias) = 'text' AND typeof(order_id) = 'integer' AND typeof(role) = 'text' AND typeof(position) = 'text' AND typeof(read_at) = 'integer' AND (bond_hash IS NULL OR typeof(bond_hash) = 'text') AND (escrow_hash IS NULL OR typeof(escrow_hash) = 'text') AND (deadline IS NULL OR typeof(deadline) = 'integer') AND (bond_step_seen_at IS NULL OR typeof(bond_step_seen_at) = 'integer') AND (bond_step_deadline IS NULL OR typeof(bond_step_deadline) = 'integer') AND typeof(breached) = 'integer' AND typeof(history_unknown) = 'integer')",
    // `TradePosition.values`, written out: a position added to the state machine needs a schema step.
    "CHECK (position IN ('start', 'bondStep', 'preTakeUnavailable', 'waitingForBoth', 'waitingForEscrow', 'waitingForPayout', 'chatting', 'fiatSent', 'inDispute', 'sendingSats', 'succeeded', 'routingFailed', 'waitingDisputeResolution', 'makerLostDispute', 'takerLostDispute', 'expired', 'cancelled', 'publicAgain', 'notAvailable'))",
    // Times from the epoch to the year 9999, as `TradeTrail.restore` takes them.
    'CHECK (read_at BETWEEN 0 AND 253402300799999999)',
    'CHECK (deadline IS NULL OR deadline BETWEEN 0 AND 253402300799999999)',
    'CHECK (bond_step_seen_at IS NULL OR bond_step_seen_at BETWEEN 0 AND read_at)',
    'CHECK (bond_step_deadline IS NULL OR bond_step_deadline BETWEEN 0 AND 253402300799999999)',
    "CHECK (bond_hash IS NULL OR (length(bond_hash) = 64 AND bond_hash NOT GLOB '*[^0-9a-f]*'))",
    "CHECK (escrow_hash IS NULL OR (length(escrow_hash) = 64 AND escrow_hash NOT GLOB '*[^0-9a-f]*'))",
    'FOREIGN KEY (key_fingerprint, robot_index) REFERENCES trades (key_fingerprint, robot_index)',
  ];
}

/// The payments of a trade's invoices this device asked the wallet's port for (schema 5, #100): one row per trade and step, written before the port is called, so that a restart knows a payment was asked and finds it again by its hash (`P2pWalletPort.findPayment`), and so that nothing pays an invoice twice.
///
/// `step IN ('bond')` and the trigger that refuses any delete mean that the escrow's panel (#97) rebuilds the table in its schema step (a new table, the rows copied, the old one dropped), the one step allowed to drop it.
///
/// It holds the invoice's payment hash (public, part of the invoice, and pinned already by the trail as `bond_hash`), when the last attempt started, and the wallet's local id of the swap that pays it once the port gives one; never the invoice, a preimage, an amount, an address or a transaction id.
/// The triggers of `trade_payments.drift` keep it: a row is never deleted, its trade, step and payment hash never change, its start never goes back, and a row is written only for an open trade whose trail is recorded.
/// Read and written only by `TradePaymentRepositoryImpl`.
@DataClassName('TradePaymentRow')
class StoredTradePayments extends Table {
  @override
  String get tableName => 'trade_payments';

  /// The trade's robot, as `trades` keys it.
  TextColumn get keyFingerprint => text()();
  IntColumn get robotIndex => integer()();

  /// `InvoiceStep.name` of the invoice paid: `bond` (the taker's bond) until the escrow's panel adds `escrow`.
  TextColumn get step => text()();

  /// The payment hash of the invoice, 64 lowercase hexadecimal characters.
  TextColumn get paymentHash => text()();

  /// When the last attempt was about to call the port, in microseconds since the epoch.
  IntColumn get startedAt => integer()();

  /// `P2pWalletPayment.id`, the wallet's local id of the swap that pays the invoice, once the port gave one.
  ///
  /// Recorded for the record's sake (a support question, a later reading): nothing decides on it, since the payment is found again by its hash (`P2pWalletPort.findPayment`), which the wallet's records key.
  TextColumn get walletPaymentId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {keyFingerprint, robotIndex, step};

  @override
  List<String> get customConstraints => const [
    "CHECK (length(key_fingerprint) = 64 AND key_fingerprint NOT GLOB '*[^0-9a-f]*')",
    'CHECK (robot_index BETWEEN 0 AND 2147483647)',
    // `InvoiceStep` written out: the escrow's panel adds it with its own schema step.
    "CHECK (step IN ('bond'))",
    "CHECK (length(payment_hash) = 64 AND payment_hash NOT GLOB '*[^0-9a-f]*')",
    'CHECK (started_at BETWEEN 0 AND 253402300799999999)',
    'CHECK (wallet_payment_id IS NULL OR length(wallet_payment_id) BETWEEN 1 AND 256)',
    // The storage class of each column this code writes, as for the terms and the trails.
    "CHECK (typeof(key_fingerprint) = 'text' AND typeof(robot_index) = 'integer' AND typeof(step) = 'text' AND typeof(payment_hash) = 'text' AND typeof(started_at) = 'integer' AND (wallet_payment_id IS NULL OR typeof(wallet_payment_id) = 'text'))",
    'FOREIGN KEY (key_fingerprint, robot_index) REFERENCES trades (key_fingerprint, robot_index)',
  ];
}

/// The peer's public key pinned for a trade's chat, with its two fingerprints (schema 6, #139): one row per trade, written when the chat pins the peer's key, so that after a restart of the app the key the coordinator serves is compared with it instead of being trusted again, and a breach then keeps reading the peer's earlier messages with it, as within one run (functional review of #139).
///
/// It holds the peer's public key in canonical armor and the two fingerprints that `PgpPublicKey` equality compares, its primary key's and its encryption subkey's: not secret, since the coordinator and the peer already hold that public key and the chat's export hands it out; never a private key, a message, or anything decrypted. The key read back is parsed by the package's bounded parser and must give these fingerprints, or the pin is unreadable. The chat's messages stay in memory only: this and the Nostr pin below are the only things of the chat that are stored.
/// The triggers of `trade_chat_pins.drift` keep it: a row is never deleted nor changed, a second one for a trade writes nothing, and a row is written only for an open trade.
/// They keep it against the app's own SQL, not against whoever can write the file, who can drop them (security review of #139).
/// Read and written only by `TradeChatPinRepositoryImpl`.
@DataClassName('TradeChatPinRow')
class StoredTradeChatPins extends Table {
  @override
  String get tableName => 'trade_chat_pins';

  /// The trade's robot, as `trades` keys it.
  TextColumn get keyFingerprint => text()();
  IntColumn get robotIndex => integer()();

  /// `PgpPublicKey.fingerprint` of the pinned key: 40 uppercase hexadecimal characters.
  TextColumn get primaryFingerprint => text()();

  /// `PgpPublicKey.subkeyFingerprint` of the pinned key: 40 uppercase hexadecimal characters.
  TextColumn get subkeyFingerprint => text()();

  /// `PgpPublicKey.armored` of the pinned key: an armored public key block of at most `PgpLimits.keyArmorChars` (20,000) characters.
  TextColumn get armoredKey => text()();

  @override
  Set<Column<Object>> get primaryKey => {keyFingerprint, robotIndex};

  @override
  List<String> get customConstraints => const [
    "CHECK (length(key_fingerprint) = 64 AND key_fingerprint NOT GLOB '*[^0-9a-f]*')",
    'CHECK (robot_index BETWEEN 0 AND 2147483647)',
    "CHECK (length(primary_fingerprint) = 40 AND primary_fingerprint NOT GLOB '*[^0-9A-F]*')",
    "CHECK (length(subkey_fingerprint) = 40 AND subkey_fingerprint NOT GLOB '*[^0-9A-F]*')",
    // The storage class of each column this code writes, as for the payments.
    "CHECK (length(armored_key) <= 20000 AND armored_key GLOB '-----BEGIN PGP PUBLIC KEY BLOCK-----*')",
    "CHECK (typeof(key_fingerprint) = 'text' AND typeof(robot_index) = 'integer' AND typeof(primary_fingerprint) = 'text' AND typeof(subkey_fingerprint) = 'text' AND typeof(armored_key) = 'text')",
    'FOREIGN KEY (key_fingerprint, robot_index) REFERENCES trades (key_fingerprint, robot_index)',
  ];
}

/// The Nostr keys of a trade pinned at its first Nostr copy (schema 6, part of #159): one row per trade, written before that copy is published, so that after a restart of the app a key the order changes stops the Nostr copies as within one run.
///
/// It holds the peer's and this robot's Nostr public keys as the order gives them: not secret, public keys that the coordinator gives both parties and that each gift wrap of the chat names in the clear to the relays; never a private key, a message or anything decrypted.
/// The triggers of `trade_chat_pins.drift` keep it as they keep the PGP pins: never deleted nor changed, a second one for a trade writes nothing, written only for an open trade.
/// Read and written only by `TradeChatPinRepositoryImpl`.
@DataClassName('TradeChatNostrPinRow')
class StoredTradeChatNostrPins extends Table {
  @override
  String get tableName => 'trade_chat_nostr_pins';

  /// The trade's robot, as `trades` keys it.
  TextColumn get keyFingerprint => text()();
  IntColumn get robotIndex => integer()();

  /// The peer's Nostr public key: 64 lowercase hexadecimal characters.
  TextColumn get peerKey => text()();

  /// This robot's Nostr public key as the order gives it: 64 lowercase hexadecimal characters.
  TextColumn get ownKey => text()();

  @override
  Set<Column<Object>> get primaryKey => {keyFingerprint, robotIndex};

  @override
  List<String> get customConstraints => const [
    "CHECK (length(key_fingerprint) = 64 AND key_fingerprint NOT GLOB '*[^0-9a-f]*')",
    'CHECK (robot_index BETWEEN 0 AND 2147483647)',
    "CHECK (length(peer_key) = 64 AND peer_key NOT GLOB '*[^0-9a-f]*')",
    "CHECK (length(own_key) = 64 AND own_key NOT GLOB '*[^0-9a-f]*')",
    "CHECK (typeof(key_fingerprint) = 'text' AND typeof(robot_index) = 'integer' AND typeof(peer_key) = 'text' AND typeof(own_key) = 'text')",
    'FOREIGN KEY (key_fingerprint, robot_index) REFERENCES trades (key_fingerprint, robot_index)',
  ];
}
