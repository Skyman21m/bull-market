import 'dart:async';
import 'dart:math';

import 'package:bull_logger/bull_logger.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../p2p_failure.dart';
import '../../repositories/trade_chat_pin_repository.dart';
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
/// It starts when the transport hands the post to the coordinator (`CoordinatorRequest.onSending`), as the reference starts it as it posts, and never when nothing is sent: a refusal before sending, a transport without a place every time, a key breach seen while the post waited (review of #158, decision A). It never delays nor blocks the post: it is composed apart (`RobotKeyComputePort.composeNostrChat`) and published without being awaited; its outcome changes nothing of the message's state and is shown nowhere, as in the reference (decision D3); only the transport logs a fixed word when a relay did not take it.
/// When the coordinator then refuses the post, the copy has left already, as in the reference: the screen says the coordinator did not take the message while a peer in the official client's Nostr view may read it, and a message typed again shows twice there (declared deviation, nothing built to avoid it).
/// Nothing is built when the order lacks a Nostr key or holds for this robot a key that is not the robot's ([OutgoingNostrChatMessage.compose]).
/// « Send again » publishes the same Nostr events again only when no relay accepted them, so that a peer never sees a message twice.
/// Nothing is posted while the peer key pinned in this run is not kept with the trade's record (review of #139), and no Nostr copy is published while the trade's Nostr keys are not (part of #159).
/// Nothing here is printed, and nothing stored but those pins; the Nostr copy logs only fixed words.
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
  final TradeChatPinRepository _pins;

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
    this._pins,
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
    // A pin whose write failed at the last read is written now, so that trying again sends (functional review of #139).
    await keepChatPin(_pins, record, chat);
    final PgpPublicKey peer;
    switch (chat.peerKey) {
      case ChatPeerKeyPinned(:final key):
        peer = key;
      case ChatPeerKeyBreach():
        return const Err(ChatPeerKeyChanged());
      case ChatPeerKeyAwaited():
        return const Err(ChatPeerKeyNotKnown());
    }
    if (!chat.pinsKept) {
      return const Err(ChatSendUnavailable(P2pStorageFailure()));
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
    final sent = await _post(
      chat,
      trade,
      order,
      message,
      text,
      pending: null,
      nostrText: text,
    );
    // A message refused, or never sent, is not pending: its Nostr copy will never be published again, nor at all if it is still being composed.
    if (sent is Err) chat.cancelNostrCopy(message);
    return sent;
  }

  /// Called when the transport writes the post of [message] to the coordinator: publishes its Nostr copy, composed now from [text] when there is none yet, unless a relay already accepted it, it is being composed, or the order changed a Nostr key pinned for the trade.
  ///
  /// The order's keys are admitted, and pinned at the first copy, here, synchronously, before anything is composed, so that two messages composed at once cannot go to two different keys; they are checked again before the copy is published (review of #158).
  /// A copy whose message was refused, or never sent, while it was composed is not published.
  /// Nothing of it, synchronous or not, reaches the post, the screen or the zone: a failure lets the copy go and logs a fixed word with the error's type (decided in the review of #158).
  void _sendOverNostr(
    TradeChat chat,
    OpenTrade trade,
    CoordinatorOrder order,
    OutgoingChatMessage message,
    String? text,
  ) {
    try {
      final peer = order.isMaker
          ? order.takerNostrPublicKeyHex
          : order.makerNostrPublicKeyHex;
      final own = order.isMaker
          ? order.makerNostrPublicKeyHex
          : order.takerNostrPublicKeyHex;
      if (!chat.admitNostrKeys(
        peer: peer,
        own: own,
        isKey: OutgoingNostrChatMessage.isNostrPublicKey,
      )) {
        log.info('P2P Nostr copy not sent: a Nostr key of the trade changed');
        return;
      }
      if (chat.nostrCopyToPublish(message) case final copy?) {
        _guarded(chat, message, () async {
          await _publishOverNostr(chat, message, copy, trade);
        });
        return;
      }
      if (text == null || chat.hasNostrCopy(message)) return;
      chat.nostrCopyComposing(message);
      final sender = trade.robot.identity.nostrKeyPair();
      _guarded(chat, message, () async {
        final composed = await _compute.composeNostrChat(
          sender,
          order: order,
          coordinator: trade.coordinator,
          network: trade.record.network,
          text: text,
          now: _reader.now(),
        );
        if (composed case Ok(value: Ok(value: final copy))) {
          // Not published when its message was refused meanwhile, or when a key of the trade changed meanwhile.
          if (chat.keepNostrCopy(message, copy)) {
            await _publishOverNostr(chat, message, copy, trade);
          }
        } else {
          chat.cancelNostrCopy(message);
        }
      });
    } on Object catch (error) {
      chat.cancelNostrCopy(message);
      log.info('P2P Nostr copy failed (${error.runtimeType})');
    }
  }

  /// Runs [work] later, its failure, whatever it is, kept from the zone: the copy is let go and a fixed word logged with the error's type, never its message.
  static void _guarded(
    TradeChat chat,
    OutgoingChatMessage message,
    Future<void> Function() work,
  ) {
    unawaited(
      Future(work).then(
        (_) {},
        onError: (Object error) {
          chat.cancelNostrCopy(message);
          log.info('P2P Nostr copy failed (${error.runtimeType})');
        },
      ),
    );
  }

  /// Publishes [copy] on the relays of the trade's network, each through a Tor session of the robot, all at once; marks it delivered when one relay accepted it.
  ///
  /// The Nostr keys this run pinned are kept with the trade's record first, so that a restart compares the order's keys with them (part of #159): no copy leaves under keys not kept. When the record holds other keys, the copies stop for the trade, as when the order changes a key; when the keys could not be written, this copy is let go and the next one tries again.
  Future<void> _publishOverNostr(
    TradeChat chat,
    OutgoingChatMessage message,
    OutgoingNostrChatMessage copy,
    OpenTrade trade,
  ) async {
    if (chat.nostrPinToKeep case final pin?) {
      switch (await _pins.keepNostr(trade.record, pin)) {
        case Ok(value: true):
          chat.nostrPinKept();
        case Ok(value: false):
          chat.nostrPinKeptOther();
          chat.cancelNostrCopy(message);
          log.info('P2P Nostr copy not sent: other Nostr keys kept');
          return;
        case Err():
          chat.cancelNostrCopy(message);
          log.info('P2P Nostr copy not sent: its keys were not kept');
          return;
      }
    }
    final relays = nostrRelaysFor(
      trade.coordinator,
      _federation,
      trade.record.network,
      _random,
    );
    final robot = trade.robot.identity.sessionKey;
    final outcomes = await Future.wait([
      for (final relay in relays) _relays.publish(relay, copy, robot: robot),
    ]);
    if (outcomes.any((outcome) => outcome is NostrRelayAccepted)) {
      chat.nostrCopyDelivered(message);
    }
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
    await keepChatPin(_pins, record, chat);
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
    // The same events when the post leaves, and only when no relay accepted them, so that a peer on the official client counts them once (same ids); composed from the pending text when the first composition failed.
    return _post(
      chat,
      trade,
      order,
      message,
      null,
      pending: id,
      nostrText: _pendingView(chat, id)?.text,
    );
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
    required String? nostrText,
  }) async {
    // Encrypted to the key pinned for the trade as it is now, right before the post: a breach read while this send waited stops it.
    if (chat.pinnedKey?.fingerprint != message.peerFingerprint) {
      return const Err(ChatPeerKeyChanged());
    }
    // Nothing is posted while the key pinned in this run is not kept with the trade's record, so that a restart cannot trust another key again (review of #139): the send writes it first, and the next read tries again.
    if (!chat.pinsKept) {
      return const Err(ChatSendUnavailable(P2pStorageFailure()));
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
        onSending: () => _sendOverNostr(chat, trade, order, message, nostrText),
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
        chat.releaseNostrCopy(message);
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
