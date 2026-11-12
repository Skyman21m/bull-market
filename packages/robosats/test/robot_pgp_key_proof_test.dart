import 'dart:typed_data';

import 'package:robosats/robosats.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:robosats/src/pgp/bytes.dart';
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
          ).proveMadeBy(repositoryRobotIdentity(number)),
        );
      }
    });

    test('fails with the token of another robot', () {
      expect(
        expectErr(
          repositoryRobotKey(1).proveMadeBy(repositoryRobotIdentity(2)),
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
        expect(expectErr(gnupg.proveMadeBy(identity)), isA<PgpInputTooLarge>());
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
        expectErr(pair.proveMadeBy(interopIdentity)),
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

      expectOk(pair.proveMadeBy(interopIdentity));
      expect(
        expectErr(pair.proveMadeBy(interopPeerIdentity)),
        isA<PgpWrongPassphrase>(),
      );
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
