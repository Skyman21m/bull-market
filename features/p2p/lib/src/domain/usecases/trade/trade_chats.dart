import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../robot_binding.dart';
import '../../robot_key_compute_port.dart';
import '../../trade/trade_chat.dart';
import '../../trade_record.dart';

/// The chats of the trades, in memory only (#93, design note § 3.6, `AGENTS.md` « The encrypted chat of a trade »): one [TradeChat] per trade, kept for the life of the process so that the peer's key stays pinned when the trade screen is opened again, and nothing of it is ever written.
///
/// One for the feature (a lazy singleton of the composition); only the chat use cases reach it.
final class TradeChats {
  final Map<(RobotSlot, int), TradeChat> _chats = {};

  /// The chat of the trade of [record].
  TradeChat of(TradeRecord record) =>
      _chats[(record.robot, record.orderId)] ??= TradeChat._();
}

/// What a message was decrypted into, or why it could not be.
typedef ChatDecryptor =
    Result<DecryptedChatMessage, PgpFailure> Function(
      String armored,
      PgpPublicKey sender,
    );

/// The chat of one trade as read so far: its messages by index (the first one seen kept), the peer's key pinned at its first read, the signatures seen, the offset to read from, and the messages posted whose outcome is not known.
///
/// Nothing in it is printed: [toString] counts.
final class TradeChat {
  TradeChat._();

  final Map<int, ChatEntry> _entries = {};

  /// The canonical armor of each message by index, for a peer's message read before the key and for the export; never logged.
  final Map<int, String> _armored = {};

  /// The index where each validly signed message was first seen.
  final Map<ChatSignatureKey, int> _signatures = {};

  /// The encrypted messages this robot sent again after a post whose outcome was unknown.
  final Set<String> _sentAgain = {};

  final List<_Pending> _pending = [];
  int _nextPendingId = 1;

  /// The Nostr copy of each message this robot sent and the coordinator has not yet shown as stored, by its canonical armor, and whether a relay accepted it (#94): « Send again » publishes the same events again only when none did.
  final Map<String, _NostrCopy> _nostrCopies = {};

  ChatPeerKeyState _peerKey = const ChatPeerKeyAwaited();
  bool _peerConnected = false;
  bool _connected = false;
  PgpPublicKey? _ownKey;
  bool _historyTooLarge = false;
  bool _skippedEarlier = false;
  bool _incomplete = false;

  /// The offset to read from: the highest index reached without a gap, carried over a gap of the reference's numbering once it held ([ChatPage.contiguousIndexOverRepeats], `AGENTS.md`).
  int _offset = 0;

  /// The index below which nothing is expected: 0, or the order's last chat index when the user chose to read only the newer messages.
  int _base = 0;

  /// The messages beyond the gap at the last reads, and for how many reads in a row they were the same.
  String? _beyondGap;
  int _gapReads = 0;

  /// The offset past the gap, as the page that showed the repeated index computed it ([ChatPage.contiguousIndexOverRepeats]): later pages, asked from before the gap, no longer show that index.
  int _carry = 0;

  /// How many reads a gap of the reference's numbering must hold, the messages beyond it unchanged, before it is read past.
  static const gapReadsToCarry = 3;

  /// The offset the next read asks from.
  int get offset => _offset;

  /// The pinned peer key, when there is one and no breach.
  PgpPublicKey? get pinnedKey => switch (_peerKey) {
    ChatPeerKeyPinned(:final key) => key,
    _ => null,
  };

  ChatPeerKeyState get peerKey => _peerKey;

  /// Whether a message read needs the robot's key: a new encrypted message, or a peer's message kept until the key was known that can now be read.
  bool needsKey(ChatPage page) =>
      page.messages.any(
        (m) =>
            m.content == ChatMessageContent.pgpMessage &&
            !_entries.containsKey(m.index),
      ) ||
      (_keyForPeer(page) != null &&
          _entries.values.any((e) => e.awaitingPeerKey));

