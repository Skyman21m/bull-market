import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/matching_orders.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/maker_form.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/presentation/active_trades_cubit.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';
import 'support/make_form.dart' show limitsOf;
import 'support/trade_harness.dart' show tradeKey;

final _eur = RobosatsCurrency.fromCode('EUR') ?? (throw StateError('EUR'));

/// The search of a form whose fields are typed as given: the side chosen [side] (the order made), EUR, the amount and the premium as typed, the methods chosen, and for a range the bounds typed, as the screen hands them to [MatchingOrders.of], the coordinator's limits [market] being read unless given (no size limit then).
MatchingOrders _of({
  OrderType? side = OrderType.buy,
  String amount = '100',
  String premium = '',
  List<String> methods = const [],
  bool range = false,
  String min = '',
  String max = '',
  MakerFormLimits market = const MakerFormLimitsLoading(),
}) {
  final input = MakerFormInput(
    type: side,
    currency: _eur,
    amount: amount,
    paymentMethods: methods,
    premium: premium,
    advanced: range,
    minAmount: min,
    maxAmount: max,
  );
  return MatchingOrders.of(
    input,
    MakerFormCheck.of(
      input,
      coordinatorsLoaded: true,
      market: market,
      sizeLimitSats: 21 * 100000000,
    ),
  );
}

/// The ids of the orders of [book] that [search] keeps, in the order it gives them, none of them held by the device unless [own] names it.
List<int> _kept(
  MatchingOrders search,
  List<PublicOrder> book, {
  Set<int> own = const {},
}) => [
  for (final order in search.apply(book, isOwn: (o) => own.contains(o.id)))
    order.id,
];

/// One order of the book read by the package's own parser, as a coordinator sends it (`support/fakes.dart`): a sell order (type 1) of 100 EUR at 2 % by « Revolut Instant SEPA » unless said otherwise.
Future<PublicOrder> _order(
  int id, {
  int type = 1,
  int currency = 2,
  double? amount = 100,
  double? minAmount,
  double? maxAmount,
  String paymentMethod = 'Revolut Instant SEPA',
  double premium = 2,
}) async => (await parseOrders([
  bookOrder(
    id: id,
    type: type,
    currency: currency,
    amount: amount,
    minAmount: minAmount,
    maxAmount: maxAmount,
    paymentMethod: paymentMethod,
    premium: premium,
  ),
])).single;

