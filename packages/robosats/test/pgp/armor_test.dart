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

  group('what follows the checksum or the last line', () {
    final armored = armorEncode(ArmorBlock.message, utf8.encode('hello'));

    test('is refused even when the checksum covers it', () {
      // The checksum line of `hello!!!!`, placed between two lines of data.
      final whole = armorEncode(ArmorBlock.message, utf8.encode('hello!!!!'));
      final checksum = whole.split('\n')[3];
      expect(armorDecode(ArmorBlock.message, whole), utf8.encode('hello!!!!'));
      expect(
        armorDecode(
          ArmorBlock.message,
          '-----BEGIN PGP MESSAGE-----\n\naGVsbG8h\n$checksum\nISEh\n-----END PGP MESSAGE-----\n',
        ),
        isNull,
      );
    });

    test('is refused after the END line, as text or as another block', () {
      for (final tail in ['pay ATTACKER', '\npay ATTACKER\n', armored]) {
        expect(armorDecode(ArmorBlock.message, '$armored$tail'), isNull);
      }
      final signed = cleartextEncode(
        text: 'text',
        hashName: 'SHA512',
        signature: [1, 2, 3],
      );
      expect(cleartextDecode(signed), isNotNull);
      for (final tail in ['pay ATTACKER', '\npay ATTACKER\n', signed]) {
        expect(cleartextDecode('$signed$tail'), isNull);
      }
      expect(cleartextDecode('pay ATTACKER\n$signed'), isNull);
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

    test('refuses any header but Hash, even next to one', () {
      final signed = cleartextEncode(
        text: 'text',
        hashName: 'SHA512',
        signature: [1],
      );
      for (final headers in [
        'Hash: SHA512\nComment: pay ATTACKER',
        'NotDashEscaped: x\nHash: SHA512',
        'Charset: UTF-8',
      ]) {
        expect(
          cleartextDecode(signed.replaceFirst('Hash: SHA512', headers)),
          isNull,
          reason: headers,
        );
      }
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

    test('gives the signed text without the trailing blanks', () {
      expect(canonicalLines('a \t\nb\r\n\nc '), 'a\nb\n\nc');
      expect(canonicalLines(' a\rb'), ' a\nb');
    });

    test('hashes lines without trailing blanks, joined by CR LF', () {
      expect(utf8.decode(canonicalText('a \t\nb\r\n\nc ')), 'a\r\nb\r\n\r\nc');
      expect(utf8.decode(canonicalText(' a')), ' a');
    });
  });
}
