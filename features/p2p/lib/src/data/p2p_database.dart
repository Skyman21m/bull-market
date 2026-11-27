import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'p2p_database.steps.dart';
import 'p2p_tables.dart';

part 'p2p_database.g.dart';

/// The P2P feature's own database, `p2p.sqlite`, apart from the wallet's: the bindings of the robots, the history of the Garage Keys, the trades of the robots, the terms and trail of each trade (a make's terms apart, since schema 8), the payments of its invoices asked of the wallet, the payouts a buyer gave per contract (since schema 9), and the keys of the peer its chat pinned (the PGP public key with its fingerprints, and the Nostr keys); since schema 10 (#81), the Garage Keys of the wallet's words this device activated, by index and fingerprint, the key selected on each network (an internal Garage Key, or the external Garage Key the vault keeps) with the last internal one selected, and the Garage's notices shown once; since schema 11 (#81), what this device read of the RoboSats recovery note of each Garage Key on each network's relays (the floor of the key's new trades, and whether a reading had an answer).
///
/// It holds no secret, and lives where the shell says, which keeps it out of cloud backups.
/// Only the foreground composition of the app opens it: the WorkManager isolate is given no directory, so no background task opens or migrates it.
/// Every schema version a release ships stays a supported upgrade source; a change adds a version, an idempotent migration step and a schema snapshot (`make drift-migrations`).
/// From schema 8 on, a file is not opened by a version of the app older than its schema: drift refuses a file newer than the code it runs. Schema 8 is in APKs given out, with real trades: its snapshot and its steps never change.
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
    StoredMakerTerms,
    StoredTradePayouts,
    DerivedGarageKeys,
    SelectedGarageKeys,
    GarageNotices,
    StoredGarageRecoveryNotes,
  ],
  include: {
    'trades.drift',
    'trade_trails.drift',
    'trade_payments.drift',
    'trade_chat_pins.drift',
    'maker_terms.drift',
    'trade_payouts.drift',
    'garage_keys.drift',
    'garage_recovery_notes.drift',
  },
)
final class P2pDatabase extends _$P2pDatabase {
  static const int schema = 11;

  /// Turns on SQLite's foreign keys for the connection, which are off by default: a trade's robot must be bound.
  ///
  /// It runs at each opening, after any migration step, outside a transaction, where SQLite takes it.
  static const String _foreignKeysOn = 'PRAGMA foreign_keys = ON';

  /// The tables and the four statements of the rebuild of the payments in the step to schema 7 (#97), pinned as written by `robot_bindings_architecture_test.dart`: none names a binding.
  static const String _payments = 'trade_payments';
  static const String _paymentsCopy = 'trade_payments_of_schema6';
  static const String _dropPaymentsCopy =
      'DROP TABLE IF EXISTS trade_payments_of_schema6';
  static const String _copyPayments =
      'CREATE TABLE trade_payments_of_schema6 AS SELECT * FROM trade_payments';
  static const String _dropPayments = 'DROP TABLE trade_payments';
  static const String _restorePayments =
      'INSERT INTO trade_payments (key_fingerprint, robot_index, step, payment_hash, started_at, wallet_payment_id) '
      'SELECT key_fingerprint, robot_index, step, payment_hash, started_at, wallet_payment_id FROM trade_payments_of_schema6 AS copy '
      'WHERE NOT EXISTS (SELECT 1 FROM trade_payments WHERE trade_payments.key_fingerprint = copy.key_fingerprint AND trade_payments.robot_index = copy.robot_index AND trade_payments.step = copy.step)';

