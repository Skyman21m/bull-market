import 'dart:async';

import 'package:drift/drift.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../domain/garage_key_fingerprint.dart';
import '../domain/order_history.dart' show ClosedTrade;
import '../domain/p2p_failure.dart';
import '../domain/repositories/trade_record_repository.dart';
import '../domain/robot_binding.dart';
import '../domain/trade/trade_edges.dart' show TradePosition;
import '../domain/trade/trade_storable.dart' show TradeTrailRecord;
import '../domain/trade_record.dart';
import 'p2p_database.dart';

/// The trade records of the robots, and the binding that reserves a robot for a new trade, in the feature's database.
///
/// Each write is one statement, which SQLite runs atomically, and reads in the same statement everything that decides it: the robot's binding and record for [reserveForNewTrade], the robot's binding, its provenance and its record for a pending take or a pending make, the robot's binding and record for a recovered trade, the record's state for its changes.
/// So two connections, or two calls on one connection, never reserve one robot twice, record two trades of one robot, or move a closed record.
/// A pending take needs the [TradeReservation] that only [reserveForNewTrade] gives, when it wrote the robot's binding.
/// The primary key of `trades` (key fingerprint, robot index) refuses a second record of a robot, its foreign key a record of a robot without a binding on the record's network, and the triggers of `trades.drift` any update but the two times set once, any delete and a second insert of a robot (`INSERT OR REPLACE` included), whatever the code that writes.
/// The only SQL that changes a row is [_confirmSql], [_closeSql], [_confirmMakeSql] and [_closePendingMakeSql], on `trades`; nothing deletes a row, and nothing changes a binding (`robot_bindings_architecture_test.dart`).
/// No write may run inside a transaction, since a rollback would undo it after it answered success: nothing in the feature opens one (`robot_bindings_architecture_test.dart`).
/// It returns no row of the database: the domain types only, and a [P2pStorageFailure] for any [Exception] the database or the directory the shell gave throws, and for a row this code never writes.
/// An [Error] is a bug (AGENTS.md, rule 11) and is not caught.
final class TradeRecordRepositoryImpl implements TradeRecordRepository {
  static const String _generated = 'generated';

  /// The indexes of the key bound or recorded with a trade, joined with commas, in one statement that always gives one row.
  static const String _newTradeStandingSql =
      'SELECT (SELECT group_concat(robot_index) FROM (SELECT robot_index FROM robot_bindings '
      'WHERE key_fingerprint = ? UNION SELECT robot_index FROM trades '
      'WHERE key_fingerprint = ?)) AS in_use';

  /// Binds a robot for a new trade, only when its index has no binding and no trade, whatever the history of its key (decided on 2026-11-26, #81), with the provenance `generated` a reservation always writes; it returns the index only when it wrote the binding.
  ///
  /// So a binding made for a new trade is `generated`, and only such a binding, or one of a key drawn here, may take a pending take or make: a robot bound by « Select Host » after « Robots from elsewhere » (`acknowledged`) never does.
  /// The `WHERE` keeps SQLite from reading `ON CONFLICT` as a join constraint.
  static const String _reserveSql =
      'INSERT INTO robot_bindings (network, key_fingerprint, robot_index, '
      'coordinator_alias, coordinator_onion, coordinator_node_keys, '
      'coordinator_nostr_key, bound_at, provenance) '
      'SELECT ?, ?, ?, ?, ?, ?, ?, ?, ? '
      'WHERE NOT EXISTS (SELECT 1 FROM trades '
      'WHERE key_fingerprint = ? AND robot_index = ?) '
      'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING '
      'RETURNING robot_index';

  /// Records a pending take of a robot bound to that very coordinator on the reservation's network for a new trade (provenance `generated`), copying the network and the coordinator from the binding; it returns the row only when it wrote it.
  static const String _recordPendingTakeSql =
      'INSERT INTO trades (network, key_fingerprint, robot_index, '
      'coordinator_alias, coordinator_onion, order_id, role, origin, '
      'taken_at, confirmed_at, closed_at) '
      "SELECT network, key_fingerprint, robot_index, coordinator_alias, "
      "coordinator_onion, ?, ?, 'takenHere', ?, NULL, NULL "
      'FROM robot_bindings WHERE key_fingerprint = ? AND robot_index = ? '
      'AND network = ? AND provenance = ? AND coordinator_alias = ? '
      'AND coordinator_onion = ? AND coordinator_node_keys = ? '
      'AND coordinator_nostr_key = ? '
      'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING '
      'RETURNING *';

