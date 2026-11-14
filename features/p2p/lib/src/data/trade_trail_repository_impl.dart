import 'dart:async';

import 'package:drift/drift.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../domain/garage_key_fingerprint.dart';
import '../domain/p2p_failure.dart';
import '../domain/repositories/trade_trail_repository.dart';
import '../domain/robot_binding.dart';
import '../domain/trade/trade_storable.dart';
import '../domain/trade_record.dart';
import 'p2p_database.dart';

/// The terms and the trail of each trade, in the feature's database (schema 4, #87).
///
/// Each write is one statement, which SQLite runs atomically: the terms are inserted once; a first trail is inserted once; a later trail replaces the stored one only while it is still the one [TradeTrailRecord.whyNotReplace] was asked about, every column compared in the statement's `WHERE`, so a write that lost a race to another writes nothing.
/// The triggers of `trade_trails.drift` refuse, whatever the code, any update or delete of the terms, a second insert of either, terms or a trail of no open trade or of another trade, any delete of a trail, and any update of a trail that goes back (its trade, version, read, breach, history, pinned hashes, pre-take, or an end left); an update of the trail of a closed trade is ignored.
/// This class is the only writer of both tables (`robot_bindings_architecture_test.dart`), and opens no transaction.
/// It returns no row of the database: the records only, and a [P2pStorageFailure] for any [Exception] the database or the directory the shell gave throws; an [Error] is a bug (AGENTS.md, rule 11) and is not caught.
final class TradeTrailRepositoryImpl implements TradeTrailRepository {
  /// The terms of one trade, written once: a second insert writes nothing (the trigger `trade_terms_inserted_once`), so the row comes back only when this call wrote it.
  static const String _recordTermsSql =
      'INSERT INTO trade_terms (key_fingerprint, robot_index, version, '
      'network, coordinator_alias, order_id, role, order_type, currency_id, '
      'amount, is_range, premium_percent, explicit_satoshis, '
      'bond_size_percent, escrow_seconds, book_price, taker_fee) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING '
      'RETURNING robot_index';

  /// The first trail of one trade: a second insert writes nothing (the trigger `trade_trails_inserted_once`), so the row comes back only when this call wrote it.
  static const String _insertTrailSql =
      'INSERT INTO trade_trails (key_fingerprint, robot_index, version, '
      'network, coordinator_alias, order_id, role, position, read_at, '
      'bond_hash, escrow_hash, deadline, bond_step_seen_at, '
      'bond_step_deadline, breached, history_unknown) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING '
      'RETURNING robot_index';

  /// A later trail of one trade, only while the stored one is, column for column, the one compared: the row comes back only when this call wrote it.
  ///
  /// The trade's own columns (network, coordinator, order, role) are compared and never set: they never change.
  static const String _replaceTrailSql =
      'UPDATE trade_trails SET version = ?, position = ?, read_at = ?, '
      'bond_hash = ?, escrow_hash = ?, deadline = ?, bond_step_seen_at = ?, '
      'bond_step_deadline = ?, breached = ?, history_unknown = ? '
      'WHERE key_fingerprint = ? AND robot_index = ? AND version IS ? '
      'AND network IS ? AND coordinator_alias IS ? AND order_id IS ? '
      'AND role IS ? AND position IS ? AND read_at IS ? AND bond_hash IS ? '
      'AND escrow_hash IS ? AND deadline IS ? AND bond_step_seen_at IS ? '
      'AND bond_step_deadline IS ? AND breached IS ? AND history_unknown IS ? '
      'RETURNING robot_index';