  /// The tables, their copies and the statements of the step to schema 8 (#176), pinned as written by `robot_bindings_architecture_test.dart`: none names a binding.
  ///
  /// The trades, their trails and their payments are rebuilt, each as the payments were in the step to schema 7: its rows copied aside, the table dropped (its triggers with it; a drop fires no trigger), made again, its rows copied back, each once, before any trigger of the step exists.
  /// Each copy keeps every column of its table at schema 7 and is dropped only at the very end, once the foreign keys of the file were checked.
  static const String _trades = 'trades';
  static const String _tradesCopy = 'trades_of_schema7';
  static const String _dropTradesCopy =
      'DROP TABLE IF EXISTS trades_of_schema7';
  static const String _copyTrades =
      'CREATE TABLE trades_of_schema7 AS SELECT * FROM trades';
  static const String _dropTrades = 'DROP TABLE trades';
  static const String _restoreTrades =
      'INSERT INTO trades (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at) '
      'SELECT network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at FROM trades_of_schema7 AS copy '
      'WHERE NOT EXISTS (SELECT 1 FROM trades WHERE trades.key_fingerprint = copy.key_fingerprint AND trades.robot_index = copy.robot_index)';
  static const String _trails = 'trade_trails';
  static const String _trailsCopy = 'trade_trails_of_schema7';
  static const String _dropTrailsCopy =
      'DROP TABLE IF EXISTS trade_trails_of_schema7';
  static const String _copyTrails =
      'CREATE TABLE trade_trails_of_schema7 AS SELECT * FROM trade_trails';
  static const String _dropTrails = 'DROP TABLE trade_trails';
  static const String _restoreTrails =
      'INSERT INTO trade_trails (key_fingerprint, robot_index, version, network, coordinator_alias, order_id, role, position, read_at, bond_hash, escrow_hash, deadline, bond_step_seen_at, bond_step_deadline, breached, history_unknown) '
      'SELECT key_fingerprint, robot_index, version, network, coordinator_alias, order_id, role, position, read_at, bond_hash, escrow_hash, deadline, bond_step_seen_at, bond_step_deadline, breached, history_unknown FROM trade_trails_of_schema7 AS copy '
      'WHERE NOT EXISTS (SELECT 1 FROM trade_trails WHERE trade_trails.key_fingerprint = copy.key_fingerprint AND trade_trails.robot_index = copy.robot_index)';
  static const String _paymentsOfSchema7 = 'trade_payments_of_schema7';
  static const String _dropPaymentsOfSchema7 =
      'DROP TABLE IF EXISTS trade_payments_of_schema7';
  static const String _copyPaymentsOfSchema7 =
      'CREATE TABLE trade_payments_of_schema7 AS SELECT * FROM trade_payments';
  static const String _restorePaymentsOfSchema7 =
      'INSERT INTO trade_payments (key_fingerprint, robot_index, step, payment_hash, started_at, wallet_payment_id, take) '
      'SELECT key_fingerprint, robot_index, step, payment_hash, started_at, wallet_payment_id, 0 FROM trade_payments_of_schema7 AS copy '
      'WHERE NOT EXISTS (SELECT 1 FROM trade_payments WHERE trade_payments.key_fingerprint = copy.key_fingerprint AND trade_payments.robot_index = copy.robot_index AND trade_payments.step = copy.step AND trade_payments.take = 0)';

  /// The triggers the step to schema 8 makes on the tables it rebuilds, each dropped before the triggers of its table are made again, and the one it replaces on a table it does not rebuild: drift makes a trigger only when none of its name exists (`CREATE TRIGGER IF NOT EXISTS`), which would keep an old one, and SQLite fires the triggers of one event newest first, so a table's triggers are made again together, in the order of a new file, at every run of the step (functional review of #176).
  static const String _dropTradesOneOpenPerOrder =
      'DROP TRIGGER IF EXISTS trades_one_open_per_order';
  static const String _dropTradesOneOpenPerOrderUpdate =
      'DROP TRIGGER IF EXISTS trades_one_open_per_order_update';
  static const String _dropTradesNeverDeleted =
      'DROP TRIGGER IF EXISTS trades_never_deleted';
  static const String _dropTradesSetOnce =
      'DROP TRIGGER IF EXISTS trades_set_once';
  static const String _dropTradesMadePending =
      'DROP TRIGGER IF EXISTS trades_made_pending';
  static const String _dropTradesInsertedOnce =
      'DROP TRIGGER IF EXISTS trades_inserted_once';
  static const String _dropTradeTrailsNeverDeleted =
      'DROP TRIGGER IF EXISTS trade_trails_never_deleted';
  static const String _dropTradeTrailsInsertedOnce =
      'DROP TRIGGER IF EXISTS trade_trails_inserted_once';
  static const String _dropTradeTrailsOfTheirTrade =
      'DROP TRIGGER IF EXISTS trade_trails_of_their_trade';
  static const String _dropTradeTrailsClosed =
      'DROP TRIGGER IF EXISTS trade_trails_closed';
  static const String _dropTradeTrailsForward =
      'DROP TRIGGER IF EXISTS trade_trails_forward';
  static const String _dropTradePaymentsNeverDeleted =
      'DROP TRIGGER IF EXISTS trade_payments_never_deleted';
  static const String _dropTradePaymentsInsertedOnce =
      'DROP TRIGGER IF EXISTS trade_payments_inserted_once';
  static const String _dropTradePaymentsOfTheirTrade =
      'DROP TRIGGER IF EXISTS trade_payments_of_their_trade';
  static const String _dropTradePaymentsForward =
      'DROP TRIGGER IF EXISTS trade_payments_forward';
  static const String _dropTradePaymentsHashOnce =
      'DROP TRIGGER IF EXISTS trade_payments_hash_once';
  static const String _dropTermsOfTheirTrade =
      'DROP TRIGGER IF EXISTS trade_terms_of_their_trade';

