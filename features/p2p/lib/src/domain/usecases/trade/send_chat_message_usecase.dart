import 'dart:async';
import 'dart:math';

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
/// The text the user typed, as typed, is checked ([refusalOf]: not empty, within `OutgoingChatMessage.maxTextBytes`, no Garage Key; an invoice or an address alone is sent, as the reference sends it, `AGENTS.md`), encrypted to the robot itself and to the peer key pinned for the trade, signed (the package refuses a text that holds the robot's token), and posted once through the robot's places in [RobotRequestLimiter], with the offset the chat has reached so that the answer brings the new messages.
/// A post the coordinator refused stored nothing; a post whose outcome is unknown is looked for in a read from the offset it was posted with ([ChatPage.indexOf]): found, it is stored; not found, it is pending, « not confirmed », and only the user sends it again ([sendAgain]), the same encrypted message, never a new encryption of the text.
///
/// As the official client (`onSendMessage`, `frontend/src/components/TradeBox/EncryptedChat/index.tsx:201-239`, commit ff1998c), a message is also published over Nostr (#94), so that a peer on the official client, which shows only the Nostr messages by default, reads it: an [OutgoingNostrChatMessage] for the order's two Nostr keys, published to the relays [nostrRelaysFor] chooses, through the robot's Tor sessions.
/// That publication never delays nor blocks the post to the coordinator: it is built and started once the post has started, its outcome changes nothing of the message's state and is shown nowhere, as in the reference (decision D3); only the transport logs a fixed word when a relay did not take it.
/// Nothing is built when the order lacks a Nostr key or holds for this robot a key that is not the robot's ([OutgoingNostrChatMessage.compose]).
/// « Send again » publishes the same Nostr events again only when no relay accepted them, so that a peer never sees a message twice.
/// Nothing here is printed, logged or stored.
final class SendChatMessageUsecase {
  final CoordinatorClient _client;
  final TradeReader _reader;
  final RobotRequestLimiter _limiter;
  final TradeKeyring _keyring;
  final RobotKeyComputePort _compute;
  final TradeChats _chats;
  final NostrRelayTransport _relays;
  final Federation _federation;

  /// [Random.secure] in the app: the NIP-44 nonces, the signatures' aux, the throwaway keys, the dates of the gift wraps and the choice of relays.
  final Random _random;

  const SendChatMessageUsecase(
    this._client,
    this._reader,
    this._limiter,
    this._keyring,
    this._compute,
    this._chats,
    this._relays,
    this._federation,
    this._random,
  );

  /// Why [text] cannot be sent, said as the user types, or `null`: what needs no key and no request (the robot's token is checked when it is encrypted).
  static ChatSendRefusal? refusalOf(String text) {
    if (text.trim().isEmpty) return const ChatTextEmpty();
    if (OutgoingChatMessage.textBytesOf(text) >
        OutgoingChatMessage.maxTextBytes) {
      return const ChatTextTooLong();
    }
    if (_garageKey.hasMatch(text)) return const ChatTextHoldsGarageKey();
    return null;
  }

  /// A Garage Key in its text form, bech32 with the part `robo` (`GarageKey`), refused by its shape alone: a key with a typo still gives most of it away.
  static final RegExp _garageKey = RegExp(
    r'robo1[02-9ac-hj-np-z]{58}',
    caseSensitive: false,
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
    final posting = _post(chat, trade, order, message, text, pending: null);
    // Once the post has started, never before it: its outcome is the message's state, whatever Nostr does.
    unawaited(
      Future(() {
        final composed = OutgoingNostrChatMessage.compose(
          identity: trade.robot.identity,
          order: order,
          coordinator: trade.coordinator,
          network: trade.record.network,
          text: text,
          now: _reader.now(),
          random: _random,
        );
        if (composed case Ok(value: final copy)) {
          chat.keepNostrCopy(message, copy);
          _publishOverNostr(chat, message, copy, trade);
        }
      }),
    );
    return posting;
  }

  /// Publishes [copy] on the relays of the trade's network, each through a Tor session of the robot, all at once; marks it delivered when one relay accepted it.
  void _publishOverNostr(
    TradeChat chat,
    OutgoingChatMessage message,
    OutgoingNostrChatMessage copy,
    OpenTrade trade,
  ) {
    final relays = nostrRelaysFor(
      trade.coordinator,
      _federation,
      trade.record.network,
      _random,
    );
    final robot = trade.robot.identity.sessionKey;
    unawaited(
      Future.wait([
        for (final relay in relays) _relays.publish(relay, copy, robot: robot),
      ]).then((outcomes) {
        if (outcomes.any((outcome) => outcome is NostrRelayAccepted)) {
          chat.nostrCopyDelivered(message);
        }
      }),
    );
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
    final posting = _post(chat, trade, order, message, null, pending: id);
    // The same events, and only when no relay accepted them: a peer on the official client counts them once (same ids).
    if (chat.nostrCopyToPublish(message) case final copy?) {
      unawaited(Future(() => _publishOverNostr(chat, message, copy, trade)));
    }
    return posting;
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
    // Checked again right before the request leaves: a breach read while the limiter waited for a place, or after a busy answer, stops it too (review of #93).
    var breached = false;
    Future<Result<ChatPage, OrderActionFailure>> post() async {
      if (chat.pinnedKey?.fingerprint != message.peerFingerprint) {
        breached = true;
        // Nothing leaves; the answer is never read.
        return const Err(OrderActionRefused(CoordinatorUnreachable()));
      }
      return _client.postChat(
        identity: identity,
        lastRead: order,
        message: message,
        offset: offset,
      );
    }

    try {
      final posted = await requests.send(
        trade.record.network,
        trade.coordinator,
        post,
        isBusy: _answeredBusy,
      );
      if (breached) return const Err(ChatPeerKeyChanged());
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
      if (index != null) {
        chat.forgetNostrCopy(message);
        return Ok(ChatSentStored(index));
      }
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
