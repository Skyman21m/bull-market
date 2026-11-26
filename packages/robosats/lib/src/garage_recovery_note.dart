import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/nostr_relay.dart';
import 'package:robosats/src/garage_key.dart';
import 'package:robosats/src/nostr/gift_unwrap.dart';
import 'package:robosats/src/nostr/gift_wrap.dart';
import 'package:robosats/src/nostr/nostr_event.dart';
import 'package:robosats/src/nostr_key_pair.dart';
import 'package:robosats/src/robosats_failure.dart';

/// The recovery note of a Garage Key, as the official client writes and reads it: the index of the robot it last moved to, which it reads back when a Garage Key is entered (`frontend/src/utils/accountRecovery.ts`, `models/GarageKey.model.ts:89-119`, `services/RoboPool/index.ts:628-728`, commit babf62e).
///
/// The note is a NIP-59 gift wrap from the key's recovery identity to itself ([GarageKey.recoveryNostrKeyPair]); its rumor is of kind [kind], with the tags `['d', 'robosats-garage-account']` and `['account', <index in decimal>]` and an empty content.
/// The official client reads the notes of the recovery identity and of the legacy one ([GarageKey.legacyRecoveryNostrKeyPair]), and writes with the recovery identity only.
///
/// What the number read is worth: a note counts only when its seal is signed by one of the two identities, which only a holder of the Garage Key can do, so no relay and no third party can make up a number; but a relay chooses which notes it gives, so it can withhold the latest one (an older number, or none), and any holder of the key (another device, the official client, whoever has the key or the words it comes from) can write any index, dated at any time, the future included, which then wins as it does in the official client.
abstract final class GarageRecoveryNote {
  /// The kind of the rumor, `ACCOUNT_RECOVERY_KIND` of the reference: application-specific data (NIP-78), addressable.
  static const int kind = 30078;

  /// The value of the rumor's `d` tag, `D_TAG_VALUE` of the reference.
  static const String dTagValue = 'robosats-garage-account';

  /// How many events [latestAccount] looks at, at most: the first ones of the list given, every one counted, duplicates and refused ones included; the others are ignored.
  ///
  /// Twice what a coordinator's relay of the reference gives for one request (`docker/strfry/strfry.conf:81-82`, 500).
  static const int maxEvents = 1000;

  /// The longest event [latestAccount] reads, in UTF-16 code units of its JSON: the largest event a coordinator's relay of the reference takes (`maxEventSize`, 65,536 bytes, `docker/strfry/strfry.conf:21`); a longer one is ignored before it is decoded.
  static const int maxEventLength = 65536;

  static final RegExp _canonicalDecimal = RegExp(r'^(0|[1-9][0-9]*)$');

  /// The note of [key] that says [accountIndex], written at [now], as `createAccountRecoveryEvent` writes it.
  ///
  /// [random] is [Random.secure] in the app (the NIP-44 nonces, the signatures' aux, the throwaway key, the dates of the seal and the wrap).
  /// Fails with [AccountIndexOutOfRange] when [accountIndex] is not a robot index (0 to [GarageKey.maxAccountIndex]), where the reference throws.
  static Result<OutgoingGarageRecoveryNote, AccountIndexOutOfRange> compose(
    GarageKey key, {
    required int accountIndex,
    required DateTime now,
    required Random random,
  }) => composeFor(
    key.recoveryNostrKeyPair,
    accountIndex: accountIndex,
    now: now,
    random: random,
  );

