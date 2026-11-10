import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/key_packets.dart';
import 'package:robosats/src/pgp/limits.dart';
import 'package:robosats/src/pgp/primitives.dart';

/// What an encrypted message holds once opened: the literal data and the signature packet bodies found next to it.
typedef OpenedMessage = ({
  int literalFormat,
  Uint8List literalData,
  List<Uint8List> signatures,
});

/// The 20 bytes RFC 6637 section 8 puts in the KDF input in place of a sender identity.
const _anonymousSender = [
  0x41, 0x6e, 0x6f, 0x6e, 0x79, 0x6d, 0x6f, 0x75, 0x73, 0x20, //
  0x53, 0x65, 0x6e, 0x64, 0x65, 0x72, 0x20, 0x20, 0x20, 0x20,
];

/// The header of the modification detection code packet that ends the plaintext: tag 19, 20 bytes.
const _mdcHeader = [0xd3, 0x14];

const _blockSize = 16;
const _sessionKeyLength = 32;
const _compressionZip = 1;
const _compressionZlib = 2;

/// Literal data formats: binary, text and UTF-8 text.
const _literalFormats = {0x62, 0x74, 0x75};

/// Encrypts [innerPackets] to each of [recipients] with AES-256, in the form OpenPGP.js 5 writes by default.
///
/// The result is one version 3 public-key encrypted session key packet per recipient, in order, then one version 1 integrity-protected data packet, all with definite lengths and no compression.
/// It draws 48 bytes from [random], then 32 per recipient, and is a deterministic function of its arguments and of those bytes.
/// Returns `null` when a recipient key yields an all-zero shared secret, which a key accepted by [PublicKeyBody.read] never does.
Uint8List? encryptPackets(
  Uint8List innerPackets,
  List<PublicKeyBody> recipients, {
  required Random random,
}) {
  final sessionKey = randomBytes(random, _sessionKeyLength);
  final prefix = randomBytes(random, _blockSize);
  final output = BytesBuilder(copy: false);
  for (final recipient in recipients) {
    final wrapped = _wrapSessionKey(
      sessionKey,
      recipient,
      clampX25519Scalar(randomBytes(random, 32)),
    );
    if (wrapped == null) {
      wipe(sessionKey);
      return null;
    }
    output.add(encodePacket(PacketTag.publicKeyEncryptedSessionKey, wrapped));
  }
  final plain = Uint8List.fromList([
    ...prefix,
    prefix[_blockSize - 2],
    prefix[_blockSize - 1],
    ...innerPackets,
    ..._mdcHeader,
  ]);
  final encrypted = aesCfb(
    encrypt: true,
    key: sessionKey,
    iv: Uint8List(_blockSize),
    data: Uint8List.fromList([...plain, ...sha1(plain)]),
  );
  wipe(sessionKey);
  wipe(plain);
  output.add(encodePacket(PacketTag.integrityProtectedData, [1, ...encrypted]));
  return output.takeBytes();
}

/// Opens [message] with the X25519 [scalar] of the encryption subkey [recipient], or returns `null`.
///
/// Only the envelope the official client and GnuPG write is accepted: session key packets, then one version 1 integrity-protected data packet and nothing else.
/// GnuPG frames that data packet with partial body lengths from about 500 bytes on, so stream lengths are read here too, within the size bound of the caller.
/// Inside it, after the modification detection code has been checked: one-pass signatures, one literal data packet and signatures, either directly or in a single compressed data packet.
/// Nothing is inflated before that check, and never beyond [PgpLimits.decompressedBytes].
/// `null` covers every refusal: not encrypted to this subkey, tampered with, not integrity-protected, any other packet, or a bound of [PgpLimits] exceeded.
OpenedMessage? decryptPackets(
  Uint8List message, {
  required PublicKeyBody recipient,
  required Uint8List scalar,
}) {
  try {
    final packets = decodePackets(
      message,
      maxPackets: PgpLimits.sessionKeyPackets + 1,
      streamLengths: true,
    );
    if (packets.length < 2 ||
        packets.last.tag != PacketTag.integrityProtectedData) {
      return null;
    }
    final sessionKeyPackets = packets.sublist(0, packets.length - 1);
    if (sessionKeyPackets.any(
      (packet) => packet.tag != PacketTag.publicKeyEncryptedSessionKey,
    )) {
      return null;
    }
    for (final packet in sessionKeyPackets) {
      final sessionKey = _unwrapSessionKey(packet.body, recipient, scalar);
      if (sessionKey == null) continue;
      final plain = _openData(packets.last.body, sessionKey);
      wipe(sessionKey);
      if (plain == null) continue;
      return _contents(plain, allowCompression: true);
    }
    return null;
  } on FormatException {
    return null;
  }
}

