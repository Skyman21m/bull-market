import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:robosats/src/nickname.dart';
import 'package:robosats/src/nickname_adjectives.dart';
import 'package:robosats/src/nickname_nouns.dart';
import 'package:test/test.dart';

import 'support/vectors.dart';

/// Hashes placed on floating-point boundaries, with the values CPython computes for them.
///
/// The `_avertissement` and `_comment_chaque_valeur_est_produite` fields of the file state how each value was produced.
final List<Map<String, dynamic>> _floatBoundaries =
    ((jsonDecode(
                  File(
                    'test/fixtures/pseudos-frontieres-flottantes.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>)['vecteurs']
            as List<dynamic>)
        .cast<Map<String, dynamic>>();

/// Parses the output of Python's `float.hex()`, exactly.
double _parsePythonHexFloat(String text) {
  final match = RegExp(r'^0x([01])\.([0-9a-f]+)p([+-]\d+)$').firstMatch(text);
  if (match == null) fail('not a Python hex float: $text');
  final [leading, fraction, exponent] = match.groups([1, 2, 3]);
  if (leading == null || fraction == null || exponent == null) {
    fail('not a Python hex float: $text');
  }
  if (leading == '0') return 0;
  var value = ((1 << 52) + int.parse(fraction.padRight(13, '0'), radix: 16))
      .toDouble();
  var shift = int.parse(exponent) - 52;
  for (; shift < 0; shift++) {
    value /= 2;
  }
  for (; shift > 0; shift--) {
    value *= 2;
  }
  return value;
}

void main() {
  group('nickname dictionaries', () {
    final reference = vectors['_reference'] as Map<String, dynamic>;
    final sizes = reference['dictionnaires_pseudos_tailles'] as Map;

    test('have the sizes of the RoboSats dictionaries', () {
      expect(nicknameAdjectives, hasLength(sizes['adjectives'] as int));
      expect(nicknameNouns, hasLength(sizes['nouns'] as int));
      expect(nicknamePoolSize, sizes['pool_size']);
      expect(nicknamePoolSize, 999 * 12591 * 4832);
    });

    test('keep the order of the RoboSats files', () {
      expect(nicknameAdjectives.first, 'Toneless');
      expect(nicknameAdjectives.last, 'Simplistic');
      expect(nicknameNouns.first, 'Aardvark');
      expect(nicknameNouns[3], 'Abaringe');
    });

    test('are a verbatim port of the RoboSats files', () {
      // Rebuilds the text of `api/nick_generator/dicts/en/{adjectives,nouns}.py` from the Dart constants and compares its SHA-256 with the one recorded when the vectors were generated.
      String pythonSource(String name, List<String> words) =>
          '$name = [\n${words.map((word) => '    "$word",\n').join()}]\n';
      final hashes = reference['dictionnaires_pseudos_sha256'] as Map;
      expect(
        '${sha256.convert(utf8.encode(pythonSource('adjectives', nicknameAdjectives)))}',
        hashes['api/nick_generator/dicts/en/adjectives.py'],
      );
      expect(
        '${sha256.convert(utf8.encode(pythonSource('nouns', nicknameNouns)))}',
        hashes['api/nick_generator/dicts/en/nouns.py'],
      );
    });

    test('keep the duplicated nouns of the RoboSats file', () {
      expect(nicknameNouns.toSet(), hasLength(lessThan(nicknameNouns.length)));
    });
  });

  group('deriveNickname', () {
    test('matches the 200 nicknames of the RoboSats coordinator code', () {
      expect(referenceNicknames, hasLength(200));
      var rehashed = 0;
      for (final reference in referenceNicknames) {
        final hashId = reference['hash_id'] as String;
        final derivation = deriveNickname(hashId);
        expect(derivation, isNotNull, reason: hashId);
        if (derivation == null) continue;
        expect(derivation.nickname, reference['nickname'], reason: hashId);
        expect(derivation.nickId, reference['nick_id'], reason: hashId);
        expect(
          derivation.rehashIterations,
          reference['rehash_iterations'],
          reason: hashId,
        );
        expect(derivation.nickname.length, lessThanOrEqualTo(18));
        if (derivation.rehashIterations > 0) rehashed++;
      }
      expect(rehashed, 103);
    });

    for (final MapEntry(key: label, value: robot) in allRobots.entries) {
      test('matches every intermediate value for $label', () {
        final detail = robot['nickname_detail'] as Map<String, dynamic>;
        final derivation = deriveNickname(robot['hash_id'] as String);
        expect(derivation, isNotNull);
        if (derivation == null) return;
        expect(derivation.nickname, robot['nickname']);
        expect(derivation.nickname, robot['nickname_reference_python']);
        expect(derivation.nickId, detail['nick_id']);
        expect(derivation.adjectiveIndex, detail['adjective_index']);
        expect(derivation.nounIndex, detail['noun_index']);
        expect(derivation.number, detail['number']);
        expect(derivation.rehashIterations, detail['rehash_iterations']);
        expect(derivation.finalHash, detail['final_hash']);
      });
    }

    test('matches the nickname files of the RoboSats repository', () {
      for (final robot in repositoryRobots) {
        final expected = robot['expected_from_robosats_repo'] as Map;
        expect(
          deriveNickname(robot['hash_id'] as String)?.nickname,
          expected['nickname'],
        );
      }
    });

    test('re-hashes until the nickname fits in 18 characters', () {
      final detail =
          nicknameRehashRobot['nickname_detail'] as Map<String, dynamic>;
      final derivation = deriveNickname(
        nicknameRehashRobot['hash_id'] as String,
      );
      expect(detail['rehash_iterations'], greaterThan(0));
      expect(derivation?.rehashIterations, detail['rehash_iterations']);
      expect(derivation?.finalHash, isNot(nicknameRehashRobot['hash_id']));
    });

    test('starts at the first words for the zero hash', () {
      // Read from the algorithm, not from a run of the RoboSats code: index 0 of each dictionary and the number 0.
      final derivation = deriveNickname('0' * 64);
      expect(derivation?.nickname, 'TonelessAardvark0');
      expect(derivation?.nickId, 0);
      expect(derivation?.rehashIterations, 0);
    });

    test('reaches the last adjective of the dictionary', () {
      // Expected values produced by running the RoboSats coordinator code on this hash.
      final derivation = deriveNickname('ffffffc0${'0' * 56}');
      expect(derivation?.nickname, 'SimplisticZonkey93');
      expect(derivation?.nickname, startsWith(nicknameAdjectives.last));
      expect(derivation?.nickId, 60778871382);
      expect(derivation?.rehashIterations, 0);
    });

    test('has no nickname when the quotient rounds up to one', () {
      // The RoboSats code raises IndexError there: the adjective index is past the dictionary.
      expect(deriveNickname('f' * 64), isNull);
      expect(deriveNickname('${'f' * 51}c${'0' * 12}'), isNull);
    });
  });

  group('double-precision arithmetic', () {
    test('rounds the 256-bit hash to the nearest double, ties to even', () {
      for (final boundary in _floatBoundaries) {
        final hashId = boundary['hash_id'] as String;
        expect(
          hashUnitFraction(BigInt.parse(hashId, radix: 16)),
          _parsePythonHexFloat(boundary['unit_fraction_hex'] as String),
          reason: '${boundary['kind']} $hashId',
        );
      }
    });

    test('scales to the pool like CPython on boundary hashes', () {
      for (final boundary in _floatBoundaries) {
        final hashId = boundary['hash_id'] as String;
        expect(
          nickIdFromHash(hashId),
          boundary['nick_id_python_float'],
          reason: '${boundary['kind']} $hashId',
        );
      }
    });

    test('is exercised by hashes that defeat simpler arithmetic', () {
      int differing(String alternative) => _floatBoundaries
          .where((b) => b['nick_id_python_float'] != b[alternative])
          .length;
      expect(differing('nick_id_exact_integer'), greaterThanOrEqualTo(8));
      expect(differing('nick_id_truncated_mantissa'), greaterThanOrEqualTo(8));
    });

    test('agrees with the conversion of the Dart runtime', () {
      // Not a reference, only a tripwire: the explicit rounding and `BigInt.toDouble` should never disagree.
      for (final boundary in _floatBoundaries) {
        final hash = BigInt.parse(boundary['hash_id'] as String, radix: 16);
        var expected = hash.toDouble();
        for (var i = 0; i < 256; i++) {
          expected /= 2;
        }
        expect(hashUnitFraction(hash), expected);
      }
    });
  });
}
