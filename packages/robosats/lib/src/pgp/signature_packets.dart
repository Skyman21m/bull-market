import 'dart:typed_data';

import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/key_packets.dart';
import 'package:robosats/src/pgp/primitives.dart';

/// OpenPGP signature types used by RoboSats (RFC 4880 section 5.2.1).
abstract final class SignatureType {
  static const binary = 0x00;
  static const text = 0x01;
  static const genericCertification = 0x10;
  static const positiveCertification = 0x13;
  static const subkeyBinding = 0x18;
}

/// Signature subpacket types (RFC 4880 section 5.2.3.1).
abstract final class _Subpacket {
  static const creationTime = 2;
  static const preferredSymmetric = 11;
  static const issuerKeyId = 16;
  static const preferredHash = 21;
  static const preferredCompression = 22;
  static const primaryUserId = 25;
  static const keyFlags = 27;
  static const features = 30;
  static const issuerFingerprint = 33;

  /// The subpackets this package may meet marked critical without having to act on them.
  static const understood = {
    creationTime,
    3,
    9,
    preferredSymmetric,
    issuerKeyId,
    preferredHash,
    preferredCompression,
    23,
    primaryUserId,
    keyFlags,
    28,
    features,
    issuerFingerprint,
    34,
  };
}

/// Key flags (RFC 4880 section 5.2.3.21).
abstract final class KeyFlags {
  static const certifyAndSign = 0x03;
  static const encrypt = 0x0c;
}

/// A version 4 EdDSA signature packet, read from a key or a message.
final class SignatureBody {
  final int type;
  final int hashId;

  /// The creation time in seconds since the Unix epoch, when the hashed area states it.
  final int? createdAt;

  /// The key flags of the hashed area, when present.
  final int? keyFlags;

  final Uint8List _hashedPortion;
  final Uint8List _digestPrefix;
  final Uint8List _signature;
  final bool _hasUnknownCriticalSubpacket;

  const SignatureBody._(
    this.type,
    this.hashId,
    this.createdAt,
    this.keyFlags,
    this._hashedPortion,
    this._digestPrefix,
    this._signature,
    this._hasUnknownCriticalSubpacket,
  );

  /// Parses a signature packet body.
  ///
  /// Throws an [UnsupportedPgpException] for anything but a version 4 EdDSA signature and a [FormatException] for malformed data.
  factory SignatureBody.parse(Uint8List body) {
    final reader = ByteReader(body);
    if (reader.u8() != 4) throw const UnsupportedPgpException();
    final type = reader.u8();
    if (reader.u8() != KeyAlgorithm.eddsaLegacy) {
      throw const UnsupportedPgpException();
    }
    final hashId = reader.u8();
    final hashed = reader.take(reader.u16());
    final hashedPortion = reader.lastRead(reader.offset);
    reader.take(reader.u16());
    final digestPrefix = reader.take(2);
    // R and S are 32-byte strings stored as integers: one in 128 signatures has a leading zero byte that the integer encoding drops.
    final signature = Uint8List.fromList([
      ...leftPad(reader.mpi(), 32),
      ...leftPad(reader.mpi(), 32),
    ]);
    if (!reader.isDone) throw const FormatException('trailing signature data');

    int? createdAt;
    int? keyFlags;
    var hasUnknownCriticalSubpacket = false;
    final subpackets = ByteReader(hashed);
    while (!subpackets.isDone) {
      final first = subpackets.u8();
      final length = first < 192
          ? first
          : first < 255
          ? ((first - 192) << 8) + subpackets.u8() + 192
          : subpackets.u32();
      if (length == 0) throw const FormatException('empty subpacket');
      final typeByte = subpackets.u8();
      final data = subpackets.take(length - 1);
      final subpacketType = typeByte & 0x7f;
      if (subpacketType == _Subpacket.creationTime && data.length == 4) {
        createdAt = ByteReader(data).u32();
      } else if (subpacketType == _Subpacket.keyFlags && data.isNotEmpty) {
        keyFlags = data[0];
      } else if (typeByte & 0x80 != 0 &&
          !_Subpacket.understood.contains(subpacketType)) {
        hasUnknownCriticalSubpacket = true;
      }
    }
    return SignatureBody._(
      type,
      hashId,
      createdAt,
      keyFlags,
      Uint8List.fromList(hashedPortion),
      Uint8List.fromList(digestPrefix),
      signature,
      hasUnknownCriticalSubpacket,
    );
  }

  /// Whether this signature covers [signedData] and was made by the Ed25519 key [publicKey].
  bool verify(Uint8List signedData, Uint8List publicKey) {
    if (_hasUnknownCriticalSubpacket) return false;
    final digest = _digest(hashId, signedData, _hashedPortion);
    if (digest == null || !bytesEqual(digest.sublist(0, 2), _digestPrefix)) {
      return false;
    }
    return ed25519Verify(publicKey, digest, _signature);
  }
}

/// The data a certification of [userId] by [primary] covers.
Uint8List certificationData(PublicKeyBody primary, List<int> userId) =>
    Uint8List.fromList([
      ...primary.hashPrefixed,
      0xb4,
      ...u32Bytes(userId.length),
      ...userId,
    ]);

