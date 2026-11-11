import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:bull_ui/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/depth_chart.dart';
import 'package:p2p/src/ui/depth_chart_view.dart';
import 'package:p2p/src/ui/order_details_screen.dart';
import 'package:p2p/src/ui/search_order_dialog.dart';
import 'package:p2p/src/ui/widgets/robot_avatar.dart';
import 'package:p2p/testing.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// An order of these tests, priced at a market of 80000 EUR: its premiums make 1 + premium / 100 exact in binary, so prices and the centre are exact.
Map<String, Object?> pricedOrder(
  int id, {
  required int type,
  required double premium,
  required int sats,
  int currency = 2,
}) => bookOrder(
  id: id,
  type: type,
  premium: premium,
  satoshisNow: sats,
  price: 80000 * (1 + premium / 100),
  currency: currency,
  makerSeed: id,
);

void main() {
  late GetIt locator;
  late FakeTransport transport;
  late StreamController<P2pTorState> tor;

  /// Two sell orders on temple and two buy orders on lake, all in euros.
  Map<String, List<Map<String, Object?>>> books() => {
    'temple': [
      pricedOrder(1, type: 1, premium: 0, sats: 1000000),
      pricedOrder(2, type: 1, premium: 3.125, sats: 2000000),
    ],
    'lake': [
      pricedOrder(3, type: 0, premium: -3.125, sats: 3000000),
      pricedOrder(4, type: 0, premium: 1.5625, sats: 500000),
    ],
  };

  setUp(() {
    locator = GetIt.asNewInstance();
    tor = StreamController<P2pTorState>.broadcast();
    transport = FakeTransport(books: books());
  });

  tearDown(() async {
    await tor.close();
    await locator.reset();
  });

  /// Opens the book on mainnet with [transport], Tor ready, then the « Chart » view.
  Future<void> openChart(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    bool torReady = true,
    bool showChart = true,
  }) async {
    setUpP2pForTesting(
      locator,
      transport: transport,
      torStates: () => tor.stream,
      clock: () => testNow,
    );
    usePhoneScreen(tester);
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [
        const P2pFeature().route(
          locator,
          network: (_) => RobosatsNetwork.mainnet,
        ),
      ],
    );
    await tester.pumpWidget(routerHarness(router, locale: locale));
    await settle(tester);
    if (torReady) tor.add(P2pTorState.ready);
    await settle(tester);
    if (!showChart) return;
    final l10n = lookupP2pLocalizations(locale);
    await tester.tap(find.text(l10n.p2pBookViewChart));
    await settle(tester);
  }

  final chart = find.byType(DepthChartView);

  /// The box the chart is painted in, axes and labels included.
  final plot = find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint &&
        widget.painter.runtimeType.toString() == '_DepthChartPainter',
  );

  IconButton zoomButton(WidgetTester tester, String tooltip) =>
      tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );

  /// A point inside the plot, near its top-right or top-left corner.
  Offset nearTopRight(WidgetTester tester) =>
      tester.getTopRight(plot) + const Offset(-14, 14);
  Offset nearTopLeft(WidgetTester tester) {
    final box = tester.getRect(plot);
    // The plot starts after the labels of the vertical axis: a third of the way in is past them.
    return Offset(box.left + box.width / 3, box.top + 14);
  }

  /// A point of the box outside the plot: on the labels of the vertical axis.
  Offset onTheLabels(WidgetTester tester) {
    final box = tester.getRect(plot);
    return Offset(box.left + 2, box.center.dy);
  }

  /// Every coordinator of mainnet, by short alias.
  final everyCoordinator = {
    for (final coordinator in Federation.robosats.on(RobosatsNetwork.mainnet))
      coordinator.shortAlias,
  };

  /// The orders of the review's scenario: one side of [count] orders priced in sats at the largest premium the package reads.
  List<Map<String, Object?>> flood(int type, {int count = 40}) => [
    for (var id = 1; id <= count; id++)
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

  testWidgets(
    '« Chart » shows the depth chart of the book, centred on its median premium',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await openChart(tester);

      expect(chart, findsOneWidget);
      // The chart replaces the list and its filter sentence, as on a phone in the official client.
      expect(find.text('I want to'), findsNothing);
      expect(find.text('Seller'), findsNothing);
      // « Chart », the axis, and the centre between the zoom buttons: temple's median premium, 1.5625, and lake's, -0.78125, have a median of 0.390625, cut to 0.
      expect(find.text('Chart'), findsNWidgets(2));
      expect(find.text('Premium'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.byTooltip('Zoom out'), findsOneWidget);
      expect(find.byTooltip('Zoom in'), findsOneWidget);
      // A screen reader reads a summary.
      expect(
        find.bySemanticsLabel(
          'Depth chart centered on 0%: 2 buy orders and 2 sell orders.',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'the chart asks nothing: opening, zooming, both axes, a long press, a hover',
    (tester) async {
      await openChart(tester, showChart: false);
      final asked = transport.requested.length;
      expect(asked, everyCoordinator.length);

      await tester.tap(find.text('Chart'));
      await settle(tester);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
      for (final axis in ['Premium', 'Price', 'Price', 'Premium']) {
        await tester.tap(find.text(axis).last);
        await settle(tester);
      }
      final finger = await tester.startGesture(nearTopRight(tester));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      expect(find.byType(OrderTooltip), findsOneWidget);
      await finger.up();
      await tester.pump();

      // A mouse shows the order it hovers, as in the official client, and nothing once it leaves the plot.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(nearTopLeft(tester));
      await tester.pump();
      expect(find.byType(OrderTooltip), findsOneWidget);
      await mouse.moveTo(onTheLabels(tester));
      await tester.pump();
      expect(find.byType(OrderTooltip), findsNothing);

      expect(transport.requested.length, asked);
    },
  );

  testWidgets('a tap opens the order nearest to it, inside the plot only', (
    tester,
  ) async {
    await openChart(tester);

    // On the labels of the vertical axis, outside the plot: nothing.
    await tester.tapAt(onTheLabels(tester));
    await settle(tester);
    expect(find.byType(OrderDetailsScreen), findsNothing);

    // Top right: the second sell order, the highest step on the right.
    await tester.tapAt(nearTopRight(tester));
    await settle(tester);
    expect(find.byType(OrderDetailsScreen), findsOneWidget);
    expect(find.text('# 2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    // Back on the book, the chart is still shown; top left is the buy order at -3.125%, the top of the buy line.
    expect(chart, findsOneWidget);
    await tester.tapAt(nearTopLeft(tester));
    await settle(tester);
    expect(find.text('# 3'), findsOneWidget);
  });

  testWidgets(
    'a long press shows the order under the finger and its coordinator, and lets go',
    (tester) async {
      await openChart(tester);

      // Outside the plot, a long press shows nothing.
      final outside = await tester.startGesture(onTheLabels(tester));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      expect(find.byType(OrderTooltip), findsNothing);
      await outside.up();
      await tester.pump();

      final at = nearTopRight(tester);
      final gesture = await tester.startGesture(at);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      final tooltip = find.byType(OrderTooltip);
      expect(tooltip, findsOneWidget);
      Finder inTooltip(Finder finder) =>
          find.descendant(of: tooltip, matching: finder);
      expect(
        inTooltip(find.text('100 EUR', findRichText: true)),
        findsOneWidget,
      );
      // The payment methods as the list writes them, in the order of the official list.
      expect(inTooltip(find.text('Instant SEPA · Revolut')), findsOneWidget);
      expect(inTooltip(find.text('Temple of Sats')), findsOneWidget);
      expect(
        tester.widget<RobotAvatar>(find.byType(RobotAvatar)).seed,
        hashId(2),
      );
      // Near the right edge, the tooltip opens on the left of the finger, inside the chart.
      expect(tester.getRect(tooltip).right, lessThanOrEqualTo(at.dx));
      expect(
        tester.getRect(tooltip).left,
        greaterThanOrEqualTo(tester.getRect(plot).left),
      );

      await gesture.moveTo(nearTopLeft(tester));
      await tester.pump();
      expect(
        tester.widget<RobotAvatar>(find.byType(RobotAvatar)).seed,
        hashId(3),
      );
      expect(inTooltip(find.text('TheBigLake')), findsOneWidget);

      await gesture.up();
      await tester.pump();
      expect(find.byType(OrderTooltip), findsNothing);
      // A long press opens nothing.
      expect(find.byType(OrderDetailsScreen), findsNothing);
    },
  );

  testWidgets(
    'zoom: « + » down to a half range of 1, and a new book puts it back',
    (tester) async {
      await openChart(tester);
      expect(zoomButton(tester, 'Zoom in').onPressed, isNotNull);

      for (var i = 0; i < 14; i++) {
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pump();
      }
      expect(zoomButton(tester, 'Zoom in').onPressed, isNull);
      expect(zoomButton(tester, 'Zoom out').onPressed, isNotNull);
      // The centre does not move.
      expect(find.text('0%'), findsOneWidget);

      // Pulling the chart down asks every coordinator again, and the new book opens on its first window.
      await tester.fling(chart, const Offset(0, 400), 1000);
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(zoomButton(tester, 'Zoom in').onPressed, isNotNull);
    },
  );

  testWidgets(
    '« Price » prices the book in its currency, or in dollars for every currency',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await openChart(tester);

      await tester.tap(find.text('Premium'));
      await settle(tester);
      expect(find.text('Price'), findsOneWidget);
      await tester.tap(find.text('Price'));
      await settle(tester);

      // Every currency is priced in US dollars, and this book has no dollar order: there is no price axis, and no value between the zoom buttons.
      expect(find.text('Price'), findsOneWidget);
      expect(find.text('-'), findsNothing);
      expect(find.textContaining('USD'), findsNothing);
      expect(zoomButton(tester, 'Zoom in').onPressed, isNull);
      expect(zoomButton(tester, 'Zoom out').onPressed, isNull);
      expect(
        find.bySemanticsLabel('Depth chart: nothing to draw on this axis.'),
        findsOneWidget,
      );

      // With euros chosen in the list, the euro orders give the price.
      await tester.tap(find.text('List'));
      await settle(tester);
      await tester.tap(find.text('ANY').at(1));
      await settle(tester);
      await tester.tap(find.text('EUR').last);
      await settle(tester);
      await tester.tap(find.text('Chart'));
      await settle(tester);
      // The view is built again on « Premium »; « Price » centres on the median of temple's median price, 81,250, and lake's, 79,375.
      await tester.tap(find.text('Premium'));
      await settle(tester);
      await tester.tap(find.text('Price'));
      await settle(tester);
      expect(find.text('80,312 EUR'), findsOneWidget);
      expect(zoomButton(tester, 'Zoom in').onPressed, isNotNull);
      semantics.dispose();
    },
  );

  testWidgets('one side only draws one line', (tester) async {
    final semantics = tester.ensureSemantics();
    transport = FakeTransport(books: {'temple': books()['temple'] ?? []});
    await openChart(tester);

    expect(
      find.bySemanticsLabel(
        'Depth chart centered on 1%: 0 buy orders and 2 sell orders.',
      ),
      findsOneWidget,
    );
    await tester.tapAt(nearTopLeft(tester));
    await settle(tester);
    expect(find.text('# 2'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'the chart ignores the side of the filter, which can empty the list',
    (tester) async {
      transport = FakeTransport(books: {'temple': books()['temple'] ?? []});
      await openChart(tester, showChart: false);
      // « I want to sell » shows the buy orders, and this book has none.
      await tester.tap(find.text('ANY').first);
      await settle(tester);
      await tester.tap(find.text('Sell').last);
      await settle(tester);
      expect(find.text('No orders found to sell BTC for ANY'), findsOneWidget);

      await tester.tap(find.text('Chart'));
      await settle(tester);
      expect(chart, findsOneWidget);
      expect(find.text('No orders found to sell BTC for ANY'), findsNothing);
    },
  );

  testWidgets(
    'a coordinator that floods the book: choosing a host brings the chart back',
    (tester) async {
      final semantics = tester.ensureSemantics();
      // The review's scenario: 80 orders at the largest premium on two coordinators, 30 honest ones on lake.
      transport = FakeTransport(
        books: {
          'temple': flood(1),
          'bazaar': flood(0),
          'lake': [
            for (var id = 1; id <= 30; id++)
              bookOrder(
                id: id,
                type: id.isEven ? 1 : 0,
                premium: (id - 15) / 4,
                makerSeed: id,
              ),
          ],
        },
      );
      await openChart(tester);
      // Two coordinators out of three, two votes out of three: the flood sets the centre.
      expect(find.text('999,999,999,999%'), findsOneWidget);

      await tester.tap(find.text('List'));
      await settle(tester);
      await tester.tap(find.text('ANY').last);
      await settle(tester);
      await tester.tap(find.text('TheBigLake').last);
      await settle(tester);
      await tester.tap(find.text('Chart'));
      await settle(tester);
      expect(find.text('0%'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Depth chart centered on 0%: 15 buy orders and 15 sell orders.',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('hostile numbers are drawn without error, or not at all', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    transport = FakeTransport(
      books: {
        'temple': [
          // The largest premium and amount the package reads, orders priced in sats, in dollars.
          bookOrder(
            id: 1,
            currency: 1,
            premium: 999999999999,
            satoshisNow: 2100000000000000,
            amount: 1e10,
            isExplicit: true,
            satoshis: 2100000000000000,
            makerSeed: 1,
          ),
          bookOrder(
            id: 2,
            type: 0,
            currency: 1,
            premium: 999999999999,
            satoshisNow: 0,
            isExplicit: true,
            satoshis: 1,
            makerSeed: 2,
          ),
          // A euro order at a price beyond the bound of the labels, and no sats.
          bookOrder(
            id: 3,
            premium: 0,
            price: 1e308,
            satoshisNow: null,
            makerSeed: 3,
          ),
        ],
      },
    );
    await openChart(tester);
    expect(tester.takeException(), isNull);
    expect(chart, findsOneWidget);
    // The median premium, 999999999999%, is far but within the bound: the chart draws it.
    expect(find.text('999,999,999,999%'), findsOneWidget);
    expect(zoomButton(tester, 'Zoom out').onPressed, isNotNull);
    await tester.tapAt(nearTopRight(tester));
    await settle(tester);
    expect(find.byType(OrderDetailsScreen), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);

    // On the price axis, in euros, the market price is 1e308: beyond the bound, nothing is drawn.
    await tester.tap(find.text('List'));
    await settle(tester);
    await tester.tap(find.text('ANY').at(1));
    await settle(tester);
    await tester.tap(find.text('EUR').last);
    await settle(tester);
    await tester.tap(find.text('Chart'));
    await settle(tester);
    await tester.tap(find.text('Premium'));
    await settle(tester);
    await tester.tap(find.text('Price'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      find.bySemanticsLabel('Depth chart: nothing to draw on this axis.'),
      findsOneWidget,
    );
    expect(zoomButton(tester, 'Zoom in').onPressed, isNull);
    expect(zoomButton(tester, 'Zoom out').onPressed, isNull);
    // A tap where nothing is drawn opens nothing.
    await tester.tapAt(nearTopRight(tester));
    await settle(tester);
    expect(find.byType(OrderDetailsScreen), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'every coordinator offline: their state and « Retry » above the empty book',
    (tester) async {
      transport = FakeTransport(
        failures: {
          for (final alias in everyCoordinator)
            alias: const CoordinatorTimedOut(),
        },
      );
      await openChart(tester);

      expect(chart, findsNothing);
      // As above the list: a failure is not an empty book.
      expect(find.text('Temple of Sats · Coordinator offline'), findsOneWidget);
      expect(find.text('TheBigLake · Coordinator offline'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No orders found to buy BTC for ANY'), findsOneWidget);

      // « Retry » from the chart asks every one of them again, and the chart shows what they now give.
      transport
        ..failures.clear()
        ..requested.clear()
        ..books.addAll(books());
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(transport.requested.toSet(), {
        for (final alias in everyCoordinator) '$alias/api/book/',
      });
      expect(find.text('Retry'), findsNothing);
      expect(chart, findsOneWidget);
    },
  );

  testWidgets('one coordinator offline among several: shown above the chart', (
    tester,
  ) async {
    transport = FakeTransport(
      books: books(),
      failures: {'bazaar': const CoordinatorTimedOut()},
    );
    await openChart(tester);

    expect(chart, findsOneWidget);
    expect(find.text('LibreBazaar · Coordinator offline'), findsOneWidget);
    transport
      ..failures.clear()
      ..requested.clear();
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(transport.requested, ['bazaar/api/book/']);
    expect(find.text('LibreBazaar · Coordinator offline'), findsNothing);
    expect(chart, findsOneWidget);
  });

  testWidgets('an empty book says so, as the list does', (tester) async {
    transport = FakeTransport();
    await openChart(tester);

    expect(chart, findsNothing);
    expect(find.text('No orders found to buy BTC for ANY'), findsOneWidget);
    expect(find.text('Be the first one to create an order'), findsOneWidget);
  });

  testWidgets('a wait while no order has arrived', (tester) async {
    transport = FakeTransport(books: books(), held: {...everyCoordinator});
    await openChart(tester);

    expect(chart, findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // A coordinator with an empty book answers: the others are still loading, as the line above says, so the book is not said empty.
    transport.release('bazaar');
    await settle(tester);
    expect(
      find.text(
        '${everyCoordinator.length - 1} coordinators are still loading',
      ),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    expect(find.text('No orders found to buy BTC for ANY'), findsNothing);

    transport.release('temple');
    await settle(tester);
    expect(chart, findsOneWidget);
  });

  testWidgets('« Search » keeps the chart, and « List » goes back', (
    tester,
  ) async {
    await openChart(tester);

    await tester.tap(find.text('Search'));
    await settle(tester);
    expect(find.byType(SearchOrderDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(SearchOrderDialog),
        matching: find.text('Cancel'),
      ),
    );
    await settle(tester);
    expect(chart, findsOneWidget);
    Color? colour(String label) => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(BullSegmented).last,
            matching: find.text(label),
          ),
        )
        .style
        ?.color;
    expect(colour('Chart'), testBullTheme.primary);
    expect(colour('Map'), isNot(testBullTheme.primary));

    // « Map » is not built yet: choosing it changes nothing.
    await tester.tap(find.text('Map'));
    await settle(tester);
    expect(chart, findsOneWidget);

    await tester.tap(find.text('List'));
    await settle(tester);
    expect(chart, findsNothing);
    expect(find.text('Seller'), findsNWidgets(2));
  });

  testWidgets('in French', (tester) async {
    final semantics = tester.ensureSemantics();
    await openChart(tester, locale: const Locale('fr'));

    expect(find.text('Graphique'), findsNWidgets(2));
    expect(find.text('Prime'), findsOneWidget);
    expect(find.text('0\u00a0%'), findsOneWidget);
    expect(find.byTooltip('Zoom arrière'), findsOneWidget);
    expect(find.byTooltip('Zoom avant'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        "Graphique de profondeur centré sur 0\u00a0% : 2 ordres d'achat et 2 ordres de vente.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Prime'));
    await settle(tester);
    await tester.tap(find.text('Prix'));
    await settle(tester);
    expect(
      find.bySemanticsLabel(
        'Graphique de profondeur : rien à tracer sur cet axe.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('a median between -1 and 0 is written « 0% », never « -0% »', (
    tester,
  ) async {
    transport = FakeTransport(
      books: {
        'temple': [
          pricedOrder(1, type: 1, premium: -0.625, sats: 1000000),
          pricedOrder(2, type: 0, premium: -0.375, sats: 1000000),
        ],
      },
    );
    await openChart(tester);
    expect(find.text('0%'), findsOneWidget);
    expect(find.textContaining('-0'), findsNothing);
  });

  testWidgets('« -0 % » in French neither', (tester) async {
    transport = FakeTransport(
      books: {
        'temple': [
          pricedOrder(1, type: 1, premium: -0.625, sats: 1000000),
          pricedOrder(2, type: 0, premium: -0.375, sats: 1000000),
        ],
      },
    );
    await openChart(tester, locale: const Locale('fr'));
    expect(find.text('0\u00a0%'), findsOneWidget);
    expect(find.textContaining('-0'), findsNothing);
  });

  test(
    'the labels of the vertical axis never take more than half of the width',
    () {
      final layout = DepthChartLayout.of(
        size: const Size(400, 300),
        window: const DepthWindow(center: 0, halfRange: 8, step: 0.5),
        top: 1,
        measure: (label) => Size(label.length * 10.0, 12),
        xLabel: (value) => '$value',
        yLabel: (value) => 'x' * 100,
      );
      expect(layout?.plot.left, 200);
      // Between the legend and the tick: a label that long is cut there.
      expect(
        layout?.yLabelWidth,
        200 - DepthChartLayout.tickSize - DepthChartLayout.gap * 2 - 12,
      );
    },
  );
}
