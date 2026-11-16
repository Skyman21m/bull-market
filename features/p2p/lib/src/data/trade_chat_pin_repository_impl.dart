import 'package:drift/drift.dart';
import 'package:primitives/primitives.dart';

import '../domain/p2p_failure.dart';
import '../domain/repositories/trade_chat_pin_repository.dart';
import '../domain/trade/trade_chat_pin.dart';
import '../domain/trade_record.dart';
import 'p2p_database.dart';

/// The peer's keys the trades' chats pinned, by their fingerprints, and the Nostr keys of their first Nostr copies, in the feature's database (schema 6, #139, part of #159).
///
/// Each write is one statement, which SQLite runs atomically. The triggers of `trade_chat_pins.drift` refuse, whatever the code, any delete, any update, a second pin of a trade, and a pin of no open trade, in both tables.
/// This class is the only writer of the two tables, and opens no transaction.
/// It returns no row of the database: the pins only, and a [P2pStorageFailure] for any [Exception] the database throws; an [Error] is a bug (AGENTS.md, rule 11) and is not caught.
final class TradeChatPinRepositoryImpl implements TradeChatPinRepository {
  /// A trade's first pin: a second insert writes nothing (the trigger `trade_chat_pins_inserted_once`), and one of a closed trade is refused (`trade_chat_pins_of_their_trade`).
  static const String _keepSql =
      'INSERT INTO trade_chat_pins (key_fingerprint, robot_index, '
      'primary_fingerprint, subkey_fingerprint) VALUES (?, ?, ?, ?) '
      'RETURNING robot_index';

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
      final written = await _database.customWriteReturning(
        _keepSql,
        variables: [
          ..._tradeVariables(trade),
          Variable.withString(pin.primary),
          Variable.withString(pin.subkey),
        ],
        updates: {_database.storedTradeChatPins},
        updateKind: UpdateKind.insert,
      );
      if (written.isNotEmpty) return const Ok(true);
    } on Exception {
      // A closed trade is refused by a trigger that aborts: nothing was written.
      return const Err(P2pStorageFailure());
    }
    // Nothing written: a pin was kept already, this one or another.
    return switch (await pinOf(trade)) {
      Ok(value: final stored?) => Ok(stored == pin),
      Ok(value: null) => const Err(P2pStorageFailure()),
      Err(:final failure) => Err(failure),
    };
  }

  /// A trade's first Nostr pin: a second insert writes nothing, and one of a closed trade is refused, as for the PGP pin.
  static const String _keepNostrSql =
      'INSERT INTO trade_chat_nostr_pins (key_fingerprint, robot_index, '
      'peer_key, own_key) VALUES (?, ?, ?, ?) '
      'RETURNING robot_index';

  static const String _nostrPinSql =
      'SELECT peer_key, own_key FROM trade_chat_nostr_pins '
      'WHERE key_fingerprint = ? AND robot_index = ?';

  @override
  Future<Result<ChatNostrPin?, P2pFailure>> nostrPinOf(
    TradeRecord trade,
  ) async {
    final List<QueryRow> rows;
    try {
      rows = await _database
          .customSelect(
            _nostrPinSql,
            variables: _tradeVariables(trade),
            readsFrom: {_database.storedTradeChatNostrPins},
          )
          .get();
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    if (rows.isEmpty) return const Ok(null);
    return switch ((rows.single.data['peer_key'], rows.single.data['own_key'])) {
      (final String peer, final String own) => Ok(
        ChatNostrPin(peer: peer, own: own),
      ),
      _ => const Err(P2pStorageFailure()),
    };
  }

  @override
  Future<Result<bool, P2pFailure>> keepNostr(
    TradeRecord trade,
    ChatNostrPin pin,
  ) async {
    try {
      final written = await _database.customWriteReturning(
        _keepNostrSql,
        variables: [
          ..._tradeVariables(trade),
          Variable.withString(pin.peer),
          Variable.withString(pin.own),
        ],
        updates: {_database.storedTradeChatNostrPins},
        updateKind: UpdateKind.insert,
      );
      if (written.isNotEmpty) return const Ok(true);
    } on Exception {
      // A closed trade is refused by a trigger that aborts: nothing was written.
      return const Err(P2pStorageFailure());
    }
    return switch (await nostrPinOf(trade)) {
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
