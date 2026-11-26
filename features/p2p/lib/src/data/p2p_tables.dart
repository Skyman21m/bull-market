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
/// A row is written before the take's request leaves, as a pending take, before the make's request leaves, as a pending make (schema 8, #176; design note `docs/design/phase-3-making-an-order.md` § 3.4, § 3.5), or on the user's take-over of a trade that recovery found; it is never deleted.
/// Its only changes are the times of its state, each set once: `confirmed_at` when the coordinator showed the robot as the taker, or as the maker, `closed_at` when the trade ended or the pending take or make turned out not to have happened; a pending make gains its order id once, in the update that confirms it, and only once its maker's terms are recorded.
/// The triggers of `trades.drift` refuse any other update, any delete and a second insert of a robot (`INSERT OR REPLACE` included), whatever the code that writes.
///
/// Schema 8 rebuilt the table (the order id became nullable, the origin `madeHere` joined the CHECKs, which SQLite cannot change in place): its step copied the rows aside, dropped the table and made it again, copied the rows back, then made its triggers again (`P2pDatabase`, from 7 to 8).
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

  /// The id of the order on that coordinator; absent only for a pending make, whose order the coordinator has not numbered yet (schema 8).
  IntColumn get orderId => integer().nullable()();

  /// `buyer` or `seller`, fixed at the take, or at the make.
  TextColumn get role => text()();

  /// `takenHere` for a take of this device, `madeHere` for an order this device made (schema 8), `recovered` for a trade the user took over after recovery found it.
  TextColumn get origin => text()();

  /// When the row was written, in milliseconds since the epoch.
  IntColumn get takenAt => integer()();

  /// When the coordinator showed this robot as the order's taker, or as its maker, in milliseconds since the epoch; absent while the take or the make is pending.
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
    // An order id, but for a pending make (schema 8): written before its order exists, never confirmed without one. Each part is true or false, never `NULL`, which a CHECK would let pass.
    "CHECK ((order_id IS NOT NULL AND order_id > 0) OR (order_id IS NULL AND origin = 'madeHere' AND confirmed_at IS NULL))",
    "CHECK (role IN ('buyer', 'seller'))",
    "CHECK (origin IN ('takenHere', 'madeHere', 'recovered'))",
    // A make is confirmed when, and only when, its order id is written.
    "CHECK (origin <> 'madeHere' OR ((order_id IS NULL) = (confirmed_at IS NULL)))",
    // A recovered trade is held by its robot when it is recorded: it is never pending.
    "CHECK (origin <> 'recovered' OR confirmed_at IS NOT NULL)",
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
/// One row per trade, keyed as `trades` is (a foreign key to it); the triggers of `trade_trails.drift` refuse any update, any delete, a second insert (`INSERT OR REPLACE` included) and terms of no open trade, of a trade made here (whose terms are in `maker_terms`, schema 8), or of another order, coordinator, network or role than the trade's, whatever the code that writes.
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
/// The triggers of `trade_trails.drift` keep it monotonic whatever the code does: the trade it belongs to never changes, the version and the read never go back, a breach is never cleared, whether the history is known never changes, a pinned payment hash is never cleared or changed (but the escrow's, in the write that opens a maker's next contract), the pre-take's last read is never cleared or moved back nor its deadline cleared, an end is never left, a maker's contract only moves forward, and the trail of a closed trade is never written again; a trail is written only for an open trade whose order id is known and whose terms are recorded.
/// That the position moves only along the edges of the trade is `TradeTrailRecord.whyNotReplace`'s alone, which the repository asks before every write.
/// Read and written only by `TradeTrailRepositoryImpl`.
///
/// Schema 8 (#176) rebuilt the table, as it rebuilt `trades` (the maker's positions joined the CHECK of the position, and four columns keep a maker's current contract): a trail of an older file keeps every value, and its contract columns their defaults, which a taker's trail always keeps.
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

  /// The index of a maker's current contract (schema 8; design note `docs/design/phase-3-making-an-order.md` § 3.2): 0 for the order's first take, one more for each take after the order went back to the book; always 0 for a trade not made here.
  IntColumn get take => integer().withDefault(const Constant(0))();

  /// The deadline the coordinator gave the current contract, in microseconds since the epoch; absent until a read of 6, 7 or 8 opens the first contract, and always for a trade not made here.
  IntColumn get takeDeadline => integer().nullable()();

  /// The hash id of the current contract's taker, 64 lowercase hexadecimal characters; absent until a read names it, and always for a trade not made here.
  TextColumn get takerHashId => text().nullable()();

  /// The fiat amount the current contract took of a range, in the order's currency; absent for a fixed amount, until a read gives it, and always for a trade not made here.
  RealColumn get takenAmount => real().nullable()();

  /// The escrow hashes a maker's earlier contracts pinned, oldest first, each 64 lowercase hexadecimal characters followed by `;` (schema 8 as amended by #178 before any release): only grown, by the escrow hash held when `take` moves, so that an escrow of an earlier contract is never pinned again; empty at contract 0, and always for a trade not made here.
  TextColumn get earlierEscrows => text().withDefault(const Constant(''))();

  /// Whether a maker's current contract was first read from the chat on (a next contract seen late, #178), set only in the write that opens that contract; false at contract 0, and always for a trade not made here.
  BoolColumn get seenLate => boolean().withDefault(const Constant(false))();

  /// When a read kept for this trade first showed it with other terms than its own (`TradeTermsChanged`), in microseconds since the epoch: the read time of that write, set once and kept to the end (schema 9, #231; design note `docs/design/phase-3-making-an-order.md` § 3.5 bis); absent when none did since schema 9, and for every trail of a schema 8 file, whose trace was never recorded.
  ///
  /// Its constraints are the column's own, so that schema 9 adds it to the table without rebuilding it.
  IntColumn get termsChangedAt => integer().nullable().customConstraint(
    "NULL CHECK (terms_changed_at IS NULL OR (typeof(terms_changed_at) = 'integer' AND terms_changed_at BETWEEN 0 AND read_at))",
  )();

  /// The lowest and the highest premium, in percent, that reads kept showed otherwise than the trade's own (an order not priced in sats, within the package's bounds, -100 to 999); both absent while no read showed another premium (schema 9, #231). Both written as soon as a premium differs, even after another term changed first; then the lowest only goes down and the highest only up, neither is cleared: the trigger `trade_trails_terms_trace` keeps them, so that the trace never says less than was seen, on either side (security reviews of schema 9, C1 and R8).
  RealColumn get termsChangedPremiumLow => real().nullable().customConstraint(
    "NULL CHECK (terms_changed_premium_low IS NULL OR (terms_changed_at IS NOT NULL AND typeof(terms_changed_premium_low) = 'real' AND terms_changed_premium_low BETWEEN -100 AND 999))",
  )();
  RealColumn get termsChangedPremiumHigh => real().nullable().customConstraint(
    "NULL CHECK ((terms_changed_premium_high IS NULL) = (terms_changed_premium_low IS NULL) AND (terms_changed_premium_high IS NULL OR (typeof(terms_changed_premium_high) = 'real' AND terms_changed_premium_high BETWEEN -100 AND 999 AND terms_changed_premium_high >= terms_changed_premium_low)))",
  )();

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
    // `TradePosition.values`, written out, and the maker's three positions (schema 8): a position added to the state machine needs a schema step.
    "CHECK (position IN ('start', 'makerBondStep', 'public', 'paused', 'bondStep', 'preTakeUnavailable', 'waitingForBoth', 'waitingForEscrow', 'waitingForPayout', 'chatting', 'fiatSent', 'inDispute', 'sendingSats', 'succeeded', 'routingFailed', 'waitingDisputeResolution', 'makerLostDispute', 'takerLostDispute', 'expired', 'cancelled', 'publicAgain', 'notAvailable'))",
    // Times from the epoch to the year 9999, as `TradeTrail.restore` takes them.
    'CHECK (read_at BETWEEN 0 AND 253402300799999999)',
    'CHECK (deadline IS NULL OR deadline BETWEEN 0 AND 253402300799999999)',
    'CHECK (bond_step_seen_at IS NULL OR bond_step_seen_at BETWEEN 0 AND read_at)',
    'CHECK (bond_step_deadline IS NULL OR bond_step_deadline BETWEEN 0 AND 253402300799999999)',
    "CHECK (bond_hash IS NULL OR (length(bond_hash) = 64 AND bond_hash NOT GLOB '*[^0-9a-f]*'))",
    "CHECK (escrow_hash IS NULL OR (length(escrow_hash) = 64 AND escrow_hash NOT GLOB '*[^0-9a-f]*'))",
    // A maker's contract (schema 8): the storage class of each of its columns, its index from 0, its deadline a time as the others, its taker a hash id, the amount it took a positive real below the make's own bound (`MakeOrderRequest.amountLimit`, written out), and a later contract always with its deadline.
    "CHECK (typeof(take) = 'integer' AND (take_deadline IS NULL OR typeof(take_deadline) = 'integer') AND (taker_hash_id IS NULL OR typeof(taker_hash_id) = 'text') AND (taken_amount IS NULL OR typeof(taken_amount) = 'real'))",
    'CHECK (take >= 0)',
    'CHECK (take_deadline IS NULL OR take_deadline BETWEEN 0 AND 253402300799999999)',
    "CHECK (taker_hash_id IS NULL OR (length(taker_hash_id) = 64 AND taker_hash_id NOT GLOB '*[^0-9a-f]*'))",
    'CHECK (taken_amount IS NULL OR (taken_amount > 0 AND taken_amount < 10000000000))',
    'CHECK (take = 0 OR take_deadline IS NOT NULL)',
    // The escrows of earlier contracts, and whether the contract was seen late (amended by #178 before any release): text of hashes each followed by `;`, a flag, both empty at contract 0, so on every first trail and every trail of a trade not made here.
    "CHECK (typeof(earlier_escrows) = 'text' AND length(earlier_escrows) % 65 = 0 AND earlier_escrows NOT GLOB '*[^0-9a-f;]*' AND typeof(seen_late) = 'integer' AND seen_late IN (0, 1))",
    "CHECK (take > 0 OR (earlier_escrows = '' AND seen_late = 0))",
    'FOREIGN KEY (key_fingerprint, robot_index) REFERENCES trades (key_fingerprint, robot_index)',
  ];
}

