import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:robosats/robosats.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/primitives.dart';

import 'pgp.dart';

/// Hand-made OpenPGP packets, to reach what the package never writes: every signature here is a real one, made again over the altered bytes.

const ed25519Oid = [0x2b, 0x06, 0x01, 0x04, 0x01, 0xda, 0x47, 0x0f, 0x01];
const curve25519Oid = [
  0x2b, 0x06, 0x01, 0x04, 0x01, 0x97, 0x55, 0x01, 0x05, 0x01, //
];

/// A signature subpacket with a one-byte length.
List<int> subpacket(int type, List<int> data, {bool critical = false}) => [
  data.length + 1,
  critical ? type | 0x80 : type,
  ...data,
];

/// The creation time subpacket, critical as OpenPGP.js writes it.
List<int> creationTime(int seconds) =>
    subpacket(2, u32Bytes(seconds), critical: true);

const _hashes = {
  HashId.sha1: crypto.sha1,
  HashId.sha256: crypto.sha256,
  HashId.sha384: crypto.sha384,
  HashId.sha512: crypto.sha512,
  HashId.sha224: crypto.sha224,
};

/// The body of a signature packet over [data] by the Ed25519 [seed], with exactly the [hashed] subpackets given.
Uint8List craftSignature({
  required Uint8List seed,
  required int type,
  required List<int> data,
  required List<int> hashed,
  int version = 4,
  int algorithm = 22,
  int hashId = HashId.sha512,
  List<int> unhashed = const [],
  List<int> trailing = const [],
  bool breakDigestPrefix = false,
}) {
  final hash = _hashes[hashId];
  if (hash == null) throw ArgumentError.value(hashId, 'hashId');
  final hashedPortion = [
    version,
    type,
    algorithm,
    hashId,
    ...u16Bytes(hashed.length),
    ...hashed,
  ];
  final digest = Uint8List.fromList(
    hash.convert([
      ...data,
      ...hashedPortion,
      4,
      0xff,
      ...u32Bytes(hashedPortion.length),
    ]).bytes,
  );
  final signature = ed25519Sign(seed, digest);
  return Uint8List.fromList([
    ...hashedPortion,
    ...u16Bytes(unhashed.length),
    ...unhashed,
    digest[0] ^ (breakDigestPrefix ? 1 : 0),
    digest[1],
    ...mpiEncode(signature.sublist(0, 32)),
    ...mpiEncode(signature.sublist(32)),
    ...trailing,
  ]);
}

/// A cleartext message with a hand-made signature packet.
String craftCleartext(
  String text,
  Uint8List signatureBody, {
  String hash = 'SHA512',
}) => cleartextEncode(
  text: text,
  hashName: hash,
  signature: encodePacket(PacketTag.signature, signatureBody),
);

Uint8List _prefixed(List<int> body) =>
    Uint8List.fromList([0x99, ...u16Bytes(body.length), ...body]);

/// A robot key built packet by packet, each part replaceable, each signature made for the parts as they are.
final class CraftedKey {
  /// The date every crafted key and signature carries unless told otherwise: 2026-11-08 12:00:00 UTC, like the generated test key.
  static const defaultCreatedAt = 1794139200;

  final Uint8List seed;
  final Uint8List scalar;
  final List<int> userId;
  final Uint8List primaryBody;
  final Uint8List subkeyBody;
  final Uint8List certification;
  final Uint8List binding;

  CraftedKey._(
    this.seed,
    this.scalar,
    this.userId,
    this.primaryBody,
    this.subkeyBody,
    this.certification,
    this.binding,
  );

