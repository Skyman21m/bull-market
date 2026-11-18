import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/exact_ratio.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_tolerances.dart';
import 'package:p2p/src/domain/trade/wallet_rate_check.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart' show coordinator;

/// The owner's payment rule of 2026-11-17 for the maker bond (#180, design note `docs/design/phase-3-making-an-order.md` § 3.3): the bond asked against the bond the order implies at the wallet's own price, one threshold of 10 % on the side that costs, never a refusal.
///
/// Every figure is computed by hand (exact rationals, Python's `fractions`, written out in the comments).
void main() {
  T some<T>(T? value) => value ?? (throw StateError('missing'));

  /// The terms of a make of [amount] (or the range [min] to [amount]) in [code] at [premium] %, a bond of [bond] %, the coordinator's price of the creation [createdPrice].
  MakerTerms terms({
    String code = 'USD',
    double amount = 100,
    double? min,
    double premium = 3.5,
    double bond = 3,
    double createdPrice = 71657,
    double makerFee = 0.00025,
  }) {
    final fiat = some(FiatAmount.tryCreate(amount));
    final request = some(
      MakeOrderRequest.tryCreate(
        type: OrderType.buy,
        currency: some(RobosatsCurrency.fromCode(code)),
        amount: min == null
            ? FixedOrderAmount(fiat)
            : some(
                RangeOrderAmount.tryCreate(
                  some(FiatAmount.tryCreate(min)),
                  fiat,
                ),
              ),
        paymentMethod: 'Revolut',
        premium: some(Premium.tryCreate(premium)),
        publicDuration: const Duration(seconds: 86340),
        escrowDuration: const Duration(seconds: 10800),
        bondSize: some(BondSize.tryCreate(bond)),
      ),
    );
    return switch (MakerTerms.create(
      network: RobosatsNetwork.mainnet,
      coordinator: coordinator('temple'),
      request: request,
      createdPrice: createdPrice,
      makerFee: makerFee,
    )) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
  }

  WalletRateCheck checkOf(
    MakerTerms terms,
    int asked, [
    P2pWalletBitcoinRate? wallet,
  ]) => WalletRateCheck.ofMakerBond(
    terms,
    asked: Sats.fromInt(asked),
    wallet: wallet ?? P2pWalletRateRead(71657),
  );

  /// [checkOf], which the test expects to be a comparison.
  WalletRateCompared check(
    MakerTerms terms,
    int asked, [
    P2pWalletBitcoinRate? wallet,
  ]) => switch (checkOf(terms, asked, wallet)) {
    final WalletRateCompared compared => compared,
    final other => throw StateError('not compared: $other'),
  };

  group(
    'what a maker buyer receives at 9, from `last_satoshis`: `round(last − last × fee)`, a half to the even one as Python\'s `round` (`Logics.payout_amount`, `api/logics.py:650-669`)',
    () {
      test(
        'the figures of the captures: 90,000 → 89,978; 106,900 → 106,873',
        () {
          expect(terms().payoutAt(Sats.fromInt(90000)), Sats.fromInt(89978));
          expect(terms().payoutAt(Sats.fromInt(106900)), Sats.fromInt(106873));
        },
      );

      test('a half goes to the even one: 999.5 → 1,000, 2,998.5 → 2,998', () {
        final half = terms(makerFee: 0.0005);
        expect(half.payoutAt(Sats.fromInt(1000)), Sats.fromInt(1000));
        expect(half.payoutAt(Sats.fromInt(3000)), Sats.fromInt(2998));
      });
    },
  );

  test('the threshold is the owner\'s, 10 %', () {
    expect(TradeTolerances.walletRateGap, 0.10);
  });

  group(
    'the owner\'s example: 71,657 USD, a premium of +3.5 %, 100 USD, a bond of 3 %',
    () {
      // 71,657 × 1.035 = 74,164.995 USD/BTC; 100 USD = 134,834.4997… sats (134,834 truncated as the coordinator does); 3 % = 4,045.03499… sats; 1.1 × that = 4,449.538…
      final made = terms();

      test('4,045 sats expected, at the wallet\'s price', () {
        final rate = check(made, 4045);
        expect(rate.expected, Sats.fromInt(4045));
        expect(rate, isA<WalletRateAtWallet>());
        expect(rate.price, 71657);
        expect(rate.currency.code, 'USD');
        expect(rate.warns, isFalse);
        // −0.0865 hundredths of a percent, away from zero: −0.01 %.
        expect(rate.gapHundredths, BigInt.from(-1));
      });

      test('4,449 sats: shown, no warning (+9.99 %)', () {
        final rate = check(made, 4449);
        expect(rate.warns, isFalse);
        expect(rate.gapHundredths, BigInt.from(999));
      });

      test('4,450 sats: the warning (+10.02 %), the first sat above 10 %', () {
        final rate = check(made, 4450);
        expect(rate.warns, isTrue);
        expect(rate.gapHundredths, BigInt.from(1002));
        expect(rate.asked, Sats.fromInt(4450));
        expect(rate.expected, Sats.fromInt(4045));
      });

      test(
        'the coordinator\'s own truncations give the same bound: int(134,834 × 3 / 100) = 4,045, × 1.1 = 4,449.5',
        () {
          // The exact bond (4,045.035) is what the rule uses; truncated as the coordinator does, 4,045, it would warn from 4,450 too.
          final bond = some(made.bondAtPrice(71657));
          expect(bond.floor(), BigInt.from(4045));
          expect(
            bond * ExactRatio.integer(11) / ExactRatio.integer(10) >
                ExactRatio.integer(4449),
            isTrue,
          );
          expect(
            bond * ExactRatio.integer(11) / ExactRatio.integer(10) <
                ExactRatio.integer(4450),
            isTrue,
          );
        },
      );
    },
  );

  group('the threshold, at it and one sat past it', () {
    // 100 USD at 100,000 with no premium: 100,000 sats exactly, a bond of 3,000, the threshold 3,300 exactly.
    final made = terms(premium: 0);

    test('3,300 sats, 10 % exactly: no warning, shown as +10.00 %', () {
      final rate = check(made, 3300, P2pWalletRateRead(100000));
      expect(rate.expected, Sats.fromInt(3000));
      expect(rate.warns, isFalse);
      expect(rate.gapHundredths, BigInt.from(1000));
    });

    test('3,000 sats, the bond expected exactly: a gap of 0, no warning', () {
      final rate = check(made, 3000, P2pWalletRateRead(100000));
      expect(rate.gapHundredths, BigInt.zero);
      expect(rate.warns, isFalse);
    });

    test('3,301 sats: the warning, +10.04 %', () {
      final rate = check(made, 3301, P2pWalletRateRead(100000));
      expect(rate.warns, isTrue);
      // 10.0333…, away from zero.
      expect(rate.gapHundredths, BigInt.from(1004));
    });
  });

  test(
    'a favourable gap is shown without a warning, however large: the side that costs only',
    () {
      final made = terms(premium: 0);
      final rate = check(made, 2000, P2pWalletRateRead(100000));
      expect(rate.warns, isFalse);
      expect(rate.gapHundredths, BigInt.from(-3334));
      final tiny = check(made, 1, P2pWalletRateRead(100000));
      expect(tiny.warns, isFalse);
    },
  );

  test('a negative premium: −5 % lowers the rate, so more sats are expected', () {
    // 100,000 × 0.95 = 95,000; 100 USD = 105,263.157… sats; 3 % = 3,157.894…; × 1.1 = 3,473.68…
    final made = terms(premium: -5);
    final at = check(made, 3473, P2pWalletRateRead(100000));
    expect(at.expected, Sats.fromInt(3157));
    expect(at.warns, isFalse);
    expect(check(made, 3474, P2pWalletRateRead(100000)).warns, isTrue);
  });

  test('a range: the bond of its maximum, as the coordinator\'s', () {
    // 50 to 200 USD: the bond of 200 USD, 8,090.0699… sats; × 1.1 = 8,899.07…
    final made = terms(min: 50, amount: 200);
    final rate = check(made, 8899);
    expect(rate.expected, Sats.fromInt(8090));
    expect(rate.warns, isFalse);
    expect(check(made, 8900).warns, isTrue);
  });

  group('the wallet\'s price is the reference whenever it is read', () {
    test(
      'never the price of the creation then: a price ten times too low at the make makes a bond ten times too large, which the coordinator\'s estimate accepts and the rule warns of',
      () {
        // The coordinator announced 7,165.7 for 71,657: its bond, 40,450 sats, agrees with its own estimate.
        final lied = terms(createdPrice: 7165.7);
        expect(lied.bondAgrees(Sats.fromInt(40450)), isTrue);
        final rate = check(lied, 40450);
        expect(rate, isA<WalletRateAtWallet>());
        expect(rate.price, 71657);
        expect(rate.expected, Sats.fromInt(4045));
        expect(rate.warns, isTrue);
      },
    );

    test(
      'a coordinator whose price moved from the wallet\'s: the bond compared with the wallet\'s price, not the creation\'s',
      () {
        // The creation at 71,657, the wallet at 79,000: 3,669.05… expected, 4,035.95… the threshold.
        final made = terms();
        final rate = check(made, 4045, P2pWalletRateRead(79000));
        expect(rate.expected, Sats.fromInt(3669));
        expect(rate.warns, isTrue);
        expect(check(made, 4035, P2pWalletRateRead(79000)).warns, isFalse);
      },
    );
  });

  group(
    'a currency the wallet does not price: nothing compared, no figure (the owner\'s decision of 2026-11-17 in the evening)',
    () {
      test(
        'the reviewer\'s scenario: a price of the creation ten times too low in GBP, a bond ten times too large: nothing reassuring, no warning to compute, the price of the creation never the reference',
        () {
          // 100 GBP announced at 6,000 for about 60,000: 48,309 sats of bond, which the coordinator's estimate accepts.
          final lied = terms(code: 'GBP', createdPrice: 6000);
          expect(lied.bondAgrees(Sats.fromInt(48309)), isTrue);
          for (final asked in [48309, 4830, 1]) {
            final rate = checkOf(lied, asked, const P2pWalletRateNotPriced());
            expect(rate, isA<WalletRateNotPriced>(), reason: '$asked');
            expect(rate, isNot(isA<WalletRateCompared>()));
            expect(rate.asked, Sats.fromInt(asked));
            expect(rate.currency.code, 'GBP');
            expect(rate.warns, isFalse);
          }
        },
      );

      test('distinct from a price that could not be read', () {
        final made = terms(code: 'GBP', createdPrice: 60000);
        expect(
          checkOf(made, 4830, const P2pWalletRateNotPriced()),
          isNot(isA<WalletRateUnverified>()),
        );
        expect(
          checkOf(made, 4830, const P2pWalletRateUnavailable()),
          isNot(isA<WalletRateNotPriced>()),
        );
      });
    },
  );

  group(
    'the wallet prices the currency but its price could not be read: nothing compared, the creation\'s price never cited (review of #180, C1)',
    () {
      test(
        'the reviewer\'s scenario: a price announced ten times too low, then the price service down: no reassuring comparison, the bond unverified',
        () {
          final lied = terms(createdPrice: 7165.7);
          final rate = checkOf(lied, 40450, const P2pWalletRateUnavailable());
          expect(rate, isA<WalletRateUnverified>());
          expect(rate, isNot(isA<WalletRateCompared>()));
          expect(rate.asked, Sats.fromInt(40450));
          expect(rate.currency.code, 'USD');
          // No red line: there is nothing to compare; the screen says « rate not checked ».
          expect(rate.warns, isFalse);
        },
      );

      test(
        'a price of the wallet outside the bounds of a price: unverified as well, never the creation\'s',
        () {
          final made = terms();
          for (final price in [1e-5, 1e15, 2e300]) {
            expect(
              checkOf(made, 4045, P2pWalletRateRead(price)),
              isA<WalletRateUnverified>(),
              reason: '$price',
            );
          }
          // At the bounds themselves, the wallet's price is taken.
          expect(
            checkOf(made, 4045, P2pWalletRateRead(0.0001)),
            isA<WalletRateAtWallet>(),
          );
        },
      );
    },
  );

  test(
    'the bond at the price of the creation is the terms\' own expected bond',
    () {
      final made = terms();
      expect(some(made.bondAtPrice(71657)).toDouble(), made.expectedBond);
      expect(made.bondAtPrice(double.nan), isNull);
      expect(made.bondAtPrice(double.infinity), isNull);
      expect(made.bondAtPrice(0), isNull);
      expect(made.bondAtPrice(-1), isNull);
    },
  );

  test('a port\'s price is a figure above zero', () {
    expect(() => P2pWalletRateRead(0), throwsArgumentError);
    expect(() => P2pWalletRateRead(-1), throwsArgumentError);
    expect(() => P2pWalletRateRead(double.nan), throwsArgumentError);
    expect(() => P2pWalletRateRead(double.infinity), throwsArgumentError);
  });

  test('its text names no amount nor price', () {
    final text = check(terms(), 4450).toString();
    expect(text, 'WalletRateAtWallet(warns)');
    expect(
      checkOf(terms(), 4045, const P2pWalletRateUnavailable()).toString(),
      'WalletRateUnverified',
    );
    expect(P2pWalletRateRead(71657).toString(), 'P2pWalletRateRead');
  });

  group(
    'on a maker buyer\'s side (#182): the sats received for 100 USD at 71,657 USD/BTC and +3.5 %, fewer by more than 10 % warns',
    () {
      // 100 USD = 134,834.4997… sats at 74,164.995 USD/BTC; 0.9 × that = 121,351.0497…
      final made = terms();
      final hundred = some(FiatAmount.tryCreate(100));
      WalletRateCheck received(int sats, [P2pWalletBitcoinRate? wallet]) =>
          WalletRateCheck.ofMakerPayout(
            made,
            amount: hundred,
            received: Sats.fromInt(sats),
            wallet: wallet ?? P2pWalletRateRead(71657),
          );
      WalletRateCompared compared(int sats) => switch (received(sats)) {
        final WalletRateCompared rate => rate,
        final other => throw StateError('not compared: $other'),
      };

      test('134,834 sats expected, the side the one that receives', () {
        final rate = compared(134834);
        expect(rate.expected, Sats.fromInt(134834));
        expect(rate.side, WalletRateSide.receives);
        expect(rate.warns, isFalse);
        expect(rate.gapHundredths, BigInt.from(-1));
      });

      test('121,352 sats, just above 90 %: no warning, −10.00 %', () {
        final rate = compared(121352);
        expect(rate.warns, isFalse);
        expect(rate.gapHundredths, BigInt.from(-1000));
      });

      test('121,351 sats, just below 90 %: the warning, −10.01 %', () {
        final rate = compared(121351);
        expect(rate.warns, isTrue);
        expect(rate.gapHundredths, BigInt.from(-1001));
      });

      test(
        'more sats than expected, by any gap, is in the buyer\'s favour: never a warning',
        () {
          expect(compared(200000).warns, isFalse);
          expect(compared(200000).gapHundredths > BigInt.zero, isTrue);
          // The bond's side would warn there.
          expect(check(made, 200000).warns, isTrue);
        },
      );

      test(
        'a currency the wallet does not price, a price not read: nothing compared',
        () {
          expect(
            received(1, const P2pWalletRateNotPriced()),
            isA<WalletRateNotPriced>(),
          );
          expect(
            received(1, const P2pWalletRateUnavailable()),
            isA<WalletRateUnverified>(),
          );
          // A price no coordinator could give (not below `MakerTerms.maxCreatedPrice`).
          expect(
            received(1, P2pWalletRateRead(1e16)),
            isA<WalletRateUnverified>(),
          );
          expect(received(1, const P2pWalletRateNotPriced()).warns, isFalse);
        },
      );
    },
  );
}
