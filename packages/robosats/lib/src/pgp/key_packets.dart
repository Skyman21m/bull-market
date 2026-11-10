import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/limits.dart';
import 'package:robosats/src/pgp/primitives.dart';

/// Thrown inside this package when OpenPGP data is well formed but outside the subset RoboSats robots use.
final class UnsupportedPgpException implements Exception {
  const UnsupportedPgpException();
}

/// OpenPGP public-key algorithm identifiers of a RoboSats robot key.
abstract final class KeyAlgorithm {
  static const ecdh = 18;
  static const eddsaLegacy = 22;
}

/// The curve identifier of an Ed25519 "legacy" key, 1.3.6.1.4.1.11591.15.1.
const _ed25519Oid = [0x2b, 0x06, 0x01, 0x04, 0x01, 0xda, 0x47, 0x0f, 0x01];

/// The curve identifier of a Curve25519 "legacy" ECDH key, 1.3.6.1.4.1.3029.1.5.1.
const curve25519Oid = [
  0x2b, 0x06, 0x01, 0x04, 0x01, 0x97, 0x55, 0x01, 0x05, 0x01, //
];

/// The prefix byte that marks a native, non-Weierstrass point in a "legacy" curve key.
const _nativePointPrefix = 0x40;

/// The public part of a version 4 key or subkey packet on Curve25519.
final class PublicKeyBody {
  /// The packet body, exactly as read or as it will be written.
  final Uint8List bytes;

  /// The creation time, in seconds since the Unix epoch.
  final int createdAt;

  /// [KeyAlgorithm.eddsaLegacy] or [KeyAlgorithm.ecdh].
  final int algorithm;

  /// The 32-byte Ed25519 or X25519 public key.
  final Uint8List point;

  /// The hash and the cipher an ECDH key asks its senders to derive and wrap with (RFC 6637 section 9), and 0 on a signing key.
  final int kdfHashId;
  final int kdfCipherId;

  /// The 20-byte version 4 fingerprint.
  late final Uint8List fingerprint = sha1(hashPrefixed);

  PublicKeyBody._(
    this.bytes,
    this.createdAt,
    this.algorithm,
    this.point, {
    this.kdfHashId = 0,
    this.kdfCipherId = 0,
  });

  /// The Ed25519 primary key of a robot.
  factory PublicKeyBody.signing({
    required int createdAt,
    required Uint8List publicKey,
  }) => PublicKeyBody._(
    Uint8List.fromList([
      4,
      ...u32Bytes(createdAt),
      KeyAlgorithm.eddsaLegacy,
      _ed25519Oid.length,
      ..._ed25519Oid,
      ...mpiEncode([_nativePointPrefix, ...publicKey]),
    ]),
    createdAt,
    KeyAlgorithm.eddsaLegacy,
    publicKey,
  );

  /// The Curve25519 encryption subkey of a robot.
  factory PublicKeyBody.encryption({
    required int createdAt,
    required Uint8List publicKey,
  }) => PublicKeyBody._(
    Uint8List.fromList([
      4,
      ...u32Bytes(createdAt),
      KeyAlgorithm.ecdh,
      curve25519Oid.length,
      ...curve25519Oid,
      ...mpiEncode([_nativePointPrefix, ...publicKey]),
      // The KDF parameters OpenPGP.js and GnuPG give a Curve25519 key: SHA-256 and AES-128.
      3,
      1,
      HashId.sha256,
      CipherId.aes128,
    ]),
    createdAt,
    KeyAlgorithm.ecdh,
    publicKey,
    kdfHashId: HashId.sha256,
    kdfCipherId: CipherId.aes128,
  );

  /// Reads the public part at the start of a key packet body, leaving [reader] on the secret part, if any.
  ///
  /// Throws an [UnsupportedPgpException] for any key that is not version 4 on Ed25519 or Curve25519, for KDF parameters other than SHA-2 with AES, and for an X25519 point of low order.
  factory PublicKeyBody.read(ByteReader reader) {
    final start = reader.offset;
    if (reader.u8() != 4) throw const UnsupportedPgpException();
    final createdAt = reader.u32();
    final algorithm = reader.u8();
    final expectedOid = switch (algorithm) {
      KeyAlgorithm.eddsaLegacy => _ed25519Oid,
      KeyAlgorithm.ecdh => curve25519Oid,
      _ => throw const UnsupportedPgpException(),
    };
    if (!bytesEqual(reader.take(reader.u8()), expectedOid)) {
      throw const UnsupportedPgpException();
    }
    final point = reader.mpi();
    if (point.length != 33 || point[0] != _nativePointPrefix) {
      throw const UnsupportedPgpException();
    }
    final publicKey = Uint8List.fromList(point.sublist(1));
    var kdfHashId = 0;
    var kdfCipherId = 0;
    if (algorithm == KeyAlgorithm.ecdh) {
      final kdf = reader.take(reader.u8());
      if (kdf.length != 3 ||
          kdf[0] != 1 ||
          ecdhKdfHash(kdf[1]) == null ||
          aesKeyLength(kdf[2]) == null ||
          isLowOrderX25519Point(publicKey)) {
        throw const UnsupportedPgpException();
      }
      kdfHashId = kdf[1];
      kdfCipherId = kdf[2];
    }
    return PublicKeyBody._(
      Uint8List.fromList(reader.lastRead(reader.offset - start)),
      createdAt,
      algorithm,
      publicKey,
      kdfHashId: kdfHashId,
      kdfCipherId: kdfCipherId,
    );
  }

  /// The last 8 bytes of the fingerprint.
  Uint8List get keyId => Uint8List.sublistView(fingerprint, 12);

