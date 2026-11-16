import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/coordinator_order.dart';
import 'package:robosats/src/coordinator/nostr_relay.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';
import 'package:robosats/src/nostr/gift_wrap.dart';
import 'package:robosats/src/nostr/nip44.dart';
import 'package:robosats/src/nostr/nostr_event.dart';
import 'package:robosats/src/nostr_key_pair.dart';
import 'package:robosats/src/robosats_failure.dart';
import 'package:robosats/src/robot_identity.dart';

/// A chat message ready to publish over Nostr, as the official client also publishes every message it posts to the coordinator (`sendToNostr`, `frontend/src/components/TradeBox/EncryptedChat/index.tsx:211-239`, commit ff1998c): two NIP-59 gift wraps of one NIP-17 rumor, one for the peer and one for the robot itself.
///
/// The rumor is the reference's, field for field: kind 14, the text as content, `created_at` the current second rounded up (`Math.ceil(Date.now() / 1000)`), and the tags `['order_id', '<shortAlias>/<orderId>']`, `['p', <peer key>, <relay>]`, `['p', <own key>, <relay>]` in that order; the relay is the coordinator's (`getRelayUrl`, `frontend/src/models/Coordinator.model.ts:374-378`).
/// The official client shows such a message only when it comes from the robot's Nostr key the coordinator holds, and every `p` tag names one of the order's two keys (`EncryptedNostrChat/index.tsx:113-122`): [compose] refuses to build anything else.
///
/// Publishing the same value again publishes the same two events, which relays and the official client count once (same ids).
/// It holds the text encrypted only, and prints nothing of it.
@immutable
final class OutgoingNostrChatMessage implements NostrRelayPublication {
  /// The kind of a NIP-17 chat message.
  static const int chatMessageKind = 14;

  /// The largest event a coordinator's relay takes, in bytes of JSON: `maxEventSize` of `docker/strfry/strfry.conf` in the reference.
  static const int maxEventBytes = 65536;

  /// The largest rumor, in bytes of JSON, that keeps each wrap within [maxEventBytes] (each wrap is about 1.8 times its rumor).
  static const int _maxRumorBytes = 32768;

  /// The two `["EVENT", <gift wrap>]` messages to send to a relay: the peer's first, then the robot's own, the order of the reference.
  @override
  final List<String> relayMessages;

  /// The ids of the two gift wraps, in the order of [relayMessages]: what a relay's `OK` names.
  @override
  final List<String> eventIds;

  OutgoingNostrChatMessage._(List<NostrEvent> wraps)
    : relayMessages = List.unmodifiable([
        for (final wrap in wraps) '["EVENT",${wrap.toJson()}]',
      ]),
      eventIds = List.unmodifiable([for (final wrap in wraps) wrap.id]);

  /// Whether [publicKeyHex] is a Nostr public key a copy can be written to: 64 hexadecimal characters, the X coordinate of a curve point (the all-zero placeholder is not).
  static bool isNostrPublicKey(String publicKeyHex) =>
      Nip44.isPublicKey(publicKeyHex);

  /// The relay of [coordinator] on [network], `ws://<onion>/relay/` as `getRelayUrl` writes it, or `null` when it has no onion address there.
  static Uri? relayUrl(Coordinator coordinator, RobosatsNetwork network) {
    final onion = coordinator.origins(network).onion;
    if (onion == null) return null;
    final protocol = onion.contains('https') ? 'wss://' : 'ws://';
    return Uri.parse(
      '${onion.replaceFirst(RegExp(r'^https?://'), protocol)}/relay/',
    );
  }

  /// [text], sent by the robot [identity] in the chat of [order] on [coordinator], wrapped for the peer and for the robot.
  ///
  /// [now] is the clock of the device; [random] is [Random.secure] in the app (nonces, signatures, throwaway keys, dates).
  /// Nothing is built when the order lacks one of the two Nostr keys ([NostrChatKeyMissing]), when the key it gives for this robot is not the robot's ([NostrChatKeyNotOurs]), or when the coordinator has no relay on [network] ([NostrChatNoRelay]).
  static Result<OutgoingNostrChatMessage, NostrChatFailure> compose({
    required RobotIdentity identity,
    required CoordinatorOrder order,
    required Coordinator coordinator,
    required RobosatsNetwork network,
    required String text,
    required DateTime now,
    required Random random,
  }) => composeFor(
    identity.nostrKeyPair(),
    order: order,
    coordinator: coordinator,
    network: network,
    text: text,
    now: now,
    random: random,
  );

  /// [compose] from the robot's Nostr key pair [sender] alone, the robot's `NostrKeyDerivation.currentFrontend` key: what an isolate is given, so that the robot's token never goes there.
  static Result<OutgoingNostrChatMessage, NostrChatFailure> composeFor(
    NostrKeyPair sender, {
    required CoordinatorOrder order,
    required Coordinator coordinator,
    required RobosatsNetwork network,
    required String text,
    required DateTime now,
    required Random random,
  }) {
    final makerKey = order.makerNostrPublicKeyHex;
    final takerKey = order.takerNostrPublicKeyHex;
    // A key that is no curve point, the all-zero placeholder of a coordinator for instance, cannot be written to: the official client's `wrapEvent` throws on it and nothing is sent.
    if (makerKey == null ||
        takerKey == null ||
        !Nip44.isPublicKey(makerKey) ||
        !Nip44.isPublicKey(takerKey)) {
      return const Err(NostrChatKeyMissing());
    }
    final ownKey = order.isMaker ? makerKey : takerKey;
    final peerKey = order.isMaker ? takerKey : makerKey;
    if (ownKey != sender.publicKeyHex) return const Err(NostrChatKeyNotOurs());
    final relay = relayUrl(coordinator, network);
    if (relay == null) return const Err(NostrChatNoRelay());

    final milliseconds = now.millisecondsSinceEpoch;
    final rumor = NostrEvent.rumor(
      kind: chatMessageKind,
      content: text,
      createdAt: (milliseconds / 1000).ceil(),
      tags: [
        ['order_id', '${coordinator.shortAlias}/${order.id}'],
        ['p', peerKey, '$relay'],
        ['p', ownKey, '$relay'],
      ],
      pubkey: sender.publicKeyHex,
    );
    if (utf8.encode(rumor.toJson()).length > _maxRumorBytes) {
      return const Err(NostrChatMessageTooLarge());
    }
    final nowSeconds = milliseconds ~/ 1000;
    final wraps = [
      for (final recipient in [peerKey, ownKey])
        NostrGiftWrap.wrap(
          rumor,
          sender,
          recipient,
          nowSeconds: nowSeconds,
          random: random,
        ),
    ];
    if (wraps.any(
      (wrap) => utf8.encode(wrap.toJson()).length > maxEventBytes,
    )) {
      return const Err(NostrChatMessageTooLarge());
    }
    return Ok(OutgoingNostrChatMessage._(wraps));
  }

  @override
  String toString() => 'OutgoingNostrChatMessage(${eventIds.length} events)';
}
