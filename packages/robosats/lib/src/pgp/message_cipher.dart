import 'dart:typed_data';

import 'package:dart_pg/dart_pg.dart' as dart_pg;
import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/key_packets.dart';

/// What an encrypted message holds once opened: the literal data and the signature packets found next to it.
typedef OpenedMessage = ({
  int literalFormat,
  Uint8List literalData,
  List<Uint8List> signatures,
});

const _publicKeyEncryptedSessionKeyTag = 1;
const _integrityProtectedDataTag = 18;

/// Encrypts [innerPackets] to each of [recipients] with AES-256, as OpenPGP.js 5 does by default.
///
/// The result is one version 3 public-key encrypted session key packet per recipient, in order, then one version 1 integrity-protected data packet, all with definite lengths.
/// This is the only file that touches `dart_pg`: the ECDH key wrap of RFC 6637 and the encrypted container are the library's, and so is their randomness, which comes from `Random.secure` and cannot be injected.
Uint8List encryptPackets(
  Uint8List innerPackets,
  List<PublicKeyBody> recipients,
) {
  final sessionKey = dart_pg.OpenPGP.generateSessionKey(
    const [],
    dart_pg.SymmetricAlgorithm.aes256,
  );
  final container =
      dart_pg.SymEncryptedIntegrityProtectedDataPacket.encryptPackets(
        sessionKey.encryptionKey,
        dart_pg.PacketList.decode(innerPackets),
        symmetric: sessionKey.symmetric,
      );
  return Uint8List.fromList([
    for (final recipient in recipients)
      ...encodePacket(
        _publicKeyEncryptedSessionKeyTag,
        dart_pg.PublicKeyEncryptedSessionKeyPacket.encryptSessionKey(
          dart_pg.PublicSubkeyPacket.fromBytes(recipient.bytes),
          sessionKey,
        ).data,
      ),
    ...encodePacket(_integrityProtectedDataTag, container.data),
  ]);
}

/// Opens [message] with the X25519 [scalar] of the encryption subkey [recipient], or returns `null`.
///
/// `null` covers every way this can fail: not encrypted to this subkey, tampered with, no integrity protection, or packets the library cannot read.
OpenedMessage? decryptPackets(
  Uint8List message, {
  required PublicKeyBody recipient,
  required Uint8List scalar,
}) {
  try {
    final secretSubkey = dart_pg.SecretSubkeyPacket.fromBytes(
      _unprotectedSecretSubkey(recipient, scalar),
    );
    final packets = dart_pg.PacketList.decode(message);
    final container = packets
        .whereType<dart_pg.SymEncryptedIntegrityProtectedDataPacket>()
        .firstOrNull;
    if (container == null) return null;
    for (final candidate
        in packets.whereType<dart_pg.PublicKeyEncryptedSessionKeyPacket>()) {
      if (!bytesEqual(candidate.keyID, recipient.keyId)) continue;
      final sessionKey = candidate.decrypt(secretSubkey).sessionKey;
      if (sessionKey == null) continue;
      final opened = container
          .decrypt(sessionKey.encryptionKey, sessionKey.symmetric)
          .packets;
      if (opened == null) return null;
      return _contents(opened);
    }
    return null;
    // The library signals malformed or forged input with errors of many kinds (`AssertionError`, `RangeError`, `StateError`, `ArgumentError`), so this boundary has to catch them all.
  } catch (_) {
    return null;
  }
}

OpenedMessage? _contents(Iterable<Object> packets) {
  final compressed = packets
      .whereType<dart_pg.CompressedDataPacket>()
      .firstOrNull;
  final Iterable<Object> plain = compressed == null
      ? packets
      : compressed.packets;
  final literal = plain.whereType<dart_pg.LiteralDataPacket>().firstOrNull;
  if (literal == null) return null;
  return (
    literalFormat: literal.format.value,
    literalData: literal.binary,
    signatures: [
      for (final signature in plain.whereType<dart_pg.SignaturePacket>())
        signature.data,
    ],
  );
}

/// A secret subkey packet body with its secret part in the clear, the form the library needs to unwrap a session key.
Uint8List _unprotectedSecretSubkey(PublicKeyBody subkey, Uint8List scalar) {
  final secret = x25519SecretFromScalar(scalar);
  var checksum = 0;
  for (final byte in secret) {
    checksum = (checksum + byte) & 0xffff;
  }
  return Uint8List.fromList([
    ...subkey.bytes,
    0,
    ...secret,
    ...u16Bytes(checksum),
  ]);
}
