import 'package:robosats/src/base62.dart';
import 'package:test/test.dart';

void main() {
  group('base62LowDigits', () {
    test('uses the RoboSats digit order', () {
      expect(base62Alphabet, hasLength(62));
      expect(base62LowDigits(BigInt.zero, 1), 'A');
      expect(base62LowDigits(BigInt.from(25), 1), 'Z');
      expect(base62LowDigits(BigInt.from(26), 1), 'a');
      expect(base62LowDigits(BigInt.from(52), 1), '0');
      expect(base62LowDigits(BigInt.from(61), 1), '9');
    });

    test('pads small values on the left with the zero digit', () {
      expect(base62LowDigits(BigInt.zero, 36), 'A' * 36);
      expect(base62LowDigits(BigInt.one, 36), '${'A' * 35}B');
      expect(base62LowDigits(BigInt.from(62), 36), '${'A' * 34}BA');
    });

    test('keeps only the low-order digits of a larger value', () {
      final modulus = BigInt.from(62).pow(36);
      final low = BigInt.parse('123456789012345678901234567890');
      expect(
        base62LowDigits(modulus * BigInt.from(7) + low, 36),
        base62LowDigits(low, 36),
      );
      expect(base62LowDigits(modulus - BigInt.one, 36), '9' * 36);
      expect(base62LowDigits(modulus, 36), 'A' * 36);
    });
  });
}
