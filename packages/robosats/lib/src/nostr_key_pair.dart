import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:meta/meta.dart';
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

  /// A copy of the 32-byte secret key: never log, display or send it.
  Uint8List revealSecretKey() => Uint8List.fromList(_secretKey);

  @override
  bool operator ==(Object other) =>
      other is NostrKeyPair && other.publicKeyHex == publicKeyHex;

  @override
  int get hashCode => publicKeyHex.hashCode;

  @override
  String toString() => 'NostrKeyPair(publicKeyHex: $publicKeyHex)';
}
