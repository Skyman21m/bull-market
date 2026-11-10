import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:pinenacl/tweetnacl.dart';
import 'package:pointycastle/export.dart' as pc;

/// OpenPGP hash algorithm identifiers (RFC 4880 section 9.4).
abstract final class HashId {
  static const sha1 = 2;
  static const sha256 = 8;
  static const sha384 = 9;
  static const sha512 = 10;
  static const sha224 = 11;
}

/// OpenPGP symmetric cipher identifiers (RFC 4880 section 9.2).
abstract final class CipherId {
  static const aes128 = 7;
  static const aes192 = 8;
  static const aes256 = 9;
}

/// The hash function behind an OpenPGP identifier that is still acceptable in a signature, or `null`.
///
/// MD5, SHA-1 and RIPEMD-160 are refused, as OpenPGP.js 5 and GnuPG 2.4 refuse them for new signatures.
crypto.Hash? signatureHash(int id) => switch (id) {
  HashId.sha256 => crypto.sha256,
  HashId.sha384 => crypto.sha384,
  HashId.sha512 => crypto.sha512,
  HashId.sha224 => crypto.sha224,
  _ => null,
};

/// The name an armor `Hash:` header gives to a hash identifier.
String? hashName(int id) => switch (id) {
  HashId.sha256 => 'SHA256',
  HashId.sha384 => 'SHA384',
  HashId.sha512 => 'SHA512',
  HashId.sha224 => 'SHA224',
  _ => null,
};

/// The key length in bytes of an AES identifier, or `null` for any other cipher.
int? aesKeyLength(int cipherId) => switch (cipherId) {
  CipherId.aes128 => 16,
  CipherId.aes192 => 24,
  CipherId.aes256 => 32,
  _ => null,
};

Uint8List sha1(List<int> data) =>
    Uint8List.fromList(crypto.sha1.convert(data).bytes);

/// [length] bytes drawn from [random], one `nextInt(256)` per byte.
Uint8List randomBytes(Random random, int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

/// The Ed25519 public key of a 32-byte [seed].
Uint8List ed25519PublicKey(Uint8List seed) =>
    nacl.SigningKey.fromSeed(seed).verifyKey.asTypedList;

/// The 64-byte Ed25519 signature of [message] under a 32-byte [seed].
Uint8List ed25519Sign(Uint8List seed, Uint8List message) =>
    nacl.SigningKey.fromSeed(seed).sign(message).signature.asTypedList;

/// Whether [signature], 64 bytes, is the Ed25519 signature of [message] under [publicKey], 32 bytes.
bool ed25519Verify(
  Uint8List publicKey,
  Uint8List message,
  Uint8List signature,
) {
  if (publicKey.length != 32 || signature.length != 64) return false;
  try {
    return nacl.VerifyKey(
      publicKey,
    ).verify(signature: nacl.Signature(signature), message: message);
    // The TweetNaCl port reports a forged signature by throwing a bare `Exception`.
  } on Exception {
    return false;
  }
}

/// Clamps 32 random bytes into an X25519 scalar, in the little-endian order of RFC 7748.
Uint8List clampX25519Scalar(Uint8List bytes) => Uint8List.fromList(bytes)
  ..[0] &= 248
  ..[31] = (bytes[31] & 127) | 64;

/// The X25519 public key of a little-endian [scalar].
Uint8List x25519PublicKey(Uint8List scalar) =>
    TweetNaCl.crypto_scalarmult_base(Uint8List(32), scalar);

/// Encrypts or decrypts [data] with AES in the full-block CFB mode OpenPGP uses for secret keys.
Uint8List aesCfb({
  required bool encrypt,
  required Uint8List key,
  required Uint8List iv,
  required Uint8List data,
}) {
  final cipher = pc.CFBBlockCipher(pc.AESEngine(), 16)
    ..init(encrypt, pc.ParametersWithIV(pc.KeyParameter(key), iv));
  // CFB is a stream mode: the zero padding of the last block only affects output bytes that are then dropped.
  final padded = Uint8List((data.length + 15) ~/ 16 * 16)..setAll(0, data);
  final output = Uint8List(padded.length);
  for (var offset = 0; offset < padded.length; offset += 16) {
    cipher.processBlock(padded, offset, output, offset);
  }
  return Uint8List.sublistView(output, 0, data.length);
}

/// The byte count an iterated and salted S2K hashes for a coded count (RFC 4880 section 3.7.1.3).
int s2kByteCount(int codedCount) =>
    (16 + (codedCount & 15)) << ((codedCount >> 4) + 6);

/// Derives a [keyLength]-byte key from [passphrase] with the iterated and salted S2K of RFC 4880 section 3.7.1.3.
///
/// The repeated salt and passphrase are streamed into the hash, so the 16 MiB an OpenPGP.js key asks for are never held in memory.
Uint8List s2kIteratedSalted({
  required crypto.Hash hash,
  required List<int> passphrase,
  required List<int> salt,
  required int codedCount,
  required int keyLength,
}) {
  final unit = [...salt, ...passphrase];
  final total = max(s2kByteCount(codedCount), unit.length);
  // Feeding whole copies of the unit in large chunks keeps the number of hash updates low.
  final copies = max(1, 65536 ~/ unit.length);
  final chunk = Uint8List(copies * unit.length);
  for (var i = 0; i < copies; i++) {
    chunk.setAll(i * unit.length, unit);
  }
  final key = BytesBuilder(copy: false);
  for (var context = 0; key.length < keyLength; context++) {
    final output = _DigestSink();
    final input = hash.startChunkedConversion(output)..add(Uint8List(context));
    var remaining = total;
    while (remaining >= chunk.length) {
      input.add(chunk);
      remaining -= chunk.length;
    }
    input
      ..add(Uint8List.sublistView(chunk, 0, remaining))
      ..close();
    key.add(output.digest.bytes);
  }
  return Uint8List.sublistView(key.takeBytes(), 0, keyLength);
}

final class _DigestSink implements Sink<crypto.Digest> {
  late crypto.Digest digest;

  @override
  void add(crypto.Digest data) => digest = data;

  @override
  void close() {}
}