  /// Records a recovered trade, confirmed at once, of a robot bound to that very coordinator on the robot's network, whatever the provenance of its binding, copying the network and the coordinator from the binding; it returns the row only when it wrote it.
  static const String _recordRecoveredTradeSql =
      'INSERT INTO trades (network, key_fingerprint, robot_index, '
      'coordinator_alias, coordinator_onion, order_id, role, origin, '
      'taken_at, confirmed_at, closed_at) '
      "SELECT network, key_fingerprint, robot_index, coordinator_alias, "
      "coordinator_onion, ?, ?, 'recovered', ?, ?, NULL "
      'FROM robot_bindings WHERE key_fingerprint = ? AND robot_index = ? '
      'AND network = ? AND coordinator_alias = ? '
      'AND coordinator_onion = ? AND coordinator_node_keys = ? '
      'AND coordinator_nostr_key = ? '
      'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING '
      'RETURNING *';

  /// Records a pending make, with no order id (schema 8, #176), of a robot bound to that very coordinator on the reservation's network for a new trade (provenance `generated`), copying the network and the coordinator from the binding; it returns the row only when it wrote it.
  static const String _recordPendingMakeSql =
      'INSERT INTO trades (network, key_fingerprint, robot_index, '
      'coordinator_alias, coordinator_onion, order_id, role, origin, '
      'taken_at, confirmed_at, closed_at) '
      "SELECT network, key_fingerprint, robot_index, coordinator_alias, "
      "coordinator_onion, NULL, ?, 'madeHere', ?, NULL, NULL "
      'FROM robot_bindings WHERE key_fingerprint = ? AND robot_index = ? '
      'AND network = ? AND provenance = ? AND coordinator_alias = ? '
      'AND coordinator_onion = ? AND coordinator_node_keys = ? '
      'AND coordinator_nostr_key = ? '
      'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING '
      'RETURNING *';

  /// Confirms a pending make with its order id: only the record of that robot and network, of origin `madeHere`, with no order id, neither confirmed nor closed, changes; the triggers refuse it unless the maker's terms are recorded and no other open trade of the coordinator holds the order.
  static const String _confirmMakeSql =
      'UPDATE trades SET order_id = ?, confirmed_at = ? WHERE key_fingerprint = ? '
      "AND robot_index = ? AND network = ? AND origin = 'madeHere' "
      'AND order_id IS NULL AND confirmed_at IS NULL AND closed_at IS NULL';

  /// Closes a pending make that did not happen: only the record of that robot and network, of origin `madeHere`, with no order id, not closed yet, changes.
  static const String _closePendingMakeSql =
      'UPDATE trades SET closed_at = ? WHERE key_fingerprint = ? '
      "AND robot_index = ? AND network = ? AND origin = 'madeHere' "
      'AND order_id IS NULL AND closed_at IS NULL';

  /// Confirms a pending take: only the record of that robot, network, order and origin, neither confirmed nor closed, changes.
  static const String _confirmSql =
      'UPDATE trades SET confirmed_at = ? WHERE key_fingerprint = ? '
      'AND robot_index = ? AND network = ? AND order_id = ? AND origin = ? '
      'AND confirmed_at IS NULL AND closed_at IS NULL';

  /// Closes a record: only the record of that robot, network, order and origin, not closed yet, changes.
  static const String _closeSql =
      'UPDATE trades SET closed_at = ? WHERE key_fingerprint = ? '
      'AND robot_index = ? AND network = ? AND order_id = ? AND origin = ? '
      'AND closed_at IS NULL';

  /// The record of one robot, and the binding of its index, in one statement that always gives one row: the columns of each absent when there is none.
  static const String _robotSql =
      'SELECT trades.network AS trade_network, '
      'trades.key_fingerprint AS trade_key_fingerprint, '
      'trades.robot_index AS trade_robot_index, '
      'trades.coordinator_alias AS trade_coordinator_alias, '
      'trades.coordinator_onion AS trade_coordinator_onion, '
      'trades.order_id AS trade_order_id, trades.role AS trade_role, '
      'trades.origin AS trade_origin, trades.taken_at AS trade_taken_at, '
      'trades.confirmed_at AS trade_confirmed_at, '
      'trades.closed_at AS trade_closed_at, robot_bindings.* '
      'FROM (SELECT 1) LEFT JOIN trades ON trades.key_fingerprint = ? '
      'AND trades.robot_index = ? LEFT JOIN robot_bindings '
      'ON robot_bindings.key_fingerprint = ? '
      'AND robot_bindings.robot_index = ?';

