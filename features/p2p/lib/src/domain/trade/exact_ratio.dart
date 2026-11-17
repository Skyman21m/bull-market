import 'dart:math' as math;

import 'package:meta/meta.dart';

/// An exact rational number, a numerator over a positive denominator, both [BigInt]: the arithmetic of a maker's money rules (`MakerTerms`, design note `docs/design/phase-3-making-an-order.md` § 3.2, § 3.3), so that the only rounding of a rule is the one the rule states.
///
/// A double enters as the decimal its shortest text writes ([ExactRatio.ofDouble]): the text `double.toString` gives, the same as Python's `repr`, which is the number the coordinator's JSON wrote and the one its decimal fields keep (`DecimalField`, `api/models/order.py:77-146`, `api/models/currency.py:17-23`). So `0.1` is one tenth here, not the binary double nearest to it, and a rule such as « 2 % above 1,500 sats, plus 1 sat » gives exactly 1,531, where the same sum in doubles may fall on either side of it.
/// Nothing here rounds: [floor] is the one rounding, toward minus infinity, and [toDouble] is for display only.
@immutable
final class ExactRatio implements Comparable<ExactRatio> {
  /// The numerator, with no factor in common with [denominator].
  final BigInt numerator;

  /// Above zero.
  final BigInt denominator;

  const ExactRatio._(this.numerator, this.denominator);

  /// [numerator] over [denominator], reduced; [denominator] must not be zero.
  factory ExactRatio._reduced(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) {
      throw ArgumentError.value(denominator, 'denominator', 'must not be 0');
    }
    final sign = denominator.isNegative ? -BigInt.one : BigInt.one;
    final divisor = numerator.gcd(denominator);
    return ExactRatio._(
      sign * numerator ~/ divisor,
      sign * denominator ~/ divisor,
    );
  }

  /// The integer [value].
  factory ExactRatio.integer(int value) =>
      ExactRatio._(BigInt.from(value), BigInt.one);

  /// The integer [value].
  factory ExactRatio.bigInt(BigInt value) => ExactRatio._(value, BigInt.one);

  static final _text = RegExp(r'^(-?)(\d+)(?:\.(\d+))?(?:e([+-]?\d+))?$');

  /// The decimal that the shortest text of [value] writes (`double.toString`), or `null` when [value] is not finite.
  static ExactRatio? ofDouble(double value) {
    if (!value.isFinite) return null;
    final match = _text.firstMatch(value.toString());
    // `double.toString` of a finite double always has this form: a bug otherwise, never a value to guess.
    if (match == null) throw StateError('unexpected double text');
    final fraction = match.group(3) ?? '';
    final exponent = int.parse(match.group(4) ?? '0') - fraction.length;
    var digits = BigInt.parse('${match.group(2)}$fraction');
    if (match.group(1) == '-') digits = -digits;
    final power = BigInt.from(10).pow(exponent.abs());
    return exponent >= 0
        ? ExactRatio._(digits * power, BigInt.one)
        : ExactRatio._reduced(digits, power);
  }

  ExactRatio operator +(ExactRatio other) => ExactRatio._reduced(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );

  ExactRatio operator -(ExactRatio other) => ExactRatio._reduced(
    numerator * other.denominator - other.numerator * denominator,
    denominator * other.denominator,
  );

  ExactRatio operator *(ExactRatio other) => ExactRatio._reduced(
    numerator * other.numerator,
    denominator * other.denominator,
  );

  /// This over [other], which must not be zero (an [ArgumentError] otherwise: a bug of the caller).
  ExactRatio operator /(ExactRatio other) => ExactRatio._reduced(
    numerator * other.denominator,
    denominator * other.numerator,
  );

  ExactRatio abs() => numerator.isNegative ? ExactRatio._(-numerator, denominator) : this;

  /// The largest integer at most this: the one rounding of a rule, down.
  BigInt floor() {
    final quotient = numerator ~/ denominator;
    // `~/` truncates toward zero: a negative number with a remainder is one below.
    return numerator.isNegative && quotient * denominator != numerator
        ? quotient - BigInt.one
        : quotient;
  }

  /// The nearest double, for display only: never compared, never paid on.
  double toDouble() {
    // Both shortened by the same number of bits when either is too long for a double, so that neither becomes infinite.
    final bits = math.max(numerator.abs().bitLength, denominator.bitLength);
    final shift = bits - 1000;
    if (shift <= 0) return numerator.toDouble() / denominator.toDouble();
    return (numerator >> shift).toDouble() / (denominator >> shift).toDouble();
  }

  @override
  int compareTo(ExactRatio other) => (numerator * other.denominator).compareTo(
    other.numerator * denominator,
  );

  bool operator <(ExactRatio other) => compareTo(other) < 0;
  bool operator <=(ExactRatio other) => compareTo(other) <= 0;
  bool operator >(ExactRatio other) => compareTo(other) > 0;
  bool operator >=(ExactRatio other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is ExactRatio &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => 'ExactRatio($numerator/$denominator)';
}
