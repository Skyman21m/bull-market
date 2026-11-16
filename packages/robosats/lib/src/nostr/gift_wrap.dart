import 'dart:math';

import 'package:robosats/src/nostr/nip44.dart';
import 'package:robosats/src/nostr/nostr_event.dart';
import 'package:robosats/src/nostr_key_pair.dart';

/// NIP-59 gift wraps, as `wrapEvent` of `nip59.ts` in `nostr-tools` 2.25.2 makes them.
///
/// - The seal, kind 13, no tags, holds the rumor encrypted with NIP-44 from the sender to the recipient, and is signed by the sender.
/// - The wrap, kind 1059, one tag `['p', recipient]`, holds the seal encrypted with NIP-44 from a throwaway key, new for each wrap, to the recipient, and is signed by that throwaway key.
/// - The seal and the wrap are dated each at a random moment of the last two days (`randomNow`); never in the future, so that a relay that refuses events from the future takes them.
///
/// Every random byte (NIP-44 nonces, signature aux, throwaway key, dates) comes from the [Random] the caller passes: [Random.secure] in the app.
abstract final class NostrGiftWrap {
  static const int sealKind = 13;
  static const int giftWrapKind = 1059;

  /// How far back a seal or a wrap may be dated, in seconds: two days, `TWO_DAYS` of `nip59.ts`.
  static const int maxBackdating = 2 * 24 * 60 * 60;

  /// [rumor] wrapped for [recipientPublicKeyHex] by [sender], whose key must be the rumor's author, at [nowSeconds] (Unix time, rounded down).
  static NostrEvent wrap(
    NostrEvent rumor,
    NostrKeyPair sender,
    String recipientPublicKeyHex, {
    required int nowSeconds,
    required Random random,
  }) {
    if (rumor.sig != null || rumor.pubkey != sender.publicKeyHex) {
      throw ArgumentError('a rumor of the sender is wrapped, unsigned');
    }
    final seal = sender.sign(
      kind: sealKind,
      content: Nip44.encrypt(
        rumor.toJson(),
        sender.conversationKeyWith(recipientPublicKeyHex),
        _bytes(random, 32),
      ),
      createdAt: _backdated(nowSeconds, random),
      tags: const [],
      aux: _bytes(random, 32),
    );
    final throwaway = NostrKeyPair.generate(random);
    return throwaway.sign(
      kind: giftWrapKind,
      content: Nip44.encrypt(
        seal.toJson(),
        throwaway.conversationKeyWith(recipientPublicKeyHex),
        _bytes(random, 32),
      ),
      createdAt: _backdated(nowSeconds, random),
      tags: [
        ['p', recipientPublicKeyHex],
      ],
      aux: _bytes(random, 32),
    );
  }

  static int _backdated(int nowSeconds, Random random) {
    final draw = _bytes(
      random,
      4,
    ).fold<int>(0, (value, byte) => value << 8 | byte);
    return nowSeconds - draw % (maxBackdating + 1);
  }

  static List<int> _bytes(Random random, int count) =>
      List<int>.generate(count, (_) => random.nextInt(256));
}
