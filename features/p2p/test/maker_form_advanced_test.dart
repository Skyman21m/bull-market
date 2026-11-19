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

  group('why a range typed is refused (#225)', () {
    test('one reason, the first that applies, with the bound the form takes', () {
      // The form's limits here are 103 and 980, the amounts under the slider's ends: a minimum is taken from 101.97, a maximum to 989.8.
      final limits = checkOf().limits;
      expect(MakerRangeProblem.of(200, 400, limits), isNull);
      expect(
        MakerRangeProblem.of(400, 200, limits),
        isA<MakerRangeMaxBelowMin>(),
      );
      expect(
        MakerRangeProblem.of(56, 826, limits),
        isA<MakerRangeMinTooSmall>().having((p) => p.atLeast, 'atLeast', 103),
      );
      expect(
        MakerRangeProblem.of(200, 1400, limits),
        isA<MakerRangeMaxTooBig>().having((p) => p.atMost, 'atMost', 980),
      );
      expect(
        MakerRangeProblem.of(200, 250, limits),
        isA<MakerRangeTooNarrow>()
            .having((p) => p.min, 'min', 200)
            .having((p) => p.atLeast, 'atLeast', 300),
      );
      // Too wide beside its minimum, without limits to say more: 14.95 times 20 is 299.
      expect(
        MakerRangeProblem.of(20, 302, null),
        isA<MakerRangeTooWide>()
            .having((p) => p.min, 'min', 20)
            .having((p) => p.atMost, 'atMost', 299),
      );
      // Nothing typed: the minimum first.
      expect(MakerRangeProblem.of(0, 0, limits), isA<MakerRangeMinTooSmall>());
      // Both bounds outside the form's amounts: the minimum first.
      expect(
        MakerRangeProblem.of(56, 1400, limits),
        isA<MakerRangeMinTooSmall>(),
      );
      // A minimum whose 1.5 times is above the largest amount: the minimum comes down, never « at least 1,050 » for a maximum the form would then refuse (independent review of #226, C1). 980 / 1.5 = 653.3.
      expect(
        MakerRangeProblem.of(700, 900, limits),
        isA<MakerRangeMinTooBig>().having((p) => p.atMost, 'atMost', 653),
      );
      // Without limits, a bound that is not above zero is said as such, never « cannot exceed -75 » (R4).
      expect(MakerRangeProblem.of(-5, 10, null), isA<MakerRangeNotPositive>());
      expect(MakerRangeProblem.of(10, 0, null), isA<MakerRangeNotPositive>());
      expect(MakerRangeProblem.of(10, 5, null), isA<MakerRangeMaxBelowMin>());
    });

    test(
      'limits that leave room for no range say so, whatever is typed (independent review of #226, R3)',
      () {
        // 100 to 1,000 EUR at 50,000 under a size limit of 250,000 sats: the form's amounts are 103 to 122.5, and 1.5 times the smallest is above the largest.
        final limits = MakerAmountLimits.of(
          narrow[eur] ?? (throw StateError('EUR')),
          premium: Premium.tryCreate(0) ?? (throw StateError('a premium')),
          sizeLimitSats: 250000,
        );
        for (final (low, high) in [
          (0.0, 0.0),
          (103.0, 122.0),
          (110.0, 165.0),
          (200.0, 100.0),
        ]) {
          expect(
            MakerRangeProblem.of(low, high, limits),
            isA<MakerRangeNoRoom>(),
            reason: '$low to $high',
          );
        }
      },
    );

    test(
      'the reasons followed one after the other lead to a range the form takes, never round in a circle (independent review of #226, C1)',
      () {
        final limits = checkOf().limits;
        const bounds = <double>[
          0,
          1,
          20,
          56,
          101,
          103,
          150,
          300,
          500,
          653,
          654,
          700,
          826,
          980,
          990,
          1400,
          5000,
        ];
        for (final start in bounds) {
          for (final end in bounds) {
            for (final under in [limits, null]) {
              var low = start;
              var high = end;
              var steps = 0;
              while (true) {
                final problem = MakerRangeProblem.of(low, high, under);
                if (problem == null) break;
                steps++;
                if (steps > 5) {
                  fail(
                    'still refused after 5 reasons from $start to $end ($low to $high, $problem), limits $under',
                  );
                }
                switch (problem) {
                  case MakerRangeNoRoom():
                    fail('no room said for limits that leave room');
                  case MakerRangeNotPositive():
                    low = 1;
                    high = 2;
                  case MakerRangeMaxBelowMin():
                    // No figure is given: the user types a maximum above the minimum.
                    high = low * 2;
                  case MakerRangeMinTooSmall(:final atLeast):
                    low = atLeast;
                  case MakerRangeMinTooBig(:final atMost):
                    low = atMost;
                  case MakerRangeMaxTooBig(:final atMost):
                    high = atMost;
                  case MakerRangeTooNarrow(:final atLeast):
                    high = atLeast;
                  case MakerRangeTooWide(:final atMost):
                    high = atMost;
                }
              }
            }
          }
        }
      },
    );

    test(
      'a reason exactly when a field is in error, and the bound shown is one the form takes when typed',
      () {
        final limits = checkOf().limits;
        const bounds = <double>[
          0,
          1,
          20,
          56,
          101,
          102,
          103,
          150,
          200,
          299,
          300,
          400,
          826,
          980,
          989,
          990,
          1400,
          5000,
        ];
        var refused = 0;
        for (final low in bounds) {
          for (final high in bounds) {
            for (final under in [limits, null]) {
              final errors = MakerFormCheck.rangeErrorsOf(low, high, under);
              final problem = MakerRangeProblem.of(low, high, under);
              expect(
                problem == null,
                !errors.min && !errors.max,
                reason: '$low to $high, limits $under',
              );
              if (problem == null) continue;
              refused++;
              // The bound shown, typed in place of the one at fault, no longer breaks that rule.
              switch (problem) {
                case MakerRangeNoRoom():
                  fail('no room said for limits that leave room');
                case MakerRangeNotPositive():
                  expect(under, isNull);
                case MakerRangeMinTooBig(:final atMost):
                  expect(
                    MakerRangeProblem.of(atMost, high, under),
                    isNot(isA<MakerRangeMinTooBig>()),
                    reason: '$low to $high',
                  );
                case MakerRangeMaxBelowMin():
                  expect(high, lessThan(low));
                case MakerRangeMinTooSmall(:final atLeast):
                  expect(
                    MakerRangeProblem.of(atLeast, high, under),
                    isNot(isA<MakerRangeMinTooSmall>()),
                    reason: '$low to $high',
                  );
                case MakerRangeMaxTooBig(:final atMost):
                  expect(
                    MakerRangeProblem.of(low, atMost, under),
                    isNot(isA<MakerRangeMaxTooBig>()),
                    reason: '$low to $high',
                  );
                case MakerRangeTooNarrow(:final min, :final atLeast):
                  expect(min, low);
                  expect(
                    MakerRangeProblem.of(low, atLeast, under),
                    isNot(isA<MakerRangeTooNarrow>()),
                    reason: '$low to $high',
                  );
                case MakerRangeTooWide(:final min, :final atMost):
                  expect(min, low);
                  expect(
                    MakerRangeProblem.of(low, atMost, under),
                    isNot(isA<MakerRangeTooWide>()),
                    reason: '$low to $high',
                  );
              }
            }
          }
        }
        expect(refused, greaterThan(200));
      },
    );

    test('the form\'s check carries it for a range only', () {
      expect(checkOf(min: '200', max: '400').rangeProblem, isNull);
      expect(
        checkOf(min: '56', max: '826').rangeProblem,
        isA<MakerRangeMinTooSmall>(),
      );
      expect(
        checkOf(min: '56', max: '826').block,
        MakerFormBlock.amountRangeInvalid,
      );
      // « Exact Amount », or the options closed: no range, no reason of one.
      expect(
        checkOf(
          range: false,
          amount: '200',
          min: '56',
          max: '826',
        ).rangeProblem,
        isNull,
      );
      expect(
        checkOf(
          advanced: false,
          amount: '200',
          min: '56',
          max: '826',
        ).rangeProblem,
        isNull,
      );
    });
  });

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
      'opening the options never fills in a range the form refuses: on a young coordinator with a discount the reference fills in 58 to 170 and refuses 170, the form\'s largest amount being 143 (#225)',
      () async {
        // The trial of 2026-11-19: 6.98 to 232.66 EUR at 58,165, a premium of -21 %, the size limit of a coordinator a few weeks old (250,000 sats, `calculateSizeLimit`, `Coordinator.model.ts:110-124`).
        final young = await limitsOf({2: (58165, 6.98, 232.66)});
        final limit = young[eur];
        final limits = MakerAmountLimits.of(
          limit ?? (throw StateError('EUR is in the limits')),
          premium: Premium.tryCreate(-21) ?? (throw StateError('a premium')),
          sizeLimitSats: 250000,
        );
        expect(limits.max, closeTo(142.5, 0.01));
        // The reference's range, and that the form refuses it.
        final reference = MakerRange.opening(amount: null, limit: limit);
        expect(reference, const MakerRange(58, 170));
        expect(MakerFormCheck.rangeErrorsOf(58, 170, limits), (
          min: false,
          max: true,
        ));
        // The form's: a quarter and three quarters of its own largest amount.
        final opened = MakerRange.opening(
          amount: null,
          limit: limit,
          limits: limits,
        );
        expect(opened, const MakerRange(36, 110));
        // An amount typed above the form's largest: half of it, and the largest the form takes.
        final typed = MakerRange.opening(
          amount: 170,
          limit: limit,
          limits: limits,
        );
        expect(typed?.min, 85);
        expect(typed?.max, lessThanOrEqualTo(limits.max * 1.01));
        expect(typed?.max, greaterThan(140));
        for (final range in [opened, typed]) {
          expect(
            MakerFormCheck.rangeErrorsOf(
              range?.min ?? 0,
              range?.max ?? 0,
              limits,
            ),
            (min: false, max: false),
          );
        }
      },
    );

    test(
      'opening the options stays the reference\'s range whenever the form takes it (#225)',
      () {
        final limits = checkOf().limits;
        for (final amount in <double?>[null, 333, 900]) {
          expect(
            MakerRange.opening(
              amount: amount,
              limit: narrow[eur],
              limits: limits,
            ),
            MakerRange.opening(amount: amount, limit: narrow[eur]),
            reason: 'amount $amount',
          );
        }
        // Without the coordinator's limit and without an amount, nothing to set, whatever the form's limits.
        expect(
          MakerRange.opening(amount: null, limit: null, limits: limits),
          isNull,
        );
        // An amount whose half is below the form's smallest amount (103): the reference fills in 55 to 110 and refuses 55; here the nearest range the form takes.
        expect(
          MakerRange.opening(amount: 110, limit: narrow[eur]),
          const MakerRange(55, 110),
        );
        final near = MakerRange.opening(
          amount: 110,
          limit: narrow[eur],
          limits: limits,
        );
        expect(near, isNot(const MakerRange(55, 110)));
        expect(
          MakerFormCheck.rangeErrorsOf(near?.min ?? 0, near?.max ?? 0, limits),
          (min: false, max: false),
        );
      },
    );

    test(
      'limits a coordinator gives without sense set nothing in the fields that is not a number above zero (independent review of #226, R3)',
      () async {
        final huge = await limitsOf({2: (50000, 100, 1e300)});
        final limit = huge[eur] ?? (throw StateError('EUR'));
        for (final size in [double.infinity, double.nan, -1.0, 0.0]) {
          final limits = MakerAmountLimits.of(
            limit,
            premium: Premium.tryCreate(0) ?? (throw StateError('a premium')),
            sizeLimitSats: size,
          );
          for (final amount in <double?>[null, 100]) {
            final range = MakerRange.opening(
              amount: amount,
              limit: limit,
              limits: limits,
            );
            if (range != null) {
              expect(
                range.min.isFinite && range.min > 0,
                isTrue,
                reason: '$size',
              );
              expect(
                range.max.isFinite && range.max > 0,
                isTrue,
                reason: '$size',
              );
            }
          }
        }
      },
    );

    test(
      'opening the options, a sweep of coordinators, premiums, size limits and amounts: the range filled in is always one the form takes (#225)',
      () async {
        var opened = 0;
        var changed = 0;
        for (final (price, low, high) in [
          (50000.0, 100.0, 1000.0),
          (50000.0, 10.0, 10000.0),
          (58165.0, 6.98, 232.66),
          (58165.0, 6.98, 1745.0),
          (63000.0, 12.6, 1070000.0),
          (0.9, 0.5, 40.0),
        ]) {
          final market = await limitsOf({2: (price, low, high)});
          final limit = market[eur] ?? (throw StateError('EUR'));
          for (final percent in [-60.0, -21.0, -5.0, 0.0, 7.5, 40.0, 300.0]) {
            final premium =
                Premium.tryCreate(percent) ?? (throw StateError('a premium'));
            for (final size in [250000.0, 928000.0, 21 * 100000000.0]) {
              final limits = MakerAmountLimits.of(
                limit,
                premium: premium,
                sizeLimitSats: size,
              );
              // Limits too close for any range (the largest under about 1.65 times the smallest) are no coordinator's: left out, as for the slider.
              if (limits.max < limits.min * 1.7) continue;
              for (final amount in <double?>[
                null,
                limits.min,
                limits.min * 1.2,
                limits.max / 2,
                limits.max,
                limits.max * 3,
              ]) {
                final range = MakerRange.opening(
                  amount: amount,
                  limit: limit,
                  limits: limits,
                );
                final reference = MakerRange.opening(
                  amount: amount,
                  limit: limit,
                );
                if (range == null) fail('a range for $limits, amount $amount');
                opened++;
                if (range != reference) changed++;
                expect(
                  MakerFormCheck.rangeErrorsOf(range.min, range.max, limits),
                  (min: false, max: false),
                  reason:
                      '${range.min} to ${range.max} at $price, $low-$high, premium $percent, size $size, amount $amount, limits $limits',
                );
              }
            }
          }
        }
        // The sweep opens ranges both ways: the reference's kept, and the reference's refused and set within the form's limits.
        expect(opened, greaterThan(300));
        expect(changed, greaterThan(50));
        expect(opened - changed, greaterThan(50));
      },
    );

    test(
      'a currency changed never leaves a range the form refuses in the new currency: kept or set again as the reference does when the form takes it, else set within the form\'s limits (#225)',
      () async {
        // FreePort on 2026-11-19: 480 to 1,400 filled in in USD, kept by the reference in EUR (within 6.98 and 1,745), refused there at -21 % under a size limit of 928,000 sats (the form's largest amount 529).
        final market = await limitsOf({2: (58165, 6.98, 1745)});
        final limit = market[eur] ?? (throw StateError('EUR'));
        final limits = MakerAmountLimits.of(
          limit,
          premium: Premium.tryCreate(-21) ?? (throw StateError('a premium')),
          sizeLimitSats: 928000,
        );
        expect(limits.max, closeTo(528.97, 0.01));
        expect(
          MakerRange.afterCurrency(min: 480, max: 1400, limit: limit),
          isNull,
        );
        expect(
          MakerRange.afterCurrency(
            min: 480,
            max: 1400,
            limit: limit,
            limits: limits,
          ),
          const MakerRange(130, 400),
        );
        // Set again by the reference on a range the form refuses: the form's own.
        expect(
          MakerRange.afterCurrency(min: 2, max: 4, limit: limit),
          const MakerRange(430, 1300),
        );
        expect(
          MakerRange.afterCurrency(
            min: 2,
            max: 4,
            limit: limit,
            limits: limits,
          ),
          const MakerRange(130, 400),
        );
        // A range the form takes in the new currency is kept, as the reference keeps it.
        expect(
          MakerRange.afterCurrency(
            min: 200,
            max: 400,
            limit: limit,
            limits: limits,
          ),
          isNull,
        );
        // A range the reference keeps, whose bounds are only too close or too far apart, is kept: the currency does not change that, and the bounds typed stay (independent review of #226, C2).
        for (final (low, high) in [(300.0, 320.0), (20.0, 500.0)]) {
          expect(
            MakerFormCheck.rangeErrorsOf(low, high, limits),
            isNot((min: false, max: false)),
          );
          expect(
            MakerRange.afterCurrency(
              min: low,
              max: high,
              limit: limit,
              limits: limits,
            ),
            isNull,
            reason: '$low to $high',
          );
        }
        // The reference's range, when the form takes it.
        final mature = checkOf().limits;
        expect(
          MakerRange.afterCurrency(
            min: 50,
            max: 400,
            limit: narrow[eur],
            limits: mature,
          ),
          const MakerRange(250, 750),
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

    test(
      'limits with no room for a range (the largest under about 1.65 times the smallest): the reference\'s range, rounded as it writes it, which the form says is not valid (security review of #183, R7)',
      () async {
        final tight = await limitsOf({2: (50000, 100, 150)});
        for (final premium in ['', '7.5']) {
          final limits = checkOf(limits: tight, premium: premium).limits;
          if (limits == null) fail('no limits');
          final low = limits.min;
          final high = limits.max;
          for (var step = 0; step <= 40; step++) {
            final value = low + (high - low) * step / 40;
            for (final (moved, next) in [
              (RangeThumb.min, MakerRange(value, high)),
              (RangeThumb.max, MakerRange(low, value)),
            ]) {
              final range = MakerRange.slid(
                moved: moved,
                next: next,
                limits: limits,
              );
              for (final bound in [range.min, range.max]) {
                expect(
                  bound,
                  significant(bound, bound < 100 ? 2 : 3),
                  reason: '$bound',
                );
              }
              final check = checkOf(
                min: '${range.min}',
                max: '${range.max}',
                limits: tight,
                premium: premium,
              );
              expect(check.block, MakerFormBlock.amountRangeInvalid);
            }
          }
        }
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