  /// The key the peer's messages of [page] would be checked with, once [page]'s key is taken.
  PgpPublicKey? _keyForPeer(ChatPage page) =>
      switch ((_peerKey, page.peerKey)) {
        (ChatPeerKeyPinned(:final key), _) => key,
        (ChatPeerKeyAwaited(), ChatPeerKeyOfPeer(:final key)) => key,
        (ChatPeerKeyBreach(:final pinned), _) => pinned,
        _ => null,
      };

  /// The messages [page] would have decrypted, once [ownKey] is known: the peer's messages read before the key, once the key is known, and each new encrypted message (this robot's and neither party's checked with [ownKey], the peer's with its key).
  List<ChatDecryptJob> jobsFor(ChatPage page, PgpPublicKey ownKey) {
    final peerKey = _keyForPeerAfter(page);
    return [
      if (peerKey != null)
        for (final kept in _entries.values)
          if (kept.awaitingPeerKey)
            if (_armored[kept.index] case final armored?)
              (armored: armored, sender: peerKey),
      for (final message in page.messages)
        if (!_entries.containsKey(message.index) &&
            message.content == ChatMessageContent.pgpMessage)
          if (message.armored case final armored?)
            if (switch (message.sender) {
                  ChatSender.peer => peerKey,
                  ChatSender.self || ChatSender.unknown => ownKey,
                }
                case final sender?)
              (armored: armored, sender: sender),
    ];
  }

  /// The key the peer's messages of [page] are checked with once [page] is taken: the pinned key, or [page]'s if it pins one now; the key pinned before a breach.
  PgpPublicKey? _keyForPeerAfter(ChatPage page) =>
      switch (_keyAfter(page.peerKey)) {
        ChatPeerKeyPinned(:final key) => key,
        ChatPeerKeyBreach(:final pinned) => pinned,
        ChatPeerKeyAwaited() => null,
      };

  /// [decrypted], the results of [jobsFor] in its order, as the decryptor [take] needs.
  static ChatDecryptor decryptorOf(
    List<ChatDecryptJob> jobs,
    List<Result<DecryptedChatMessage, PgpFailure>> decrypted,
  ) {
    final byJob = {
      for (var i = 0; i < jobs.length && i < decrypted.length; i++)
        '${jobs[i].sender.fingerprint}:${jobs[i].armored}': decrypted[i],
    };
    return (armored, sender) =>
        byJob['${sender.fingerprint}:$armored'] ??
        const Err(PgpMessageUndecryptable());
  }

