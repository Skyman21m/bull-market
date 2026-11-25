import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_tolerances.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart' show coordinator;

/// For a currency the Bull wallet does not price, an order made here (#237, the owner's decision of 2026-11-20; design note `docs/design/phase-3-making-an-order.md` § 3.3 bis): the contract's sats fixed at the take against its amount's sats at the rate of the creation, said only beyond the owner's threshold against the maker, both sides.
///
/// Every figure is computed by hand: 100 GBP at 50,000 GBP/BTC and a premium of 0 are 200,000 sats exactly; 10 % of them is 20,000.
void main() {
  T some<T>(T? value) => value ?? (throw StateError('missing'));

  /// The terms of a make of 100 GBP (or the range 50 to [max]) at [premium] %, bought (or [sell] sold), made at the coordinator's [createdPrice].
  MakerTerms terms({
    bool sell = false,
    double premium = 0,
    double createdPrice = 50000,
    double? max,
  }) {
    final request = some(
      MakeOrderRequest.tryCreate(
        type: sell ? OrderType.sell : OrderType.buy,
        currency: some(RobosatsCurrency.fromCode('GBP')),
        amount: max == null
            ? FixedOrderAmount(some(FiatAmount.tryCreate(100)))
            : some(
                RangeOrderAmount.tryCreate(
                  some(FiatAmount.tryCreate(50)),
                  some(FiatAmount.tryCreate(max)),
                ),
              ),
        paymentMethod: 'Revolut',
        premium: some(Premium.tryCreate(premium)),
        publicDuration: const Duration(seconds: 86340),
        escrowDuration: const Duration(seconds: 10800),
        bondSize: some(BondSize.tryCreate(3)),
      ),
    );
    return switch (MakerTerms.create(
      network: RobosatsNetwork.mainnet,
      coordinator: coordinator('temple'),
      request: request,
      createdPrice: createdPrice,
      makerFee: 0.00025,
    )) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
  }

  /// The gap against a maker of [role] when the take fixed [sats] sats for 100 GBP (or [range] of a range).
  BigInt? against(
    MakerTerms maker,
    TradeRole role,
    int sats, {
    double? range,
  }) => some(
    maker.rateGap(
      rangeAmount: range == null ? null : FiatAmount.tryCreate(range),
      tradeSatoshis: Sats.fromInt(sats),
    ),
  ).againstFor(role);

  test('the threshold is the owner\'s one, 10 %', () {
    expect(TradeTolerances.walletRateGap, 0.10);
  });

  group('a maker buyer: fewer sats is against it', () {
    final maker = terms();
    test(
      'taken at 56,000 GBP/BTC, 178,571 sats: 10.7145 % fewer, said 10.72',
      () {
        expect(against(maker, TradeRole.buyer, 178571), BigInt.from(1072));
      },
    );
    test('179,999 sats, just beyond: 10.0005 %, said 10.01, never 10.00', () {
      expect(against(maker, TradeRole.buyer, 179999), BigInt.from(1001));
    });
    test('180,000 sats, exactly 10 % fewer: nothing', () {
      expect(against(maker, TradeRole.buyer, 180000), isNull);
    });
    test('taken at 55,500, 180,180 sats, 9.91 % fewer: nothing', () {
      expect(against(maker, TradeRole.buyer, 180180), isNull);
    });
    test('200,000 sats, the very rate: nothing', () {
      expect(against(maker, TradeRole.buyer, 200000), isNull);
    });
    test('taken at 45,000, 222,222 sats, more for the buyer: nothing', () {
      expect(against(maker, TradeRole.buyer, 222222), isNull);
    });
    test('a hundred times more sats, in its favour: nothing', () {
      expect(against(maker, TradeRole.buyer, 20000000), isNull);
    });
  });

  group('a maker seller: more sats to lock is against it', () {
    final maker = terms(sell: true);
    test(
      'taken at 45,000 GBP/BTC, 222,222 sats: 11.111 % more, said 11.12',
      () {
        expect(against(maker, TradeRole.seller, 222222), BigInt.from(1112));
      },
    );
    test('220,001 sats, just beyond: 10.0005 %, said 10.01', () {
      expect(against(maker, TradeRole.seller, 220001), BigInt.from(1001));
    });
    test('220,000 sats, exactly 10 % more: nothing', () {
      expect(against(maker, TradeRole.seller, 220000), isNull);
    });
    test('taken at 45,500, 219,780 sats, 9.89 % more: nothing', () {
      expect(against(maker, TradeRole.seller, 219780), isNull);
    });
    test('taken at 56,000, 178,571 sats, fewer to lock: nothing', () {
      expect(against(maker, TradeRole.seller, 178571), isNull);
    });
  });

  test(
    'the premium of the creation counts: at +5 % the creation\'s rate is 52,500, 190,476.19… sats; 171,428 sats is just beyond 10 % fewer (10.0002 %, said 10.01), 171,429 just within',
    () {
      final maker = terms(premium: 5);
      expect(against(maker, TradeRole.buyer, 171428), BigInt.from(1001));
      expect(against(maker, TradeRole.buyer, 171429), isNull);
    },
  );

  test(
    'a range: the amount its take chose, 120 GBP of 50 to 200, 240,000 sats at the creation\'s rate; 215,999 sats is against a buyer, 216,000 not',
    () {
      final maker = terms(max: 200);
      expect(
        against(maker, TradeRole.buyer, 215999, range: 120),
        BigInt.from(1001),
      );
      expect(against(maker, TradeRole.buyer, 216000, range: 120), isNull);
    },
  );

  test('a figure never says an amount nor a rate', () {
    final gap = some(
      terms().rateGap(rangeAmount: null, tradeSatoshis: Sats.fromInt(178571)),
    );
    expect(gap.toString(), 'TradeRateGap');
  });
}
