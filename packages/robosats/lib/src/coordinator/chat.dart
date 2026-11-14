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
/// Posting the same value twice posts the same ciphertext twice, which a reader can tell from two messages ([ChatPage.indexOf]).
@immutable
final class OutgoingChatMessage {
  /// The most characters this package posts in `PGP_message`: the `max_length` the coordinator's model declares (`chat/models.py:389`).
  ///
  /// The reference coordinator does not enforce it (its serializer declares the field without it, `chat/serializers.py:280-283`, and the column is a PostgreSQL `text`), nor does the official client; this package keeps to it all the same.
  /// A message of a robot of the official client or of this package takes about 1.4 characters per byte of UTF-8 text plus about 700: see the tests for the longest text that always fits.
  static const maxWireChars = 5000;

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
  /// Fails with [ChatRefused] of [ChatRefusal.messageTooLong] when it would take more than [maxWireChars] on the wire, and with [PgpArmorMalformed] when [armored] holds a backslash or a carriage return, which the one-line form could not carry both ways: neither happens with the armor of this package.
  @internal
  static Result<OutgoingChatMessage, RobosatsFailure> fromArmored(
    String armored, {
    required RobotHashId sender,
    required String peerFingerprint,
  }) {
    if (armored.contains(r'\') || armored.contains('\r')) {
      return const Err(PgpArmorMalformed());
    }
    final wire = pgpArmorToWire(armored);
    if (wire.length > maxWireChars) {
      return const Err(ChatRefused(ChatRefusal.messageTooLong));
    }
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
sealed class ChatPeerKey {
  const ChatPeerKey();
}

/// A key named after the peer of the last read of the order (`RoboSats ID <hash id>`, the user ID the official client gives a robot's key, `frontend/src/pgp/index.ts:26`).
///
/// A coordinator knows the peer's hash id and can make such a key itself: only pinning tells a key replaced after the first page.
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
/// Its query has no `order_by` (`chat/models.py:358-360`), and it numbers a post `count + 1` without a lock or a unique constraint (`chat/views.py:158-166`), so two posts at once can share an index and the next one skips an index.
/// So the order, a repeated index and a gap are facts given to the caller ([inIndexOrder], [repeatsAnIndex], [isContiguous]), not reasons to refuse the page: key messages by index, keep the first one seen, as the official client does (`EncryptedApiChat/index.tsx:174-178`), and say when a page is not contiguous.
/// What no honest coordinator sends refuses the whole page with [CoordinatorResponseMalformed]: a field of the wrong type, an index not above the offset or above [maxIndex], a time out of range, a nickname that no robot can have, more than [maxMessages] messages.
/// What a peer chooses never refuses a page, so that a peer cannot stop this robot from reading the chat: the text of a message, whatever its length or form, is classified per message ([ChatMessageContent]).
@immutable
final class ChatPage {
  /// The most messages a page may hold: a trade's chat holds tens.
  static const maxMessages = 2000;

  /// The largest index: the coordinator's `PositiveIntegerField` on PostgreSQL (`chat/models.py:373`).
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

  /// The highest index of the page, or [offset] when it has none: the offset to ask the next page from.
  ///
  /// It counts every message, those whose text was dropped included, so that a message this package cannot read is not asked for again and again (the official client asks again for every message it did not decrypt).
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

  /// The index of the first message of the page attributed to this robot whose text is exactly [message], or `null`.
  ///
  /// After a post whose outcome is unknown, it tells whether a later page holds the message: a coordinator stores a post's text as it was sent.
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
    if (list is! List<Object?> || list.length > maxMessages) {
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
    final nick = fields.requiredString('nick', maxLength: ChatMessage.maxNickLength);
    if (fields.rejected case final field?) {
      return Err(CoordinatorResponseMalformed(field));
    }
    if (index <= offset) return const Err(CoordinatorResponseMalformed('index'));
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
