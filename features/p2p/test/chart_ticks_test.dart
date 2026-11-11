import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/presentation/chart_ticks.dart';

void main() {
  test('round steps of 1, 2 or 5 times a power of ten', () {
    expect(ChartTicks.between(0, 10, 5), [0, 2, 4, 6, 8, 10]);
    expect(ChartTicks.between(-6, 10, 4), [-5, 0, 5, 10]);
    expect(ChartTicks.between(-6, 10, 16), [
      -6,
      -5,
      -4,
      -3,
      -2,
      -1,
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
    ]);
    expect(ChartTicks.between(25000, 75000, 5), [
      30000,
      40000,
      50000,
      60000,
      70000,
    ]);
  });

  test('decimals are written exactly, the bounds included when round', () {
    expect(ChartTicks.between(0, 0.065, 4), [0, 0.02, 0.04, 0.06]);
    expect(ChartTicks.between(0.1, 0.3, 2), [0.1, 0.2, 0.3]);
    expect(ChartTicks.between(0, 0.0003, 3), [0, 0.0001, 0.0002, 0.0003]);
    // Never a negative zero, which a locale writes « -0 ».
    final ticks = ChartTicks.between(-1, 1, 2);
    expect(ticks, [-1, 0, 1]);
    expect(ticks[1].isNegative, isFalse);
  });

  test(
    'nothing for bounds that are not numbers, not increasing, or no count',
    () {
      expect(ChartTicks.between(double.nan, 1, 5), isEmpty);
      expect(ChartTicks.between(0, double.infinity, 5), isEmpty);
      expect(ChartTicks.between(1, 1, 5), isEmpty);
      expect(ChartTicks.between(2, 1, 5), isEmpty);
      expect(ChartTicks.between(0, 1, 0), isEmpty);
      // A span too wide to be a number.
      expect(ChartTicks.between(-1.7e308, 1.7e308, 5), isEmpty);
    },
  );

  test(
    'never more than the bound, even where a step no longer changes a value',
    () {
      expect(
        ChartTicks.between(0, 1e15, 100000).length,
        lessThanOrEqualTo(ChartTicks.maxTicks),
      );
      final far = ChartTicks.between(1e17, 1e17 + 64, 4);
      expect(far.length, lessThanOrEqualTo(ChartTicks.maxTicks));
      for (final value in far) {
        expect(value, inInclusiveRange(1e17, 1e17 + 64));
      }
      // Around the largest finite numbers a step is lost in the rounding: still bounded, and inside.
      final huge = ChartTicks.between(1e300, 1.0000000000000002e300, 3);
      expect(huge.length, lessThanOrEqualTo(ChartTicks.maxTicks));
      expect(ChartTicks.between(1e-300, 2e-300, 3), isNotEmpty);
    },
  );
}
