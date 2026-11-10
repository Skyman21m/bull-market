/// The base62 alphabet of RoboSats robot tokens: uppercase first, then lowercase, then digits.
///
/// This order differs from the usual `0-9A-Za-z` and is the one of `derivedKeyToToken` (`frontend/src/utils/garageKey.ts:100`, commit ff1998c).
const String base62Alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// The [length] low-order base62 digits of [value], most significant first, left-padded with `A`, the zero digit.
///
/// `derivedKeyToToken` stops after 36 digits and pads with `A`, which is the same as writing `value mod 62^36` on 36 digits.
String base62LowDigits(BigInt value, int length) {
  if (value.isNegative) throw ArgumentError('value must not be negative');
  final base = BigInt.from(base62Alphabet.length);
  final digits = List<String>.filled(length, base62Alphabet[0]);
  var rest = value;
  for (var i = length - 1; i >= 0 && rest > BigInt.zero; i--) {
    digits[i] = base62Alphabet[(rest % base).toInt()];
    rest ~/= base;
  }
  return digits.join();
}
