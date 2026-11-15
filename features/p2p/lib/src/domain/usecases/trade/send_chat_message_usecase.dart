import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../robot_key_compute_port.dart';
import '../../robot_request_limiter.dart';
import '../../trade/trade_chat.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import 'trade_chats.dart';
import 'trade_keyring.dart';
import 'trade_reader.dart';
import 'watch_chat_usecase.dart';

/// Sends a message in the chat of a trade (#93, design note § 3.6, § 4.2, `AGENTS.md` « The encrypted chat of a trade »).
///
/// The text the user typed, as typed, is checked ([refusalOf]: not empty, within `OutgoingChatMessage.maxTextBytes`, no Garage Key, not a Lightning invoice or a Bitcoin address on its own), encrypted to the robot itself and to the peer key pinned for the trade, signed (the package refuses a text that holds the robot's token), and posted once through the robot's places in [RobotRequestLimiter], with the offset the chat has reached so that the answer brings the new messages.
/// A post the coordinator refused stored nothing; a post whose outcome is unknown is looked for in a read from the offset it was posted with ([ChatPage.indexOf]): found, it is stored; not found, it is pending, « not confirmed », and only the user sends it again ([sendAgain]), the same encrypted message, never a new encryption of the text.
/// Nothing here is printed, logged or stored.
final class SendChatMessageUsecase {
  final CoordinatorClient _client;
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final TradeKeyring _keyring;
  final RobotKeyComputePort _compute;
  final TradeChats _chats;

  const SendChatMessageUsecase(
    this._client,
    this._reader,
    this._limiter,
    this._keyring,
    this._compute,
    this._chats,
  );

  /// Why [text] cannot be sent, said as the user types, or `null`: what needs no key and no request (the robot's token is checked when it is encrypted).
  static ChatSendRefusal? refusalOf(String text) {
    if (text.trim().isEmpty) return const ChatTextEmpty();
    if (OutgoingChatMessage.textBytesOf(text) >
        OutgoingChatMessage.maxTextBytes) {
      return const ChatTextTooLong();
    }
    if (_garageKey.hasMatch(text)) return const ChatTextHoldsGarageKey();
    if (_isPayout(text)) return const ChatTextIsPayout();
    return null;
  }

  /// A Garage Key in its text form, bech32 with the part `robo` (`GarageKey`), refused by its shape alone: a key with a typo still gives most of it away.
  static final RegExp _garageKey = RegExp(
    r'robo1[02-9ac-hj-np-z]{58}',
    caseSensitive: false,
  );

  /// A Lightning invoice by its shape (BOLT 11: `ln`, a network's prefix, an amount, the separator, bech32 data), with or without the `lightning:` prefix.
  static final RegExp _invoice = RegExp(
    r'^(lightning:)?ln(bcrt|bc|tbs|tb)[0-9]*[munp]?1[02-9ac-hj-np-z]{50,}$',
    caseSensitive: false,
  );

  /// Whether [text], stripped as the coordinator strips a clear-signed text, is on its own a Lightning invoice or a Bitcoin address of either network, with or without its URI prefix (review of #93).
  ///
  /// A chat message's signature is the same text signature as a clear-signed payout's (`UnlockedRobotPgpKey.signCleartext`): for a text of one line the signed bytes are identical, so the message can be turned into this robot's signed payout. The peer alone cannot use it, since a coordinator checks a payout against the key of the robot that sends it, authenticated by its token's hash; whoever holds that hash, any coordinator this robot was shown to, colluding with the peer, can: at status 15 of this trade, or at the payout step of any later trade where this robot buys, the signature being tied to no order. The dangerous text is the attacker's destination pasted back by the user, not the user's own. The reference refuses nothing (`AGENTS.md`, a deviation the owner is asked about); the design note's § 4.2 refused the trade's own payout text, the wrong text.
  static bool _isPayout(String text) {
    final stripped = text.replaceAll(_pythonSpace, '');
    if (_invoice.hasMatch(stripped)) return true;
    final lower = stripped.toLowerCase();
    final address = lower.startsWith('bitcoin:')
        ? stripped.substring('bitcoin:'.length).split('?').first
        : stripped;
    // The segwit versions this wallet's check leaves out (version 1 of another length, 2 to 16) are valid to the coordinator's bitcoind, and anyone can spend them.
    return RobosatsNetwork.values.any(
      (network) => switch (BitcoinAddress.check(address, network)) {
        Ok() || Err(failure: PayoutDestinationUnsupported()) => true,
        Err() => false,
      },
    );
  }

  /// What Python's `str.strip()` removes from both ends, as the coordinator does before it checks a clear-signed text (`api/utils.py:642-644`): Dart's whitespace, which lacks U+001C to U+001F and U+0085, and those.
  static final RegExp _pythonSpace = RegExp(
    r'^[\s\x1c-\x1f\x85]+|[\s\x1c-\x1f\x85]+$',
  );

