import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator_order.dart';
import 'package:robosats/src/coordinator/json_fields.dart';
import 'package:robosats/src/pgp/limits.dart';
import 'package:robosats/src/pgp_wire.dart';
import 'package:robosats/src/robosats_failure.dart';
import 'package:robosats/src/robot_hash_id.dart';
import 'package:robosats/src/robot_identity.dart';
import 'package:robosats/src/robot_pgp_key.dart';

/// A chat message encrypted by a robot's key for the chat of an order, ready to post: the only thing `CoordinatorClient.postChat` sends.
///
/// Only `UnlockedRobotPgpKey.encryptChatMessageToPost` makes one, so that no plaintext and no text of unknown origin can be posted by mistake.
/// It is encrypted to the robot itself and to one peer key, and signed by the robot, as the official client's `encryptMessage` (`frontend/src/pgp/index.ts:39-62`, commit ff1998c).
/// Posting the same value twice posts the same ciphertext twice, which a reader can tell from two messages ([ChatPage.indexOf], [ChatPage.repeatsACiphertext]).
@immutable
final class OutgoingChatMessage {
  /// The most characters this package posts in `PGP_message`: the `max_length` the coordinator's model declares (`chat/models.py:87`).
  ///
  /// The reference coordinator does not enforce it (its serializer declares the field again without it, `chat/serializers.py:62-65`, and the column is a PostgreSQL `text`), nor does the official client; this package keeps to it all the same.
  static const maxWireChars = 5000;

  /// The most bytes of text a message may hold, counted by [textBytesOf]: a text within it always fits in [maxWireChars].
  ///
  /// A message of a robot's key to one peer takes 574 characters for an empty text and about 1.36 more per byte (base64, and a line feed every 60 characters): 3,250 bytes take 4,982 characters, 3,300 take 5,051 (measured in the tests).
  /// The signature's two integers can only make a message a few characters shorter, never longer, so the bound holds for every message.
  static const maxTextBytes = 3250;

  /// The bytes [plaintext] takes inside a message, compared with [maxTextBytes]: its UTF-8 bytes, a line feed counting two since a text signature covers it as CR LF (`canonicalizeEOL` of OpenPGP.js), one already preceded by a carriage return counting one.
  ///
  /// For a screen: show how much is left before the text is refused.
  static int textBytesOf(String plaintext) {
    var bytes = 0;
    var previous = 0;
    for (final rune in plaintext.runes) {
      bytes += rune < 0x80
          ? 1
          : rune < 0x800
          ? 2
          : rune < 0x10000
          ? 3
          : 4;
      if (rune == 0x0a && previous != 0x0d) bytes++;
      previous = rune;
    }
    return bytes;
  }

  /// The armored `PGP MESSAGE`, with line feeds, as this package armors it: no armor header, no backslash, no carriage return.
  final String armored;

  /// [armored] on one line, as `PGP_message` carries it: every line feed turned into a backslash ([pgpArmorToWire]), exactly as the official client sends it (`frontend/src/components/TradeBox/EncryptedChat/index.tsx:263`).
  final String wire;

  /// The robot whose key encrypted and signed the message.
  final RobotHashId sender;

  /// The fingerprint of the peer key the message was encrypted to, besides the robot's own: compare it with the peer key pinned for the trade before posting.
  final String peerFingerprint;

  OutgoingChatMessage._(
    this.armored,
    this.wire,
    this.sender,
    this.peerFingerprint,
  );

