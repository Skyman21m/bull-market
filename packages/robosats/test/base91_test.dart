import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:robosats/src/base91.dart';
import 'package:test/test.dart';

import 'support/vectors.dart';

void main() {
  group('base91Encode', () {
    test('encodes nothing as an empty string', () {
      expect(base91Encode(Uint8List(0)), '');
    });

    test('matches the published basE91 example', () {
      expect(base91Encode(utf8.encode('test')), 'fPNKd');
    });

    for (final MapEntry(key: label, value: robot) in allRobots.entries) {
      test('encodes the token SHA-256 of $label', () {
        final digest = hex.decode(robot['sha256_hex'] as String);
        final encoded = base91Encode(digest);
        expect(encoded, robot['token_sha256_base91']);
        expect(encoded.length, robot['token_sha256_base91_length']);
      });
    }

    test('matches the b91_token files of the RoboSats repository', () {
      for (final robot in repositoryRobots) {
        final expected = robot['expected_from_robosats_repo'] as Map;
        expect(
          base91Encode(hex.decode(robot['sha256_hex'] as String)),
          expected['b91_token'],
        );
      }
    });

    test('can yield 39 characters for 32 bytes', () {
      final digest = hex.decode(base91ShortRobot['sha256_hex'] as String);
      expect(base91Encode(digest), hasLength(39));
    });

    test('only emits characters of the coordinator alphabet', () {
      // Copied from `api/utils.py:668` of RoboSats (commit ff1998c).
      const coordinatorCharset =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#\$%&()*+,./:;<=>?@[]^_`{|}~"';
      expect(base91Alphabet, coordinatorCharset);
      final all = base91Encode(
        Uint8List.fromList(List.generate(4096, (i) => (i * 131 + 7) & 0xff)),
      );
      expect(all.split('').every(coordinatorCharset.contains), isTrue);
    });
  });

  group('base91Decode', () {
    test('decodes what the coordinator decodes', () {
      for (final robot in allRobots.values) {
        final decoded = base91Decode(robot['token_sha256_base91'] as String);
        expect(decoded, isNotNull);
        expect(hex.encode(decoded ?? const []), robot['sha256_hex']);
      }
    });

    test('rejects characters outside the alphabet', () {
      for (final invalid in ['fPN Kd', "fPN'Kd", 'fPN-Kd', r'fPN\Kd', 'é']) {
        expect(base91Decode(invalid), isNull, reason: invalid);
      }
    });

    test('round-trips arbitrary bytes', () {
      final random = Random(91);
      for (var i = 0; i < 2000; i++) {
        final bytes = Uint8List.fromList(
          List.generate(random.nextInt(80), (_) => random.nextInt(256)),
        );
        expect(base91Decode(base91Encode(bytes)), bytes);
      }
    });

    test('round-trips the extreme byte patterns', () {
      for (final fill in [0x00, 0xff]) {
        for (var length = 0; length <= 40; length++) {
          final bytes = Uint8List(length)..fillRange(0, length, fill);
          expect(base91Decode(base91Encode(bytes)), bytes);
        }
      }
    });
  });
}
