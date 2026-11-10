import 'dart:convert';

import 'package:robosats/src/pgp/armor.dart';
import 'package:test/test.dart';

import '../support/pgp.dart';

void main() {
  group('armorEncode', () {
    for (final number in [1, 2, 3]) {
      test('lays a block out as OpenPGP.js did for test robot $number', () {
        final original = repositoryRobotFile(number, 'enc_priv_key');
        final bytes = armorDecode(ArmorBlock.privateKey, original);
        if (bytes == null) fail('fixture is not armored');
        // The files of the repository lack the final line feed.
        expect(armorEncode(ArmorBlock.privateKey, bytes), '$original\n');
      });
    }

    // The checksum is the one `printf hello | gpg --enarmor` prints.
    test('writes a short block on one line', () {
      expect(
        armorEncode(ArmorBlock.message, utf8.encode('hello')),
        '-----BEGIN PGP MESSAGE-----\n\naGVsbG8=\n=R/WK\n-----END PGP MESSAGE-----\n',
      );
    });
  });

  group('armorDecode', () {
    final armored = armorEncode(ArmorBlock.message, utf8.encode('hello'));

    test('reads what armorEncode wrote', () {
      expect(armorDecode(ArmorBlock.message, armored), utf8.encode('hello'));
    });

    test('skips the headers other implementations write', () {
      final withHeaders = armored.replaceFirst(
        '\n\n',
        '\nVersion: GnuPG v2\nComment: https://example.org\n\n',
      );
      expect(
        armorDecode(ArmorBlock.message, withHeaders),
        utf8.encode('hello'),
      );
    });

    test('accepts CRLF line endings and surrounding blank space', () {
      expect(
        armorDecode(
          ArmorBlock.message,
          '\n ${armored.replaceAll('\n', '\r\n')}\n',
        ),
        utf8.encode('hello'),
      );
    });

    test('rejects what is not one block of the expected kind', () {
      for (final text in [
        '',
        'aGVsbG8=',
        armored.replaceFirst('\n\n', '\n'),
        armored.replaceFirst('=R/WK', '=R/WL'),
        armored.replaceFirst('aGVsbG8=', 'aGVs*G8='),
        armored.replaceFirst('aGVsbG8=\n', ''),
        armored.replaceFirst('=R/WK\n', '=R/WK\naGVsbG8=\n'),
        armored.replaceAll('PGP MESSAGE', 'PGP SIGNATURE'),
        '$armored$armored',
        'before\n$armored',
        '${armored}after',
      ]) {
        expect(armorDecode(ArmorBlock.message, text), isNull, reason: text);
      }
    });
  });

  group('cleartext framework', () {
    test('escapes and restores lines that start with a dash', () {
      const text = 'first\n-second\n--third\n- fourth';
      final signed = cleartextEncode(
        text: text,
        hashName: 'SHA512',
        signature: [1, 2, 3],
      );
      expect(signed, contains('\n- -second\n- --third\n- - fourth\n'));
      final parts = cleartextDecode(signed);
      expect(parts?.text, text);
      expect(parts?.hashes, ['SHA512']);
      expect(parts?.signature, [1, 2, 3]);
    });

    test('reads several hash names and none', () {
      final signed = cleartextEncode(
        text: 'text',
        hashName: 'SHA256, SHA512',
        signature: [1],
      );
      expect(cleartextDecode(signed)?.hashes, ['SHA256', 'SHA512']);
      expect(
        cleartextDecode(
          signed.replaceFirst('Hash: SHA256, SHA512\n', ''),
        )?.hashes,
        isEmpty,
      );
    });

    test('hashes lines without trailing blanks, joined by CR LF', () {
      expect(utf8.decode(canonicalText('a \t\nb\r\n\nc ')), 'a\r\nb\r\n\r\nc');
      expect(utf8.decode(canonicalText(' a')), ' a');
    });
  });
}
