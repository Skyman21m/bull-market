import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:robosats/src/nostr/gift_wrap.dart';
import 'package:robosats/src/nostr/nip44.dart';
import 'package:robosats/src/nostr/nostr_event.dart';
import 'package:robosats/src/nostr/schnorr.dart';
import 'package:robosats/src/nostr_key_pair.dart';
import 'package:robosats/src/secp256k1.dart';

/// The reading of a NIP-59 gift wrap received from a relay, as `unwrapEvent` of `nip59.ts` in `nostr-tools` reads it (2.25.2, the same function in 2.26.0, which the official client locks at RoboSats commit babf62e).
///
/// Its checks, in its order: the wrap is of kind 1059; its content decrypts with NIP-44 from the wrap's `pubkey` to the recipient; the seal is of kind 13 and passes `verifyEvent` (its fields of the types `validateEvent` asks for, its `pubkey` in lowercase hexadecimal, its id recomputed from its fields and equal to the lowercase hash, its BIP-340 signature by its `pubkey`, in either case as `hexToBytes` of `@noble/hashes` reads it); the seal's content decrypts from the seal's `pubkey` to the recipient; the rumor names the seal's `pubkey` as its own.
/// Like `unwrapEvent`, it checks neither the wrap's signature (a throwaway key's), nor its `p` tag, nor the rumor's id: a caller that needs them checks them.
/// Stricter than `verifyEvent` in one point: the seal's `kind` and `created_at` must be JSON integers, which every seal `nostr-tools` makes has.
///
/// Everything it reads comes from a relay to be taken as hostile: it never throws on what it reads, and keeps nothing of it but the rumor it returns.
abstract final class NostrGiftUnwrap {
  static final RegExp _lowercaseHex32 = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _hex64 = RegExp(r'^[0-9a-fA-F]{128}$');
  static final BigInt _fieldPrime = BigInt.parse(
    'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f',
    radix: 16,
  );

  /// The rumor of [wrap], a gift wrap decoded from its JSON, read with [recipient]'s key, or `null` when any check fails.
  ///
  /// With [sealAuthor], a seal of any other `pubkey` is refused before its signature is checked: the caller that keeps only the rumors of one author (`rumor.pubkey === seal.pubkey === sealAuthor`) gets the same rumors, without checking a signature it would drop anyway.
  /// The rumor is the decoded JSON object of the seal's content, unchecked beyond its `pubkey`.
  static Map<String, Object?>? unwrap(
    Map<String, Object?> wrap,
    NostrKeyPair recipient, {
    String? sealAuthor,
  }) {
    if (wrap['kind'] != NostrGiftWrap.giftWrapKind) return null;
    final seal = _decryptedObject(wrap, recipient);
    if (seal == null || seal['kind'] != NostrGiftWrap.sealKind) return null;
    if (sealAuthor != null && seal['pubkey'] != sealAuthor) return null;
    if (!_verifies(seal)) return null;
    final rumor = _decryptedObject(seal, recipient);
    if (rumor == null || rumor['pubkey'] != seal['pubkey']) return null;
    return rumor;
  }

  /// The JSON object encrypted in [event]'s content from [event]'s `pubkey` to [recipient], or `null`.
  static Map<String, Object?>? _decryptedObject(
    Map<String, Object?> event,
    NostrKeyPair recipient,
  ) {
    final content = event['content'];
    final sender = event['pubkey'];
    // A `pubkey` that is not the X coordinate of a curve point is refused before the conversation key, which would throw an `ArgumentError` for it: nothing here catches an `Error` (rule 11 of `AGENTS.md`, #314).
    if (content is! String || sender is! String || !Nip44.isPublicKey(sender)) {
      return null;
    }
    try {
      final plaintext = Nip44.decrypt(
        content,
        recipient.conversationKeyWith(sender),
      );
      final decoded = jsonDecode(plaintext);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Whether [event] passes `verifyEvent` of `nostr-tools`: its fields of the types `validateEvent` asks for, its id recomputed from them, its signature by its `pubkey`.
  static bool _verifies(Map<String, Object?> event) {
    final kind = event['kind'];
    final content = event['content'];
    final createdAt = event['created_at'];
    final pubkey = event['pubkey'];
    final rawTags = event['tags'];
    final id = event['id'];
    final signature = event['sig'];
    if (kind is! int ||
        content is! String ||
        createdAt is! int ||
        pubkey is! String ||
        !_lowercaseHex32.hasMatch(pubkey) ||
        rawTags is! List<Object?> ||
        id is! String ||
        signature is! String ||
        !_hex64.hasMatch(signature)) {
      return false;
    }
    final tags = <List<String>>[];
    for (final tag in rawTags) {
      if (tag is! List<Object?> || tag.any((value) => value is! String)) {
        return false;
      }
      tags.add(tag.cast<String>());
    }
    final computed = NostrEvent.idOf(pubkey, createdAt, kind, tags, content);
    if (computed != id) return false;
    final signatureBytes = hex.decode(signature);
    if (!_verifiable(pubkey, signatureBytes)) return false;
    return Bip340.verify(
      hex.decode(pubkey),
      hex.decode(computed),
      signatureBytes,
    );
  }

  /// Whether [pubkey] and [signature] pass the checks `schnorrVerify` of `@noble/curves` makes before any curve arithmetic: the key lifts to a curve point, `r` is in `1..p-1` and `s` in `1..n-1`.
  ///
  /// The `bip340` package makes the first two checks itself (`r ≥ p`, `s ≥ n`, a key it cannot lift: `false`) but takes `r` or `s` of zero; with these checks, the only input left on which one of its non-null assertions (`P * e`) could fail is a challenge `e` of zero modulo `n`, which takes a SHA-256 preimage to make, so its call is not wrapped in a `catch`.
  static bool _verifiable(String pubkey, List<int> signature) {
    final r = bigIntFromBytes(signature.sublist(0, 32));
    final s = bigIntFromBytes(signature.sublist(32));
    return Nip44.isPublicKey(pubkey) &&
        r > BigInt.zero &&
        r < _fieldPrime &&
        s > BigInt.zero &&
        s < secp256k1Order;
  }
}