  /// The active records of one network, oldest first: a pending make, which has no order id yet, is not one (schema 8).
  static const String _activeSql =
      'SELECT * FROM trades WHERE network = ? AND closed_at IS NULL '
      'AND order_id IS NOT NULL '
      'ORDER BY taken_at, key_fingerprint, robot_index';

  /// Every record of one network that has an order id, active or closed, oldest first (#216, #217): a pending make is not one.
  static const String _tradesSql =
      'SELECT * FROM trades WHERE network = ? AND order_id IS NOT NULL '
      'ORDER BY taken_at, key_fingerprint, robot_index';

  /// Every closed record of one network that has an order id, with the columns of its trail that say which order it is of and where it stopped, named `trail_` then their column, absent when no trail is stored (#253).
  static const String _closedSql =
      'SELECT trades.*, trade_trails.key_fingerprint AS trail_key_fingerprint, '
      'trade_trails.version AS trail_version, '
      'trade_trails.network AS trail_network, '
      'trade_trails.coordinator_alias AS trail_coordinator_alias, '
      'trade_trails.order_id AS trail_order_id, '
      'trade_trails.role AS trail_role, '
      'trade_trails.position AS trail_position '
      'FROM trades LEFT JOIN trade_trails '
      'ON trade_trails.key_fingerprint = trades.key_fingerprint '
      'AND trade_trails.robot_index = trades.robot_index '
      'WHERE trades.network = ? AND trades.order_id IS NOT NULL '
      'AND trades.closed_at IS NOT NULL '
      'ORDER BY trades.closed_at, trades.key_fingerprint, trades.robot_index';

  /// The pending makes of one network, oldest first.
  static const String _pendingMakesSql =
      "SELECT * FROM trades WHERE network = ? AND origin = 'madeHere' "
      'AND order_id IS NULL AND closed_at IS NULL '
      'ORDER BY taken_at, key_fingerprint, robot_index';

  final P2pDatabase _database;
  final DateTime Function() _clock;

  const TradeRecordRepositoryImpl(this._database, {required this._clock});