  /// [subkeyCreatedAt] dates the subkey apart from the primary key and from both signatures, [kdf] is the KDF field with its length byte, [subkeyPoint] replaces the point of [label]'s scalar, and [boundSubkeyBody] makes the binding cover another subkey than the one in the key.
  factory CraftedKey({
    String label = 'crafted',
    int createdAt = defaultCreatedAt,
    int? subkeyCreatedAt,
    String userId = 'RoboSats ID crafted',
    List<int> primaryOid = ed25519Oid,
    List<int> subkeyOid = curve25519Oid,
    List<int> kdf = const [3, 1, HashId.sha256, CipherId.aes128],
    Uint8List? subkeyPoint,
    int certificationType = 0x10,
    int bindingType = 0x18,
    List<int>? certificationHashed,
    List<int>? bindingHashed,
    Uint8List? bindingSeed,
    Uint8List? boundSubkeyBody,
  }) {
    final random = DeterministicRandom(label);
    final seed = randomBytes(random, 32);
    final scalar = clampX25519Scalar(randomBytes(random, 32));
    final primaryBody = Uint8List.fromList([
      4,
      ...u32Bytes(createdAt),
      22,
      primaryOid.length,
      ...primaryOid,
      ...mpiEncode([0x40, ...ed25519PublicKey(seed)]),
    ]);
    final subkeyBody = Uint8List.fromList([
      4,
      ...u32Bytes(subkeyCreatedAt ?? createdAt),
      18,
      subkeyOid.length,
      ...subkeyOid,
      ...mpiEncode([0x40, ...subkeyPoint ?? x25519PublicKey(scalar)]),
      ...kdf,
    ]);
    final userIdBytes = utf8.encode(userId);
    return CraftedKey._(
      seed,
      scalar,
      userIdBytes,
      primaryBody,
      subkeyBody,
      craftSignature(
        seed: seed,
        type: certificationType,
        data: [
          ..._prefixed(primaryBody),
          0xb4,
          ...u32Bytes(userIdBytes.length),
          ...userIdBytes,
        ],
        hashed:
            certificationHashed ??
            [
              ...creationTime(createdAt),
              ...subpacket(27, [0x03], critical: true),
            ],
      ),
      craftSignature(
        seed: bindingSeed ?? seed,
        type: bindingType,
        data: [
          ..._prefixed(primaryBody),
          ..._prefixed(boundSubkeyBody ?? subkeyBody),
        ],
        hashed:
            bindingHashed ??
            [
              ...creationTime(createdAt),
              ...subpacket(27, [0x0c], critical: true),
            ],
      ),
    );
  }

  /// The 32-byte Ed25519 public key.
  Uint8List get primaryPoint => ed25519PublicKey(seed);

  List<RawPacket> get publicPackets => [
    (tag: PacketTag.publicKey, body: primaryBody),
    (tag: PacketTag.userId, body: Uint8List.fromList(userId)),
    (tag: PacketTag.signature, body: certification),
    (tag: PacketTag.publicSubkey, body: subkeyBody),
    (tag: PacketTag.signature, body: binding),
  ];

  String get publicArmored => armorPackets(ArmorBlock.publicKey, publicPackets);

  /// The private packets, both secret parts locked by [passphrase] with a 64 KiB S2K, which keeps these tests fast.
  ///
  /// [primarySecret] and [subkeySecret] replace the secret integers, and [protect] the whole protection.
  List<RawPacket> privatePackets(
    String passphrase, {
    Uint8List? primarySecret,
    Uint8List? subkeySecret,
    Uint8List Function(Uint8List secret, String passphrase)? protect,
  }) {
    final lock = protect ?? protectSecret;
    return [
      (
        tag: PacketTag.secretKey,
        body: Uint8List.fromList([
          ...primaryBody,
          ...lock(primarySecret ?? mpiEncode(seed), passphrase),
        ]),
      ),
      (tag: PacketTag.userId, body: Uint8List.fromList(userId)),
      (tag: PacketTag.signature, body: certification),
      (
        tag: PacketTag.secretSubkey,
        body: Uint8List.fromList([
          ...subkeyBody,
          ...lock(
            subkeySecret ?? mpiEncode(scalar.reversed.toList()),
            passphrase,
          ),
        ]),
      ),
      (tag: PacketTag.signature, body: binding),
    ];
  }

  String privateArmored(String passphrase) =>
      armorPackets(ArmorBlock.privateKey, privatePackets(passphrase));

  PgpPublicKey get publicKey => expectOk(PgpPublicKey.parse(publicArmored));

  /// This key, unlocked, as the key of the robot [identity].
  UnlockedRobotPgpKey unlockedFor(RobotIdentity identity) => expectOk(
    expectOk(
      RobotPgpKey.parse(
        publicKey: publicArmored,
        encryptedPrivateKey: privateArmored(identity.token.reveal()),
      ),
    ).unlock(identity),
  );
}

/// The secret part of a key packet: [secret] locked by [passphrase] as OpenPGP.js locks it, but for the iteration count.
Uint8List protectSecret(
  Uint8List secret,
  String passphrase, {
  int usage = 254,
  int cipherId = CipherId.aes256,
  int codedCount = 96,
  int? ciphertextLength,
}) {
  final salt = Uint8List.fromList(List.generate(8, (i) => i + 1));
  final iv = Uint8List.fromList(List.generate(16, (i) => 0x10 + i));
  final ciphertext = aesCfb(
    encrypt: true,
    key: s2kIteratedSalted(
      hash: crypto.sha256,
      passphrase: utf8.encode(passphrase),
      salt: salt,
      codedCount: codedCount,
      keyLength: 32,
    ),
    iv: iv,
    data: Uint8List.fromList([...secret, ...sha1(secret)]),
  );
  return Uint8List.fromList([
    usage,
    cipherId,
    3,
    HashId.sha256,
    ...salt,
    codedCount,
    ...iv,
    ...ciphertext.sublist(0, ciphertextLength ?? ciphertext.length),
  ]);
}

