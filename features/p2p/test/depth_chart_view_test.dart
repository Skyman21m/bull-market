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

  testWidgets(
    '« Chart » shows the depth chart of the book, centred on the median premium',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await openChart(tester);

      expect(chart, findsOneWidget);
      // The chart replaces the list and its filter sentence, as on a phone in the official client.
      expect(find.text('I want to'), findsNothing);
      expect(find.text('Seller'), findsNothing);
      // « Chart », the axis, and the centre between the zoom buttons: premiums -3.125, 0, 1.5625 and 3.125 have a median of 0.78125, cut to 0.
      expect(find.text('Chart'), findsNWidgets(2));
      expect(find.text('Premium'), findsOneWidget);
      expect(find.text('0.00%'), findsOneWidget);
      expect(find.byTooltip('Zoom out'), findsOneWidget);
      expect(find.byTooltip('Zoom in'), findsOneWidget);
      // A screen reader reads a summary.
      expect(
        find.bySemanticsLabel(
          'Depth chart centered on 0.00%: 2 buy orders and 2 sell orders.',
        ),
        findsOneWidget,
      );
      // Only the books were asked: the chart needs no other request.
      expect(
        transport.requested.every((request) => request.endsWith('/api/book/')),
        isTrue,
      );
      semantics.dispose();
    },
  );

  testWidgets('a tap opens the order nearest to it', (tester) async {
    await openChart(tester);

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

  testWidgets('a long press shows the order under the finger, and lets go', (
    tester,
  ) async {
    await openChart(tester);

    final gesture = await tester.startGesture(nearTopRight(tester));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    expect(find.byType(OrderTooltip), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(OrderTooltip),
        matching: find.text('100 EUR', findRichText: true),
      ),
      findsOneWidget,
    );
    // The payment methods as the list writes them, in the order of the official list.
    expect(find.text('Instant SEPA · Revolut'), findsOneWidget);
    expect(
      tester.widget<RobotAvatar>(find.byType(RobotAvatar)).seed,
      hashId(2),
    );

    await gesture.moveTo(nearTopLeft(tester));
    await tester.pump();
    expect(
      tester.widget<RobotAvatar>(find.byType(RobotAvatar)).seed,
      hashId(3),
    );

    await gesture.up();
    await tester.pump();
    expect(find.byType(OrderTooltip), findsNothing);
    // A long press opens nothing.
    expect(find.byType(OrderDetailsScreen), findsNothing);
  });

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
      expect(find.text('0.00%'), findsOneWidget);

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

      // Every currency is priced in US dollars, and this book has no dollar order: there is no price axis.
      expect(find.text('Price'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
      expect(zoomButton(tester, 'Zoom in').onPressed, isNull);
      expect(zoomButton(tester, 'Zoom out').onPressed, isNull);
      expect(
        find.bySemanticsLabel(
          'Depth chart centered on -: 0 buy orders and 0 sell orders.',
        ),
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
      // The view is built again on « Premium »; choosing « Price » shows the median price, 80,625 EUR.
      await tester.tap(find.text('Premium'));
      await settle(tester);
      await tester.tap(find.text('Price'));
      await settle(tester);
      expect(find.text('80,625 EUR'), findsOneWidget);
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
        'Depth chart centered on 1.00%: 0 buy orders and 2 sell orders.',
      ),
      findsOneWidget,
    );
    await tester.tapAt(nearTopLeft(tester));
    await settle(tester);
    expect(find.text('# 2'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('hostile numbers are drawn without error, or not at all', (
    tester,
  ) async {
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
    expect(find.text('1.00e+12%'), findsNothing);
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
    expect(find.text('-'), findsOneWidget);
    expect(zoomButton(tester, 'Zoom in').onPressed, isNull);
    expect(zoomButton(tester, 'Zoom out').onPressed, isNull);
    // A tap where nothing is drawn opens nothing.
    await tester.tapAt(nearTopRight(tester));
    await settle(tester);
    expect(find.byType(OrderDetailsScreen), findsNothing);
  });

  testWidgets('an empty book says so, as the list does', (tester) async {
    transport = FakeTransport();
    await openChart(tester);

    expect(chart, findsNothing);
    expect(find.text('No orders found to buy BTC for ANY'), findsOneWidget);
    expect(find.text('Be the first one to create an order'), findsOneWidget);
  });

  testWidgets('a wait while no order has arrived', (tester) async {
    transport = FakeTransport(
      books: books(),
      held: {
        for (final coordinator in Federation.robosats.on(
          RobosatsNetwork.mainnet,
        ))
          coordinator.shortAlias,
      },
    );
    await openChart(tester);

    expect(chart, findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

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
    expect(find.text('0,00\u00a0%'), findsOneWidget);
    expect(find.byTooltip('Zoom arrière'), findsOneWidget);
    expect(find.byTooltip('Zoom avant'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        "Graphique de profondeur centré sur 0,00\u00a0% : 2 ordres d'achat et 2 ordres de vente.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Prime'));
    await settle(tester);
    expect(find.text('Prix'), findsOneWidget);
    semantics.dispose();
  });
}