/// The payments of a trade's invoices this device asked the wallet's port for (schema 5, #100): one row per trade, step and contract, written before the port is called, so that a restart knows a payment was asked and finds it again by its hash (`P2pWalletPort.findPayment`), and so that nothing pays an invoice twice.
///
/// Schema 7 (#97) widened its step to `('bond', 'escrow')`: the trigger that refuses any delete does not fire on a drop, so its step rebuilt the table (the rows copied aside, the table dropped and made again, the rows copied back, then the triggers), the one step allowed to drop it (`P2pDatabase`, from 6 to 7).
/// Schema 8 (#176) rebuilt it again, as it rebuilt `trades` and `trade_trails`, for the contract of a maker's escrow (`take`, in the primary key; design note `docs/design/phase-3-making-an-order.md` § 3.5): every payment of an older file is of contract 0.
///
/// It holds the invoice's payment hash (public, part of the invoice, and pinned already by the trail as `bond_hash`), when the last attempt started, the wallet's local id of the swap that pays it once the port gives one, and since schema 9 (#233) the total the user confirmed for it; never the invoice, a preimage, an address or a transaction id.
/// The triggers of `trade_payments.drift` keep it: a row is never deleted, its trade, step, contract and payment hash never change, its start never goes back, a row is written only for an open trade whose trail is recorded at the row's contract, a payment hash another row holds is never written again, whatever its trade, step or contract, and since schema 9 a row is written only with its amount, which never goes down.
/// Read and written only by `TradePaymentRepositoryImpl`.
@DataClassName('TradePaymentRow')
class StoredTradePayments extends Table {
  @override
  String get tableName => 'trade_payments';

