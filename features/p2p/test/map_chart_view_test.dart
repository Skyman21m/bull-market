import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:bull_ui/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/map_marks.dart';
import 'package:p2p/src/domain/web_mercator.dart';
import 'package:p2p/src/ui/depth_chart_view.dart';
import 'package:p2p/src/ui/map_chart_view.dart';
import 'package:p2p/src/ui/order_details_screen.dart';
import 'package:p2p/src/ui/search_order_dialog.dart';
import 'package:p2p/src/ui/widgets/coordinators_row.dart';
import 'package:p2p/src/ui/widgets/offer_row.dart';
import 'package:p2p/testing.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// An order at [latitude] and [longitude], written as a coordinator writes them, as decimal text.
Map<String, Object?> located(
  int id,
  Object latitude,
  Object longitude, {
  int type = 1,
  int currency = 2,
}) => {
  ...bookOrder(id: id, type: type, currency: currency, makerSeed: id),
  'latitude': '$latitude',
  'longitude': '$longitude',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GetIt locator;
  late FakeTransport transport;
  late StreamController<P2pTorState> tor;

  /// Two sellers in Paris and Berlin on temple, a buyer in São Paulo on lake, and an order without a position on each.
  Map<String, List<Map<String, Object?>>> books() => {
    'temple': [
      located(1, '48.8566', '2.3522'),
      located(2, '52.5200', '13.4050'),
      bookOrder(id: 3, makerSeed: 3),
    ],
    'lake': [
      located(4, '-23.5505', '-46.6333', type: 0),
      bookOrder(id: 5, type: 0, makerSeed: 5),
    ],
  };

  setUpAll(() async {
    // The world map is read from the test's bundle once, out of the fake clock of the widget tests.
    expect(await MapChartView.worldOf(rootBundle), isNotNull);
  });

  setUp(() {
    locator = GetIt.asNewInstance();
    tor = StreamController<P2pTorState>.broadcast();
    transport = FakeTransport(books: books());
  });

  tearDown(() async {
    await tor.close();
    await locator.reset();
  });

  /// Opens the book on mainnet with [transport], Tor ready, then the « Map » view.
  Future<void> openMap(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    bool showMap = true,
    Size? screen,
    double textScale = 1,
    AssetBundle? bundle,
  }) async {
    setUpP2pForTesting(
      locator,
      transport: transport,
      torStates: () => tor.stream,
      clock: () => testNow,
    );
    if (screen == null) {
      usePhoneScreen(tester);
    } else {
      tester.view
        ..physicalSize = screen * 2
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [
        const P2pFeature().route(
          locator,
          network: (_) => RobosatsNetwork.mainnet,
        ),
      ],
    );
    await tester.pumpWidget(
      bundle == null
          ? routerHarness(router, locale: locale)
          : DefaultAssetBundle(
              bundle: bundle,
              child: routerHarness(router, locale: locale),
            ),
    );
    await settle(tester);
    tor.add(P2pTorState.ready);
    await settle(tester);
    if (!showMap) return;
    final l10n = lookupP2pLocalizations(locale);
    await tester.tap(find.text(l10n.p2pBookViewMap));
    await settle(tester);
  }

  final map = find.byType(MapChartView);
  final paint = find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is MapChartPainter,
  );

  MapChartPainter painter(WidgetTester tester) =>
      switch (tester.widget<CustomPaint>(paint).painter) {
        final MapChartPainter painter => painter,
        _ => throw StateError('no map'),
      };

  MapLayout layout(WidgetTester tester) => painter(tester).layout;

  /// Where on the screen the mark that [matches] is drawn, and the mark.
  (MapMark, Offset) mark(
    WidgetTester tester,
    bool Function(MapMark mark) matches,
  ) {
    final origin = tester.getTopLeft(paint);
    for (final (mark, at) in layout(tester).drawn) {
      if (matches(mark)) return (mark, origin + at);
    }
    throw StateError('no such mark');
  }

  /// Where a finger lands on the pin of the order [id]: the middle of the pin.
  Offset pinOf(WidgetTester tester, int id) => mark(
    tester,
    (mark) => mark is MapPin && mark.order.id == id,
  ).$2.translate(0, -MapChartPainter.pinHeight / 2);

  /// Where the group holding the order [id] is drawn.
  Offset groupOf(WidgetTester tester, int id) => mark(
    tester,
    (mark) => mark is MapGroup && mark.pins.any((pin) => pin.order.id == id),
  ).$2;

  /// The ids of the orders of each mark drawn, a pin as one id.
  List<List<int>> drawnIds(WidgetTester tester) => [
    for (final (mark, _) in layout(tester).drawn)
      switch (mark) {
        MapPin(:final order) => [order.id],
        MapGroup(:final pins) => [for (final pin in pins) pin.order.id],
      },
  ];

  /// Every coordinator of mainnet, by short alias.
  final everyCoordinator = {
    for (final coordinator in Federation.robosats.on(RobosatsNetwork.mainnet))
      coordinator.shortAlias,
  };

  /// A text of the screen that is shown, not one of the forms the line of the row keeps the room of.
  Finder shown(String text) => find.text(text).hitTestable();

  const summary =
      'Map of the face to face locations of the order book: 1 buy order and 2 sell orders.';

  testWidgets(
    '« Map » shows the orders with a position on the world, under the row of the coordinators',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await openMap(tester);

      expect(map, findsOneWidget);
      // The view replaces the list and its filter sentence, as the chart does.
      expect(find.text('I want'), findsNothing);
      expect(find.text('Map'), findsNWidgets(2));
      expect(find.text('Show tiles'), findsNothing);
      expect(
        tester.getRect(find.byType(CoordinatorsRow)).bottom,
        lessThanOrEqualTo(tester.getRect(map).top),
      );
      // The world is drawn, the orders without a position are not on it.
      expect(painter(tester).world, isNotNull);
      expect(layout(tester).camera, const MapCamera());
      // At zoom 1, Paris and Berlin are 17 points apart: one group; São Paulo has its pin.
      expect(drawnIds(tester), [
        [1, 2],
        [4],
      ]);
      expect(find.byTooltip('Zoom in'), findsOneWidget);
      expect(find.byTooltip('Zoom out'), findsOneWidget);
      expect(find.bySemanticsLabel(summary), findsOneWidget);
      expect(find.semantics.byLabel('2 orders here'), findsOne);
      expect(find.semantics.byLabel('Buyer, 100 EUR, TheBigLake'), findsOne);
      // « Map » is the view chosen in the bar.
      final segment = tester.widget<Text>(
        find.descendant(
          of: find.byType(BullSegmented).last,
          matching: find.text('Map'),
        ),
      );
      expect(segment.style?.color, testBullTheme.primary);
      semantics.dispose();
    },
  );

  testWidgets(
    'the countries are drawn where they lie, and each pin in the colour of its side, a pin further south over one further north',
    (tester) async {
      transport = FakeTransport(
        books: {
          'temple': [located(1, '48.8566', '2.3522')],
          'lake': [located(2, '-23.5505', '-46.6333', type: 0)],
        },
      );
      await openMap(tester);
      final size = tester.getSize(paint);
      final camera = layout(tester).camera;
      Offset at(double latitude, double longitude) {
        final point =
            WebMercator.project(latitude, longitude) ?? (x: 0.0, y: 0.0);
        return camera.toView(point.x, point.y, size);
      }

      final theme = testBullTheme;
      expect(
        tester.renderObject(paint),
        paints
          // The countries, filled as one: France and Brazil are land, the Atlantic and the Indian Ocean are not.
          ..path(
            color: theme.text.withValues(alpha: 0.1),
            includes: [at(48.8566, 2.3522), at(-15, -55), at(60, 100)],
            excludes: [at(30, -40), at(-30, 80), at(0, -150)],
          )
          ..path(color: theme.textMuted)
          // Paris, a seller, in the primary colour, outlined, its visor, eyes and smile; then São Paulo, a buyer, further south, over it.
          ..path(color: theme.primary)
          ..path(color: theme.onSurfaceFixed)
          ..rrect(color: theme.onSurfaceFixed)
          ..rrect(color: theme.surfaceFixed)
          ..rrect(color: theme.surfaceFixed)
          ..arc(color: theme.surfaceFixed)
          ..path(color: theme.secondary)
          ..path(color: theme.onSurfaceFixed),
      );
      // The tip of each pin is the position of its order.
      expect(layout(tester).drawn.map((entry) => entry.$2), [
        at(48.8566, 2.3522),
        at(-23.5505, -46.6333),
      ]);
    },
  );

  testWidgets('a group is drawn with its count, in the colour of its size', (
    tester,
  ) async {
    transport = FakeTransport(
      books: {
        'temple': [
          for (var id = 1; id <= 10; id++) located(id, '38.7223', '-9.1393'),
        ],
        'lake': [
          for (var id = 1; id <= 9; id++) located(id, '-23.5505', '-46.6333'),
        ],
        'bazaar': [
          for (var id = 1; id <= 100; id++) located(id, '35.6762', '139.6503'),
        ],
      },
    );
    await openMap(tester);
    final theme = testBullTheme;
    expect(
      tester.renderObject(paint),
      paints
        ..path(color: theme.text.withValues(alpha: 0.1))
        ..path(color: theme.textMuted)
        // From north to south, at the edges of the sizes: ten in Lisbon, yellow; a hundred in Tokyo, orange; nine in São Paulo, green.
        // The figures of the test font are about as wide as the text is high: two or three widen the discs, one fits the 30 and 40 points of Leaflet.markercluster's.
        ..circle(color: theme.tertiary.withValues(alpha: 0.35))
        ..circle(color: theme.tertiary.withValues(alpha: 0.75))
        ..paragraph()
        ..circle(color: theme.warning.withValues(alpha: 0.35))
        ..circle(color: theme.warning.withValues(alpha: 0.75))
        ..paragraph()
        ..circle(color: theme.success.withValues(alpha: 0.35), radius: 20)
        ..circle(color: theme.success.withValues(alpha: 0.75), radius: 15)
        ..paragraph(),
    );
  });

  testWidgets(
    'the map asks nothing: opening, moving, zooming, a group, a long press, a hover',
    (tester) async {
      await openMap(tester, showMap: false);
      final asked = transport.requested.length;
      expect(asked, everyCoordinator.length);

      await tester.tap(find.text('Map'));
      await settle(tester);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
      await tester.dragFrom(tester.getCenter(paint), const Offset(-60, 30));
      await tester.pump();
      await tester.tapAt(groupOf(tester, 1));
      await tester.pump();
      final finger = await tester.startGesture(pinOf(tester, 1));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      expect(find.byType(OrderTooltip), findsOneWidget);
      await finger.up();
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(pinOf(tester, 2));
      await tester.pump();
      expect(find.byType(OrderTooltip), findsOneWidget);
      await settle(tester);

      expect(transport.requested.length, asked);
    },
  );

  testWidgets(
    'a tap on a pin opens its order, and the map is kept on the way back',
    (tester) async {
      await openMap(tester);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();

      await tester.tapAt(pinOf(tester, 4));
      await settle(tester);
      expect(find.byType(OrderDetailsScreen), findsOneWidget);
      expect(find.text('# 4'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(map, findsOneWidget);
      expect(layout(tester).camera.zoom, 2);
      // A tap where there is nothing opens nothing.
      await tester.tapAt(tester.getTopLeft(paint) + const Offset(200, 8));
      await settle(tester);
      expect(find.byType(OrderDetailsScreen), findsNothing);
    },
  );

  testWidgets(
    'a tap on a group zooms in where it parts, as Leaflet.markercluster does, then each pin opens its order',
    (tester) async {
      await openMap(tester);
      final (group, _) = mark(tester, (mark) => mark is MapGroup);

      await tester.tapAt(groupOf(tester, 1));
      await tester.pump();
      // Paris and Berlin part at level 4, and fit in the view up to zoom 5: the map goes to 4, centred on them.
      final camera = layout(tester).camera;
      expect(camera, MapCamera.at(zoom: 4, x: group.x, y: group.y));
      expect(
        drawnIds(tester),
        containsAll([
          [1],
          [2],
        ]),
      );
      await tester.tapAt(pinOf(tester, 2));
      await settle(tester);
      expect(find.text('# 2'), findsOneWidget);
    },
  );

  testWidgets(
    'a group that zooming cannot part lists its orders, as the list shows them',
    (tester) async {
      transport = FakeTransport(
        books: {
          'temple': [
            for (var id = 1; id <= 3; id++) located(id, '38.7223', '-9.1393'),
          ],
        },
      );
      await openMap(tester);
      expect(drawnIds(tester), [
        [1, 2, 3],
      ]);

      await tester.tapAt(groupOf(tester, 1));
      await settle(tester);
      expect(find.byType(MapGroupSheet), findsOneWidget);
      expect(find.text('3 orders here'), findsOneWidget);
      expect(find.byType(OfferRow), findsNWidgets(3));
      // Closed, it opens nothing and leaves the map as it was.
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(find.byType(MapGroupSheet), findsNothing);
      expect(find.byType(OrderDetailsScreen), findsNothing);
      expect(layout(tester).camera, const MapCamera());

      await tester.tapAt(groupOf(tester, 1));
      await settle(tester);
      await tester.tap(find.byType(OfferRow).at(1));
      await settle(tester);
      expect(find.byType(OrderDetailsScreen), findsOneWidget);
      expect(find.text('# 2'), findsOneWidget);
    },
  );

  testWidgets(
    'a long press shows the order of the pin under the finger, and lets go; a group shows nothing',
    (tester) async {
      await openMap(tester);

      final gesture = await tester.startGesture(pinOf(tester, 4));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      final tooltip = find.byType(OrderTooltip);
      expect(tooltip, findsOneWidget);
      expect(
        find.descendant(of: tooltip, matching: find.text('TheBigLake')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tooltip,
          matching: find.text('100 EUR', findRichText: true),
        ),
        findsOneWidget,
      );
      // Inside the map, beside the pin.
      expect(
        tester.getRect(map).contains(tester.getRect(tooltip).center),
        isTrue,
      );
      await gesture.up();
      await tester.pump();
      expect(tooltip, findsNothing);
      expect(find.byType(OrderDetailsScreen), findsNothing);

      final onGroup = await tester.startGesture(groupOf(tester, 1));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      expect(tooltip, findsNothing);
      await onGroup.up();
      await tester.pump();
      expect(layout(tester).camera, const MapCamera());

      // A mouse shows the order it hovers, and nothing once it leaves.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(pinOf(tester, 4));
      await tester.pump();
      expect(tooltip, findsOneWidget);
      await mouse.moveTo(tester.getTopLeft(find.byType(CoordinatorsRow)));
      await tester.pump();
      expect(tooltip, findsNothing);
    },
  );

  testWidgets(
    'a drag moves the map, never the book around it, and stops with the world in view',
    (tester) async {
      await openMap(tester);
      final row = tester.getRect(find.byType(CoordinatorsRow));
      final asked = transport.requested.length;

      // Down by 4 points at a time: the map takes the drag once it passes 6 points, twice its slop, before the book would at its own slop, and follows the finger from there.
      final finger = await tester.startGesture(tester.getCenter(paint));
      for (var step = 0; step < 30; step++) {
        await finger.moveBy(const Offset(0, 4));
        await tester.pump();
      }
      await finger.moveBy(const Offset(-100, 0));
      await tester.pump();
      await finger.up();
      await tester.pump();
      final camera = layout(tester).camera;
      expect(camera.zoom, 1);
      expect(camera.x, closeTo(0.5 + 100 / 512, 1e-12));
      expect(camera.y, closeTo(0.5 - (120 - 8) / 512, 1e-12));
      // A drag down that starts on the map does not pull the book to refresh it, nor scroll it.
      expect(tester.getRect(find.byType(CoordinatorsRow)), row);
      await settle(tester);
      expect(transport.requested.length, asked);

      // However far it is dragged, the centre of the view stays on the world.
      await tester.dragFrom(
        tester.getCenter(paint),
        const Offset(-3000, -3000),
      );
      await tester.pump();
      expect((layout(tester).camera.x, layout(tester).camera.y), (1.0, 1.0));
      await tester.dragFrom(tester.getCenter(paint), const Offset(6000, 6000));
      await tester.pump();
      expect((layout(tester).camera.x, layout(tester).camera.y), (0.0, 0.0));
    },
  );

  testWidgets('a pinch zooms around the fingers, within zooms 0 and 15', (
    tester,
  ) async {
    await openMap(tester);
    final centre = tester.getCenter(paint);
    Future<void> pinch(double from, double to) async {
      final left = await tester.startGesture(centre.translate(-from, 0));
      final right = await tester.startGesture(
        centre.translate(from, 0),
        pointer: 2,
      );
      await left.moveTo(centre.translate(-to, 0));
      await tester.pump();
      await right.moveTo(centre.translate(to, 0));
      await tester.pump();
      await left.up();
      await right.up();
      await tester.pump();
    }

    // The fingers twice as far apart: one level nearer, the point between them kept there.
    await pinch(50, 100);
    expect(layout(tester).camera.zoom, closeTo(2, 1e-12));
    await pinch(20, 150);
    await pinch(10, 150);
    await pinch(10, 150);
    await pinch(5, 150);
    expect(layout(tester).camera.zoom, 15);
    for (var i = 0; i < 4; i++) {
      await pinch(150, 5);
    }
    expect(layout(tester).camera.zoom, 0);
  });

  testWidgets('« + » and « − » zoom by whole levels, and stop at 15 and 0', (
    tester,
  ) async {
    await openMap(tester);
    IconButton button(String tooltip) => tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );

    for (var zoom = 2; zoom <= 15; zoom++) {
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(layout(tester).camera.zoom, zoom);
    }
    expect(button('Zoom in').onPressed, isNull);
    expect(button('Zoom out').onPressed, isNotNull);
    // From zoom 14 every order has its own pin.
    expect(layout(tester).level, 15);
    for (var zoom = 14; zoom >= 0; zoom--) {
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
      expect(layout(tester).camera.zoom, zoom);
    }
    expect(button('Zoom out').onPressed, isNull);
    // The centre does not move.
    expect((layout(tester).camera.x, layout(tester).camera.y), (0.5, 0.5));
  });

  testWidgets(
    'the map shows every order of the book that has a position, whatever the filter, as the official client\'s map',
    (tester) async {
      final semantics = tester.ensureSemantics();
      transport = FakeTransport(
        books: {
          'temple': [
            located(1, '48.8566', '2.3522'),
            located(2, '40.7128', '-74.0060', currency: 1),
          ],
          'lake': [
            located(3, '-23.5505', '-46.6333', type: 0),
            located(4, '35.6762', '139.6503', type: 0, currency: 1),
          ],
        },
      );
      const all =
          'Map of the face to face locations of the order book: 2 buy orders and 2 sell orders.';
      await openMap(tester);
      expect(drawnIds(tester).expand((ids) => ids).toSet(), {1, 2, 3, 4});
      expect(find.bySemanticsLabel(all), findsOneWidget);

      // « I want to sell » with euros, hosted by TheBigLake, in the list: the map still draws both sides, dollars too, and temple's orders.
      await tester.tap(find.text('List'));
      await settle(tester);
      await tester.tap(find.text('Any type'));
      await settle(tester);
      await tester.tap(find.text('Sell').last);
      await settle(tester);
      await tester.tap(find.text('Any currency'));
      await settle(tester);
      await tester.tap(find.text('EUR').last);
      await settle(tester);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      await tester.tap(find.text('Any host'));
      await settle(tester);
      await tester.tap(find.text('TheBigLake').last);
      await settle(tester);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      await tester.tap(find.text('Map'));
      await settle(tester);
      expect(drawnIds(tester).expand((ids) => ids).toSet(), {1, 2, 3, 4});
      expect(find.bySemanticsLabel(all), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('no order with a position: the map says so', (tester) async {
    final semantics = tester.ensureSemantics();
    transport = FakeTransport(
      books: {
        'temple': [bookOrder(id: 1)],
      },
    );
    await openMap(tester);
    expect(map, findsOneWidget);
    expect(layout(tester).drawn, isEmpty);
    expect(find.text('No order with a face to face location'), findsOneWidget);
    expect(
      find.bySemanticsLabel('No order with a face to face location'),
      findsOneWidget,
    );
    // The zoom buttons still move the empty map.
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(layout(tester).camera.zoom, 2);
    semantics.dispose();
  });

  testWidgets('an empty book says so, as the chart does', (tester) async {
    transport = FakeTransport();
    await openMap(tester);
    expect(map, findsNothing);
    expect(
      find.text('No orders found to buy BTC for any currency'),
      findsOneWidget,
    );
    expect(find.text('Be the first one to create an order'), findsOneWidget);
  });

  testWidgets('a wait while no order has arrived, then the map', (
    tester,
  ) async {
    transport = FakeTransport(books: books(), held: {...everyCoordinator});
    await openMap(tester);
    expect(map, findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    transport.release('lake');
    await settle(tester);
    expect(map, findsOneWidget);
    expect(drawnIds(tester), [
      [4],
    ]);
    // Temple's orders join the map as they arrive, the map staying where it is.
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    transport.release('temple');
    await settle(tester);
    expect(layout(tester).camera.zoom, 2);
    expect(layout(tester).drawn, hasLength(greaterThanOrEqualTo(2)));
  });

  testWidgets(
    'every coordinator offline: their state and « Retry » above, and no map',
    (tester) async {
      transport = FakeTransport(
        failures: {
          for (final alias in everyCoordinator)
            alias: const CoordinatorTimedOut(),
        },
      );
      await openMap(tester);
      await settleAttempts(tester);
      expect(map, findsNothing);
      expect(shown('6 coordinators offline'), findsOneWidget);
      expect(shown('Retry'), findsOneWidget);
      expect(
        find.text('No orders found to buy BTC for any currency'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'hostile positions: the poles, the antimeridian, a thousand orders at one point, every order of a book',
    (tester) async {
      final semantics = tester.ensureSemantics();
      transport = FakeTransport(
        books: {
          // The most a book is read with: 1,000 orders, all at one point.
          'temple': [
            for (var id = 1; id <= 1000; id++)
              located(id, '48.8566', '2.3522', type: id % 2),
          ],
          'lake': [
            located(1, 90, 180),
            located(2, -90, -180),
            located(3, 90, -180),
            located(4, -90, 180),
            located(5, 0, 0),
            located(6, '85.0511287798', 0),
          ],
          'bazaar': [
            for (var id = 1; id <= 300; id++)
              located(
                id,
                ((id * 37) % 170 - 85).toString(),
                ((id * 113) % 360 - 180).toString(),
                type: id % 2,
              ),
          ],
        },
      );
      await openMap(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel(
          'Map of the face to face locations of the order book: 650 buy orders and 656 sell orders.',
        ),
        findsOneWidget,
      );
      // The thousand orders are in one group, drawn once.
      expect(
        layout(tester).drawn.where((entry) => entry.$1.count >= 1000),
        hasLength(1),
      );
      // Zooming in cannot part them: taps zoom in on their group until it holds them alone, then list them, lazily.
      for (var tap = 0; tap < 16; tap++) {
        if (find.byType(MapGroupSheet).evaluate().isNotEmpty) break;
        await tester.tapAt(
          mark(tester, (mark) => mark is MapGroup && mark.count >= 1000).$2,
        );
        await settle(tester);
      }
      expect(find.text('1000 orders here'), findsOneWidget);
      expect(find.byType(OfferRow), findsWidgets);
      expect(find.byType(OfferRow).evaluate().length, lessThan(30));
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);

      // At the nearest zoom on Paris, the thousand pins are drawn as one.
      final world = tester.getSize(paint);
      final point = WebMercator.project(48.8566, 2.3522);
      final near = MapLayout.of(
        MapMarks.of([
          for (final (mark, _) in layout(tester).drawn)
            ...switch (mark) {
              MapPin(:final order) => [order],
              MapGroup(:final pins) => [for (final pin in pins) pin.order],
            },
        ]),
        MapCamera.at(zoom: 15, x: point?.x ?? 0, y: point?.y ?? 0),
        world,
      );
      expect(near.drawn, hasLength(1));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'a screen reader reads each pin and group in view, and opens them as a tap does',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await openMap(tester);

      final group = find.semantics.byLabel('2 orders here');
      expect(group, findsOne);
      tester.semantics.tap(group);
      await tester.pump();
      expect(layout(tester).camera.zoom, 4);
      // Zoomed in, Paris and Berlin are pins of their own, and São Paulo is out of view.
      expect(
        find.semantics.byLabel('Seller, 100 EUR, Temple of Sats'),
        findsExactly(2),
      );
      expect(
        find.semantics.byLabel('Buyer, 100 EUR, TheBigLake'),
        findsNothing,
      );
      tester.semantics.tap(
        find.semantics.byLabel('Seller, 100 EUR, Temple of Sats').first,
      );
      await settle(tester);
      expect(find.byType(OrderDetailsScreen), findsOneWidget);
      semantics.dispose();
    },
  );

  for (final (name, bundle) in [
    ('missing', () => _BrokenMapBundle(missing: true)),
    ('cut short', _BrokenMapBundle.new),
  ]) {
    testWidgets(
      'a world map $name in the bundle: no error, and the orders on an empty map',
      (tester) async {
        await openMap(tester, bundle: bundle());
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(map, findsOneWidget);
        expect(painter(tester).world, isNull);
        expect(drawnIds(tester), [
          [1, 2],
          [4],
        ]);
        await tester.tapAt(pinOf(tester, 4));
        await settle(tester);
        expect(find.text('# 4'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'a pin keeps its node for a screen reader while the map moves, and scrolling the summary moves the map',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await openMap(tester);
      final pin = find.semantics.byLabel('Buyer, 100 EUR, TheBigLake');
      final group = find.semantics.byLabel('2 orders here');
      expect(group, findsOne);
      final id = pin.evaluate().single.id;
      // Dragged 220 points east: the group over Europe leaves the view, São Paulo's pin stays, with its node.
      final finger = await tester.startGesture(tester.getCenter(paint));
      for (var step = 0; step < 55; step++) {
        await finger.moveBy(const Offset(4, 0));
        await tester.pump();
      }
      await finger.up();
      await tester.pump();
      expect(layout(tester).camera.x, lessThan(0.5));
      expect(group, findsNothing);
      expect(pin.evaluate().single.id, id);

      // Scrolled left, the map shows what lies east, half a view further; scrolled down, what lies north.
      final width = tester.getSize(paint).width;
      final height = tester.getSize(paint).height;
      final before = layout(tester).camera;
      tester.semantics.scrollLeft(scrollable: find.semantics.byLabel(summary));
      await tester.pump();
      expect(
        layout(tester).camera.x,
        closeTo(before.x + width / 2 / 512, 1e-12),
      );
      tester.semantics.scrollDown(scrollable: find.semantics.byLabel(summary));
      await tester.pump();
      expect(
        layout(tester).camera.y,
        closeTo(before.y - height / 2 / 512, 1e-12),
      );
      semantics.dispose();
    },
  );

  testWidgets('« Search » keeps the map, and « List » and « Chart » go back', (
    tester,
  ) async {
    await openMap(tester);

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
    expect(map, findsOneWidget);
    // The bar, built again after « Search », still shows « Map » chosen.
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byType(BullSegmented).last,
              matching: find.text('Map'),
            ),
          )
          .style
          ?.color,
      testBullTheme.primary,
    );

    await tester.tap(find.text('Chart'));
    await settle(tester);
    expect(map, findsNothing);
    expect(find.byType(DepthChartView), findsOneWidget);
    await tester.tap(find.text('Map'));
    await settle(tester);
    expect(map, findsOneWidget);
    await tester.tap(find.text('List'));
    await settle(tester);
    expect(map, findsNothing);
    expect(find.text('Seller'), findsNWidgets(3));
  });

  testWidgets(
    'pulled from the row, the book is asked again and the map stays where it was',
    (tester) async {
      await openMap(tester);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      transport.requested.clear();

      // From the header of the map, above the map itself: the book's scroll view takes the drag there.
      await tester.flingFrom(
        tester.getCenter(find.text('Map').first),
        const Offset(0, 400),
        1000,
      );
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(transport.requested.toSet(), {
        for (final alias in everyCoordinator) '$alias/api/book/',
      });
      expect(layout(tester).camera.zoom, 2);
      expect(drawnIds(tester), [
        [1, 2],
        [4],
      ]);
    },
  );

  testWidgets('in French', (tester) async {
    final semantics = tester.ensureSemantics();
    await openMap(tester, locale: const Locale('fr'));

    expect(find.text('Carte'), findsNWidgets(2));
    expect(find.byTooltip('Zoom avant'), findsOneWidget);
    expect(find.byTooltip('Zoom arrière'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        "Carte des emplacements face à face du carnet d'ordres : 1 ordre d'achat et 2 ordres de vente.",
      ),
      findsOneWidget,
    );
    expect(find.semantics.byLabel('2 ordres ici'), findsOne);
    expect(find.semantics.byLabel('Acheteur, 100 EUR, TheBigLake'), findsOne);
    semantics.dispose();
  });

  testWidgets('in French, with no order with a position', (tester) async {
    transport = FakeTransport(
      books: {
        'temple': [bookOrder(id: 1)],
      },
    );
    await openMap(tester, locale: const Locale('fr'));
    expect(
      find.text('Aucun ordre avec un emplacement face à face'),
      findsOneWidget,
    );
  });

  for (final locale in const [Locale('en'), Locale('fr')]) {
    for (final (screen, textScale) in [
      (const Size(320, 568), 1.0),
      (const Size(320, 568), 2.0),
      (const Size(320, 568), 3.0),
      (const Size(390, 844), 3.0),
    ]) {
      testWidgets(
        'on a ${screen.width.round()}x${screen.height.round()} screen at text size $textScale in ${locale.languageCode}: nothing overflows, and the map keeps its height',
        (tester) async {
          transport = FakeTransport(
            books: books(),
            failures: {'bazaar': const CoordinatorTimedOut()},
          );
          await openMap(
            tester,
            locale: locale,
            screen: screen,
            textScale: textScale,
          );
          await settleAttempts(tester);
          // An overflow would have failed the test already: the map comes into view by scrolling, at least 320 tall.
          await tester.scrollUntilVisible(
            paint,
            100,
            scrollable: find
                .descendant(
                  of: find.byType(CustomScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await settle(tester);
          expect(tester.getSize(map).height, greaterThanOrEqualTo(320));
          expect(tester.getSize(paint).height, greaterThan(100));
          expect(
            find.byTooltip(lookupP2pLocalizations(locale).p2pChartZoomIn),
            findsOneWidget,
          );
          // A group's count grows with the text, at most one and a half times.
          expect(
            painter(tester).scaler.scale(10),
            closeTo(10 * (textScale < 1.5 ? textScale : 1.5), 1e-9),
          );
        },
      );
    }
  }

  testWidgets('the world map in the bundle is read once, and fails closed', (
    tester,
  ) async {
    // A bundle whose map is not what the script writes: the view draws the orders on an empty map.
    final bundle = _BrokenMapBundle();
    expect(await tester.runAsync(() => MapChartView.worldOf(bundle)), isNull);
    final missing = _BrokenMapBundle(missing: true);
    expect(await tester.runAsync(() => MapChartView.worldOf(missing)), isNull);
    expect(
      identical(MapChartView.worldOf(bundle), MapChartView.worldOf(bundle)),
      isTrue,
    );
  });
}

/// The bundle of the tests, with a world map cut short, or without it when [missing], as a build that lost it.
final class _BrokenMapBundle extends CachingAssetBundle {
  final bool missing;

  _BrokenMapBundle({this.missing = false});

  @override
  Future<ByteData> load(String key) async {
    if (key == MapChartView.worldAsset && missing) {
      throw FlutterError('Unable to load asset: "$key".');
    }
    final data = await rootBundle.load(key);
    if (key != MapChartView.worldAsset) return data;
    return ByteData.sublistView(data, 0, data.lengthInBytes - 1);
  }
}
