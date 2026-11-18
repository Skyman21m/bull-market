import 'package:p2p/src/domain/trade/maker_form.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/make_form.dart';

/// The advanced options of the create form (#183), as the reference sets them (`components/MakerForm/MakerForm.tsx`, `AmountRange.tsx`, `models/Maker.model.ts`, commit ff1998c): the range, its bounds and ratios, the bond on its maximum, the description, the durations and the bond size, and what the request sends.
void main() {
  late CurrencyLimits narrow;
  late CurrencyLimits wide;
  late CurrencyLimits odd;
  late CurrencyLimits tiny;
  setUpAll(() async {
    // 100 to 1,000 EUR at 50,000: the form's limits are exactly 103 and 980.
    narrow = await limitsOf({2: (50000, 100, 1000)});
    // 10 to 10,000 EUR at 50,000: the form's limits are 10.3 and 9,800.
    wide = await limitsOf({2: (50000, 10, 10000)});
    // A largest order of 1,349 EUR, where rounding before or after the quarters differs (functional review of #183, C4).
    odd = await limitsOf({2: (50000, 100, 1349)});
    // 1 to 60 EUR: bounds of 2 significant digits at every place of the slider.
    tiny = await limitsOf({2: (50000, 1, 60)});
  });

  /// The slider moved from what it showed, [previous], to [next]: the thumb told as the screen tells it.
  MakerRange slide({
    required MakerRange previous,
    required MakerRange next,
    required MakerAmountLimits limits,
  }) => MakerRange.slid(
    moved: MakerRange.movedThumb(previous, next),
    next: next,
    limits: limits,
  );

  MakerFormCheck checkOf({
    bool advanced = true,
    bool range = true,
    String amount = '',
    String min = '200',
    String max = '400',
    String description = '',
    Duration publicDuration = MakerFormCheck.publicDurationDefault,
    Duration escrowDuration = MakerFormCheck.escrowDurationDefault,
    double bondSize = MakerFormCheck.bondSizeDefault,
    String premium = '',
    List<String> methods = const ['Revolut'],
    CurrencyLimits? limits,
  }) => MakerFormCheck.of(
    MakerFormInput(
      type: OrderType.buy,
      currency: eur,
      amount: amount,
      paymentMethods: methods,
      premium: premium,
      advanced: advanced,
      rangeEnabled: range,
      minAmount: min,
      maxAmount: max,
      description: description,
      publicDuration: publicDuration,
      escrowDuration: escrowDuration,
      bondSizePercent: bondSize,
    ),
    coordinatorsLoaded: true,
    market: MakerFormLimitsRead(limits ?? narrow),
    sizeLimitSats: 21 * 100000000,
  );

  group('the reference\'s defaults', () {
    test(
      'options closed, « Amount Range » on, 23:59 public, 3 hours, 3 %, no description',
      () {
        final input = MakerFormInput(
          type: OrderType.buy,
          currency: eur,
          amount: '100',
          paymentMethods: const ['Revolut'],
          premium: '',
        );
        expect(input.advanced, isFalse);
        expect(input.rangeEnabled, isTrue);
        expect(input.hasRange, isFalse);
        expect(input.publicDuration, const Duration(hours: 23, minutes: 59));
        expect(input.escrowDuration, const Duration(hours: 3));
        expect(input.bondSizePercent, 3);
        expect(input.description, '');
      },
    );

    test(
      'a range only while the options are open and « Amount Range » is chosen',
      () {
        expect(checkOf().hasRange, isTrue);
        expect(checkOf(advanced: false, amount: '200').hasRange, isFalse);
        expect(checkOf(range: false, amount: '200').hasRange, isFalse);
        // Closed, the bounds typed are not read: the exact amount is.
        final closed = checkOf(advanced: false, amount: '200', min: 'x');
        expect(closed.block, isNull);
        expect(closed.request?.amount, isA<FixedOrderAmount>());
        expect(closed.request?.amount.max.value, 200);
      },
    );
  });

  group('a range', () {
    test(
      'the request: a range of the bounds typed, as the summary shows them; the bond estimated on its maximum',
      () {
        final check = checkOf(bondSize: 5);
        expect(check.block, isNull);
        final amount = check.request?.amount;
        expect(amount, isA<RangeOrderAmount>());
        expect(amount?.min.value, 200);
        expect(amount?.max.value, 400);
        expect(check.rangeMin, 200);
        expect(check.rangeMax, 400);
        // (400 / 50,000) × 10^8 × 5 % = 40,000, the maximum's (`bondCalculator.ts:24`).
        expect(check.estimatedBond, 40000);
        expect(checkOf().estimatedBond, 24000);
        // No exact amount judged: nothing typed there is no reason.
        expect(check.amountProblem, isNull);
      },
    );

    test('the bounds: 0.99 of the form\'s smallest, 1.01 of its largest', () {
      // 103 × 0.99 = 101.97; 980 × 1.01 = 989.8.
      expect(checkOf(min: '101.98', max: '300').block, isNull);
      final low = checkOf(min: '101.96', max: '300');
      expect(low.block, MakerFormBlock.amountRangeInvalid);
      expect(low.rangeMinError, isTrue);
      expect(low.rangeMaxError, isFalse);
      expect(checkOf(min: '200', max: '989.79').block, isNull);
      final high = checkOf(min: '200', max: '989.81');
      expect(high.block, MakerFormBlock.amountRangeInvalid);
      expect(high.rangeMaxError, isTrue);
      expect(high.rangeMinError, isFalse);
    });

    test(
      'the reference\'s check of typed bounds (`AmountRange.tsx:57-77`): 1.6 − 0.1 and 14.8 + 0.15, in floating point as there',
      () {
        expect(MakerFormCheck.typedMinRangeRatio, 1.6 - 0.1);
        expect(MakerFormCheck.typedMaxRangeRatio, 14.8 + 0.15);
        // 1.6 − 0.1 is 1.5 in floating point: exactly 1.5 is taken, as there.
        expect(checkOf(min: '200', max: '300').block, isNull);
        expect(checkOf(min: '200', max: '320').block, isNull);
        final under = checkOf(min: '200', max: '299.99');
        expect(under.block, MakerFormBlock.amountRangeInvalid);
        expect(under.rangeMinError && under.rangeMaxError, isTrue);
        expect(checkOf(min: '100', max: '155', limits: wide).block, isNull);
        expect(checkOf(min: '100', max: '1495', limits: wide).block, isNull);
        expect(
          checkOf(min: '100', max: '1495.01', limits: wide).block,
          MakerFormBlock.amountRangeInvalid,
        );
        // 15, the coordinator's, is beyond the reference's 14.95.
        expect(
          checkOf(min: '100', max: '1500', limits: wide).block,
          MakerFormBlock.amountRangeInvalid,
        );
      },
    );

    test(
      'a maximum below the minimum; a bound left empty or no number read as 0, as the reference\'s number field',
      () {
        final crossed = checkOf(min: '400', max: '200');
        expect(crossed.rangeMinError && crossed.rangeMaxError, isTrue);
        expect(crossed.block, MakerFormBlock.amountRangeInvalid);
        final noMin = checkOf(min: '');
        expect(noMin.rangeMin, 0);
        // 0 is below the form's smallest amount, and 0 < 400 / 14.95: both fields in error.
        expect(noMin.rangeMinError && noMin.rangeMaxError, isTrue);
        expect(noMin.block, MakerFormBlock.amountRangeInvalid);
        final noMax = checkOf(max: 'abc');
        expect(noMax.rangeMax, 0);
        expect(noMax.rangeMaxError, isTrue);
        expect(checkOf(min: '0').rangeMinError, isTrue);
        expect(checkOf(min: '-200').block, MakerFormBlock.amountRangeInvalid);
        // No estimate without a maximum.
        expect(checkOf(max: '').estimatedBond, isNull);
      },
    );

    test('its reason in the reference\'s order', () {
      // Neither « Please enter an amount. » nor the exact amount's limits with a range.
      expect(checkOf(amount: '').block, isNull);
      expect(checkOf(amount: '5').block, isNull);
      // After the payment method's text, before the premium.
      expect(
        checkOf(min: '', methods: ['x' * 51]).block,
        MakerFormBlock.badPaymentMethod,
      );
      expect(
        checkOf(min: '', premium: '1000').block,
        MakerFormBlock.amountRangeInvalid,
      );
      expect(
        checkOf(min: '', methods: []).block,
        MakerFormBlock.amountRangeInvalid,
      );
    });
  });

  group('the description', () {
    test(
      'sent as the coordinator stores it: ends trimmed, an ideographic space made ordinary, `null` when empty',
      () {
        expect(checkOf().request?.description, isNull);
        expect(checkOf(description: '   ').request?.description, isNull);
        expect(
          checkOf(description: '  Revolut only,  please ').request?.description,
          'Revolut only,  please',
        );
        expect(
          checkOf(
            description: 'a${char(0x3000)}b${char(0x3000)}',
          ).request?.description,
          'a b',
        );
      },
    );

    test(
      'sent whatever the options say, as the reference sends `maker.description`',
      () {
        final closed = checkOf(
          advanced: false,
          amount: '200',
          description: 'Fast',
        );
        expect(closed.request?.description, 'Fast');
      },
    );

    test('240 UTF-16 units at most, as the reference counts', () {
      expect(checkOf(description: 'x' * 240).block, isNull);
      final long = checkOf(description: 'x' * 241);
      expect(long.descriptionTooLong, isTrue);
      expect(long.block, MakerFormBlock.descriptionInvalid);
      expect(long.request, isNull);
      // An emoji is two units: 121 are 242.
      expect(
        checkOf(description: chars([0x1F402]) * 121).descriptionTooLong,
        isTrue,
      );
      expect(checkOf(description: chars([0x1F402]) * 120).block, isNull);
    });

    test('a text others would not see as written is refused, said apart', () {
      for (final text in [
        'a${char(0x200B)}b',
        'line${char(0x0A)}break',
        'a${char(0x202E)}b',
        char(0x200B),
      ]) {
        final check = checkOf(description: text);
        expect(check.descriptionNotShown, isTrue, reason: text);
        expect(check.descriptionTooLong, isFalse, reason: text);
        expect(check.block, MakerFormBlock.descriptionInvalid, reason: text);
      }
    });

    test('its reason last, before « You must fill the form correctly »', () {
      expect(
        checkOf(description: 'x' * 241, methods: []).block,
        MakerFormBlock.noPaymentMethod,
      );
    });
  });

  group('the durations and the bond size', () {
    test('sent as chosen', () {
      final check = checkOf(
        publicDuration: const Duration(minutes: 10),
        escrowDuration: const Duration(hours: 10),
        bondSize: 15,
      );
      expect(check.block, isNull);
      expect(check.request?.publicDuration, const Duration(minutes: 10));
      expect(check.request?.escrowDuration, const Duration(hours: 10));
      expect(check.request?.bondSize.percent, 15);
      final other = checkOf(
        publicDuration: const Duration(hours: 23, minutes: 59),
        escrowDuration: const Duration(hours: 1),
        bondSize: 2,
      );
      expect(other.request?.publicDuration.inSeconds, 86340);
      expect(other.request?.escrowDuration.inSeconds, 3600);
      expect(other.request?.bondSize.percent, 2);
    });

    test(
      'the pickers\' bounds: 00:10 to 23:59 public, 01:00 to 10:00 for each step, whole minutes',
      () {
        expect(
          MakerFormCheck.publicDurationOf(const Duration(minutes: 9)),
          const Duration(minutes: 10),
        );
        expect(
          MakerFormCheck.publicDurationOf(const Duration(hours: 24)),
          const Duration(hours: 23, minutes: 59),
        );
        expect(
          MakerFormCheck.publicDurationOf(
            const Duration(hours: 5, minutes: 7, seconds: 30),
          ),
          const Duration(hours: 5, minutes: 7),
        );
        expect(
          MakerFormCheck.escrowDurationOf(const Duration(minutes: 30)),
          const Duration(hours: 1),
        );
        expect(
          MakerFormCheck.escrowDurationOf(const Duration(hours: 11)),
          const Duration(hours: 10),
        );
        expect(
          MakerFormCheck.escrowDurationOf(const Duration(hours: 4, minutes: 5)),
          const Duration(hours: 4, minutes: 5),
        );
      },
    );

    test('the slider\'s steps: 2 to 15 % by 0.25', () {
      expect(MakerFormCheck.bondSizeOf(3.1), 3);
      expect(MakerFormCheck.bondSizeOf(3.13), 3.25);
      expect(MakerFormCheck.bondSizeOf(1), 2);
      expect(MakerFormCheck.bondSizeOf(20), 15);
      expect(MakerFormCheck.bondSizeOf(double.nan), 3);
    });

    test(
      'a value no picker or slider gives is never sent: « You must fill the form correctly »',
      () {
        for (final check in [
          checkOf(publicDuration: const Duration(minutes: 9)),
          checkOf(publicDuration: const Duration(hours: 24)),
          checkOf(publicDuration: const Duration(minutes: 30, seconds: 1)),
          checkOf(escrowDuration: const Duration(minutes: 59)),
          checkOf(escrowDuration: const Duration(hours: 10, minutes: 1)),
          checkOf(bondSize: 2.1),
          checkOf(bondSize: 1.75),
          checkOf(bondSize: 15.25),
        ]) {
          expect(check.block, MakerFormBlock.formIncorrect);
          expect(check.request, isNull);
        }
      },
    );

    test('the bond estimated at the size chosen', () {
      // (400 / 50,000) × 10^8 × 15 % = 120,000.
      expect(checkOf(bondSize: 15).estimatedBond, 120000);
      expect(
        checkOf(advanced: false, amount: '200', bondSize: 2).estimatedBond,
        8000,
      );
    });
  });

  group(
    'the options sent, said under the summary (security review of #183, C1)',
    () {
      test('none at the defaults', () {
        expect(checkOf().optionsSent.any, isFalse);
        expect(
          checkOf(advanced: false, amount: '200').optionsSent.any,
          isFalse,
        );
      });

      test(
        'a description (never its text), each duration and the bond size away from their defaults',
        () {
          final sent = checkOf(
            advanced: false,
            amount: '200',
            description: 'Call me',
            escrowDuration: const Duration(hours: 1),
            bondSize: 15,
          ).optionsSent;
          expect(sent.any, isTrue);
          expect(sent.description, isTrue);
          expect(sent.publicDuration, isNull);
          expect(sent.escrowDuration, const Duration(hours: 1));
          expect(sent.bondSizePercent, 15);
          expect(
            checkOf(
              publicDuration: const Duration(minutes: 10),
            ).optionsSent.publicDuration,
            const Duration(minutes: 10),
          );
          // Only spaces is no description.
          expect(checkOf(description: '   ').optionsSent.any, isFalse);
        },
      );
    },
  );

  group('the range the form sets', () {
    test(
      'opening the options: half the amount and the amount, else a quarter and three quarters of the coordinator\'s largest order',
      () {
        final limit = narrow[eur];
        expect(
          MakerRange.opening(amount: 100, limit: limit),
          const MakerRange(50, 100),
        );
        // Half to 2 significant digits, the amount as it is.
        expect(
          MakerRange.opening(amount: 333, limit: limit),
          const MakerRange(170, 333),
        );
        // 1,000 × 0.25 and × 0.75, the coordinator's `max_amount` without margins.
        expect(
          MakerRange.opening(amount: null, limit: limit),
          const MakerRange(250, 750),
        );
        expect(
          MakerRange.opening(amount: 0, limit: limit),
          const MakerRange(250, 750),
        );
        expect(MakerRange.opening(amount: null, limit: null), isNull);
        // `max_amount` × 0.25 and × 0.75, each to 2 significant digits, never the rounded `max_amount` (`MakerForm.tsx:399`, `:403`): 337.25 and 1,011.75.
        expect(
          MakerRange.opening(amount: null, limit: odd[eur]),
          const MakerRange(340, 1000),
        );
      },
    );

    test(
      'a currency changed: kept within its orders, else set again to its quarters',
      () {
        final limit = narrow[eur];
        expect(
          MakerRange.afterCurrency(min: 200, max: 400, limit: limit),
          isNull,
        );
        expect(
          MakerRange.afterCurrency(min: 50, max: 400, limit: limit),
          const MakerRange(250, 750),
        );
        expect(
          MakerRange.afterCurrency(min: 200, max: 1100, limit: limit),
          const MakerRange(250, 750),
        );
        // A bound left empty is 0, as the reference reads it (`Number('')`): set again.
        expect(
          MakerRange.afterCurrency(min: 0, max: 400, limit: limit),
          const MakerRange(250, 750),
        );
        // Here the largest order is rounded first, as the reference rounds it there (`:186`, `:195-196`): 1,300 × 0.25 and × 0.75.
        expect(
          MakerRange.afterCurrency(min: 50, max: 400, limit: odd[eur]),
          const MakerRange(330, 980),
        );
        expect(
          MakerRange.afterCurrency(min: 200, max: 400, limit: null),
          isNull,
        );
      },
    );

    test(
      'the slider: the other thumb follows to keep 1.6 to 14.8, each bound to 2 or 3 significant digits',
      () {
        final narrowLimits = checkOf().limits;
        final wideLimits = checkOf(limits: wide).limits;
        expect(narrowLimits?.min, 103);
        expect(narrowLimits?.max, 980);
        if (narrowLimits == null || wideLimits == null) return;
        // The minimum capped at 980 × 0.98 / 1.6 = 600.25, the maximum pushed to 1.6 × 600.25 = 960.4.
        expect(
          slide(
            previous: const MakerRange(200, 800),
            next: const MakerRange(700, 800),
            limits: narrowLimits,
          ),
          const MakerRange(600, 960),
        );
        // The maximum at least 1.6 × 103 × 1.03 = 169.744, the minimum pulled to 169.744 / 1.6 = 106.09.
        expect(
          slide(
            previous: const MakerRange(120, 800),
            next: const MakerRange(120, 150),
            limits: narrowLimits,
          ),
          const MakerRange(106, 170),
        );
        // Above 14.8: the maximum follows the minimum moved.
        expect(
          slide(
            previous: const MakerRange(100, 9000),
            next: const MakerRange(20, 9000),
            limits: wideLimits,
          ),
          const MakerRange(20, 296),
        );
        // The maximum moved: the minimum follows.
        expect(
          slide(
            previous: const MakerRange(20, 200),
            next: const MakerRange(20, 1480),
            limits: wideLimits,
          ),
          const MakerRange(100, 1480),
        );
        // Within the ratios: only the precision.
        expect(
          slide(
            previous: const MakerRange(200, 500),
            next: const MakerRange(213.456, 500),
            limits: narrowLimits,
          ),
          const MakerRange(213, 500),
        );
        expect(
          slide(
            previous: const MakerRange(20, 200),
            next: const MakerRange(23.456, 200),
            limits: wideLimits,
          ),
          const MakerRange(23, 200),
        );
      },
    );

    test(
      'the thumb moved is the one that moved the most: the platform\'s slider can shift the other a little',
      () {
        expect(
          MakerRange.movedThumb(
            const MakerRange(200, 400),
            const MakerRange(200.04, 280),
          ),
          RangeThumb.max,
        );
        expect(
          MakerRange.movedThumb(
            const MakerRange(200, 400),
            const MakerRange(300, 399.96),
          ),
          RangeThumb.min,
        );
      },
    );

    test(
      '« to » pulled down: « From » follows, as the reference (`AmountRange.tsx:101-102`)',
      () {
        final limits = checkOf(limits: wide).limits;
        if (limits == null) fail('no limits');
        expect(
          slide(
            previous: const MakerRange(200, 400),
            next: const MakerRange(200, 280),
            limits: limits,
          ),
          const MakerRange(175, 280),
        );
        expect(
          slide(
            previous: const MakerRange(200, 400),
            next: const MakerRange(300, 400),
            limits: limits,
          ),
          const MakerRange(300, 480),
        );
      },
    );

    test(
      'where the reference\'s rounding leaves its own check, the other bound computed again from the one moved (functional review of #183, C2)',
      () {
        final limits = checkOf(limits: wide).limits;
        if (limits == null) fail('no limits');
        // The reference writes 20-302 (a ratio of 15.1, refused by its own check); here 20-296.
        final wideRange = slide(
          previous: const MakerRange(20, 9000),
          next: const MakerRange(20.4, 9000),
          limits: limits,
        );
        expect(wideRange, const MakerRange(20, 296));
        // 105-167: a ratio of 1.590, which the reference's check takes, written as the reference writes it.
        final narrowRange = slide(
          previous: const MakerRange(110, 200),
          next: const MakerRange(110, 167.4),
          limits: limits,
        );
        expect(narrowRange, const MakerRange(105, 167));
        for (final range in [wideRange, narrowRange]) {
          final check = checkOf(
            min: '${range.min}',
            max: '${range.max}',
            limits: wide,
          );
          expect(check.block, isNull, reason: '$range');
        }
      },
    );

    test(
      'every range the slider writes is one the form takes: each thumb across the slider, the other anywhere, for coordinators\' limits round and not, small and large, with and without a premium (security review of #183)',
      () async {
        final markets = [
          narrow,
          wide,
          tiny,
          odd,
          await limitsOf({2: (37.123, 0.77, 3.3)}),
          await limitsOf({2: (1234.5678, 13.37, 999.99)}),
          await limitsOf({2: (50000, 2.5, 6.1)}),
          await limitsOf({2: (91711.15, 18.34223, 4585.5575)}),
          await limitsOf({2: (64000, 0.0123, 0.5)}),
          await limitsOf({2: (50000, 123456, 9876543)}),
        ];
        var ranges = 0;
        for (final market in markets) {
          for (final premium in ['', '7.5', '-12.25']) {
            final limits = checkOf(limits: market, premium: premium).limits;
            if (limits == null) fail('no limits');
            final low = limits.min;
            final high = limits.max;
            double at(int step, int of) => low + (high - low) * step / of;
            for (var other = 0; other <= 12; other++) {
              for (var step = 0; step <= 120; step++) {
                final value = at(step, 120);
                final fixed = at(other, 12);
                for (final (moved, next) in [
                  if (value <= fixed)
                    (RangeThumb.min, MakerRange(value, fixed)),
                  if (value >= fixed)
                    (RangeThumb.max, MakerRange(fixed, value)),
                ]) {
                  final range = MakerRange.slid(
                    moved: moved,
                    next: next,
                    limits: limits,
                  );
                  ranges++;
                  final errors = MakerFormCheck.rangeErrorsOf(
                    range.min,
                    range.max,
                    limits,
                  );
                  expect(
                    errors.min || errors.max,
                    isFalse,
                    reason:
                        '$low-$high, $moved: ${next.min}-${next.max} gave ${range.min}-${range.max}',
                  );
                  // As the field writes it back: no more than the amount's decimals.
                  for (final bound in [range.min, range.max]) {
                    expect(
                      double.parse(bound.toStringAsFixed(8)),
                      bound,
                      reason: '$bound',
                    );
                  }
                }
              }
            }
          }
        }
        expect(ranges, greaterThan(40000));
      },
    );

    test('what the slider sets is a range the form takes', () {
      final limits = checkOf().limits;
      if (limits == null) fail('no limits');
      for (final (previous, next) in [
        (const MakerRange(200, 800), const MakerRange(700, 800)),
        (const MakerRange(120, 800), const MakerRange(120, 150)),
        (const MakerRange(200, 500), const MakerRange(103, 500)),
        (const MakerRange(200, 500), const MakerRange(200, 980)),
      ]) {
        final range = slide(previous: previous, next: next, limits: limits);
        final check = checkOf(min: '${range.min}', max: '${range.max}');
        expect(check.block, isNull, reason: '$previous → $next: $range');
      }
    });
  });

  test(
    'the package\'s nominal ratios, the coordinator\'s, are no narrower than the form\'s',
    () {
      expect(
        MakeOrderRequest.minRangeRatio,
        lessThanOrEqualTo(MakerFormCheck.typedMinRangeRatio),
      );
      expect(
        MakeOrderRequest.maxRangeRatio,
        greaterThan(MakerFormCheck.typedMaxRangeRatio),
      );
      expect(MakerAmountLimits.rangeMinMargin, 0.99);
      expect(MakerAmountLimits.rangeMaxMargin, 1.01);
    },
  );
}