  /// The trade's robot, as `trades` keys it.
  TextColumn get keyFingerprint => text()();
  IntColumn get robotIndex => integer()();

  /// `InvoiceStep.name` of the invoice paid: `bond` (the taker's bond) or, since schema 7 (#97), `escrow` (the seller's escrow).
  TextColumn get step => text()();

  /// The payment hash of the invoice, 64 lowercase hexadecimal characters.
  TextColumn get paymentHash => text()();

  /// When the last attempt was about to call the port, in microseconds since the epoch.
  IntColumn get startedAt => integer()();

  /// `P2pWalletPayment.id`, the wallet's local id of the swap that pays the invoice, once the port gave one.
  ///
  /// Recorded for the record's sake (a support question, a later reading): nothing decides on it, since the payment is found again by its hash (`P2pWalletPort.findPayment`), which the wallet's records key.
  TextColumn get walletPaymentId => text().nullable()();

  /// The contract the invoice belongs to, the trail's `take` when the row was written (schema 8): 0 for a bond and for every payment of a trade not made here, one more for a maker seller's escrow of each later contract.
  IntColumn get take => integer().withDefault(const Constant(0))();

  /// What the payment takes out of the wallet: the total of the quote the user confirmed (the invoice, the swap service's fee and the network fee, `P2pWalletQuote.total`), in sats, written by the statement that records the payment's start, before the wallet is asked (schema 9, #233; design note `docs/design/phase-3-making-an-order.md` § 3.5 bis); a new attempt of the same invoice never lowers it.
  ///
  /// Absent for every payment of a schema 8 file, whose amount was never kept: unknown, never zero. Its constraints are the column's own, so that schema 9 adds it to the table without rebuilding it; the triggers of `trade_payments.drift` refuse a payment recorded without it and an amount that goes down, is cleared, or appears on a payment whose amount was unknown.
  IntColumn get confirmedSats => integer().nullable().customConstraint(
    "NULL CHECK (confirmed_sats IS NULL OR (typeof(confirmed_sats) = 'integer' AND confirmed_sats BETWEEN 1 AND 2100000000000000))",
  )();

