import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/key_packets.dart';
import 'package:robosats/src/pgp/message_cipher.dart';
import 'package:robosats/src/pgp/primitives.dart';
import 'package:robosats/src/pgp/signature_packets.dart';
import 'package:robosats/src/pgp/transferable_key.dart';
import 'package:robosats/src/pgp_wire.dart';
import 'package:robosats/src/robosats_failure.dart';
import 'package:robosats/src/robot_identity.dart';

/// The official client dates keys and chat signatures one day in the past (`frontend/src/pgp/index.ts:29` and `:58`).
///
/// A coordinator refuses a key younger than 12 hours (`api/utils.py:582-594`), and the offset absorbs a client clock that runs ahead.
const _backdating = Duration(days: 1);

const _onePassSignatureTag = 4;
const _literalDataTag = 11;
const _utf8LiteralFormat = 0x75;

/// [time], or the system clock, moved [back] and truncated to the whole seconds OpenPGP dates hold.
///
/// Throws an [ArgumentError] outside the range of an OpenPGP date, 1970 to 2106.
int _epochSeconds(DateTime? time, {Duration back = Duration.zero}) {
  final seconds =
      (time ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000 - back.inSeconds;
  if (seconds < 0 || seconds > 0xffffffff) {
    throw ArgumentError.value(time, 'now', 'outside the OpenPGP date range');
  }
  return seconds;
}

/// An OpenPGP public key of the kind RoboSats robots use: the robot's own, or the one of its trade peer.
///
/// A coordinator returns the peer's key as `peer_pubkey` on `GET /api/chat/` (`chat/views.py:99-111`).
@immutable
final class PgpPublicKey {
  /// The ASCII-armored block, with line feeds.
  final String armored;

  /// The fingerprint of the primary key: 40 uppercase hexadecimal characters, as GnuPG prints it.
  ///
  /// A coordinator accepts a clear-signed invoice only when GnuPG reports this fingerprint as the signer (`api/utils.py:641`).
  final String fingerprint;

  /// The user ID the primary key certifies: `RoboSats ID <hash id>` on a key made by the official client.
  ///
  /// No coordinator reads it: it is a convention between clients.
  final String userId;

  /// When the key says it was created, in UTC: one day before its real creation on a key made by the official client.
  final DateTime createdAt;

  final TransferableKey _key;

  PgpPublicKey._(this.armored, this._key)
    : fingerprint = hex.encode(_key.primary.fingerprint).toUpperCase(),
      userId = _key.userId,
      createdAt = DateTime.fromMillisecondsSinceEpoch(
        _key.primary.createdAt * 1000,
        isUtc: true,
      );

  /// Reads an armored public key, with its line breaks or with the backslashes RoboSats puts in their place.
  ///
  /// Fails with [PgpArmorMalformed] or [PgpKeyUnsupported].
  static Result<PgpPublicKey, PgpFailure> parse(String armored) {
    final text = pgpArmorFromWire(armored);
    final bytes = armorDecode(ArmorBlock.publicKey, text);
    if (bytes == null) return const Err(PgpArmorMalformed());
    try {
      return Ok(
        PgpPublicKey._(text, TransferableKey.parse(bytes, secret: false)),
      );
    } on FormatException {
      return const Err(PgpKeyUnsupported());
    } on UnsupportedPgpException {
      return const Err(PgpKeyUnsupported());
    }
  }

  /// Returns the text of [signedMessage] when its signature is a valid cleartext signature by the primary key of this key.
  ///
  /// This is the check a coordinator runs on an invoice or a payout address, without its requirement on the exact header.
  /// Fails with [PgpArmorMalformed] or [PgpSignatureInvalid].
  Result<String, PgpFailure> verifyCleartext(String signedMessage) {
    final parts = cleartextDecode(signedMessage);
    if (parts == null) return const Err(PgpArmorMalformed());
    final canonical = canonicalText(parts.text);
    try {
      for (final packet in decodePackets(parts.signature)) {
        if (packet.tag != PacketTag.signature) continue;
        final signature = SignatureBody.parse(packet.body);
        // GnuPG refuses a message whose `Hash` header disagrees with its signature.
        if (signature.type == SignatureType.text &&
            (parts.hashes.isEmpty ||
                parts.hashes.contains(hashName(signature.hashId))) &&
            signature.verify(canonical, _key.primary.point)) {
          return Ok(parts.text);
        }
      }
    } on FormatException {
      return const Err(PgpSignatureInvalid());
    } on UnsupportedPgpException {
      return const Err(PgpSignatureInvalid());
    }
    return const Err(PgpSignatureInvalid());
  }

  @override
  bool operator ==(Object other) =>
      other is PgpPublicKey &&
      other.fingerprint == fingerprint &&
      bytesEqual(other._key.subkey.fingerprint, _key.subkey.fingerprint);

  @override
  int get hashCode => fingerprint.hashCode;

  @override
  String toString() => 'PgpPublicKey($fingerprint, $userId)';
}

/// The OpenPGP key pair of a robot, as the two armored blocks a coordinator stores: the public key and the private key locked by the robot token.
///
/// It reproduces `genKey` of `frontend/src/pgp/index.ts:21-36` (commit ff1998c).
/// The same key serves every coordinator, and a coordinator keeps the first one it receives for good (`robosats/middleware.py:166-169`).
@immutable
final class RobotPgpKey {
  final PgpPublicKey publicKey;

  /// The ASCII-armored private key, each secret part encrypted with the robot token as passphrase.
  ///
  /// Coordinators store it and hand it back on `GET /api/robot/`: it is only as secret as the token.
  final String encryptedPrivateKeyArmored;

  final TransferableKey _secretKey;

  const RobotPgpKey._(
    this.publicKey,
    this.encryptedPrivateKeyArmored,
    this._secretKey,
  );

  /// Generates the key the official client would generate for [identity].
  ///
  /// The key is version 4, Ed25519 with a Curve25519 encryption subkey, named `RoboSats ID <hash id>`, locked by the token, and created exactly 24 hours before [now].
  /// The official client subtracts one calendar day in local time instead, which differs by an hour on the two days a year the clock changes.
  /// [random] defaults to `Random.secure()` and [now] to the system clock: with both fixed, the result is fixed, byte for byte.
  /// Hashing the passphrase takes 32 MiB of SHA-256: call it off the UI isolate.
  static RobotPgpKey generate(
    RobotIdentity identity, {
    DateTime? now,
    Random? random,
  }) {
    final generated = TransferableKey.generate(
      userId: identity.pgpUserId,
      passphrase: utf8.encode(identity.token.reveal()),
      createdAt: _epochSeconds(now, back: _backdating),
      random: random ?? Random.secure(),
    );
    final publicArmored = armorEncode(
      ArmorBlock.publicKey,
      generated.key.encodePublic(generated.secretKeys),
    );
    return RobotPgpKey._(
      PgpPublicKey._(publicArmored, generated.key),
      armorEncode(
        ArmorBlock.privateKey,
        generated.key.encodePrivate(generated.secretKeys),
      ),
      generated.key,
    );
  }

  /// Reads the two blocks of a robot, as generated earlier or as a coordinator returns them (`public_key` and `encrypted_private_key` of `GET /api/robot/`).
  ///
  /// The private key is not unlocked: no token is needed.
  /// Fails with [PgpArmorMalformed], [PgpKeyUnsupported], or [PgpKeyPairMismatch] when the two blocks are not the same key.
  static Result<RobotPgpKey, PgpFailure> parse({
    required String publicKey,
    required String encryptedPrivateKey,
  }) {
    final PgpPublicKey public;
    switch (PgpPublicKey.parse(publicKey)) {
      case Ok(:final value):
        public = value;
      case Err(:final failure):
        return Err(failure);
    }
    final privateText = pgpArmorFromWire(encryptedPrivateKey);
    final bytes = armorDecode(ArmorBlock.privateKey, privateText);
    if (bytes == null) return const Err(PgpArmorMalformed());
    final TransferableKey secretKey;
    try {
      secretKey = TransferableKey.parse(bytes, secret: true);
    } on FormatException {
      return const Err(PgpKeyUnsupported());
    } on UnsupportedPgpException {
      return const Err(PgpKeyUnsupported());
    }
    if (!bytesEqual(
          secretKey.primary.fingerprint,
          public._key.primary.fingerprint,
        ) ||
        !bytesEqual(
          secretKey.subkey.fingerprint,
          public._key.subkey.fingerprint,
        )) {
      return const Err(PgpKeyPairMismatch());
    }
    return Ok(RobotPgpKey._(public, privateText, secretKey));
  }

  /// Whether the key carries the user ID the official client gives the key of [identity].
  ///
  /// A robot created by another client may carry any user ID, so this is informative, not a validity check.
  bool isNamedAfter(RobotIdentity identity) =>
      publicKey.userId == identity.pgpUserId;

  /// Unlocks the private key with the token of [identity], to sign and to read and write chat messages.
  ///
  /// Hashing the passphrase takes 32 MiB of SHA-256: call it off the UI isolate, and unlock once for a batch of messages rather than once per message.
  /// Fails with [PgpWrongPassphrase], or with [PgpKeyUnsupported] when the secret values do not match the public key.
  Result<UnlockedRobotPgpKey, PgpFailure> unlock(RobotIdentity identity) {
    try {
      final secretKeys = _secretKey.unlock(
        utf8.encode(identity.token.reveal()),
      );
      if (secretKeys == null) return const Err(PgpWrongPassphrase());
      return Ok(UnlockedRobotPgpKey._(this, identity, secretKeys));
    } on UnsupportedPgpException {
      return const Err(PgpKeyUnsupported());
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RobotPgpKey &&
      other.publicKey == publicKey &&
      other.encryptedPrivateKeyArmored == encryptedPrivateKeyArmored;

  @override
  int get hashCode => publicKey.hashCode;

  @override
  String toString() => 'RobotPgpKey(${publicKey.fingerprint})';
}

/// A robot key with its secret values in memory.
///
/// Keep it for the duration of one task and drop it: nothing here is written anywhere, and nothing it prints reveals a secret.
final class UnlockedRobotPgpKey {
  final RobotPgpKey key;

  final RobotIdentity _identity;
  final SecretKeys _secretKeys;

  UnlockedRobotPgpKey._(this.key, this._identity, this._secretKeys);

  /// Clear-signs [text], a Lightning invoice or an on-chain address, for the `update_invoice` and `update_address` actions and for `POST /api/reward/`.
  ///
  /// It reproduces `signCleartextMessage` of `frontend/src/pgp/index.ts:102-119`: a text signature over SHA-512 by the primary key, dated [now].
  /// The result starts with exactly `-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n`, the string a coordinator splits on (`api/utils.py:642-644`).
  /// Fails with [PgpCleartextUnsuitable] when the coordinator's parser would not hand [text] back intact.
  Result<String, PgpCleartextUnsuitable> signCleartext(
    String text, {
    DateTime? now,
  }) {
    if (!_survivesCoordinatorParsing(text)) {
      return const Err(PgpCleartextUnsuitable());
    }
    final primary = key._secretKey.primary;
    return Ok(
      cleartextEncode(
        text: text,
        hashName: 'SHA512',
        signature: encodePacket(
          PacketTag.signature,
          textSignature(
            primary: primary,
            canonicalData: canonicalText(text),
            seed: _secretKeys.ed25519Seed,
            createdAt: _epochSeconds(now),
          ),
        ),
      ),
    );
  }

  /// Encrypts [plaintext] to this robot and to [peer], and signs it: the armored `PGP MESSAGE` a robot posts to the chat of an order.
  ///
  /// It reproduces `encryptMessage` of `frontend/src/pgp/index.ts:39-62`: both recipients in that order, so that each trader can read the whole history, AES-256, no compression, and a signature dated 24 hours before [now].
  /// On `POST /api/chat/` the result travels in the `PGP_message` field with its line breaks turned into backslashes: see [pgpArmorToWire].
  /// The plaintext never leaves the device: a coordinator stores only this block (`chat/models.py:87`), and the robot reads its own messages back by decrypting them.
  /// Fails with [PgpPlaintextContainsToken], as the official client refuses to send a message that contains the robot token.
  Result<String, PgpPlaintextContainsToken> encryptChatMessage(
    String plaintext, {
    required PgpPublicKey peer,
    DateTime? now,
  }) {
    if (plaintext.contains(_identity.token.reveal())) {
      return const Err(PgpPlaintextContainsToken());
    }
    final primary = key._secretKey.primary;
    final data = _canonicalLineEndings(utf8.encode(plaintext));
    final signature = textSignature(
      primary: primary,
      canonicalData: data,
      seed: _secretKeys.ed25519Seed,
      createdAt: _epochSeconds(now, back: _backdating),
    );
    final inner = Uint8List.fromList([
      ...encodePacket(_onePassSignatureTag, [
        3,
        SignatureType.text,
        HashId.sha512,
        KeyAlgorithm.eddsaLegacy,
        ...primary.keyId,
        1,
      ]),
      ...encodePacket(_literalDataTag, [
        _utf8LiteralFormat,
        0,
        ...u32Bytes(_epochSeconds(now)),
        ...data,
      ]),
      ...encodePacket(PacketTag.signature, signature),
    ]);
    return Ok(
      armorEncode(
        ArmorBlock.message,
        encryptPackets(inner, [key._secretKey.subkey, peer._key.subkey]),
      ),
    );
  }

  /// Decrypts a chat message, with its line breaks or with backslashes in their place, and checks that [sender] signed it.
  ///
  /// It reproduces `decryptMessage` of `frontend/src/pgp/index.ts:70-99`: a missing or invalid signature does not hide the text, it is reported as [DecryptedChatMessage.validSignature].
  /// [sender] is this robot's own public key when the coordinator attributes the message to this robot's nickname, and the peer's otherwise (`EncryptedApiChat/index.tsx:156`).
  /// Fails with [PgpArmorMalformed] or [PgpMessageUndecryptable].
  Result<DecryptedChatMessage, PgpFailure> decryptChatMessage(
    String armored, {
    required PgpPublicKey sender,
  }) {
    final bytes = armorDecode(ArmorBlock.message, pgpArmorFromWire(armored));
    if (bytes == null) return const Err(PgpArmorMalformed());
    final opened = decryptPackets(
      bytes,
      recipient: key._secretKey.subkey,
      scalar: _secretKeys.x25519Scalar,
    );
    if (opened == null) return const Err(PgpMessageUndecryptable());
    final text = _nativeText(opened.literalData);
    for (final body in opened.signatures) {
      final SignatureBody signature;
      // A signature this package cannot read counts as no signature, as in the official client.
      try {
        signature = SignatureBody.parse(body);
      } on FormatException {
        continue;
      } on UnsupportedPgpException {
        continue;
      }
      final signedData = switch (signature.type) {
        SignatureType.binary => opened.literalData,
        SignatureType.text => _canonicalLineEndings(opened.literalData),
        _ => null,
      };
      if (signedData != null &&
          signature.verify(signedData, sender._key.primary.point)) {
        final signedAt = signature.createdAt;
        return Ok(
          DecryptedChatMessage._(
            text,
            validSignature: true,
            signedAt: signedAt == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    signedAt * 1000,
                    isUtc: true,
                  ),
          ),
        );
      }
    }
    return Ok(
      DecryptedChatMessage._(text, validSignature: false, signedAt: null),
    );
  }

  @override
  String toString() => 'UnlockedRobotPgpKey(${key.publicKey.fingerprint})';
}

/// A chat message once decrypted.
@immutable
final class DecryptedChatMessage {
  /// The plaintext, with line feeds: never log it.
  final String text;

  /// Whether the expected sender signed the message.
  ///
  /// The official client shows the text either way and flags the message when this is false.
  final bool validSignature;

  /// When the valid signature says it was made, in UTC: one day before the real time on a message from the official client.
  ///
  /// `null` without a valid signature.
  final DateTime? signedAt;

  const DecryptedChatMessage._(
    this.text, {
    required this.validSignature,
    required this.signedAt,
  });

  @override
  String toString() =>
      'DecryptedChatMessage(<redacted>, validSignature: $validSignature)';
}

final RegExp _dashAtLineStart = RegExp('^-', multiLine: true);
final RegExp _spaceAtLineEnd = RegExp(r'[ \t]$', multiLine: true);

/// Whether `signed.split(header)[1].split(footer)[0].strip()`, the coordinator's extraction (`api/utils.py:642-644`), returns [text] unchanged.
bool _survivesCoordinatorParsing(String text) =>
    text.isNotEmpty &&
    text == text.trim() &&
    !text.contains('\r') &&
    !_dashAtLineStart.hasMatch(text) &&
    !_spaceAtLineEnd.hasMatch(text);

/// Turns every line feed that no carriage return precedes into CR LF: `canonicalizeEOL` of OpenPGP.js, the form a text signature covers.
Uint8List _canonicalLineEndings(List<int> data) {
  final builder = BytesBuilder(copy: false);
  var previous = 0;
  for (final byte in data) {
    if (byte == 0x0a && previous != 0x0d) builder.addByte(0x0d);
    builder.addByte(byte);
    previous = byte;
  }
  return builder.takeBytes();
}

/// Decodes literal data as the official client does: UTF-8, with CR LF turned back into line feeds.
String _nativeText(Uint8List data) =>
    utf8.decode(data, allowMalformed: true).replaceAll('\r\n', '\n');