  /// The columns of the terms and of the trail, each named after its table.
  static const String _columns =
      'trade_terms.key_fingerprint AS terms_key_fingerprint, '
      'trade_terms.robot_index AS terms_robot_index, '
      'trade_terms.version AS terms_version, '
      'trade_terms.network AS terms_network, '
      'trade_terms.coordinator_alias AS terms_coordinator_alias, '
      'trade_terms.order_id AS terms_order_id, '
      'trade_terms.role AS terms_role, '
      'trade_terms.order_type AS terms_order_type, '
      'trade_terms.currency_id AS terms_currency_id, '
      'trade_terms.amount AS terms_amount, '
      'trade_terms.is_range AS terms_is_range, '
      'trade_terms.premium_percent AS terms_premium_percent, '
      'trade_terms.explicit_satoshis AS terms_explicit_satoshis, '
      'trade_terms.bond_size_percent AS terms_bond_size_percent, '
      'trade_terms.escrow_seconds AS terms_escrow_seconds, '
      'trade_terms.book_price AS terms_book_price, '
      'trade_terms.taker_fee AS terms_taker_fee, '
      'trade_trails.key_fingerprint AS trail_key_fingerprint, '
      'trade_trails.version AS trail_version, '
      'trade_trails.network AS trail_network, '
      'trade_trails.coordinator_alias AS trail_coordinator_alias, '
      'trade_trails.order_id AS trail_order_id, '
      'trade_trails.role AS trail_role, '
      'trade_trails.position AS trail_position, '
      'trade_trails.read_at AS trail_read_at, '
      'trade_trails.bond_hash AS trail_bond_hash, '
      'trade_trails.escrow_hash AS trail_escrow_hash, '
      'trade_trails.deadline AS trail_deadline, '
      'trade_trails.bond_step_seen_at AS trail_bond_step_seen_at, '
      'trade_trails.bond_step_deadline AS trail_bond_step_deadline, '
      'trade_trails.breached AS trail_breached, '
      'trade_trails.history_unknown AS trail_history_unknown';

  /// The terms and the trail of one robot's trade, in one statement that always gives one row: the columns of each absent when there is none.
  static const String _historySql =
      'SELECT $_columns FROM (SELECT 1) '
      'LEFT JOIN trade_terms ON trade_terms.key_fingerprint = ? '
      'AND trade_terms.robot_index = ? '
      'LEFT JOIN trade_trails ON trade_trails.key_fingerprint = ? '
      'AND trade_trails.robot_index = ?';

  /// The terms and the trails of one network: a trail is never written without its terms (the trigger `trade_trails_of_their_trade`).
  static const String _historiesSql =
      'SELECT $_columns FROM trade_terms '
      'LEFT JOIN trade_trails ON trade_trails.key_fingerprint = '
      'trade_terms.key_fingerprint AND trade_trails.robot_index = '
      'trade_terms.robot_index WHERE trade_terms.network = ? '
      'ORDER BY trade_terms.key_fingerprint, trade_terms.robot_index';

  final P2pDatabase _database;

  const TradeTrailRepositoryImpl(this._database);