  /// The message armored as [armored], encrypted by the robot [sender] to the key of fingerprint [peerFingerprint].
  ///
  /// Fails with [PgpArmorMalformed] when [armored] holds a backslash or a carriage return, which the one-line form could not carry both ways, and with [PgpChatTextTooLong] when it would take more than [maxWireChars] on the wire: neither happens with the armor of this package and a text within [maxTextBytes], which `UnlockedRobotPgpKey.encryptChatMessageToPost` checks before encrypting.
  @internal
  static Result<OutgoingChatMessage, PgpFailure> fromArmored(
    String armored, {
    required RobotHashId sender,
    required String peerFingerprint,
  }) {
    if (armored.contains(r'\') || armored.contains('\r')) {
      return const Err(PgpArmorMalformed());
    }
    final wire = pgpArmorToWire(armored);
    if (wire.length > maxWireChars) return const Err(PgpChatTextTooLong());
    return Ok(OutgoingChatMessage._(armored, wire, sender, peerFingerprint));
  }

  @override
  String toString() =>
      'OutgoingChatMessage(<redacted>, ${wire.length} characters)';
}

/// Who a chat message is from, by the nickname the coordinator gives it, compared with the nicknames derived from the hash ids of the last read of the order.
enum ChatSender {
  /// This robot: decrypt the message and check its signature with this robot's own key.
  self,

  /// The peer of the trade: check its signature with the peer's key pinned for the trade.
  peer,

  /// Neither: a reference coordinator never sends it (the sender of a message is the maker or the taker, `chat/views.py:139-144`), so the coordinator is not honest; the official client would take it as the peer (`EncryptedApiChat/index.tsx:156`).
  unknown,
}

/// What a message of a chat page holds.
enum ChatMessageContent {
  /// An armored `PGP MESSAGE` within [ChatMessage.maxReadChars], given as [ChatMessage.armored].
  pgpMessage,

  /// Text that does not start with `-----BEGIN PGP MESSAGE-----`: the official client ignores it (`EncryptedApiChat/index.tsx:155`), and this package drops the text, which no key protects.
  notPgpMessage,

  /// More than [ChatMessage.maxReadChars] characters: the text is dropped unread, since nothing in the reference bounds what a peer posts.
  tooLong,
}

/// One message of a chat page: `{index, time, message, nick}` (`chat/views.py:95-105`).
///
/// The text is never printed: [toString] shows the index, the sender and the kind of content only.
@immutable
final class ChatMessage {
  /// The longest nickname a coordinator gives a robot (`robosats/middleware.py:149`, `max_length=18`).
  static const maxNickLength = 18;

  /// The most characters of a message handed on for decryption: what `UnlockedRobotPgpKey.decryptChatMessage` reads.
  static const maxReadChars = PgpLimits.messageArmorChars;

  /// The coordinator's number for the message, above the offset of the page: see [ChatPage] for what it means and what it does not.
  final int index;

  /// When the coordinator stored it, as the coordinator says.
  final DateTime time;

  /// The nickname the coordinator gives the sender: letters, digits and hyphens, at most [maxNickLength], like every robot nickname.
  final String nick;

  final ChatSender sender;
  final ChatMessageContent content;

  /// The armored `PGP MESSAGE` with its line feeds restored ([pgpArmorFromWire]), for `UnlockedRobotPgpKey.decryptChatMessage` and for an export; `null` unless [content] is [ChatMessageContent.pgpMessage].
  ///
  /// Never log it.
  final String? armored;

  const ChatMessage._({
    required this.index,
    required this.time,
    required this.nick,
    required this.sender,
    required this.content,
    required this.armored,
  });

