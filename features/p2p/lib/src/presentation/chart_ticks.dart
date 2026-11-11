import 'dart:math' as math;

/// The round values a chart labels along a numeric axis: multiples of 1, 2 or 5 times a power of ten.
abstract final class ChartTicks {
  /// The most values ever returned, whatever the bounds.
  static const maxTicks = 50;

  /// About [count] round values from [min] to [max], each bound included when it is round.
  ///
  /// It is empty when the bounds are not finite numbers, when [max] is not above [min], or when [count] is below 1.
  static List<double> between(double min, double max, int count) {
    if (!min.isFinite || !max.isFinite || !(max > min) || count < 1) {
      return const [];
    }
    final span = max - min;
    if (!span.isFinite) return const [];
    final raw = span / count;
    // A span so small that a step underflows to zero has no power of ten.
    if (!(raw > 0)) return const [];
    final power = (math.log(raw) / math.ln10).floor();
    final magnitude = math.pow(10, power).toDouble();
    if (!magnitude.isFinite || magnitude == 0) return const [];
    final error = raw / magnitude;
    final factor = error < 1.5
        ? 1
        : error < 3
        ? 2
        : error < 7
        ? 5
        : 10;
    // Below one, a step is written as a fraction with a power of ten below it, so that 0.1 times 3 gives 0.3 and not 0.30000000000000004.
    final denominator = power < 0 ? math.pow(10, -power).toDouble() : 1.0;
    final unit = power < 0 ? factor.toDouble() : factor * magnitude;
    if (!denominator.isFinite || !unit.isFinite) return const [];
    final step = unit / denominator;
    double at(double k) => k * unit / denominator;
    // The nearest multiples, not the ones inside, since 0.3 / 0.1 is just below 3: a value outside the bounds is left out below.
    final first = (min / step).roundToDouble();
    final last = (max / step).roundToDouble();
    if (!first.isFinite || !last.isFinite) return const [];
    final ticks = <double>[];
    // At most [maxTicks] turns, even where the values are too large for one more step to change them.
    for (var i = 0; i < maxTicks && first + i <= last; i++) {
      final value = at(first + i);
      if (value < min || value > max) continue;
      // Never a negative zero, which a locale would write « -0 ».
      ticks.add(value == 0 ? 0 : value);
    }
    return ticks;
  }
}