  /// [compose] from the recovery identity [identity] alone, for an isolate that must not receive the Garage Key.
  ///
  /// The rumor's `created_at` is [now] rounded down to the second (`Math.floor(Date.now() / 1000)`); the seal and the wrap are dated as `NostrGiftWrap.wrap` dates them, at random within the two days before.
  static Result<OutgoingGarageRecoveryNote, AccountIndexOutOfRange> composeFor(
    NostrKeyPair identity, {
    required int accountIndex,
    required DateTime now,
    required Random random,
  }) {
    if (accountIndex < 0 || accountIndex > GarageKey.maxAccountIndex) {
      return const Err(AccountIndexOutOfRange());
    }
    final milliseconds = now.millisecondsSinceEpoch;
    final rumor = NostrEvent.rumor(
      kind: kind,
      content: '',
      createdAt: (milliseconds / 1000).floor(),
      tags: [
        ['d', dTagValue],
        ['account', '$accountIndex'],
      ],
      pubkey: identity.publicKeyHex,
    );
    return Ok(
      OutgoingGarageRecoveryNote._(
        NostrGiftWrap.wrap(
          rumor,
          identity,
          identity.publicKeyHex,
          nowSeconds: (milliseconds / 1000).floor(),
          random: random,
        ),
      ),
    );
  }

  /// The two requests the official client makes to a relay for the notes of [key]: the recovery identity's, then the legacy one's.
  static List<GarageRecoveryFilter> filters(GarageKey key) =>
      List.unmodifiable([
        GarageRecoveryFilter._(key.recoveryNostrKeyPair.publicKeyHex),
        GarageRecoveryFilter._(key.legacyRecoveryNostrKeyPair.publicKeyHex),
      ]);

  /// The robot index of the latest note of [key] among [events], or `null` when none counts.
  ///
  /// [events] are the JSON texts of the events relays answered to [filters], each as received: from any relay, in any order, duplicates included.
  /// Reads the notes of the recovery identity and of the legacy one, as the official client does; see [latestAccountFor].
  static int? latestAccount(GarageKey key, Iterable<String> events) =>
      latestAccountFor([
        key.recoveryNostrKeyPair,
        key.legacyRecoveryNostrKeyPair,
      ], events);

  /// [latestAccount] with the identities [identities] in place of a Garage Key, for an isolate that must not receive it.
  ///
  /// A note counts for an identity when its wrap has a `p` tag naming it (what the filter of that identity returns), it unwraps with that identity's key as `unwrapEvent` unwraps it ([NostrGiftUnwrap]), its rumor is that identity's (`RoboPool/index.ts:684-685`), and the rumor reads as `parseAccountRecoveryEvent` reads it (`accountRecovery.ts:32-53`): kind [kind], the first `d` tag [dTagValue], the first `account` tag a canonical decimal (no sign, no leading zero) of a robot index; the content is not read, as in the reference.
  /// Two points are stricter than the reference, where only a holder of the key could make a note differ: every tag of the rumor must be a list of strings, and its `created_at` an integer of at least 0.
  /// The choice is the reference's: the latest rumor `created_at`, the larger index on a tie, whichever identity wrote it; a note dated in the future is not set apart.
  /// Everything else is ignored, without an exception or a log; at most [maxEvents] events are looked at, and none longer than [maxEventLength].
  static int? latestAccountFor(
    List<NostrKeyPair> identities,
    Iterable<String> events,
  ) {
    final seen = <String>{};
    ({int createdAt, int accountIndex})? latest;
    var looked = 0;
    for (final text in events) {
      if (looked == maxEvents) break;
      looked++;
      if (text.length > maxEventLength || !seen.add(text)) continue;
      final wrap = _decodedObject(text);
      if (wrap == null) continue;
      for (final identity in identities) {
        final note = _noteOf(wrap, identity);
        final current = latest;
        if (note != null &&
            (current == null ||
                note.createdAt > current.createdAt ||
                (note.createdAt == current.createdAt &&
                    note.accountIndex > current.accountIndex))) {
          latest = note;
        }
      }
    }
    return latest?.accountIndex;
  }

