import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:robosats/src/nickname_adjectives.dart';
import 'package:robosats/src/nickname_nouns.dart';

/// The highest number appended to a nickname, and the multiplier of the pool size (`max_num=999`, `robosats/middleware.py:19-21`).
const int _maxNumber = 999;

/// The longest nickname a coordinator assigns (`max_length=18`, `robosats/middleware.py:149`).
const int _maxLength = 18;

/// The number of hashes tried before giving up (`max_iter=10_000`).
const int _maxIterations = 10000;

/// The number of nicknames the generator scales a hash onto: 999 × 12 591 nouns × 4 832 adjectives.
const int nicknamePoolSize = 60778872288;

/// How a nickname was obtained from a hash id, for comparison with the reference values.
final class NicknameDerivation {
  final String nickname;
  final int nickId;
  final int adjectiveIndex;
  final int nounIndex;
  final int number;

  /// How many times the hash had to be re-hashed before the nickname fitted in 18 characters.
  final int rehashIterations;

  /// The hash that produced the nickname: the hash id itself when [rehashIterations] is zero.
  final String finalHash;

  const NicknameDerivation({
    required this.nickname,
    required this.nickId,
    required this.adjectiveIndex,
    required this.nounIndex,
    required this.number,
    required this.rehashIterations,
    required this.finalHash,
  });
}

/// The quotient `hash / 2^256` as the nearest double, ties to even.
///
/// Python computes `int_hash / max_int_hash` with a correctly rounded true division, and the divisor is a power of two, so the result is the 256-bit integer rounded to 53 significant bits.
/// The rounding is spelled out with integers here rather than left to `BigInt.toDouble`, whose rounding the Dart documentation does not specify.
double hashUnitFraction(BigInt hash) {
  if (hash.isNegative || hash.bitLength > 256) {
    throw ArgumentError('hash must be an unsigned 256-bit integer');
  }
  var mantissa = hash;
  var droppedBits = 0;
  if (hash.bitLength > 53) {
    droppedBits = hash.bitLength - 53;
    mantissa = hash >> droppedBits;
    final remainder = hash - (mantissa << droppedBits);
    final half = BigInt.one << (droppedBits - 1);
    final comparison = remainder.compareTo(half);
    if (comparison > 0 || (comparison == 0 && mantissa.isOdd)) {
      mantissa += BigInt.one;
    }
  }
  // The mantissa is at most 2^53, so the conversion is exact, and so is every halving below.
  var fraction = mantissa.toInt().toDouble();
  for (var exponent = droppedBits; exponent < 256; exponent++) {
    fraction /= 2;
  }
  return fraction;
}

/// The position of [sha256Hex] in the nickname pool: `int((int_hash / 2**256) * pool_size)`.
///
/// This is deliberately double-precision arithmetic, as in `api/nick_generator/nick_generator.py:86-88`: exact integer arithmetic gives another result for some hashes.
/// The result equals [nicknamePoolSize], one past the last nickname, when the quotient rounds up to 1.0.
int nickIdFromHash(String sha256Hex) =>
    (hashUnitFraction(BigInt.parse(sha256Hex, radix: 16)) * nicknamePoolSize)
        .truncate();

/// The nickname a RoboSats coordinator assigns to the robot whose hash id is [hashId], 64 lowercase hexadecimal characters.
///
/// It reproduces `NickGenerator(lang="English", use_adv=False, use_adj=True, use_noun=True, max_num=999).short_from_SHA256(hash, max_length=18)` of `api/nick_generator/nick_generator.py` (RoboSats commit ff1998c): adjective, noun and number without separator, re-hashing `sha256(hash + "42")` while the nickname is longer than 18 characters.
/// Returns `null` where the reference code has no nickname either: it raises `IndexError` when the quotient rounds up to 1.0, and returns an empty nickname after 10 000 re-hashes.
NicknameDerivation? deriveNickname(String hashId) {
  final nounCount = nicknameNouns.length;
  var hash = hashId;
  for (var iteration = 0; iteration < _maxIterations; iteration++) {
    final nickId = nickIdFromHash(hash);
    // The divisions below are double-precision divisions truncated toward zero, as `int(a / b)` in Python.
    final adjectiveIndex = (nickId / (_maxNumber * nounCount)).truncate();
    if (adjectiveIndex >= nicknameAdjectives.length) return null;
    final remainder = nickId - adjectiveIndex * _maxNumber * nounCount;
    final nounIndex = (remainder / _maxNumber).truncate();
    final number = remainder - nounIndex * _maxNumber;
    final nickname =
        '${nicknameAdjectives[adjectiveIndex]}${nicknameNouns[nounIndex]}$number';
    if (nickname.length <= _maxLength) {
      return NicknameDerivation(
        nickname: nickname,
        nickId: nickId,
        adjectiveIndex: adjectiveIndex,
        nounIndex: nounIndex,
        number: number,
        rehashIterations: iteration,
        finalHash: hash,
      );
    }
    hash = sha256.convert(ascii.encode('${hash}42')).toString();
  }
  return null;
}