  /// The table, the triggers and the statement of the step to schema 9 (#204, #231, #233; design note `docs/design/phase-3-making-an-order.md` § 3.5 bis), pinned as written by `robot_bindings_architecture_test.dart`: none names a binding, and none changes or deletes a row of a table older than schema 9.
  ///
  /// The triggers of the new table of the payouts are dropped before its marks are written and made again after, in the order a new file has them, so that a step run again over a file it left writes them as the first run did.
  static const String _dropTradePayoutsNeverDeleted =
      'DROP TRIGGER IF EXISTS trade_payouts_never_deleted';
  static const String _dropTradePayoutsForward =
      'DROP TRIGGER IF EXISTS trade_payouts_forward';
  static const String _dropTradePayoutsOfTheirTrade =
      'DROP TRIGGER IF EXISTS trade_payouts_of_their_trade';
  static const String _dropTradePayoutsInsertedOnce =
      'DROP TRIGGER IF EXISTS trade_payouts_inserted_once';

  /// The marks of the contracts under way when the step to schema 9 runs: for every trail of a buyer at a position where the payout of its current contract may already have been given, a row `unrecorded` of that contract, unless one is there already. Schema 8 recorded no payout, so such a payout is unknown, never « given elsewhere ».
  static const String _markPayoutsUnrecorded =
      'INSERT INTO trade_payouts (key_fingerprint, robot_index, take, source, kind, submitted_at) '
      "SELECT key_fingerprint, robot_index, take, 'unrecorded', NULL, NULL FROM trade_trails AS trail "
      "WHERE role = 'buyer' AND position NOT IN ('start', 'makerBondStep', 'public', 'paused', 'bondStep', 'preTakeUnavailable', 'publicAgain', 'notAvailable') "
      'AND NOT EXISTS (SELECT 1 FROM trade_payouts WHERE trade_payouts.key_fingerprint = trail.key_fingerprint AND trade_payouts.robot_index = trail.robot_index AND trade_payouts.take = trail.take)';

  /// « Your Garage Keys » made due by the step to schema 10 (#81, decided on 2026-11-26): a file of schema 9 is an update, the one case where a Garage Key the vault kept is renamed the external Garage Key; a new file never has it due. Written once, in the step's own new table; a step run again leaves a notice shown as it is.
  static const String _externalKeyNamedDue =
      "INSERT INTO garage_notices (notice, shown) VALUES ('externalKeyNamed', 0) "
      'ON CONFLICT (notice) DO NOTHING';

