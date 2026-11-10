import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:robosats/robosats.dart';
import 'package:robosats/src/pgp/armor.dart';
import 'package:robosats/src/pgp/bytes.dart';
import 'package:robosats/src/pgp/signature_packets.dart';
import 'package:test/test.dart';

import 'support/pgp.dart';
import 'support/vectors.dart';

/// A fixed "now" for every generated artefact: the key is then dated 2026-11-08 12:00:00 UTC.
final _now = DateTime.utc(2026, 11, 9, 12);

/// A robot of the vectors file that the RoboSats repository has no key for: index 0 of the example Garage Key.
final _identity = identityOf(garageKeyRobots.first['token'] as String);

RobotPgpKey _generate([String label = 'troc']) => expectOk(
  RobotPgpKey.generateWith(
    _identity,
    now: _now,
    random: DeterministicRandom(label),
  ),
);

/// `_is_well_formed_pgp_key` of `api/utils.py:496-518`, the shape check a coordinator runs before GnuPG sees the public key.
bool _coordinatorFindsWellFormed(String keyText) {
  final lines = const LineSplitter().convert(keyText.trim());
  if (lines.length < 4) return false;
  if (!lines.first.startsWith('-----BEGIN PGP PUBLIC KEY BLOCK-----')) {
    return false;
  }
  if (!lines.last.startsWith('-----END PGP PUBLIC KEY BLOCK-----')) {
    return false;
  }
  final blank = lines.indexWhere((line) => line.trim().isEmpty, 1);
  if (blank < 1 || blank >= lines.length - 1) return false;
  final bodyLine = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');
  return lines
      .sublist(blank + 1, lines.length - 1)
      .every((line) => line.startsWith('=') || bodyLine.hasMatch(line));
}