/// The input of the RFC 6637 KDF that is specific to [recipient]: curve, algorithm, KDF parameters, the anonymous sender and the fingerprint.
Uint8List _kek(PublicKeyBody recipient, Uint8List sharedSecret) {
  final hash = ecdhKdfHash(recipient.kdfHashId);
  final length = aesKeyLength(recipient.kdfCipherId);
  if (hash == null || length == null) {
    throw StateError('an ECDH key always carries valid KDF parameters');
  }
  final digest = hash.convert([
    0,
    0,
    0,
    1,
    ...sharedSecret,
    curve25519Oid.length,
    ...curve25519Oid,
    KeyAlgorithm.ecdh,
    3,
    1,
    recipient.kdfHashId,
    recipient.kdfCipherId,
    ..._anonymousSender,
    ...recipient.fingerprint,
  ]);
  return Uint8List.fromList(digest.bytes.sublist(0, length));
}

/// The body of a version 3 session key packet for [recipient], made with a fresh [ephemeralScalar].
Uint8List? _wrapSessionKey(
  Uint8List sessionKey,
  PublicKeyBody recipient,
  Uint8List ephemeralScalar,
) {
  final sharedSecret = x25519SharedSecret(ephemeralScalar, recipient.point);
  if (sharedSecret == null) return null;
  var checksum = 0;
  for (final byte in sessionKey) {
    checksum = (checksum + byte) & 0xffff;
  }
  // Cipher, key and checksum take 35 bytes, padded to 40 in the PKCS #5 manner.
  final encoded = Uint8List.fromList([
    CipherId.aes256,
    ...sessionKey,
    ...u16Bytes(checksum),
    5,
    5,
    5,
    5,
    5,
  ]);
  final kek = _kek(recipient, sharedSecret);
  final wrapped = aesKeyWrap(kek, encoded);
  final ephemeralPublic = x25519PublicKey(ephemeralScalar);
  for (final secret in [sharedSecret, encoded, kek, ephemeralScalar]) {
    wipe(secret);
  }
  return Uint8List.fromList([
    3,
    ...recipient.keyId,
    KeyAlgorithm.ecdh,
    ...mpiEncode([0x40, ...ephemeralPublic]),
    wrapped.length,
    ...wrapped,
  ]);
}

/// The AES session key a session key packet holds for [recipient], or `null` when the packet is for another key, of another kind, or does not unwrap.
Uint8List? _unwrapSessionKey(
  Uint8List body,
  PublicKeyBody recipient,
  Uint8List scalar,
) {
  final reader = ByteReader(body);
  if (reader.u8() != 3) return null;
  final keyId = reader.take(8);
  // An all-zero key ID hides the recipient: such a packet is tried with every key.
  if (!bytesEqual(keyId, recipient.keyId) && !bytesEqual(keyId, Uint8List(8))) {
    return null;
  }
  if (reader.u8() != KeyAlgorithm.ecdh) return null;
  final ephemeral = reader.mpi();
  if (ephemeral.length != 33 || ephemeral[0] != 0x40) return null;
  final wrapped = reader.take(reader.u8());
  if (!reader.isDone) return null;
  final sharedSecret = x25519SharedSecret(
    scalar,
    Uint8List.sublistView(ephemeral, 1),
  );
  if (sharedSecret == null) return null;
  final kek = _kek(recipient, sharedSecret);
  final encoded = aesKeyUnwrap(kek, wrapped);
  wipe(sharedSecret);
  wipe(kek);
  if (encoded == null) return null;
  final sessionKey = _sessionKeyOf(encoded);
  wipe(encoded);
  return sessionKey;
}