  @override
  String toString() => 'ChatMessage(#$index, ${sender.name}, ${content.name})';
}

/// The peer's public key as a chat page gives it (`peer_pubkey`, `chat/views.py:84,91,110`): the coordinator's word, which a coordinator can replace.
///
/// Pin the key of the first page for the trade and compare every later one with it (`PgpPublicKey` equality, or its fingerprint): this package keeps nothing from one page to the next.
/// No check here can tell that a key is the peer's: a coordinator that gives each side, from the first page, a key it made in the other's name can decrypt, read, change, encrypt again and sign again every message both ways, and every message then verifies.
/// Only comparing the keys outside the app, with the peer, tells that: the official client's « Don't trust, verify » dialog shows both public keys for that (`frontend/src/components/Dialogs/AuditPGP.tsx:107-151`).
/// What it needs is here: the peer's [PgpPublicKey.armored] and [PgpPublicKey.fingerprint] from [ChatPeerKeyOfPeer.key], and this robot's own from `RobotPgpKey.publicKey` (the robot read back, or `UnlockedRobotPgpKey.key`).
sealed class ChatPeerKey {
  const ChatPeerKey();
}

/// A key whose user ID is exactly `RoboSats ID ` followed by the hash id of the peer of the last read of the order, in lowercase hexadecimal: the only form the official client writes (`userIDs: [{ name: 'RoboSats ID ' + sha256(sha256(token)) }]`, `frontend/src/pgp/index.ts:26`, which OpenPGP.js writes as the name alone), and the one the reference's own test robots carry (`tests/robots/*/pub_key`); no other client in the reference makes robot keys.
///
/// What the name proves: the coordinator did not hand over a key that is plainly another robot's or its own under its own name.
/// What it does not prove: that the key is the peer's.
/// The hash id comes from the coordinator too, and a coordinator can make a key in the peer's name: pinning tells a key replaced after the first page, and only comparing the keys outside the app tells a key replaced from the first page (see [ChatPeerKey]).
final class ChatPeerKeyOfPeer extends ChatPeerKey {
  final PgpPublicKey key;

  const ChatPeerKeyOfPeer(this.key);

  @override
  String toString() => 'ChatPeerKeyOfPeer(${key.fingerprint})';
}

/// A key that reads, but is not named after the peer: another robot's key, this robot's own, or one the coordinator made; do not encrypt to it.
final class ChatPeerKeyMisnamed extends ChatPeerKey {
  final PgpPublicKey key;

  const ChatPeerKeyMisnamed(this.key);

  @override
  String toString() => 'ChatPeerKeyMisnamed(${key.fingerprint})';
}

/// No key: `peer_pubkey` absent, `null` (a robot without a key, `api/models/robot.py:21-27`) or empty.
final class ChatPeerKeyMissing extends ChatPeerKey {
  const ChatPeerKeyMissing();

  @override
  String toString() => 'ChatPeerKeyMissing()';
}

/// Text that is not a key this package reads, or over `PgpLimits.keyArmorChars` and left unread: [reason] says which, without the text.
final class ChatPeerKeyUnreadable extends ChatPeerKey {
  final PgpFailure reason;

  const ChatPeerKeyUnreadable(this.reason);

  @override
  String toString() => 'ChatPeerKeyUnreadable(${reason.runtimeType})';
}

/// The messages of the chat of an order above an offset, with the peer's connection and key: the answer of `GET /api/chat/` and of `POST /api/chat/` with an offset (`chat/views.py:107-113`, `:194-214`).
///
/// [messages] are as the coordinator sent them, in its order, none dropped: the coordinator chooses which and in which order, and the reference's own numbering is not reliable either.
/// Its model has no `ordering` (`chat/models.py:56-58`) and its query no `order_by` (`chat/views.py:64`), and it numbers a post `count + 1` without a lock or a unique constraint (`chat/views.py:158-166`), so two posts at once can share an index and the next one skips an index.
/// So the order, a repeated index, a gap and a repeated message are facts given to the caller ([inIndexOrder], [repeatsAnIndex], [isContiguous], [contiguousIndex], [repeatsACiphertext]), not reasons to refuse the page: key messages by index, keep the first one seen, as the official client does (`EncryptedApiChat/index.tsx:174-178`), and say when a page is not contiguous or shows a message again.
/// What no honest coordinator sends refuses the whole page with [CoordinatorResponseMalformed]: a field of the wrong type, an index not above the offset or above [maxIndex], a time out of range, a nickname that no robot can have.
/// What a peer chooses never refuses a page, so that a peer cannot stop this robot from reading the chat: the text of a message, whatever its length or form, is classified per message ([ChatMessageContent]), and the number of messages is not bounded but by the size of the body.
/// The size is the one thing a peer can push past a bound: a page over `CoordinatorReadBounds.chatBytes` is [ChatPageTooLarge], for the caller to say so (see there).
@immutable
final class ChatPage {
  /// The largest index: the coordinator's `PositiveIntegerField` on PostgreSQL (`chat/models.py:71`).
  static const maxIndex = 2147483647;

