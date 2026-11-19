import 'package:drift/drift.dart';
import 'package:primitives/primitives.dart';

import '../domain/p2p_failure.dart';
import '../domain/repositories/trade_payment_repository.dart';
import '../domain/robot_binding.dart';
import '../domain/trade/trade_status.dart';
import '../domain/trade/trade_payment.dart';
import '../domain/trade_record.dart';
import 'p2p_database.dart';

/// The payments of a trade's invoices asked of the wallet, in the feature's database (schema 5, #100).
///
/// Each write is one statement, which SQLite runs atomically. The triggers of `trade_payments.drift` refuse, whatever the code, any delete, a second insert of a trade's step and contract, a payment of no open trade, of a trade never read or of a contract its trail is not at, a payment hash another payment holds, and any update that changes a payment's trade, step, contract or hash or moves its start back.
/// This class is the only writer of the table, and opens no transaction.
/// It returns no row of the database: the records only, and a [P2pStorageFailure] for any [Exception] the database throws; an [Error] is a bug (AGENTS.md, rule 11) and is not caught.
final class TradePaymentRepositoryImpl implements TradePaymentRepository {
  /// A new attempt of the payment already recorded for this invoice: its start moved forward, the earlier attempt's id kept until the wallet gives a new one (a payment that may have moved funds is never forgotten); whether or not its trade is still open (the use case pays only from a status it has just read and stored, so an open trade); the row comes back only when it is this invoice's.
  static const String _restartSql =
      'UPDATE trade_payments SET started_at = max(started_at, ?) '
      'WHERE key_fingerprint = ? AND robot_index = ? AND step = ? '
      'AND take = ? AND payment_hash = ? '
      'RETURNING robot_index';

  /// The first attempt of a trade's step and contract: a second insert writes nothing (the trigger `trade_payments_inserted_once`), nor one of a closed or unread trade, of a contract the trail is not at, or of a payment hash another payment holds (`trade_payments_of_their_trade` and `trade_payments_hash_once` abort it), so the row comes back only when this call wrote it.
  static const String _startSql =
      'INSERT INTO trade_payments (key_fingerprint, robot_index, step, take, '
      'payment_hash, started_at, wallet_payment_id) '
      'VALUES (?, ?, ?, ?, ?, ?, NULL) '
      'RETURNING robot_index';

  /// The wallet's id of the payment of this invoice.
  static const String _walletPaymentSql =
      'UPDATE trade_payments SET wallet_payment_id = ? '
      'WHERE key_fingerprint = ? AND robot_index = ? AND step = ? '
      'AND take = ? AND payment_hash = ? '
      'RETURNING robot_index';

  static const String _paymentSql =
      'SELECT payment_hash, started_at, wallet_payment_id FROM trade_payments '
      'WHERE key_fingerprint = ? AND robot_index = ? AND step = ? AND take = ?';

  /// Every payment of a trade, by contract then step.
  static const String _paymentsSql =
      'SELECT step, take, payment_hash, started_at, wallet_payment_id '
      'FROM trade_payments WHERE key_fingerprint = ? AND robot_index = ? '
      'ORDER BY take, step';

  final P2pDatabase _database;

  const TradePaymentRepositoryImpl(this._database);

