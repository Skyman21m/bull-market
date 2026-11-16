import 'dart:typed_data';

import 'package:bip340/bip340.dart' as bip340;
import 'package:convert/convert.dart';
import 'package:robosats/src/secp256k1.dart';

/// BIP-340 Schnorr signatures of 32-byte digests, the signatures of Nostr events, through the `bip340` package (fiatjaf).
///
/// The one place this package calls `bip340`: the tests replay the official BIP-340 vectors through it (`test/fixtures/nostr/bip340-test-vectors.csv`).
abstract final class Bip340 {
  /// The 64-byte signature of [digest] by [secretKey], with the 32 bytes [aux] that BIP-340 mixes into the nonce (drawn from a secure source at each signature, as `nostr-tools` does).
  ///
  /// The signature is verified before it is returned: a [StateError] rather than a wrong signature, which the peer would drop without a word.
  /// Throws [ArgumentError] for inputs of the wrong length or a secret key outside `1..n-1`.
  static Uint8List sign(List<int> secretKey, List<int> digest, List<int> aux) {
    if (secretKey.length != 32 || digest.length != 32 || aux.length != 32) {
      throw ArgumentError('BIP-340 takes 32-byte keys, digests and aux');
    }
    // Checked here: `bip340.sign` would throw a bare `Error` for it.
    if (!isValidSecretScalar(bigIntFromBytes(secretKey))) {
      throw ArgumentError('not a secp256k1 secret key');
    }
    final signature = bip340.sign(
      hex.encode(secretKey),
      hex.encode(digest),
      hex.encode(aux),
    );
    final publicKey = bip340.getPublicKey(hex.encode(secretKey));
    if (!verify(hex.decode(publicKey), digest, hex.decode(signature))) {
      throw StateError('BIP-340 signature does not verify');
    }
    return Uint8List.fromList(hex.decode(signature));
  }

  /// Whether [signature] is a valid BIP-340 signature of [digest] by the x-only [publicKey].
  static bool verify(
    List<int> publicKey,
    List<int> digest,
    List<int> signature,
  ) {
    if (publicKey.length != 32 ||
        digest.length != 32 ||
        signature.length != 64) {
      return false;
    }
    return bip340.verify(
      hex.encode(publicKey),
      hex.encode(digest),
      hex.encode(signature),
    );
  }
}
