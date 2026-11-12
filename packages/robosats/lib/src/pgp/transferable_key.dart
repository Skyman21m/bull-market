import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/key_packets.dart';
import 'package:robosats/src/pgp/limits.dart';
import 'package:robosats/src/pgp/primitives.dart';
import 'package:robosats/src/pgp/signature_packets.dart';

/// The secret values of an unlocked robot key.
final class SecretKeys {
  final Uint8List ed25519Seed;

  /// The scalar of the encryption subkey, little-endian.
  final Uint8List x25519Scalar;

  const SecretKeys(this.ed25519Seed, this.x25519Scalar);

  @override
  String toString() => 'SecretKeys(<redacted>)';
}

typedef _Subkey = ({
  PublicKeyBody body,
  ProtectedSecret? secret,
  SignatureBody? binding,
});

/// An OpenPGP key of the shape RoboSats robots use: an Ed25519 primary key, one user ID and a Curve25519 encryption subkey.
///
/// Only a user ID certified by the primary key and a subkey bound by it are kept, so every instance is internally consistent.
final class TransferableKey {
  final PublicKeyBody primary;

  /// The first user ID the primary key certifies.
  final String userId;

  /// The most recent encryption subkey the primary key binds.
  final PublicKeyBody subkey;

  final SignatureBody _certification;
  final SignatureBody _binding;
  final ProtectedSecret? _primarySecret;
  final ProtectedSecret? _subkeySecret;

  const TransferableKey._(
    this.primary,
    this.userId,
    this.subkey,
    this._certification,
    this._binding,
    this._primarySecret,
    this._subkeySecret,
  );

  /// Reads the packets of a public key block ([secret] false) or of a private key block ([secret] true).
  ///
  /// Throws a [FormatException] for malformed packets and an [UnsupportedPgpException] for a key outside the RoboSats shape: another algorithm or version, no certified user ID, no bound Curve25519 subkey, or a secret key that is not passphrase-protected.
  /// Dates are not looked at here, since reading a key needs no clock: see [couldSignAt] and [canReceiveAt].
  /// Revocation is not evaluated: a coordinator keeps the first key of a robot for good.
  factory TransferableKey.parse(Uint8List bytes, {required bool secret}) {
    final packets = decodePackets(bytes, maxPackets: PgpLimits.keyPackets);
    if (packets.isEmpty ||
        packets.first.tag !=
            (secret ? PacketTag.secretKey : PacketTag.publicKey)) {
      throw const UnsupportedPgpException();
    }
    final primaryReader = ByteReader(packets.first.body);
    final primary = PublicKeyBody.read(primaryReader);
    if (primary.algorithm != KeyAlgorithm.eddsaLegacy) {
      throw const UnsupportedPgpException();
    }
    final primarySecret = secret ? ProtectedSecret.read(primaryReader) : null;
    if (!primaryReader.isDone) throw const UnsupportedPgpException();

    String? userId;
    SignatureBody? certification;
    List<int>? pendingUserId;
    _Subkey? pendingSubkey;
    _Subkey? subkey;
    for (final packet in packets.skip(1)) {
      switch (packet.tag) {
        case PacketTag.userId:
          pendingUserId = packet.body;
          pendingSubkey = null;
        case PacketTag.publicSubkey || PacketTag.secretSubkey:
          pendingUserId = null;
          pendingSubkey = _readSubkey(packet, secret: secret);
        case PacketTag.signature:
          final signature = _tryParseSignature(packet.body);
          if (signature == null) continue;
          if (pendingSubkey != null) {
            final flags = signature.keyFlags;
            final bound =
                signature.type == SignatureType.subkeyBinding &&
                (flags == null || flags & KeyFlags.encrypt != 0) &&
                signature.verify(
                  bindingData(primary, pendingSubkey.body),
                  primary.point,
                );
            if (bound &&
                (subkey == null ||
                    pendingSubkey.body.createdAt > subkey.body.createdAt)) {
              subkey = (
                body: pendingSubkey.body,
                secret: pendingSubkey.secret,
                binding: signature,
              );
            }
          } else if (pendingUserId != null && certification == null) {
            final certified =
                signature.type >= SignatureType.genericCertification &&
                signature.type <= SignatureType.positiveCertification &&
                signature.verify(
                  certificationData(primary, pendingUserId),
                  primary.point,
                );
            if (certified) {
              userId = utf8.decode(pendingUserId, allowMalformed: true);
              certification = signature;
            }
          }
      }
    }
    final binding = subkey?.binding;
    if (userId == null ||
        certification == null ||
        subkey == null ||
        binding == null) {
      throw const UnsupportedPgpException();
    }
    return TransferableKey._(
      primary,
      userId,
      subkey.body,
      certification,
      binding,
      primarySecret,
      subkey.secret,
    );
  }