  /// Sends [text] in the chat of [record], about the order of [seen], the status the screen shows.
  Future<Result<ChatSent, ChatSendRefusal>> send(
    TradeRecord record,
    TradeSeen seen,
    String text,
  ) async {
    if (refusalOf(text) case final refusal?) return Err(refusal);
    final chat = _chats.of(record);
    final PgpPublicKey peer;
    switch (chat.peerKey) {
      case ChatPeerKeyPinned(:final key):
        peer = key;
      case ChatPeerKeyBreach():
        return const Err(ChatPeerKeyChanged());
      case ChatPeerKeyAwaited():
        return const Err(ChatPeerKeyNotKnown());
    }
    final order = seen.order;
    if (order == null) return const Err(ChatClosed());
    final OpenTrade trade;
    switch (await _open(record)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        trade = value;
    }
    final TradeKeyLease lease;
    switch (await _keyring.lease(trade)) {
      case Err(:final failure):
        return Err(ChatSendUnavailable(failure));
      case Ok(:final value):
        lease = value;
    }
    final OutgoingChatMessage message;
    try {
      switch (lease.key.encryptChatMessageToPost(
        text,
        peer: peer,
        now: _reader.now(),
      )) {
        case Err(failure: PgpPlaintextContainsToken()):
          return const Err(ChatTextHoldsToken());
        case Err(failure: PgpChatTextTooLong()):
          return const Err(ChatTextTooLong());
        case Err(:final failure):
          return Err(ChatSendUnavailable(failure));
        case Ok(:final value):
          message = value;
      }
    } finally {
      lease.close();
    }
    return _post(chat, trade, order, message, text, pending: null);
  }

  /// Sends again the pending message [id] of the chat of [record], the user's choice: the same encrypted message, so that a reader can tell a duplicate by its text.
  Future<Result<ChatSent, ChatSendRefusal>> sendAgain(
    TradeRecord record,
    TradeSeen seen,
    int id,
  ) async {
    final chat = _chats.of(record);
    final message = chat.pendingMessage(id);
    if (message == null) return const Err(ChatClosed());
    if (chat.peerKey is! ChatPeerKeyPinned) {
      return const Err(ChatPeerKeyChanged());
    }
    final order = seen.order;
    if (order == null) return const Err(ChatClosed());
    final OpenTrade trade;
    switch (await _open(record)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        trade = value;
    }
    return _post(chat, trade, order, message, null, pending: id);
  }

  Future<Result<OpenTrade, ChatSendRefusal>> _open(TradeRecord record) async =>
      switch (await _reader.open(record)) {
        TradeOpened(:final trade) => Ok(trade),
        TradeNotOpened(:final failure) => Err(ChatSendUnavailable(failure)),
        TradeNotRestorable(:final reason) => Err(ChatSendUnavailable(reason)),
        TradeTakeNeverSent() => const Err(ChatClosed()),
      };

  /// Posts [message] once, then says what it gave: stored at an index, refused (nothing stored), or not confirmed after a read from the offset it was posted with.
  Future<Result<ChatSent, ChatSendRefusal>> _post(
    TradeChat chat,
    OpenTrade trade,
    CoordinatorOrder order,
    OutgoingChatMessage message,
    String? text, {
    required int? pending,
  }) async {
    // Encrypted to the key pinned for the trade as it is now, right before the post: a breach read while this send waited stops it.
    if (chat.pinnedKey?.fingerprint != message.peerFingerprint) {
      return const Err(ChatPeerKeyChanged());
    }
    if (pending != null) chat.sentAgain(message);
    final offset = chat.offset;
    final identity = trade.robot.identity;
    final requests = _limiter.open(identity.sessionKey);
    try {
      final posted = await requests.send(
        trade.record.network,
        trade.coordinator,
        () => _client.postChat(
          identity: identity,
          lastRead: order,
          message: message,
          offset: offset,
        ),
        isBusy: _answeredBusy,
      );
      final ChatPage? page;
      switch (posted) {
        // The limiter sent nothing (a busy coordinator every time).
        case Err(:final failure):
          return Err(ChatSendRefused(failure));
        case Ok(value: Err(failure: OrderActionRefused(:final cause))):
          return Err(
            ChatSendRefused(
              cause,
              fromLastRead: cause is ChatRefused && cause.fromLastRead,
            ),
          );
        case Ok(value: Err(failure: OrderActionOutcomeUnknown())):
          // Read again from the offset it was posted with, and look for it there.
          final again = await requests.send(
            trade.record.network,
            trade.coordinator,
            () => _client.fetchChat(
              identity: identity,
              lastRead: order,
              offset: offset,
            ),
            isBusy: TradeReader.answeredBusy,
          );
          page = switch (again) {
            Ok(value: Ok(:final value)) => value,
            _ => null,
          };
        case Ok(value: Ok(:final value)):
          page = value;
      }
      final index = page?.indexOf(message);
      if (page != null) {
        await ChatPages.take(_keyring, _compute, _reader, chat, trade, page);
      }
      // A page that shows it took it off the pending messages too.
      if (index != null) return Ok(ChatSentStored(index));
      final kept = switch (pending) {
        final id? => _pendingView(chat, id),
        null => null,
      };
      return Ok(
        ChatSentNotConfirmed(
          kept ?? chat.pend(text ?? '', message, _reader.now()),
        ),
      );
    } finally {
      requests.close();
    }
  }

  static ChatPendingMessage? _pendingView(TradeChat chat, int id) {
    for (final p in chat.view.pending) {
      if (p.id == id) return p;
    }
    return null;
  }

  static bool _answeredBusy(Result<ChatPage, OrderActionFailure> answer) =>
      switch (answer) {
        Err(failure: OrderActionRefused(cause: CoordinatorTransportBusy())) =>
          true,
        _ => false,
      };
}