  /// The form of this key that fingerprints and signatures hash: `0x99`, a two-byte length, the body.
  Uint8List get hashPrefixed =>
      Uint8List.fromList([0x99, ...u16Bytes(bytes.length), ...bytes]);
}

/// The passphrase-protected secret part of a key packet: iterated and salted S2K, AES in CFB mode, SHA-1 check.
///
/// This is the only protection OpenPGP.js 5 and GnuPG 2 write for version 4 keys.
final class ProtectedSecret {
  static const _sha1CheckUsage = 254;
  static const _iteratedSaltedS2k = 3;

  /// The coded iteration count of OpenPGP.js 5: 16 777 216 bytes hashed.
  static const openPgpJsCodedCount = 224;

  final int cipherId;
  final int s2kHashId;
  final Uint8List salt;
  final int codedCount;
  final Uint8List iv;
  final Uint8List ciphertext;

  const ProtectedSecret._(
    this.cipherId,
    this.s2kHashId,
    this.salt,
    this.codedCount,
    this.iv,
    this.ciphertext,
  );

  /// Reads the secret part that follows the public part in a secret key packet body.
  ///
  /// Throws an [UnsupportedPgpException] for an unprotected key, for any other protection, and for an iteration count above [PgpLimits.s2kBytes].
  factory ProtectedSecret.read(ByteReader reader) {
    if (reader.u8() != _sha1CheckUsage) throw const UnsupportedPgpException();
    final cipherId = reader.u8();
    if (aesKeyLength(cipherId) == null) throw const UnsupportedPgpException();
    if (reader.u8() != _iteratedSaltedS2k) {
      throw const UnsupportedPgpException();
    }
    final s2kHashId = reader.u8();
    if (_s2kHash(s2kHashId) == null) throw const UnsupportedPgpException();
    final salt = reader.take(8);
    final codedCount = reader.u8();
    if (s2kByteCount(codedCount) > PgpLimits.s2kBytes) {
      throw const UnsupportedPgpException();
    }
    final iv = reader.take(16);
    final ciphertext = reader.rest();
    // An integer of at least one byte, then the 20 bytes of the SHA-1 check.
    if (ciphertext.length < 23) throw const UnsupportedPgpException();
    return ProtectedSecret._(
      cipherId,
      s2kHashId,
      salt,
      codedCount,
      iv,
      ciphertext,
    );
  }

  /// Protects [secret], the secret multiprecision integers of a key, with the parameters OpenPGP.js 5 uses: SHA-256, 16 MiB, AES-256.
  factory ProtectedSecret.lock({
    required List<int> passphrase,
    required Uint8List secret,
    required Uint8List salt,
    required Uint8List iv,
  }) {
    final key = s2kIteratedSalted(
      hash: crypto.sha256,
      passphrase: passphrase,
      salt: salt,
      codedCount: openPgpJsCodedCount,
      keyLength: 32,
    );
    final plain = Uint8List.fromList([...secret, ...sha1(secret)]);
    final ciphertext = aesCfb(encrypt: true, key: key, iv: iv, data: plain);
    wipe(key);
    wipe(plain);
    return ProtectedSecret._(
      CipherId.aes256,
      HashId.sha256,
      salt,
      openPgpJsCodedCount,
      iv,
      ciphertext,
    );
  }

  /// The secret multiprecision integers, or `null` when [passphrase] is wrong.
  Uint8List? unlock(List<int> passphrase) {
    final hash = _s2kHash(s2kHashId);
    final keyLength = aesKeyLength(cipherId);
    if (hash == null || keyLength == null || ciphertext.length < 23) {
      return null;
    }
    final key = s2kIteratedSalted(
      hash: hash,
      passphrase: passphrase,
      salt: salt,
      codedCount: codedCount,
      keyLength: keyLength,
    );
    final plain = aesCfb(encrypt: false, key: key, iv: iv, data: ciphertext);
    wipe(key);
    final secret = Uint8List.sublistView(plain, 0, plain.length - 20);
    final check = Uint8List.sublistView(plain, plain.length - 20);
    if (bytesEqual(sha1(secret), check)) return secret;
    wipe(plain);
    return null;
  }

  /// The bytes that follow the public part in a secret key packet body.
  Uint8List encode() => Uint8List.fromList([
    _sha1CheckUsage,
    cipherId,
    _iteratedSaltedS2k,
    s2kHashId,
    ...salt,
    codedCount,
    ...iv,
    ...ciphertext,
  ]);

  static crypto.Hash? _s2kHash(int id) =>
      id == HashId.sha1 ? crypto.sha1 : signatureHash(id);
}

/// The Ed25519 seed held in the secret multiprecision integer of a primary key.
///
/// A seed that starts with zero bytes is stored shortened, so it is padded back to 32 bytes.
Uint8List ed25519SeedFromSecret(Uint8List secret) {
  final reader = ByteReader(secret);
  final seed = leftPad(reader.mpi(), 32);
  if (!reader.isDone) throw const FormatException('trailing secret key data');
  return seed;
}

/// The secret multiprecision integer of an Ed25519 [seed].
Uint8List ed25519SecretFromSeed(Uint8List seed) => mpiEncode(seed);

/// The little-endian X25519 scalar held, big-endian, in the secret multiprecision integer of a Curve25519 subkey.
Uint8List x25519ScalarFromSecret(Uint8List secret) {
  final reader = ByteReader(secret);
  final bigEndian = leftPad(reader.mpi(), 32);
  if (!reader.isDone) throw const FormatException('trailing secret key data');
  return Uint8List.fromList(bigEndian.reversed.toList());
}

/// The secret multiprecision integer of a little-endian X25519 [scalar].
Uint8List x25519SecretFromScalar(Uint8List scalar) =>
    mpiEncode(scalar.reversed.toList());
