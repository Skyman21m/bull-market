import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/key_packets.dart';
import 'package:robosats/src/pgp/primitives.dart';
import 'package:robosats/src/pgp/signature_packets.dart';

/// The secret values of an unlocked robot key.
typedef SecretKeys = ({Uint8List ed25519Seed, Uint8List x25519Scalar});

/// An OpenPGP key of the shape RoboSats robots use: an Ed25519 primary key, one user ID and a Curve25519 encryption subkey.
///
/// Only a user ID certified by the primary key and a subkey bound by it are kept, so every instance is internally consistent.
final class TransferableKey {
  final PublicKeyBody primary;

  /// The first user ID the primary key certifies.
  final String userId;

  /// The most recent encryption subkey the primary key binds.
  final PublicKeyBody subkey;

  final ProtectedSecret? _primarySecret;
  final ProtectedSecret? _subkeySecret;

  const TransferableKey._(
    this.primary,
    this.userId,
    this.subkey,
    this._primarySecret,
    this._subkeySecret,
  );

  /// Reads the packets of a public key block ([secret] false) or of a private key block ([secret] true).
  ///
  /// Throws a [FormatException] for malformed packets and an [UnsupportedPgpException] for a key outside the RoboSats shape: another algorithm or version, no certified user ID, no bound Curve25519 subkey, or a secret key that is not passphrase-protected.
  /// Expiry and revocation are not evaluated: robot keys are disposable and carry neither.
  factory TransferableKey.parse(Uint8List bytes, {required bool secret}) {
    final packets = decodePackets(bytes);
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

    String? userId;
    List<int>? pendingUserId;
    ({PublicKeyBody body, ProtectedSecret? secret})? pendingSubkey;
    ({PublicKeyBody body, ProtectedSecret? secret})? subkey;
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
              subkey = pendingSubkey;
            }
          } else if (pendingUserId != null && userId == null) {
            final certified =
                signature.type >= SignatureType.genericCertification &&
                signature.type <= SignatureType.positiveCertification &&
                signature.verify(
                  certificationData(primary, pendingUserId),
                  primary.point,
                );
            if (certified) {
              userId = utf8.decode(pendingUserId, allowMalformed: true);
            }
          }
      }
    }
    if (userId == null || subkey == null) throw const UnsupportedPgpException();
    return TransferableKey._(
      primary,
      userId,
      subkey.body,
      primarySecret,
      subkey.secret,
    );
  }

  /// Generates the key the official RoboSats client would generate, drawing 112 bytes from [random].
  ///
  /// Both packets and both signatures carry [createdAt], in seconds since the Unix epoch.
  /// The result is a deterministic function of the arguments and of the bytes [random] returns.
  static ({TransferableKey key, SecretKeys secretKeys}) generate({
    required String userId,
    required List<int> passphrase,
    required int createdAt,
    required Random random,
  }) {
    final seed = randomBytes(random, 32);
    final scalar = clampX25519Scalar(randomBytes(random, 32));
    final key = TransferableKey._(
      PublicKeyBody.signing(
        createdAt: createdAt,
        publicKey: ed25519PublicKey(seed),
      ),
      userId,
      PublicKeyBody.encryption(
        createdAt: createdAt,
        publicKey: x25519PublicKey(scalar),
      ),
      ProtectedSecret.lock(
        passphrase: passphrase,
        secret: ed25519SecretFromSeed(seed),
        salt: randomBytes(random, 8),
        iv: randomBytes(random, 16),
      ),
      ProtectedSecret.lock(
        passphrase: passphrase,
        secret: x25519SecretFromScalar(scalar),
        salt: randomBytes(random, 8),
        iv: randomBytes(random, 16),
      ),
    );
    return (key: key, secretKeys: (ed25519Seed: seed, x25519Scalar: scalar));
  }

  /// Whether this key carries its passphrase-protected secret part.
  bool get hasSecret => _primarySecret != null && _subkeySecret != null;

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
    if (subkeyPlain == null) return null;
    final Uint8List seed;
    final Uint8List scalar;
    try {
      seed = ed25519SeedFromSecret(primaryPlain);
      scalar = x25519ScalarFromSecret(subkeyPlain);
    } on FormatException {
      throw const UnsupportedPgpException();
    }
    if (!bytesEqual(ed25519PublicKey(seed), primary.point) ||
        !bytesEqual(x25519PublicKey(scalar), subkey.point)) {
      throw const UnsupportedPgpException();
    }
    return (ed25519Seed: seed, x25519Scalar: scalar);
  }

  /// The packets of the public key block, in the order and framing OpenPGP.js 5 writes, with freshly made self-signatures.
  ///
  /// Meant for a generated key: a parsed key is kept as the armored text it came from.
  Uint8List encodePublic(SecretKeys secretKeys) =>
      _encode(secretKeys, secret: false);

  /// The packets of the private key block, each secret part protected by the passphrase.
  Uint8List encodePrivate(SecretKeys secretKeys) =>
      _encode(secretKeys, secret: true);

  Uint8List _encode(SecretKeys secretKeys, {required bool secret}) {
    final primarySecret = _primarySecret;
    final subkeySecret = _subkeySecret;
    if (primarySecret == null || subkeySecret == null) {
      throw StateError('only a key with its secret part can be encoded');
    }
    final userIdBytes = utf8.encode(userId);
    return Uint8List.fromList([
      ...encodePacket(
        secret ? PacketTag.secretKey : PacketTag.publicKey,
        secret ? [...primary.bytes, ...primarySecret.encode()] : primary.bytes,
      ),
      ...encodePacket(PacketTag.userId, userIdBytes),
      ...encodePacket(
        PacketTag.signature,
        selfCertification(
          primary: primary,
          userId: userIdBytes,
          seed: secretKeys.ed25519Seed,
          createdAt: primary.createdAt,
        ),
      ),
      ...encodePacket(
        secret ? PacketTag.secretSubkey : PacketTag.publicSubkey,
        secret ? [...subkey.bytes, ...subkeySecret.encode()] : subkey.bytes,
      ),
      ...encodePacket(
        PacketTag.signature,
        subkeyBinding(
          primary: primary,
          subkey: subkey,
          seed: secretKeys.ed25519Seed,
          createdAt: primary.createdAt,
        ),
      ),
    ]);
  }

  static ({PublicKeyBody body, ProtectedSecret? secret})? _readSubkey(
    RawPacket packet, {
    required bool secret,
  }) {
    if (secret != (packet.tag == PacketTag.secretSubkey)) return null;
    // A subkey this package cannot use is skipped, as GnuPG and OpenPGP.js skip it.
    try {
      final reader = ByteReader(packet.body);
      final body = PublicKeyBody.read(reader);
      if (body.algorithm != KeyAlgorithm.ecdh) return null;
      return (body: body, secret: secret ? ProtectedSecret.read(reader) : null);
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
