import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// Who wrote a message of the chat of a trade, by the nickname the coordinator gives it ([ChatSender]).
enum ChatAuthor {
  /// This robot.
  self,

  /// The peer of the trade.
  peer,

  /// Neither party: a reference coordinator never sends it; the message is never checked as the peer's.
  unknown,
}

/// One message of the chat of a trade, as the screen shows it (#93), kept in memory only.
///
/// [toString] shows its index, author and kind, never its text.
@immutable
final class ChatEntry {
  /// The coordinator's number for the message: messages are keyed by it, the first one seen kept (`EncryptedApiChat/index.tsx:174-178`).
  final int index;

  /// When the coordinator says it stored the message.
  final DateTime time;

  /// The nickname the coordinator gives the author.
  final String nick;

  final ChatAuthor author;

  /// The decrypted text, cleaned for display ([ChatEntry.displayable]); `null` when it could not be read ([unreadable]) or while the peer's key is not known yet ([awaitingPeerKey]).
  final String? text;

  /// Whether the author's key signed it ([DecryptedChatMessage.validSignature]): the reference marks a message whose signature does not verify (`MessageCard/index.tsx`).
  final bool validSignature;

  /// When its valid signature says it was made; `null` without one.
  final DateTime? signedAt;

  /// The message could not be read: not an encrypted message, too long, or not decryptable by this robot.
  final bool unreadable;

  /// A message of the peer that came before the peer's key was known: decrypted once the key is pinned.
  final bool awaitingPeerKey;

  /// A message of the chat seems to be missing just before this one (a gap in the coordinator's numbering, `AGENTS.md`).
  final bool afterGap;

  /// The index of an earlier message that this one shows again, by its signature: the same signed message at two indexes (`AGENTS.md` « A message shown again »); `null` otherwise.
  final int? repeatOf;

  /// Whether this robot sent this message again itself, after a post whose outcome was unknown: a legitimate duplicate of [repeatOf], not a replay.
  final bool sentTwice;

  /// Whether its signature is older than an earlier-indexed message of the same author's.
  final bool signedOutOfOrder;

  const ChatEntry({
    required this.index,
    required this.time,
    required this.nick,
    required this.author,
    required this.text,
    required this.validSignature,
    required this.signedAt,
    this.unreadable = false,
    this.awaitingPeerKey = false,
    this.afterGap = false,
    this.repeatOf,
    this.sentTwice = false,
    this.signedOutOfOrder = false,
  });

  ChatEntry withMarks({
    bool? afterGap,
    int? Function()? repeatOf,
    bool? sentTwice,
    bool? signedOutOfOrder,
  }) => ChatEntry(
    index: index,
    time: time,
    nick: nick,
    author: author,
    text: text,
    validSignature: validSignature,
    signedAt: signedAt,
    unreadable: unreadable,
    awaitingPeerKey: awaitingPeerKey,
    afterGap: afterGap ?? this.afterGap,
    repeatOf: repeatOf == null ? this.repeatOf : repeatOf(),
    sentTwice: sentTwice ?? this.sentTwice,
    signedOutOfOrder: signedOutOfOrder ?? this.signedOutOfOrder,
  );

  /// [text] as the screen may show it and a copy gives it: plain text, the control characters but line feeds and tabs dropped, and every format character (Unicode category Cf: the marks that reorder text, U+061C, the zero-width characters, the zero-width joiner too, so that an emoji sequence shows as its parts, U+00AD, U+FEFF, the tag characters) and variation selector removed, so that nothing invisible reorders or hides in a peer's IBAN or address (design note § 3.6, review of #93).
  ///
  /// Also: the line and paragraph separators (U+2028, U+2029) become line feeds, as they render; the private-use characters, the noncharacters and the letters that show nothing (U+115F, U+1160, U+2800, U+3164, U+FFA0, and the combining grapheme joiner U+034F) are removed; a run of combining marks keeps its first [maxMarks]. What is left to the panel: a box of a bounded height that scrolls, and the text in a forced direction.
  static String displayable(String text) => text
      .replaceAll(_separators, '\n')
      .replaceAll(_hidden, '')
      .replaceAllMapped(_markRun, (run) => run[1] ?? '');

  /// The combining marks a character keeps: enough for the scripts that stack them, not for a text drawn over its neighbours.
  static const maxMarks = 4;

  static final RegExp _separators = RegExp(
    r'[\u{2028}\u{2029}]',
    unicode: true,
  );

