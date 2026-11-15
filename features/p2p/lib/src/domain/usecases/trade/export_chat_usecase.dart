import 'package:primitives/primitives.dart';

import '../../trade/trade_chat.dart';
import '../../trade_record.dart';
import 'trade_chats.dart';
import 'trade_keyring.dart';
import 'trade_reader.dart';

/// The chat of a trade as the official client's « Export » and « Don't trust, verify » give it (#93, `Prompts/Chat.tsx`, `Dialogs/AuditPGP.tsx`, commit ff1998c), the owner's choice (2026-11-15: as the reference): this robot's public key and the peer's, the encrypted private key, its passphrase, which is the robot's token, and the messages ([TradeChat.export]).
///
/// The only file of the feature that reads a robot's token, besides the Garage Key's fingerprint (`robot_bindings_architecture_test.dart`): whoever holds what it gives can act as the robot at its coordinator. It runs on the user's tap only; the robot's key is leased from [TradeKeyring] for the encrypted private key and its public key, and the lease is closed before it returns. Nothing here is printed, logged or stored.
final class ExportChatUsecase {
  final TradeReader _reader;
  final TradeKeyring _keyring;
  final TradeChats _chats;

  const ExportChatUsecase(this._reader, this._keyring, this._chats);

  /// The export of the chat of [record], or why it could not be made (the trade or the robot's key could not be had).
  Future<Result<Map<String, Object?>, ChatReadFailure>> execute(
    TradeRecord record,
  ) async {
    final OpenTrade trade;
    switch (await _reader.open(record)) {
      case TradeOpened(trade: final opened):
        trade = opened;
      case TradeNotOpened(:final failure):
        return Err(ChatTradeUnavailable(failure));
      case TradeNotRestorable() || TradeTakeNeverSent():
        return const Err(ChatNotOpen());
    }
    final TradeKeyLease lease;
    switch (await _keyring.lease(trade)) {
      case Err(:final failure):
        return Err(ChatTradeUnavailable(failure));
      case Ok(:final value):
        lease = value;
    }
    try {
      final key = lease.key.key;
      return Ok(
        _chats
            .of(record)
            .export(
              own: key.publicKey,
              encryptedPrivateKey: key.encryptedPrivateKeyArmored,
              passphrase: trade.robot.identity.token.reveal(),
            ),
      );
    } finally {
      lease.close();
    }
  }
}