  @override
  Set<Column<Object>> get primaryKey => {
    keyFingerprint,
    robotIndex,
    step,
    take,
  };

  @override
  List<String> get customConstraints => const [
    "CHECK (length(key_fingerprint) = 64 AND key_fingerprint NOT GLOB '*[^0-9a-f]*')",
    'CHECK (robot_index BETWEEN 0 AND 2147483647)',
    // `InvoiceStep` written out: the escrow joined the bond in schema 7 (#97).
    "CHECK (step IN ('bond', 'escrow'))",
    "CHECK (length(payment_hash) = 64 AND payment_hash NOT GLOB '*[^0-9a-f]*')",
    'CHECK (started_at BETWEEN 0 AND 253402300799999999)',
    'CHECK (wallet_payment_id IS NULL OR length(wallet_payment_id) BETWEEN 1 AND 256)',
    // The storage class of each column this code writes, as for the terms and the trails.
    "CHECK (typeof(key_fingerprint) = 'text' AND typeof(robot_index) = 'integer' AND typeof(step) = 'text' AND typeof(payment_hash) = 'text' AND typeof(started_at) = 'integer' AND (wallet_payment_id IS NULL OR typeof(wallet_payment_id) = 'text'))",
    // The contract (schema 8): an integer from 0, and 0 for a bond, which is one for the order's whole life.
    "CHECK (typeof(take) = 'integer' AND take >= 0)",
    "CHECK (step = 'escrow' OR take = 0)",
    'FOREIGN KEY (key_fingerprint, robot_index) REFERENCES trades (key_fingerprint, robot_index)',
  ];
}

/// Where the payout of each contract of a buyer's trade came from, as this device gave it (schema 9, #204; design note `docs/design/phase-3-making-an-order.md` § 3.5 bis): one row per trade and contract (`take`), written by `SubmitPayoutUsecase` right after the coordinator's answer took the payout, or may have, so that before « Confirm … sent » the app knows whether the payout of the contract it stands at was given from this wallet, pasted, or not given from this device.
///
/// It holds whether the payout was given from this wallet or pasted, whether it is an invoice or an address, and when it was submitted; never the invoice, its payment hash, nor the address (nothing reads them, and the hash of a pasted invoice would tie this file to another wallet's payment: security review of schema 9, R4). `unrecorded` marks a contract already under way when the step to schema 9 ran (its payout, if any, was given before payouts were recorded): written by that step only, it reads « unknown », never « given elsewhere ».
/// The triggers of `trade_payouts.drift` keep it: a row is never deleted, its trade and contract never change, it never becomes `unrecorded`, its time never goes back, a second insert writes nothing, and a row is written only for an open trade of a buyer whose trail stands at the row's contract.
/// Read and written only by `TradePayoutRepositoryImpl`.
@DataClassName('TradePayoutRow')
class StoredTradePayouts extends Table {
  @override
  String get tableName => 'trade_payouts';

  /// The trade's robot, as `trades` keys it.
  TextColumn get keyFingerprint => text()();
  IntColumn get robotIndex => integer()();

  /// The contract the payout was given for, the trail's `take` of the read the payout was signed from: 0 for every taker and for a maker's first contract.
  IntColumn get take => integer()();