  static final RegExp _hidden = RegExp(
    r'(?![\t\n])[\p{Cc}\p{Cf}\p{Co}\u{FE00}-\u{FE0F}\u{E0100}-\u{E01EF}\u{FDD0}-\u{FDEF}\u{FFFE}\u{FFFF}\u{1FFFE}\u{1FFFF}\u{2FFFE}\u{2FFFF}\u{3FFFE}\u{3FFFF}\u{4FFFE}\u{4FFFF}\u{5FFFE}\u{5FFFF}\u{6FFFE}\u{6FFFF}\u{7FFFE}\u{7FFFF}\u{8FFFE}\u{8FFFF}\u{9FFFE}\u{9FFFF}\u{AFFFE}\u{AFFFF}\u{BFFFE}\u{BFFFF}\u{CFFFE}\u{CFFFF}\u{DFFFE}\u{DFFFF}\u{EFFFE}\u{EFFFF}\u{FFFFE}\u{FFFFF}\u{10FFFE}\u{10FFFF}\u{115F}\u{1160}\u{2800}\u{3164}\u{FFA0}\u{034F}]',
    unicode: true,
  );

  static final RegExp _markRun = RegExp(
    '(\\p{M}{$maxMarks})\\p{M}+',
    unicode: true,
  );

  @override
  String toString() =>
      'ChatEntry(#$index, ${author.name}, ${unreadable
          ? 'unreadable'
          : awaitingPeerKey
          ? 'awaiting key'
          : 'text'})';
}

/// What is known of the peer's key for the chat of a trade.
@immutable
sealed class ChatPeerKeyState {
  const ChatPeerKeyState();
}

/// No key yet (the coordinator gives none, or one that cannot be read, before any was pinned): the reference shows « Waiting for peer... » and sends nothing.
final class ChatPeerKeyAwaited extends ChatPeerKeyState {
  const ChatPeerKeyAwaited();

  @override
  String toString() => 'ChatPeerKeyAwaited()';
}

/// The key pinned for the trade at its first read, named after the peer's hash id ([ChatPeerKeyOfPeer]): messages are encrypted to it and the peer's are checked with it.
final class ChatPeerKeyPinned extends ChatPeerKeyState {
  final PgpPublicKey key;

  const ChatPeerKeyPinned(this.key);

  @override
  String toString() => 'ChatPeerKeyPinned(${key.fingerprint})';
}

/// The coordinator gave a key that is not the peer's by its name ([ChatPeerKeyMisnamed]), or, once one was pinned, another key, none, or one that cannot be read (`TradeKeyChanged`, design note § 3.4), or a key that does not verify a message of the peer read with it in the page that pinned it (the history read again after a restart): nothing is sent any more in this chat, and the screen says so.
final class ChatPeerKeyBreach extends ChatPeerKeyState {
  /// The key pinned before, when there was one.
  final PgpPublicKey? pinned;

  const ChatPeerKeyBreach({this.pinned});

  @override
  String toString() => 'ChatPeerKeyBreach(${pinned?.fingerprint})';
}

/// A message this robot posted whose outcome is not known: not shown by the coordinator as stored; it may still reach the peer (`AGENTS.md`, never « not sent » nor « failed »).
@immutable
final class ChatPendingMessage {
  /// Its number among the messages this robot sent in this chat, to send it again.
  final int id;

  /// The text sent, as typed: shown in its place.
  final String text;

  /// When it was sent.
  final DateTime sentAt;

  const ChatPendingMessage(this.id, this.text, this.sentAt);

  @override
  String toString() => 'ChatPendingMessage($id)';
}

/// The chat of a trade as the screen shows it: its messages by index, what is known of the peer, and what the last reads said.
@immutable
final class ChatView {
  /// The messages in index order.
  final List<ChatEntry> entries;

  /// Messages this robot posted that the coordinator does not show as stored.
  final List<ChatPendingMessage> pending;

  final ChatPeerKeyState peerKey;

  /// Whether the coordinator says the peer made a request in the last minute (`ChatPage.peerConnected`); `false` before any read.
  final bool peerConnected;

  /// Whether a read of the chat succeeded since the screen opened: the reference's « You: connected ».
  final bool connected;

  /// This robot's public key, once a read needed it: to compare with the peer outside the app.
  final PgpPublicKey? ownKey;

  /// The history from the start is larger than a read takes (`ChatPageTooLarge`): the screen says so, and reads only the newer messages on the user's choice ([skippedEarlier]).
  final bool historyTooLarge;

  /// The user chose to read only the messages after the order's last chat index: the earlier ones are not shown.
  final bool skippedEarlier;