/// The data a binding of [subkey] to [primary] covers.
Uint8List bindingData(PublicKeyBody primary, PublicKeyBody subkey) =>
    Uint8List.fromList([...primary.hashPrefixed, ...subkey.hashPrefixed]);

/// The self-certification OpenPGP.js 5 gives the user ID of a Curve25519 key, subpacket for subpacket.
///
/// The layout is the one of `tests/robots/3/enc_priv_key` in the RoboSats repository: creation time, AES-256 then AES-128 then AES-192, issuer, SHA-256 then SHA-512, no compression then ZLIB then ZIP, primary user ID, certify and sign, modification detection, issuer fingerprint.
Uint8List selfCertification({
  required PublicKeyBody primary,
  required List<int> userId,
  required Uint8List seed,
  required int createdAt,
}) => _sign(
  type: SignatureType.genericCertification,
  seed: seed,
  signedData: certificationData(primary, userId),
  hashedSubpackets: [
    _subpacket(_Subpacket.creationTime, u32Bytes(createdAt), critical: true),
    _subpacket(_Subpacket.preferredSymmetric, const [
      CipherId.aes256,
      CipherId.aes128,
      CipherId.aes192,
    ]),
    _subpacket(_Subpacket.issuerKeyId, primary.keyId, critical: true),
    _subpacket(_Subpacket.preferredHash, const [HashId.sha256, HashId.sha512]),
    _subpacket(_Subpacket.preferredCompression, const [0, 2, 1]),
    _subpacket(_Subpacket.primaryUserId, const [1]),
    _subpacket(_Subpacket.keyFlags, const [
      KeyFlags.certifyAndSign,
    ], critical: true),
    _subpacket(_Subpacket.features, const [1]),
    _subpacket(_Subpacket.issuerFingerprint, [4, ...primary.fingerprint]),
  ],
);

/// The binding signature OpenPGP.js 5 gives the encryption subkey of a Curve25519 key.
Uint8List subkeyBinding({
  required PublicKeyBody primary,
  required PublicKeyBody subkey,
  required Uint8List seed,
  required int createdAt,
}) => _sign(
  type: SignatureType.subkeyBinding,
  seed: seed,
  signedData: bindingData(primary, subkey),
  hashedSubpackets: [
    _subpacket(_Subpacket.creationTime, u32Bytes(createdAt), critical: true),
    _subpacket(_Subpacket.issuerKeyId, primary.keyId, critical: true),
    _subpacket(_Subpacket.keyFlags, const [KeyFlags.encrypt], critical: true),
    _subpacket(_Subpacket.issuerFingerprint, [4, ...primary.fingerprint]),
  ],
);

/// A text signature of [canonicalData] by [primary], with the subpackets OpenPGP.js 5 writes: creation time, issuer, issuer fingerprint.
Uint8List textSignature({
  required PublicKeyBody primary,
  required Uint8List canonicalData,
  required Uint8List seed,
  required int createdAt,
}) => _sign(
  type: SignatureType.text,
  seed: seed,
  signedData: canonicalData,
  hashedSubpackets: [
    _subpacket(_Subpacket.creationTime, u32Bytes(createdAt), critical: true),
    _subpacket(_Subpacket.issuerKeyId, primary.keyId, critical: true),
    _subpacket(_Subpacket.issuerFingerprint, [4, ...primary.fingerprint]),
  ],
);

List<int> _subpacket(int type, List<int> data, {bool critical = false}) => [
  data.length + 1,
  critical ? type | 0x80 : type,
  ...data,
];

/// Builds a version 4 EdDSA signature packet body over SHA-512, the hash OpenPGP.js 5 and GnuPG pick for Ed25519.
///
/// EdDSA is deterministic and no salt is added, so the same input always gives the same packet.
Uint8List _sign({
  required int type,
  required Uint8List seed,
  required Uint8List signedData,
  required List<List<int>> hashedSubpackets,
}) {
  final hashed = hashedSubpackets.expand((subpacket) => subpacket).toList();
  final hashedPortion = Uint8List.fromList([
    4,
    type,
    KeyAlgorithm.eddsaLegacy,
    HashId.sha512,
    ...u16Bytes(hashed.length),
    ...hashed,
  ]);
  final digest = _digest(HashId.sha512, signedData, hashedPortion);
  if (digest == null) throw StateError('SHA-512 is always available');
  final signature = ed25519Sign(seed, digest);
  return Uint8List.fromList([
    ...hashedPortion,
    0,
    0,
    digest[0],
    digest[1],
    ...mpiEncode(signature.sublist(0, 32)),
    ...mpiEncode(signature.sublist(32)),
  ]);
}

/// The digest a version 4 signature signs: the data, the hashed portion of the packet, then a six-byte trailer.
Uint8List? _digest(int hashId, Uint8List signedData, Uint8List hashedPortion) {
  final hash = signatureHash(hashId);
  if (hash == null) return null;
  return Uint8List.fromList(
    hash.convert([
      ...signedData,
      ...hashedPortion,
      4,
      0xff,
      ...u32Bytes(hashedPortion.length),
    ]).bytes,
  );
}