  /// `thisWallet` (an invoice or an address this wallet gave), `pasted` (anything else), or `unrecorded` (a contract under way before schema 9).
  TextColumn get source => text()();

  /// `invoice` or `address`; absent for `unrecorded`.
  TextColumn get kind => text().nullable()();

  /// When the payout was submitted, in microseconds since the epoch; absent for `unrecorded` only.
  IntColumn get submittedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {keyFingerprint, robotIndex, take};

  @override
  List<String> get customConstraints => const [
    // The storage class of each column this code writes, as for the payments.
    "CHECK (typeof(key_fingerprint) = 'text' AND typeof(robot_index) = 'integer' AND typeof(take) = 'integer' AND typeof(source) = 'text' AND (kind IS NULL OR typeof(kind) = 'text') AND (submitted_at IS NULL OR typeof(submitted_at) = 'integer'))",
    "CHECK (length(key_fingerprint) = 64 AND key_fingerprint NOT GLOB '*[^0-9a-f]*')",
    'CHECK (robot_index BETWEEN 0 AND 2147483647)',
    'CHECK (take >= 0)',
    "CHECK (source IN ('thisWallet', 'pasted', 'unrecorded'))",
    "CHECK (kind IS NULL OR kind IN ('invoice', 'address'))",
    // A mark of a contract under way before schema 9 says nothing of a payout; a payout given since says what it was and when. Each part is true or false, never `NULL`, which a CHECK would let pass.
    "CHECK ((source = 'unrecorded' AND kind IS NULL AND submitted_at IS NULL) OR (source <> 'unrecorded' AND kind IS NOT NULL AND submitted_at IS NOT NULL))",
    'CHECK (submitted_at IS NULL OR submitted_at BETWEEN 0 AND 253402300799999999)',
    'FOREIGN KEY (key_fingerprint, robot_index) REFERENCES trades (key_fingerprint, robot_index)',
  ];
}

/// What the maker asked, for each order this device made (schema 8, #176; design note `docs/design/phase-3-making-an-order.md` § 3.2, § 3.5): `MakerTermsRecord` column for column, written once with the pending make, before the make's request leaves, and never changed nor deleted.
///
/// One row per trade, keyed as `trades` is (a foreign key to it); it names no order, which does not exist yet when it is written.
/// It holds the order as the maker asked it, the description and the meeting point included, which the coordinator holds and shows anyway; whether the order has a password, never the password nor its hash.
/// The triggers of `maker_terms.drift` refuse any update, any delete, a second insert (`INSERT OR REPLACE` included) and terms of anything but a pending make of the same network, coordinator and role, whatever the code that writes.
/// Read and written only by `TradeTrailRepositoryImpl`.
@DataClassName('MakerTermsRow')
class StoredMakerTerms extends Table {
  @override
  String get tableName => 'maker_terms';

  /// The trade's robot, as `trades` keys it.
  TextColumn get keyFingerprint => text()();
  IntColumn get robotIndex => integer()();

  /// `MakerTermsRecord.version`.
  IntColumn get version => integer()();

  /// The make the terms belong to, which must be the pending make of the row of `trades` they are keyed by: `RobosatsNetwork.name`, the coordinator's short alias, `TradeRole.name`.
  TextColumn get network => text()();
  TextColumn get coordinatorAlias => text()();
  TextColumn get role => text()();

  /// `OrderType.wire`: 0 buy, 1 sell.
  IntColumn get orderType => integer()();
  IntColumn get currencyId => integer()();

  /// The fixed amount, or the bounds of a range, in the order's currency: one or the other.
  RealColumn get amount => real().nullable()();
  RealColumn get minAmount => real().nullable()();
  RealColumn get maxAmount => real().nullable()();

  RealColumn get premiumPercent => real()();

  /// The payment methods as sent, one text.
  TextColumn get paymentMethod => text()();
  RealColumn get bondSizePercent => real()();

  /// The public duration and the escrow duration asked, in seconds.
  IntColumn get publicSeconds => integer()();
  IntColumn get escrowSeconds => integer()();

  /// The description sent, or absent.
  TextColumn get description => text().nullable()();

  /// Whether the order was sent with a password: never the password nor its hash.
  BoolColumn get hasPassword => boolean()();

  /// The meeting point sent, both coordinates or none.
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();

  /// The coordinator's price of a bitcoin in the order's currency, read from `/api/limits/` just before the make.
  RealColumn get createdPrice => real()();

