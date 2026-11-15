import 'package:drift/drift.dart';
import 'package:primitives/primitives.dart';

import '../domain/p2p_failure.dart';
import '../domain/repositories/trade_chat_pin_repository.dart';
import '../domain/trade/trade_chat_pin.dart';
import '../domain/trade_record.dart';
import 'p2p_database.dart';

/// The peer's keys the trades' chats pinned, by their fingerprints, in the feature's database (schema 6, #139).
///
/// Each write is one statement, which SQLite runs atomically. The triggers of `trade_chat_pins.drift` refuse, whatever the code, any delete, any update, a second pin of a trade, and a pin of no open trade.
/// This class is the only writer of the table, and opens no transaction.
/// It returns no row of the database: the pins only, and a [P2pStorageFailure] for any [Exception] the database throws; an [Error] is a bug (AGENTS.md, rule 11) and is not caught.
final class TradeChatPinRepositoryImpl implements TradeChatPinRepository {
  /// A trade's first pin: a second insert writes nothing (the trigger `trade_chat_pins_inserted_once`), and one of a closed trade is refused (`trade_chat_pins_of_their_trade`).
  static const String _keepSql =
      'INSERT INTO trade_chat_pins (key_fingerprint, robot_index, '
      'primary_fingerprint, subkey_fingerprint) VALUES (?, ?, ?, ?)';

  static const String _pinSql =
      'SELECT primary_fingerprint, subkey_fingerprint FROM trade_chat_pins '
      'WHERE key_fingerprint = ? AND robot_index = ?';

  final P2pDatabase _database;

  const TradeChatPinRepositoryImpl(this._database);

  @override
  Future<Result<ChatPinFingerprints?, P2pFailure>> pinOf(
    TradeRecord trade,
  ) async {
    final List<QueryRow> rows;
    try {
      rows = await _database
          .customSelect(
            _pinSql,
            variables: _tradeVariables(trade),
            readsFrom: {_database.storedTradeChatPins},
          )
          .get();
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    if (rows.isEmpty) return const Ok(null);
    return switch ((
      rows.single.data['primary_fingerprint'],
      rows.single.data['subkey_fingerprint'],
    )) {
      (final String primary, final String subkey) => Ok(
        ChatPinFingerprints(primary: primary, subkey: subkey),
      ),
      _ => const Err(P2pStorageFailure()),
    };
  }

  @override
  Future<Result<bool, P2pFailure>> keep(
    TradeRecord trade,
    ChatPinFingerprints pin,
  ) async {
    try {
      await _database.customStatement(_keepSql, [
        trade.robot.keyFingerprint.hex,
        trade.robot.accountIndex,
        pin.primary,
        pin.subkey,
      ]);
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    // The pin stored now, this call's or an earlier one's.
    return switch (await pinOf(trade)) {
      Ok(value: final stored?) => Ok(stored == pin),
      Ok(value: null) => const Err(P2pStorageFailure()),
      Err(:final failure) => Err(failure),
    };
  }

  static List<Variable<Object>> _tradeVariables(TradeRecord trade) => [
    Variable.withString(trade.robot.keyFingerprint.hex),
    Variable.withInt(trade.robot.accountIndex),
  ];
}
