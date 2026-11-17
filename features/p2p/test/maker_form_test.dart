import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/maker_form.dart';
import 'package:p2p/src/domain/trade/trade_tolerances.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/make_form.dart';

/// The create form's rules (#181): what a field reads, the reference's limits, rate and estimate, the reasons of a disabled « Create order » in the reference's order, the request built from the values the summary shows, and the price check of the owner's decision of 2026-11-17.
void main() {
  group('a number typed', () {
    FormNumber amount(String text) =>
        FormNumber.read(text, maxDecimals: MakerFormCheck.amountDecimals);

    test('nothing, or only spaces, is empty', () {
      expect(amount(''), isA<FormNumberEmpty>());
      expect(amount('   '), isA<FormNumberEmpty>());
    });

    test('a point or a comma, spaces at the ends, a minus, nothing else', () {
      for (final (text, value) in [
        ('12', 12.0),
        ('12.5', 12.5),
        ('12,5', 12.5),
        (' 12 ', 12.0),
        ('.5', 0.5),
        (',5', 0.5),
        ('5.', 5.0),
        ('-5', -5.0),
        ('0012', 12.0),
        ('10000000000000000000', 1e19),
        ('123456789.12345678', 123456789.12345678),
      ]) {
        expect(amount(text).value, value, reason: text);
      }
      // `-0` is 0, never a negative zero.
      expect((amount('-0').value ?? 1).isNegative, isFalse);
      expect((amount('-0.0').value ?? 1).isNegative, isFalse);
    });

    test('anything that is not a plain decimal number is no number', () {
      for (final text in [
        '1 000',
        '1,000.5',
        '1.000,5',
        '1..5',
        '+5',
        '--5',
        '5-',
        '-',
        '.',
        ',',
        '-.',
        'NaN',
        'nan',
        'Infinity',
        '-Infinity',
        '1e5',
        '1E5',
        '0x10',
        'abc',
        '12abc',
        '1_000',
        // A character no keyboard of digits gives: a no-break space, a zero width space, a Thai digit.
        '1${char(0xA0)}000',
        '12${char(0x200B)}',
        chars([0x0E51, 0x0E52]),
        // More than 20 characters.
        '1' * 21,
      ]) {
        expect(amount(text), isA<FormNumberInvalid>(), reason: text);
      }
    });

    test(
      'the digits of the Arabic-Indic, Persian, Devanagari and full-width scripts, and the Arabic decimal separator',
      () {
        expect(amount(chars([0x0661, 0x0662, 0x066B, 0x0665])).value, 12.5);
        expect(amount(chars([0x06F1, 0x06F2])).value, 12.0);
        expect(amount(chars([0x0967, 0x0968])).value, 12.0);
        expect(amount(chars([0xFF11, 0xFF12])).value, 12.0);
        // The full-width full stop and comma, beside the full-width digits (functional review of #181, R5).
        expect(amount(chars([0xFF11, 0xFF12, 0xFF0E, 0xFF15])).value, 12.5);
        expect(amount(chars([0xFF11, 0xFF12, 0xFF0C, 0xFF15])).value, 12.5);
        // Each script's zero and nine too.
        expect(amount(chars([0x0661, 0x0660, 0x0669])).value, 109.0);
        expect(amount(chars([0x06F1, 0x06F0, 0x06F9])).value, 109.0);
        expect(amount(chars([0x0967, 0x0966, 0x096F])).value, 109.0);
        expect(amount(chars([0xFF11, 0xFF10, 0xFF19])).value, 109.0);
      },
    );

    test(
      'no number a double cannot hold as it is typed (security review of #181): what the field shows is what is read and sent',
      () {
        for (final text in [
          '100000000.00000002',
          '99999999999999999999',
          '12345678901234567.5',
        ]) {
          expect(amount(text), isA<FormNumberInvalid>(), reason: text);
          expect(
            FormNumber.beyondPrecision(
              text,
              maxDecimals: MakerFormCheck.amountDecimals,
            ),
            isTrue,
            reason: text,
          );
        }
        for (final text in ['100000000.00000001', '0.1', '12.50', '5.', '.5']) {
          expect(amount(text), isA<FormNumberValue>(), reason: text);
          expect(
            FormNumber.beyondPrecision(
              text,
              maxDecimals: MakerFormCheck.amountDecimals,
            ),
            isFalse,
            reason: text,
          );
        }
        // Not a number at all, or too many decimals: not « beyond precision », the field's other rules say it.
        expect(FormNumber.beyondPrecision('abc', maxDecimals: 8), isFalse);
        expect(FormNumber.beyondPrecision('1.123456789', maxDecimals: 8), isFalse);
      },
    );

    test('no more decimals than the field keeps', () {
      expect(amount('1.12345678').value, 1.12345678);
      expect(amount('1.123456789'), isA<FormNumberInvalid>());
      final premium = FormNumber.read(
        '1.234',
        maxDecimals: MakerFormCheck.premiumDecimals,
      );
      expect(premium, isA<FormNumberInvalid>());
      expect(FormNumber.read('-1.23', maxDecimals: 2).value, -1.23);
    });
  });

  group('a custom payment method', () {
    test('kept as others see it: its ends trimmed, its spaces single', () {
      expect(CustomPaymentMethod.tryCreate('  Lydia  ')?.text, 'Lydia');
      expect(
        CustomPaymentMethod.tryCreate('Lydia${char(0x3000)}')?.text,
        'Lydia',
      );
      // The ideographic space a Japanese keyboard types is an ordinary space (functional review of #181, R4).
      expect(
        CustomPaymentMethod.tryCreate(
          chars([0x9280, 0x884C, 0x3000, 0x632F, 0x8FBC]),
        )?.text,
        chars([0x9280, 0x884C, 0x20, 0x632F, 0x8FBC]),
      );
      expect(
        CustomPaymentMethod.tryCreate('Bank   transfer')?.text,
        'Bank transfer',
      );
      // Persian, with its zero width non-joiner between two letters.
      final persian = chars([
        0x06A9, 0x0627, 0x0631, 0x062A, 0x200C, 0x0628, 0x0647, //
        0x200C, 0x06A9, 0x0627, 0x0631, 0x062A,
      ]);
      expect(CustomPaymentMethod.tryCreate(persian)?.text, persian);
    });

    test('« Can\'t be empty »: nothing left but spaces', () {
      for (final text in ['', ' ', '    ']) {
        expect(CustomPaymentMethod.tryCreate(text), isNull);
        expect(CustomPaymentMethod.isEmpty(text), isTrue);
      }
    });

    test(
      'never a method that shows as empty or that others would see otherwise (security review of #194)',
      () {
        for (final text in [
          char(0x200B),
          chars([0x200B, 0x200B, 0x200B]),
          'SEPA${char(0x200B)}',
          'SEPA${char(0xA0)}Revolut',
          // Another space than the ideographic one, which is made ordinary.
          'SEPA${char(0x2007)}Revolut',
          '${char(0xE0041)}${char(0xE0042)}',
          'Revolut${char(0xE0041)}',
          char(0x0301),
          'SEPA${char(0x202E)}',
          'SEPA${char(0x2066)}x',
          'SEPA\nRevolut',
          'SEPA${char(0xE000)}',
          char(0x3164),
          char(0x2800),
        ]) {
          expect(
            CustomPaymentMethod.tryCreate(text),
            isNull,
            reason: text.runes.map((r) => r.toRadixString(16)).join(' '),
          );
          expect(CustomPaymentMethod.isEmpty(text), isFalse);
        }
      },
    );
  });

  group('the form, as the reference judges it', () {
    late CurrencyLimits limits;
    late CurrencyLimits limitsRecorded;
    late CurrencyLimits limitsExact;
    setUpAll(() async {
      limits = await limitsAt({2: 91711.15, 1: 100000});
      limitsRecorded = await limitsAt({2: 66227.95});
      // Bounds of 100 and 1,000 EUR: the form's are exactly 103 and 980.
      limitsExact = await limitsOf({2: (50000, 100, 1000)});
    });

    MakerFormCheck checkOf({
      OrderType? type = OrderType.buy,
      RobosatsCurrency? currency,
      String amount = '100',
      List<String> methods = const ['Revolut'],
      String premium = '',
      bool loaded = true,
      MakerFormLimits? market,
      double sizeLimitSats = 21 * 100000000,
    }) => MakerFormCheck.of(
      MakerFormInput(
        type: type,
        currency: currency ?? eur,
        amount: amount,
        paymentMethods: methods,
        premium: premium,
      ),
      coordinatorsLoaded: loaded,
      market: market ?? MakerFormLimitsRead(limits),
      sizeLimitSats: sizeLimitSats,
    );

    test(
      'a ready form: the request of the summary\'s values, with the reference\'s defaults',
      () {
        final check = checkOf(premium: '2', methods: ['Revolut', 'SEPA']);
        expect(check.block, isNull);
        final request = check.request;
        expect(request, isNotNull);
        expect(request?.type, OrderType.buy);
        expect(request?.currency, eur);
        expect(request?.amount, isA<FixedOrderAmount>());
        expect(request?.amount.max.value, check.amount);
        expect(check.amount, 100);
        expect(request?.premium.percent, check.premiumPercent);
        expect(check.premiumPercent, 2);
        expect(request?.paymentMethod, 'Revolut SEPA');
        expect(request?.publicDuration, const Duration(seconds: 86340));
        expect(request?.escrowDuration, const Duration(seconds: 10800));
        expect(request?.bondSize.percent, 3);
        expect(request?.description, isNull);
      },
    );

    test(
      'the rate to 5 significant digits, the estimate of the reference, the limits with their margins',
      () {
        final atMarket = checkOf();
        expect(atMarket.price, 91711.15);
        expect(atMarket.rate, 91711);
        // (100 / 91,711) × 10^8 × 3 % = 3,271.14…
        expect(atMarket.estimatedBond, 3271);
        // 20,000 and 5,000,000 sats at 91,711.15, × 1.03 and × 0.98.
        expect(atMarket.limits?.min, closeTo(18.89249, 1e-5));
        expect(atMarket.limits?.max, closeTo(4493.84635, 1e-5));
        final premium = checkOf(premium: '2');
        // 91,711.15 × 1.02 = 93,545.373.
        expect(premium.rate, 93545);
        // (100 / 93,545) × 10^8 × 3 % = 3,207.01…
        expect(premium.estimatedBond, 3207);
        expect(premium.limits?.min, closeTo(18.89249 * 1.02, 1e-4));
        final discount = checkOf(premium: '-5.5');
        expect(discount.rate, 86667);
        // Rounded down, never to the nearest (functional review of #181, R12): 100 / 67,553 × 10^8 × 3 % = 4,440.96.
        final recorded = MakerFormCheck.of(
          MakerFormInput(
            type: OrderType.buy,
            currency: eur,
            amount: '100',
            paymentMethods: const ['Revolut'],
            premium: '2',
          ),
          coordinatorsLoaded: true,
          market: MakerFormLimitsRead(limitsRecorded),
          sizeLimitSats: 21 * 100000000,
        );
        expect(recorded.rate, 67553);
        expect(recorded.estimatedBond, 4440);
      },
    );

    test(
      'no estimate for no amount, nothing typed, or a negative one; every figure finite',
      () {
        expect(checkOf(amount: '').estimatedBond, isNull);
        expect(checkOf(amount: '0').estimatedBond, isNull);
        expect(checkOf(amount: '-5').estimatedBond, isNull);
        expect(checkOf(amount: 'NaN').estimatedBond, isNull);
        final huge = checkOf(amount: '10000000000000000000');
        expect(huge.estimatedBond, isNull);
        expect(huge.block, MakerFormBlock.amountOutsideLimits);
      },
    );

    test('the amount\'s line: the bound to 2 significant digits', () {
      final low = checkOf(amount: '18.8');
      expect(low.amountProblem, isA<MakerAmountTooLow>());
      expect(low.amountProblem?.shown, 19);
      final high = checkOf(amount: '4500');
      expect(high.amountProblem, isA<MakerAmountTooHigh>());
      expect(high.amountProblem?.shown, 4500);
      expect(checkOf(amount: '18.9').amountProblem, isNull);
      expect(checkOf(amount: '4493.84').amountProblem, isNull);
      expect(checkOf(amount: '4493.85').amountProblem, isNotNull);
      // A zero is no number outside the limits, as the reference's `maker.amount &&` (`MakerForm.tsx:884`).
      expect(checkOf(amount: '0').amountProblem, isNull);
    });

    test(
      'the bounds themselves are allowed (functional review of #181, R12)',
      () {
        final market = MakerFormLimitsRead(limitsExact);
        expect(checkOf(market: market).limits?.min, 103);
        expect(checkOf(market: market).limits?.max, 980);
        for (final (amount, allowed) in [
          ('103', true),
          ('102.99999999', false),
          ('980', true),
          ('980.00000001', false),
        ]) {
          final check = checkOf(market: market, amount: amount);
          expect(check.amountProblem == null, allowed, reason: amount);
          expect(check.block == null, allowed, reason: amount);
        }
      },
    );

    test('the size limit caps the maximum, without the premium', () {
      final capped = checkOf(sizeLimitSats: 250000, premium: '2');
      expect(capped.limits?.max, closeTo(250000 / 1e8 * 91711.15 * 0.98, 1e-9));
      expect(
        checkOf(amount: '225', sizeLimitSats: 250000).block,
        MakerFormBlock.amountOutsideLimits,
      );
    });

    test('the premium\'s bounds: above 999, or -100 and below', () {
      expect(checkOf(premium: '999').premiumProblem, isNull);
      // At 999 % the coordinator's smallest order is about 207.6 EUR.
      expect(checkOf(premium: '999', amount: '1000').block, isNull);
      expect(
        checkOf(premium: '999.01').premiumProblem,
        MakerPremiumProblem.tooHigh,
      );
      expect(checkOf(premium: '-99.99').premiumProblem, isNull);
      // At -99.99 % its largest is about 0.449 EUR.
      expect(checkOf(premium: '-99.99', amount: '0.1').block, isNull);
      expect(
        checkOf(premium: '-100').premiumProblem,
        MakerPremiumProblem.tooLow,
      );
      // Kept within its bounds for the figures, as the reference keeps it.
      expect(checkOf(premium: '5000').premiumPercent, 999);
      expect(checkOf(premium: '-500').premiumPercent, -99.99);
      expect(
        checkOf(premium: '5000', amount: '1000').block,
        MakerFormBlock.premiumInvalid,
      );
      expect(
        checkOf(premium: '-100', amount: '0.1').block,
        MakerFormBlock.premiumInvalid,
      );
    });

    test(
      'an empty premium is 0, « at market price »; no number is refused',
      () {
        final empty = checkOf();
        expect(empty.premiumPercent, 0);
        expect(empty.request?.premium.percent, 0);
        expect(checkOf(premium: '-').block, MakerFormBlock.premiumNotANumber);
        expect(checkOf(premium: 'abc').block, MakerFormBlock.premiumNotANumber);
        expect(checkOf(premium: '-').premiumPercent, 0);
      },
    );

    test(
      'the payment methods\' text: more than 50 UTF-16 units is refused',
      () {
        final fifty = ['x' * 50];
        expect(checkOf(methods: fifty).badPaymentMethod, isFalse);
        expect(checkOf(methods: fifty).block, isNull);
        expect(checkOf(methods: ['x' * 25, 'y' * 25]).badPaymentMethod, isTrue);
        expect(
          checkOf(methods: ['x' * 51]).block,
          MakerFormBlock.badPaymentMethod,
        );
        // An emoji counts two units, as the reference's `length`.
        expect(
          checkOf(
            methods: [
              chars([0x1F402]) * 26,
            ],
          ).badPaymentMethod,
          isTrue,
        );
      },
    );

    group('the reasons, in the reference\'s order', () {
      test('one by one', () {
        expect(
          checkOf(loaded: false).block,
          MakerFormBlock.loadingCoordinators,
        );
        expect(
          checkOf(market: const MakerFormLimitsLoading()).block,
          MakerFormBlock.priceNotSynchronized,
        );
        expect(
          checkOf(market: const MakerFormLimitsUnreadable()).block,
          MakerFormBlock.limitsUnavailable,
        );
        // A currency the coordinator gives no price for.
        expect(
          checkOf(currency: gbp).block,
          MakerFormBlock.priceNotSynchronized,
        );
        expect(checkOf(type: null).block, MakerFormBlock.noSide);
        expect(
          checkOf(type: OrderType.sell).block,
          MakerFormBlock.sellComingLater,
        );
        expect(checkOf(amount: '5').block, MakerFormBlock.amountOutsideLimits);
        expect(checkOf(amount: '-5').block, MakerFormBlock.amountOutsideLimits);
        expect(
          checkOf(methods: ['x' * 51]).block,
          MakerFormBlock.badPaymentMethod,
        );
        expect(checkOf(amount: '').block, MakerFormBlock.noAmount);
        expect(checkOf(amount: 'abc').block, MakerFormBlock.noAmount);
        expect(checkOf(amount: '0').block, MakerFormBlock.amountNotPositive);
        expect(
          checkOf(premium: '1000', amount: '1000').block,
          MakerFormBlock.premiumInvalid,
        );
        expect(checkOf(premium: '-').block, MakerFormBlock.premiumNotANumber);
        expect(checkOf(methods: []).block, MakerFormBlock.noPaymentMethod);
        // What the package refuses although every rule passed: a method no one would see.
        expect(
          checkOf(methods: [char(0x200B)]).block,
          MakerFormBlock.formIncorrect,
        );
      });

      test('the first that applies wins', () {
        final everything = checkOf(
          type: null,
          amount: '',
          methods: [],
          premium: '-',
          loaded: false,
          market: const MakerFormLimitsUnreadable(),
        );
        expect(everything.block, MakerFormBlock.loadingCoordinators);
        expect(
          checkOf(
            type: null,
            amount: '',
            methods: [],
            premium: '-',
            market: const MakerFormLimitsUnreadable(),
          ).block,
          MakerFormBlock.limitsUnavailable,
        );
        expect(
          checkOf(type: null, amount: '5', methods: [], premium: '-').block,
          MakerFormBlock.noSide,
        );
        expect(
          checkOf(amount: '5', methods: ['x' * 51], premium: '-').block,
          MakerFormBlock.amountOutsideLimits,
        );
        expect(
          checkOf(amount: '', methods: ['x' * 51], premium: '-').block,
          MakerFormBlock.badPaymentMethod,
        );
        expect(
          checkOf(amount: '', methods: [], premium: '1000').block,
          MakerFormBlock.noAmount,
        );
        expect(
          checkOf(amount: '0', methods: [], premium: '1000').block,
          MakerFormBlock.amountNotPositive,
        );
        expect(
          checkOf(amount: '1000', methods: [], premium: '1000').block,
          MakerFormBlock.premiumInvalid,
        );
        expect(
          checkOf(methods: [], premium: '-').block,
          MakerFormBlock.premiumNotANumber,
        );
      });

      test('no request while a reason applies', () {
        for (final check in [
          checkOf(type: null),
          checkOf(amount: ''),
          checkOf(methods: []),
          checkOf(premium: '1000'),
          checkOf(market: const MakerFormLimitsUnreadable()),
        ]) {
          expect(check.request, isNull);
        }
      });
    });

    test(
      'a price the make\'s terms would refuse gives no figure, and no request',
      () async {
        final tiny = await limitsAt({2: 0.00001});
        final check = checkOf(market: MakerFormLimitsRead(tiny));
        expect(check.price, isNull);
        expect(check.rate, isNull);
        expect(check.estimatedBond, isNull);
        expect(check.block, MakerFormBlock.priceNotSynchronized);
        final huge = await limitsAt({2: 2e15});
        expect(
          checkOf(market: MakerFormLimitsRead(huge)).block,
          MakerFormBlock.priceNotSynchronized,
        );
      },
    );
  });

  group('the coordinator\'s price against the Bull wallet\'s', () {
    MakePriceCheck checkOf(double coordinator, P2pWalletBitcoinRate wallet) =>
        MakePriceCheck.of(
          currency: eur,
          coordinatorPrice: coordinator,
          wallet: wallet,
        );

    MakePriceCompared compared(double coordinator, double wallet) =>
        switch (checkOf(coordinator, P2pWalletRateRead(wallet))) {
          final MakePriceCompared compared => compared,
          final other => throw StateError('$other'),
        };

    test('the threshold is the payment rule\'s, 10 %', () {
      expect(TradeTolerances.walletRateGap, 0.10);
    });

    test('within 10 % either way: information, no warning', () {
      for (final coordinator in [100000.0, 90000.0, 110000.0, 95000.0]) {
        final check = compared(coordinator, 100000);
        expect(check.side, MakePriceSide.within, reason: '$coordinator');
        expect(check.warns, isFalse);
      }
      expect(compared(100000, 100000).gapHundredths, BigInt.zero);
      expect(compared(90000, 100000).gapHundredths, BigInt.from(-1000));
      expect(compared(110000, 100000).gapHundredths, BigInt.from(1000));
      expect(compared(91711.15, 91711.15).walletPrice, 91711.15);
      expect(compared(91711.15, 90000).coordinatorPrice, 91711.15);
    });

    test(
      'beyond 10 % below: the warning of a bond too large, the gap shown beyond 10.00 %',
      () {
        final check = compared(89999.99, 100000);
        expect(check.side, MakePriceSide.below);
        expect(check.warns, isTrue);
        expect(check.gapHundredths, BigInt.from(-1001));
        // The reviewer's scenario: a price ten times too low.
        expect(compared(9171.115, 91711.15).side, MakePriceSide.below);
      },
    );

    test('beyond 10 % above: the warning of fewer sats', () {
      final check = compared(110000.01, 100000);
      expect(check.side, MakePriceSide.above);
      expect(check.warns, isTrue);
      expect(check.gapHundredths, BigInt.from(1001));
    });

    test(
      'a currency the Bull wallet does not price: no figure, no warning',
      () {
        final check = checkOf(9171.115, const P2pWalletRateNotPriced());
        expect(check, isA<MakePriceNotPriced>());
        expect(check, isNot(isA<MakePriceCompared>()));
        expect(check.warns, isFalse);
        expect(check.currency, eur);
      },
    );

    test('a price that could not be read, or is no price: unverified', () {
      expect(
        checkOf(91711.15, const P2pWalletRateUnavailable()),
        isA<MakePriceUnverified>(),
      );
      for (final price in [1e-5, 1e15, 2e300]) {
        expect(
          checkOf(91711.15, P2pWalletRateRead(price)),
          isA<MakePriceUnverified>(),
          reason: '$price',
        );
      }
    });

    test('never prints a price', () {
      expect(compared(89999.99, 100000).toString(), isNot(contains('9')));
    });
  });
}