  @override
  Future<Result<List<TradePaymentRecord>, P2pFailure>> paymentsOfTrade(
    TradeRecord trade,
  ) async {
    final List<QueryRow> rows;
    try {
      rows = await _database
          .customSelect(
            _paymentsSql,
            variables: _robotVariables(trade.robot),
            readsFrom: {_database.storedTradePayments},
          )
          .get();
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    final payments = <TradePaymentRecord>[];
    for (final row in rows) {
      final data = row.data;
      final step = InvoiceStep.values
          .where((value) => value.name == data['step'])
          .firstOrNull;
      switch ((
        step,
        data['take'],
        data['payment_hash'],
        data['started_at'],
        data['wallet_payment_id'],
      )) {
        case (
          final step?,
          final int take,
          final String hash,
          final int startedAt,
          final String? id,
        ):
          payments.add(
            TradePaymentRecord(
              step: step,
              paymentHash: hash,
              startedAt: DateTime.fromMicrosecondsSinceEpoch(
                startedAt,
                isUtc: true,
              ),
              walletPaymentId: id,
              take: take,
            ),
          );
        // A row this code never writes.
        case _:
          return const Err(P2pStorageFailure());
      }
    }
    return Ok(List.unmodifiable(payments));
  }

  @override
  Future<Result<TradePaymentRecord?, P2pFailure>> paymentOf(
    TradeRecord trade,
    InvoiceStep step, {
    int take = 0,
  }) async {
    final List<QueryRow> rows;
    try {
      rows = await _database
          .customSelect(
            _paymentSql,
            variables: [
              ..._robotVariables(trade.robot),
              Variable.withString(step.name),
              Variable.withInt(take),
            ],
            readsFrom: {_database.storedTradePayments},
          )
          .get();
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    if (rows.isEmpty) return const Ok(null);
    final data = rows.single.data;
    return switch ((
      data['payment_hash'],
      data['started_at'],
      data['wallet_payment_id'],
    )) {
      (final String hash, final int startedAt, final String? id) => Ok(
        TradePaymentRecord(
          step: step,
          paymentHash: hash,
          startedAt: DateTime.fromMicrosecondsSinceEpoch(
            startedAt,
            isUtc: true,
          ),
          walletPaymentId: id,
          take: take,
        ),
      ),
      // A row this code never writes.
      _ => const Err(P2pStorageFailure()),
    };
  }

  @override
  Future<Result<bool, P2pFailure>> recordStart(
    TradeRecord trade,
    InvoiceStep step, {
    required String paymentHash,
    required DateTime at,
    int take = 0,
  }) async {
    final key = [
      ..._robotVariables(trade.robot),
      Variable.withString(step.name),
      Variable.withInt(take),
      Variable.withString(paymentHash),
    ];
    try {
      final restarted = await _database.customWriteReturning(
        _restartSql,
        variables: [Variable.withInt(at.microsecondsSinceEpoch), ...key],
        updates: {_database.storedTradePayments},
        updateKind: UpdateKind.update,
      );
      if (restarted.isNotEmpty) return const Ok(true);
      final started = await _database.customWriteReturning(
        _startSql,
        variables: [...key, Variable.withInt(at.microsecondsSinceEpoch)],
        updates: {_database.storedTradePayments},
        updateKind: UpdateKind.insert,
      );
      return Ok(started.isNotEmpty);
    } on Exception {
      // A trade closed or never read is refused by a trigger that aborts: nothing was written, and the wallet is not asked.
      return const Err(P2pStorageFailure());
    }
  }

  @override
  Future<Result<bool, P2pFailure>> recordWalletPayment(
    TradeRecord trade,
    InvoiceStep step, {
    required String paymentHash,
    required String walletPaymentId,
    int take = 0,
  }) async {
    try {
      final written = await _database.customWriteReturning(
        _walletPaymentSql,
        variables: [
          Variable.withString(walletPaymentId),
          ..._robotVariables(trade.robot),
          Variable.withString(step.name),
          Variable.withInt(take),
          Variable.withString(paymentHash),
        ],
        updates: {_database.storedTradePayments},
        updateKind: UpdateKind.update,
      );
      return Ok(written.isNotEmpty);
    } on Exception {
      return const Err(P2pStorageFailure());
    }
  }

  /// The robot's key fingerprint and index, as the tables key a trade.
  static List<Variable<Object>> _robotVariables(RobotSlot robot) => [
    Variable.withString(robot.keyFingerprint.hex),
    Variable.withInt(robot.accountIndex),
  ];
}
