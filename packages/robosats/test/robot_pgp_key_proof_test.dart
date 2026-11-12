import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import 'package:robosats/robosats.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/key_packets.dart';
import 'package:robosats/src/pgp/limits.dart';
import 'package:robosats/src/pgp/primitives.dart';
import 'package:robosats/src/pgp/transferable_key.dart';
import 'package:test/test.dart';

import 'support/craft.dart';
import 'support/pgp.dart';

/// The private key of an armored block, as `RobotPgpKey` holds it.
TransferableKey _secretKeyOf(String armored) => TransferableKey.parse(
  armorDecode(ArmorBlock.privateKey, armored) ?? Uint8List(0),
  secret: true,
);

/// [key] locked by [passphrase], each part with the S2K given.
RobotPgpKey _pairOf(
  CraftedKey key,
  String passphrase, {
  required List<int> counts,
  int s2kHashId = HashId.sha256,
  int cipherId = CipherId.aes256,
}) {
  var part = 0;
  return expectOk(
    RobotPgpKey.parse(
      publicKey: key.publicArmored,
      encryptedPrivateKey: armorPackets(
        ArmorBlock.privateKey,
        key.privatePackets(
          passphrase,
          protect: (secret, passphrase) => protectSecret(
            secret,
            passphrase,
            codedCount: counts[part++],
            s2kHashId: s2kHashId,
            cipherId: cipherId,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('the bytes unlocking a private key hashes', () {
    // A token of a Garage Key is 36 characters.
    const tokenBytes = 36;

    test('are 32 MiB for a key of the official client or of Troc', () {
      expect(
        _secretKeyOf(
          repositoryRobotFile(1, 'enc_priv_key'),
        ).unlockHashedBytes(tokenBytes),
        2 * 16777216,
      );
      expect(
        _secretKeyOf(
          generateInteropKey().encryptedPrivateKeyArmored,
        ).unlockHashedBytes(tokenBytes),
        2 * 16777216,
      );
    });

    test(
      'are twice the bound for a key GnuPG protected at its largest count',
      () {
        expect(
          _secretKeyOf(
            interopFile('gpg_protected_enc_priv_key'),
          ).unlockHashedBytes(tokenBytes),
          2 * PgpLimits.s2kBytes,
        );
      },
    );

    test(
      'count each pass when the digest is shorter than the key, with its zero prefix',
      () {
        final key = CraftedKey(label: 'passes');
        final passphrase = 'p' * tokenBytes;
        // SHA-1 gives 20 bytes: AES-128 needs one pass, AES-192 and AES-256 two.
        for (final (cipherId, passes) in [
          (CipherId.aes128, 1),
          (CipherId.aes192, 2),
          (CipherId.aes256, 2),
        ]) {
          final pair = _pairOf(
            key,
            passphrase,
            counts: [96, 96],
            s2kHashId: HashId.sha1,
            cipherId: cipherId,
          );
          expect(
            _secretKeyOf(
              pair.encryptedPrivateKeyArmored,
            ).unlockHashedBytes(tokenBytes),
            2 * (passes * s2kByteCount(96) + passes * (passes - 1) ~/ 2),
            reason: 'cipher $cipherId',
          );
        }
        // SHA-224 gives 28 bytes: two passes for AES-256 only.
        for (final (cipherId, passes) in [
          (CipherId.aes192, 1),
          (CipherId.aes256, 2),
        ]) {
          expect(
            _secretKeyOf(
              _pairOf(
                key,
                passphrase,
                counts: [96, 96],
                s2kHashId: HashId.sha224,
                cipherId: cipherId,
              ).encryptedPrivateKeyArmored,
            ).unlockHashedBytes(tokenBytes),
            2 * (passes * s2kByteCount(96) + passes * (passes - 1) ~/ 2),
            reason: 'cipher $cipherId',
          );
        }
      },
    );

    test(
      'are the salt and the passphrase when they are longer than the count',
      () {
        final pair = _pairOf(CraftedKey(label: 'long'), 'p', counts: [0, 0]);
        // Coded count 0 is 1 024 bytes.
        expect(
          _secretKeyOf(pair.encryptedPrivateKeyArmored).unlockHashedBytes(2000),
          2 * (8 + 2000),
        );
        expect(
          _secretKeyOf(pair.encryptedPrivateKeyArmored).unlockHashedBytes(10),
          2 * 1024,
        );
      },
    );
  });

  group('proving a pair', () {
    test('holds for the official pair of each RoboSats test robot', () {
      for (final number in [1, 2, 3]) {
        expectOk(
          repositoryRobotKey(
            number,
          ).proveMadeBy(repositoryRobotIdentity(number).token),
        );
      }
    });

    test('fails with the token of another robot', () {
      expect(
        expectErr(
          repositoryRobotKey(1).proveMadeBy(repositoryRobotIdentity(2).token),
        ),
        isA<PgpWrongPassphrase>(),
      );
    });

    test('fails over the bound, before unlocking, whatever the token', () {
      // GnuPG protected it at count 255 with SHA-1 and AES-128, and its token unlocks it (`pgp_interop_test.dart`).
      final gnupg = expectOk(
        RobotPgpKey.parse(
          publicKey: interopFile('gpg_protected_pub_key'),
          encryptedPrivateKey: interopFile('gpg_protected_enc_priv_key'),
        ),
      );
      for (final identity in [interopPeerIdentity, interopIdentity]) {
        expect(
          expectErr(gnupg.proveMadeBy(identity.token)),
          isA<PgpInputTooLarge>(),
        );
      }
    });

    test('fails when the secret values are not those of the public key', () {
      final key = CraftedKey(label: 'values');
      final token = interopIdentity.token.reveal();
      final pair = expectOk(
        RobotPgpKey.parse(
          publicKey: key.publicArmored,
          encryptedPrivateKey: armorPackets(
            ArmorBlock.privateKey,
            key.privatePackets(
              token,
              subkeySecret: mpiEncode(
                CraftedKey(label: 'other values').scalar.reversed.toList(),
              ),
            ),
          ),
        ),
      );

      expect(
        expectErr(pair.proveMadeBy(interopIdentity.token)),
        isA<PgpKeyUnsupported>(),
      );
    });

    test('holds for a crafted pair locked by the token, at a small count', () {
      final key = CraftedKey(label: 'small');
      final pair = _pairOf(
        key,
        interopIdentity.token.reveal(),
        counts: [96, 96],
      );

      expectOk(pair.proveMadeBy(interopIdentity.token));
      expect(
        expectErr(pair.proveMadeBy(interopPeerIdentity.token)),
        isA<PgpWrongPassphrase>(),
      );
    });
  });

  group('the S2K of a part', () {
    test(
      'proves its passphrase only iterated and salted, over SHA-1 or SHA-2, with AES',
      () {
        bool proves({
          int s2kType = 3,
          int s2kHashId = HashId.sha256,
          int saltLength = 8,
          int codedCount = 224,
          int cipherId = CipherId.aes256,
        }) => ProtectedSecret.provesPassphraseWith(
          s2kType: s2kType,
          s2kHashId: s2kHashId,
          saltLength: saltLength,
          codedCount: codedCount,
          cipherId: cipherId,
        );

        expect(proves(), isTrue);
        for (final hash in [
          HashId.sha1,
          HashId.sha224,
          HashId.sha384,
          HashId.sha512,
        ]) {
          expect(proves(s2kHashId: hash), isTrue, reason: 'hash $hash');
        }
        expect(proves(codedCount: 0), isTrue);
        expect(proves(codedCount: 255), isTrue);
        // A simple S2K derives the hash of the passphrase alone: over SHA-256, the token hash every coordinator holds.
        expect(proves(s2kType: 0), isFalse);
        expect(proves(s2kType: 0, saltLength: 0), isFalse);
        expect(proves(s2kType: 1), isFalse);
        for (final type in [2, 4, 100, 101, 255]) {
          expect(proves(s2kType: type), isFalse, reason: 'type $type');
        }
        for (final length in [0, 1, 7, 9, 16]) {
          expect(proves(saltLength: length), isFalse, reason: 'salt $length');
        }
        // MD5 (1), RIPEMD-160 (3) and unknown hashes.
        for (final hash in [0, 1, 3, 12, 255]) {
          expect(proves(s2kHashId: hash), isFalse, reason: 'hash $hash');
        }
        for (final count in [-1, 256]) {
          expect(proves(codedCount: count), isFalse, reason: 'count $count');
        }
        for (final cipher in [0, 2, 3, 10, 13]) {
          expect(proves(cipherId: cipher), isFalse, reason: 'cipher $cipher');
        }
      },
    );

    test('other than iterated and salted is refused by the parser', () {
      // The parser is the first wall: a simple or salted S2K keyed by the token hash never becomes a key, before any proof.
      final key = CraftedKey(label: 'simple s2k');
      final tokenHash = Uint8List.fromList(
        sha256.convert(utf8.encode(interopIdentity.token.reveal())).bytes,
      );
      for (final s2kType in [0, 1]) {
        expect(
          expectErr(
            RobotPgpKey.parse(
              publicKey: key.publicArmored,
              encryptedPrivateKey: armorPackets(
                ArmorBlock.privateKey,
                key.privatePackets(
                  'unused',
                  protect: (secret, _) =>
                      protectSecretWithKey(secret, tokenHash, s2kType: s2kType),
                ),
              ),
            ),
          ),
          isA<PgpKeyUnsupported>(),
          reason: 'S2K type $s2kType',
        );
      }
    });
  });

  group('a proven pair', () {
    test('is the pair as made, for a pair made by this package', () {
      final made = generateInteropKey();

      final proven = expectOk(made.proveMadeBy(interopIdentity.token));

      expect(proven, made);
      expect(proven.publicKey.armored, made.publicKey.armored);
    });

    test(
      'keeps only the packets the proof checked, whatever the blocks held',
      () {
        final key = CraftedKey(label: 'carried', userId: 'RoboSats ID carried');
        final other = CraftedKey(label: 'other key');
        final token = interopIdentity.token.reveal();
        final foreignUserId = (
          tag: PacketTag.userId,
          body: Uint8List.fromList(utf8.encode('coordinator was here')),
        );
        // Unhashed subpackets nobody signs: an issuer and padding.
        RawPacket withUnhashed(Uint8List body) => (
          tag: PacketTag.signature,
          body: Uint8List.fromList([
            ...body.sublist(0, 6 + (body[4] << 8 | body[5])),
            // One subpacket of 601 bytes, type and data, behind its two-byte length.
            ...u16Bytes(2 + 601),
            193,
            153,
            16,
            ...List.filled(600, 0x41),
            ...body.sublist(6 + (body[4] << 8 | body[5]) + 2),
          ]),
        );
        final padded = expectOk(
          RobotPgpKey.parse(
            publicKey: armorPackets(ArmorBlock.publicKey, [
              ...key.publicPackets,
              foreignUserId,
              ...other.publicPackets,
            ]),
            encryptedPrivateKey: armorPackets(ArmorBlock.privateKey, [
              for (final packet in key.privatePackets(token))
                packet.tag == PacketTag.signature
                    ? withUnhashed(packet.body)
                    : packet,
              foreignUserId,
              (
                tag: PacketTag.secretKey,
                body: Uint8List.fromList([
                  ...other.primaryBody,
                  ...unprotectedSecret(mpiEncode(other.seed)),
                ]),
              ),
            ]),
          ),
        );
        final clean = expectOk(
          RobotPgpKey.parse(
            publicKey: key.publicArmored,
            encryptedPrivateKey: key.privateArmored(token),
          ),
        );
        expect(padded.publicKey, clean.publicKey);
        expect(padded, isNot(clean));

        final proven = expectOk(padded.proveMadeBy(interopIdentity.token));

        expect(proven, clean);
        expect(proven.publicKey.armored, clean.publicKey.armored);
        expect(
          packetsOf(
            ArmorBlock.publicKey,
            proven.publicKey.armored,
          ).map((packet) => packet.tag),
          [
            PacketTag.publicKey,
            PacketTag.userId,
            PacketTag.signature,
            PacketTag.publicSubkey,
            PacketTag.signature,
          ],
        );
        expect(
          packetsOf(
            ArmorBlock.privateKey,
            proven.encryptedPrivateKeyArmored,
          ).map((packet) => packet.tag),
          [
            PacketTag.secretKey,
            PacketTag.userId,
            PacketTag.signature,
            PacketTag.secretSubkey,
            PacketTag.signature,
          ],
        );
        expect(proven.publicKey.userId, 'RoboSats ID carried');
        expect(expectOk(proven.proveMadeBy(interopIdentity.token)), clean);
      },
    );

    test('of each RoboSats test robot still unlocks, under its own key', () {
      for (final number in [1, 2, 3]) {
        final official = repositoryRobotKey(number);
        final identity = repositoryRobotIdentity(number);

        final proven = expectOk(official.proveMadeBy(identity.token));

        expect(proven.publicKey, official.publicKey, reason: 'robot $number');
        expect(proven.publicKey.userId, official.publicKey.userId);
        expect(
          '${expectOk(proven.unlock(identity))}',
          'UnlockedRobotPgpKey(${official.publicKey.fingerprint})',
        );
      }
    });
  });

  group('two pairs', () {
    test('are equal when their keys and their private packets are', () {
      final key = CraftedKey(label: 'equal');
      final one = _pairOf(key, 'passphrase', counts: [96, 96]);
      final again = _pairOf(key, 'passphrase', counts: [96, 96]);
      final relocked = _pairOf(key, 'passphrase', counts: [97, 96]);

      expect(one, again);
      expect(one, isNot(relocked));
      expect(one.publicKey, relocked.publicKey);
    });
  });
}