  @override
  Future<Result<NewTradeStanding, P2pFailure>> newTradeStandingOf(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) async {
    final QueryRow row;
    try {
      row = await _database
          .customSelect(
            _newTradeStandingSql,
            variables: [
              Variable.withString(key.hex),
              Variable.withString(key.hex),
            ],
            readsFrom: {_database.robotBindings, _database.trades},
          )
          .getSingle();
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    final inUse = switch (row.data['in_use']) {
      null => const <int>[],
      final String joined => _indexesFrom(joined),
      // One index alone may come back as a number.
      final int index => [index],
      _ => null,
    };
    if (inUse == null) return const Err(P2pStorageFailure());
    return Ok(NewTradeStanding(indexesInUse: inUse));
  }

  @override
  Future<Result<TradeReservation?, P2pFailure>> reserveForNewTrade(
    RobotSlot robot,
    CoordinatorIdentity coordinator,
  ) async {
    if (coordinator.network != robot.network) {
      return const Err(RobotNotForNewTradeFailure());
    }
    final network = _networkValue(robot.network);
    final fingerprint = robot.keyFingerprint.hex;
    try {
      final written = await _database.customWriteReturning(
        _reserveSql,
        variables: [
          Variable.withString(network),
          Variable.withString(fingerprint),
          Variable.withInt(robot.accountIndex),
          Variable.withString(coordinator.alias),
          Variable.withString(coordinator.onion),
          Variable.withString(coordinator.nodeKeys.join(',')),
          Variable.withString(coordinator.nostrKey),
          Variable.withInt(_clock().millisecondsSinceEpoch),
          Variable.withString(_generated),
          Variable.withString(fingerprint),
          Variable.withInt(robot.accountIndex),
        ],
        updates: {_database.robotBindings},
        updateKind: UpdateKind.insert,
      );
      // The statement returns the row only when it wrote it: this call bound the robot, and no other can.
      return Ok(written.isEmpty ? null : TradeReservation(robot, coordinator));
    } on Exception {
      return const Err(P2pStorageFailure());
    }
  }

  @override
  Future<Result<TradeRecord, P2pFailure>> recordPendingTake(
    TradeReservation reservation, {
    required int orderId,
    required TradeRole role,
  }) async {
    final robot = reservation.robot;
    final coordinator = reservation.coordinator;
    // The robot and the coordinator name one network, which the binding must have too.
    if (coordinator.network != robot.network) {
      return const Err(RobotNotForNewTradeFailure());
    }
    final fingerprint = robot.keyFingerprint.hex;
    final List<QueryRow> written;
    try {
      written = await _database.customWriteReturning(
        _recordPendingTakeSql,
        variables: [
          Variable.withInt(orderId),
          Variable.withString(_roleValue(role)),
          Variable.withInt(_clock().millisecondsSinceEpoch),
          Variable.withString(fingerprint),
          Variable.withInt(robot.accountIndex),
          Variable.withString(_networkValue(reservation.network)),
          Variable.withString(_generated),
          ..._coordinatorVariables(coordinator),
        ],
        updates: {_database.trades},
        updateKind: UpdateKind.insert,
      );
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    return _writtenOrWhyNot(written, robot, coordinator, newTrade: true);
  }

  @override
  Future<Result<TradeRecord, P2pFailure>> recordRecoveredTrade(
    RobotSlot robot,
    CoordinatorIdentity coordinator, {
    required int orderId,
    required TradeRole role,
  }) async {
    if (coordinator.network != robot.network) {
      return const Err(RobotBoundToAnotherCoordinatorFailure());
    }
    final fingerprint = robot.keyFingerprint.hex;
    final now = _clock().millisecondsSinceEpoch;
    final List<QueryRow> written;
    try {
      written = await _database.customWriteReturning(
        _recordRecoveredTradeSql,
        variables: [
          Variable.withInt(orderId),
          Variable.withString(_roleValue(role)),
          Variable.withInt(now),
          Variable.withInt(now),
          Variable.withString(fingerprint),
          Variable.withInt(robot.accountIndex),
          Variable.withString(_networkValue(robot.network)),
          ..._coordinatorVariables(coordinator),
        ],
        updates: {_database.trades},
        updateKind: UpdateKind.insert,
      );
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    return _writtenOrWhyNot(written, robot, coordinator, newTrade: false);
  }

  @override
  Future<Result<PendingMake, P2pFailure>> recordPendingMake(
    TradeReservation reservation, {
    required TradeRole role,
  }) async {
    final robot = reservation.robot;
    final coordinator = reservation.coordinator;
    // The robot and the coordinator name one network, which the binding must have too.
    if (coordinator.network != robot.network) {
      return const Err(RobotNotForNewTradeFailure());
    }
    final fingerprint = robot.keyFingerprint.hex;
    final List<QueryRow> written;
    try {
      written = await _database.customWriteReturning(
        _recordPendingMakeSql,
        variables: [
          Variable.withString(_roleValue(role)),
          Variable.withInt(_clock().millisecondsSinceEpoch),
          Variable.withString(fingerprint),
          Variable.withInt(robot.accountIndex),
          Variable.withString(_networkValue(reservation.network)),
          Variable.withString(_generated),
          ..._coordinatorVariables(coordinator),
        ],
        updates: {_database.trades},
        updateKind: UpdateKind.insert,
      );
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    if (written case [final row]) {
      return switch (_pendingMakeFrom(row.data, prefix: '')) {
        final make? => Ok(make),
        null => const Err(P2pStorageFailure()),
      };
    }
    // Nothing written: why is the pending take's why, which gives a failure whenever no row was written.
    return switch (await _writtenOrWhyNot(
      const [],
      robot,
      coordinator,
      newTrade: true,
    )) {
      Ok() => const Err(P2pStorageFailure()),
      Err(:final failure) => Err(failure),
    };
  }

  @override
  Future<Result<TradeRecord, P2pFailure>> confirmMake(
    PendingMake make, {
    required int orderId,
  }) async {
    final fingerprint = make.robot.keyFingerprint.hex;
    final QueryRow row;
    try {
      await _database.customUpdate(
        _confirmMakeSql,
        variables: [
          Variable.withInt(orderId),
          Variable.withInt(_clock().millisecondsSinceEpoch),
          Variable.withString(fingerprint),
          Variable.withInt(make.robot.accountIndex),
          Variable.withString(_networkValue(make.network)),
        ],
        updates: {_database.trades},
        updateKind: UpdateKind.update,
      );
      row = await _robotRow(make.robot);
    } on Exception {
      // The triggers refuse an order id without the maker's terms, and one that another open trade of the coordinator holds.
      return const Err(P2pStorageFailure());
    }
    switch (_recordFrom(row.data, prefix: 'trade_')) {
      case final stored?
          when stored.robot == make.robot &&
              stored.origin == TradeOrigin.madeHere:
        // A make closed since its confirmation is a closed trade; one confirmed with another order is not the make asked.
        if (stored.closedAt != null) return const Err(TradeClosedFailure());
        if (stored.orderId != orderId) return const Err(P2pStorageFailure());
        return Ok(stored);
      case _:
        // Still without an order: closed as not made, or a make the database does not hold as given.
        return switch (_pendingMakeFrom(row.data, prefix: 'trade_')) {
          PendingMake(:final robot, closedAt: _?) when robot == make.robot =>
            const Err(TradeClosedFailure()),
          _ => const Err(P2pStorageFailure()),
        };
    }
  }

  @override
  Future<Result<PendingMake, P2pFailure>> closePendingMake(
    PendingMake make,
  ) async {
    final fingerprint = make.robot.keyFingerprint.hex;
    final QueryRow row;
    try {
      await _database.customUpdate(
        _closePendingMakeSql,
        variables: [
          Variable.withInt(_clock().millisecondsSinceEpoch),
          Variable.withString(fingerprint),
          Variable.withInt(make.robot.accountIndex),
          Variable.withString(_networkValue(make.network)),
        ],
        updates: {_database.trades},
        updateKind: UpdateKind.update,
      );
      row = await _robotRow(make.robot);
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    return switch (_pendingMakeFrom(row.data, prefix: 'trade_')) {
      final stored?
          when stored.robot == make.robot &&
              stored.coordinatorAlias == make.coordinatorAlias =>
        Ok(stored),
      // Confirmed meanwhile, which a close never undoes, or a make the database does not hold as given.
      _ => const Err(P2pStorageFailure()),
    };
  }

  @override
  Stream<Result<List<PendingMake>, P2pFailure>> watchPendingMakes(
    RobosatsNetwork network,
  ) => _database
      .customSelect(
        _pendingMakesSql,
        variables: [Variable.withString(_networkValue(network))],
        readsFrom: {_database.trades},
      )
      .watch()
      .transform(
        StreamTransformer<
          List<QueryRow>,
          Result<List<PendingMake>, P2pFailure>
        >.fromHandlers(
          handleData: (rows, sink) {
            final makes = <PendingMake>[];
            for (final row in rows) {
              switch (_pendingMakeFrom(row.data, prefix: '')) {
                case final make?:
                  makes.add(make);
                case null:
                  sink.add(const Err(P2pStorageFailure()));
                  return;
              }
            }
            sink.add(Ok(List.unmodifiable(makes)));
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

  @override
  Future<Result<TradeRecord, P2pFailure>> confirmTake(
    TradeRecord record,
  ) async {
    switch (await _change(_confirmSql, record)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: final stored):
        // A record closed, before or since, never turns taken.
        if (stored.closedAt != null) return const Err(TradeClosedFailure());
        return Ok(stored);
    }
  }

  @override
  Future<Result<TradeRecord, P2pFailure>> closeTrade(TradeRecord record) =>
      _change(_closeSql, record);

  @override
  Stream<Result<List<TradeRecord>, P2pFailure>> watchActiveTrades(
    RobosatsNetwork network,
  ) => _watchRecords(_activeSql, network);

  @override
  Stream<Result<List<TradeRecord>, P2pFailure>> watchTrades(
    RobosatsNetwork network,
  ) => _watchRecords(_tradesSql, network);

  @override
  Stream<Result<List<ClosedTrade>, P2pFailure>> watchClosedTrades(
    RobosatsNetwork network,
  ) => _database
      .customSelect(
        _closedSql,
        variables: [Variable.withString(_networkValue(network))],
        readsFrom: {_database.trades, _database.storedTradeTrails},
      )
      .watch()
      .transform(
        StreamTransformer<
          List<QueryRow>,
          Result<List<ClosedTrade>, P2pFailure>
        >.fromHandlers(
          handleData: (rows, sink) {
            final closed = <ClosedTrade>[];
            for (final row in rows) {
              switch (_recordFrom(row.data, prefix: '')) {
                case final record?:
                  closed.add(
                    ClosedTrade(record, _lastPositionFrom(row.data, record)),
                  );
                case null:
                  sink.add(const Err(P2pStorageFailure()));
                  return;
              }
            }
            sink.add(Ok(List.unmodifiable(closed)));
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

  /// The position of the trail the columns `trail_…` of [data] hold, when it is the trail of [record]'s order as this code writes it: its version, network, coordinator, order and role those of the record, its position one of [TradePosition]; `null` for no trail and for any other.
  static TradePosition? _lastPositionFrom(
    Map<String, Object?> data,
    TradeRecord record,
  ) {
    Object? column(String name) => data['trail_$name'];
    if ((
          column('key_fingerprint'),
          column('version'),
          column('network'),
          column('coordinator_alias'),
          column('order_id'),
          column('role'),
          column('position'),
        )
        case (
          String(),
          TradeTrailRecord.currentVersion,
          final String network,
          final String alias,
          final int orderId,
          final String role,
          final String position,
        )
        when network == _networkValue(record.network) &&
            alias == record.coordinatorAlias &&
            orderId == record.orderId &&
            role == record.role.name) {
      for (final value in TradePosition.values) {
        if (value.name == position) return value;
      }
    }
    return null;
  }

  /// The records [sql] selects on [network], each read back as [_recordFrom] reads it: a new list after each write of the records.
  Stream<Result<List<TradeRecord>, P2pFailure>> _watchRecords(
    String sql,
    RobosatsNetwork network,
  ) => _database
      .customSelect(
        sql,
        variables: [Variable.withString(_networkValue(network))],
        readsFrom: {_database.trades},
      )
      .watch()
      .transform(
        StreamTransformer<
          List<QueryRow>,
          Result<List<TradeRecord>, P2pFailure>
        >.fromHandlers(
          handleData: (rows, sink) {
            final records = <TradeRecord>[];
            for (final row in rows) {
              switch (_recordFrom(row.data, prefix: '')) {
                case final record?:
                  records.add(record);
                case null:
                  sink.add(const Err(P2pStorageFailure()));
                  return;
              }
            }
            sink.add(Ok(List.unmodifiable(records)));
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

  /// Runs [sql], one of the two changes of a record, for [record], then reads the record as stored: the change applies only in the state its `WHERE` names, so a call in any other state leaves the record as it is.
  Future<Result<TradeRecord, P2pFailure>> _change(
    String sql,
    TradeRecord record,
  ) async {
    final fingerprint = record.robot.keyFingerprint.hex;
    try {
      await _database.customUpdate(
        sql,
        variables: [
          Variable.withInt(_clock().millisecondsSinceEpoch),
          Variable.withString(fingerprint),
          Variable.withInt(record.robot.accountIndex),
          Variable.withString(_networkValue(record.network)),
          Variable.withInt(record.orderId),
          Variable.withString(_originValue(record.origin)),
        ],
        updates: {_database.trades},
        updateKind: UpdateKind.update,
      );
      final row = await _robotRow(record.robot);
      return switch (_recordFrom(row.data, prefix: 'trade_')) {
        // The record of that robot is the one asked: one robot has one trade, so another order or network here is a row this code never wrote.
        final stored?
            when stored.orderId == record.orderId &&
                stored.robot == record.robot &&
                stored.origin == record.origin =>
          Ok(stored),
        _ => const Err(P2pStorageFailure()),
      };
    } on Exception {
      return const Err(P2pStorageFailure());
    }
  }

  /// The record [written] holds, or why a write of a trade of [robot] on [coordinator] wrote none: the robot already has a record, has no binding, is bound to another coordinator or to one that changed, or, for a new trade, is not bound for one.
  Future<Result<TradeRecord, P2pFailure>> _writtenOrWhyNot(
    List<QueryRow> written,
    RobotSlot robot,
    CoordinatorIdentity coordinator, {
    required bool newTrade,
  }) async {
    if (written case [final row]) {
      return switch (_recordFrom(row.data, prefix: '')) {
        final record? => Ok(record),
        null => const Err(P2pStorageFailure()),
      };
    }
    final QueryRow row;
    try {
      row = await _robotRow(robot);
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    final data = row.data;
    if (data['trade_key_fingerprint'] != null) {
      return const Err(TradeAlreadyRecordedFailure());
    }
    if (data['key_fingerprint'] == null) {
      return Err(
        newTrade
            ? const RobotNotForNewTradeFailure()
            : const RobotNotBoundFailure(),
      );
    }
    final binding = _bindingFrom(data);
    if (binding == null) return const Err(P2pStorageFailure());
    if (binding.admits(coordinator) case Err(:final failure)) {
      return Err(failure);
    }
    if (!newTrade) {
      // Bound to that coordinator, with no record, and still not written: a write that another connection's record beat, read here as gone (it is never deleted), which this code does not explain.
      return const Err(P2pStorageFailure());
    }
    return const Err(RobotNotForNewTradeFailure());
  }

  /// The row of [_robotSql] for [robot].
  Future<QueryRow> _robotRow(RobotSlot robot) {
    final fingerprint = robot.keyFingerprint.hex;
    return _database
        .customSelect(
          _robotSql,
          variables: [
            Variable.withString(fingerprint),
            Variable.withInt(robot.accountIndex),
            Variable.withString(fingerprint),
            Variable.withInt(robot.accountIndex),
          ],
          readsFrom: {_database.trades, _database.robotBindings},
        )
        .getSingle();
  }

  /// The indexes of [joined], numbers joined with commas, or `null` for a text that is not.
  static List<int>? _indexesFrom(String joined) {
    final indexes = <int>[];
    for (final text in joined.split(',')) {
      final index = int.tryParse(text);
      if (index == null) return null;
      indexes.add(index);
    }
    return indexes;
  }

  /// The variables of a coordinator in the statements that write a trade: its alias, onion address, node keys and Nostr key, as a binding stores them.
  static List<Variable<Object>> _coordinatorVariables(
    CoordinatorIdentity coordinator,
  ) => [
    Variable.withString(coordinator.alias),
    Variable.withString(coordinator.onion),
    Variable.withString(coordinator.nodeKeys.join(',')),
    Variable.withString(coordinator.nostrKey),
  ];

  /// The largest distance from the epoch a `DateTime` holds, in milliseconds.
  static const int _maxMilliseconds = 8640000000000000;

  /// Whether [value] is absent or a time this code writes, from the epoch to the last a `DateTime` holds, and that time.
  static (bool, DateTime?) _timeFrom(Object? value) => switch (value) {
    null => (true, null),
    final int milliseconds
        when milliseconds >= 0 && milliseconds <= _maxMilliseconds =>
      (true, DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true)),
    _ => (false, null),
  };

  /// The record the columns of a row of `trades` make, each named [prefix] then its column, or `null` for a row this code never writes: a value of another type, a NULL the schema forbids, a network, role or origin outside the constraints, a time no `DateTime` holds, or a state the statements never make.
  static TradeRecord? _recordFrom(
    Map<String, Object?> data, {
    required String prefix,
  }) {
    Object? column(String name) => data['$prefix$name'];
    if ((
          column('network'),
          column('key_fingerprint'),
          column('robot_index'),
          column('coordinator_alias'),
          column('coordinator_onion'),
          column('order_id'),
          column('role'),
          column('origin'),
          column('taken_at'),
        )
        case (
          final String network,
          final String fingerprint,
          final int index,
          final String alias,
          final String onion,
          final int orderId,
          final String role,
          final String origin,
          final int takenAt,
        )) {
      final tradeNetwork = _networkFrom(network);
      final key = GarageKeyFingerprint.stored(fingerprint);
      final tradeRole = switch (role) {
        'buyer' => TradeRole.buyer,
        'seller' => TradeRole.seller,
        _ => null,
      };
      final tradeOrigin = _originFrom(origin);
      final (takenValid, taken) = _timeFrom(takenAt);
      final (confirmedValid, confirmed) = _timeFrom(column('confirmed_at'));
      final (closedValid, closed) = _timeFrom(column('closed_at'));
      if (tradeNetwork == null ||
          key == null ||
          tradeRole == null ||
          tradeOrigin == null ||
          taken == null ||
          !takenValid ||
          !confirmedValid ||
          !closedValid ||
          index < 0 ||
          index > 2147483647 ||
          orderId <= 0 ||
          (tradeOrigin != TradeOrigin.takenHere && confirmed == null)) {
        return null;
      }
      return TradeRecord(
        robot: RobotSlot(tradeNetwork, key, index),
        coordinatorAlias: alias,
        coordinatorOnion: onion,
        orderId: orderId,
        role: tradeRole,
        origin: tradeOrigin,
        takenAt: taken,
        confirmedAt: confirmed,
        closedAt: closed,
      );
    }
    return null;
  }

  /// The pending make the columns of a row of `trades` make, each named [prefix] then its column, or `null` for any other row: a trade with an order id, one not made here, a confirmed one, or a row this code never writes.
  static PendingMake? _pendingMakeFrom(
    Map<String, Object?> data, {
    required String prefix,
  }) {
    Object? column(String name) => data['$prefix$name'];
    if ((
          column('network'),
          column('key_fingerprint'),
          column('robot_index'),
          column('coordinator_alias'),
          column('coordinator_onion'),
          column('order_id'),
          column('role'),
          column('origin'),
          column('taken_at'),
          column('confirmed_at'),
        )
        case (
          final String network,
          final String fingerprint,
          final int index,
          final String alias,
          final String onion,
          null,
          final String role,
          'madeHere',
          final int takenAt,
          null,
        )) {
      final makeNetwork = _networkFrom(network);
      final key = GarageKeyFingerprint.stored(fingerprint);
      final makeRole = switch (role) {
        'buyer' => TradeRole.buyer,
        'seller' => TradeRole.seller,
        _ => null,
      };
      final (_, written) = _timeFrom(takenAt);
      final (closedValid, closed) = _timeFrom(column('closed_at'));
      if (makeNetwork == null ||
          key == null ||
          makeRole == null ||
          written == null ||
          !closedValid ||
          index < 0 ||
          index > 2147483647) {
        return null;
      }
      return PendingMake(
        robot: RobotSlot(makeNetwork, key, index),
        coordinatorAlias: alias,
        coordinatorOnion: onion,
        role: makeRole,
        writtenAt: written,
        closedAt: closed,
      );
    }
    return null;
  }

  /// The binding the columns of `robot_bindings` in [data] make, or `null` for a value this code never writes.
  static RobotBinding? _bindingFrom(Map<String, Object?> data) {
    if (data case {
      'network': final String network,
      'coordinator_alias': final String alias,
      'coordinator_onion': final String onion,
      'coordinator_node_keys': final String nodeKeys,
      'coordinator_nostr_key': final String nostrKey,
      'bound_at': final int boundAt,
      'provenance': final String provenance,
    }) {
      final coordinatorNetwork = _networkFrom(network);
      final bindingProvenance = switch (provenance) {
        _generated => BindingProvenance.drawnHere,
        'acknowledged' => BindingProvenance.acknowledged,
        _ => null,
      };
      final (boundValid, bound) = _timeFrom(boundAt);
      if (coordinatorNetwork == null ||
          bindingProvenance == null ||
          !boundValid ||
          bound == null) {
        return null;
      }
      return RobotBinding(
        CoordinatorIdentity(
          network: coordinatorNetwork,
          alias: alias,
          onion: onion,
          nodeKeys: nodeKeys.split(',').where((key) => key.isNotEmpty),
          nostrKey: nostrKey,
        ),
        bound,
        bindingProvenance,
      );
    }
    return null;
  }

  /// The network a row stores, or `null` for a value this code never writes.
  static RobosatsNetwork? _networkFrom(String value) {
    for (final network in RobosatsNetwork.values) {
      if (_networkValue(network) == value) return network;
    }
    return null;
  }

  /// The network as the database stores it; a new network does not compile without a decision.
  static String _networkValue(RobosatsNetwork network) => switch (network) {
    RobosatsNetwork.mainnet => 'mainnet',
    RobosatsNetwork.testnet => 'testnet',
  };

  /// The origin as the database stores it.
  static String _originValue(TradeOrigin origin) => switch (origin) {
    TradeOrigin.takenHere => 'takenHere',
    TradeOrigin.madeHere => 'madeHere',
    TradeOrigin.recovered => 'recovered',
  };

  /// The origin a row stores, or `null` for a value this code never writes.
  static TradeOrigin? _originFrom(String value) {
    for (final origin in TradeOrigin.values) {
      if (_originValue(origin) == value) return origin;
    }
    return null;
  }

  /// The side as the database stores it.
  static String _roleValue(TradeRole role) => switch (role) {
    TradeRole.buyer => 'buyer',
    TradeRole.seller => 'seller',
  };
}
