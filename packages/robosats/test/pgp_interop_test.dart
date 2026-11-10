import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/pgp.dart';

/// Replays, without GnuPG, the last run of `tool/pgp_interop.sh` against GnuPG 2.4.4.
///
/// Key generation and signing are deterministic, so the first group pins the exact bytes GnuPG accepted: if the code ever writes anything else, the script has to be run again.
/// The second group reads what GnuPG wrote during that run.
void main() {
  final key = generateInteropKey();
  final unlocked = expectOk(key.unlock(interopIdentity));
  final transcript = interopFile('gpg_transcript.txt');

  group('what GnuPG accepted is still what the code writes', () {
    test('the transcript is the one of this key and ends well', () {
      expect(
        transcript,
        contains(
          'gpg.import_keys(pub_key): imported == 1, fingerprint ${key.publicKey.fingerprint}',
        ),
      );
      expect(transcript, isNot(contains('FAIL')));
      expect(transcript.trimRight(), endsWith('## All checks passed'));
    });

    test('the public key GnuPG imported, 24 hours old', () {
      expect(key.publicKey.armored, interopFile('troc_pub_key'));
    });

    test('the private key GnuPG imported and unlocked with the token', () {
      expect(key.encryptedPrivateKeyArmored, interopFile('troc_enc_priv_key'));
    });

    test('the clear-signed invoice GnuPG verified, SHA512 header included', () {
      expect(
        expectOk(unlocked.signCleartext(interopInvoice, now: interopNow)),
        interopFile('troc_invoice_signed.asc'),
      );
    });

    test('the chat message GnuPG decrypted as peer and as robot', () {
      final decrypted = expectOk(
        unlocked.decryptChatMessage(
          interopFile('troc_chat_to_gpg.asc'),
          sender: key.publicKey,
        ),
      );
      expect(decrypted.text, interopChatText);
      expect(decrypted.validSignature, isTrue);
      expect(decrypted.signedAt, interopNow.subtract(const Duration(days: 1)));
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
      expect(expectOk(key.publicKey.verifyCleartext(signed)), interopInvoice);
      expect(
        expectErr(peer.verifyCleartext(signed)),
        isA<PgpSignatureInvalid>(),
      );
    });

    test('a compressed message GnuPG encrypted to both keys and signed', () {
      final message = interopFile('gpg_chat_to_troc.asc');
      final decrypted = expectOk(
        unlocked.decryptChatMessage(message, sender: peer),
      );
      expect(decrypted.text, interopChatText);
      expect(decrypted.validSignature, isTrue);
      expect(
        expectOk(
          unlocked.decryptChatMessage(message, sender: key.publicKey),
        ).validSignature,
        isFalse,
      );
    });
  });
}
