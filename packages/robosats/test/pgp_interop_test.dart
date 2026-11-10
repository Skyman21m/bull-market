import 'dart:typed_data';

import 'package:robosats/robosats.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:test/test.dart';

import 'support/pgp.dart';

/// Replays, without GnuPG or OpenPGP.js, the last run of `tool/pgp_interop.sh` against GnuPG 2.4.4 and OpenPGP.js 5.11.3.
///
/// Key generation, signing and, with given randomness, encryption are deterministic, so the first group pins the exact bytes both accepted: if the code ever writes anything else, the script has to be run again.
/// The other groups read what GnuPG and OpenPGP.js wrote during that run.
void main() {
  final key = generateInteropKey();
  final unlocked = expectOk(key.unlock(interopIdentity));
  final transcript = interopFile('transcript.txt');

  group('what GnuPG and OpenPGP.js accepted is still what the code writes', () {
    test('the transcript is the one of this key and ends well', () {
      expect(
        transcript,
        contains(
          'gpg.import_keys(pub_key): imported == 1, fingerprint ${key.publicKey.fingerprint}',
        ),
      );
      expect(transcript, contains('OpenPGP.js 5.11.3 wrote a key'));
      expect(transcript, isNot(contains('FAIL')));
      expect(transcript.trimRight(), endsWith('## All checks passed'));
    });

    test('the public key both imported, 24 hours old', () {
      expect(key.publicKey.armored, interopFile('troc_pub_key'));
    });

    test('the private key both unlocked with the token', () {
      expect(key.encryptedPrivateKeyArmored, interopFile('troc_enc_priv_key'));
    });

    test('the clear-signed invoice both verified, SHA512 header included', () {
      expect(
        expectOk(unlocked.signCleartext(interopInvoice, now: interopNow)),
        interopFile('troc_invoice_signed.asc'),
      );
    });

    test('the chat message both decrypted with the key of the robot', () {
      final message = interopFile('troc_chat_to_peer.asc');
      expect(encryptInteropChatMessage(unlocked), message);
      final peer = expectOk(
        generateInteropPeerKey().unlock(interopPeerIdentity),
      );
      for (final reader in [unlocked, peer]) {
        final decrypted = expectOk(
          reader.decryptChatMessage(message, sender: key.publicKey),
        );
        expect(decrypted.text, interopChatText);
        expect(decrypted.validSignature, isTrue);
        expect(
          decrypted.signedAt,
          interopNow.subtract(const Duration(days: 1)),
        );
      }
    });

    test('the chat messages their own keys decrypted', () {
      for (final name in ['gpg', 'openpgpjs']) {
        final decrypted = expectOk(
          unlocked.decryptChatMessage(
            interopFile('troc_chat_to_$name.asc'),
            sender: key.publicKey,
            now: interopReplayTime,
          ),
        );
        expect(decrypted.text, interopChatText, reason: name);
        expect(decrypted.validSignature, isTrue, reason: name);
      }
    });
  });

  group('what GnuPG wrote is read', () {
    final peer = expectOk(PgpPublicKey.parse(interopFile('gpg_peer_pub_key')));

    test(
      'the public key as a coordinator stores it and hands it to the peer',
      () {
        // `api/utils.py:597-598`: the coordinator keeps GnuPG's export, not the text it received.
        final reexported = expectOk(
          PgpPublicKey.parse(interopFile('troc_pub_key_reexported_by_gpg')),
        );
        expect(reexported, key.publicKey);
        expect(reexported.userId, key.publicKey.userId);
        expect(reexported.createdAt, key.publicKey.createdAt);
        expect(reexported.armored, isNot(key.publicKey.armored));
        expectOk(
          RobotPgpKey.parse(
            publicKey: reexported.armored,
            encryptedPrivateKey: key.encryptedPrivateKeyArmored,
          ),
        );
      },
    );

    test('a key GnuPG generated with ed25519/cert,sign+cv25519/encr', () {
      expect(peer.userId, 'RoboSats ID gnupg-peer');
      expect(transcript, contains('peer key ${peer.fingerprint} generated'));
    });

    test('a text GnuPG clear-signed with the generated key and the token', () {
      final signed = interopFile('gpg_clearsigned_by_troc_key.asc');
      expect(
        signed,
        startsWith('-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n'),
      );
      expect(
        expectOk(key.publicKey.verifyCleartext(signed, now: interopReplayTime)),
        interopInvoice,
      );
      expect(
        expectErr(peer.verifyCleartext(signed, now: interopReplayTime)),
        isA<PgpSignatureInvalid>(),
      );
      // GnuPG signed on the day of the run: the day before, the signature is from the future.
      expect(
        expectErr(key.publicKey.verifyCleartext(signed, now: interopNow)),
        isA<PgpSignatureInvalid>(),
      );
    });

    test('a compressed message GnuPG encrypted to both keys and signed', () {
      final message = interopFile('gpg_chat_to_troc.asc');
      final decrypted = expectOk(
        unlocked.decryptChatMessage(
          message,
          sender: peer,
          now: interopReplayTime,
        ),
      );
      expect(decrypted.text, interopChatText);
      expect(decrypted.validSignature, isTrue);
      expect(
        expectOk(
          unlocked.decryptChatMessage(
            message,
            sender: key.publicKey,
            now: interopReplayTime,
          ),
        ).validSignature,
        isFalse,
      );
    });
  });

  group('what GnuPG wrote beyond a short message is read', () {
    test('a long message, its data packet framed with partial lengths', () {
      final message = interopFile('gpg_chat_long_to_troc.asc');
      // GnuPG starts the tag 18 packet, after two 96-byte session key packets, with a partial length: 0xd2, then a byte from 0xe0 to 0xfe.
      final bytes = armorDecode(ArmorBlock.message, message) ?? Uint8List(194);
      expect(bytes[192], 0xd2);
      expect(bytes[193], inInclusiveRange(0xe0, 0xfe));
      expect(transcript, contains('tag=18 hlen=2 plen=0 partial'));
      final decrypted = expectOk(
        unlocked.decryptChatMessage(
          message,
          sender: expectOk(PgpPublicKey.parse(interopFile('gpg_peer_pub_key'))),
          now: interopReplayTime,
        ),
      );
      expect(decrypted.text, interopLongChatText);
      expect(decrypted.text.length, greaterThan(3900));
      expect(decrypted.validSignature, isTrue);
    });

    test('a private key GnuPG protected: S2K count 255, SHA-1, AES-128', () {
      final protected = expectOk(
        RobotPgpKey.parse(
          publicKey: interopFile('gpg_protected_pub_key'),
          encryptedPrivateKey: interopFile('gpg_protected_enc_priv_key'),
        ),
      );
      expect(protected.publicKey.userId, 'RoboSats ID gnupg-protected');
      expect(transcript, contains('protect count: 65011712 (255)'));
      final signed = expectOk(
        expectOk(
          protected.unlock(interopPeerIdentity),
        ).signCleartext('text', now: interopReplayTime),
      );
      expectOk(
        protected.publicKey.verifyCleartext(signed, now: interopReplayTime),
      );
      expect(
        expectErr(protected.unlock(interopIdentity)),
        isA<PgpWrongPassphrase>(),
      );
    });
  });

  group(
    'what OpenPGP.js 5.11.3 wrote, with the calls of the official client, is read',
    () {
      final peerKey = expectOk(
        RobotPgpKey.parse(
          publicKey: interopFile('openpgpjs_peer_pub_key'),
          encryptedPrivateKey: interopFile('openpgpjs_peer_enc_priv_key'),
        ),
      );
      final peer = peerKey.publicKey;

      test('a key pair it generated, unlocked by its token', () {
        expect(peerKey.isNamedAfter(interopOpenPgpJsIdentity), isTrue);
        final peerUnlocked = expectOk(peerKey.unlock(interopOpenPgpJsIdentity));
        expect(
          expectErr(peerKey.unlock(interopIdentity)),
          isA<PgpWrongPassphrase>(),
        );
        // The same shape as the key this package generates, and as the newest key of the RoboSats repository.
        expect(
          keyShape(ArmorBlock.privateKey, peerKey.encryptedPrivateKeyArmored),
          keyShape(ArmorBlock.privateKey, key.encryptedPrivateKeyArmored),
        );
        final decrypted = expectOk(
          peerUnlocked.decryptChatMessage(
            interopFile('troc_chat_to_openpgpjs.asc'),
            sender: key.publicKey,
            now: interopReplayTime,
          ),
        );
        expect(decrypted.text, interopChatText);
        expect(decrypted.validSignature, isTrue);
      });

      test('texts it clear-signed, returned as it returns them', () {
        for (final name in [
          'openpgpjs_clearsigned',
          'openpgpjs_clearsigned_lines',
        ]) {
          expect(
            expectOk(
              peer.verifyCleartext(
                interopFile('$name.asc'),
                now: interopReplayTime,
              ),
            ),
            interopFile('$name.expected.txt'),
            reason: name,
          );
        }
        // Lines that start with a dash, a line that ends with blanks: the second text exercises the whole framework.
        expect(
          interopFile('openpgpjs_clearsigned_lines.expected.txt'),
          'première ligne\n-dash line\ntrailing space\n\nlast ⚡',
        );
      });

      test('a text signed with its key by this package, which it verified', () {
        expect(
          expectOk(
            peer.verifyCleartext(
              interopFile('troc_clearsigned_by_openpgpjs_key.asc'),
              now: interopReplayTime,
            ),
          ),
          interopInvoice,
        );
      });

      test('a chat message it encrypted to both keys and signed', () {
        final message = interopFile('openpgpjs_chat_to_troc.asc');
        final decrypted = expectOk(
          unlocked.decryptChatMessage(
            message,
            sender: peer,
            now: interopReplayTime,
          ),
        );
        expect(decrypted.text, interopChatText);
        expect(decrypted.validSignature, isTrue);
        // The official client dates the key and the signature one day back, a moment apart.
        expect(decrypted.signedAt?.isBefore(peer.createdAt), isFalse);
        expect(
          expectOk(
            unlocked.decryptChatMessage(
              message,
              sender: key.publicKey,
              now: interopReplayTime,
            ),
          ).validSignature,
          isFalse,
        );
      });

      test('a chat message it encrypted without signing', () {
        final decrypted = expectOk(
          unlocked.decryptChatMessage(
            interopFile('openpgpjs_chat_unsigned.asc'),
            sender: peer,
            now: interopReplayTime,
          ),
        );
        expect(decrypted.text, interopChatText);
        expect(decrypted.validSignature, isFalse);
      });

      test(
        'messages with the same packets as the ones this package writes',
        () {
          List<int> tags(String name) => [
            for (final packet in packetsOf(
              ArmorBlock.message,
              interopFile(name),
            ))
              packet.tag,
          ];
          expect(tags('openpgpjs_chat_to_troc.asc'), [1, 1, 18]);
          expect(tags('troc_chat_to_peer.asc'), [1, 1, 18]);
          expect(
            interopFile('openpgpjs_chat_to_troc.asc').length,
            interopFile('troc_chat_to_peer.asc').length,
          );
        },
      );
    },
  );
}
