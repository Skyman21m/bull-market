import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../robot_request_limiter.dart';
import '../../trade/trade_chat.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import 'trade_chats.dart';
import 'trade_keyring.dart';
import 'trade_reader.dart';

/// Reads the chat of a trade (#93, design note § 3.6, `AGENTS.md` « The encrypted chat of a trade »): one [read] each time the screen polls, every 5 s while the chat is shown (the reference's `CHAT_POLL_INTERVAL_MS`, `EncryptedApiChat/index.tsx:51`).
///
/// A read asks `GET /api/chat/` through the robot's places in [RobotRequestLimiter], from the offset the trade's chat has reached ([TradeChat.offset]), pins or compares the peer's key, and decrypts each new message once with the robot's key, leased from [TradeKeyring] (kept while the chat holds it, `HoldTradeKeyUsecase`); the chat is kept in [TradeChats], in memory only.
/// Nothing here is printed, logged or stored.
final class WatchChatUsecase {
  final CoordinatorClient _client;
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final TradeKeyring _keyring;
  final TradeChats _chats;

  const WatchChatUsecase(
    this._client,
    this._reader,
    this._limiter,
    this._keyring,
    this._chats,
  );

  /// The chat of [record] as read so far, without a request.
  ChatView current(TradeRecord record) => _chats.of(record).view;

  /// Reads the chat of [record] once, about the order of [seen], the status the screen shows: the chat with what was new, or why nothing was (the chat as it was stays shown).
  Future<Result<ChatView, ChatReadFailure>> read(
    TradeRecord record,
    TradeSeen seen,
  ) async {
    final order = seen.order;
    if (order == null) return const Err(ChatNotOpen());
    final OpenTrade trade;
    switch (await _reader.open(record)) {
      case TradeOpened(trade: final opened):
        trade = opened;
      case TradeNotOpened(:final failure):
        return Err(ChatTradeUnavailable(failure));
      case TradeNotRestorable() || TradeTakeNeverSent():
        return const Err(ChatNotOpen());
    }
    final chat = _chats.of(record);
    final requests = _limiter.open(trade.robot.identity.sessionKey);
    try {
      final read = await requests.send(
        record.network,
        trade.coordinator,
        () => _client.fetchChat(
          identity: trade.robot.identity,
          lastRead: order,
          offset: chat.offset,
        ),
        isBusy: TradeReader.answeredBusy,
      );
      switch (read) {
        case Err(:final failure):
          return Err(ChatReadFailed(failure));
        case Ok(value: Err(failure: ChatPageTooLarge())):
          chat.tooLarge();
          return Ok(chat.view);
        case Ok(value: Err(failure: ChatRefused(fromLastRead: true))):
          return const Err(ChatNotOpen());
        case Ok(value: Err(:final failure)):
          return Err(ChatReadFailed(failure));
        case Ok(value: Ok(value: final page)):
          return switch (await ChatPages.take(
            _keyring,
            _reader,
            chat,
            trade,
            page,
          )) {
            Err(:final failure) => Err(ChatTradeUnavailable(failure)),
            Ok() => Ok(chat.view),
          };
      }
    } finally {
      requests.close();
    }
  }

  /// The user chose to read only the messages after the order's last chat index ([CoordinatorOrder.chatLastIndex] of [seen]), the history being too large to read from the start: the earlier messages are not shown, and the chat says so.
  ChatView readNewerOnly(TradeRecord record, TradeSeen seen) {
    final chat = _chats.of(record);
    final last = seen.order?.chatLastIndex;
    if (last != null) chat.skipTo(last);
    return chat.view;
  }
}

/// Takes a page into a trade's chat, the robot's key leased only when the page needs it, and the lease closed at once.
abstract final class ChatPages {
  static Future<Result<void, Failure>> take(
    TradeKeyring keyring,
    TradeReader reader,
    TradeChat chat,
    OpenTrade trade,
    ChatPage page,
  ) async {
    if (!chat.needsKey(page)) {
      chat.take(page);
      return const Ok(null);
    }
    final TradeKeyLease lease;
    switch (await keyring.lease(trade)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        lease = value;
    }
    try {
      final key = lease.key;
      final now = reader.now();
      chat.take(
        page,
        decrypt: (armored, sender) =>
            key.decryptChatMessage(armored, sender: sender, now: now),
        ownKey: key.key.publicKey,
      );
      return const Ok(null);
    } finally {
      lease.close();
    }
  }
}