  /// Takes [page], read from [offset]: the peer's key pinned or compared, each new message decrypted once with [decrypt] ([ownKey] for this robot's, the pinned key for the peer's), marked, and the offset moved on.
  ///
  /// [decrypt] and [ownKey] are `null` when the page needs no key ([needsKey]).
  void take(ChatPage page, {ChatDecryptor? decrypt, PgpPublicKey? ownKey}) {
    _connected = true;
    _historyTooLarge = false;
    if (ownKey != null) _ownKey = ownKey;
    _peerConnected = page.peerConnected;
    final keyBefore = _peerKey;
    _peerKey = _keyAfter(page.peerKey);
    _incomplete = !page.isContiguous || page.repeatsAnIndex;
    final peerKey = _keyForPeer(page);

    // The peer's messages read before the key: read now that it is known.
    if (peerKey != null && decrypt != null) {
      for (final kept in [..._entries.values]) {
        final armored = _armored[kept.index];
        if (!kept.awaitingPeerKey || armored == null) continue;
        _entries[kept.index] = _decrypted(
          kept.index,
          kept.time,
          kept.nick,
          ChatAuthor.peer,
          armored,
          peerKey,
          decrypt,
        );
      }
    }
    for (final message in page.messages) {
      // An index already shown keeps the message first seen.
      if (_entries.containsKey(message.index)) continue;
      final armored = message.armored;
      if (armored != null) _armored[message.index] = armored;
      _entries[message.index] = switch ((message.content, message.sender)) {
        (ChatMessageContent.pgpMessage, ChatSender.peer)
            when peerKey == null || decrypt == null =>
          ChatEntry(
            index: message.index,
            time: message.time,
            nick: message.nick,
            author: ChatAuthor.peer,
            text: null,
            validSignature: false,
            signedAt: null,
            awaitingPeerKey: true,
          ),
        (ChatMessageContent.pgpMessage, final sender)
            when armored != null && decrypt != null =>
          _entryOf(message, armored, switch (sender) {
            ChatSender.peer => peerKey ?? _ownKeyOrThrow(),
            // Neither party: never checked as the peer's.
            ChatSender.self || ChatSender.unknown => _ownKeyOrThrow(),
          }, decrypt),
        _ => ChatEntry(
          index: message.index,
          time: message.time,
          nick: message.nick,
          author: _authorOf(message.sender),
          text: null,
          validSignature: false,
          signedAt: null,
          unreadable: true,
        ),
      };
    }

    // The page that pins the key, after a restart the whole history again: a message of the peer that the key just pinned does not verify was signed by another key, so the key given is not the one the peer wrote with (review of #93: a restart must not pin a forged key silently).
    if ((keyBefore, _peerKey)
        case (ChatPeerKeyAwaited(), ChatPeerKeyPinned(:final key))
        when _entries.values.any(
          (e) =>
              e.author == ChatAuthor.peer &&
              e.text != null &&
              !e.validSignature,
        )) {
      _peerKey = ChatPeerKeyBreach(pinned: key);
    }

    // The pending messages the coordinator now shows as stored.
    _pending.removeWhere((p) => page.indexOf(p.message) != null);
    _nostrCopies.removeWhere(
      (armored, copy) => page.indexOf(copy.message) != null,
    );
    _remark();
    _moveOffset(page);
  }

  PgpPublicKey _ownKeyOrThrow() => switch (_ownKey) {
    final key? => key,
    null => throw StateError('a message decrypted without the own key'),
  };

  ChatEntry _entryOf(
    ChatMessage message,
    String armored,
    PgpPublicKey sender,
    ChatDecryptor decrypt,
  ) => _decrypted(
    message.index,
    message.time,
    message.nick,
    _authorOf(message.sender),
    armored,
    sender,
    decrypt,
  );

  ChatEntry _decrypted(
    int index,
    DateTime time,
    String nick,
    ChatAuthor author,
    String armored,
    PgpPublicKey sender,
    ChatDecryptor decrypt,
  ) {
    switch (decrypt(armored, sender)) {
      case Err():
        return ChatEntry(
          index: index,
          time: time,
          nick: nick,
          author: author,
          text: null,
          validSignature: false,
          signedAt: null,
          unreadable: true,
        );
      case Ok(:final value):
        final signature = value.signatureKey;
        if (signature != null) {
          _signatures.putIfAbsent(signature, () => index);
        }
        final first = signature == null ? null : _signatures[signature];
        final repeat = first != null && first != index ? first : null;
        return ChatEntry(
          index: index,
          time: time,
          nick: nick,
          author: author,
          text: ChatEntry.displayable(value.text),
          validSignature: value.validSignature,
          signedAt: value.signedAt,
          repeatOf: repeat,
          sentTwice:
              repeat != null &&
              author == ChatAuthor.self &&
              _sentAgain.contains(armored),
        );
    }
  }

  static ChatAuthor _authorOf(ChatSender sender) => switch (sender) {
    ChatSender.self => ChatAuthor.self,
    ChatSender.peer => ChatAuthor.peer,
    ChatSender.unknown => ChatAuthor.unknown,
  };

