import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/taken_price_check.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:test/test.dart';

import 'support/prepared_takes.dart';

/// The owner's payment rule on the order page, before the take (#249, slice 4; design note `docs/design/phase-3-taken-order-price-check.md` § 3, first row, § 4, § 8 point 4; option B decided on 2026-11-24): the coordinator's price without the premium, from the terms the take is sent on, compared with the Bull wallet's by `MakePriceCheck` on the taker's own side, and what the page shows of it.
///
/// Every price is chosen so that the figures are exact: 100,000 USD/BTC for the Bull wallet, the bounds at a hundredth of a percent around it.
void main() {
  T some<T>(T? value) => value ?? (throw StateError('missing'));

  final usd = some(RobosatsCurrency.fromCode('USD'));

  /// The terms of a take as stored (version 1): a seller takes a buy order, a buyer a sell order; [bookPrice] the read's price, premium included.
  TradeTerms<TakenSide> taken({
    TradeRole role = TradeRole.buyer,
    double premium = 3.5,
    required double bookPrice,
    bool range = false,
    int? explicitSatoshis,
  }) => switch (TradeTerms.restore(
    TradeTermsRecord(
      version: 1,
      network: 'mainnet',
      coordinatorAlias: 'temple',
      orderId: 42,
      role: role.name,
      type: role == TradeRole.seller ? 0 : 1,
      currencyId: usd.id,
      amount: 100,
      isRange: range,
      premiumPercent: premium,
      explicitSatoshis: explicitSatoshis,
      bondSizePercent: 3,
      escrowSeconds: 10800,
      bookPrice: bookPrice,
      takerFee: 0.00175,
    ),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  /// The check the page draws for [terms] against a Bull wallet's price of 100,000 USD/BTC (or [wallet]).
  MakePriceCheck check(
    TradeTerms<TakenSide> terms, {
    P2pWalletBitcoinRate? wallet,
  }) => MakePriceCheck.of(
    currency: terms.currency,
    coordinatorPrice: some(TakenPriceCheck.coordinatorPrice(terms)),
    wallet: wallet ?? P2pWalletRateRead(100000),
  );

  TakenPriceShown shown(TradeTerms<TakenSide> terms) =>
      TakenPriceCheck.shownOf(check(terms), terms.role);

  BigInt gapOf(TradeTerms<TakenSide> terms) => switch (check(terms)) {
    final MakePriceCompared compared => compared.gapHundredths,
    final other => throw StateError('not compared: $other'),
  };

  group('the coordinator\'s price without the premium, from the terms', () {
    test('the read\'s price over 1 plus the premium, exactly', () {
      // 113,850 = 110,000 × 1.035; 113,860.35 = 110,010 × 1.035.
      expect(
        TakenPriceCheck.coordinatorPrice(taken(bookPrice: 113850)),
        110000,
      );
      expect(
        TakenPriceCheck.coordinatorPrice(taken(bookPrice: 113860.35)),
        110010,
      );
    });

    test(
      'a negative premium: the price is above the read\'s (88,000 at −12 % is 100,000)',
      () {
        final terms = taken(premium: -12, bookPrice: 88000);
        expect(TakenPriceCheck.coordinatorPrice(terms), 100000);
        // Compared without the premium, within the threshold for both roles; with it, −12 % would warn.
        expect(shown(terms), TakenPriceShown.nothing);
        expect(
          shown(taken(role: TradeRole.seller, premium: -12, bookPrice: 88000)),
          TakenPriceShown.nothing,
        );
      },
    );

    test(
      'a premium of +12 %: 112,000 is 100,000, nothing shown (the price with the premium would warn a buyer)',
      () {
        final terms = taken(premium: 12, bookPrice: 112000);
        expect(TakenPriceCheck.coordinatorPrice(terms), 100000);
        expect(shown(terms), TakenPriceShown.nothing);
      },
    );

    test(
      'a premium of −100 %, which `Premium.tryCreate` accepts: no price, never a division',
      () {
        expect(
          TakenPriceCheck.coordinatorPrice(
            taken(premium: -100, bookPrice: 1000),
          ),
          isNull,
        );
      },
    );

    test('a price outside the bounds of a price gives none', () {
      expect(
        TakenPriceCheck.coordinatorPrice(taken(premium: 0, bookPrice: 1e-5)),
        isNull,
      );
      expect(
        TakenPriceCheck.coordinatorPrice(taken(premium: 0, bookPrice: 2e15)),
        isNull,
      );
      // Within the bounds once the premium is taken off: 1e15 at +100 % is 5e14.
      expect(
        TakenPriceCheck.coordinatorPrice(taken(premium: 100, bookPrice: 9e14)),
        4.5e14,
      );
    });

    test(
      'a read of a range: the price of the read, whatever the amount taken (100 EUR of 50 to 200)',
      () async {
        // 200 EUR for 213,800 sats at +2 %: 200 / 0.002138 / 1.02.
        final read = await preparedTake(
          range: true,
          amount: some(TakeAmount.tryCreate(100)),
          changes: {'satoshis_now': 213800},
        );
        expect(
          TakenPriceCheck.coordinatorPrice(read.terms),
          closeTo(200 / 0.002138 / 1.02, 1e-6),
        );
      },
    );

    test(
      'a read of an order priced in sats: the coordinator\'s `premium_now` taken off, not the order\'s premium',
      () async {
        final read = await preparedTake(
          changes: {
            'is_explicit': true,
            'satoshis': 106900,
            'premium': null,
            'premium_now': 15.0,
          },
        );
        expect(read.terms.premium.percent, 15);
        expect(
          TakenPriceCheck.coordinatorPrice(read.terms),
          closeTo(100 / 0.001069 / 1.15, 1e-6),
        );
      },
    );

    test(
      'never the book\'s price: a read whose `price_now` says otherwise is compared on its sats',
      () async {
        final read = await preparedTake(changes: {'price_now': 50000.0});
        expect(
          TakenPriceCheck.coordinatorPrice(read.terms),
          closeTo(100 / 0.001069 / 1.02, 1e-6),
        );
      },
    );
  });

  group(
    'the premium of an order priced in sats, read by the robot, against the one shown',
    () {
      Premium premium(double percent) => some(Premium.tryCreate(percent));

      test('an order priced against the market: never said moved here', () {
        expect(
          TakenPriceCheck.premiumMovedFrom(
            taken(premium: 39.55, bookPrice: 100000),
            premium(3.5),
          ),
          isFalse,
        );
      });

      test(
        'within the trade\'s price tolerance of 2 %, (1 + premium read) ÷ (1 + premium shown): not moved; beyond: moved',
        () {
          TradeTerms<TakenSide> read(double percent) => taken(
            premium: percent,
            bookPrice: 100000,
            explicitSatoshis: 100000,
          );
          // 102 ÷ 100 = 1.02 exactly: within.
          expect(
            TakenPriceCheck.premiumMovedFrom(read(2), premium(0)),
            isFalse,
          );
          expect(
            TakenPriceCheck.premiumMovedFrom(read(2.01), premium(0)),
            isTrue,
          );
          // 98 ÷ 100: within; 97.99 ÷ 100: beyond.
          expect(
            TakenPriceCheck.premiumMovedFrom(read(-2), premium(0)),
            isFalse,
          );
          expect(
            TakenPriceCheck.premiumMovedFrom(read(-2.01), premium(0)),
            isTrue,
          );
          // The same premium, and the market moving a little: not moved.
          expect(
            TakenPriceCheck.premiumMovedFrom(read(3.5), premium(3.5)),
            isFalse,
          );
          expect(
            TakenPriceCheck.premiumMovedFrom(read(4.2), premium(3.5)),
            isFalse,
          );
          // The security review's case: 3.5 % shown, 39.55 % read.
          expect(
            TakenPriceCheck.premiumMovedFrom(read(39.55), premium(3.5)),
            isTrue,
          );
          // A premium of −100 % on one side: moved when they differ.
          expect(
            TakenPriceCheck.premiumMovedFrom(read(-100), premium(3.5)),
            isTrue,
          );
          expect(
            TakenPriceCheck.premiumMovedFrom(read(-100), premium(-100)),
            isFalse,
          );
        },
      );
    },
  );

  group('the taker\'s side', () {
    test('a buyer is warned as a maker buyer, a seller as a maker seller', () {
      expect(TakenPriceCheck.sideOf(TradeRole.buyer), OrderType.buy);
      expect(TakenPriceCheck.sideOf(TradeRole.seller), OrderType.sell);
    });

    test(
      'the taker of a buy order is a seller: a price above the Bull wallet\'s does not warn it',
      () {
        final terms = taken(role: TradeRole.seller, bookPrice: 124200);
        expect(terms.type, OrderType.buy);
        // Given the order's type instead (a buy order), it would warn.
        expect(check(terms).warnsFor(terms.type), isTrue);
        expect(shown(terms), TakenPriceShown.nothing);
      },
    );
  });

  group('the bounds, at a hundredth of a percent', () {
    for (final (name, role, book, gap, expected) in [
      // 110,000 × 1.035: +10.00 %, within.
      ('+10.00 %', TradeRole.buyer, 113850.0, 1000, TakenPriceShown.nothing),
      // 110,010 × 1.035: +10.01 %, against a buyer.
      ('+10.01 %', TradeRole.buyer, 113860.35, 1001, TakenPriceShown.against),
      // 110,001 × 1.035: +10.001 %, shown +10.01 %, rounded away from zero.
      ('+10.001 %', TradeRole.buyer, 113851.035, 1001, TakenPriceShown.against),
      ('+10.01 %', TradeRole.seller, 113860.35, 1001, TakenPriceShown.nothing),
      // 90,000 × 1.035: −10.00 %, within.
      ('−10.00 %', TradeRole.buyer, 93150.0, -1000, TakenPriceShown.nothing),
      ('−10.00 %', TradeRole.seller, 93150.0, -1000, TakenPriceShown.nothing),
      // 89,990 × 1.035: −10.01 %.
      ('−10.01 %', TradeRole.buyer, 93139.65, -1001, TakenPriceShown.farBelow),
      ('−10.01 %', TradeRole.seller, 93139.65, -1001, TakenPriceShown.against),
      // The owner's example of § 3: a price 20 % too high (+20.00 %), and ten times too low.
      ('+20.00 %', TradeRole.buyer, 124200.0, 2000, TakenPriceShown.against),
      ('−90.00 %', TradeRole.buyer, 10350.0, -9000, TakenPriceShown.farBelow),
      ('−90.00 %', TradeRole.seller, 10350.0, -9000, TakenPriceShown.against),
    ]) {
      test('a taker ${role.name} at $name: ${expected.name}', () {
        final terms = taken(role: role, bookPrice: book);
        expect(gapOf(terms), BigInt.from(gap));
        expect(shown(terms), expected);
      });
    }
  });

  group('what the page shows', () {
    final terms = taken(bookPrice: 103500);

    test('nothing before a read', () {
      expect(
        TakenPriceCheck.shownOf(null, TradeRole.buyer),
        TakenPriceShown.nothing,
      );
    });

    test(
      '« Price not checked » when the Bull wallet\'s price is unreadable',
      () {
        for (final role in TradeRole.values) {
          expect(
            TakenPriceCheck.shownOf(
              check(terms, wallet: const P2pWalletRateUnavailable()),
              role,
            ),
            TakenPriceShown.unverified,
          );
        }
      },
    );

    test('« not quoted » for a currency the Bull wallet does not price', () {
      for (final role in TradeRole.values) {
        expect(
          TakenPriceCheck.shownOf(
            check(terms, wallet: const P2pWalletRateNotPriced()),
            role,
          ),
          TakenPriceShown.notPriced,
        );
      }
    });
  });
}
