import 'package:drift/drift.dart';
import 'package:primitives/primitives.dart';

import '../domain/p2p_failure.dart';
import '../domain/repositories/trade_payout_repository.dart';
import '../domain/robot_binding.dart';
import '../domain/trade/payout_trace.dart';
import '../domain/trade_record.dart';
import 'p2p_database.dart';

/// The payouts a buyer gave from this device, per trade and contract, in the feature's database (schema 9, #204).
///
/// Each write is one statement, which SQLite runs atomically. The triggers of `trade_payouts.drift` refuse, whatever the code, any delete, a second insert of a trade's contract, a record of no open trade of a buyer or of a contract its trail is not at, the mark `unrecorded`, and any update that changes a record's trade or contract, turns it into a mark, or moves its time back.
/// This class is the only writer of the table, and opens no transaction.
/// It returns no row of the database: the records only, and a [P2pStorageFailure] for any [Exception] the database throws; an [Error] is a bug (AGENTS.md, rule 11) and is not caught.
final class TradePayoutRepositoryImpl implements TradePayoutRepository {
  /// A later payout of a contract already recorded (or marked `unrecorded` by the step to schema 9): the row comes back only when this call wrote it.
  static const String _replaceSql =
      'UPDATE trade_payouts SET source = ?, kind = ?, payment_hash = ?, '
      'submitted_at = ? '
      'WHERE key_fingerprint = ? AND robot_index = ? AND take = ? '
      'RETURNING robot_index';

  /// The first payout of a contract: a second insert writes nothing (the trigger `trade_payouts_inserted_once`), so the row comes back only when this call wrote it.
  static const String _insertSql =
      'INSERT INTO trade_payouts (key_fingerprint, robot_index, take, source, '
      'kind, payment_hash, submitted_at) VALUES (?, ?, ?, ?, ?, ?, ?) '
      'RETURNING robot_index';

  static const String _traceSql =
      'SELECT source, kind, submitted_at FROM trade_payouts '
      'WHERE key_fingerprint = ? AND robot_index = ? AND take = ?';

  final P2pDatabase _database;

  const TradePayoutRepositoryImpl(this._database);

  @override
  Future<Result<PayoutTrace, P2pFailure>> traceOf(
    TradeRecord trade, {
    required int take,
  }) async {
    final List<QueryRow> rows;
    try {
      rows = await _database
          .customSelect(
            _traceSql,
            variables: [
              ..._robotVariables(trade.robot),
              Variable.withInt(take),
            ],
            readsFrom: {_database.storedTradePayouts},
          )
          .get();
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    if (rows.isEmpty) return const Ok(PayoutNotGivenHere());
    final data = rows.single.data;
    final kind = PayoutTraceKind.values
        .where((value) => value.name == data['kind'])
        .firstOrNull;
    return switch ((data['source'], kind, data['submitted_at'])) {
      ('unrecorded', null, null) => const Ok(PayoutUnrecorded()),
      ('thisWallet', final kind?, final int at) => Ok(
        PayoutFromThisWallet(kind, _time(at)),
      ),
      ('pasted', final kind?, final int at) => Ok(
        PayoutPasted(kind, _time(at)),
      ),
      // A row this code never writes.
      _ => const Err(P2pStorageFailure()),
    };
  }

  @override
  Future<Result<bool, P2pFailure>> recordPayout(
    TradeRecord trade, {
    required int take,
    required PayoutTraceSource source,
    required PayoutTraceKind kind,
    required String? paymentHash,
    required DateTime at,
  }) async {
    final values = [
      Variable.withString(source.name),
      Variable.withString(kind.name),
      Variable<String>(paymentHash),
      Variable.withInt(at.toUtc().microsecondsSinceEpoch),
    ];
    final key = [..._robotVariables(trade.robot), Variable.withInt(take)];
    try {
      final replaced = await _database.customWriteReturning(
        _replaceSql,
        variables: [...values, ...key],
        updates: {_database.storedTradePayouts},
        updateKind: UpdateKind.update,
      );
      if (replaced.isNotEmpty) return const Ok(true);
      final inserted = await _database.customWriteReturning(
        _insertSql,
        variables: [...key, ...values],
        updates: {_database.storedTradePayouts},
        updateKind: UpdateKind.insert,
      );
      return Ok(inserted.isNotEmpty);
    } on Exception {
      // A closed trade, a seller's, or another contract than the trail's is refused by a trigger that aborts: nothing was written.
      return const Err(P2pStorageFailure());
    }
  }

  static DateTime _time(int micros) =>
      DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);

  /// The robot's key fingerprint and index, as the tables key a trade.
  static List<Variable<Object>> _robotVariables(RobotSlot robot) => [
    Variable.withString(robot.keyFingerprint.hex),
    Variable.withInt(robot.accountIndex),
  ];
}