/// Takes the padding, the cipher and the checksum off an unwrapped session key, or returns `null` when one of them is wrong.
///
/// RFC 6637 section 8 lets a sender pad up to 40 bytes, so the padding may be longer than a block: every byte of it is checked.
Uint8List? _sessionKeyOf(Uint8List encoded) {
  final padding = encoded.last;
  if (padding < 1 || padding > encoded.length - 3) return null;
  var mismatch = 0;
  for (var i = encoded.length - padding; i < encoded.length; i++) {
    mismatch |= encoded[i] ^ padding;
  }
  if (mismatch != 0) return null;
  final keyEnd = encoded.length - padding - 2;
  if (aesKeyLength(encoded[0]) != keyEnd - 1) return null;
  var checksum = 0;
  for (var i = 1; i < keyEnd; i++) {
    checksum = (checksum + encoded[i]) & 0xffff;
  }
  if (checksum != (encoded[keyEnd] << 8 | encoded[keyEnd + 1])) return null;
  return Uint8List.fromList(encoded.sublist(1, keyEnd));
}

/// The packets inside a version 1 integrity-protected data packet, or `null` unless the modification detection code matches.
Uint8List? _openData(Uint8List body, Uint8List sessionKey) {
  // Version, prefix, and the 22 bytes of the modification detection code packet.
  if (body.length < 1 + _blockSize + 2 + 22 || body[0] != 1) return null;
  final plain = aesCfb(
    encrypt: false,
    key: sessionKey,
    iv: Uint8List(_blockSize),
    data: Uint8List.sublistView(body, 1),
  );
  final hashed = Uint8List.sublistView(plain, 0, plain.length - 20);
  final code = Uint8List.sublistView(plain, plain.length - 20);
  final authentic =
      bytesEqual(sha1(hashed), code) &&
      hashed[hashed.length - 2] == _mdcHeader[0] &&
      hashed[hashed.length - 1] == _mdcHeader[1];
  if (!authentic) {
    wipe(plain);
    return null;
  }
  return Uint8List.sublistView(hashed, _blockSize + 2, hashed.length - 2);
}

/// Reads authenticated plaintext: one-pass signatures, one literal data packet, signatures, or all of that in one compressed data packet.
OpenedMessage? _contents(Uint8List plain, {required bool allowCompression}) {
  final packets = decodePackets(
    plain,
    maxPackets: 2 * PgpLimits.signatures + 1,
    streamLengths: true,
  );
  if (packets.length == 1 && packets.single.tag == PacketTag.compressedData) {
    if (!allowCompression) return null;
    final inflated = _inflate(packets.single.body);
    return inflated == null
        ? null
        : _contents(inflated, allowCompression: false);
  }
  var index = 0;
  while (index < packets.length &&
      packets[index].tag == PacketTag.onePassSignature) {
    index++;
  }
  if (index > PgpLimits.signatures ||
      index >= packets.length ||
      packets[index].tag != PacketTag.literalData) {
    return null;
  }
  final literal = ByteReader(packets[index].body);
  final format = literal.u8();
  if (!_literalFormats.contains(format)) return null;
  // The file name and the date are not signed and not used.
  literal
    ..take(literal.u8())
    ..u32();
  final signatures = packets.sublist(index + 1);
  if (signatures.length > PgpLimits.signatures ||
      signatures.any((packet) => packet.tag != PacketTag.signature)) {
    return null;
  }
  return (
    literalFormat: format,
    literalData: literal.rest(),
    signatures: [for (final packet in signatures) packet.body],
  );
}

/// Inflates the body of a compressed data packet, ZIP or ZLIB, or returns `null` when it is damaged, of another kind, or larger than [PgpLimits.decompressedBytes].
Uint8List? _inflate(Uint8List body) {
  if (body.isEmpty) return null;
  final algorithm = body[0];
  if (algorithm != _compressionZip && algorithm != _compressionZlib) {
    return null;
  }
  final output = BytesBuilder(copy: false);
  // The filter reports damaged data with errors of several kinds, none of them documented: all mean the same here.
  try {
    final filter = RawZLibFilter.inflateFilter(
      raw: algorithm == _compressionZip,
    )..process(body, 1, body.length);
    while (true) {
      final chunk = filter.processed(flush: true, end: true);
      if (chunk == null) break;
      if (output.length + chunk.length > PgpLimits.decompressedBytes) {
        return null;
      }
      output.add(chunk);
    }
  } on Object {
    return null;
  }
  return output.takeBytes();
}