  /// The peer's key after a page that gives [given]: pinned at the first key named after the peer, any other later key, a misnamed one, none or an unreadable one after it a breach, which stays.
  ChatPeerKeyState _keyAfter(ChatPeerKey given) => switch ((_peerKey, given)) {
    (ChatPeerKeyBreach(), _) => _peerKey,
    (ChatPeerKeyAwaited(), ChatPeerKeyOfPeer(:final key)) => ChatPeerKeyPinned(
      key,
    ),
    (ChatPeerKeyAwaited(), ChatPeerKeyMisnamed()) => const ChatPeerKeyBreach(),
    (ChatPeerKeyAwaited(), _) => _peerKey,
    (ChatPeerKeyPinned(:final key), ChatPeerKeyOfPeer(key: final again))
        when again == key =>
      _peerKey,
    (ChatPeerKeyPinned(:final key), _) => ChatPeerKeyBreach(pinned: key),
  };

  /// The marks of every message, from the messages in index order: a gap before it, a signature older than an earlier message of the same author.
  void _remark() {
    final indexes = _entries.keys.toList()..sort();
    var previous = _base;
    final latestSigned = <ChatAuthor, DateTime>{};
    for (final index in indexes) {
      final entry = _entries[index];
      if (entry == null) continue;
      final signedAt = entry.signedAt;
      final latest = latestSigned[entry.author];
      _entries[index] = entry.withMarks(
        afterGap: index > previous + 1,
        signedOutOfOrder:
            signedAt != null && latest != null && signedAt.isBefore(latest),
      );
      if (signedAt != null && (latest == null || signedAt.isAfter(latest))) {
        latestSigned[entry.author] = signedAt;
      }
      previous = index;
    }
  }

  /// The offset after [page]: its contiguous index, carried over a gap of the reference's numbering once that gap held for [gapReadsToCarry] reads with the messages beyond it unchanged.
  void _moveOffset(ChatPage page) {
    final reached = page.contiguousIndex;
    final beyond = [
      for (final m in page.messages)
        if (m.index > reached) '${m.index}:${m.armored ?? m.content.name}',
    ]..sort();
    final signature = beyond.join('|');
    if (beyond.isEmpty) {
      _beyondGap = null;
      _gapReads = 0;
      _carry = 0;
      _offset = reached;
      return;
    }
    final same = signature == _beyondGap;
    _gapReads = same ? _gapReads + 1 : 1;
    _beyondGap = signature;
    final carried = page.contiguousIndexOverRepeats;
    _carry = same && _carry > carried ? _carry : carried;
    _offset = _gapReads >= gapReadsToCarry && _carry > reached
        ? _carry
        : reached;
  }

  /// The history from [offset] is too large to read at once ([ChatPageTooLarge]).
  void tooLarge() => _historyTooLarge = true;

  /// The user chose to read only the messages after [lastIndex], the order's last chat index: the earlier ones are not shown, and the screen says so. Whether it skipped: not when [lastIndex] is not past the offset (an order read before those messages).
  bool skipTo(int lastIndex) {
    if (lastIndex <= _offset) return false;
    _offset = lastIndex;
    _base = lastIndex;
    _skippedEarlier = true;
    _historyTooLarge = false;
    return true;
  }

  /// A message this robot posted, not shown as stored: kept with its encrypted message to send again, and returned.
  ChatPendingMessage pend(
    String text,
    OutgoingChatMessage message,
    DateTime at,
  ) {
    final pending = ChatPendingMessage(_nextPendingId++, text, at);
    _pending.add(_Pending(pending, message));
    return pending;
  }

  /// The encrypted message of the pending message [id], to send again exactly, or `null`.
  OutgoingChatMessage? pendingMessage(int id) {
    for (final p in _pending) {
      if (p.view.id == id) return p.message;
    }
    return null;
  }

  /// The Nostr copy of [message] is being composed, its post having left.
  void nostrCopyComposing(OutgoingChatMessage message) =>
      _nostrCopies[message.armored] = _NostrCopy(message);

