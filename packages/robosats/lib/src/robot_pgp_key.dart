import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/key_packets.dart';
import 'package:robosats/src/pgp/limits.dart';
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

const _utf8LiteralFormat = 0x75;

/// [time], or the system clock, moved [back] and truncated to the whole seconds OpenPGP dates hold.
///
/// `null` outside the range of an OpenPGP date, 1970 to 2106.
int? _epochSeconds(DateTime? time, {Duration back = Duration.zero}) {
  final seconds =
      (time ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000 - back.inSeconds;
  return seconds < 0 || seconds > 0xffffffff ? null : seconds;
}

/// An OpenPGP public key of the kind RoboSats robots use: the robot's own, or the one of its trade peer.
///
/// A coordinator returns the peer's key as `peer_pubkey` on `GET /api/chat/` (`chat/views.py:99-111`).
@immutable
final class PgpPublicKey {
  /// The key in canonical ASCII armor, with line feeds: its packets armored as the official client armors them, without any armor header, whatever the armor the key was read from.
  ///
  /// It is therefore made of the two fixed lines, base64 characters and line feeds only, which is what makes it safe to put in the `Authorization` header of a first contact: a `Comment` header of the armor it was read from, which may hold any text, never comes along.
  /// Two keys with the same packets have the same text.
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
  /// Armor headers such as `Version` or `Comment` are accepted, as GnuPG writes them, and dropped: [armored] is the canonical armor of the packets read.
  /// The key is not checked against a clock: [verifyCleartext] and the chat methods do that.
  /// Fails with [PgpInputTooLarge], [PgpArmorMalformed] or [PgpKeyUnsupported].
  static Result<PgpPublicKey, PgpFailure> parse(String armored) {
    if (armored.length > PgpLimits.keyArmorChars) {
      return const Err(PgpInputTooLarge());
    }
    final bytes = armorDecode(ArmorBlock.publicKey, pgpArmorFromWire(armored));
    if (bytes == null) return const Err(PgpArmorMalformed());
    try {
      return Ok(
        PgpPublicKey._(
          armorEncode(ArmorBlock.publicKey, bytes),
          TransferableKey.parse(bytes, secret: false),
        ),
      );
    } on FormatException {
      return const Err(PgpKeyUnsupported());
    } on UnsupportedPgpException {
      return const Err(PgpKeyUnsupported());
    }
  }

  /// Returns the text [signedMessage] signs when its signature is a valid cleartext signature by the primary key of this key, as of [now].
  ///
  /// This is the check a coordinator runs on an invoice or a payout address, with the date rules of the official client: the signature must not be dated after [now], expired, older than the key, or made when the key was expired.
  /// The text returned is the signed text itself: trailing spaces and tabs, which a cleartext signature does not cover, are dropped from every line.
  /// A `Hash` header naming the hash of the signature is required, as coordinators require `Hash: SHA512` (`api/utils.py:642`).
  /// Fails with [PgpInputTooLarge], [PgpClockOutOfRange], [PgpArmorMalformed] or [PgpSignatureInvalid].
  Result<String, PgpFailure> verifyCleartext(
    String signedMessage, {
    DateTime? now,
  }) {
    if (signedMessage.length > PgpLimits.cleartextChars) {
      return const Err(PgpInputTooLarge());
    }
    final time = _epochSeconds(now);
    if (time == null) return const Err(PgpClockOutOfRange());
    final parts = cleartextDecode(signedMessage);
    if (parts == null || parts.hashes.isEmpty) {
      return const Err(PgpArmorMalformed());
    }
    final List<RawPacket> packets;
    try {
      packets = decodePackets(
        parts.signature,
        maxPackets: PgpLimits.signatures,
      );
    } on FormatException {
      return const Err(PgpSignatureInvalid());
    }
    final canonical = canonicalText(parts.text);
    for (final packet in packets) {
      if (packet.tag != PacketTag.signature) continue;
      final signature = _tryParseSignature(packet.body);
      // GnuPG and OpenPGP.js refuse a message whose `Hash` header disagrees with its signature.
      if (signature != null &&
          signature.type == SignatureType.text &&
          parts.hashes.contains(hashName(signature.hashId)) &&
          _key.acceptsSignatureDates(signature, time) &&
          signature.verify(canonical, _key.primary.point)) {
        return Ok(canonicalLines(parts.text));
      }
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

  /// The private key in canonical ASCII armor, as [PgpPublicKey.armored] is, each secret part encrypted with the robot token as passphrase.
  ///
  /// Coordinators store it and hand it back on `GET /api/robot/`: it is only as secret as the token.
  final String encryptedPrivateKeyArmored;

  final TransferableKey _secretKey;

  const RobotPgpKey._(
    this.publicKey,
    this.encryptedPrivateKeyArmored,
    this._secretKey,
  );

  /// Generates the key the official client would generate for [identity], with the system clock and a cryptographically secure generator.
  ///
  /// The key is version 4, Ed25519 with a Curve25519 encryption subkey, named `RoboSats ID <hash id>`, locked by the token, and dated exactly 24 hours in the past.
  /// The official client subtracts one calendar day in local time instead, which differs by an hour on the two days a year the clock changes.
  /// Hashing the passphrase takes 32 MiB of SHA-256: call it off the UI isolate.
  /// Fails with [PgpClockOutOfRange] on a device whose clock is not between 2 January 1970 and 2106.
  static Result<RobotPgpKey, PgpClockOutOfRange> generate(
    RobotIdentity identity,
  ) => generateWith(identity, now: DateTime.now(), random: Random.secure());

  /// [generate] with a given clock and source of randomness: with both fixed, the result is fixed, byte for byte.
  ///
  /// For tests only: a key is only as strong as [random].
  @visibleForTesting
  static Result<RobotPgpKey, PgpClockOutOfRange> generateWith(
    RobotIdentity identity, {
    required DateTime now,
    required Random random,
  }) {
    final createdAt = _epochSeconds(now, back: _backdating);
    if (createdAt == null) return const Err(PgpClockOutOfRange());
    final passphrase = utf8.encode(identity.token.reveal());
    final generated = TransferableKey.generate(
      userId: identity.pgpUserId,
      passphrase: passphrase,
      createdAt: createdAt,
      random: random,
    );
    wipe(passphrase);
    final publicArmored = armorEncode(ArmorBlock.publicKey, generated.public);
    return Ok(
      RobotPgpKey._(
        PgpPublicKey._(
          publicArmored,
          TransferableKey.parse(generated.public, secret: false),
        ),
        armorEncode(ArmorBlock.privateKey, generated.private),
        TransferableKey.parse(generated.private, secret: true),
      ),
    );
  }

  /// Reads the two blocks of a robot, as generated earlier or as a coordinator returns them (`public_key` and `encrypted_private_key` of `GET /api/robot/`).
  ///
  /// The private key is not unlocked: no token is needed.
  /// Both blocks may carry armor headers, which are dropped: the key holds the canonical armor of the packets read, so nothing but base64 ever goes from it into a request.
  /// Fails with [PgpInputTooLarge], [PgpArmorMalformed], [PgpKeyUnsupported], or [PgpKeyPairMismatch] when the two blocks are not the same key.
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
    if (encryptedPrivateKey.length > PgpLimits.keyArmorChars) {
      return const Err(PgpInputTooLarge());
    }
    final bytes = armorDecode(
      ArmorBlock.privateKey,
      pgpArmorFromWire(encryptedPrivateKey),
    );
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
    return Ok(
      RobotPgpKey._(
        public,
        armorEncode(ArmorBlock.privateKey, bytes),
        secretKey,
      ),
    );
  }

  /// Whether the key carries the user ID the official client gives the key of [identity].
  ///
  /// A robot created by another client may carry any user ID, so this is informative, not a validity check.
  bool isNamedAfter(RobotIdentity identity) =>
      publicKey.userId == identity.pgpUserId;

  /// Unlocks the private key with the token of [identity], to sign and to read and write chat messages.
  ///
  /// Hashing the passphrase takes 32 MiB of SHA-256 for a key of the official client, and up to 130 MiB for a key GnuPG protected: call it off the UI isolate, and unlock once for a batch of messages rather than once per message.
  /// Fails with [PgpWrongPassphrase], or with [PgpKeyUnsupported] when the secret values do not match the public key.
  Result<UnlockedRobotPgpKey, PgpFailure> unlock(RobotIdentity identity) {
    final passphrase = utf8.encode(identity.token.reveal());
    try {
      final secretKeys = _secretKey.unlock(passphrase);
      if (secretKeys == null) return const Err(PgpWrongPassphrase());
      return Ok(UnlockedRobotPgpKey._(this, identity, secretKeys));
    } on UnsupportedPgpException {
      return const Err(PgpKeyUnsupported());
    } finally {
      wipe(passphrase);
    }
  }

  /// Checks that a holder of the token of [identity] made this pair: the proof that lets a robot take a key pair it did not send, from a coordinator that holds it.
  ///
  /// The private key must unlock with the token and hold the secret values of the public key: its primary key and its encryption subkey must be, packet body for packet body, the ones of the public block, which [parse] compared by fingerprint only.
  /// It proves who made the pair because each secret part is locked by an S2K salted and iterated over the token itself, and a coordinator never receives the token, only its SHA-256.
  /// Nothing is hashed when the two blocks are not the same key, or when unlocking would hash more than [PgpLimits.proofHashedBytes]; otherwise it costs what [unlock] costs, 32 MiB of SHA-256 for a key of the official client or of Troc: call it off the UI isolate.
  /// The passphrase and the secret values it unlocked are wiped before it returns, and nothing unlocked is kept.
  /// Fails with [PgpKeyPairMismatch], [PgpInputTooLarge], [PgpWrongPassphrase], or [PgpKeyUnsupported] when the secret values are not those of the public key.
  @internal
  Result<void, PgpFailure> proveMadeBy(RobotIdentity identity) {
    if (!bytesEqual(_secretKey.primary.bytes, publicKey._key.primary.bytes) ||
        !bytesEqual(_secretKey.subkey.bytes, publicKey._key.subkey.bytes)) {
      return const Err(PgpKeyPairMismatch());
    }
    final passphrase = utf8.encode(identity.token.reveal());
    try {
      if (_secretKey.unlockHashedBytes(passphrase.length) >
          PgpLimits.proofHashedBytes) {
        return const Err(PgpInputTooLarge());
      }
      final secretKeys = _secretKey.unlock(passphrase);
      if (secretKeys == null) return const Err(PgpWrongPassphrase());
      wipe(secretKeys.ed25519Seed);
      wipe(secretKeys.x25519Scalar);
      return const Ok(null);
    } on UnsupportedPgpException {
      return const Err(PgpKeyUnsupported());
    } finally {
      wipe(passphrase);
    }
  }

  /// The private keys are compared without stopping at the first difference.
  ///
  /// They are locked, and a coordinator that returns one holds it already, so the time a comparison takes reveals nothing it does not know; the comparison is constant-time all the same, so that no reader has to check that.
  @override
  bool operator ==(Object other) =>
      other is RobotPgpKey &&
      other.publicKey == publicKey &&
      bytesEqual(
        other.encryptedPrivateKeyArmored.codeUnits,
        encryptedPrivateKeyArmored.codeUnits,
      );

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
  /// A clock that runs behind the date of the key would give a signature GnuPG and the official client refuse: the signature is then dated like the key.
  /// Fails with [PgpInputTooLarge], [PgpClockOutOfRange], or with [PgpCleartextUnsuitable] when the coordinator's parser would not hand [text] back intact.
  Result<String, PgpFailure> signCleartext(String text, {DateTime? now}) {
    if (text.length > PgpLimits.cleartextChars ~/ 2) {
      return const Err(PgpInputTooLarge());
    }
    if (!_survivesCoordinatorParsing(text)) {
      return const Err(PgpCleartextUnsuitable());
    }
    final time = _epochSeconds(now);
    if (time == null) return const Err(PgpClockOutOfRange());
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
            createdAt: max(time, primary.createdAt),
          ),
        ),
      ),
    );
  }

  /// Encrypts [plaintext] to this robot and to [peer], and signs it: the armored `PGP MESSAGE` a robot posts to the chat of an order.
  ///
  /// It reproduces `encryptMessage` of `frontend/src/pgp/index.ts:39-62`: both recipients in that order, so that each trader can read the whole history, AES-256, no compression, and a signature dated 24 hours before [now].
  /// The official client refuses a signature older than its key, so the signature is never dated before the key of this robot.
  /// On `POST /api/chat/` the result travels in the `PGP_message` field with its line breaks turned into backslashes: see [pgpArmorToWire].
  /// The plaintext never leaves the device: a coordinator stores only this block (`chat/models.py:87`), and the robot reads its own messages back by decrypting them.
  /// Fails with [PgpInputTooLarge], [PgpClockOutOfRange], with [PgpPlaintextContainsToken], as the official client refuses to send a message that contains the robot token, with [PgpKeyOutOfDate] when either key cannot be used at [now], and with [PgpKeyUnsupported] when [peer] cannot be encrypted to.
  Result<String, PgpFailure> encryptChatMessage(
    String plaintext, {
    required PgpPublicKey peer,
    DateTime? now,
  }) => encryptChatMessageWith(
    plaintext,
    peer: peer,
    now: now ?? DateTime.now(),
    random: Random.secure(),
  );

  /// [encryptChatMessage] with a given source of randomness: with it and the clock fixed, the result is fixed, byte for byte.
  ///
  /// For tests only: a message is only as secret as [random].
  @visibleForTesting
  Result<String, PgpFailure> encryptChatMessageWith(
    String plaintext, {
    required PgpPublicKey peer,
    required DateTime now,
    required Random random,
  }) {
    final text = utf8.encode(plaintext);
    if (text.length > PgpLimits.messageTextBytes) {
      return const Err(PgpInputTooLarge());
    }
    if (plaintext.contains(_identity.token.reveal())) {
      return const Err(PgpPlaintextContainsToken());
    }
    final own = key._secretKey;
    final time = _epochSeconds(now);
    if (time == null) return const Err(PgpClockOutOfRange());
    if (!own.canReceiveAt(time) || !peer._key.canReceiveAt(time)) {
      return const Err(PgpKeyOutOfDate());
    }
    final data = _canonicalLineEndings(text);
    final signature = textSignature(
      primary: own.primary,
      canonicalData: data,
      seed: _secretKeys.ed25519Seed,
      createdAt: max(time - _backdating.inSeconds, own.primary.createdAt),
    );
    final inner = Uint8List.fromList([
      ...encodePacket(PacketTag.onePassSignature, [
        3,
        SignatureType.text,
        HashId.sha512,
        KeyAlgorithm.eddsaLegacy,
        ...own.primary.keyId,
        1,
      ]),
      ...encodePacket(PacketTag.literalData, [
        _utf8LiteralFormat,
        0,
        ...u32Bytes(time),
        ...data,
      ]),
      ...encodePacket(PacketTag.signature, signature),
    ]);
    final encrypted = encryptPackets(inner, [
      own.subkey,
      peer._key.subkey,
    ], random: random);
    wipe(inner);
    if (encrypted == null) return const Err(PgpKeyUnsupported());
    return Ok(armorEncode(ArmorBlock.message, encrypted));
  }

  /// Decrypts a chat message, with its line breaks or with backslashes in their place, and checks that [sender] signed it, as of [now].
  ///
  /// It reproduces `decryptMessage` of `frontend/src/pgp/index.ts:70-99`: a missing or invalid signature does not hide the text, it is reported as [DecryptedChatMessage.validSignature].
  /// A signature dated after [now], expired, older than the key of [sender] or made when that key was expired is invalid, as in the official client.
  /// [sender] is this robot's own public key when the coordinator attributes the message to this robot's nickname, and the peer's otherwise (`EncryptedApiChat/index.tsx:156`).
  /// Only the envelope the official client and GnuPG write is read, with the partial lengths GnuPG uses for long messages, within the bounds of `PgpLimits`, and nothing is inflated before the message has been authenticated.
  /// Fails with [PgpInputTooLarge], [PgpClockOutOfRange], [PgpArmorMalformed] or [PgpMessageUndecryptable].
  Result<DecryptedChatMessage, PgpFailure> decryptChatMessage(
    String armored, {
    required PgpPublicKey sender,
    DateTime? now,
  }) {
    if (armored.length > PgpLimits.messageArmorChars) {
      return const Err(PgpInputTooLarge());
    }
    final time = _epochSeconds(now);
    if (time == null) return const Err(PgpClockOutOfRange());
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
      // A signature this package cannot read counts as no signature, as in the official client.
      final signature = _tryParseSignature(body);
      if (signature == null) continue;
      final signedData = switch (signature.type) {
        SignatureType.binary => opened.literalData,
        SignatureType.text => _canonicalLineEndings(opened.literalData),
        _ => null,
      };
      final signedAt = signature.createdAt;
      if (signedData != null &&
          signedAt != null &&
          sender._key.acceptsSignatureDates(signature, time) &&
          signature.verify(signedData, sender._key.primary.point)) {
        return Ok(
          DecryptedChatMessage._(
            text,
            validSignature: true,
            signedAt: DateTime.fromMillisecondsSinceEpoch(
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

SignatureBody? _tryParseSignature(Uint8List body) {
  try {
    return SignatureBody.parse(body);
  } on FormatException {
    return null;
  } on UnsupportedPgpException {
    return null;
  }
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