  /// The offset the page was asked from: every index is above it.
  final int offset;

  /// Whether the coordinator says the peer made a request in the last minute (`chat/views.py:78-91`); after a post, the flag it stored, not recomputed (`:174-179`).
  final bool peerConnected;

  final ChatPeerKey peerKey;

  /// Unmodifiable, in the coordinator's order.
  final List<ChatMessage> messages;

  const ChatPage._({
    required this.offset,
    required this.peerConnected,
    required this.peerKey,
    required this.messages,
  });

  /// The highest index of the page, or [offset] when it has none.
  ///
  /// Not the offset to poll from after a gap: one message at index 2,147,483,647 would make every later index of an honest coordinator fall at or below it, and nothing more would ever be read; poll from [contiguousIndex].
  int get lastIndex {
    var last = offset;
    for (final message in messages) {
      if (message.index > last) last = message.index;
    }
    return last;
  }

  /// Whether every index is above the one before it, in the coordinator's order.
  bool get inIndexOrder {
    for (var i = 1; i < messages.length; i++) {
      if (messages[i].index <= messages[i - 1].index) return false;
    }
    return true;
  }

  /// Whether two messages of the page have the same index: two posts at once on the reference, or a replay.
  bool get repeatsAnIndex =>
      messages.map((message) => message.index).toSet().length !=
      messages.length;

