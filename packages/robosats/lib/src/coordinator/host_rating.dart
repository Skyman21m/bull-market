import 'dart:math';

import 'package:meta/meta.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/nostr_relay.dart';
import 'package:robosats/src/nostr/nostr_event.dart';
import 'package:robosats/src/nostr_key_pair.dart';

/// The token a coordinator gives a robot to rate it over Nostr (`POST /api/review/`, `ReviewView` of `api/views.py:1236-1269`, commit ff1998c): its BIP-340 signature of the text `<robot's Nostr key><id of the robot's last order>` (`Nostr.sign_message`, `api/nostr.py:164-175`), which readers of the rating check (`verifyCoordinatorToken`, `frontend/src/utils/nostr.ts:131-149`).
///
/// Only its form is checked here, 128 lowercase hexadecimal characters, the `signature.hex()` of the reference: it goes as it is into a public event, so nothing else can be carried in it.
@immutable
final class HostReviewToken {
  /// The 64-byte signature in lowercase hexadecimal.
  final String hex;

  const HostReviewToken._(this.hex);

  static final RegExp _form = RegExp(r'^[0-9a-f]{128}$');

  /// The token of [value], or `null` when it is not a string of that form (the reference's `""` when its signature failed included).
  static HostReviewToken? parse(Object? value) =>
      value is String && _form.hasMatch(value)
      ? HostReviewToken._(value)
      : null;

  @override
  bool operator ==(Object other) =>
      other is HostReviewToken && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;

  @override
  String toString() => 'HostReviewToken';
}

/// The stars a robot gives its coordinator, « Rate your host » (`TradeBox/Prompts/Successful.tsx`, commit ff1998c).
@immutable
final class HostRating {
  static const min = 1;
  static const max = 5;

  /// The stars, [min] to [max].
  final int stars;

  const HostRating._(this.stars);

  /// The rating of [stars], or `null` outside [min] to [max].
  static HostRating? of(int stars) =>
      stars >= min && stars <= max ? HostRating._(stars) : null;

  /// The value of the event's `rating` tag, `String(hostRating / 5)` of the reference as JavaScript writes it: `0.2` to `0.8`, then `1` (never `1.0`).
  String get tagValue => const ['0.2', '0.4', '0.6', '0.8', '1'][stars - 1];

  @override
  bool operator ==(Object other) => other is HostRating && other.stars == stars;

  @override
  int get hashCode => stars.hashCode;

  @override
  String toString() => 'HostRating($stars)';
}

/// The rating of a coordinator by a robot, ready to publish on Nostr, as the official client publishes it at the end of a trade (`rateHostPlatform`, `frontend/src/components/TradeBox/Prompts/Successful.tsx:54-89`, commit ff1998c).
///
/// One event of kind [kind], field for field the reference's, its JSON in the order of the reference's template (`kind`, `created_at`, `tags`, `content`, `pubkey`, `id`, `sig`): `created_at` the current second rounded down (`Math.floor(Date.now() / 1000)`), an empty content, and the tags `['sig', <token>]`, `['d', '<shortAlias>:<orderId>']`, `['p', <coordinator's Nostr key>]`, `['rating', <stars / 5>]` in that order, signed by the robot's Nostr key.
/// The kind is in the range NIP-01 makes addressable (30000 to 39999): a relay keeps the latest event of a robot's key for one `d`, so a new rating of the same order replaces the earlier one.
/// It is public: anyone reading the relays learns that this robot's Nostr key rated this coordinator for this order, with these stars.
@immutable
final class OutgoingHostRating implements NostrRelayPublication {
  /// The kind of a coordinator's rating in RoboSats.
  static const int kind = 31986;

  final NostrEvent _event;

  OutgoingHostRating._(this._event);

  /// The rating [rating] of [coordinator] for the order [orderId], signed by the robot's Nostr key pair [sender] with the [token] the coordinator gave it.
  ///
  /// [now] is the clock of the device; [random] is [Random.secure] in the app (the signature's aux).
  static OutgoingHostRating compose(
    NostrKeyPair sender, {
    required HostReviewToken token,
    required Coordinator coordinator,
    required int orderId,
    required HostRating rating,
    required DateTime now,
    required Random random,
  }) => OutgoingHostRating._(
    sender.sign(
      kind: kind,
      content: '',
      createdAt: now.millisecondsSinceEpoch ~/ 1000,
      tags: [
        ['sig', token.hex],
        ['d', '${coordinator.shortAlias}:$orderId'],
        ['p', coordinator.nostrHexPubkey],
        ['rating', rating.tagValue],
      ],
      aux: List<int>.generate(32, (_) => random.nextInt(256)),
      fullTemplate: true,
    ),
  );

  /// The signed event, for the tests.
  @visibleForTesting
  NostrEvent get event => _event;

  @override
  List<String> get relayMessages =>
      List.unmodifiable(['["EVENT",${_event.toJson()}]']);

  @override
  List<String> get eventIds => List.unmodifiable([_event.id]);

  @override
  String toString() => 'OutgoingHostRating';
}