void main() {
  group('the side (`filterOrders.ts:88`, `MakerPage/index.tsx:38`)', () {
    late List<PublicOrder> book;
    setUpAll(() async {
      book = [await _order(1, type: 0), await _order(2, type: 1)];
    });

    test(
      'a buy order being made is shown the sell orders, those a buyer takes: « Buy » sets `fav.type` to 1 (`MakerForm.tsx:764-775`), the order made is type 0 (`:258`)',
      () {
        expect(_of().type, OrderType.sell);
        expect(_kept(_of(), book), [2]);
      },
    );

    test('a sell order being made is shown the buy orders', () {
      expect(_of(side: OrderType.sell).type, OrderType.buy);
      expect(_kept(_of(side: OrderType.sell), book), [1]);
    });

    test(
      'no side chosen shows both types (`baseFilter.type === null`), in the book\'s order',
      () {
        expect(_of(side: null).type, isNull);
        expect(_kept(_of(side: null), book), [1, 2]);
      },
    );
  });

  test(
    'the mode `fiat` and the currency (`:89`, `:91`): an order of another currency or of bitcoin (a swap) is never shown',
    () async {
      final book = [
        await _order(1),
        await _order(2, currency: 1),
        await _order(3, currency: 1000),
      ];
      expect(_kept(_of(), book), [1]);
    },
  );

  group('the premium (`filterByPremium`, `filterOrders.ts:62-69`)', () {
    test(
      'none typed, or no number, keeps every premium (`maker.premium ?? null`, `MakerForm.tsx:252`)',
      () async {
        final book = [await _order(1, premium: 500), await _order(2)];
        expect(_of().premium, isNull);
        expect(_kept(_of(), book), [2, 1]);
        expect(_of(premium: '2a').premium, isNull);
        expect(_kept(_of(premium: '2a'), book), [2, 1]);
      },
    );

    test(
      'a sell order is kept at the premium typed or lower (`orderPremium <= premium`), 0 included',
      () async {
        final book = [
          await _order(1, premium: 2),
          await _order(2, premium: 2.01),
          await _order(3, premium: 1.99),
          await _order(4, premium: -3),
        ];
        expect(_kept(_of(premium: '2'), book), [4, 3, 1]);
        expect(_kept(_of(premium: '0'), book), [4]);
      },
    );

    test(
      'a buy order is kept at the premium typed or higher (`orderPremium >= premium`)',
      () async {
        final book = [
          await _order(1, type: 0, premium: 2),
          await _order(2, type: 0, premium: 2.01),
          await _order(3, type: 0, premium: 1.99),
        ];
        expect(_kept(_of(side: OrderType.sell, premium: '2'), book), [2, 1]);
      },
    );

    test(
      'a premium beyond its bounds is searched at the bound the form keeps (999, or −99.99, `MakerForm.tsx:241-247`)',
      () async {
        // A buy order at 999 % is kept for 1,500 typed (searched at 999), a sell order at −99.99 % for −100 typed (searched at −99.99).
        final book = [
          await _order(1, type: 0, premium: 999),
          await _order(2, type: 0, premium: 998),
          await _order(3, premium: -99.99),
          await _order(4, premium: -99),
        ];
        expect(_of(premium: '1500').premium, 999);
        expect(_kept(_of(side: OrderType.sell, premium: '1500'), book), [1]);
        expect(_of(premium: '-100').premium, -99.99);
        expect(_kept(_of(premium: '-100'), book), [3]);
      },
    );
  });

  test(
    'the payment methods (`filterByPayment`, `:19-29`): none keeps every order, else the order\'s text contains one of them, case included, anywhere',
    () async {
      final book = [
        await _order(1, paymentMethod: 'Instant SEPA'),
        await _order(2, paymentMethod: 'revolut'),
        await _order(3, paymentMethod: 'Revolut Wise'),
        await _order(4, paymentMethod: 'Cash F2F'),
      ];
      expect(_kept(_of(), book), [1, 2, 3, 4]);
      expect(_kept(_of(methods: ['SEPA']), book), [1]);
      expect(_kept(_of(methods: ['Revolut']), book), [3]);
      expect(_kept(_of(methods: ['Wise', 'SEPA']), book), [1, 3]);
      expect(_kept(_of(methods: ['PayPal']), book), isEmpty);
    },
  );

  group('the amount (`filterByAmount`, `:46-60`, threshold 0.7)', () {
    test(
      'from 0.3 to 1.7 times the amount typed, in floating point as the reference: 100 × (1 − 0.7) is 30.000000000000004, so 30 is out and 170 is in',
      () async {
        final book = [
          await _order(1, amount: 30),
          await _order(2, amount: 31),
          await _order(3, amount: 170),
          await _order(4, amount: 170.01),
        ];
        expect(MatchingOrders.threshold, 0.7);
        expect(_kept(_of(), book), [2, 3]);
      },
    );

    test(
      'a range order is kept when its range overlaps those bounds (`max(min) <= min(max)`)',
      () async {
        final book = [
          await _order(1, amount: null, minAmount: 10, maxAmount: 31),
          await _order(2, amount: null, minAmount: 10, maxAmount: 30),
          await _order(3, amount: null, minAmount: 170, maxAmount: 900),
          await _order(4, amount: null, minAmount: 171, maxAmount: 900),
          await _order(5, amount: null, minAmount: 10, maxAmount: 900),
        ];
        expect(_kept(_of(), book), [1, 3, 5]);
      },
    );

    test(
      'no amount typed, or no number, is 0 (`Number(null)`, `Number(\'\')`): nothing is kept, a range neither',
      () async {
        final book = [
          await _order(1, amount: 0.01),
          await _order(2, amount: null, minAmount: 0.01, maxAmount: 900),
        ];
        expect(_of(amount: '').amount, 0);
        expect(_kept(_of(amount: ''), book), isEmpty);
        expect(_kept(_of(amount: 'x'), book), isEmpty);
        expect(_kept(_of(amount: '-5'), book), isEmpty);
      },
    );

  });

  group(
    'an order made with a range (#230, a deviation from the reference, its defect corrected): the range typed is searched, from 0.3 times its minimum to 1.7 times its maximum, as `filterOrders.ts:47-50` is written',
    () {
      test(
        'the reference\'s threshold, the same as for an exact amount, in floating point: 50 to 200 searches from 50 × (1 − 0.7), 15.000000000000002, so 15 is out, to 200 × 1.7, 340, in',
        () async {
          final book = [
            await _order(1, amount: 15),
            await _order(2, amount: 15.01),
            await _order(3, amount: 120),
            await _order(4, amount: 340),
            await _order(5, amount: 340.01),
            await _order(6, amount: 400),
          ];
          final ranged = _of(amount: '', range: true, min: '50', max: '200');
          expect(MatchingOrders.rangeThreshold, MatchingOrders.threshold);
          expect(ranged.range?.min, 50);
          expect(ranged.range?.max, 200);
          expect(_kept(ranged, book), [2, 3, 4]);
        },
      );

      test(
        'a range order is kept when its range overlaps the range searched (`Math.max(filterMin, orderMin) <= Math.min(filterMax, orderMax)`)',
        () async {
          final book = [
            await _order(1, amount: null, minAmount: 5, maxAmount: 15),
            await _order(2, amount: null, minAmount: 5, maxAmount: 15.01),
            await _order(3, amount: null, minAmount: 340, maxAmount: 900),
            await _order(4, amount: null, minAmount: 340.01, maxAmount: 900),
            await _order(5, amount: null, minAmount: 1, maxAmount: 900),
            await _order(6, amount: null, minAmount: 60, maxAmount: 90),
          ];
          expect(
            _kept(_of(amount: '', range: true, min: '50', max: '200'), book),
            [2, 3, 5, 6],
          );
        },
      );

      test(
        'the field « Amount » that « Amount Range » hides is not searched: 100 held from before the options opened, 500 to 1,000 typed, 150 to 1,700 searched',
        () async {
          final book = [
            await _order(1, amount: 100),
            await _order(2, amount: 700),
            await _order(3, amount: 150),
            await _order(4, amount: 1700),
          ];
          final ranged = _of(range: true, min: '500', max: '1000');
          expect(ranged.amount, 100);
          expect(_kept(ranged, book), [2, 4]);
          // The same range with nothing in « Amount », which the reference searches at 0 and keeps nothing.
          expect(
            _kept(_of(amount: '', range: true, min: '500', max: '1000'), book),
            [2, 4],
          );
        },
      );

      test(
        'the range only while it is on: the options closed, or « Exact Amount », search the amount typed, the bounds kept aside',
        () async {
          final book = [
            await _order(1, amount: 100),
            await _order(2, amount: 700),
          ];
          for (final input in [
            MakerFormInput(
              type: OrderType.buy,
              currency: _eur,
              amount: '100',
              paymentMethods: const [],
              minAmount: '500',
              maxAmount: '1000',
            ),
            MakerFormInput(
              type: OrderType.buy,
              currency: _eur,
              amount: '100',
              paymentMethods: const [],
              advanced: true,
              rangeEnabled: false,
              minAmount: '500',
              maxAmount: '1000',
            ),
          ]) {
            final search = MatchingOrders.of(
              input,
              MakerFormCheck.of(
                input,
                coordinatorsLoaded: true,
                market: const MakerFormLimitsLoading(),
                sizeLimitSats: 21 * 100000000,
              ),
            );
            expect(search.range, isNull);
            expect(_kept(search, book), [1]);
          }
        },
      );

      test(
        'bounds that are no range the form takes search nothing, as an exact amount none typed: empty, no number, 0 or below, crossed, too close or too far apart (`AmountRange.tsx:57-77`)',
        () async {
          final book = [
            await _order(1, amount: 0.01),
            await _order(2, amount: 60),
            await _order(3, amount: 120),
            await _order(4, amount: null, minAmount: 0.01, maxAmount: 99999),
          ];
          for (final (min, max) in [
            ('', ''),
            ('', '200'),
            ('50', ''),
            ('x', '200'),
            ('50', '2O0'),
            ('0', '200'),
            ('-50', '200'),
            ('-200', '-50'),
            // Crossed: 200 to 50 would otherwise search from 60 to 85.
            ('200', '50'),
            // Under 1.5 times apart, or over 14.95 times.
            ('50', '74.99'),
            ('20', '300'),
          ]) {
            final search = _of(amount: '120', range: true, min: min, max: max);
            expect(search.range, MatchingOrders.noRange, reason: '$min-$max');
            expect(_kept(search, book), isEmpty, reason: '$min-$max');
          }
          // At 1.5 and 14.95 times apart, the form's own bounds: searched.
          expect(
            _kept(_of(amount: '', range: true, min: '50', max: '75'), book),
            [2, 3, 4],
          );
          expect(
            _kept(_of(amount: '', range: true, min: '20', max: '299'), book),
            [2, 3, 4],
          );
        },
      );

      test(
        'a range outside the coordinator\'s limits, which the form refuses, searches nothing; a range within them is searched',
        () async {
          // EUR at 50,000, orders from 100 to 1,000 EUR.
          final market = MakerFormLimitsRead(
            await limitsOf({2: (50000, 100, 1000)}),
          );
          final book = [await _order(1, amount: 120), await _order(2)];
          final below = _of(
            amount: '',
            range: true,
            min: '50',
            max: '200',
            market: market,
          );
          expect(below.range, MatchingOrders.noRange);
          expect(_kept(below, book), isEmpty);
          final within = _of(
            amount: '',
            range: true,
            min: '200',
            max: '500',
            market: market,
          );
          expect(within.range?.min, 200);
          expect(_kept(within, book), [1, 2]);
        },
      );

      test(
        'the other fields do not change with a range: the side, the currency, bitcoin, the premium and the methods filter as for an exact amount',
        () async {
          final book = [
            await _order(1, premium: 1),
            await _order(2, type: 0, amount: 120),
            await _order(3, currency: 1, amount: 120),
            await _order(4, currency: 1000, amount: 120),
            await _order(5, premium: 2.5, amount: 120),
            await _order(6, paymentMethod: 'PayPal', amount: 120),
            await _order(7, amount: 120, premium: 0),
          ];
          expect(
            _kept(
              _of(
                amount: '',
                range: true,
                min: '50',
                max: '200',
                premium: '2',
                methods: ['Revolut'],
              ),
              book,
            ),
            [7, 1],
          );
          expect(
            _kept(
              _of(
                side: OrderType.sell,
                amount: '',
                range: true,
                min: '50',
                max: '200',
              ),
              book,
            ),
            [2],
          );
        },
      );
    },
  );

  test(
    'an order this device holds is never offered, the others are (the owner\'s rule; the reference shows them)',
    () async {
      final book = [await _order(1), await _order(2), await _order(3)];
      expect(_kept(_of(), book, own: {2}), [1, 3]);
    },
  );

  test(
    'the device holds an order when an open record of its network names its coordinator and number, whatever the record\'s origin (`ActiveTradesListed.holds`)',
    () async {
      final order = await _order(5);
      final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
      TradeRecord record({
        RobosatsNetwork network = RobosatsNetwork.mainnet,
        String alias = 'temple',
        int id = 5,
        TradeOrigin origin = TradeOrigin.takenHere,
        DateTime? closedAt,
      }) => TradeRecord(
        robot: RobotSlot(network, fingerprint, 1),
        coordinatorAlias: alias,
        coordinatorOnion: 'unused.onion',
        orderId: id,
        role: TradeRole.buyer,
        origin: origin,
        takenAt: testNow,
        confirmedAt: testNow,
        closedAt: closedAt,
      );
      bool holds(TradeRecord record) => ActiveTradesListed([
        ActiveTrade(record, const ActiveTradeTakeNeverSent()),
      ]).holds(order, RobosatsNetwork.mainnet);
      for (final origin in TradeOrigin.values) {
        expect(holds(record(origin: origin)), isTrue, reason: '$origin');
      }
      expect(holds(record(network: RobosatsNetwork.testnet)), isFalse);
      expect(holds(record(alias: 'lake')), isFalse);
      expect(holds(record(id: 6)), isFalse);
      expect(holds(record(closedAt: testNow)), isFalse);
      expect(
        const ActiveTradesListed([]).holds(order, RobosatsNetwork.mainnet),
        isFalse,
      );
    },
  );

  group(
    'the order of the reference\'s table (`BookTable/index.tsx:118-122`)',
    () {
      test(
        'sell orders shown: the lowest premium first, equal premiums in the book\'s order',
        () async {
          final book = [
            await _order(1, premium: 1),
            await _order(2, premium: -1),
            await _order(3, premium: 1),
            await _order(4, premium: 0),
          ];
          expect(_kept(_of(), book), [2, 4, 1, 3]);
        },
      );

      test('buy orders shown: the highest premium first', () async {
        final book = [
          await _order(1, type: 0, premium: 1),
          await _order(2, type: 0, premium: 3),
          await _order(3, type: 0, premium: 1),
          await _order(4, type: 0, premium: 2),
        ];
        expect(_kept(_of(side: OrderType.sell), book), [2, 4, 1, 3]);
      });

      test('both shown: the book\'s order', () async {
        final book = [
          await _order(1, premium: 3),
          await _order(2, type: 0, premium: -1),
          await _order(3, premium: 1),
        ];
        expect(_kept(_of(side: null), book), [1, 2, 3]);
      });
    },
  );
}