  /// The maker fee of `/api/info/`, read just before the make.
  RealColumn get makerFee => real()();

  @override
  Set<Column<Object>> get primaryKey => {keyFingerprint, robotIndex};

  @override
  List<String> get customConstraints => const [
    // The storage class of each column this code writes, as for the terms of a take; the real numbers have theirs in their own CHECKs.
    "CHECK (typeof(key_fingerprint) = 'text' AND typeof(robot_index) = 'integer' AND typeof(version) = 'integer' AND typeof(network) = 'text' AND typeof(coordinator_alias) = 'text' AND typeof(role) = 'text' AND typeof(order_type) = 'integer' AND typeof(currency_id) = 'integer' AND typeof(payment_method) = 'text' AND typeof(public_seconds) = 'integer' AND typeof(escrow_seconds) = 'integer' AND (description IS NULL OR typeof(description) = 'text') AND typeof(has_password) = 'integer')",
    "CHECK (length(key_fingerprint) = 64 AND key_fingerprint NOT GLOB '*[^0-9a-f]*')",
    'CHECK (robot_index BETWEEN 0 AND 2147483647)',
    'CHECK (version >= 1)',
    "CHECK (network IN ('mainnet', 'testnet'))",
    // A text the code writes holds no NUL, which would end it early for `length` (SQLite counts characters up to the first NUL): searched in its bytes, the file being UTF-8, where only U+0000 has a 0 byte (security review of #176). With no NUL, `length` counts code points, as `MakeOrderRequest.tryCreate` does.
    "CHECK (instr(CAST(coordinator_alias AS BLOB), X'00') = 0 AND length(coordinator_alias) > 0)",
    "CHECK (role IN ('buyer', 'seller'))",
    // Making a buy order makes a buyer, making a sell order a seller: the opposite of a take.
    "CHECK ((order_type = 0 AND role = 'buyer') OR (order_type = 1 AND role = 'seller'))",
    'CHECK (currency_id > 0)',
    // A fixed amount, or a range within the coordinator's nominal ratios, 1.5 to 15, compared as `MakeOrderRequest.tryCreate` compares the same doubles; each amount above 0 and below 10^10 (`MakeOrderRequest.amountLimit`), written out, since drift's snapshot reads an exponent as 0.
    "CHECK ((amount IS NOT NULL AND min_amount IS NULL AND max_amount IS NULL AND typeof(amount) = 'real' AND amount > 0 AND amount < 10000000000) OR (amount IS NULL AND min_amount IS NOT NULL AND max_amount IS NOT NULL AND typeof(min_amount) = 'real' AND typeof(max_amount) = 'real' AND min_amount > 0 AND max_amount < 10000000000 AND min_amount <= max_amount / 1.5 AND min_amount >= max_amount / 15))",
    // The bounds of `MakeOrderRequest.tryCreate`: a premium above -100 and at most 999, a payment method of 1 to 70 code points, a bond of 2 to 15 %, a public duration of 600 to 86,400 s, an escrow duration of 1,800 to 36,000 s, a description of 1 to 240 code points, neither with a NUL.
    "CHECK (typeof(premium_percent) = 'real' AND premium_percent > -100 AND premium_percent <= 999)",
    "CHECK (instr(CAST(payment_method AS BLOB), X'00') = 0 AND length(payment_method) BETWEEN 1 AND 70)",
    "CHECK (typeof(bond_size_percent) = 'real' AND bond_size_percent BETWEEN 2 AND 15)",
    'CHECK (public_seconds BETWEEN 600 AND 86400)',
    'CHECK (escrow_seconds BETWEEN 1800 AND 36000)',
    "CHECK (description IS NULL OR (instr(CAST(description AS BLOB), X'00') = 0 AND length(description) BETWEEN 1 AND 240))",
    // The meeting point: both coordinates or none, within the coordinator's bounds (`api/models/order.py:148-168`).
    "CHECK ((latitude IS NULL AND longitude IS NULL) OR (latitude IS NOT NULL AND longitude IS NOT NULL AND typeof(latitude) = 'real' AND typeof(longitude) = 'real' AND latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180))",
    "CHECK (typeof(created_price) = 'real' AND created_price > 0 AND created_price < 1000000000000000)",
    // The maker fee, refused above 1 % as the taker fee is.
    "CHECK (typeof(maker_fee) = 'real' AND maker_fee BETWEEN 0 AND 0.01)",
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

/// The Garage Keys of the wallet's words this device activated, per network (schema 10, #81; design note `docs/design/garage-key-from-the-words.md` § 2): the index of each and the `GarageKeyFingerprint` of the key the words gave there when it was activated, never the key, which the words give again.
///
/// Indexes go up one by one from 0 (`derived_garage_keys_in_order`), and a row is never changed nor deleted: « New internal Garage Key » activates the index after the highest, and the trades of every key finish with it, whichever key is selected (`selected_garage_keys`). A fingerprint is unique on its network, so two indexes never claim the same key.
@DataClassName('DerivedGarageKeyRow')
class DerivedGarageKeys extends Table {
  /// `mainnet` or `testnet`: the network step of the BIP85 path.
  TextColumn get network => text()();

  /// The index of the key, from 0: the last step of the BIP85 path.
  IntColumn get keyIndex => integer()();

  /// The `GarageKeyFingerprint` of the key, 64 lowercase hexadecimal characters.
  TextColumn get keyFingerprint => text()();

  /// When this device activated the key, in milliseconds since the epoch.
  IntColumn get activatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {network, keyIndex};

  @override
  List<String> get customConstraints => const [
    "CHECK (typeof(network) = 'text' AND typeof(key_index) = 'integer' AND typeof(key_fingerprint) = 'text' AND typeof(activated_at) = 'integer')",
    "CHECK (network IN ('mainnet', 'testnet'))",
    'CHECK (key_index BETWEEN 0 AND 2147483647)',
    "CHECK (length(key_fingerprint) = 64 AND key_fingerprint NOT GLOB '*[^0-9a-f]*')",
    'CHECK (activated_at BETWEEN 0 AND 8640000000000000)',
    'UNIQUE (network, key_fingerprint)',
  ];
}

/// The Garage Key the Garage Key card shows on each network, the key of every new trade there (schema 10, #81; decided on 2026-11-26): one row per network, kept across restarts, either an internal Garage Key (a key of the words) by its index or, with no index, the external Garage Key, the one the vault keeps in the slot of the network (drawn at random before #81, or imported); and the last internal Garage Key the card showed, where « Back to internal Garage Keys » returns.
@DataClassName('SelectedGarageKeyRow')
class SelectedGarageKeys extends Table {
  /// `mainnet` or `testnet`.
  TextColumn get network => text()();

  /// The index of the internal Garage Key selected, one of `derived_garage_keys` on that network; `NULL` for the external Garage Key.
  IntColumn get keyIndex => integer().nullable()();

  /// The index of the last internal Garage Key selected on that network, kept while the external Garage Key is: where « Back to internal Garage Keys » returns. `NULL` when none was selected yet (the highest is then taken).
  IntColumn get lastInternalIndex => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {network};

  @override
  List<String> get customConstraints => const [
    "CHECK (typeof(network) = 'text' AND (key_index IS NULL OR typeof(key_index) = 'integer') AND (last_internal_index IS NULL OR typeof(last_internal_index) = 'integer'))",
    "CHECK (network IN ('mainnet', 'testnet'))",
    'CHECK (key_index IS NULL OR key_index BETWEEN 0 AND 2147483647)',
    'CHECK (last_internal_index IS NULL OR last_internal_index BETWEEN 0 AND 2147483647)',
    'CHECK (key_index IS NULL OR last_internal_index = key_index)',
  ];
}

/// The notices of the Garage shown once on this device (schema 10, #81; decided on 2026-11-26): `externalKeyNamed`, « Your Garage Keys », made due by the step to schema 10 (an update, never a new file), shown at the first opening of a Garage whose vault kept a key from before #81 (that key is named « External Garage Key » from then on), and turned shown without a word at a first opening without one; never again. A row only turns shown.
@DataClassName('GarageNoticeRow')
class GarageNotices extends Table {
  /// The notice: `externalKeyNamed` only.
  TextColumn get notice => text()();

  /// `0` while the notice is due, `1` once it was shown.
  IntColumn get shown => integer()();

  @override
  Set<Column<Object>> get primaryKey => {notice};

  @override
  List<String> get customConstraints => const [
    "CHECK (typeof(notice) = 'text' AND typeof(shown) = 'integer')",
    "CHECK (notice IN ('externalKeyNamed'))",
    'CHECK (shown IN (0, 1))',
  ];
}