String armorPackets(ArmorBlock block, List<RawPacket> packets) => armorEncode(
  block,
  [for (final packet in packets) ...encodePacket(packet.tag, packet.body)],
);

/// A literal data packet holding [text] as UTF-8 text, as it is.
Uint8List literalPacket(String text, {int format = 0x75}) => encodePacket(
  PacketTag.literalData,
  [format, 0, 0, 0, 0, 0, ...utf8.encode(text)],
);

/// A session key as it is wrapped for a recipient: cipher, key, checksum, then [padding] bytes each equal to [padding].
///
/// By default the padding fills the last 8-byte block, as OpenPGP.js and GnuPG pad.
Uint8List encodeSessionKey(
  List<int> key, {
  int cipherId = CipherId.aes256,
  int? padding,
  int checksumOffset = 0,
}) {
  final checksum =
      (key.fold<int>(0, (sum, byte) => sum + byte) + checksumOffset) & 0xffff;
  final length = 1 + key.length + 2;
  final count = padding ?? 8 - length % 8;
  return Uint8List.fromList([
    cipherId,
    ...key,
    ...u16Bytes(checksum),
    ...List.filled(count, count),
  ]);
}

/// A session key packet for [recipient], written without the code under test: the ECDH of RFC 6637 from its text, on the primitives only.
///
/// [encoded] is wrapped as it is, so that a test decides every byte of what the recipient unwraps.
Uint8List craftSessionKeyPacket(
  CraftedKey recipient,
  Uint8List encoded, {
  List<int> trailing = const [],
  int? wrappedLength,
}) {
  final ephemeral = clampX25519Scalar(
    Uint8List.fromList(List.generate(32, (i) => 0x40 + i)),
  );
  final body = recipient.subkeyBody;
  final point = Uint8List.sublistView(
    body,
    body.length - 4 - 32,
    body.length - 4,
  );
  final shared = x25519SharedSecret(ephemeral, point);
  if (shared == null) throw StateError('low-order recipient');
  final kdfHash = body[body.length - 2];
  final kdfCipher = body[body.length - 1];
  final fingerprint = sha1(_prefixed(body));
  final digest = (_hashes[kdfHash] ?? crypto.sha256).convert([
    0,
    0,
    0,
    1,
    ...shared,
    curve25519Oid.length,
    ...curve25519Oid,
    18,
    3,
    1,
    kdfHash,
    kdfCipher,
    ...utf8.encode('Anonymous Sender    '),
    ...fingerprint,
  ]);
  final kek = Uint8List.fromList(
    digest.bytes.sublist(0, aesKeyLength(kdfCipher) ?? 16),
  );
  final wrapped = aesKeyWrap(kek, encoded);
  final carried = wrapped.sublist(0, wrappedLength ?? wrapped.length);
  return encodePacket(PacketTag.publicKeyEncryptedSessionKey, [
    3,
    ...fingerprint.sublist(12),
    18,
    ...mpiEncode([0x40, ...x25519PublicKey(ephemeral)]),
    carried.length,
    ...carried,
    ...trailing,
  ]);
}

/// An integrity-protected data packet under [sessionKey] whose plaintext is exactly [plaintext], followed by its SHA-1.
Uint8List craftDataPacketOver(Uint8List sessionKey, List<int> plaintext) {
  final plain = Uint8List.fromList(plaintext);
  return encodePacket(PacketTag.integrityProtectedData, [
    1,
    ...aesCfb(
      encrypt: true,
      key: sessionKey,
      iv: Uint8List(16),
      data: Uint8List.fromList([...plain, ...sha1(plain)]),
    ),
  ]);
}

/// A well-formed integrity-protected data packet holding [inner], with a fixed prefix and the [mdcHeader] given.
Uint8List craftDataPacket(
  Uint8List sessionKey,
  List<int> inner, {
  List<int> mdcHeader = const [0xd3, 0x14],
}) {
  final prefix = List.generate(16, (i) => 0x30 + i);
  return craftDataPacketOver(sessionKey, [
    ...prefix,
    prefix[14],
    prefix[15],
    ...inner,
    ...mdcHeader,
  ]);
}
