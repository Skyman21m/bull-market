import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:meta/meta.dart';
import 'package:robosats/src/nostr/nip44.dart';
import 'package:robosats/src/nostr/nostr_event.dart';
import 'package:robosats/src/nostr/schnorr.dart';
import 'package:robosats/src/secp256k1.dart';

/// A Nostr identity: a secp256k1 secret key and its BIP340 x-only public key.
@immutable
final class NostrKeyPair {
  final Uint8List _secretKey;

  /// The x-only public key: 64 lowercase hexadecimal characters, as `getPublicKey` of `nostr-tools` returns it.
  late final String publicKeyHex = hex.encode(
    xOnlyPublicKey(bigIntFromBytes(_secretKey)),
  );

  NostrKeyPair._(this._secretKey);

  /// Wraps a 32-byte secret key produced by one of the RoboSats derivations.
  ///
  /// Every caller passes a SHA-256 digest, which falls outside the valid range with probability below 2^-127: that case throws a [StateError], as `nostr-tools` throws in RoboSats.
  @internal
  factory NostrKeyPair.fromSecretKey(List<int> secretKey) {
    if (secretKey.length != 32 ||
        !isValidSecretScalar(bigIntFromBytes(secretKey))) {
      throw StateError('derived Nostr secret key out of range');
    }
    return NostrKeyPair._(Uint8List.fromList(secretKey));
  }

  /// A new key pair drawn from [random], a secure source: the throwaway key of one NIP-59 gift wrap, as `generateSecretKey` of `nostr-tools` makes a new one for each wrap.
  @internal
  factory NostrKeyPair.generate(Random random) {
    while (true) {
      final candidate = List<int>.generate(32, (_) => random.nextInt(256));
      if (isValidSecretScalar(bigIntFromBytes(candidate))) {
        return NostrKeyPair._(Uint8List.fromList(candidate));
      }
    }
  }

  /// A copy of the 32-byte secret key: never log, display or send it.
  Uint8List revealSecretKey() => Uint8List.fromList(_secretKey);

  /// The NIP-44 conversation key of this key and the x-only public key [publicKeyHex], so that the secret key stays here.
  ///
  /// Throws [ArgumentError] when [publicKeyHex] is not the X coordinate of a curve point.
  @internal
  Uint8List conversationKeyWith(String publicKeyHex) =>
      Nip44.conversationKey(_secretKey, publicKeyHex);

  /// The event of these fields, signed by this key: its id ([NostrEvent.idOf]) signed with BIP-340, [aux] being 32 bytes of a secure source.
  @internal
  NostrEvent sign({
    required int kind,
    required String content,
    required int createdAt,
    required List<List<String>> tags,
    required List<int> aux,
  }) {
    final id = NostrEvent.idOf(publicKeyHex, createdAt, kind, tags, content);
    final signature = Bip340.sign(_secretKey, hex.decode(id), aux);
    return NostrEvent.signed(
      kind: kind,
      content: content,
      createdAt: createdAt,
      tags: tags,
      pubkey: publicKeyHex,
      id: id,
      signature: hex.encode(signature),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NostrKeyPair && other.publicKeyHex == publicKeyHex;

  @override
  int get hashCode => publicKeyHex.hashCode;

  @override
  String toString() => 'NostrKeyPair(publicKeyHex: $publicKeyHex)';
}
