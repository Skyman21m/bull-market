import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

final ECDomainParameters _curve = ECCurve_secp256k1();

/// The order of the secp256k1 group.
BigInt get secp256k1Order => _curve.n;

/// Reads [bytes] as a big-endian unsigned integer.
BigInt bigIntFromBytes(List<int> bytes) =>
    bytes.isEmpty ? BigInt.zero : BigInt.parse(hex.encode(bytes), radix: 16);

/// Writes [value] as 32 big-endian bytes.
Uint8List bigIntToBytes32(BigInt value) {
  if (value.isNegative || value.bitLength > 256) {
    throw ArgumentError('value does not fit in 32 bytes');
  }
  return Uint8List.fromList(
    hex.decode(value.toRadixString(16).padLeft(64, '0')),
  );
}

/// Whether [scalar] is a usable secp256k1 secret key: strictly between zero and the group order.
bool isValidSecretScalar(BigInt scalar) =>
    scalar > BigInt.zero && scalar < _curve.n;

/// The 33-byte SEC1 compressed public key of [secretScalar].
Uint8List compressedPublicKey(BigInt secretScalar) {
  if (!isValidSecretScalar(secretScalar)) {
    throw ArgumentError('not a secp256k1 secret key');
  }
  final point = _curve.G * secretScalar;
  if (point == null || point.isInfinity) {
    throw StateError('secp256k1 multiplication yielded no point');
  }
  return point.getEncoded(true);
}

/// The BIP340 x-only public key of [secretScalar]: the 32-byte X coordinate.
Uint8List xOnlyPublicKey(BigInt secretScalar) =>
    compressedPublicKey(secretScalar).sublist(1);