  /// Keeps [copy], the Nostr copy of [message], for « Send again », while [message] may still be sent again: not once it was forgotten ([forgetNostrCopy]).
  void keepNostrCopy(
    OutgoingChatMessage message,
    OutgoingNostrChatMessage copy,
  ) => _nostrCopies[message.armored]?.copy = copy;

  /// Whether a Nostr copy of [message] exists or is being composed.
  bool hasNostrCopy(OutgoingChatMessage message) =>
      _nostrCopies.containsKey(message.armored);

  /// The Nostr copy of [message] while no relay has accepted it, or `null`: none was made, it is being composed, or a relay has it.
  OutgoingNostrChatMessage? nostrCopyToPublish(OutgoingChatMessage message) =>
      switch (_nostrCopies[message.armored]) {
        _NostrCopy(delivered: false, :final copy?) => copy,
        _ => null,
      };

  /// A relay accepted the Nostr copy of [message].
  void nostrCopyDelivered(OutgoingChatMessage message) =>
      _nostrCopies[message.armored]?.delivered = true;

  /// [message] is stored by the coordinator, refused, or never sent: its Nostr copy will not be published again, and is let go.
  void forgetNostrCopy(OutgoingChatMessage message) =>
      _nostrCopies.remove(message.armored);

  /// The pending message [id] is sent again: a copy of it shown later is labelled as sent twice.
  void sentAgain(OutgoingChatMessage message) =>
      _sentAgain.add(message.armored);

  /// The chat as the screen shows it.
  ChatView get view {
    final indexes = _entries.keys.toList()..sort();
    return ChatView(
      entries: [for (final index in indexes) ?_entries[index]],
      pending: [for (final p in _pending) p.view],
      peerKey: _peerKey,
      peerConnected: _peerConnected,
      connected: _connected,
      ownKey: _ownKey,
      historyTooLarge: _historyTooLarge,
      skippedEarlier: _skippedEarlier,
      incomplete: _incomplete,
    );
  }

  /// The chat as the official client's « Export » gives it (`Prompts/Chat.tsx:150-160`, `complete_log_chat_<id>.json`), the owner's choice (2026-11-15: as the reference): the credentials, this robot's public key [own], the peer's pinned key, the encrypted private key and its passphrase, the robot's token, then every message as the reference keeps it (`EncryptedApiChat/index.tsx:185-195`). Whoever holds it can act as the robot at its coordinator; never printed, logged or stored.
  Map<String, Object?> export({
    required PgpPublicKey own,
    required String encryptedPrivateKey,
    required String passphrase,
  }) {
    final pinned = switch (_peerKey) {
      ChatPeerKeyPinned(:final key) => key,
      ChatPeerKeyBreach(:final pinned) => pinned,
      ChatPeerKeyAwaited() => null,
    };
    final indexes = _entries.keys.toList()..sort();
    return {
      'credentials': {
        'own_public_key': own.armored,
        // Left out before the peer's key is known, as the reference leaves `peerPubKey` undefined.
        'peer_public_key': ?pinned?.armored,
        'encrypted_private_key': encryptedPrivateKey,
        'passphrase': passphrase,
      },
      'messages': [
        for (final index in indexes)
          if (_entries[index] case final entry?)
            {
              'index': entry.index,
              'encryptedMessage': _armored[index],
              'plainTextMessage': entry.text,
              'validSignature': entry.validSignature,
              'userNick': entry.nick,
              'time': entry.time.toIso8601String(),
            },
      ],
    };
  }

  @override
  String toString() =>
      'TradeChat(${_entries.length} messages, ${_pending.length} pending, $_peerKey)';
}

final class _NostrCopy {
  final OutgoingChatMessage message;

  /// `null` while it is composed.
  OutgoingNostrChatMessage? copy;
  bool delivered = false;

  _NostrCopy(this.message);
}

final class _Pending {
  final ChatPendingMessage view;
  final OutgoingChatMessage message;

  const _Pending(this.view, this.message);
}
