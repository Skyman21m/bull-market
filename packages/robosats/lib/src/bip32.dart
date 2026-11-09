import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:robosats/src/secp256k1.dart';

/// The bit that marks a hardened BIP32 child index.
const int bip32Hardened = 0x80000000;

/// The private key at [path] below the BIP32 master key of [seed].
///
/// Each element of [path] is a 32-bit child index, hardened when [bip32Hardened] is set.
/// This is private-parent to private-child derivation only, which is all RoboSats needs (`HDKey.fromMasterSeed(seed).derive(path).privateKey` in `frontend/src/utils/garageKey.ts:84-95`, commit ff1998c).
/// It is implemented here rather than with the wallet BIP32 library because that library is reserved to `packages/secrets` by the custody gate, and a Garage Key is not wallet seed material.
/// A derived key outside the valid range, which happens with probability below 2^-127, throws a [StateError], as `@scure/bip32` throws in RoboSats.
Uint8List deriveBip32PrivateKey(List<int> seed, List<int> path) {
  final master = Hmac(sha512, utf8.encode('Bitcoin seed')).convert(seed).bytes;
  var key = bigIntFromBytes(master.sublist(0, 32));
  var chainCode = master.sublist(32);
  if (!isValidSecretScalar(key)) {
    throw StateError('BIP32 master key out of range');
  }
  for (final index in path) {
    RangeError.checkValueInInterval(index, 0, 0xffffffff, 'path');
    final data = BytesBuilder(copy: false)
      ..add(
        index >= bip32Hardened
            ? [0, ...bigIntToBytes32(key)]
            : compressedPublicKey(key),
      )
      ..add([
        index >> 24 & 0xff,
        index >> 16 & 0xff,
        index >> 8 & 0xff,
        index & 0xff,
      ]);
    final digest = Hmac(sha512, chainCode).convert(data.takeBytes()).bytes;
    final tweak = bigIntFromBytes(digest.sublist(0, 32));
    final child = (key + tweak) % secp256k1Order;
    if (tweak >= secp256k1Order || child == BigInt.zero) {
      throw StateError('BIP32 child key out of range');
    }
    key = child;
    chainCode = digest.sublist(32);
  }
  return bigIntToBytes32(key);
}