  @override
  Future<Result<void, P2pFailure>> recordTerms(
    TradeRecord trade,
    TradeTermsRecord terms,
  ) async {
    final List<QueryRow> written;
    try {
      written = await _database.customWriteReturning(
        _recordTermsSql,
        variables: [
          ..._robotVariables(trade.robot),
          Variable.withInt(terms.version),
          Variable.withString(terms.network),
          Variable.withString(terms.coordinatorAlias),
          Variable.withInt(terms.orderId),
          Variable.withString(terms.role),
          Variable.withInt(terms.type),
          Variable.withInt(terms.currencyId),
          Variable.withReal(terms.amount),
          Variable.withBool(terms.isRange),
          Variable.withReal(terms.premiumPercent),
          Variable<int>(terms.explicitSatoshis),
          Variable.withReal(terms.bondSizePercent),
          Variable.withInt(terms.escrowSeconds),
          Variable.withReal(terms.bookPrice),
          Variable.withReal(terms.takerFee),
        ],
        updates: {_database.storedTradeTerms},
        updateKind: UpdateKind.insert,
      );
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    // Written by this call, or already there: the terms are set once.
    return written.isEmpty
        ? const Err(TradeAlreadyRecordedFailure())
        : const Ok(null);
  }

  @override
  Future<Result<TrailStoreOutcome, P2pFailure>> storeTrail(
    TradeRecord trade,
    TradeTrailRecord trail,
  ) async {
    final TradeTrailRecord? stored;
    switch (await historyOf(trade)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: StoredTradeHistory(unreadable: true)):
        return const Err(P2pStorageFailure());
      case Ok(:final value):
        stored = value.trail;
    }
    if (stored != null) {
      // Always asked first: a trail that may not replace the stored one is never sent to the database.
      if (trail.whyNotReplace(stored) case final reason?) {
        return Ok(TrailKept(stored, reason: reason));
      }
    }
    final List<QueryRow> written;
    try {
      written = stored == null
          ? await _database.customWriteReturning(
              _insertTrailSql,
              variables: [
                ..._robotVariables(trade.robot),
                Variable.withInt(trail.version),
                Variable.withString(trail.network),
                Variable.withString(trail.coordinatorAlias),
                Variable.withInt(trail.orderId),
                Variable.withString(trail.role),
                ..._trailVariables(trail),
              ],
              updates: {_database.storedTradeTrails},
              updateKind: UpdateKind.insert,
            )
          : await _database.customWriteReturning(
              _replaceTrailSql,
              variables: [
                Variable.withInt(trail.version),
                ..._trailVariables(trail),
                ..._robotVariables(trade.robot),
                Variable.withInt(stored.version),
                Variable.withString(stored.network),
                Variable.withString(stored.coordinatorAlias),
                Variable.withInt(stored.orderId),
                Variable.withString(stored.role),
                ..._trailVariables(stored),
              ],
              updates: {_database.storedTradeTrails},
              updateKind: UpdateKind.update,
            );
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    if (written.isNotEmpty) return Ok(TrailStored(trail));
    // Another write came first, or the trade was closed meanwhile: what is stored now wins.
    return switch (await historyOf(trade)) {
      Ok(value: StoredTradeHistory(trail: final now?, unreadable: false)) => Ok(
        TrailKept(now, reason: null),
      ),
      Ok() => const Err(P2pStorageFailure()),
      Err(:final failure) => Err(failure),
    };
  }

  @override
  Future<Result<StoredTradeHistory, P2pFailure>> historyOf(
    TradeRecord trade,
  ) async {
    final QueryRow row;
    try {
      row = await _database
          .customSelect(
            _historySql,
            variables: [
              ..._robotVariables(trade.robot),
              ..._robotVariables(trade.robot),
            ],
            readsFrom: {
              _database.storedTradeTerms,
              _database.storedTradeTrails,
            },
          )
          .getSingle();
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    return Ok(_historyFrom(row.data));
  }

  @override
  Stream<Result<Map<RobotSlot, StoredTradeHistory>, P2pFailure>> watchHistories(
    RobosatsNetwork network,
  ) => _database
      .customSelect(
        _historiesSql,
        variables: [Variable.withString(network.name)],
        readsFrom: {_database.storedTradeTerms, _database.storedTradeTrails},
      )
      .watch()
      .transform(
        StreamTransformer<
          List<QueryRow>,
          Result<Map<RobotSlot, StoredTradeHistory>, P2pFailure>
        >.fromHandlers(
          handleData: (rows, sink) {
            final histories = <RobotSlot, StoredTradeHistory>{};
            for (final row in rows) {
              final data = row.data;
              final key = switch (data['terms_key_fingerprint']) {
                final String hex => GarageKeyFingerprint.stored(hex),
                _ => null,
              };
              final index = data['terms_robot_index'];
              if (key == null || index is! int) {
                sink.add(const Err(P2pStorageFailure()));
                return;
              }
              histories[RobotSlot(network, key, index)] = _historyFrom(data);
            }
            sink.add(Ok(Map.unmodifiable(histories)));
          },
          handleError: (error, stackTrace, sink) {
            if (error is Exception) {
              sink.add(const Err(P2pStorageFailure()));
            } else {
              sink.addError(error, stackTrace);
            }
          },
        ),
      );

  /// The robot's key fingerprint and index, as the tables key a trade.
  static List<Variable<Object>> _robotVariables(RobotSlot robot) => [
    Variable.withString(robot.keyFingerprint.hex),
    Variable.withInt(robot.accountIndex),
  ];

  /// The columns of [trail] that change from one read to the next, in the order of the statements.
  static List<Variable<Object>> _trailVariables(TradeTrailRecord trail) => [
    Variable.withString(trail.position),
    Variable.withInt(trail.readAtMicros),
    Variable<String>(trail.bondHash),
    Variable<String>(trail.escrowHash),
    Variable<int>(trail.deadlineMicros),
    Variable<int>(trail.bondStepSeenAtMicros),
    Variable<int>(trail.bondStepDeadlineMicros),
    Variable.withBool(trail.breached),
    Variable.withBool(trail.historyUnknown),
  ];

  /// What the columns of [data] hold of a trade's terms and trail, named `terms_` and `trail_` then their column.
  static StoredTradeHistory _historyFrom(Map<String, Object?> data) {
    final termsPresent = data['terms_key_fingerprint'] != null;
    final trailPresent = data['trail_key_fingerprint'] != null;
    final terms = termsPresent ? _termsFrom(data) : null;
    final trail = trailPresent ? _trailFrom(data) : null;
    return StoredTradeHistory(
      terms: terms,
      trail: trail,
      unreadable:
          (termsPresent && terms == null) || (trailPresent && trail == null),
    );
  }

  /// The terms the columns `terms_…` of [data] hold, or `null` for values of another type than this code writes.
  static TradeTermsRecord? _termsFrom(Map<String, Object?> data) {
    Object? column(String name) => data['terms_$name'];
    if ((
          column('version'),
          column('network'),
          column('coordinator_alias'),
          column('order_id'),
          column('role'),
          column('order_type'),
          column('currency_id'),
          column('amount'),
          _boolFrom(column('is_range')),
          column('premium_percent'),
          column('explicit_satoshis'),
          column('bond_size_percent'),
          column('escrow_seconds'),
          column('book_price'),
          column('taker_fee'),
        )
        case (
          final int version,
          final String network,
          final String alias,
          final int orderId,
          final String role,
          final int type,
          final int currencyId,
          final double amount,
          final bool isRange,
          final double premium,
          final int? explicit,
          final double bondSize,
          final int escrowSeconds,
          final double bookPrice,
          final double takerFee,
        )) {
      return TradeTermsRecord(
        version: version,
        network: network,
        coordinatorAlias: alias,
        orderId: orderId,
        role: role,
        type: type,
        currencyId: currencyId,
        amount: amount,
        isRange: isRange,
        premiumPercent: premium,
        explicitSatoshis: explicit,
        bondSizePercent: bondSize,
        escrowSeconds: escrowSeconds,
        bookPrice: bookPrice,
        takerFee: takerFee,
      );
    }
    return null;
  }

  /// The trail the columns `trail_…` of [data] hold, or `null` for values of another type than this code writes.
  static TradeTrailRecord? _trailFrom(Map<String, Object?> data) {
    Object? column(String name) => data['trail_$name'];
    if ((
          column('version'),
          column('network'),
          column('coordinator_alias'),
          column('order_id'),
          column('role'),
          column('position'),
          column('read_at'),
          column('bond_hash'),
          column('escrow_hash'),
          column('deadline'),
          column('bond_step_seen_at'),
          column('bond_step_deadline'),
          _boolFrom(column('breached')),
          _boolFrom(column('history_unknown')),
        )
        case (
          final int version,
          final String network,
          final String alias,
          final int orderId,
          final String role,
          final String position,
          final int readAt,
          final String? bondHash,
          final String? escrowHash,
          final int? deadline,
          final int? bondStepSeenAt,
          final int? bondStepDeadline,
          final bool breached,
          final bool historyUnknown,
        )) {
      return TradeTrailRecord(
        version: version,
        network: network,
        coordinatorAlias: alias,
        orderId: orderId,
        role: role,
        position: position,
        readAtMicros: readAt,
        bondHash: bondHash,
        escrowHash: escrowHash,
        deadlineMicros: deadline,
        bondStepSeenAtMicros: bondStepSeenAt,
        bondStepDeadlineMicros: bondStepDeadline,
        breached: breached,
        historyUnknown: historyUnknown,
      );
    }
    return null;
  }

  /// A boolean as SQLite stores it, or the value itself when it is not one.
  static Object? _boolFrom(Object? value) => switch (value) {
    0 => false,
    1 => true,
    _ => value,
  };
}
