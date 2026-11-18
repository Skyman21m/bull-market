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
import 'support/trade_harness.dart' show tradeKey;

final _eur = RobosatsCurrency.fromCode('EUR') ?? (throw StateError('EUR'));

/// The search of a form whose fields are typed as given: the side chosen [side] (the order made), EUR, the amount and the premium as typed, the methods chosen, and for a range the bounds typed, as the screen hands them to [MatchingOrders.of].
MatchingOrders _of({
  OrderType? side = OrderType.buy,
  String amount = '100',
  String premium = '',
  List<String> methods = const [],
  bool range = false,
  String min = '',
  String max = '',
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
      market: const MakerFormLimitsLoading(),
      sizeLimitSats: 0,
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

    test(
      'the reference\'s defect, reproduced: a range typed is never searched, the exact amount the hidden field « Amount » holds is (`filter.amount !== \'\'` always holds)',
      () async {
        final book = [
          await _order(1, amount: 100),
          await _order(2, amount: 700),
        ];
        // « Amount Range » 500 to 1,000, the field « Amount » holding 100 from before the options opened.
        final ranged = _of(range: true, min: '500', max: '1000');
        expect(ranged.amount, 100);
        expect(_kept(ranged, book), [1]);
        // The same range with nothing in « Amount »: nothing, the 700 inside the range included.
        expect(
          _kept(_of(amount: '', range: true, min: '500', max: '1000'), book),
          isEmpty,
        );
      },
    );
  });

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
