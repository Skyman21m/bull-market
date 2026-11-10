import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/robosats_failure.dart';

/// The entropy of a robot token, measured as the RoboSats client does.
///
/// It reproduces `validateTokenEntropy` of `frontend/src/utils/token.ts:19-45` (commit ff1998c), which counts UTF-16 code units.
/// Base-2 logarithms of exact powers of two are exact, as in JavaScript, so the two thresholds behave identically on such inputs; other values may differ from the JavaScript ones in the last few bits.
@immutable
final class TokenEntropy {
  /// `log2(distinct characters ^ length)`, infinite when the power overflows a double, as in the client.
  final double bitsEntropy;

  /// The Shannon entropy of the character distribution, in bits per character.
  final double shannonEntropy;

  const TokenEntropy({required this.bitsEntropy, required this.shannonEntropy});

  /// The rule of the official client: without it, the client never contacts a coordinator.
  bool get hasEnoughEntropy => bitsEntropy > 128 && shannonEntropy > 4;

  @override
  bool operator ==(Object other) =>
      other is TokenEntropy &&
      other.bitsEntropy == bitsEntropy &&
      other.shannonEntropy == shannonEntropy;

  @override
  int get hashCode => Object.hash(bitsEntropy, shannonEntropy);

  @override
  String toString() =>
      'TokenEntropy(bitsEntropy: $bitsEntropy, shannonEntropy: $shannonEntropy)';
}

/// The secret a RoboSats robot is derived from: any string with enough entropy, 36 base62 characters when it comes from a Garage Key.
///
/// The token is also the passphrase of the robot PGP key: never log, display by accident or send it.
@immutable
final class RobotToken {
  final String _value;

  /// The entropy of this token, which always satisfies [TokenEntropy.hasEnoughEntropy].
  final TokenEntropy entropy;

  const RobotToken._(this._value, this.entropy);

  /// Accepts [value] as a robot token when it passes the client-side entropy rule of RoboSats.
  ///
  /// The coordinator never sees the token and enforces nothing: the strength of the token is the client's responsibility.
  static Result<RobotToken, TokenEntropyTooLow> parse(String value) {
    final entropy = measureEntropy(value);
    if (!entropy.hasEnoughEntropy) return Err(TokenEntropyTooLow(entropy));
    return Ok(RobotToken._(value, entropy));
  }

  /// Measures [candidate] without accepting it, for instance to guide a user who types their own token.
  static TokenEntropy measureEntropy(String candidate) {
    final counts = <int, int>{};
    for (final unit in candidate.codeUnits) {
      counts[unit] = (counts[unit] ?? 0) + 1;
    }
    final length = candidate.length;
    var shannonEntropy = 0.0;
    for (final count in counts.values) {
      final probability = count / length;
      shannonEntropy -= probability * _log2(probability);
    }
    final bitsEntropy = _log2(
      math.pow(counts.length.toDouble(), length.toDouble()).toDouble(),
    );
    return TokenEntropy(
      bitsEntropy: bitsEntropy,
      shannonEntropy: shannonEntropy,
    );
  }

  /// The token itself: never log it.
  String reveal() => _value;

  @override
  bool operator ==(Object other) =>
      other is RobotToken && other._value == _value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => 'RobotToken(<redacted>)';
}

/// The base-2 logarithm of a positive [x], exact when [x] is a power of two.
///
/// Dart has no `log2`: the argument is first scaled into [1, 2) by exact halvings or doublings, so that a power of two yields its integer exponent, as `Math.log2` does.
double _log2(double x) {
  if (x.isNaN || x < 0) return double.nan;
  if (x == 0) return double.negativeInfinity;
  if (x.isInfinite) return double.infinity;
  var exponent = 0;
  var mantissa = x;
  while (mantissa >= 2) {
    mantissa /= 2;
    exponent++;
  }
  while (mantissa < 1) {
    mantissa *= 2;
    exponent--;
  }
  return exponent + math.log(mantissa) / math.ln2;
}
