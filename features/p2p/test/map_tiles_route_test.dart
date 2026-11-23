import 'dart:async';
import 'dart:ui' as ui;

import 'package:bull_ui/testing.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/web_mercator.dart';
import 'package:p2p/src/ui/map_chart_view.dart';
import 'package:p2p/src/ui/map_tile_layer.dart';
import 'package:p2p/src/ui/order_details_screen.dart';
import 'package:p2p/src/ui/widgets/map_tiles_controls.dart';
import 'package:p2p/testing.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/map_tiles.dart';

/// « Show tiles » on the book's map (#246), by the user's gestures on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`), in English and in French, with a tile provider of the test ([FakeMapTiles]): never a request, never a real tile.
///
/// The map where the meeting point is chosen has the same tests in `maker_password_location_route_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GetIt locator;
  late FakeTransport transport;
  late StreamController<P2pTorState> tor;
  late FakeMapTiles tiles;

  setUpAll(() async {
    expect(await MapChartView.worldOf(rootBundle), isNotNull);
  });

  setUp(() {
    locator = GetIt.asNewInstance();
    tor = StreamController<P2pTorState>.broadcast();
    transport = FakeTransport(
      books: {
        'temple': [
          {
            ...bookOrder(id: 1, makerSeed: 1),
            'latitude': '48.8566',
            'longitude': '2.3522',
          },
        ],
      },
    );
    tiles = FakeMapTiles();
  });

  tearDown(() async {
    await tor.close();
    await locator.reset();
  });

  Future<P2pLocalizations> openMap(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    setUpP2pForTesting(
      locator,
      transport: transport,
      torStates: () => tor.stream,
      clock: () => testNow,
      tiles: tiles,
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
    tor.add(P2pTorState.ready);
    await settle(tester);
    final l10n = lookupP2pLocalizations(locale);
    await tester.tap(find.text(l10n.p2pBookViewMap));
    await settle(tester);
    return l10n;
  }

  final paint = find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is MapChartPainter,
  );

  MapChartPainter painter(WidgetTester tester) =>
      switch (tester.widget<CustomPaint>(paint).painter) {
        final MapChartPainter painter => painter,
        _ => throw StateError('no map'),
      };

  final switchFinder = find.descendant(
    of: find.byType(MapTilesSwitch),
    matching: find.byType(Switch),
  );

  bool switchOn(WidgetTester tester) =>
      tester.widget<Switch>(switchFinder).value;

  /// Lets the tiles that came be decoded: the pictures are decoded out of the test's fake time.
  Future<void> settleTiles(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> drag(WidgetTester tester, Offset by) async {
    final gesture = await tester.startGesture(tester.getCenter(paint));
    for (var i = 1; i <= 4; i++) {
      await gesture.moveBy(by / 4);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  /// The tiles a view of the map shows now, as the map asks them.
  List<MapTile> inView(WidgetTester tester) {
    final camera = painter(tester).layout.camera;
    final size = tester.getSize(paint);
    return MapTile.covering(
      zoom: camera.zoom,
      x: camera.x,
      y: camera.y,
      width: size.width,
      height: size.height,
    );
  }

  for (final (locale, words) in const [
    (
      Locale('en'),
      (
        tooltip: 'Show tiles',
        title: 'Download high resolution map?',
        close: 'Close',
        go: 'Acknowledged',
      ),
    ),
    (
      Locale('fr'),
      (
        tooltip: 'Afficher les tuiles',
        title: 'Télécharger une carte haute résolution?',
        close: 'Fermer',
        go: 'Confirmer',
      ),
    ),
  ]) {
    testWidgets(
      '${locale.languageCode}: nothing is asked until the switch is on and the dialog acknowledged, as the reference asks it',
      (tester) async {
        final l10n = await openMap(tester, locale: locale);
        expect(find.byTooltip(words.tooltip), findsOneWidget);
        expect(switchOn(tester), isFalse);
        expect(painter(tester).tiles, isNull);
        // The map moved and zoomed, the switch off: nothing asked, no session opened.
        await drag(tester, const Offset(-80, 40));
        await tester.tap(find.byTooltip(l10n.p2pChartZoomIn));
        await tester.pump();
        expect(tiles.sessions, isEmpty);
        expect(tiles.asked, isEmpty);

        // The first tap opens the reference's dialog, word for word; « Close » leaves the tiles off.
        await tester.tap(switchFinder);
        await settle(tester);
        expect(find.text(words.title), findsOneWidget);
        expect(
          find.text(
            'By doing so, you will be fetching map tiles from a third-party provider. Depending on your setup, private information might be leaked to servers outside the RoboSats federation.',
          ),
          findsOneWidget,
        );
        expect(find.text(words.close), findsOneWidget);
        expect(find.text(words.go), findsOneWidget);
        await tester.tap(find.text(words.close));
        await settle(tester);
        expect(find.text(words.title), findsNothing);
        expect(switchOn(tester), isFalse);
        expect(tiles.sessions, isEmpty);

        // A tap outside closes it too, the tiles left off.
        await tester.tap(switchFinder);
        await settle(tester);
        await tester.tapAt(const Offset(5, 5));
        await settle(tester);
        expect(find.text(words.title), findsNothing);
        expect(tiles.sessions, isEmpty);

        // « Acknowledged »: the tiles in view, at the map's zoom, and those only.
        await tester.tap(switchFinder);
        await settle(tester);
        await tester.tap(find.text(words.go));
        await settle(tester);
        await settleTiles(tester);
        expect(switchOn(tester), isTrue);
        expect(tiles.sessions, hasLength(1));
        expect(tiles.asked.toSet(), inView(tester).toSet());
        expect(tiles.asked, hasLength(tiles.asked.toSet().length));
        final frame = painter(tester).tiles;
        if (frame == null) fail('no tiles drawn');
        expect(frame.images.keys.toSet(), frame.wanted.toSet());
        // The provider's credit on the map, as the reference shows it.
        expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
        expect(find.text(l10n.p2pMapTilesUnavailable), findsNothing);
      },
    );
  }

  testWidgets(
    'once acknowledged the switch turns the tiles off and on; off, it closes the session and asks nothing',
    (tester) async {
      await openMap(tester);
      await tester.tap(switchFinder);
      await settle(tester);
      await tester.tap(find.text('Acknowledged'));
      await settleTiles(tester);
      final asked = tiles.asked.length;
      expect(asked, greaterThan(0));

      await tester.tap(switchFinder);
      await settle(tester);
      expect(find.text('Download high resolution map?'), findsNothing);
      expect(switchOn(tester), isFalse);
      expect(tiles.sessions.single.closed, isTrue);
      expect(painter(tester).tiles, isNull);
      expect(find.text('© OpenStreetMap contributors'), findsNothing);
      await drag(tester, const Offset(60, 60));
      expect(tiles.asked, hasLength(asked));

      // On again, without the dialog: a new session, nothing kept from the one closed.
      await tester.tap(switchFinder);
      await settle(tester);
      expect(find.text('Download high resolution map?'), findsNothing);
      await settleTiles(tester);
      expect(tiles.sessions, hasLength(2));
      expect(tiles.sessions.last.asked.toSet(), inView(tester).toSet());
    },
  );

  testWidgets(
    'a map opened again starts without tiles and asks the dialog again; nothing is asked on coming back',
    (tester) async {
      await openMap(tester);
      await tester.tap(switchFinder);
      await settle(tester);
      await tester.tap(find.text('Acknowledged'));
      await settleTiles(tester);
      final asked = tiles.asked.length;

      // To the list and back to the map: a new map, the switch off, the session of the first closed.
      await tester.tap(find.text('List'));
      await settle(tester);
      expect(tiles.sessions.single.closed, isTrue);
      await tester.tap(find.text('Map'));
      await settle(tester);
      await settleTiles(tester);
      expect(switchOn(tester), isFalse);
      expect(painter(tester).tiles, isNull);
      expect(tiles.asked, hasLength(asked));
      expect(tiles.sessions, hasLength(1));
      await tester.tap(switchFinder);
      await settle(tester);
      expect(find.text('Download high resolution map?'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await settle(tester);
      expect(tiles.sessions, hasLength(1));

      // Through the chart and back: the same.
      await tester.tap(find.text('Chart'));
      await settle(tester);
      await tester.tap(find.text('Map').last);
      await settle(tester);
      await settleTiles(tester);
      expect(switchOn(tester), isFalse);
      expect(tiles.asked, hasLength(asked));
    },
  );

  testWidgets(
    'a pan asks the tiles that come into view and gives up those that left it; the zoom never asks beyond 15',
    (tester) async {
      await openMap(tester);
      await tester.tap(switchFinder);
      await settle(tester);
      await tester.tap(find.text('Acknowledged'));
      await settleTiles(tester);
      for (var i = 0; i < 16; i++) {
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pump();
      }
      await settleTiles(tester);
      expect(painter(tester).layout.camera.zoom, WebMercator.maxZoom);
      expect(
        tiles.asked.map((tile) => tile.z).reduce((a, b) => a > b ? a : b),
        15,
      );
      // Held answers, then a pan of a whole view: what left the view is given up.
      tiles.held = true;
      final before = inView(tester).toSet();
      await drag(tester, const Offset(-200, 0));
      final now = inView(tester).toSet();
      expect(now, isNot(before));
      final asked = tiles.sessions.single.asked.toSet();
      expect(asked.containsAll(now), isTrue);
      await drag(tester, const Offset(-400, 0));
      expect(
        tiles.dropped.toSet().intersection(inView(tester).toSet()),
        isEmpty,
      );
      expect(tiles.dropped, isNotEmpty);
      tiles.release();
      await settleTiles(tester);
      final frame = painter(tester).tiles;
      if (frame == null) fail('no tiles drawn');
      expect(frame.images.keys.toSet(), inView(tester).toSet());
    },
  );

  testWidgets(
    'a tile that fails leaves the countries in its square and says « Map tiles unavailable »; the next pan asks it again',
    (tester) async {
      final failing = <MapTile>{};
      tiles.answer = (tile) {
        if (failing.isEmpty) failing.add(tile);
        return failing.contains(tile)
            ? const MapTileFailed()
            : MapTileImage(testTilePng(tile));
      };
      await openMap(tester);
      // At zoom 3, where a pan brings new tiles into view.
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      await tester.tap(switchFinder);
      await settle(tester);
      await tester.tap(find.text('Acknowledged'));
      await settleTiles(tester);
      final frame = painter(tester).tiles;
      if (frame == null) fail('no tiles drawn');
      final failed = failing.single;
      expect(frame.wanted, contains(failed));
      expect(frame.images.containsKey(failed), isFalse);
      expect(find.text('Map tiles unavailable'), findsOneWidget);
      // One line, over the map, with the credit.
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);

      // The countries are drawn only in the squares of the tiles that did not come.
      final canvas = _RecordingCanvas();
      final size = tester.getSize(paint);
      final world = await tester.runAsync(
        () => MapChartView.outlineOf(rootBundle),
      );
      MapChartPainter.paintGround(
        canvas,
        size,
        painter(tester).layout.camera,
        world,
        frame,
        MapColors.of(testBullTheme),
      );
      final square = MapChartPainter.tileRect(
        failed,
        painter(tester).layout.camera,
        size,
      );
      final clip = canvas.clips.single;
      expect(clip.contains(square.center), isTrue);
      for (final tile in frame.images.keys) {
        final other = MapChartPainter.tileRect(
          tile,
          painter(tester).layout.camera,
          size,
        );
        expect(clip.contains(other.center), isFalse);
      }
      expect(canvas.images, frame.images.length);
      expect(canvas.paths, greaterThan(0));

      // A pan within the same tiles asks nothing; the next pan that changes the tiles in view asks it again, and it comes this time.
      final askedBefore = tiles.asked.where((tile) => tile == failed).length;
      final shown = inView(tester).toSet();
      await drag(tester, const Offset(-2, 0));
      await settleTiles(tester);
      expect(inView(tester).toSet(), shown);
      expect(tiles.asked.where((tile) => tile == failed).length, askedBefore);
      failing
        ..clear()
        ..add(MapTile.of(0, 0, 0) ?? failed);
      for (var i = 0; i < 8 && setEquals(inView(tester).toSet(), shown); i++) {
        await drag(tester, const Offset(-40, 0));
      }
      await settleTiles(tester);
      expect(inView(tester).toSet(), isNot(shown));
      expect(inView(tester), contains(failed));
      expect(
        tiles.asked.where((tile) => tile == failed).length,
        greaterThan(askedBefore),
      );
    },
  );

  testWidgets(
    'a tile refused by the provider says « Map tiles unavailable », and nothing more is asked until the switch is turned off and on',
    (tester) async {
      tiles.answer = (tile) => const MapTileRefused();
      await openMap(tester);
      await tester.tap(switchFinder);
      await settle(tester);
      await tester.tap(find.text('Acknowledged'));
      await settleTiles(tester);
      expect(find.text('Map tiles unavailable'), findsOneWidget);
      final asked = tiles.asked.length;
      await drag(tester, const Offset(-200, 0));
      await settleTiles(tester);
      expect(tiles.asked, hasLength(asked));
      expect(find.text('Map tiles unavailable'), findsOneWidget);
    },
  );

  testWidgets(
    'a tile that failed is asked again only when the tiles in view change, never on a mere redraw of the same tiles',
    (tester) async {
      tiles.answer = (tile) => const MapTileFailed();
      await openMap(tester);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      await tester.tap(switchFinder);
      await settle(tester);
      await tester.tap(find.text('Acknowledged'));
      await settleTiles(tester);
      expect(tiles.asked.toSet(), inView(tester).toSet());
      expect(tiles.asked, hasLength(inView(tester).length));
      expect(find.text('Map tiles unavailable'), findsOneWidget);
      // A slow drag, two points at a time: the asks are counted at each step.
      var unchanged = 0;
      var changes = 0;
      final gesture = await tester.startGesture(tester.getCenter(paint));
      for (var step = 0; step < 60; step++) {
        final before = tiles.asked.length;
        final shownBefore = inView(tester).toSet();
        await gesture.moveBy(const Offset(-2, 0));
        await tester.pump();
        final shownAfter = inView(tester).toSet();
        final more = tiles.asked.length - before;
        if (setEquals(shownBefore, shownAfter)) {
          unchanged++;
          expect(more, 0, reason: 'step $step: the same tiles, nothing asked');
        } else {
          changes++;
          expect(more, lessThanOrEqualTo(shownAfter.length));
        }
      }
      await gesture.up();
      await tester.pump();
      expect(unchanged, greaterThan(changes));
      // No tile asked more than once per change of the tiles in view, plus its first time.
      final counts = <MapTile, int>{};
      for (final tile in tiles.asked) {
        counts[tile] = (counts[tile] ?? 0) + 1;
      }
      expect(
        counts.values.reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo(1 + changes),
      );
    },
  );

  testWidgets(
    'covered by an order\'s details, the map gives up the tiles asked and asks nothing; shown again, it asks what is missing',
    (tester) async {
      await openMap(tester);
      await tester.tap(switchFinder);
      await settle(tester);
      await tester.tap(find.text('Acknowledged'));
      await settle(tester);
      // The answers held: the tiles stay asked while the order opens.
      tiles.held = true;
      await tester.tap(switchFinder);
      await settle(tester);
      await tester.tap(switchFinder);
      await settle(tester);
      final session = tiles.sessions.last;
      final asked = session.asked.toSet();
      expect(asked, isNotEmpty);
      final (_, tip) = painter(tester).layout.drawn.first;
      await tester.tapAt(
        tester.getTopLeft(paint) +
            tip.translate(0, -MapChartPainter.pinHeight / 2),
      );
      await settle(tester);
      expect(find.byType(OrderDetailsScreen), findsOneWidget);
      expect(session.dropped.toSet(), asked);
      final whileCovered = session.asked.length;
      tiles.release();
      await settleTiles(tester);
      expect(session.asked, hasLength(whileCovered));
      // Back on the map: the switch still on, the missing tiles asked again.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settleTiles(tester);
      expect(switchOn(tester), isTrue);
      expect(session.asked.length, greaterThan(whileCovered));
      final frame = painter(tester).tiles;
      if (frame == null) fail('no tiles drawn');
      expect(frame.images.keys.toSet(), inView(tester).toSet());
    },
  );

  test(
    'a refusal is kept with the choice: the map opened again asks nothing until the switch is turned off and on',
    () async {
      final choice = MapTilesChoice();
      tiles.answer = (tile) => const MapTileRefused();
      final first = MapTileLayer(tiles.open, choice: choice)
        ..acknowledge()
        ..show()
        ..view(zoom: 2, x: 0.5, y: 0.5, size: const Size(300, 300));
      await Future<void>.delayed(Duration.zero);
      expect(choice.refused, isTrue);
      first.dispose();
      final asked = tiles.asked.length;
      final again = MapTileLayer(tiles.open, choice: choice)
        ..view(zoom: 2, x: 0.5, y: 0.5, size: const Size(300, 300));
      expect(again.shown, isTrue);
      expect(again.unavailable, isTrue);
      expect(tiles.asked, hasLength(asked));
      tiles.answer = (tile) => MapTileImage(testTilePng(tile));
      again
        ..hide()
        ..show()
        ..view(zoom: 2, x: 0.5, y: 0.5, size: const Size(300, 300));
      expect(tiles.asked.length, greaterThan(asked));
      again.dispose();
    },
  );

  test(
    'the layer opens nothing before « Acknowledged », and closes its session when disposed',
    () {
      final layer = MapTileLayer(tiles.open)..show();
      expect(layer.shown, isFalse);
      expect(tiles.sessions, isEmpty);
      layer
        ..acknowledge()
        ..show()
        ..view(zoom: 1, x: 0.5, y: 0.5, size: const Size(300, 300));
      expect(tiles.sessions, hasLength(1));
      layer.dispose();
      expect(tiles.sessions.single.closed, isTrue);
    },
  );
}

/// A canvas that records the clips, the pictures and the paths it is given.
final class _RecordingCanvas implements Canvas {
  final clips = <Path>[];
  var images = 0;
  var paths = 0;

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) => clips.add(path);

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) =>
      images++;

  @override
  void drawPath(Path path, Paint paint) => paths++;

  @override
  void save() {}

  @override
  void restore() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
