import 'dart:convert';

import 'package:robosats/src/nostr/gift_unwrap.dart';
import 'package:robosats/src/nostr/gift_wrap.dart';
import 'package:robosats/src/nostr/nip44.dart';
import 'package:robosats/src/nostr/nostr_event.dart';
import 'package:robosats/src/nostr_key_pair.dart';
import 'package:test/test.dart';

import '../support/deterministic_random.dart';

/// `NostrGiftUnwrap` on its own, as `unwrapEvent` of `nip59.ts` (`nostr-tools` 2.25.2) reads a gift wrap, and with the author it is asked to keep.
void main() {
  final random = DeterministicRandom('gift unwrap');
  final recipient = NostrKeyPair.generate(DeterministicRandom('recipient'));
  final stranger = NostrKeyPair.generate(DeterministicRandom('stranger'));
  List<int> bytes32() => List<int>.generate(32, (_) => random.nextInt(256));

  NostrEvent rumorOf(NostrKeyPair author) => NostrEvent.rumor(
    kind: 14,
    content: 'hello',
    createdAt: 1767225600,
    tags: const [],
    pubkey: author.publicKeyHex,
  );

  /// A gift wrap to [recipient] of a seal signed by [sealer] around [rumor].
  Map<String, Object?> wrapOf(NostrEvent rumor, NostrKeyPair sealer) {
    final seal = sealer.sign(
      kind: NostrGiftWrap.sealKind,
      content: Nip44.encrypt(
        rumor.toJson(),
        sealer.conversationKeyWith(recipient.publicKeyHex),
        bytes32(),
      ),
      createdAt: 1767200000,
      tags: const [],
      aux: bytes32(),
    );
    final throwaway = NostrKeyPair.generate(random);
    return jsonDecode(
          throwaway
              .sign(
                kind: NostrGiftWrap.giftWrapKind,
                content: Nip44.encrypt(
                  seal.toJson(),
                  throwaway.conversationKeyWith(recipient.publicKeyHex),
                  bytes32(),
                ),
                createdAt: 1767210000,
                tags: [
                  ['p', recipient.publicKeyHex],
                ],
                aux: bytes32(),
              )
              .toJson(),
        )
        as Map<String, Object?>;
  }

  test('gives the rumor of any author whose seal signs it', () {
    final rumor = NostrGiftUnwrap.unwrap(
      wrapOf(rumorOf(stranger), stranger),
      recipient,
    );
    expect(rumor?['pubkey'], stranger.publicKeyHex);
    expect(rumor?['content'], 'hello');
  });

  test('refuses a rumor that names another key than its seal\'s', () {
    expect(
      NostrGiftUnwrap.unwrap(wrapOf(rumorOf(recipient), stranger), recipient),
      isNull,
    );
  });

  test('with an author to keep, refuses a seal of any other key', () {
    final wrap = wrapOf(rumorOf(stranger), stranger);
    expect(
      NostrGiftUnwrap.unwrap(
        wrap,
        recipient,
        sealAuthor: recipient.publicKeyHex,
      ),
      isNull,
    );
    expect(
      NostrGiftUnwrap.unwrap(
        wrap,
        recipient,
        sealAuthor: stranger.publicKeyHex,
      )?['pubkey'],
      stranger.publicKeyHex,
    );
  });
}