  /// Whether the indexes are exactly `offset + 1`, `offset + 2`, … in order: no gap, no repeat, no disorder.
  ///
  /// When it is false, a message may be missing, dropped by the coordinator or skipped by its numbering: the caller says so rather than taking the page as the whole chat.
  bool get isContiguous {
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].index != offset + 1 + i) return false;
    }
    return true;
  }

  /// The highest index reached from [offset] without a gap, whatever the order of the page: `offset + n` when every index from `offset + 1` to `offset + n` is in the page and `offset + n + 1` is not; [offset] when `offset + 1` is missing.
  ///
  /// It counts every message, those whose text was dropped included, so that a message this package cannot read is not asked for again and again (the official client asks again for every message it did not decrypt).
  /// The offset to poll from next: messages beyond a gap are read again at each poll until the gap fills, or for good when the gap is one the reference's numbering skipped.
  int get contiguousIndex {
    final indexes = {for (final message in messages) message.index};
    var reached = offset;
    while (indexes.contains(reached + 1)) {
      reached++;
    }
    return reached;
  }

  /// Whether two messages of the page carry exactly the same encrypted text: one message shown again at another index, by a coordinator that replays it, or sent again by its sender after a post whose outcome was unknown.
  ///
  /// The indexes say nothing of it: a message shown again at a new index leaves the page in order and contiguous.
  /// Across pages, the caller compares the texts it keeps ([ChatMessage.armored]).
  bool get repeatsACiphertext {
    final seen = <String>{};
    for (final message in messages) {
      final armored = message.armored;
      if (armored != null && !seen.add(armored)) return true;
    }
    return false;
  }

  /// The index of the first message of the page attributed to this robot whose text is exactly [message], or `null`.
  ///
  /// After a post whose outcome is unknown, an index found means the coordinator shows the message as stored; `null` proves nothing: it means not confirmed, never not sent, since a coordinator can leave the message out of this robot's pages and still show it to the peer, give it the peer's nickname, or change one character of it.
  int? indexOf(OutgoingChatMessage message) {
    for (final candidate in messages) {
      if (candidate.sender == ChatSender.self &&
          candidate.armored == message.armored) {
        return candidate.index;
      }
    }
    return null;
  }

  static final RegExp _nick = RegExp(r'^[A-Za-z0-9-]{1,18}$');

  static const _pgpMessageBegin = '-----BEGIN PGP MESSAGE-----';

  /// Reads the decoded body of a chat page asked from [offset] by the robot [identity], about the order of [lastRead], which that robot read.
  ///
  /// [lastRead] gives the peer, whose nickname tells who sent each message and whose hash id must name the peer's key.
  @internal
  static Result<ChatPage, CoordinatorFailure> parse(
    Object? body, {
    required RobotIdentity identity,
    required CoordinatorOrder lastRead,
    required int offset,
  }) {
    if (body is! Map<String, Object?>) {
      return const Err(CoordinatorResponseMalformed('chat'));
    }
    final fields = JsonFields(body);
    final peerConnected = fields.requiredBool('peer_connected');
    if (fields.rejected case final field?) {
      return Err(CoordinatorResponseMalformed(field));
    }
    final list = body['messages'];
    if (list is! List<Object?>) {
      return const Err(CoordinatorResponseMalformed('messages'));
    }
    final peer = lastRead.isMaker ? lastRead.taker : lastRead.maker;
    if (peer == null) return const Err(CoordinatorResponseMalformed('chat'));
    final messages = <ChatMessage>[];
    for (final item in list) {
      if (item is! Map<String, Object?>) {
        return const Err(CoordinatorResponseMalformed('messages'));
      }
      final message = _messageOf(
        item,
        identity: identity,
        peer: peer,
        offset: offset,
      );
      switch (message) {
        case Ok(:final value):
          messages.add(value);
        case Err(:final failure):
          return Err(failure);
      }
    }
    final ChatPeerKey peerKey;
    switch (body['peer_pubkey']) {
      case null || '':
        peerKey = const ChatPeerKeyMissing();
      case final String text:
        peerKey = switch (PgpPublicKey.parse(text)) {
          Err(:final failure) => ChatPeerKeyUnreadable(failure),
          Ok(value: final key) when key.userId == 'RoboSats ID ${peer.hex}' =>
            ChatPeerKeyOfPeer(key),
          Ok(value: final key) => ChatPeerKeyMisnamed(key),
        };
      default:
        return const Err(CoordinatorResponseMalformed('peer_pubkey'));
    }
    return Ok(
      ChatPage._(
        offset: offset,
        peerConnected: peerConnected,
        peerKey: peerKey,
        messages: List.unmodifiable(messages),
      ),
    );
  }

  static Result<ChatMessage, CoordinatorFailure> _messageOf(
    Map<String, Object?> item, {
    required RobotIdentity identity,
    required RobotHashId peer,
    required int offset,
  }) {
    final fields = JsonFields(item);
    final index = fields.requiredInt('index', min: 0, max: maxIndex);
    final time = fields.requiredDate('time');
    final nick = fields.requiredString(
      'nick',
      maxLength: ChatMessage.maxNickLength,
    );
    if (fields.rejected case final field?) {
      return Err(CoordinatorResponseMalformed(field));
    }
    if (index <= offset) {
      return const Err(CoordinatorResponseMalformed('index'));
    }
    if (time == null) return const Err(CoordinatorResponseMalformed('time'));
    if (!_nick.hasMatch(nick)) {
      return const Err(CoordinatorResponseMalformed('nick'));
    }
    final text = item['message'];
    if (text is! String) {
      return const Err(CoordinatorResponseMalformed('message'));
    }
    final ChatMessageContent content;
    if (text.length > ChatMessage.maxReadChars) {
      content = ChatMessageContent.tooLong;
    } else if (!text.startsWith(_pgpMessageBegin)) {
      content = ChatMessageContent.notPgpMessage;
    } else {
      content = ChatMessageContent.pgpMessage;
    }
    return Ok(
      ChatMessage._(
        index: index,
        time: time,
        nick: nick,
        sender: nick == identity.nickname
            ? ChatSender.self
            : nick == peer.nickname
            ? ChatSender.peer
            : ChatSender.unknown,
        content: content,
        armored: content == ChatMessageContent.pgpMessage
            ? pgpArmorFromWire(text)
            : null,
      ),
    );
  }

  @override
  String toString() =>
      'ChatPage(offset: $offset, ${messages.length} messages, lastIndex: $lastIndex, peerConnected: $peerConnected, $peerKey)';
}
