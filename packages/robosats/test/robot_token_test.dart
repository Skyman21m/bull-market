import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/vectors.dart';

/// Tolerance for entropies whose base-2 logarithm is not an exact power of two: see `TokenEntropy`.
const _ulps = 1e-12;

RobotToken _token(String value) => switch (RobotToken.parse(value)) {
  Ok(:final value) => value,
  Err(:final failure) => fail('expected a valid token, got $failure'),
};

void main() {
  group('RobotToken.measureEntropy', () {
    for (final MapEntry(key: label, value: robot) in allRobots.entries) {
      test('matches the RoboSats client for $label', () {
        final expected = robot['entropy'] as Map<String, dynamic>;
        final entropy = RobotToken.measureEntropy(robot['token'] as String);
        expect(
          entropy.bitsEntropy,
          closeTo(expected['bitsEntropy'] as num, _ulps),
        );
        expect(
          entropy.shannonEntropy,
          closeTo(expected['shannonEntropy'] as num, _ulps),
        );
        expect(entropy.hasEnoughEntropy, expected['hasEnoughEntropy']);
      });
    }

    test('is exact when the alphabet size is a power of two', () {
      final entropy = RobotToken.measureEntropy(
        repositoryRobots.first['token'] as String,
      );
      expect(entropy.bitsEntropy, 180.0);
    });

    // Expected values below come from running `validateTokenEntropy` of `frontend/src/utils/token.ts:19-45` under Node v24.15.0.
    test('requires strictly more than 128 bits', () {
      final entropy = RobotToken.measureEntropy('abcdefghijklmnop' * 2);
      expect(entropy.bitsEntropy, 128.0);
      expect(entropy.shannonEntropy, 4.0);
      expect(entropy.hasEnoughEntropy, isFalse);
    });

    test('requires a Shannon entropy strictly above 4', () {
      final uniform = RobotToken.measureEntropy('abcdefghijklmnop' * 3);
      expect(uniform.bitsEntropy, 192.0);
      expect(uniform.shannonEntropy, 4.0);
      expect(uniform.hasEnoughEntropy, isFalse);

      final dyadic = RobotToken.measureEntropy(
        'aaaabbbbccccddddefghijklmnopqrst',
      );
      expect(dyadic.bitsEntropy, closeTo(138.3016990363956, _ulps));
      expect(dyadic.shannonEntropy, 4.0);
      expect(dyadic.hasEnoughEntropy, isFalse);
    });

    test('accepts seventeen evenly spread characters', () {
      final entropy = RobotToken.measureEntropy('abcdefghijklmnopq' * 2);
      expect(entropy.bitsEntropy, closeTo(138.97373660251154, _ulps));
      expect(entropy.shannonEntropy, closeTo(4.08746284125034, _ulps));
      expect(entropy.hasEnoughEntropy, isTrue);
    });

    test('rejects many bits with a poor distribution', () {
      final entropy = RobotToken.measureEntropy('abcdefghijkl' * 3);
      expect(entropy.bitsEntropy, closeTo(129.0586500259616, _ulps));
      expect(entropy.shannonEntropy, closeTo(3.584962500721156, _ulps));
      expect(entropy.hasEnoughEntropy, isFalse);
    });

    test('measures degenerate inputs like the client', () {
      for (final degenerate in ['', 'a' * 36]) {
        final entropy = RobotToken.measureEntropy(degenerate);
        expect(entropy.bitsEntropy, 0.0);
        expect(entropy.shannonEntropy, 0.0);
        expect(entropy.hasEnoughEntropy, isFalse);
      }
    });

    test('lets the bit count overflow to infinity like the client', () {
      const base62 =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
      final entropy = RobotToken.measureEntropy(base62 * 200);
      expect(entropy.bitsEntropy, double.infinity);
      expect(entropy.shannonEntropy, closeTo(5.954196310386873, _ulps));
      expect(entropy.hasEnoughEntropy, isTrue);
    });

    test('counts UTF-16 code units like the client', () {
      final entropy = RobotToken.measureEntropy(
        'é€😀abcdefghijklmnopqrstuvwxyz0123456',
      );
      expect(entropy.bitsEntropy, closeTo(192.74977452827113, _ulps));
      expect(entropy.shannonEntropy, closeTo(5.209453365628954, _ulps));
    });
  });

  group('RobotToken.parse', () {
    for (final MapEntry(key: label, value: robot) in allRobots.entries) {
      test('accepts the token of $label', () {
        final token = _token(robot['token'] as String);
        expect(token.reveal(), robot['token']);
        expect(
          hex.encode(utf8.encode(token.reveal())),
          robot['token_utf8_hex'],
        );
        expect(token.entropy.hasEnoughEntropy, isTrue);
      });
    }

    test('rejects a low-entropy token and reports its entropy', () {
      final result = RobotToken.parse('abcdefghijkl' * 3);
      expect(result, isA<Err<RobotToken, TokenEntropyTooLow>>());
      final failure = (result as Err<RobotToken, TokenEntropyTooLow>).failure;
      expect(failure.entropy.shannonEntropy, lessThan(4));
      expect(failure.entropy.hasEnoughEntropy, isFalse);
    });

    test('rejects short, empty and repetitive tokens', () {
      for (final weak in ['', 'short', 'a' * 64, 'abcdefghijklmnop' * 3]) {
        expect(
          RobotToken.parse(weak),
          isA<Err<RobotToken, TokenEntropyTooLow>>(),
          reason: weak,
        );
      }
    });

    test('has value equality', () {
      const value = 'C2etfi7nPeUD7rCcwAOy4XoLvEAxbTRGSK6H';
      expect(_token(value), _token(value));
      expect({_token(value), _token(value)}, hasLength(1));
      expect(
        _token(value),
        isNot(_token('oKrH73YD4ISQ0wzLNyPBeGp2OK7JTKghDfJe')),
      );
    });

    test('never prints the token', () {
      const value = 'C2etfi7nPeUD7rCcwAOy4XoLvEAxbTRGSK6H';
      final token = _token(value);
      expect('$token', isNot(contains(value)));
      expect('${[token]}', isNot(contains(value)));
      expect('${RobotToken.parse(value)}', isNot(contains(value)));
    });

    test('never carries the rejected token in the failure', () {
      const weak = 'abcdefghijklabcdefghijklabcdefghijkl';
      final failure = (RobotToken.parse(weak) as Err).failure;
      expect('$failure', isNot(contains('abcdefghijkl')));
      expect(failure.logMessage, isNull);
    });
  });
}