  static Map<String, Object?>? _decodedObject(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// The note [wrap] carries for [identity], or `null`.
  static ({int createdAt, int accountIndex})? _noteOf(
    Map<String, Object?> wrap,
    NostrKeyPair identity,
  ) {
    if (!_addressedTo(wrap, identity.publicKeyHex)) return null;
    final rumor = NostrGiftUnwrap.unwrap(wrap, identity);
    if (rumor == null || rumor['pubkey'] != identity.publicKeyHex) return null;
    final accountIndex = _accountIndexOf(rumor);
    final createdAt = rumor['created_at'];
    if (accountIndex == null || createdAt is! int || createdAt < 0) {
      return null;
    }
    return (createdAt: createdAt, accountIndex: accountIndex);
  }

  /// Whether [wrap] has a `p` tag naming [publicKeyHex], as a relay matches `'#p'`.
  static bool _addressedTo(Map<String, Object?> wrap, String publicKeyHex) {
    final tags = wrap['tags'];
    if (tags is! List<Object?>) return false;
    return tags.any(
      (tag) =>
          tag is List<Object?> &&
          tag.length >= 2 &&
          tag[0] == 'p' &&
          tag[1] == publicKeyHex,
    );
  }

  /// The robot index [rumor] says, as `parseAccountRecoveryEvent` reads it, or `null`.
  static int? _accountIndexOf(Map<String, Object?> rumor) {
    if (rumor['kind'] != kind) return null;
    final rawTags = rumor['tags'];
    if (rawTags is! List<Object?>) return null;
    final tags = <List<String>>[];
    for (final tag in rawTags) {
      if (tag is! List<Object?> || tag.any((value) => value is! String)) {
        return null;
      }
      tags.add(tag.cast<String>());
    }
    if (_firstValue(tags, 'd') != dTagValue) return null;
    final account = _firstValue(tags, 'account');
    // Ten digits at most: the reference's `Number` of a longer one is out of range anyway, and `int.parse` of it could overflow.
    if (account == null ||
        account.length > 10 ||
        !_canonicalDecimal.hasMatch(account)) {
      return null;
    }
    final accountIndex = int.parse(account);
    return accountIndex <= GarageKey.maxAccountIndex ? accountIndex : null;
  }

  /// The second value of the first tag named [name], as `tags.find((t) => t[0] === name)?.[1]` gives it.
  static String? _firstValue(List<List<String>> tags, String name) {
    for (final tag in tags) {
      if (tag.isNotEmpty && tag[0] == name) {
        return tag.length > 1 ? tag[1] : null;
      }
    }
    return null;
  }
}

/// A recovery note ready to publish on a relay: one `["EVENT", <gift wrap>]`, as `publishAccountRecoveryEvent` sends it.
///
/// It prints nothing of the event, whose `p` tag names the key's recovery identity.
@immutable
final class OutgoingGarageRecoveryNote implements NostrRelayPublication {
  final NostrEvent _wrap;

  const OutgoingGarageRecoveryNote._(this._wrap);

  /// The gift wrap, for the tests.
  @visibleForTesting
  NostrEvent get wrap => _wrap;

  @override
  List<String> get relayMessages =>
      List.unmodifiable(['["EVENT",${_wrap.toJson()}]']);

  @override
  List<String> get eventIds => List.unmodifiable([_wrap.id]);

  @override
  String toString() => 'OutgoingGarageRecoveryNote';
}

/// One request of the official client for the notes of one identity of a Garage Key: `{"kinds":[1059],"#p":[<identity>]}`, without `limit` or `since` (`RoboPool/index.ts:663-670`).
///
/// It prints nothing of the identity, a fixed label of the Garage Key on every relay it is sent to.
@immutable
final class GarageRecoveryFilter {
  /// The identity's x-only public key, 64 lowercase hexadecimal characters.
  final String publicKeyHex;

  const GarageRecoveryFilter._(this.publicKeyHex);

  /// The filter's JSON, to send in a `["REQ", <subscription id>, <filter>]`.
  String toJson() => NostrEvent.stringify({
    'kinds': [NostrGiftWrap.giftWrapKind],
    '#p': [publicKeyHex],
  });

  @override
  bool operator ==(Object other) =>
      other is GarageRecoveryFilter && other.publicKeyHex == publicKeyHex;

  @override
  int get hashCode => publicKeyHex.hashCode;

  @override
  String toString() => 'GarageRecoveryFilter';
}