void main() {
  const repositoryFingerprints = {
    1: '3221562385A735A8BCFBB0BC2E345B4B498D9724',
    2: 'EAA47013A346EC9F1C8305275E8DD403D3FB182D',
    3: '177E43B670BF6192F9FF597B07C01BE5DB91A93F',
  };
  // Creation times read by `gpg --list-packets` on `tests/robots/*/enc_priv_key`.
  const repositoryCreationTimes = {1: 1699986799, 2: 1699195195, 3: 1740323676};

  for (final number in [1, 2, 3]) {
    group(
      'key of RoboSats test robot $number, made by the official client',
      () {
        final identity = repositoryRobotIdentity(number);
        final key = repositoryRobotKey(number);

        test('has the fingerprint GnuPG reports', () {
          expect(key.publicKey.fingerprint, repositoryFingerprints[number]);
        });

        test('is named after the hash id of its token', () {
          expect(key.publicKey.userId, identity.pgpUserId);
          expect(key.isNamedAfter(identity), isTrue);
          expect(key.isNamedAfter(_identity), isFalse);
        });

        test('carries its creation time', () {
          expect(
            key.publicKey.createdAt,
            DateTime.fromMillisecondsSinceEpoch(
              (repositoryCreationTimes[number] ?? 0) * 1000,
              isUtc: true,
            ),
          );
          expect(key.publicKey.createdAt.isUtc, isTrue);
        });

        test('keeps both armored blocks', () {
          expect(key.publicKey.armored, repositoryRobotFile(number, 'pub_key'));
          expect(
            key.encryptedPrivateKeyArmored,
            repositoryRobotFile(number, 'enc_priv_key'),
          );
        });

        test('is unlocked by its token and by no other', () {
          expectOk(key.unlock(identity));
          expect(expectErr(key.unlock(_identity)), isA<PgpWrongPassphrase>());
        });

        test('signs a text that its public key verifies', () {
          final signed = expectOk(
            expectOk(key.unlock(identity)).signCleartext('lnbcrt1invoice'),
          );
          expect(
            expectOk(key.publicKey.verifyCleartext(signed)),
            'lnbcrt1invoice',
          );
        });
      },
    );
  }

  group('PgpPublicKey.parse', () {
    final armored = repositoryRobotFile(1, 'pub_key');

    test('reads a key carried on one line with backslashes', () {
      final key = expectOk(PgpPublicKey.parse(pgpArmorToWire(armored)));
      expect(key.fingerprint, repositoryFingerprints[1]);
      expect(key.armored, armored);
    });

    test('reads a key with CRLF line endings', () {
      final key = expectOk(
        PgpPublicKey.parse(armored.replaceAll('\n', '\r\n')),
      );
      expect(key, expectOk(PgpPublicKey.parse(armored)));
      expect(key.armored, isNot(contains('\r')));
    });

    test('reads the public key the official client made, not only GnuPG', () {
      // `pub_key` is a GnuPG export with old-format packet headers: a generated key has the new-format headers of OpenPGP.js.
      expect(packetsOf(ArmorBlock.publicKey, armored), hasLength(5));
      final generated = _generate().publicKey;
      expect(
        expectOk(PgpPublicKey.parse(generated.armored)).fingerprint,
        generated.fingerprint,
      );
    });

    test('rejects text that is not an armored public key', () {
      for (final text in [
        '',
        'not a key',
        repositoryRobotFile(1, 'enc_priv_key'),
        repositoryRobotFile(1, 'signed_message'),
        armored.replaceFirst('\n\n', '\n'),
        armored.replaceFirst('mDME', 'mDM*'),
        '$armored$armored',
      ]) {
        expect(
          expectErr(PgpPublicKey.parse(text)),
          isA<PgpArmorMalformed>(),
          reason: text.split('\n').first,
        );
      }
    });

    test('rejects a key whose checksum line does not match', () {
      expect(
        expectErr(PgpPublicKey.parse(armored.replaceFirst('=32+r', '=32+s'))),
        isA<PgpArmorMalformed>(),
      );
    });

    test('accepts a key without checksum line, as RFC 9580 allows', () {
      expectOk(PgpPublicKey.parse(armored.replaceFirst('=32+r\n', '')));
    });

    test('rejects armored data that is not a robot key', () {
      String armorOf(List<int> bytes) =>
          armorEncode(ArmorBlock.publicKey, bytes);
      final packets = packetsOf(ArmorBlock.publicKey, armored);
      List<int> without(int index) => [
        for (final (i, packet) in packets.indexed)
          if (i != index) ...encodePacket(packet.tag, packet.body),
      ];
      final tamperedUserId = [
        for (final packet in packets)
          ...encodePacket(
            packet.tag,
            packet.tag == PacketTag.userId
                ? utf8.encode('RoboSats ID forged')
                : packet.body,
          ),
      ];
      for (final MapEntry(key: reason, value: bytes) in {
        'garbage': [1, 2, 3],
        'truncated packet': without(-1).sublist(0, 40),
        'no user id': without(1),
        'no self-certification': without(2),
        'no subkey': [...without(3).sublist(0, without(3).length - 122)],
        'no subkey binding': without(4),
        'user id that the key did not certify': tamperedUserId,
      }.entries) {
        expect(
          expectErr(PgpPublicKey.parse(armorOf(bytes))),
          isA<PgpKeyUnsupported>(),
          reason: reason,
        );
      }
    });

    test('has value equality on the key, not on the armor', () {
      final a = expectOk(PgpPublicKey.parse(armored));
      final b = expectOk(PgpPublicKey.parse(pgpArmorToWire(armored)));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(repositoryRobotKey(2).publicKey));
    });
  });

  group('RobotPgpKey.parse', () {
    test('rejects a private key that belongs to another public key', () {
      expect(
        expectErr(
          RobotPgpKey.parse(
            publicKey: repositoryRobotFile(1, 'pub_key'),
            encryptedPrivateKey: repositoryRobotFile(2, 'enc_priv_key'),
          ),
        ),
        isA<PgpKeyPairMismatch>(),
      );
    });

    test('rejects text that is not an armored private key', () {
      for (final text in ['', 'nope', repositoryRobotFile(1, 'pub_key')]) {
        expect(
          expectErr(
            RobotPgpKey.parse(
              publicKey: repositoryRobotFile(1, 'pub_key'),
              encryptedPrivateKey: text,
            ),
          ),
          isA<PgpArmorMalformed>(),
        );
      }
    });

    test('reports the failure of the public key first', () {
      expect(
        expectErr(
          RobotPgpKey.parse(
            publicKey: 'nope',
            encryptedPrivateKey: repositoryRobotFile(1, 'enc_priv_key'),
          ),
        ),
        isA<PgpArmorMalformed>(),
      );
    });

    test('rejects a private key whose secret part is not protected', () {
      final packets = packetsOf(
        ArmorBlock.privateKey,
        repositoryRobotFile(1, 'enc_priv_key'),
      );
      final unprotected = [
        for (final packet in packets)
          ...encodePacket(
            packet.tag,
            packet.tag == PacketTag.secretKey
                // Usage octet 0 after the 51 bytes of the public part: a secret key stored in the clear.
                ? [...packet.body.sublist(0, 51), 0, ...List.filled(36, 1)]
                : packet.body,
          ),
      ];
      expect(
        expectErr(
          RobotPgpKey.parse(
            publicKey: repositoryRobotFile(1, 'pub_key'),
            encryptedPrivateKey: armorEncode(
              ArmorBlock.privateKey,
              unprotected,
            ),
          ),
        ),
        isA<PgpKeyUnsupported>(),
      );
    });

    test('reads both blocks carried on one line with backslashes', () {
      final key = expectOk(
        RobotPgpKey.parse(
          publicKey: pgpArmorToWire(repositoryRobotFile(1, 'pub_key')),
          encryptedPrivateKey: pgpArmorToWire(
            repositoryRobotFile(1, 'enc_priv_key'),
          ),
        ),
      );
      expect(key, repositoryRobotKey(1));
      expect(key.hashCode, repositoryRobotKey(1).hashCode);
      expect(key, isNot(repositoryRobotKey(2)));
    });
  });

  group('RobotPgpKey.generate', () {
    final key = _generate();

    test('is a deterministic function of identity, clock and randomness', () {
      final again = _generate();
      expect(again.publicKey.armored, key.publicKey.armored);
      expect(again.encryptedPrivateKeyArmored, key.encryptedPrivateKeyArmored);
      expect(again, key);
      expect(
        _generate('other randomness').publicKey.fingerprint,
        isNot(key.publicKey.fingerprint),
      );
    });

    test('names the key after the hash id, as the official client does', () {
      expect(key.publicKey.userId, 'RoboSats ID ${_identity.hashId.hex}');
      expect(key.isNamedAfter(_identity), isTrue);
    });

    test('dates the key exactly 24 hours before now', () {
      expect(key.publicKey.createdAt, DateTime.utc(2026, 11, 8, 12));
      // A coordinator refuses a key younger than 12 hours (`api/utils.py:582-594`).
      expect(
        _now.difference(key.publicKey.createdAt),
        greaterThan(const Duration(hours: 12)),
      );
    });

    test('drops the fraction of a second, as OpenPGP dates do', () {
      final late = expectOk(
        RobotPgpKey.generateWith(
          _identity,
          now: _now.add(const Duration(milliseconds: 999)),
          random: DeterministicRandom('troc'),
        ),
      );
      expect(late.publicKey.armored, key.publicKey.armored);
    });

    test('locks the private key with the token', () {
      expectOk(key.unlock(_identity));
      expect(
        expectErr(key.unlock(repositoryRobotIdentity(1))),
        isA<PgpWrongPassphrase>(),
      );
    });

    test('has the shape of the newest key of the RoboSats repository', () {
      // Test robot 3 dates from February 2025: test robots 1 and 2, from 2023, differ only by a SHA-256 subkey binding.
      expect(
        keyShape(ArmorBlock.privateKey, key.encryptedPrivateKeyArmored),
        keyShape(ArmorBlock.privateKey, repositoryRobotFile(3, 'enc_priv_key')),
      );
    });

    test('exports the public key with the same packets, minus the secrets', () {
      final public = packetsOf(ArmorBlock.publicKey, key.publicKey.armored);
      final private = packetsOf(
        ArmorBlock.privateKey,
        key.encryptedPrivateKeyArmored,
      );
      expect(public.map((packet) => packet.tag), [6, 13, 2, 14, 2]);
      expect(private.map((packet) => packet.tag), [5, 13, 2, 7, 2]);
      for (final index in [1, 2, 4]) {
        expect(public[index].body, private[index].body);
      }
      expect(private[0].body.sublist(0, public[0].body.length), public[0].body);
      expect(private[3].body.sublist(0, public[3].body.length), public[3].body);
    });

    test('armors both blocks as the official client does', () {
      final reference = repositoryRobotFile(3, 'enc_priv_key').split('\n');
      for (final armored in [
        key.publicKey.armored,
        key.encryptedPrivateKeyArmored,
      ]) {
        final lines = armored.split('\n');
        expect(lines[1], isEmpty, reason: 'no Version or Comment header');
        expect(lines.last, isEmpty, reason: 'ends with a line feed');
        expect(lines[lines.length - 3], matches(r'^=[A-Za-z0-9+/]{4}$'));
        expect(lines[2].length, reference[2].length);
        expect(armored, isNot(contains('\r')));
        expect(armored, isNot(contains(': ')));
      }
      expect(
        key.encryptedPrivateKeyArmored.split('\n').length,
        reference.length + 1,
        reason: 'same number of lines, plus the final line feed',
      );
    });

    test('passes the shape check of the coordinator', () {
      expect(_coordinatorFindsWellFormed(key.publicKey.armored), isTrue);
      expect(
        _coordinatorFindsWellFormed(repositoryRobotFile(1, 'pub_key')),
        isTrue,
      );
      expect(
        _coordinatorFindsWellFormed(repositoryRobotFile(1, 'enc_priv_key')),
        isFalse,
      );
    });

    test('reads back the blocks it wrote', () {
      final parsed = expectOk(
        RobotPgpKey.parse(
          publicKey: key.publicKey.armored,
          encryptedPrivateKey: key.encryptedPrivateKeyArmored,
        ),
      );
      expect(parsed, key);
      expect(parsed.publicKey.createdAt, key.publicKey.createdAt);
      expectOk(parsed.unlock(_identity));
    });

    test('handles an Ed25519 seed that starts with a zero byte', () {
      // One key in 256: the secret integer is then stored on 31 bytes, which dart_pg 2.0.0 cannot read back.
      final shortSeedKey = expectOk(
        RobotPgpKey.generateWith(
          _identity,
          now: _now,
          random: ScriptedRandom([0, 0, ...List.filled(30, 7)]),
        ),
      );
      final parsed = expectOk(
        RobotPgpKey.parse(
          publicKey: shortSeedKey.publicKey.armored,
          encryptedPrivateKey: shortSeedKey.encryptedPrivateKeyArmored,
        ),
      );
      final signed = expectOk(
        expectOk(parsed.unlock(_identity)).signCleartext('bcrt1qaddress'),
      );
      expect(
        expectOk(parsed.publicKey.verifyCleartext(signed)),
        'bcrt1qaddress',
      );
    });

    test('uses the system clock and a secure generator by default', () {
      final before = DateTime.now().toUtc();
      final fresh = expectOk(RobotPgpKey.generate(_identity));
      final age = before.difference(fresh.publicKey.createdAt);
      expect(age, greaterThanOrEqualTo(const Duration(hours: 24)));
      expect(age, lessThan(const Duration(hours: 24, minutes: 1)));
      expect(fresh.publicKey.fingerprint, isNot(key.publicKey.fingerprint));
      expect(
        expectOk(RobotPgpKey.generate(_identity)).publicKey.fingerprint,
        isNot(fresh.publicKey.fingerprint),
      );
    });

    test('fails, without throwing, on a clock outside the range of OpenPGP dates', () {
      for (final now in [
        DateTime.utc(1969),
        // The key would be dated before the Unix epoch.
        DateTime.utc(1970, 1, 1, 12),
        DateTime.utc(2107),
        DateTime.utc(275760, 9, 13),
      ]) {
        expect(
          expectErr(
            RobotPgpKey.generateWith(
              _identity,
              now: now,
              random: DeterministicRandom('troc'),
            ),
          ),
          isA<PgpClockOutOfRange>(),
        );
      }
      expectOk(
        RobotPgpKey.generateWith(
          _identity,
          now: DateTime.utc(1970, 1, 2),
          random: DeterministicRandom('troc'),
        ),
      );
    });
  });

  group('a clock outside 1970 to 2106', () {
    final key = _generate();
    final unlocked = expectOk(key.unlock(_identity));
    final signed = expectOk(unlocked.signCleartext('lnbc1', now: _now));
    final message = expectOk(
      unlocked.encryptChatMessage('hello', peer: key.publicKey, now: _now),
    );

    for (final now in [DateTime.utc(1969, 12, 31), DateTime.utc(2107)]) {
      test('is a failure of every operation, never an exception: ${now.year}', () {
        expect(
          expectErr(unlocked.signCleartext('lnbc1', now: now)),
          isA<PgpClockOutOfRange>(),
        );
        expect(
          expectErr(key.publicKey.verifyCleartext(signed, now: now)),
          isA<PgpClockOutOfRange>(),
        );
        expect(
          expectErr(
            unlocked.encryptChatMessage('hello', peer: key.publicKey, now: now),
          ),
          isA<PgpClockOutOfRange>(),
        );
        expect(
          expectErr(
            unlocked.decryptChatMessage(
              message,
              sender: key.publicKey,
              now: now,
            ),
          ),
          isA<PgpClockOutOfRange>(),
        );
      });
    }
  });

  group('first-contact Authorization value with a generated key', () {
    test('survives the parsing of the coordinator', () {
      final key = _generate();
      final value = _identity.firstContactAuthorizationHeader(
        pgpPublicKey: key.publicKey.armored,
        pgpEncryptedPrivateKey: key.encryptedPrivateKeyArmored,
      );
      expect(value, isNot(contains('\n')));
      // `robosats/middleware.py:53-59` splits on " | " and requires exactly four parts.
      final parts = value.split(' | ');
      expect(parts, hasLength(4));
      expect(parts[0], _identity.authorizationHeader());
      expect(parts[3], 'Nostr ${_identity.nostrKeyPair().publicKeyHex}');
      // `robosats/middleware.py:122-125` drops the labels, `api/utils.py:525-526` restores the line feeds.
      String received(String part, String label) => part
          .replaceAll(label, '')
          .replaceAll('\r\n', '\n')
          .replaceAll(r'\', '\n');
      final publicKey = received(parts[1], 'Public ');
      final encryptedPrivateKey = received(parts[2], 'Private ');
      expect(publicKey, key.publicKey.armored);
      expect(encryptedPrivateKey, key.encryptedPrivateKeyArmored);
      expect(_coordinatorFindsWellFormed(publicKey), isTrue);

      final stored = expectOk(
        RobotPgpKey.parse(
          publicKey: publicKey,
          encryptedPrivateKey: encryptedPrivateKey,
        ),
      );
      expect(stored, key);
      // Restoring a robot: the token alone unlocks what the coordinator hands back.
      expectOk(stored.unlock(_identity));
    });
  });

  group('UnlockedRobotPgpKey.signCleartext', () {
    final key = _generate();
    final unlocked = expectOk(key.unlock(_identity));
    const invoice = 'lnbcrt500u1p5xyzzypp5examplexexamplexexample';

    test('starts with the exact header the coordinator splits on', () {
      final signed = expectOk(unlocked.signCleartext(invoice, now: _now));
      // `api/utils.py:642-644`.
      const header = '-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n';
      const footer = '-----BEGIN PGP SIGNATURE-----';
      expect(signed, startsWith(header));
      expect(signed, isNot(contains('\r')));
      expect(signed, isNot(contains('Version')));
      expect(signed, isNot(contains('Comment')));
      expect(signed, endsWith('-----END PGP SIGNATURE-----\n'));
      expect(signed.split(header)[1].split(footer)[0].trim(), invoice);
    });

    test('is deterministic for a given text and time', () {
      expect(
        expectOk(unlocked.signCleartext(invoice, now: _now)),
        expectOk(unlocked.signCleartext(invoice, now: _now)),
      );
      expect(
        expectOk(unlocked.signCleartext(invoice, now: _now)),
        isNot(
          expectOk(
            unlocked.signCleartext(
              invoice,
              now: _now.add(const Duration(seconds: 1)),
            ),
          ),
        ),
      );
    });

    test(
      'makes one text signature over SHA-512, dated now, like the official client',
      () {
        final signed = expectOk(unlocked.signCleartext(invoice, now: _now));
        final parts = cleartextDecode(signed);
        if (parts == null) fail('not a cleartext signed message');
        final packets = decodePackets(parts.signature, maxPackets: 8);
        expect(packets.map((packet) => packet.tag), [PacketTag.signature]);
        final signature = SignatureBody.parse(packets.single.body);
        expect(signature.type, SignatureType.text);
        expect(signature.hashId, 10);
        expect(signature.createdAt, _now.millisecondsSinceEpoch ~/ 1000);
        // Creation time and issuer are critical, as in the self-signatures OpenPGP.js 5 writes.
        expect(hex.encode(packets.single.body.sublist(0, 6)), '0401160a0027');
        expect(
          hex.encode(packets.single.body.sublist(6, 45)),
          '0582${hex.encode(u32Bytes(_now.millisecondsSinceEpoch ~/ 1000))}'
          '0990${key.publicKey.fingerprint.substring(24).toLowerCase()}'
          '162104${key.publicKey.fingerprint.toLowerCase()}',
        );
        expect(packets.single.body.sublist(45, 47), [0, 0]);
      },
    );

    test('is verified by its own public key only', () {
      final signed = expectOk(unlocked.signCleartext(invoice, now: _now));
      expect(expectOk(key.publicKey.verifyCleartext(signed)), invoice);
      expect(
        expectErr(repositoryRobotKey(1).publicKey.verifyCleartext(signed)),
        isA<PgpSignatureInvalid>(),
      );
    });

    test('refuses a text the coordinator would not hand back intact', () {
      for (final text in [
        '',
        ' lnbc1',
        'lnbc1 ',
        'lnbc1\n',
        '\tlnbc1',
        '-lnbc1',
        'lnbc1\n-second',
        'lnbc1 \nsecond',
        'lnbc1\r\nsecond',
      ]) {
        expect(
          expectErr(unlocked.signCleartext(text)),
          isA<PgpCleartextUnsuitable>(),
          reason: jsonEncode(text),
        );
      }
    });

    test('never dates a signature before the key', () {
      // A clock two days behind: GnuPG and the official client refuse a signature older than its key.
      final early = _now.subtract(const Duration(days: 2));
      final signed = expectOk(unlocked.signCleartext(invoice, now: early));
      expectOk(
        key.publicKey.verifyCleartext(signed, now: key.publicKey.createdAt),
      );
      expect(
        expectErr(key.publicKey.verifyCleartext(signed, now: early)),
        isA<PgpSignatureInvalid>(),
      );
    });

    test('refuses a text beyond the size bound', () {
      expectOk(unlocked.signCleartext('x' * 10000));
      expect(
        expectErr(unlocked.signCleartext('x' * 10001)),
        isA<PgpInputTooLarge>(),
      );
    });

    test('signs a text of several lines and non-ASCII characters', () {
      const text = 'première ligne\nsecond line ⚡';
      final signed = expectOk(unlocked.signCleartext(text, now: _now));
      expect(expectOk(key.publicKey.verifyCleartext(signed)), text);
    });

    // R and S are stored as integers: one signature in 128 has a leading zero byte that the encoding drops, and dart_pg 2.0.0 rejects it.
    test('verifies signatures whose R or S starts with a zero byte', () {
      var shortSignatures = 0;
      for (var i = 0; i < 400; i++) {
        final text = 'lnbcrt$i';
        final signed = expectOk(unlocked.signCleartext(text, now: _now));
        final parts = cleartextDecode(signed);
        if (parts == null) fail('not a cleartext signed message');
        if (parts.signature.length < 119) shortSignatures++;
        expect(expectOk(key.publicKey.verifyCleartext(signed)), text);
      }
      expect(shortSignatures, greaterThan(0));
    });
  });

  group('PgpPublicKey.verifyCleartext', () {
    final robot1 = repositoryRobotKey(1).publicKey;
    final signed = repositoryRobotFile(1, 'signed_message');

    test('accepts the message GnuPG signed with the key of test robot 1', () {
      expect(
        expectOk(robot1.verifyCleartext(signed)),
        'bcrt1qrrvml8tr4lkwlqpg9g394tye6s5950qf9tj9e9',
      );
    });

    test('accepts CRLF line endings', () {
      expect(
        expectOk(robot1.verifyCleartext(signed.replaceAll('\n', '\r\n'))),
        'bcrt1qrrvml8tr4lkwlqpg9g394tye6s5950qf9tj9e9',
      );
    });

    test('rejects a text that was changed', () {
      expect(
        expectErr(
          robot1.verifyCleartext(signed.replaceFirst('bcrt1q', 'bcrt1p')),
        ),
        isA<PgpSignatureInvalid>(),
      );
    });

    test('rejects a signature by another key', () {
      expect(
        expectErr(repositoryRobotKey(2).publicKey.verifyCleartext(signed)),
        isA<PgpSignatureInvalid>(),
      );
    });

    test(
      'returns the signed text, not the blanks a signature does not cover',
      () {
        // Trailing spaces and tabs are outside a cleartext signature: anyone can add them.
        const address = 'bcrt1qrrvml8tr4lkwlqpg9g394tye6s5950qf9tj9e9';
        expect(
          expectOk(
            robot1.verifyCleartext(
              signed.replaceFirst('$address\n', '$address \t \n'),
            ),
          ),
          address,
        );
      },
    );

    test('rejects a message without Hash header', () {
      expect(
        expectErr(
          robot1.verifyCleartext(signed.replaceFirst('Hash: SHA512\n', '')),
        ),
        isA<PgpArmorMalformed>(),
      );
    });

    test('accepts a Hash header that names several algorithms', () {
      expectOk(
        robot1.verifyCleartext(
          signed.replaceFirst('Hash: SHA512', 'Hash: SHA256,SHA512'),
        ),
      );
    });

    test('rejects a signature from the future of the given clock', () {
      // GnuPG made this signature on 2024-06-26.
      expectOk(robot1.verifyCleartext(signed, now: DateTime.utc(2024, 6, 27)));
      expect(
        expectErr(
          robot1.verifyCleartext(signed, now: DateTime.utc(2024, 6, 26)),
        ),
        isA<PgpSignatureInvalid>(),
      );
    });

    test('does not read a message beyond the size bound', () {
      expect(
        expectErr(robot1.verifyCleartext('$signed${' ' * 20000}')),
        isA<PgpInputTooLarge>(),
      );
    });

    test('rejects a Hash header that contradicts the signature', () {
      expect(
        expectErr(
          robot1.verifyCleartext(signed.replaceFirst('SHA512', 'SHA256')),
        ),
        isA<PgpSignatureInvalid>(),
      );
    });

    test('rejects a signature block that is not a signature', () {
      final notASignature = cleartextEncode(
        text: 'text',
        hashName: 'SHA512',
        signature: [1, 2, 3],
      );
      expect(
        expectErr(robot1.verifyCleartext(notASignature)),
        isA<PgpSignatureInvalid>(),
      );
    });

    test('rejects text that is not a cleartext signed message', () {
      for (final text in [
        '',
        'bcrt1qrrvml8tr4lkwlqpg9g394tye6s5950qf9tj9e9',
        repositoryRobotFile(1, 'pub_key'),
        signed.substring(0, signed.indexOf('-----BEGIN PGP SIGNATURE')),
        signed.replaceFirst('=Nlv0', '=Nlv1'),
        signed.replaceFirst('Hash: SHA512', 'Charset: UTF-8'),
      ]) {
        expect(
          expectErr(robot1.verifyCleartext(text)),
          isA<PgpArmorMalformed>(),
          reason: text.split('\n').first,
        );
      }
    });
  });

  group('chat messages', () {
    final aliceIdentity = repositoryRobotIdentity(1);
    final alice = expectOk(repositoryRobotKey(1).unlock(aliceIdentity));
    final bob = expectOk(_generate().unlock(_identity));
    final carol = expectOk(
      repositoryRobotKey(3).unlock(repositoryRobotIdentity(3)),
    );
    const plaintext = 'Hola, envío 50 € por Bizum ⚡\nGracias';
    final message = expectOk(
      alice.encryptChatMessage(plaintext, peer: bob.key.publicKey, now: _now),
    );

    test('are armored like the messages of the official client', () {
      expect(message, startsWith('-----BEGIN PGP MESSAGE-----\n\n'));
      expect(message, endsWith('-----END PGP MESSAGE-----\n'));
      expect(message, isNot(contains('Version')));
      expect(message, isNot(contains('\r')));
      // `chat/consumers.py:201` and `EncryptedApiChat/index.tsx:155` recognise a message by its first 27 characters.
      expect(message.substring(0, 27), '-----BEGIN PGP MESSAGE-----');
    });

    test('hold one session key per trader, sender first, then the data', () {
      final packets = packetsOf(ArmorBlock.message, message);
      expect(packets.map((packet) => packet.tag), [1, 1, 18]);
      for (final (index, key) in [alice.key, bob.key].indexed) {
        final body = packets[index].body;
        expect(body[0], 3, reason: 'version 3');
        expect(body[9], 18, reason: 'ECDH');
        expect(body, hasLength(94));
        // The key ID of the encryption subkey is not exposed: it only has to differ between the two recipients.
        expect(key.publicKey.fingerprint, isNotEmpty);
      }
      expect(
        packets[0].body.sublist(1, 9),
        isNot(packets[1].body.sublist(1, 9)),
      );
      expect(packets[2].body[0], 1, reason: 'integrity-protected, version 1');
    });

    test('are read by the sender and by the peer, and by nobody else', () {
      for (final reader in [alice, bob]) {
        final decrypted = expectOk(
          reader.decryptChatMessage(message, sender: alice.key.publicKey),
        );
        expect(decrypted.text, plaintext);
        expect(decrypted.validSignature, isTrue);
      }
      expect(
        expectErr(
          carol.decryptChatMessage(message, sender: alice.key.publicKey),
        ),
        isA<PgpMessageUndecryptable>(),
      );
    });

    test('are signed with a date 24 hours in the past', () {
      final decrypted = expectOk(
        bob.decryptChatMessage(message, sender: alice.key.publicKey),
      );
      expect(decrypted.signedAt, DateTime.utc(2026, 11, 8, 12));
    });

    test('differ on every encryption', () {
      expect(
        expectOk(
          alice.encryptChatMessage(
            plaintext,
            peer: bob.key.publicKey,
            now: _now,
          ),
        ),
        isNot(message),
      );
    });

    test(
      'are a deterministic function of text, keys, clock and randomness',
      () {
        String encrypt(String label) => expectOk(
          alice.encryptChatMessageWith(
            plaintext,
            peer: bob.key.publicKey,
            now: _now,
            random: DeterministicRandom(label),
          ),
        );
        expect(encrypt('a'), encrypt('a'));
        expect(encrypt('a'), isNot(encrypt('b')));
      },
    );

    test('are never signed with a date before the key of the sender', () {
      // A clock set back one hour after bob generated his key: 24 hours back would be one hour before the date of the key.
      final message = expectOk(
        bob.encryptChatMessage(
          plaintext,
          peer: alice.key.publicKey,
          now: _now.subtract(const Duration(hours: 1)),
        ),
      );
      final decrypted = expectOk(
        alice.decryptChatMessage(message, sender: bob.key.publicKey),
      );
      expect(decrypted.validSignature, isTrue);
      expect(decrypted.signedAt, bob.key.publicKey.createdAt);
    });

    test('are flagged when read with a clock behind their signature', () {
      final decrypted = expectOk(
        bob.decryptChatMessage(
          message,
          sender: alice.key.publicKey,
          now: _now.subtract(const Duration(days: 1, seconds: 1)),
        ),
      );
      expect(decrypted.text, plaintext);
      expect(decrypted.validSignature, isFalse);
    });

    test('are refused beyond the size bound', () {
      expectOk(alice.encryptChatMessage('é' * 15000, peer: bob.key.publicKey));
      expect(
        expectErr(
          alice.encryptChatMessage('é' * 15001, peer: bob.key.publicKey),
        ),
        isA<PgpInputTooLarge>(),
      );
    });

    test('show the text but flag it when the sender is not the signer', () {
      final decrypted = expectOk(
        bob.decryptChatMessage(message, sender: bob.key.publicKey),
      );
      expect(decrypted.text, plaintext);
      expect(decrypted.validSignature, isFalse);
      expect(decrypted.signedAt, isNull);
    });

    test('travel on one line with backslashes', () {
      // `EncryptedChat/index.tsx:263` writes `PGP_message` so, `EncryptedApiChat/index.tsx:166` reads it back.
      final wire = pgpArmorToWire(message);
      expect(wire, isNot(contains('\n')));
      expect(pgpArmorFromWire(wire), message);
      expect(pgpArmorFromWire(message), message);
      expect(
        expectOk(
          bob.decryptChatMessage(wire, sender: alice.key.publicKey),
        ).text,
        plaintext,
      );
    });

    test('keep line breaks and accept an empty or a long text', () {
      for (final text in ['', 'a\r\nb', 'x' * 5000, '\n\n']) {
        final decrypted = expectOk(
          bob.decryptChatMessage(
            expectOk(
              bob.encryptChatMessage(
                text,
                peer: alice.key.publicKey,
                now: _now,
              ),
            ),
            sender: bob.key.publicKey,
          ),
        );
        expect(decrypted.text, text.replaceAll('\r\n', '\n'));
        expect(decrypted.validSignature, isTrue);
      }
    });

    test('keep a definite length whatever their size, as OpenPGP.js does', () {
      final long = expectOk(
        alice.encryptChatMessage('x' * 5000, peer: bob.key.publicKey),
      );
      // `decodePackets` refuses partial lengths, which dart_pg writes on its own from 512 bytes.
      expect(
        packetsOf(ArmorBlock.message, long).last.body.length,
        greaterThan(5000),
      );
    });

    test('are refused when they contain the robot token', () {
      // `EncryptedApiChat/index.tsx:210-214`.
      final token = aliceIdentity.token.reveal();
      expect(
        expectErr(
          alice.encryptChatMessage(
            'my token is $token, keep it',
            peer: bob.key.publicKey,
          ),
        ),
        isA<PgpPlaintextContainsToken>(),
      );
      expectOk(
        bob.encryptChatMessage(
          'the token of my peer is $token',
          peer: alice.key.publicKey,
        ),
      );
    });

    test('cannot be opened once tampered with', () {
      final packets = packetsOf(ArmorBlock.message, message);
      final data = packets.last.body;
      final tampered = armorEncode(ArmorBlock.message, [
        ...encodePacket(packets[0].tag, packets[0].body),
        ...encodePacket(packets[1].tag, packets[1].body),
        ...encodePacket(packets[2].tag, [
          ...data.sublist(0, data.length - 30),
          data[data.length - 30] ^ 1,
          ...data.sublist(data.length - 29),
        ]),
      ]);
      expect(
        expectErr(
          bob.decryptChatMessage(tampered, sender: alice.key.publicKey),
        ),
        isA<PgpMessageUndecryptable>(),
      );
      final wrongSessionKey = armorEncode(ArmorBlock.message, [
        ...encodePacket(packets[0].tag, packets[0].body),
        ...encodePacket(packets[1].tag, [
          ...packets[1].body.sublist(0, 93),
          packets[1].body[93] ^ 1,
        ]),
        ...encodePacket(packets[2].tag, data),
      ]);
      expect(
        expectErr(
          bob.decryptChatMessage(wrongSessionKey, sender: alice.key.publicKey),
        ),
        isA<PgpMessageUndecryptable>(),
      );
    });

    test('are rejected when they are not an armored message', () {
      for (final text in [
        '',
        'Example message string',
        repositoryRobotFile(1, 'pub_key'),
        message.replaceFirst('\n\n', '\n'),
      ]) {
        expect(
          expectErr(bob.decryptChatMessage(text, sender: alice.key.publicKey)),
          isA<PgpArmorMalformed>(),
        );
      }
      expect(
        expectErr(
          bob.decryptChatMessage(
            armorEncode(ArmorBlock.message, [1, 2, 3]),
            sender: alice.key.publicKey,
          ),
        ),
        isA<PgpMessageUndecryptable>(),
      );
    });
  });

  group('damaged input', () {
    // Every byte of a key, a signed text and a chat message, changed in turn: the outcome may be anything but an exception.
    final key = _generate();
    final unlocked = expectOk(key.unlock(_identity));
    String flipped(String armored, int index) => String.fromCharCodes([
      ...armored.codeUnits.take(index),
      armored.codeUnitAt(index) ^ 0x01,
      ...armored.codeUnits.skip(index + 1),
    ]);

    test('never throws from a public key', () {
      final armored = key.publicKey.armored;
      for (var i = 0; i < armored.length; i++) {
        PgpPublicKey.parse(flipped(armored, i));
      }
    });

    test('never throws from a private key, parsed', () {
      final armored = key.encryptedPrivateKeyArmored;
      for (var i = 0; i < armored.length; i++) {
        RobotPgpKey.parse(
          publicKey: key.publicKey.armored,
          encryptedPrivateKey: flipped(armored, i),
        );
      }
    });

    test('never throws from a signed text', () {
      final signed = expectOk(unlocked.signCleartext('lnbc1', now: _now));
      for (var i = 0; i < signed.length; i++) {
        key.publicKey.verifyCleartext(flipped(signed, i));
      }
    });

    test('never throws from a chat message', () {
      final message = expectOk(
        unlocked.encryptChatMessage('hello', peer: key.publicKey, now: _now),
      );
      for (var i = 0; i < message.length; i++) {
        unlocked.decryptChatMessage(flipped(message, i), sender: key.publicKey);
      }
    });
  });

  group('secrecy', () {
    final identity = repositoryRobotIdentity(1);
    final key = repositoryRobotKey(1);
    final unlocked = expectOk(key.unlock(identity));
    const plaintext = 'a very private chat message';
    final decrypted = expectOk(
      unlocked.decryptChatMessage(
        expectOk(unlocked.encryptChatMessage(plaintext, peer: key.publicKey)),
        sender: key.publicKey,
      ),
    );

    test('nothing a PGP object prints reveals a secret', () {
      final printed =
          '$key ${key.publicKey} $unlocked $decrypted ${[unlocked]}';
      expect(printed, isNot(contains(identity.token.reveal())));
      expect(printed, isNot(contains(plaintext)));
      expect(printed, isNot(contains('PRIVATE KEY')));
      expect(printed, contains(key.publicKey.fingerprint));
      expect(
        '$decrypted',
        'DecryptedChatMessage(<redacted>, validSignature: true)',
      );
    });

    test('no PGP failure carries a value', () {
      const List<PgpFailure> failures = [
        PgpInputTooLarge(),
        PgpClockOutOfRange(),
        PgpArmorMalformed(),
        PgpKeyUnsupported(),
        PgpKeyOutOfDate(),
        PgpKeyPairMismatch(),
        PgpWrongPassphrase(),
        PgpCleartextUnsuitable(),
        PgpSignatureInvalid(),
        PgpPlaintextContainsToken(),
        PgpMessageUndecryptable(),
      ];
      for (final failure in failures) {
        expect('$failure', isNot(contains(identity.token.reveal())));
        expect(failure, isA<RobosatsFailure>());
      }
    });
  });
}