  /// The last page read was not contiguous or repeated an index: a message may be missing or shown again.
  final bool incomplete;

  const ChatView({
    this.entries = const [],
    this.pending = const [],
    this.peerKey = const ChatPeerKeyAwaited(),
    this.peerConnected = false,
    this.connected = false,
    this.ownKey,
    this.historyTooLarge = false,
    this.skippedEarlier = false,
    this.incomplete = false,
  });

  /// Whether a message may be sent: the peer's key pinned, and no breach.
  bool get canSend => peerKey is ChatPeerKeyPinned;

  @override
  String toString() =>
      'ChatView(${entries.length} messages, ${pending.length} pending, $peerKey)';
}

/// Why a read of the chat gave nothing new: the screen keeps what it shows and says it.
@immutable
sealed class ChatReadFailure extends Failure {
  const ChatReadFailure();
}

/// The status shown has no order read, or is not one where the chat is read (9, 10, 11, 16): nothing was asked.
final class ChatNotOpen extends ChatReadFailure {
  const ChatNotOpen();
}

/// The trade could not be opened from its records, or the robot's key could not be had: [cause] says why.
final class ChatTradeUnavailable extends ChatReadFailure {
  final Failure cause;

  const ChatTradeUnavailable(this.cause);
}

/// The coordinator could not be read: [cause] is a `CoordinatorFailure` or a `P2pFailure`, never its text.
final class ChatReadFailed extends ChatReadFailure {
  final Failure cause;

  const ChatReadFailed(this.cause);
}

/// Why « Read only the newer messages » could not skip the earlier messages yet (#93): nothing was skipped.
@immutable
sealed class ChatSkipRefusal extends Failure {
  const ChatSkipRefusal();
}

/// The order shown was read before the messages there are to skip: its last chat index (0 for a chat that was empty) is not past what is read, so the order must be read again first.
final class ChatSkipNeedsOrderRead extends ChatSkipRefusal {
  const ChatSkipNeedsOrderRead();
}

/// Why a message was not sent, said before anything leaves (#93).
@immutable
sealed class ChatSendRefusal extends Failure {
  const ChatSendRefusal();
}

/// The text is empty, or only spaces.
final class ChatTextEmpty extends ChatSendRefusal {
  const ChatTextEmpty();
}

/// The text takes more than `OutgoingChatMessage.maxTextBytes` bytes.
final class ChatTextTooLong extends ChatSendRefusal {
  const ChatTextTooLong();
}

/// The text holds the robot's token: the reference blocks it (`EncryptedApiChat/index.tsx:209-214`).
final class ChatTextHoldsToken extends ChatSendRefusal {
  const ChatTextHoldsToken();
}

/// The text holds a Garage Key (`robo1…`), which controls every robot derived from it.
final class ChatTextHoldsGarageKey extends ChatSendRefusal {
  const ChatTextHoldsGarageKey();
}

/// The peer's key is not known yet: the reference sends nothing either (« Waiting for peer... »).
final class ChatPeerKeyNotKnown extends ChatSendRefusal {
  const ChatPeerKeyNotKnown();
}

/// The peer's key changed, or is not the peer's by its name ([ChatPeerKeyBreach]): nothing is sent any more in this chat.
final class ChatPeerKeyChanged extends ChatSendRefusal {
  const ChatPeerKeyChanged();
}

/// The status shown is not one where a message is posted (9, 10), or has no order read.
final class ChatClosed extends ChatSendRefusal {
  const ChatClosed();
}

/// The trade could not be opened, or the robot's key could not be had: [cause] says why; nothing was sent.
final class ChatSendUnavailable extends ChatSendRefusal {
  final Failure cause;

  const ChatSendUnavailable(this.cause);
}

/// The coordinator refused the message before storing it, or this client refused it from the last read ([fromLastRead]: read the order again before saying more): [cause] is the kind, never its text.
final class ChatSendRefused extends ChatSendRefusal {
  final Failure cause;
  final bool fromLastRead;

  const ChatSendRefused(this.cause, {this.fromLastRead = false});
}

/// What a message posted gave.
@immutable
sealed class ChatSent {
  const ChatSent();
}

/// The coordinator shows the message as stored, at [index].
final class ChatSentStored extends ChatSent {
  final int index;

  const ChatSentStored(this.index);
}

/// The coordinator does not show the message as stored: it may still reach the peer ([ChatPendingMessage]); sending it again sends the same encrypted message.
final class ChatSentNotConfirmed extends ChatSent {
  final ChatPendingMessage pending;

  const ChatSentNotConfirmed(this.pending);
}
