import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/limits.dart';
import 'package:robosats/src/pgp/primitives.dart';
import 'package:robosats/src/pgp/transferable_key.dart';
import 'package:test/test.dart';

import '../support/craft.dart';
import '../support/pgp.dart';

const _keyDate = CraftedKey.defaultCreatedAt;

DateTime _at(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

final _now = _at(_keyDate + 3600);
final _identity = interopIdentity;
final _token = _identity.token.reveal();

void _expectUnsupported(String armored, {String? reason}) => expect(
  expectErr(PgpPublicKey.parse(armored)),
  isA<PgpKeyUnsupported>(),
  reason: reason,
);

Result<RobotPgpKey, PgpFailure> _parsePair(
  CraftedKey key,
  List<RawPacket> privatePackets,
) => RobotPgpKey.parse(
  publicKey: key.publicArmored,
  encryptedPrivateKey: armorPackets(ArmorBlock.privateKey, privatePackets),
);

void main() {
  group('a public key from a coordinator', () {
    test('is read when it is an honest hand-made key', () {
      final key = CraftedKey().publicKey;
      expect(key.userId, 'RoboSats ID crafted');
      expect(key.createdAt, _at(_keyDate));
    });

    test('is refused when its KDF parameters are not SHA-2 with AES', () {
      // Each of these made dart_pg 2.0.0 throw at the first message sent to the key.
      for (final MapEntry(key: reason, value: kdf) in {
        'empty': [0],
        'two bytes': [2, 1, 1],
        'hash 0xff': [3, 1, 0xff, CipherId.aes128],
        'cipher 0xff': [3, 1, HashId.sha256, 0xff],
        'no cipher': [3, 1, HashId.sha256, 0],
        'MD5 and 3DES': [3, 1, 1, 2],
        'SHA-1': [3, 1, HashId.sha1, CipherId.aes128],
        'SHA-224': [3, 1, HashId.sha224, CipherId.aes128],
        'version 2': [3, 2, HashId.sha256, CipherId.aes128],
        'four bytes': [4, 1, HashId.sha256, CipherId.aes128, 0],
        '200 bytes': [200, ...List.filled(200, 1)],
      }.entries) {
        _expectUnsupported(CraftedKey(kdf: kdf).publicArmored, reason: reason);
      }
    });

    test('is used with the other KDF parameters RFC 6637 allows', () {
      final sender = expectOk(generateInteropKey().unlock(_identity));
      for (final kdf in [
        [3, 1, HashId.sha512, CipherId.aes256],
        [3, 1, HashId.sha384, CipherId.aes192],
      ]) {
        final recipient = CraftedKey(kdf: kdf);
        final message = expectOk(
          sender.encryptChatMessage('hello', peer: recipient.publicKey),
        );
        final decrypted = expectOk(
          recipient
              .unlockedFor(interopPeerIdentity)
              .decryptChatMessage(message, sender: sender.key.publicKey),
        );
        expect(decrypted.text, 'hello');
        expect(decrypted.validSignature, isTrue);
      }
    });

    test('is refused when its X25519 point has a low order', () {
      // The points of RFC 7748 section 6.1 and of the libsodium blocklist: with any of them the shared secret is all zero.
      for (final point in [
        '0000000000000000000000000000000000000000000000000000000000000000',
        '0100000000000000000000000000000000000000000000000000000000000000',
        'e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800',
        '5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157',
        'ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
        'edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
        'eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
      ]) {
        final bytes = Uint8List.fromList(hex.decode(point));
        expect(isLowOrderX25519Point(bytes), isTrue, reason: point);
        _expectUnsupported(
          CraftedKey(subkeyPoint: bytes).publicArmored,
          reason: point,
        );
      }
      expect(
        isLowOrderX25519Point(x25519PublicKey(CraftedKey().scalar)),
        isFalse,
      );
    });

    test('is refused when the subkey is not the one its binding covers', () {
      final other = CraftedKey(label: 'other');
      _expectUnsupported(
        CraftedKey(boundSubkeyBody: other.subkeyBody).publicArmored,
      );
    });

    test('is refused when another key signed the binding', () {
      _expectUnsupported(
        CraftedKey(bindingSeed: CraftedKey(label: 'other').seed).publicArmored,
      );
    });

    test('is refused when the binding is a signature of another type', () {
      // Each is a genuine signature by the primary key over the very data a binding covers.
      for (final type in [0x19, 0x10, 0x28, 0x00]) {
        _expectUnsupported(
          CraftedKey(bindingType: type).publicArmored,
          reason: 'type 0x${type.toRadixString(16)}',
        );
      }
    });

    test('is refused when the binding does not allow encryption', () {
      List<int> flags(int value) => [
        ...creationTime(_keyDate),
        ...subpacket(27, [value], critical: true),
      ];
      for (final signOnly in [0x02, 0x01, 0x20]) {
        _expectUnsupported(
          CraftedKey(bindingHashed: flags(signOnly)).publicArmored,
        );
      }
      for (final hashed in [flags(0x04), flags(0x08), creationTime(_keyDate)]) {
        expectOk(
          PgpPublicKey.parse(CraftedKey(bindingHashed: hashed).publicArmored),
        );
      }
    });

    test('is refused when the user ID is signed, but not certified', () {
      // A certification revocation (0x30) and a binding (0x18) by the primary key over the data a certification covers.
      for (final type in [0x30, 0x18, 0x1f, 0x01]) {
        _expectUnsupported(
          CraftedKey(certificationType: type).publicArmored,
          reason: 'type 0x${type.toRadixString(16)}',
        );
      }
      for (final type in [0x10, 0x11, 0x12, 0x13]) {
        expectOk(
          PgpPublicKey.parse(CraftedKey(certificationType: type).publicArmored),
        );
      }
    });

    test('is refused on another curve, every signature made again', () {
      // The identifier of secp256k1 padded to the length of the Ed25519 one, then of the Curve25519 one.
      const nine = [0x2b, 0x81, 0x04, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x00];
      _expectUnsupported(CraftedKey(primaryOid: nine).publicArmored);
      _expectUnsupported(CraftedKey(subkeyOid: [...nine, 0]).publicArmored);
      _expectUnsupported(CraftedKey(subkeyOid: ed25519Oid).publicArmored);
    });

    test('is refused when a secret subkey packet stands in a public block', () {
      final key = CraftedKey();
      final secretSubkey = key.privatePackets(_token)[3];
      _expectUnsupported(
        armorPackets(ArmorBlock.publicKey, [
          ...key.publicPackets.take(3),
          secretSubkey,
          key.publicPackets[4],
        ]),
      );
    });

    test('is refused with more packets than a key block may hold', () {
      final key = CraftedKey();
      final filler = (tag: PacketTag.userId, body: Uint8List.fromList([0x61]));
      List<RawPacket> withFiller(int count) => [
        ...key.publicPackets,
        for (var i = 0; i < count; i++) filler,
      ];
      expectOk(
        PgpPublicKey.parse(
          armorPackets(
            ArmorBlock.publicKey,
            withFiller(PgpLimits.keyPackets - 5),
          ),
        ),
      );
      _expectUnsupported(
        armorPackets(
          ArmorBlock.publicKey,
          withFiller(PgpLimits.keyPackets - 4),
        ),
      );
    });

    test('is refused with more signatures than a key block may hold', () {
      // Copies of the key's own certification, each a valid signature: the bound counts signature packets, whatever they hold, before any is verified (#69).
      final key = CraftedKey();
      List<RawPacket> withSignatures(List<RawPacket> packets, int count) => [
        ...packets.take(3),
        for (var i = 2; i < count; i++) packets[2],
        ...packets.skip(3),
      ];
      expect(
        withSignatures(
          key.publicPackets,
          PgpLimits.keySignatures,
        ).where((packet) => packet.tag == PacketTag.signature),
        hasLength(PgpLimits.keySignatures),
      );
      expectOk(
        PgpPublicKey.parse(
          armorPackets(
            ArmorBlock.publicKey,
            withSignatures(key.publicPackets, PgpLimits.keySignatures),
          ),
        ),
      );
      _expectUnsupported(
        armorPackets(
          ArmorBlock.publicKey,
          withSignatures(key.publicPackets, PgpLimits.keySignatures + 1),
        ),
      );
      // A private block too, before anything of it is unlocked.
      final private = key.privatePackets(_token);
      expectOk(
        _parsePair(key, withSignatures(private, PgpLimits.keySignatures)),
      );
      expect(
        expectErr(
          _parsePair(key, withSignatures(private, PgpLimits.keySignatures + 1)),
        ),
        isA<PgpKeyUnsupported>(),
      );
    });

    test('is not read at all beyond its size bound', () {
      final huge =
          '${CraftedKey().publicArmored}${' ' * PgpLimits.keyArmorChars}';
      expect(expectErr(PgpPublicKey.parse(huge)), isA<PgpInputTooLarge>());
      expect(
        expectErr(
          RobotPgpKey.parse(
            publicKey: CraftedKey().publicArmored,
            encryptedPrivateKey: huge,
          ),
        ),
        isA<PgpInputTooLarge>(),
      );
    });
  });

  group('the dates of a peer key', () {
    final sender = expectOk(generateInteropKey().unlock(_identity));

    Result<String, PgpFailure> encryptTo(CraftedKey peer, int time) => sender
        .encryptChatMessage('hello', peer: peer.publicKey, now: _at(time));

    test('allow a message from the second the key exists', () {
      final peer = CraftedKey(createdAt: _keyDate + 1000);
      expectOk(encryptTo(peer, _keyDate + 1000));
      expect(
        expectErr(encryptTo(peer, _keyDate + 999)),
        isA<PgpKeyOutOfDate>(),
      );
    });

    test('forbid a message once the key or the subkey has expired', () {
      List<int> expiring(int flags) => [
        ...creationTime(_keyDate),
        ...subpacket(9, u32Bytes(1000)),
        ...subpacket(27, [flags], critical: true),
      ];
      for (final peer in [
        CraftedKey(certificationHashed: expiring(0x03)),
        CraftedKey(bindingHashed: expiring(0x0c)),
      ]) {
        expectOk(encryptTo(peer, _keyDate + 999));
        expect(
          expectErr(encryptTo(peer, _keyDate + 1000)),
          isA<PgpKeyOutOfDate>(),
        );
      }
    });

    test('forbid a message once a self-signature has expired', () {
      List<int> shortLived(int flags) => [
        ...creationTime(_keyDate),
        ...subpacket(3, u32Bytes(1000), critical: true),
        ...subpacket(27, [flags], critical: true),
      ];
      for (final peer in [
        CraftedKey(certificationHashed: shortLived(0x03)),
        CraftedKey(bindingHashed: shortLived(0x0c)),
      ]) {
        expectOk(encryptTo(peer, _keyDate + 999));
        expect(
          expectErr(encryptTo(peer, _keyDate + 1000)),
          isA<PgpKeyOutOfDate>(),
        );
      }
    });

    test(
      'forbid a message before the subkey exists, whatever its binding says',
      () {
        final peer = CraftedKey(subkeyCreatedAt: _keyDate + 1000);
        expectOk(encryptTo(peer, _keyDate + 1000));
        expect(
          expectErr(encryptTo(peer, _keyDate + 999)),
          isA<PgpKeyOutOfDate>(),
        );
      },
    );

    test('forbid a message when a self-signature states no date', () {
      for (final peer in [
        CraftedKey(certificationHashed: subpacket(27, [0x03], critical: true)),
        CraftedKey(bindingHashed: subpacket(27, [0x0c], critical: true)),
      ]) {
        expect(
          expectErr(encryptTo(peer, _keyDate + 1000)),
          isA<PgpKeyOutOfDate>(),
        );
      }
    });

    test('forbid a message when the clock is behind the key of the robot', () {
      expect(
        expectErr(encryptTo(CraftedKey(createdAt: 1000), _keyDate - 1)),
        isA<PgpKeyOutOfDate>(),
      );
    });
  });

  group('a private key from a coordinator', () {
    final key = CraftedKey();
    final other = CraftedKey(label: 'other');

    test(
      'is unlocked when it is an honest hand-made key, whatever its S2K count',
      () {
        // 64 KiB here, 16 MiB on a key of the official client: the count is read from the packet.
        final unlocked = key.unlockedFor(_identity);
        final signed = expectOk(unlocked.signCleartext('text', now: _now));
        expect(
          expectOk(key.publicKey.verifyCleartext(signed, now: _now)),
          'text',
        );
      },
    );

    test(
      'is refused at unlock when a secret value is not the one of its public key',
      () {
        for (final MapEntry(key: reason, value: packets) in {
          'primary': key.privatePackets(
            _token,
            primarySecret: mpiEncode(other.seed),
          ),
          'subkey': key.privatePackets(
            _token,
            subkeySecret: mpiEncode(other.scalar.reversed.toList()),
          ),
          'both': key.privatePackets(
            _token,
            primarySecret: mpiEncode(other.seed),
            subkeySecret: mpiEncode(other.scalar.reversed.toList()),
          ),
          'trailing bytes': key.privatePackets(
            _token,
            primarySecret: Uint8List.fromList([...mpiEncode(key.seed), 0]),
          ),
          'too long': key.privatePackets(
            _token,
            primarySecret: mpiEncode([1, ...key.seed]),
          ),
        }.entries) {
          expect(
            expectErr(expectOk(_parsePair(key, packets)).unlock(_identity)),
            isA<PgpKeyUnsupported>(),
            reason: reason,
          );
        }
      },
    );

    test('is refused when its subkey is not the one of the public block', () {
      // Both subkeys are validly bound to the same primary key.
      final sibling = CraftedKey(subkeyPoint: x25519PublicKey(other.scalar));
      expect(
        expectErr(_parsePair(key, sibling.privatePackets(_token))),
        isA<PgpKeyPairMismatch>(),
      );
    });

    test('is refused under any protection but S2K usage 254', () {
      for (final usage in [255, 253, 0, CipherId.aes256]) {
        expect(
          expectErr(
            _parsePair(
              key,
              key.privatePackets(
                _token,
                protect: (secret, passphrase) =>
                    protectSecret(secret, passphrase, usage: usage),
              ),
            ),
          ),
          isA<PgpKeyUnsupported>(),
          reason: 'usage $usage',
        );
      }
    });

    test(
      'is refused when its ciphertext cannot hold a secret and its check',
      () {
        for (final length in [0, 10, 22]) {
          expect(
            expectErr(
              _parsePair(
                key,
                key.privatePackets(
                  _token,
                  protect: (secret, passphrase) => protectSecret(
                    secret,
                    passphrase,
                    ciphertextLength: length,
                  ),
                ),
              ),
            ),
            isA<PgpKeyUnsupported>(),
            reason: '$length bytes',
          );
        }
      },
    );

    test(
      'is unlocked with the largest S2K count, the one GnuPG 2.4 writes',
      () {
        // Coded count 255 is 65 011 712 bytes, the most the format can ask for.
        expect(s2kByteCount(255), PgpLimits.s2kBytes);
        final parsed = expectOk(
          _parsePair(
            key,
            key.privatePackets(
              _token,
              protect: (secret, passphrase) =>
                  protectSecret(secret, passphrase, codedCount: 255),
            ),
          ),
        );
        expectOk(parsed.unlock(_identity));
        expect(
          expectErr(parsed.unlock(interopPeerIdentity)),
          isA<PgpWrongPassphrase>(),
        );
      },
    );

    test('never prints its secret values once unlocked', () {
      final secretKeys = TransferableKey.parse(
        armorDecode(ArmorBlock.privateKey, key.privateArmored(_token)) ??
            Uint8List(0),
        secret: true,
      ).unlock(_token.codeUnits);
      expect('$secretKeys', 'SecretKeys(<redacted>)');
      expect(secretKeys?.ed25519Seed, key.seed);
      expect(secretKeys?.x25519Scalar, key.scalar);
    });
  });
}
