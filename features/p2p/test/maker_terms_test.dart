import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/exact_ratio.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_tolerances.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/testing/bolt11_test_invoice.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';
import 'support/trade_orders.dart';

/// A maker's terms (#177; design note `docs/design/phase-3-making-an-order.md` § 3.2, § 3.3): what the maker asked, the maker bond's check and the wallet's ceilings for a maker, the gap from the rate of the creation, and the sealed side of `TradeTerms`.
///
/// Every money rule is checked at its bounds with figures computed by hand, and against a simulation of the reference's own arithmetic (`api/logics.py`, commit ff1998c): Python floats are IEEE doubles as Dart's are, and its decimals are simulated with integers.
void main() {
  const testnet = RobosatsNetwork.testnet;
  final temple = coordinator('temple');
  final usd = _some(RobosatsCurrency.fromId(1));

  FiatAmount fiat(double value) => _some(FiatAmount.tryCreate(value));

  MakeOrderRequest request({
    OrderType type = OrderType.buy,
    OrderAmount? amount,
    double premium = 0,
    double bond = 3,
    String paymentMethod = 'Revolut',
    int publicSeconds = 86340,
    int escrowSeconds = 10800,
    String? description,
  }) => _some(
    MakeOrderRequest.tryCreate(
      type: type,
      currency: usd,
      amount: amount ?? FixedOrderAmount(fiat(100)),
      paymentMethod: paymentMethod,
      premium: _some(Premium.tryCreate(premium)),
      publicDuration: Duration(seconds: publicSeconds),
      escrowDuration: Duration(seconds: escrowSeconds),
      bondSize: _some(BondSize.tryCreate(bond)),
      description: description,
    ),
  );

  RangeOrderAmount range(double min, double max) =>
      _some(RangeOrderAmount.tryCreate(fiat(min), fiat(max)));

  Result<MakerTerms, MakerTermsRefusal> create({
    MakeOrderRequest? asked,
    double createdPrice = 50000,
    double makerFee = 0.00025,
    Coordinator? on,
    RobosatsNetwork network = testnet,
  }) => MakerTerms.create(
    network: network,
    coordinator: on ?? temple,
    request: asked ?? request(),
    createdPrice: createdPrice,
    makerFee: makerFee,
  );

  MakerTerms terms({
    OrderType type = OrderType.buy,
    OrderAmount? amount,
    double premium = 0,
    double bond = 3,
    double createdPrice = 50000,
    double makerFee = 0.00025,
  }) => switch (create(
    asked: request(type: type, amount: amount, premium: premium, bond: bond),
    createdPrice: createdPrice,
    makerFee: makerFee,
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  Sats sats(int value) => Sats.fromInt(value);

  group('ExactRatio', () {
    ExactRatio of(double value) => _some(ExactRatio.ofDouble(value));
    ExactRatio ratio(int numerator, int denominator) =>
        ExactRatio.integer(numerator) / ExactRatio.integer(denominator);

    test('a double is the decimal its shortest text writes', () {
      expect(of(0.1), ratio(1, 10));
      expect(of(120.0), ExactRatio.integer(120));
      expect(of(-99.99), ratio(-9999, 100));
      expect(of(0.00025), ratio(1, 4000));
      expect(of(1e-7), ratio(1, 10000000));
      expect(of(1.5e-7), ratio(15, 100000000));
      expect(of(1e21), ExactRatio.bigInt(BigInt.from(10).pow(21)));
      expect(of(-0.0), ExactRatio.integer(0));
      expect(
        of(5e-324),
        ratio(5, 1) / ExactRatio.bigInt(BigInt.from(10).pow(324)),
      );
      expect(ExactRatio.ofDouble(double.nan), isNull);
      expect(ExactRatio.ofDouble(double.infinity), isNull);
      expect(ExactRatio.ofDouble(double.negativeInfinity), isNull);
    });

    test('arithmetic is exact and reduced', () {
      expect(ratio(1, 10) + ratio(2, 10), ratio(3, 10));
      expect(of(0.1) + of(0.2), of(0.3));
      expect(ratio(1, 3) * ExactRatio.integer(3), ExactRatio.integer(1));
      expect(ratio(1, 2) - ratio(3, 4), ratio(-1, 4));
      expect(ratio(2, 4).numerator, BigInt.one);
      expect(ratio(2, -4), ratio(-1, 2));
      expect(ratio(-1, 2).denominator, BigInt.two);
      expect(() => ratio(1, 0), throwsArgumentError);
    });

    test('floor rounds down, toward minus infinity', () {
      expect(ratio(7, 2).floor(), BigInt.from(3));
      expect(ratio(-7, 2).floor(), BigInt.from(-4));
      expect(ExactRatio.integer(-4).floor(), BigInt.from(-4));
      expect(ExactRatio.integer(4).floor(), BigInt.from(4));
      expect(ratio(1, 3).floor(), BigInt.zero);
      expect(ratio(-1, 3).floor(), -BigInt.one);
    });

    test('order, absolute value and display', () {
      expect(ratio(1, 3) < ratio(1, 2), isTrue);
      expect(ratio(1, 2) <= ratio(2, 4), isTrue);
      expect(ratio(1, 2) > ratio(1, 3), isTrue);
      expect(ratio(1, 2) >= ratio(1, 2), isTrue);
      expect(ratio(-1, 2).abs(), ratio(1, 2));
      expect(ratio(1, 4).toDouble(), 0.25);
      final huge = ExactRatio.bigInt(BigInt.from(10).pow(400));
      expect((huge / (huge + ExactRatio.integer(1))).toDouble(), 1.0);
      expect(huge.toDouble(), double.infinity);
    });
  });

  group('MakerTerms.create', () {
    test('the maker of a buy order buys, of a sell order sells', () {
      expect(tradeRoleMaking(OrderType.buy), TradeRole.buyer);
      expect(tradeRoleMaking(OrderType.sell), TradeRole.seller);
      expect(terms().role, TradeRole.buyer);
      expect(terms(type: OrderType.sell).role, TradeRole.seller);
      // The opposite of a take: the two rules never give the same role.
      for (final type in OrderType.values) {
        expect(tradeRoleMaking(type), isNot(tradeRoleTaking(type)));
      }
    });

    test(
      'the maker fee: 0 to 1 %, refused above, unusable when no fraction',
      () {
        expect(create(makerFee: 0), isA<Ok>());
        expect(create(makerFee: 0.01), isA<Ok>());
        expect(TradeTolerances.makerFeeCeiling, 0.01);
        for (final fee in [0.010000000000000002, 0.02, 1.0]) {
          expect(
            create(makerFee: fee),
            isA<Err>().having(
              (e) => e.failure,
              'failure',
              isA<MakerFeeTooHigh>(),
            ),
            reason: '$fee',
          );
        }
        for (final fee in [-1e-9, -0.01, double.nan, double.infinity]) {
          expect(
            create(makerFee: fee),
            isA<Err>().having(
              (e) => e.failure,
              'failure',
              isA<MakerTermsUnusable>(),
            ),
            reason: '$fee',
          );
        }
        // Minus zero is zero, so that the record and its hash are those of 0.
        final zero = terms(makerFee: -0.0);
        expect(zero.makerFee.isNegative, isFalse);
        expect(zero, terms(makerFee: 0));
      },
    );

    test('the price: from 0.0001 and below 10^15, finite', () {
      expect(create(createdPrice: 0.0001), isA<Ok>());
      expect(create(createdPrice: 999999999999999.875), isA<Ok>());
      expect(MakerTerms.minCreatedPrice, 0.0001);
      expect(MakerTerms.maxCreatedPrice, 1e15);
      for (final price in [
        0.00009999999999999999,
        0.00005,
        5e-324,
        2.2e-308,
        0.0,
        -0.0,
        -1.0,
        1e15,
        2e15,
        double.nan,
        double.infinity,
      ]) {
        expect(
          create(createdPrice: price),
          isA<Err>().having(
            (e) => e.failure,
            'failure',
            isA<MakerTermsUnusable>(),
          ),
          reason: '$price',
        );
      }
    });

    test(
      'every figure for display is finite, and every ceiling at least 1 sat, for any terms create accepts',
      () {
        final random = Random(17703);
        final prices = [
          MakerTerms.minCreatedPrice,
          999999999999999.875,
          for (var i = 0; i < 400; i++)
            _price(exp(log(1e-4) + random.nextDouble() * log(9.99e18))),
        ];
        final amounts = [1e-8, 9999999999.999998, 0.01, 100.0, 5e9];
        final premiums = [-99.99, 0.0, 999.0];
        final lasts = [
          Sats.fromInt(1),
          Sats.fromInt(200000),
          Sats(BigInt.two.pow(62)),
          Sats(BigInt.two.pow(2000)),
        ];
        for (final price in prices) {
          final amount = amounts[random.nextInt(amounts.length)];
          final premium = premiums[random.nextInt(premiums.length)];
          final made = terms(
            type: OrderType.sell,
            amount: FixedOrderAmount(fiat(amount)),
            premium: premium,
            bond: random.nextBool() ? 2 : 15,
            createdPrice: price,
            makerFee: random.nextBool() ? 0 : 0.01,
          );
          final reason = '$price $amount $premium';
          expect(made.expectedBond.isFinite, isTrue, reason: reason);
          expect(made.expectedBond, greaterThan(0), reason: reason);
          expect(made.createdRate.isFinite, isTrue, reason: reason);
          expect(made.createdRate, greaterThan(0), reason: reason);
          expect(made.bondCeiling.value, greaterThanOrEqualTo(BigInt.one));
          for (final last in lasts) {
            final gap = _some(
              made.rateGap(rangeAmount: null, tradeSatoshis: last),
            );
            expect(gap.fixedRate.isFinite, isTrue, reason: '$reason $last');
            expect(gap.createdRate.isFinite, isTrue, reason: '$reason $last');
            expect(gap.percent.isFinite, isTrue, reason: '$reason $last');
          }
          final asTradeTerms = _some(TradeTerms.made(made, orderId: 1));
          expect(asTradeTerms.expectedBond.isFinite, isTrue, reason: reason);
        }
      },
    );

    test('a coordinator not on the network is refused', () {
      final bazaar = coordinator('bazaar');
      expect(bazaar.isOn(testnet), isFalse);
      expect(create(on: bazaar), isA<Err>());
      expect(create(on: bazaar, network: RobosatsNetwork.mainnet), isA<Ok>());
    });

    test('the request is the terms\' own: what is sent is what is checked', () {
      final asked = request(
        amount: range(100, 600),
        premium: -2.5,
        description: 'Fast',
      );
      final made = switch (create(asked: asked)) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(identical(made.request, asked), isTrue);
      expect(made.amount, asked.amount);
      expect(made.premium, asked.premium);
      expect(made.bondSize, asked.bondSize);
      expect(made.publicDuration, asked.publicDuration);
      expect(made.escrowDuration, asked.escrowDuration);
      expect(made.currency, usd);
      expect(made.type, OrderType.buy);
    });

    test('its text names no amount, method or description', () {
      final made = switch (create(
        asked: request(paymentMethod: 'Secret bank', description: 'Hidden'),
        createdPrice: 12345.6789,
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      for (final text in ['$made', '${made.record}']) {
        expect(text, isNot(contains('Secret')));
        expect(text, isNot(contains('Hidden')));
        expect(text, isNot(contains('100')));
        expect(text, isNot(contains('12345')));
      }
    });
  });

  group('MakerTerms equality', () {
    test(
      'equal by every term: the request, the network, the coordinator, the price and the fee',
      () {
        final made = terms();
        expect(made, terms());
        expect(made.hashCode, terms().hashCode);
        MakerTerms other({
          RobosatsNetwork network = testnet,
          Coordinator? on,
          double createdPrice = 50000,
          double makerFee = 0.00025,
          MakeOrderRequest? asked,
        }) => switch (create(
          network: network,
          on: on,
          createdPrice: createdPrice,
          makerFee: makerFee,
          asked: asked,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        expect(other(), made);
        expect(other(createdPrice: 50000.0001), isNot(made));
        expect(other(makerFee: 0.0002), isNot(made));
        expect(other(network: RobosatsNetwork.mainnet), isNot(made));
        expect(other(on: coordinator('lake')), isNot(made));
        expect(other(asked: request(premium: 1)), isNot(made));
        expect(other(asked: request(description: 'Fast')), isNot(made));
      },
    );
  });

  group('MakerTerms records', () {
    test('a record round-trips exactly, fixed or range', () {
      for (final made in [
        terms(),
        terms(type: OrderType.sell, amount: range(100, 1500), premium: 999),
        terms(premium: -99.99, bond: 15, makerFee: 0),
        switch (create(
          asked: request(description: 'Cash in hand', publicSeconds: 600),
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        },
      ]) {
        final record = made.record;
        expect(record.hasPassword, isFalse);
        expect(record.latitude, isNull);
        expect(record.longitude, isNull);
        expect(record.version, MakerTermsRecord.currentVersion);
        expect(switch (MakerTerms.restore(record)) {
          Ok(:final value) => value,
          Err(:final failure) => failure,
        }, made);
      }
      final fixed = terms().record;
      expect(
        (fixed.amount, fixed.minAmount, fixed.maxAmount),
        (100.0, null, null),
      );
      final ranged = terms(amount: range(100, 600)).record;
      expect(
        (ranged.amount, ranged.minAmount, ranged.maxAmount),
        (null, 100.0, 600.0),
      );
    });

    MakerTermsRecord changed(
      MakerTermsRecord r, {
      int? version,
      String? network,
      String? alias,
      String? role,
      int? type,
      int? currencyId,
      (double?, double?, double?)? amounts,
      double? premium,
      String? paymentMethod,
      double? bond,
      int? publicSeconds,
      int? escrowSeconds,
      (String?,)? description,
      bool? hasPassword,
      (double?, double?)? place,
      double? createdPrice,
      double? makerFee,
    }) => MakerTermsRecord(
      version: version ?? r.version,
      network: network ?? r.network,
      coordinatorAlias: alias ?? r.coordinatorAlias,
      role: role ?? r.role,
      type: type ?? r.type,
      currencyId: currencyId ?? r.currencyId,
      amount: amounts == null ? r.amount : amounts.$1,
      minAmount: amounts == null ? r.minAmount : amounts.$2,
      maxAmount: amounts == null ? r.maxAmount : amounts.$3,
      premiumPercent: premium ?? r.premiumPercent,
      paymentMethod: paymentMethod ?? r.paymentMethod,
      bondSizePercent: bond ?? r.bondSizePercent,
      publicSeconds: publicSeconds ?? r.publicSeconds,
      escrowSeconds: escrowSeconds ?? r.escrowSeconds,
      description: description == null ? r.description : description.$1,
      hasPassword: hasPassword ?? r.hasPassword,
      latitude: place == null ? r.latitude : place.$1,
      longitude: place == null ? r.longitude : place.$2,
      createdPrice: createdPrice ?? r.createdPrice,
      makerFee: makerFee ?? r.makerFee,
    );

    test('a record this version would not write is refused, never guessed', () {
      final r = terms().record;
      expect(MakerTerms.restore(changed(r)), isA<Ok>());
      final malformed = <String, MakerTermsRecord>{
        'version': changed(r, version: 2),
        'network': changed(r, network: 'regtest'),
        'role of a taker': changed(r, role: 'seller'),
        'unknown role': changed(r, role: 'maker'),
        'type': changed(r, type: 2),
        'currency': changed(r, currencyId: 99999),
        'bitcoin': changed(r, currencyId: 1000),
        'no amount': changed(r, amounts: (null, null, null)),
        'both amounts': changed(r, amounts: (100, 100, 600)),
        'half a range': changed(r, amounts: (null, 100, null)),
        'range upside down': changed(r, amounts: (null, 600, 100)),
        'range too narrow': changed(r, amounts: (null, 100, 140)),
        'range too wide': changed(r, amounts: (null, 100, 1600)),
        'zero amount': changed(r, amounts: (0, null, null)),
        'amount too many decimals': changed(
          r,
          amounts: (100.123456789, null, null),
        ),
        'premium -100': changed(r, premium: -100),
        'premium decimals': changed(r, premium: 1.234),
        'premium above 999': changed(r, premium: 999.01),
        'empty method': changed(r, paymentMethod: ''),
        'method with a space at its end': changed(r, paymentMethod: 'Revolut '),
        'method with a line break': changed(r, paymentMethod: 'Rev\nolut'),
        'bond below 2': changed(r, bond: 1.99),
        'bond decimals': changed(r, bond: 3.001),
        'public too short': changed(r, publicSeconds: 599),
        'escrow too long': changed(r, escrowSeconds: 36001),
        'empty description': changed(r, description: ('',)),
        'password': changed(r, hasPassword: true),
        'meeting point': changed(r, place: (48.85, 2.35)),
        'half a meeting point': changed(r, place: (48.85, null)),
        'price zero': changed(r, createdPrice: 0),
        'price too high': changed(r, createdPrice: 1e15),
        'fee above 1 %': changed(r, makerFee: 0.0101),
        'negative fee': changed(r, makerFee: -0.0001),
      };
      for (final MapEntry(:key, :value) in malformed.entries) {
        expect(
          MakerTerms.restore(value),
          isA<Err>().having(
            (e) => e.failure,
            'failure',
            isA<TradeRecordMalformed>(),
          ),
          reason: key,
        );
      }
    });

    test('a coordinator gone, or not on the network, has its own refusal', () {
      final r = terms().record;
      for (final alias in ['nowhere', 'bazaar']) {
        expect(
          MakerTerms.restore(changed(r, alias: alias)),
          isA<Err>().having(
            (e) => e.failure,
            'failure',
            isA<TradeCoordinatorGone>(),
          ),
          reason: alias,
        );
      }
    });
  });

  group('the maker bond (status 0)', () {
    test(
      'expected: the bond size of the sats of the amount at the price and premium of the creation',
      () {
        // 100 USD at 50,000 USD/BTC: 200,000 sats; 3 % of them: 6,000.
        final made = terms();
        expect(made.createdSatoshis(fiat(100)), ExactRatio.integer(200000));
        expect(made.expectedBond, 6000);
        // A premium of 25 %: a rate of 62,500, 160,000 sats, 4,800.
        expect(terms(premium: 25).expectedBond, 4800);
        // A discount of 50 %: a rate of 25,000, 400,000 sats, 12,000.
        expect(terms(premium: -50).expectedBond, 12000);
        // 999 %: a rate of 549,500.
        expect(
          terms(premium: 999).createdSatoshis(fiat(100)),
          ExactRatio.integer(10000000000) / ExactRatio.integer(549500),
        );
        // -99.99 %: a rate of 5 USD/BTC, 2,000,000,000 sats.
        expect(
          terms(premium: -99.99).createdSatoshis(fiat(100)),
          ExactRatio.integer(2000000000),
        );
        expect(terms(premium: 1.5).createdRate, 50750);
      },
    );

    test('a range\'s bond is on its maximum, never its minimum', () {
      final made = terms(amount: range(100, 600));
      expect(made.expectedBond, 36000);
      expect(made.bondCeiling, sats(36721));
    });

    test(
      'the ceiling: 2 % above it and 1 sat, rounded down; the check agrees up to it, both ways',
      () {
        final made = terms();
        // 6,000 × 1.02 + 1 = 6,121.
        expect(made.bondCeiling, sats(6121));
        expect(made.bondAgrees(sats(6121)), isTrue);
        expect(made.bondAgrees(sats(6122)), isFalse);
        // 6,000 − 120 − 1 = 5,879.
        expect(made.bondAgrees(sats(5879)), isTrue);
        expect(made.bondAgrees(sats(5878)), isFalse);
        expect(made.bondAgrees(sats(6000)), isTrue);
        expect(made.bondAgrees(Sats.zero), isFalse);
      },
    );

    test(
      'computed exactly: the rule\'s own sat, where the same sum in doubles falls one below',
      () {
        // 10 USD at 45,000 with a bond of 7.5 %: 1,666.67 sats expected, 1,700.67 + 1 = 1,701.67 with the tolerance, so 1,701; in doubles the sum gives 1,700.
        final made = terms(
          amount: FixedOrderAmount(fiat(10)),
          createdPrice: 45000,
          bond: 7.5,
        );
        expect(made.bondCeiling, sats(1701));
        expect(made.bondAgrees(sats(1701)), isTrue);
        expect(made.bondAgrees(sats(1702)), isFalse);
        final inDoubles =
            (10 / 45000 * 1e8 * 7.5 / 100 * (1 + TradeTolerances.price) + 1)
                .floor();
        expect(inDoubles, 1700);
      },
    );

    test(
      'the reference\'s bond at the price of the creation, or a price up to 1.9 % away, always agrees and is within the ceiling',
      () {
        final random = Random(177);
        var checked = 0;
        for (var i = 0; i < 3000; i++) {
          // From 0.5 to 20,000, spread evenly on a log scale, so that many orders are small: from about 50 sats.
          final amount = _round(
            exp(log(0.5) + random.nextDouble() * log(40000)),
            2,
          );
          final price = _decimals(random, 100, 500000, 4);
          final premium = _decimals(random, -50, 100, 2);
          final bond = _decimals(random, 2, 15, 2);
          final ranged = random.nextBool();
          final made = terms(
            amount: ranged
                ? range(_round(amount / 4, 2), amount)
                : FixedOrderAmount(fiat(amount)),
            premium: premium,
            bond: bond,
            createdPrice: price,
          );
          // The rule's own limit, set by the size of the order (`MakerTerms.bondAgrees`): with S the order's sats at the rate of the creation, a price 1.9 % higher can take the reference's bond under the lower mark only when S × (0.02 − 0.019 / 1.019) < 1, that is below 738.4 sats; 739, for the rounding of the price to 4 decimals. The smallest order a recorded coordinator allows is 1,000 sats (`ammanaya-mainnet-limits.json`).
          final orderSats = made.createdSatoshis(made.amount.max).toDouble();
          if (orderSats < 739) continue;
          for (final move in [
            0.0,
            -0.019,
            0.019,
            _decimals(random, -0.019, 0.019, 5),
          ]) {
            final priceThen = _round(price * (1 + move), 4);
            final reference = _referenceBond(amount, priceThen, premium, bond);
            expect(
              made.bondAgrees(sats(reference)),
              isTrue,
              reason: '$i $move',
            );
            expect(
              reference,
              lessThanOrEqualTo(made.bondCeiling.value.toInt()),
            );
          }
          checked++;
        }
        expect(checked, greaterThan(2000));
      },
    );

    test(
      'a known limit, set by the size of the order: a price 2 % higher can take the reference\'s bond on an order of 1,279 sats under the lower mark, 1.9 % cannot',
      () {
        // 1.279 USD at 100,000: 1,279 sats; a bond of 15 %: 191.85 expected, 4.837 of tolerance below.
        final made = terms(
          amount: FixedOrderAmount(fiat(1.279)),
          bond: 15,
          createdPrice: 100000,
        );
        expect(made.createdSatoshis(fiat(1.279)), ExactRatio.integer(1279));
        // At 102,000: 1,253 sats, a bond of 187, 4.85 below.
        expect(_referenceBond(1.279, 102000, 0, 15), 187);
        expect(made.bondAgrees(sats(187)), isFalse);
        // At 101,900: 1,255 sats, a bond of 188, 3.85 below.
        expect(_referenceBond(1.279, 101900, 0, 15), 188);
        expect(made.bondAgrees(sats(188)), isTrue);
      },
    );

    test(
      'every bond the check accepts is within the ceiling, and the ceiling is the largest it accepts',
      () {
        final random = Random(1770);
        for (var i = 0; i < 2000; i++) {
          final made = terms(
            amount: FixedOrderAmount(fiat(_decimals(random, 1, 5000, 2))),
            createdPrice: _decimals(random, 1000, 200000, 4),
            premium: _decimals(random, -99.99, 999, 2),
            bond: _decimals(random, 2, 15, 2),
          );
          final ceiling = made.bondCeiling.value.toInt();
          expect(made.bondAgrees(sats(ceiling)), isTrue);
          expect(made.bondAgrees(sats(ceiling + 1)), isFalse);
        }
      },
    );
  });

  group('the contract\'s amount of a maker seller\'s escrow (#187)', () {
    test(
      'a range: the amount of the contract, never the maximum nor the minimum; outside the range, or none, no amount',
      () {
        final made = terms(type: OrderType.sell, amount: range(100, 600));
        expect(made.contractAmount(fiat(300)), fiat(300));
        expect(made.contractAmount(fiat(100)), fiat(100));
        expect(made.contractAmount(fiat(600)), fiat(600));
        expect(made.contractAmount(fiat(99.99)), isNull);
        expect(made.contractAmount(fiat(600.01)), isNull);
        expect(made.contractAmount(null), isNull);
      },
    );

    test('a fixed order: no amount of a range', () {
      final made = terms(type: OrderType.sell);
      expect(made.contractAmount(null), fiat(100));
      expect(made.contractAmount(fiat(100)), isNull);
    });

    test(
      'the escrow\'s sats expected at a price are the contract\'s amount with the premium, exactly, whatever the price of the creation',
      () {
        // 100 USD at 50,000 with no premium: 200,000 sats, the creation's price not used (#187 replaced its ceiling).
        final made = terms(type: OrderType.sell, createdPrice: 5000);
        expect(
          _some(made.satsAtPrice(50000, fiat(100))),
          ExactRatio.integer(200000),
        );
        expect(
          _some(
            terms(
              type: OrderType.sell,
              premium: 25,
            ).satsAtPrice(50000, fiat(100)),
          ),
          ExactRatio.integer(160000),
        );
      },
    );
  });

  group('the fee a maker\'s contract implies', () {
    test('a seller locks the trade and at most its fee and 1 sat above it', () {
      final made = terms(type: OrderType.sell);
      final last = sats(400000);
      expect(made.feeAgrees(tradeSatoshis: last, paid: sats(400000)), isTrue);
      expect(made.feeAgrees(tradeSatoshis: last, paid: sats(400100)), isTrue);
      expect(made.feeAgrees(tradeSatoshis: last, paid: sats(400101)), isTrue);
      expect(made.feeAgrees(tradeSatoshis: last, paid: sats(400102)), isFalse);
      expect(made.feeAgrees(tradeSatoshis: last, paid: sats(399999)), isFalse);
    });

    test('a buyer receives the trade less at most its fee and 1 sat', () {
      final made = terms();
      final last = sats(400000);
      expect(made.feeAgrees(tradeSatoshis: last, paid: sats(400000)), isTrue);
      expect(made.feeAgrees(tradeSatoshis: last, paid: sats(399900)), isTrue);
      expect(made.feeAgrees(tradeSatoshis: last, paid: sats(399899)), isTrue);
      expect(made.feeAgrees(tradeSatoshis: last, paid: sats(399898)), isFalse);
      expect(made.feeAgrees(tradeSatoshis: last, paid: sats(400001)), isFalse);
    });

    test('with no fee announced, 1 sat only; at 1 %, 1 % and 1 sat', () {
      final none = terms(type: OrderType.sell, makerFee: 0);
      expect(
        none.feeAgrees(tradeSatoshis: sats(400000), paid: sats(400001)),
        isTrue,
      );
      expect(
        none.feeAgrees(tradeSatoshis: sats(400000), paid: sats(400002)),
        isFalse,
      );
      final most = terms(makerFee: 0.01);
      expect(
        most.feeAgrees(tradeSatoshis: sats(400000), paid: sats(395999)),
        isTrue,
      );
      expect(
        most.feeAgrees(tradeSatoshis: sats(400000), paid: sats(395998)),
        isFalse,
      );
    });

    test(
      'the reference\'s escrow and payout always agree; two sats more fee never',
      () {
        final random = Random(17702);
        for (var i = 0; i < 3000; i++) {
          final fee = [
            0.0,
            0.0001995,
            0.00025,
            0.000375,
            0.01,
            _decimals(random, 0, 0.01, 7),
          ][random.nextInt(6)];
          final last = 1 + random.nextInt(2000000000);
          final seller = terms(type: OrderType.sell, makerFee: fee);
          final buyer = terms(makerFee: fee);
          final escrow = _referenceEscrow(last, fee);
          final payout = _referencePayout(last, fee);
          expect(
            seller.feeAgrees(tradeSatoshis: sats(last), paid: sats(escrow)),
            isTrue,
            reason: '$i',
          );
          expect(
            buyer.feeAgrees(tradeSatoshis: sats(last), paid: sats(payout)),
            isTrue,
            reason: '$i',
          );
          expect(
            seller.feeAgrees(tradeSatoshis: sats(last), paid: sats(escrow + 2)),
            isFalse,
            reason: '$i',
          );
          expect(
            buyer.feeAgrees(tradeSatoshis: sats(last), paid: sats(payout - 2)),
            isFalse,
            reason: '$i',
          );
          // The side matters: a seller's escrow is no buyer's payout.
          if (escrow != last) {
            expect(
              buyer.feeAgrees(tradeSatoshis: sats(last), paid: sats(escrow)),
              isFalse,
              reason: '$i',
            );
          }
        }
      },
    );
  });

  group('the gap from the rate of the creation', () {
    test(
      'the rate the sats imply, against the price and premium of the creation',
      () {
        final made = terms();
        final even = _some(
          made.rateGap(rangeAmount: null, tradeSatoshis: sats(200000)),
        );
        expect(even.fixedRate, 50000);
        expect(even.createdRate, 50000);
        expect(even.percent, 0);
        // 190,000 sats for 100 USD: a rate of 52,631.58, 5.26 % above.
        final fewer = _some(
          made.rateGap(rangeAmount: null, tradeSatoshis: sats(190000)),
        );
        expect(fewer.fixedRate, closeTo(52631.578947368, 1e-6));
        expect(fewer.percent, closeTo(5.263157894736842, 1e-12));
        // 250,000 sats: a rate of 40,000, 20 % below.
        expect(
          _some(
            made.rateGap(rangeAmount: null, tradeSatoshis: sats(250000)),
          ).percent,
          -20,
        );
      },
    );

    test('the premium is in both rates', () {
      // At 1.5 %, 197,044 sats is about the rate of the creation, 50,750.
      final gap = _some(
        terms(
          premium: 1.5,
        ).rateGap(rangeAmount: null, tradeSatoshis: sats(197044)),
      );
      expect(gap.createdRate, 50750);
      expect(gap.percent, closeTo(0.00017, 0.00001));
    });

    test('a range: on the amount of the contract', () {
      final made = terms(amount: range(100, 600));
      expect(
        _some(
          made.rateGap(rangeAmount: fiat(300), tradeSatoshis: sats(600000)),
        ).percent,
        0,
      );
      expect(
        _some(
          made.rateGap(rangeAmount: fiat(600), tradeSatoshis: sats(600000)),
        ).percent,
        100,
      );
      expect(
        made.rateGap(rangeAmount: null, tradeSatoshis: sats(600000)),
        isNull,
      );
      expect(
        made.rateGap(rangeAmount: fiat(700), tradeSatoshis: sats(600000)),
        isNull,
      );
    });

    test('no sats, no gap', () {
      expect(
        terms().rateGap(rangeAmount: null, tradeSatoshis: Sats.zero),
        isNull,
      );
    });
  });

  group('TradeTerms of a maker', () {
    test(
      'made: the maker\'s network, coordinator, role and order terms, with the order\'s number',
      () {
        final maker = terms(
          type: OrderType.sell,
          amount: range(100, 600),
          premium: 2,
          bond: 5,
        );
        final made = _some(TradeTerms.made(maker, orderId: 7));
        expect(made.network, testnet);
        expect(made.coordinator, temple);
        expect(made.orderId, 7);
        expect(made.role, TradeRole.seller);
        expect(made.type, OrderType.sell);
        expect(made.currency, usd);
        expect(made.premium, maker.premium);
        expect(made.bondSize, maker.bondSize);
        expect(made.escrowDuration, maker.escrowDuration);
        expect(made.side.maker, maker);
        expect(made.expectedBond, maker.expectedBond);
        expect(made.bondCeiling, maker.bondCeiling);
        // 600 USD at 51,000: 58,823.53 sats of bond; × 1.02 is exactly 60,000; + 1.
        expect(made.bondCeiling, sats(60001));
        expect(TradeTerms.made(maker, orderId: 0), isNull);
        expect(TradeTerms.made(maker, orderId: -1), isNull);
      },
    );

    test(
      'equal by order and what the maker asked; never equal to a taker\'s',
      () async {
        final maker = terms();
        expect(
          TradeTerms.made(maker, orderId: 7),
          TradeTerms.made(terms(), orderId: 7),
        );
        expect(
          TradeTerms.made(maker, orderId: 7),
          isNot(TradeTerms.made(maker, orderId: 8)),
        );
        expect(
          TradeTerms.made(maker, orderId: 7),
          isNot(TradeTerms.made(terms(premium: 1), orderId: 7)),
        );
        final taken = await tradeTerms(network: testnet);
        expect(taken.side, isA<TakenSide>());
        expect(TradeTerms.made(maker, orderId: taken.orderId), isNot(taken));
      },
    );

    test('restored from the record and the order\'s number', () {
      final maker = terms(amount: range(100, 600));
      expect(switch (TradeTerms.restoreMade(maker.record, orderId: 7)) {
        Ok(:final value) => value,
        Err(:final failure) => failure,
      }, TradeTerms.made(maker, orderId: 7));
      expect(
        TradeTerms.restoreMade(maker.record, orderId: 0),
        isA<Err>().having(
          (e) => e.failure,
          'failure',
          isA<TradeRecordMalformed>(),
        ),
      );
      expect(
        TradeTerms.restoreMade(
          MakerTermsRecord(
            version: 1,
            network: 'testnet',
            coordinatorAlias: 'bazaar',
            role: 'buyer',
            type: 0,
            currencyId: 1,
            amount: 100,
            minAmount: null,
            maxAmount: null,
            premiumPercent: 0,
            paymentMethod: 'Revolut',
            bondSizePercent: 3,
            publicSeconds: 86340,
            escrowSeconds: 10800,
            description: null,
            hasPassword: false,
            latitude: null,
            longitude: null,
            createdPrice: 50000,
            makerFee: 0.00025,
          ),
          orderId: 7,
        ),
        isA<Err>().having(
          (e) => e.failure,
          'failure',
          isA<TradeCoordinatorGone>(),
        ),
      );
    });

    test('a taker\'s terms keep their figures and their record', () async {
      final taken = await tradeTerms();
      final TradeTerms<TradeSide> asAnyTerms = taken;
      expect(asAnyTerms is TradeTerms<TakenSide>, isTrue);
      expect(asAnyTerms is TradeTerms<MadeSide>, isFalse);
      expect(taken.amount, taken.side.amount);
      expect(taken.takerFee, takerFee);
      expect(taken.expectedBond, taken.side.expectedSatoshis * 3 / 100);
      expect(
        taken.bondCeiling,
        Sats.fromInt((taken.expectedBond * 1.02 + 1).floor()),
      );
      expect(taken.escrowCeiling, taken.side.escrowCeiling);
      expect(switch (TradeTerms.restore(taken.record)) {
        Ok(:final value) => value == taken,
        Err() => false,
      }, isTrue);
    });

    test(
      'the state machine refuses a taker\'s answer, and error 1044, about a maker\'s trade, and leaves its trail (#178 follows the rest)',
      () async {
        final made42 = _some(
          TradeTerms.made(switch (create(
            asked: request(type: OrderType.sell),
            network: RobosatsNetwork.mainnet,
          )) {
            Ok(:final value) => value,
            Err(:final failure) => fail('$failure'),
          }, orderId: tradeOrderId),
        );
        final reader = Bolt11Reader(Bolt11TestDecoder());
        final before = TradeStatus.beforeFirstRead(
          TradeTrail.recovered(made42, tradeNow),
        );
        for (final (answer, Type refusal) in <(TradeAnswer, Type)>[
          // Error 1044 goes only to a robot that is no participant (`api/views.py:269-275`): never to a maker.
          (const TradeOrderNotAvailable(), TradeStatusUnexpected),
          // A taker's answers: this robot is not the maker the terms say.
          (
            await readAnswer(orderJson(6, role: TradeRole.buyer)),
            TradeRoleMismatch,
          ),
          (await readAnswer(orderJson(1)), TradeRoleMismatch),
        ]) {
          final after = TradeStatus.from(
            previous: before,
            answer: answer,
            terms: made42,
            now: tradeNow,
            reader: reader,
          );
          expect(after.position, before.position, reason: '$answer');
          // The trail is left where it was, the breach recorded.
          expect(after.trail.position, before.trail.position);
          expect(after.trail.breached, isTrue);
          expect(
            after.warnings.where((w) => w.runtimeType == refusal),
            hasLength(1),
            reason: '$answer',
          );
          expect(after.invoice, isNull);
          // Refused again: the warning is not added twice.
          final again = TradeStatus.from(
            previous: after,
            answer: answer,
            terms: made42,
            now: tradeNow,
            reader: reader,
          );
          expect(
            again.warnings.where((w) => w.runtimeType == refusal),
            hasLength(1),
          );
        }
      },
    );
  });
}

/// A random number from [min] to [max] with [decimals] decimals, as the coordinator's decimal fields keep it.
double _decimals(Random random, double min, double max, int decimals) =>
    _round(min + random.nextDouble() * (max - min), decimals);

double _round(double value, int decimals) {
  final scale = pow(10, decimals);
  return (value * scale).round() / scale;
}

/// `Logics.satoshis_now` of a fixed amount (`api/logics.py:256-275`): Python floats are IEEE doubles, as Dart's are, and `int` truncates.
int _referenceSats(double amount, double price, double premium) {
  final premiumRate = price * (1 + premium / 100);
  return ((amount / premiumRate) * 100 * 1000 * 1000).truncate();
}

/// `Logics.gen_maker_hold_invoice`'s bond (`api/logics.py:1266-1268`): `int(last_satoshis × bond_size / 100)` with the bond size a decimal of two places, so exact in integers.
int _referenceBond(double amount, double price, double premium, double bond) {
  final last = _referenceSats(amount, price, premium);
  return last * (bond * 100).round() ~/ 10000;
}

/// Python's `round` of a float: to the nearest integer, a half to the even one.
int _roundHalfEven(double value) {
  final floor = value.floorToDouble();
  final rest = value - floor;
  if (rest > 0.5) return floor.toInt() + 1;
  if (rest < 0.5) return floor.toInt();
  return floor.toInt().isEven ? floor.toInt() : floor.toInt() + 1;
}

/// `Logics.escrow_amount` of the maker seller (`api/logics.py:733-749`).
int _referenceEscrow(int last, double makerFee) =>
    _roundHalfEven(last + last * makerFee);

/// `Logics.payout_amount` of the maker buyer (`api/logics.py:650-668`).
int _referencePayout(int last, double makerFee) =>
    _roundHalfEven(last - last * makerFee);

/// [value], which the test knows is there.
T _some<T>(T? value) => value ?? (throw StateError('missing'));

/// [raw] as the coordinator's price could be: 4 decimals (whole above 10^10, where a double keeps none), at least `MakerTerms.minCreatedPrice`.
double _price(double raw) => max(
  MakerTerms.minCreatedPrice,
  raw < 1e10 ? _round(raw, 4) : raw.floorToDouble(),
);
