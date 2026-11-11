import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/book_filter.dart';
import 'package:p2p/src/domain/depth_chart.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart';

/// A line as the official client's series print it: each point's place, amount and order number.
List<(double, double, int?)> shape(List<DepthPoint> line) => [
  for (final point in line) (point.x, point.btc, point.order?.id),
];

/// An order of the cases of `reference-js/depth.js`: its number, side (0 buy, 1 sell), premium and sats now.
Map<String, Object?> caseOrder(
  int id,
  int type,
  double premium,
  int sats, {
  int currency = 2,
  double? price = 93330,
}) => bookOrder(
  id: id,
  type: type,
  premium: premium,
  satoshisNow: sats,
  currency: currency,
  price: price,
  makerSeed: id,
);

RobosatsCurrency currency(int id) =>
    RobosatsCurrency.fromId(id) ?? (throw StateError('no currency $id'));

final eur = currency(2);
final usd = currency(1);

void main() {
  // The expected values were printed by the official client's own functions (`generateSerie`, `closeSerie`, `matchMedian` and the effect that sets the centre), copied into `archives-session-2026-11-10/graphique-30/reference-js/depth.js` and run with node on the same orders.
  group('as the official client computes it', () {
    // Case A: one currency, both sides, orders on both sides of the window.
    final caseA = [
      caseOrder(1, 1, 1, 1000000),
      caseOrder(2, 1, 3, 2000000),
      caseOrder(3, 1, 12, 5000000),
      caseOrder(4, 0, -1, 3000000),
      caseOrder(5, 0, 2.5, 1000000),
      caseOrder(6, 0, -9, 4000000),
      caseOrder(7, 0, 2.5, 2000000),
      caseOrder(8, 0, 11, 500000),
      caseOrder(9, 1, -7, 100000),
    ];

    test(
      'premium axis: the window opens on the median cut to a whole number, ±8 by 0.5',
      () async {
        final chart = DepthChart.of(
          book: await parseOrders(caseA),
          filter: BookFilter(currency: eur),
          axis: DepthAxis.premium,
        );
        expect(
          chart.window,
          const DepthWindow(center: 2, halfRange: 8, step: 0.5),
        );
        expect(chart.priceCurrency, isNull);
      },
    );

    test('premium axis: the two lines add up the orders from each edge', () async {
      final chart = DepthChart.of(
        book: await parseOrders(caseA),
        filter: BookFilter(currency: eur),
        axis: DepthAxis.premium,
      );
      final lines = chart.linesIn(chart.window);
      // Buy orders come from the right; order 8, beyond the right edge, still counts, so the line starts flat from the edge.
      // Equal premiums (orders 5 and 7) come in the reverse of the book's order, and order 6, beyond the left edge, is left out.
      expect(shape(lines.buy), [
        (10, 0.005, null),
        (2.5, 0.005, null),
        (2.5, 0.025, 7),
        (2.5, 0.025, null),
        (2.5, 0.035, 5),
        (-1, 0.035, null),
        (-1, 0.065, 4),
        (-6, 0.065, null),
      ]);
      expect(shape(lines.sell), [
        (-6, 0.001, null),
        (1, 0.001, null),
        (1, 0.011, 1),
        (3, 0.011, null),
        (3, 0.031, 2),
        (10, 0.031, null),
      ]);
      expect(lines.buyOrders, 3);
      expect(lines.sellOrders, 2);
      expect(lines.top, 0.065);
    });

    test('premium axis: zooming moves the edges by one step each time', () async {
      final chart = DepthChart.of(
        book: await parseOrders(caseA),
        filter: BookFilter(currency: eur),
        axis: DepthAxis.premium,
      );
      final narrow = chart.window.zoomedIn().zoomedIn();
      expect(narrow, const DepthWindow(center: 2, halfRange: 7, step: 0.5));
      final lines = chart.linesIn(narrow);
      expect(shape(lines.buy).first, (9, 0.005, null));
      expect(shape(lines.buy).last, (-5, 0.065, null));
      expect(shape(lines.sell).first, (-5, 0.001, null));
      expect(shape(lines.sell).last, (9, 0.031, null));

      final wide = chart.window.zoomedOut().zoomedOut().zoomedOut();
      expect(wide.halfRange, 9.5);
      final wider = chart.linesIn(wide);
      // Orders 8 and 9 now fall inside: each line starts at zero, so no flat start is added.
      expect(shape(wider.buy), [
        (11, 0, null),
        (11, 0.005, 8),
        (2.5, 0.005, null),
        (2.5, 0.025, 7),
        (2.5, 0.025, null),
        (2.5, 0.035, 5),
        (-1, 0.035, null),
        (-1, 0.065, 4),
        (-7.5, 0.065, null),
      ]);
      expect(shape(wider.sell), [
        (-7, 0, null),
        (-7, 0.001, 9),
        (1, 0.001, null),
        (1, 0.011, 1),
        (3, 0.011, null),
        (3, 0.031, 2),
        (11.5, 0.031, null),
      ]);
    });

    test(
      'premium axis: « + » is disabled at a half range of 1, after 14 steps',
      () async {
        final chart = DepthChart.of(
          book: await parseOrders(caseA),
          filter: BookFilter(currency: eur),
          axis: DepthAxis.premium,
        );
        var window = chart.window;
        var clicks = 0;
        while (window.canZoomIn) {
          window = window.zoomedIn();
          clicks++;
        }
        expect(clicks, 14);
        expect(window.halfRange, 1);
        expect(window.zoomedIn(), window);
        expect(window.canZoomOut, isTrue);
      },
    );

    test(
      'an even count takes the mean of the two middle premiums, cut toward zero',
      () async {
        final chart = DepthChart.of(
          book: await parseOrders([
            caseOrder(1, 1, -2.7, 1000000),
            caseOrder(2, 0, -0.4, 1000000),
          ]),
          filter: const BookFilter(),
          axis: DepthAxis.premium,
        );
        // matchMedian gives -1.55, and `~~` cuts it to -1.
        expect(DepthChart.median([-2.7, -0.4]), closeTo(-1.55, 1e-12));
        expect(chart.window.center, -1);
      },
    );

    test(
      'every currency and host: both coordinators drawn, the lines of the official client',
      () async {
        final book = await parseOrders([
          caseOrder(1, 1, 1, 1000000),
          caseOrder(2, 1, 2, 1000000, currency: 1),
          caseOrder(4, 1, 7, 1000000),
        ]);
        final lake = await parseOrders([
          caseOrder(3, 1, 3, 1000000),
        ], alias: 'lake');
        final everything = DepthChart.of(
          book: [...book, ...lake],
          filter: const BookFilter(),
          axis: DepthAxis.premium,
        );
        // The official client takes the median of the four premiums, 2.5; here temple's median, 2, and lake's, 3, give 2.5 too: the centre is 2 either way.
        expect(everything.window.center, 2);
        expect(shape(everything.linesIn(everything.window).sell), [
          (1, 0, null),
          (1, 0.01, 1),
          (2, 0.01, null),
          (2, 0.02, 2),
          (3, 0.02, null),
          (3, 0.03, 3),
          (7, 0.03, null),
          (7, 0.04, 4),
          (10, 0.04, null),
        ]);
      },
    );

    // Case E: premiums whose factor 1 + premium / 100 is exact in binary, at a market price of 50000.
    final caseE = [
      for (final (id, type, premium, sats) in [
        (1, 1, 0.0, 1000000),
        (2, 1, 12.5, 2000000),
        (3, 1, 25.0, 3000000),
        (4, 0, -12.5, 1500000),
        (5, 0, -25.0, 2500000),
        (6, 0, -50.0, 500000),
        (7, 1, 50.0, 700000),
      ])
        caseOrder(id, type, premium, sats, price: 50000 * (1 + premium / 100)),
    ];

    test(
      'price axis: from the median to the highest price, a tenth of that per step',
      () async {
        final chart = DepthChart.of(
          book: await parseOrders(caseE),
          filter: BookFilter(currency: eur),
          axis: DepthAxis.price,
        );
        expect(chart.priceCurrency, eur);
        expect(
          chart.window,
          const DepthWindow(center: 50000, halfRange: 25000, step: 2500),
        );
        final lines = chart.linesIn(chart.window);
        // The highest order (7, at 75000) lies on the edge: the strict bounds of the official client leave it out, and the lowest (6, at 25000) too.
        expect(shape(lines.buy), [
          (43750, 0, null),
          (43750, 0.015, 4),
          (37500, 0.015, null),
          (37500, 0.04, 5),
          (25000, 0.04, null),
        ]);
        expect(shape(lines.sell), [
          (50000, 0, null),
          (50000, 0.01, 1),
          (56250, 0.01, null),
          (56250, 0.03, 2),
          (62500, 0.03, null),
          (62500, 0.06, 3),
          (75000, 0.06, null),
        ]);
        final narrow = chart.linesIn(
          chart.window.zoomedIn().zoomedIn().zoomedIn(),
        );
        expect(shape(narrow.buy).last, (32500, 0.04, null));
        expect(shape(narrow.sell).last, (67500, 0.06, null));
      },
    );

    test(
      'price axis: « + » stops one step before the window would close up',
      () async {
        final chart = DepthChart.of(
          book: await parseOrders(caseE),
          filter: BookFilter(currency: eur),
          axis: DepthAxis.price,
        );
        var window = chart.window;
        var clicks = 0;
        while (window.canZoomIn) {
          window = window.zoomedIn();
          clicks++;
        }
        // The official client allows a tenth click, down to a half range of 0.
        expect(clicks, 9);
        expect(window.halfRange, 2500);
        expect(window.isDrawable, isTrue);
      },
    );
  });

  group('one vote per coordinator, after the filter', () {
    test('the centre follows the currency and the host chosen', () async {
      final book = await parseOrders([
        caseOrder(1, 1, 1, 1000000),
        caseOrder(2, 1, 2, 1000000, currency: 1),
        caseOrder(4, 1, 7, 1000000),
      ]);
      final lake = await parseOrders([
        caseOrder(3, 1, 3, 1000000),
      ], alias: 'lake');
      final narrow = DepthChart.of(
        book: [...book, ...lake],
        filter: BookFilter(currency: eur, host: coordinator('temple')),
        axis: DepthAxis.premium,
      );
      // Only temple's two euro orders are drawn: their median, 4, is the centre (the official client keeps 2, the median of every order).
      expect(narrow.window.center, 4);
      expect(shape(narrow.linesIn(narrow.window).sell), [
        (1, 0, null),
        (1, 0.01, 1),
        (7, 0.01, null),
        (7, 0.02, 4),
        (12, 0.02, null),
      ]);
      expect(narrow.linesIn(narrow.window).buy, isEmpty);
    });

    test('the median of each coordinator, then the median of those', () {
      final temple = coordinator('temple');
      final lake = coordinator('lake');
      final bazaar = coordinator('bazaar');
      expect(
        DepthChart.medianOfCoordinators([
          for (var i = 0; i < 100; i++) (temple, 1e12),
          (lake, 1),
          (lake, 3),
          (bazaar, 5),
        ]),
        5,
      );
      expect(DepthChart.medianOfCoordinators([(temple, 2)]), 2);
      expect(DepthChart.medianOfCoordinators(const []), isNull);
    });

    // The scenario of the review: 40 sell and 40 buy orders priced in sats at the largest premium the package reads, on two coordinators, and 30 honest orders.
    List<Map<String, Object?>> flood(int type) => [
      for (var id = 1; id <= 40; id++)
        bookOrder(
          id: id,
          type: type,
          premium: 999999999999,
          satoshisNow: 1000,
          isExplicit: true,
          satoshis: 1000,
          price: 1,
          makerSeed: id,
        ),
    ];
    List<Map<String, Object?>> honest() => [
      for (var id = 1; id <= 30; id++)
        caseOrder(id, id.isEven ? 1 : 0, (id - 15) / 4, 1000000),
    ];

    test(
      'two flooding coordinators out of five do not move the centre',
      () async {
        final book = [
          ...await parseOrders(flood(1)),
          ...await parseOrders(flood(0), alias: 'bazaar'),
          ...await parseOrders(honest(), alias: 'lake'),
          ...await parseOrders(honest(), alias: 'freeport'),
          ...await parseOrders(honest(), alias: 'ammanaya'),
        ];
        final chart = DepthChart.of(
          book: book,
          filter: const BookFilter(),
          axis: DepthAxis.premium,
        );
        // Each honest coordinator's median is 1/8: the centre is 0, with the 90 honest orders in the window and the flood outside.
        expect(chart.window.center, 0);
        final lines = chart.linesIn(chart.window);
        expect(lines.buyOrders + lines.sellOrders, 3 * 30);
      },
    );

    test(
      'two flooding coordinators out of three win, and choosing a host brings the chart back',
      () async {
        final book = [
          ...await parseOrders(flood(1)),
          ...await parseOrders(flood(0), alias: 'bazaar'),
          ...await parseOrders(honest(), alias: 'lake'),
        ];
        final flooded = DepthChart.of(
          book: book,
          filter: const BookFilter(),
          axis: DepthAxis.premium,
        );
        expect(flooded.window.center, 999999999999);
        final honestHost = DepthChart.of(
          book: book,
          filter: BookFilter(host: coordinator('lake')),
          axis: DepthAxis.premium,
        );
        expect(honestHost.window.center, 0);
        final lines = honestHost.linesIn(honestHost.window);
        // Lake's premiums run from -3.5 to 3.75, all inside ±8: its 30 orders are drawn.
        expect(lines.buyOrders + lines.sellOrders, 30);
      },
    );

    test(
      'the market price: one vote per coordinator, the chosen host first',
      () async {
        final book = [
          // Temple floods the dollar book with absurd prices.
          for (final order in await parseOrders([
            for (var id = 1; id <= 50; id++)
              caseOrder(id, 1, 0, 1000, currency: 1, price: 1),
          ]))
            order,
          ...await parseOrders([
            caseOrder(1, 1, 0, 1000, currency: 1, price: 70000),
          ], alias: 'lake'),
          ...await parseOrders([
            caseOrder(1, 1, 0, 1000, currency: 1, price: 70000),
          ], alias: 'bazaar'),
        ];
        expect(DepthChart.impliedMarketPrice(book, usd), 70000);
        // Temple chosen: its own price, absurd as it is, prices its own orders.
        final templeOnly = DepthChart.of(
          book: book,
          filter: BookFilter(host: coordinator('temple')),
          axis: DepthAxis.price,
        );
        expect(templeOnly.window.center, 1);
        // A host with no dollar order takes the price of every coordinator.
        final euros = await parseOrders([
          caseOrder(9, 1, 0, 1000, price: 60000),
        ], alias: 'freeport');
        final freeport = DepthChart.of(
          book: [...book, ...euros],
          filter: BookFilter(host: coordinator('freeport')),
          axis: DepthAxis.price,
        );
        expect(freeport.window.center, 70000);
      },
    );

    test(
      'a median between -1 and 0 is a centre of 0, never a negative zero',
      () async {
        final chart = DepthChart.of(
          book: await parseOrders([
            caseOrder(1, 1, -0.625, 1000000),
            caseOrder(2, 0, -0.375, 1000000),
          ]),
          filter: const BookFilter(),
          axis: DepthAxis.premium,
        );
        expect(chart.window.center, 0);
        expect(chart.window.center.isNegative, isFalse);
        expect(DepthChart.wholeTowardZero(-0.5).isNegative, isFalse);
        expect(DepthChart.wholeTowardZero(-1.5), -1);
        expect(DepthChart.wholeTowardZero(2.7), 2);
      },
    );
  });

  group('the price axis', () {
    test('every currency is priced in US dollars, from the dollar orders', () async {
      final book = await parseOrders([
        // The only dollar order: 75000 at 2% gives a market price of 75000 / 1.02.
        caseOrder(1, 1, 2, 1000000, currency: 1, price: 75000),
        // Euro orders never change the dollar price.
        caseOrder(2, 1, 1, 1000000, price: 70000),
        caseOrder(3, 1, 5, 1000000, price: 1),
      ]);
      final chart = DepthChart.of(
        book: book,
        filter: const BookFilter(),
        axis: DepthAxis.price,
      );
      expect(chart.priceCurrency, usd);
      final market = 75000 / (1 + 2 / 100);
      expect(DepthChart.impliedMarketPrice(book, usd), market);
      // The euro order is placed with its premium on the dollar price, as `base_price` is.
      expect(
        shape(chart.linesIn(chart.window).sell).map((point) => point.$1),
        contains(market * (1 + 1 / 100)),
      );
      // With euros chosen, the euro orders give the price, the median of the two.
      expect(
        DepthChart.impliedMarketPrice(book, eur),
        DepthChart.median([70000 / (1 + 1 / 100), 1 / (1 + 5 / 100)]),
      );
    });

    test('the market price is the median of the prices the orders imply', () {
      expect(DepthChart.median([3, 1, 2]), 2);
      expect(DepthChart.median([4, 1, 3, 2]), 2.5);
      expect(DepthChart.median([]), isNull);
    });

    test('without a market price there is no window and no line', () async {
      final book = await parseOrders([
        caseOrder(1, 1, 2, 1000000, price: null),
        caseOrder(2, 0, 2, 1000000, currency: 1, price: null),
      ]);
      final chart = DepthChart.of(
        book: book,
        filter: const BookFilter(),
        axis: DepthAxis.price,
      );
      expect(chart.window.isDrawable, isFalse);
      expect(chart.window.canZoomIn, isFalse);
      expect(chart.window.canZoomOut, isFalse);
      final lines = chart.linesIn(chart.window);
      expect(lines.buy, isEmpty);
      expect(lines.sell, isEmpty);
      expect(lines.top, 1);
    });

    test(
      'one price only opens ± 8% of it, the width of the premium axis',
      () async {
        final chart = DepthChart.of(
          book: await parseOrders([caseOrder(1, 1, 0, 1000000, price: 50000)]),
          filter: BookFilter(currency: eur),
          axis: DepthAxis.price,
        );
        expect(
          chart.window,
          const DepthWindow(center: 50000, halfRange: 4000, step: 400),
        );
        expect(shape(chart.linesIn(chart.window).sell), [
          (50000, 0, null),
          (50000, 0.01, 1),
          (54000, 0.01, null),
        ]);
      },
    );
  });

  group('what an order adds', () {
    test(
      'the sats its coordinator gives, else its largest amount at its price',
      () async {
        final orders = await parseOrders([
          caseOrder(1, 1, 2, 2500000),
          bookOrder(
            id: 2,
            minAmount: 50,
            maxAmount: 300,
            satoshisNow: null,
            price: 60000,
            makerSeed: 2,
          ),
          bookOrder(id: 3, satoshisNow: null, price: null, makerSeed: 3),
        ]);
        expect(DepthChart.btcOf(orders[0]), 0.025);
        expect(DepthChart.btcOf(orders[1]), 300 / 60000);
        expect(DepthChart.btcOf(orders[2]), 0);
      },
    );

    test(
      'never more than every bitcoin there will be, nothing when absurd',
      () async {
        final orders = await parseOrders([
          caseOrder(1, 1, 2, 2100000000000000),
          // The largest amount the package reads, at a tiny price: more bitcoin than exists.
          bookOrder(
            id: 2,
            amount: 1e10,
            satoshisNow: null,
            price: 1e-6,
            makerSeed: 2,
          ),
          // At a price so small that the amount is not a finite number.
          bookOrder(
            id: 3,
            amount: 1e10,
            satoshisNow: null,
            price: 1e-300,
            makerSeed: 3,
          ),
        ]);
        expect(DepthChart.btcOf(orders[0]), DepthChart.maxBtc);
        expect(DepthChart.btcOf(orders[1]), DepthChart.maxBtc);
        expect(DepthChart.btcOf(orders[2]), 0);
      },
    );

    test(
      'the chart filter keeps both sides, every method and the swaps',
      () async {
        final orders = await parseOrders([
          caseOrder(1, 1, 2, 1),
          caseOrder(2, 0, 2, 1),
          caseOrder(3, 1, 2, 1, currency: 1000, price: 1.001),
          caseOrder(4, 1, 2, 1, currency: 1),
        ]);
        const any = BookFilter(side: BookSide.buy, paymentMethod: 'Revolut');
        expect(orders.where(any.showsInDepthChart).length, 4);
        final euros = BookFilter(currency: eur);
        expect(
          [for (final o in orders.where(euros.showsInDepthChart)) o.id],
          [1, 2],
        );
        final lake = BookFilter(host: coordinator('lake'));
        expect(orders.where(lake.showsInDepthChart), isEmpty);
      },
    );
  });

  group('hostile numbers', () {
    test('an empty book gives a premium window on 0 and no line', () {
      final chart = DepthChart.of(
        book: const [],
        filter: const BookFilter(),
        axis: DepthAxis.premium,
      );
      expect(
        chart.window,
        const DepthWindow(center: 0, halfRange: 8, step: 0.5),
      );
      final lines = chart.linesIn(chart.window);
      expect(lines.buy, isEmpty);
      expect(lines.sell, isEmpty);
      expect(lines.buyOrders, 0);
      expect(lines.top, 1);
    });

    test('orders of zero sats draw flat lines on the axis', () async {
      final chart = DepthChart.of(
        book: await parseOrders([caseOrder(1, 1, 2, 0), caseOrder(2, 0, 1, 0)]),
        filter: const BookFilter(),
        axis: DepthAxis.premium,
      );
      final lines = chart.linesIn(chart.window);
      expect(lines.sell.every((point) => point.btc == 0), isTrue);
      expect(lines.top, 1);
    });

    test('two huge middle values do not overflow the median', () {
      expect(DepthChart.median([1.7e308, 1.7e308]), 1.7e308);
      expect(DepthChart.median([-1.7e308, -1.7e308]), -1.7e308);
    });

    test(
      'the largest premium the package reads still draws, on its own axis',
      () async {
        // An order priced in sats can have any premium the coordinator computes, up to 12 digits as the package reads it.
        final huge = await parseOrders([
          for (var id = 1; id <= 3; id++)
            bookOrder(
              id: id,
              premium: 999999999999,
              satoshisNow: 1000,
              makerSeed: id,
              isExplicit: true,
              satoshis: 1000,
            ),
        ]);
        final chart = DepthChart.of(
          book: huge,
          filter: const BookFilter(),
          axis: DepthAxis.premium,
        );
        expect(chart.window.center, 999999999999);
        expect(chart.window.isDrawable, isTrue);
        final lines = chart.linesIn(chart.window);
        expect(lines.sellOrders, 3);
        expect(lines.top, closeTo(3000 / 100000000, 1e-18));
      },
    );

    test('a price beyond the bound of the labels is not drawn', () async {
      final chart = DepthChart.of(
        book: await parseOrders([caseOrder(1, 1, 0, 1000, price: 1e308)]),
        filter: BookFilter(currency: eur),
        axis: DepthAxis.price,
      );
      expect(chart.window.center, 1e308);
      expect(chart.window.isDrawable, isFalse);
      expect(chart.window.canZoomOut, isFalse);
      expect(chart.linesIn(chart.window).sell, isEmpty);
      // A premium that would take a price past every finite number leaves the order out of the axis.
      final far = await parseOrders([
        bookOrder(
          id: 2,
          premium: 999999999999,
          price: 1e308,
          makerSeed: 2,
          isExplicit: true,
          satoshis: 1000,
        ),
      ]);
      expect(DepthChart.priceAt(1e300, far.first), isNull);
    });

    test('a window never widens past the bound of its labels', () {
      var window = const DepthWindow(center: 9e14, halfRange: 5e13, step: 5e13);
      for (var i = 0; i < 10; i++) {
        window = window.zoomedOut();
      }
      expect(window.halfRange, 1e14);
      // The same below zero: the lower bound stops the widening.
      var below = const DepthWindow(center: -9e14, halfRange: 5e13, step: 5e13);
      for (var i = 0; i < 10; i++) {
        below = below.zoomedOut();
      }
      expect(below.min, greaterThanOrEqualTo(-DepthWindow.maxMagnitude));
      expect(below.halfRange, 1e14);
      expect(window.max, lessThanOrEqualTo(DepthWindow.maxMagnitude));
      expect(window.isDrawable, isTrue);
      expect(
        const DepthWindow(center: 0, halfRange: 1, step: double.nan).canZoomOut,
        isFalse,
      );
      expect(
        const DepthWindow(center: double.nan, halfRange: 1, step: 1).isDrawable,
        isFalse,
      );
      expect(
        const DepthWindow(
          center: 0,
          halfRange: double.infinity,
          step: 1,
        ).isDrawable,
        isFalse,
      );
      expect(
        const DepthWindow(center: 5, halfRange: 0, step: 0).isDrawable,
        isFalse,
      );
    });

    test(
      'a premium of -100 has a price of zero, still inside the axis',
      () async {
        final chart = DepthChart.of(
          book: await parseOrders([
            caseOrder(1, 1, 0, 1000000, price: 50000),
            caseOrder(2, 0, -100, 1000000, price: 50000),
          ]),
          filter: BookFilter(currency: eur),
          axis: DepthAxis.price,
        );
        // The order at -100% implies no market price (its factor is zero), the other gives 50000.
        expect(chart.window.center, 25000);
        expect(chart.window.halfRange, 25000);
      },
    );

    test('thousands of orders are built at once', () async {
      final book = await parseOrders([
        for (var id = 1; id <= 1000; id++)
          caseOrder(id, id.isEven ? 1 : 0, (id % 200 - 100) / 10, 10000 + id),
      ]);
      final many = [for (var copy = 0; copy < 8; copy++) ...book];
      final watch = Stopwatch()..start();
      final chart = DepthChart.of(
        book: many,
        filter: const BookFilter(),
        axis: DepthAxis.premium,
      );
      final lines = chart.linesIn(chart.window);
      watch.stop();
      expect(lines.buy, isNotEmpty);
      expect(lines.sell, isNotEmpty);
      expect(lines.top.isFinite, isTrue);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });
}