  /// Generates the key the official RoboSats client would generate, drawing 112 bytes from [random], and returns its public and its private packets.
  ///
  /// Both key packets and both signatures carry [createdAt], in seconds since the Unix epoch.
  /// The result is a deterministic function of the arguments and of the bytes [random] returns.
  static ({Uint8List public, Uint8List private}) generate({
    required String userId,
    required List<int> passphrase,
    required int createdAt,
    required Random random,
  }) {
    final seed = randomBytes(random, 32);
    final scalar = clampX25519Scalar(randomBytes(random, 32));
    final primary = PublicKeyBody.signing(
      createdAt: createdAt,
      publicKey: ed25519PublicKey(seed),
    );
    final subkey = PublicKeyBody.encryption(
      createdAt: createdAt,
      publicKey: x25519PublicKey(scalar),
    );
    final seedInteger = ed25519SecretFromSeed(seed);
    final scalarInteger = x25519SecretFromScalar(scalar);
    final primarySecret = ProtectedSecret.lock(
      passphrase: passphrase,
      secret: seedInteger,
      salt: randomBytes(random, 8),
      iv: randomBytes(random, 16),
    );
    final subkeySecret = ProtectedSecret.lock(
      passphrase: passphrase,
      secret: scalarInteger,
      salt: randomBytes(random, 8),
      iv: randomBytes(random, 16),
    );
    final userIdBytes = utf8.encode(userId);
    final certification = encodePacket(
      PacketTag.signature,
      selfCertification(
        primary: primary,
        userId: userIdBytes,
        seed: seed,
        createdAt: createdAt,
      ),
    );
    final binding = encodePacket(
      PacketTag.signature,
      subkeyBinding(
        primary: primary,
        subkey: subkey,
        seed: seed,
        createdAt: createdAt,
      ),
    );
    for (final secret in [seed, scalar, seedInteger, scalarInteger]) {
      wipe(secret);
    }
    // The order and the framing are those of OpenPGP.js 5.
    Uint8List block({required bool secret}) => Uint8List.fromList([
      ...encodePacket(
        secret ? PacketTag.secretKey : PacketTag.publicKey,
        secret ? [...primary.bytes, ...primarySecret.encode()] : primary.bytes,
      ),
      ...encodePacket(PacketTag.userId, userIdBytes),
      ...certification,
      ...encodePacket(
        secret ? PacketTag.secretSubkey : PacketTag.publicSubkey,
        secret ? [...subkey.bytes, ...subkeySecret.encode()] : subkey.bytes,
      ),
      ...binding,
    ]);
    return (public: block(secret: false), private: block(secret: true));
  }

  /// Whether the primary key could have made a signature at [time], in seconds since the Unix epoch.
  ///
  /// OpenPGP.js 5 refuses a signature older than its key ("Key is newer than the signature") and one made when the key, or its self-certification, was not valid.
  bool couldSignAt(int time) =>
      primary.createdAt <= time &&
      _certification.isCurrentAt(time) &&
      !_isExpired(primary, _certification, time);

  /// Whether the dates of [signature], a signature over data, are acceptable at [time]: not from the future, not expired, and made when this key could sign.
  bool acceptsSignatureDates(SignatureBody signature, int time) {
    final signedAt = signature.createdAt;
    return signedAt != null &&
        signature.isCurrentAt(time) &&
        couldSignAt(signedAt);
  }

  /// Whether a message can be encrypted to the subkey at [time]: neither key is from the future, expired, or bound by an expired signature.
  bool canReceiveAt(int time) =>
      couldSignAt(time) &&
      subkey.createdAt <= time &&
      _binding.isCurrentAt(time) &&
      !_isExpired(subkey, _binding, time);

  /// The bytes [unlock] feeds its hashes with a right passphrase of [passphraseLength] bytes, both secret parts together, computed without hashing anything; 0 on a public key.
  ///
  /// A passphrase that does not unlock the primary key's part hashes that part only, since [unlock] stops there.
  int unlockHashedBytes(int passphraseLength) =>
      (_primarySecret?.unlockHashedBytes(passphraseLength) ?? 0) +
      (_subkeySecret?.unlockHashedBytes(passphraseLength) ?? 0);

  /// The secret values behind both packets, or `null` when [passphrase] is wrong.
  ///
  /// Throws a [StateError] on a public key, and an [UnsupportedPgpException] when a secret value does not match its public key.
  SecretKeys? unlock(List<int> passphrase) {
    final primarySecret = _primarySecret;
    final subkeySecret = _subkeySecret;
    if (primarySecret == null || subkeySecret == null) {
      throw StateError('a public key has nothing to unlock');
    }
    final primaryPlain = primarySecret.unlock(passphrase);
    if (primaryPlain == null) return null;
    final subkeyPlain = subkeySecret.unlock(passphrase);
    if (subkeyPlain == null) {
      wipe(primaryPlain);
      return null;
    }
    final Uint8List seed;
    final Uint8List scalar;
    try {
      seed = ed25519SeedFromSecret(primaryPlain);
      scalar = x25519ScalarFromSecret(subkeyPlain);
    } on FormatException {
      throw const UnsupportedPgpException();
    } finally {
      wipe(primaryPlain);
      wipe(subkeyPlain);
    }
    if (!bytesEqual(ed25519PublicKey(seed), primary.point) ||
        !bytesEqual(x25519PublicKey(scalar), subkey.point)) {
      wipe(seed);
      wipe(scalar);
      throw const UnsupportedPgpException();
    }
    return SecretKeys(seed, scalar);
  }

  static bool _isExpired(PublicKeyBody key, SignatureBody by, int time) =>
      by.keyExpiresAfter != 0 && time >= key.createdAt + by.keyExpiresAfter;

  static _Subkey? _readSubkey(RawPacket packet, {required bool secret}) {
    if (secret != (packet.tag == PacketTag.secretSubkey)) return null;
    // A subkey this package cannot use is skipped, as GnuPG and OpenPGP.js skip it.
    try {
      final reader = ByteReader(packet.body);
      final body = PublicKeyBody.read(reader);
      if (body.algorithm != KeyAlgorithm.ecdh) return null;
      final protected = secret ? ProtectedSecret.read(reader) : null;
      if (!reader.isDone) return null;
      return (body: body, secret: protected, binding: null);
    } on UnsupportedPgpException {
      return null;
    }
  }

  static SignatureBody? _tryParseSignature(Uint8List body) {
    // A signature of another kind, or one that cannot be read, is skipped rather than fatal: only the self-signatures matter.
    try {
      return SignatureBody.parse(body);
    } on UnsupportedPgpException {
      return null;
    } on FormatException {
      return null;
    }
  }
}