  /// Whether the connection enforces foreign keys, which the step to schema 8 needs off to drop `trades` (and turns off when they are on: `beforeOpen` turns them on again after every step), and the rows that break a foreign key anywhere in the file, which it needs none of before it drops its copies.
  static const String _foreignKeys = 'PRAGMA foreign_keys';
  static const String _foreignKeysOff = 'PRAGMA foreign_keys = OFF';
  static const String _foreignKeyCheck = 'PRAGMA foreign_key_check';

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
        // The payments gain the seller's escrow (#97): `escrow` widens the CHECK of their step, which SQLite cannot change in place. The table is rebuilt: its rows copied aside, the table dropped (its four triggers with it; a drop fires no trigger), made again with the new CHECK, its rows copied back before its triggers exist (a payment of a trade closed since is kept, which the insert trigger would refuse), the copy dropped, then the triggers made again.
        // No transaction (the feature opens none, `robot_bindings_architecture_test.dart`): each part is one statement, and each is done only when the file needs it, so that a step that stopped after any of them runs again over the file it left; a row is copied back only when it is not there already.
        final payments = await _tableText(_payments);
        if (payments != null && !payments.contains("'escrow'")) {
          await customStatement(_dropPaymentsCopy);
          await customStatement(_copyPayments);
          await customStatement(_dropPayments);
        }
        if (await _tableText(_payments) == null) {
          await m.createTable(schema.tradePayments);
        }
        if (await _tableText(_paymentsCopy) != null) {
          await customStatement(_restorePayments);
          await customStatement(_dropPaymentsCopy);
        }
        await m.createTrigger(schema.tradePaymentsNeverDeleted);
        await m.createTrigger(schema.tradePaymentsInsertedOnce);
        await m.createTrigger(schema.tradePaymentsOfTheirTrade);
        await m.createTrigger(schema.tradePaymentsForward);
      },
      from7To8: (m, schema) async {
        // The maker (#176; design note `docs/design/phase-3-making-an-order.md` § 3.5): a pending make with no order id, the maker's positions and contracts in the trails, a payment per contract, and the maker's terms in a table of their own. SQLite cannot change a CHECK in place, so `trades`, `trade_trails` and `trade_payments` are rebuilt, as the payments were in the step to schema 7, `trades` first, since the others name it.
        // No transaction (the feature opens none): each part is one statement, done only when the file needs it, so that a step that stopped after any of them runs again over the file it left; a row is copied back only when it is not there already, and every copy is kept until the foreign keys of the file are checked.
        // `trades` is the parent of five tables: with the foreign keys on, its drop would run an implicit delete that their rows make fail. They are on only from `beforeOpen`, after every step, and off by default in the SQLite the app ships (`sqlite3_flutter_libs`, built without `SQLITE_DEFAULT_FOREIGN_KEYS`); a connection that has them on here turns them off, as SQLite's own procedure for a rebuild does, outside a transaction (drift opens none around a step), and the step changes nothing unless they read off afterwards.
        if (await _foreignKeysAreOn()) {
          await customStatement(_foreignKeysOff);
          if (await _foreignKeysAreOn()) {
            throw const P2pSchemaStepRefused('foreign keys on');
          }
        }
        final trades = await _tableText(_trades);
        if (trades != null && !trades.contains("'madeHere'")) {
          await customStatement(_dropTradesCopy);
          await customStatement(_copyTrades);
          await customStatement(_dropTrades);
        }
        if (await _tableText(_trades) == null) {
          await m.createTable(schema.trades);
        }
        if (await _tableText(_tradesCopy) != null) {
          await customStatement(_restoreTrades);
        }
        if (await _tableText(_trails) != null &&
            !await _hasColumn(_trails, 'take')) {
          await customStatement(_dropTrailsCopy);
          await customStatement(_copyTrails);
          await customStatement(_dropTrails);
        }
        if (await _tableText(_trails) == null) {
          await m.createTable(schema.tradeTrails);
        }
        if (await _tableText(_trailsCopy) != null) {
          await customStatement(_restoreTrails);
        }
        if (await _tableText(_payments) != null &&
            !await _hasColumn(_payments, 'take')) {
          await customStatement(_dropPaymentsOfSchema7);
          await customStatement(_copyPaymentsOfSchema7);
          await customStatement(_dropPayments);
        }
        if (await _tableText(_payments) == null) {
          await m.createTable(schema.tradePayments);
        }
        if (await _tableText(_paymentsOfSchema7) != null) {
          await customStatement(_restorePaymentsOfSchema7);
        }
        await m.createTable(schema.makerTerms);
        // Every row is back: the triggers of the rebuilt tables, and of `maker_terms`, made again, each table's in the order a new file has them, since SQLite fires the triggers of one event newest first and the order decides which refusal a write meets (`trades_inserted_once`, which writes nothing, before `trades_one_open_per_order`, which aborts: functional review of #176).
        // Each rebuilt table's triggers are all dropped first, whatever a run before left (a table already rebuilt may hold triggers made in another order, or older ones), then all made again in that order.
        await customStatement(_dropTradesOneOpenPerOrder);
        await customStatement(_dropTradesOneOpenPerOrderUpdate);
        await customStatement(_dropTradesNeverDeleted);
        await customStatement(_dropTradesSetOnce);
        await customStatement(_dropTradesMadePending);
        await customStatement(_dropTradesInsertedOnce);
        await m.createTrigger(schema.tradesOneOpenPerOrder);
        await m.createTrigger(schema.tradesOneOpenPerOrderUpdate);
        await m.createTrigger(schema.tradesNeverDeleted);
        await m.createTrigger(schema.tradesSetOnce);
        await m.createTrigger(schema.tradesMadePending);
        await m.createTrigger(schema.tradesInsertedOnce);
        await m.createTrigger(schema.makerTermsNeverDeleted);
        await m.createTrigger(schema.makerTermsSetOnce);
        await m.createTrigger(schema.makerTermsInsertedOnce);
        await m.createTrigger(schema.makerTermsOfTheirMake);
        // The one replaced trigger of a table the step does not rebuild, dropped first, since drift makes a trigger only when none of its name exists; made again, it is the last of its table, as in a new file.
        await customStatement(_dropTermsOfTheirTrade);
        await m.createTrigger(schema.tradeTermsOfTheirTrade);
        await customStatement(_dropTradeTrailsNeverDeleted);
        await customStatement(_dropTradeTrailsInsertedOnce);
        await customStatement(_dropTradeTrailsOfTheirTrade);
        await customStatement(_dropTradeTrailsClosed);
        await customStatement(_dropTradeTrailsForward);
        await m.createTrigger(schema.tradeTrailsNeverDeleted);
        await m.createTrigger(schema.tradeTrailsInsertedOnce);
        await m.createTrigger(schema.tradeTrailsOfTheirTrade);
        await m.createTrigger(schema.tradeTrailsClosed);
        await m.createTrigger(schema.tradeTrailsForward);
        await customStatement(_dropTradePaymentsNeverDeleted);
        await customStatement(_dropTradePaymentsInsertedOnce);
        await customStatement(_dropTradePaymentsOfTheirTrade);
        await customStatement(_dropTradePaymentsForward);
        await customStatement(_dropTradePaymentsHashOnce);
        await m.createTrigger(schema.tradePaymentsNeverDeleted);
        await m.createTrigger(schema.tradePaymentsInsertedOnce);
        await m.createTrigger(schema.tradePaymentsOfTheirTrade);
        await m.createTrigger(schema.tradePaymentsForward);
        await m.createTrigger(schema.tradePaymentsHashOnce);
        // A row whose parent is missing stops the step here, at every opening, its copies kept: the version stays 7 and the P2P records unreadable, rather than a file of schema 8 with orphan rows.
        if (await _breaksAForeignKey()) {
          throw const P2pSchemaStepRefused('foreign key check');
        }
        await customStatement(_dropTradesCopy);
        await customStatement(_dropTrailsCopy);
        await customStatement(_dropPaymentsOfSchema7);
      },
      from8To9: (m, schema) async {
        // What each payment took out of the wallet (#233), where the payout of each contract came from (#204), and a trace of terms shown otherwise (#231): design note `docs/design/phase-3-making-an-order.md` § 3.5 bis. Schema 8 is frozen: no table is rebuilt, no trigger of it replaced, no row of it copied, changed or deleted; four columns are added in place, each with its constraints as its own, one table and five triggers are new.
        // No transaction (the feature opens none): each part is one statement, done only when the file needs it, so that a step that stopped after any of them runs again over the file it left. No table is dropped, so the foreign keys stay as they are.
        if (!await _hasColumn(_payments, 'confirmed_sats')) {
          await m.addColumn(
            schema.tradePayments,
            schema.tradePayments.confirmedSats,
          );
        }
        if (!await _hasColumn(_trails, 'terms_changed_at')) {
          await m.addColumn(
            schema.tradeTrails,
            schema.tradeTrails.termsChangedAt,
          );
        }
        if (!await _hasColumn(_trails, 'terms_changed_premium_low')) {
          await m.addColumn(
            schema.tradeTrails,
            schema.tradeTrails.termsChangedPremiumLow,
          );
        }
        if (!await _hasColumn(_trails, 'terms_changed_premium_high')) {
          await m.addColumn(
            schema.tradeTrails,
            schema.tradeTrails.termsChangedPremiumHigh,
          );
        }
        await m.createTable(schema.tradePayouts);
        // The marks of the contracts under way, each written once, while no trigger of the payouts exists: those of a run before are dropped first, then all made again, in the order a new file has them.
        await customStatement(_dropTradePayoutsNeverDeleted);
        await customStatement(_dropTradePayoutsForward);
        await customStatement(_dropTradePayoutsOfTheirTrade);
        await customStatement(_dropTradePayoutsInsertedOnce);
        await customStatement(_markPayoutsUnrecorded);
        await m.createTrigger(schema.tradePayoutsNeverDeleted);
        await m.createTrigger(schema.tradePayoutsForward);
        await m.createTrigger(schema.tradePayoutsOfTheirTrade);
        await m.createTrigger(schema.tradePayoutsInsertedOnce);
        // The new triggers of two tables the step does not rebuild, each the newest of its table, as in a new file; made only when missing.
        await m.createTrigger(schema.tradeTrailsTermsTrace);
        await m.createTrigger(schema.tradePaymentsSatsKnown);
        await m.createTrigger(schema.tradePaymentsSatsForward);
      },
      from9To10: (m, schema) async {
        // The Garage Keys of the words (#81, design note `docs/design/garage-key-from-the-words.md` § 2): the keys this device activated and their triggers, the key selected per network, and the Garage's notices shown once with their triggers, each made only when missing, so that a step that stopped after any of them runs again over the file it left; then « Your Garage Keys » made due, the one row the step writes, in its own new table. No row of an older table is copied, changed or deleted: the records of the key the vault keeps, the external Garage Key since #81, stay as they are, under its fingerprint.
        await m.createTable(schema.derivedGarageKeys);
        await m.createTable(schema.selectedGarageKeys);
        await m.createTrigger(schema.derivedGarageKeysNeverDeleted);
        await m.createTrigger(schema.derivedGarageKeysNeverChanged);
        await m.createTrigger(schema.derivedGarageKeysInOrder);
        await m.createTrigger(schema.derivedGarageKeysInsertedOnce);
        await m.createTable(schema.garageNotices);
        await m.createTrigger(schema.garageNoticesShownOnce);
        await m.createTrigger(schema.garageNoticesNeverDeleted);
        await customStatement(_externalKeyNamedDue);
      },
      from10To11: (m, schema) async {
        // What this device read of the RoboSats recovery notes (#81, design note `docs/design/garage-key-from-the-words.md` § 3, « As PR 3 built it »): one new table and its two triggers, each made only when missing, so that a step that stopped after any of them runs again over the file it left. The step writes no row: no row of an older table is copied, changed or deleted, and every key is read on the relays at its next visit, its robots used before the update being in the bindings and the records already.
        await m.createTable(schema.garageRecoveryNotes);
        await m.createTrigger(schema.garageRecoveryNotesNeverDeleted);
        await m.createTrigger(schema.garageRecoveryNotesForward);
      },
    ),
    // Every connection, the app's and the tests', enforces the foreign key of the trades.
    beforeOpen: (details) => customStatement(_foreignKeysOn),
  );

  /// SQLite's own text of the table [table], `null` when the file has no such table.
  Future<String?> _tableText(String table) async {
    final row = await customSelect(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(table)],
    ).getSingleOrNull();
    return row?.read<String>('sql');
  }

  /// Whether [table] has a column named [column], read from SQLite's own description of the table.
  Future<bool> _hasColumn(String table, String column) async =>
      (await customSelect(
        'SELECT 1 FROM pragma_table_info(?) WHERE name = ?',
        variables: [Variable.withString(table), Variable.withString(column)],
      ).get()).isNotEmpty;

  /// Whether the connection enforces foreign keys: anything but SQLite's `0` counts as on.
  Future<bool> _foreignKeysAreOn() async =>
      (await customSelect(_foreignKeys).getSingle()).data.values.single != 0;

  /// Whether a row of the file breaks a foreign key: SQLite gives one row per such row, of any table.
  Future<bool> _breaksAForeignKey() async =>
      (await customSelect(_foreignKeyCheck).get()).isNotEmpty;
}

/// A step of the schema that would have left the file wrong and stopped before (schema 8, #176): the foreign keys on before `trades` is dropped, or a row that breaks a foreign key once every row is back.
///
/// Thrown by the step, so drift does not write the new version and the next opening runs the step again; an [Exception] of the data layer, which the repositories turn into a `P2pStorageFailure`, as for any database that cannot be opened.
/// It holds no row and no value of the file, only which check stopped the step.
final class P2pSchemaStepRefused implements Exception {
  /// Which check stopped the step.
  final String check;

  const P2pSchemaStepRefused(this.check);

  @override
  String toString() => 'P2pSchemaStepRefused($check)';
}
