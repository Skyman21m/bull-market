import 'dart:async';
import 'dart:convert';

import 'package:bull_ui/bull_ui.dart' show BullTopBar;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/location_map_dialog.dart';
import 'package:p2p/src/ui/widgets/map_tiles_controls.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/harness.dart';
import 'support/map_tiles.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// A protected order, an order with a meeting point and the renewal of a protected order, made on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`) by the user's gestures (#189), in English and in French.
///
/// The coordinators are played by [ScriptedMakerCoordinator] (never real ones), which keeps the body of each make as it was sent; the book is empty. The password is a test text, never anyone's. Nothing is paid: the bond is said locked by the coordinator.
const _net = RobosatsNetwork.testnet;

/// A password of the tests.
const _password = 'a test password';

/// Its SHA-256 in lowercase hexadecimal, computed apart (`hashlib.sha256(b'a test password').hexdigest()`).
const _passwordHash =
    '7c8c067cf46835b89fb83f6e9f1faab5bfadabd658aba621d7ecd6b36534d6f8';

/// The coordinators: [maker] for every robot's request, the limits and the make whatever the host; each coordinator's `/api/info/` under its own alias; the book empty (`404` with the reference's `not_found`, `api/views.py:797-801`).
final class _Coordinators implements CoordinatorTransport {
  final ScriptedMakerCoordinator maker;
  final Map<String, ScriptedMakerCoordinator> _infos = {};

  _Coordinators(this.maker);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final path = request.url.path;
    if (path.startsWith('/api/book')) {
      return Ok(
        _json(404, {'not_found': 'No orders found, be the first to make one'}),
      );
    }
    if (path.startsWith('/api/chat')) {
      return Ok(_json(400, {'bad_request': 'not played'}));
    }
    if (path == '/api/info/' && request.robot == null) {
      final alias = _aliasOf(request.url.host);
      final info = _infos[alias] ??= ScriptedMakerCoordinator(
        network: _net,
        robots: const [],
        clock: () => DateTime.utc(2026, 11, 20, 9),
        alias: alias,
      );
      return info.send(request);
    }
    return maker.send(request);
  }

  static String _aliasOf(String host) {
    for (final coordinator in Federation.robosats.on(_net)) {
      if (Uri.parse(coordinator.origins(_net).onion ?? '').host == host) {
        return coordinator.shortAlias;
      }
    }
    throw StateError('unknown host');
  }

  static CoordinatorResponse _json(int status, Object body) =>
      CoordinatorResponse(
        statusCode: status,
        headers: const {'content-type': 'application/json'},
        body: utf8.encode(jsonEncode(body)),
      );
}

final class _Journey {
  final WidgetTester tester;
  final ScriptedMakerCoordinator coordinator;
  final void Function(Duration) advance;
  final Locale locale;

  _Journey(this.tester, this.coordinator, this.advance, this.locale);

  /// The calls of the protection from screen capture (`PrivacyScreen`), on the channel of its plugin, which the test plays.
  final privacy = <String>[];

  /// Whether the platform sets the protection when asked.
  bool protects = true;

  P2pLocalizations get l10n => lookupP2pLocalizations(locale);

  /// The orders made, at the coordinator, oldest first.
  List<ScriptedMadeOrder> get orders => coordinator.orders.values.toList();

  /// The bodies of the makes, as sent, oldest first.
  List<String> get makes => [
    for (final request in coordinator.requests)
      if (request.url.path == '/api/make/')
        utf8.decode(request.body ?? const []),
  ];

  Finder inForm(Finder finder) =>
      find.descendant(of: find.byType(CreateOrderScreen), matching: finder);

  Finder get passwordField => inForm(
    find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == l10n.p2pMakePassword,
    ),
  );

  Finder get createButton =>
      inForm(find.widgetWithText(TradeButton, l10n.p2pMakeCreateOrder));

  bool get createEnabled =>
      tester.widget<TradeButton>(createButton).onPressed != null;

  Future<void> pass(int seconds) async {
    for (var i = 0; i < seconds * 4; i++) {
      advance(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> waitFor(Finder finder, {int seconds = 60}) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (finder.evaluate().isNotEmpty) return;
      advance(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
    fail('never shown: $finder');
  }

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  static Future<_Journey> start(
    WidgetTester tester,
    Locale locale, {
    double Function()? draws,
    MapTilePort? tiles,
  }) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 3200 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    var clock = DateTime.utc(2026, 11, 20, 9);
    final coordinator = ScriptedMakerCoordinator(
      network: _net,
      robots: TradeHarness.robotsOf(_net),
      clock: () => clock,
    );
    coordinator.prices[1] = 50000;
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    setUpP2pForTesting(
      locator,
      transport: _Coordinators(coordinator),
      torStates: () => tor.stream,
      clock: () => clock,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      robotKeys: HarnessKeys(),
      bolt11Decoder: coordinator.decoder,
      locationDraws: draws ?? () => 0.5,
      tiles: tiles ?? FakeMapTiles(),
    );
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [const P2pFeature().route(locator, network: (_) => _net)],
    );
    final journey = _Journey(
      tester,
      coordinator,
      (by) => clock = clock.add(by),
      locale,
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('com.flutterplaza.no_screenshot_methods');
    messenger.setMockMethodCallHandler(channel, (call) async {
      journey.privacy.add(call.method);
      return call.method == 'screenshotOff' ? journey.protects : true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    await tester.runAsync(
      () async => (
        await locator<GarageKeyRepository>().import(_net, tradeKey),
        await locator<RobotBindingRepository>().recordGeneratedKey(
          _net,
          fingerprint,
        ),
      ),
    );
    await tester.pumpWidget(routerHarness(router, locale: locale));
    tor.add(P2pTorState.ready);
    await settle(tester);
    await settle(tester);
    return journey;
  }

  /// « Create », « Buy », 100 USD and a premium of 2 %, then [method] added as a custom method.
  Future<void> fillForm({String method = 'Revolut'}) async {
    await tap(find.text(l10n.p2pNavCreate));
    await settle(tester);
    expect(find.byType(CreateOrderScreen), findsOneWidget);
    await tap(inForm(find.text(l10n.p2pMakeBuy)));
    await tester.enterText(inForm(find.byType(TextField)).at(0), '100');
    await settle(tester);
    await tester.enterText(inForm(find.byType(TextField)).at(1), '2');
    await settle(tester);
    // The method last: a face-to-face one opens the map.
    await tap(inForm(find.byTooltip(l10n.p2pMakeAddCustomMethod)));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, method);
    await tester.pump();
    await tap(find.text(l10n.p2pMakeAddPaymentMethod));
    await settle(tester);
  }

  /// « Create order », then « Done » of « Store your garage key »: the trade of the order made, at its maker bond.
  Future<void> create() async {
    await tap(createButton);
    await settle(tester);
    await tap(find.text(l10n.p2pCommonDone));
    await waitFor(find.textContaining('PUBL'), seconds: 20);
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.pump(const Duration(seconds: 61));
  }
}

/// The texts of the journey that the test writes out, to check each language's own.
final class _Words {
  final Locale locale;
  final String protectedLine;
  final String pointSent;
  final String passwordAgain;

  const _Words({
    required this.locale,
    required this.protectedLine,
    required this.pointSent,
    required this.passwordAgain,
  });
}

const _english = _Words(
  locale: Locale('en'),
  protectedLine: 'Kept out of the book; taken with its link and the password.',
  pointSent: 'Point sent: 0.025, -0.025',
  passwordAgain: 'Enter a password again',
);

const _french = _Words(
  locale: Locale('fr'),
  protectedLine: 'Hors du carnet ; se prend avec son lien et le mot de passe.',
  pointSent: 'Point envoyé : 0.025, -0.025',
  passwordAgain: 'Saisissez à nouveau le mot de passe',
);

void main() {
  test('the hash of the tests is the SHA-256 of the password', () {
    expect(OrderPasswordHash.of(_password)?.hex, _passwordHash);
  });

  // The renewal from the expiry (5) in both languages, and from « Trade finished! » (14) in English (independent review of #189, R7): the same page, by another button.
  for (final (words, succeeded) in [
    (_english, false),
    (_french, false),
    (_english, true),
  ]) {
    testWidgets(
      '${words.locale}: a protected order made from the form sends its SHA-256 and never the password, then its renewal ${succeeded ? 'at 14' : 'at 5'} asks for it again and sends its SHA-256',
      (tester) async {
        final journey = await _Journey.start(tester, words.locale);
        final l10n = journey.l10n;
        await journey.fillForm();
        await journey.tap(journey.inForm(find.byType(Switch).first));
        await settle(tester);
        // The field empty: nothing more than it, the reference's help on demand.
        expect(find.text(words.protectedLine), findsNothing);
        await tester.enterText(journey.passwordField, _password);
        await settle(tester);
        expect(find.text(words.protectedLine), findsOneWidget);
        // The details only on demand.
        expect(find.text(l10n.p2pMakePasswordTakers), findsNothing);
        await journey.tap(journey.inForm(find.text(l10n.p2pMakeSeeDetails)));
        await settle(tester);
        expect(find.text(l10n.p2pMakePasswordTakers), findsOneWidget);
        expect(find.text(l10n.p2pMakePasswordHint), findsWidgets);
        // A coordinator of version 0.8.8: no alert.
        expect(find.textContaining('0.8.7'), findsNothing);
        expect(
          find.text(
            l10n.p2pMakeOptionsSentOpen(l10n.p2pMakeOptionSentPassword),
          ),
          findsOneWidget,
        );
        await journey.create();

        final order = journey.orders.single;
        expect(order.body['password'], _passwordHash);
        expect(journey.makes.single, contains('"password":"$_passwordHash"'));
        expect(journey.makes.single, isNot(contains(_password)));
        for (final request in journey.coordinator.requests) {
          expect(
            utf8.decode(request.body ?? const []),
            isNot(contains(_password)),
          );
          expect(request.url.toString(), isNot(contains(_passwordHash)));
        }

        // The bond locked, then the order expired untaken: « Renew Order »; or taken and its trade finished: « Renew ».
        journey.coordinator.lockMakerBond(order.id);
        if (succeeded) {
          journey.coordinator.take(order.id, TradeHarness.robotsOf(_net)[5]);
          order.status = 14;
        } else {
          journey.coordinator.expire(order.id);
        }
        final renew = find.widgetWithText(
          TradeButton,
          succeeded ? l10n.p2pRenew : l10n.p2pRenewOrder,
        );
        await journey.waitFor(renew, seconds: 60);
        await journey.tap(renew);
        await settle(tester);
        await settle(tester);
        await journey.waitFor(journey.passwordField, seconds: 20);
        // The only field open, empty: « Enter a password again », nothing sent.
        expect(tester.widget<TextField>(journey.passwordField).enabled, isTrue);
        expect(
          tester.widget<TextField>(journey.passwordField).controller?.text,
          isEmpty,
        );
        expect(find.text(words.passwordAgain), findsWidgets);
        expect(journey.createEnabled, isFalse);
        await tester.enterText(journey.passwordField, _password);
        await settle(tester);
        expect(find.text(words.passwordAgain), findsNothing);
        expect(journey.createEnabled, isTrue);
        await journey.tap(journey.createButton);
        await journey.waitFor(find.textContaining('PUBL'), seconds: 30);
        expect(journey.orders, hasLength(2));
        // Its SHA-256, where the reference sends the text typed (`TradeBox/index.tsx:180`).
        expect(journey.orders.last.body['password'], _passwordHash);
        expect(journey.makes.last, isNot(contains(_password)));
        // The rest of the order as kept.
        final kept = Map.of(journey.orders.first.body);
        final renewed = Map.of(journey.orders.last.body);
        expect(renewed, kept);
        await journey.close();
      },
    );

    testWidgets(
      '${words.locale}: a face-to-face method opens the map; the point sent is the point shown, moved as the reference moves it',
      (tester) async {
        final draws = [0.75, 0.25];
        var drawn = 0;
        final journey = await _Journey.start(
          tester,
          words.locale,
          draws: () => draws[drawn++ % draws.length],
        );
        final l10n = journey.l10n;
        // A face-to-face method as the last one chosen: the map opens by itself (`MakerForm.tsx:213-217`).
        await journey.fillForm(method: 'Meet F2F');
        await journey.waitFor(find.byType(LocationMapDialog), seconds: 5);
        expect(find.text(l10n.p2pMapChooseLocation), findsOneWidget);
        expect(find.text(l10n.p2pMakeLocationRandomized), findsOneWidget);
        expect(find.text(l10n.p2pMakeLocationPublished), findsOneWidget);
        final save = find.widgetWithText(TradeButton, l10n.p2pMapSave);
        expect(tester.widget<TradeButton>(save).onPressed, isNull);
        // A tap at the centre of the map, opened on 0°, 0°: pinned there; « Save » moves it.
        await tester.tap(find.byKey(LocationMapDialog.mapKey));
        await settle(tester);
        await tester.tap(save);
        await settle(tester);
        expect(find.byType(LocationMapDialog), findsNothing);
        expect(drawn, 2);
        // 0 + 0.75 × 0.1 − 0.05 and 0 + 0.25 × 0.1 − 0.05.
        expect(find.text(words.pointSent), findsOneWidget);
        // « Cash F2F » put first among the methods, as the reference does.
        expect(journey.inForm(find.text('Cash F2F')), findsOneWidget);
        // Opened again: on the point sent, the pin where the order puts it.
        await journey.tap(journey.inForm(find.text(l10n.p2pMakeLocation)));
        await settle(tester);
        expect(
          tester
              .widget<LocationMapDialog>(find.byType(LocationMapDialog))
              .initial,
          OrderLocation.tryCreate(0.025, -0.025),
        );
        await tester.tap(
          find.byTooltip(
            MaterialLocalizations.of(
              tester.element(find.byType(LocationMapDialog)),
            ).closeButtonTooltip,
          ),
        );
        await settle(tester);
        expect(find.text(words.pointSent), findsOneWidget);
        await journey.create();
        final order = journey.orders.single;
        expect(order.body['latitude'], 0.025);
        expect(order.body['longitude'], -0.025);
        expect(order.body['payment_method'], 'Cash F2F Meet F2F');
        expect(order.body['password'], isNull);
        await journey.close();
      },
    );
  }

  testWidgets(
    'the meeting point leaves with the last face-to-face method, and a cross removes it',
    (tester) async {
      final journey = await _Journey.start(tester, const Locale('en'));
      final l10n = journey.l10n;
      await journey.fillForm(method: 'Cash F2F');
      await journey.waitFor(find.byType(LocationMapDialog), seconds: 5);
      await tester.tap(find.byKey(LocationMapDialog.mapKey));
      await settle(tester);
      await tester.tap(find.widgetWithText(TradeButton, l10n.p2pMapSave));
      await settle(tester);
      expect(find.textContaining('Point sent:'), findsOneWidget);
      // The cross: removed, the method kept.
      await journey.tap(
        journey.inForm(find.byTooltip(l10n.p2pMakeLocationRemove)),
      );
      await settle(tester);
      expect(find.textContaining('Point sent:'), findsNothing);
      expect(journey.inForm(find.text('Cash F2F')), findsOneWidget);
      // Saved again, then the face-to-face method removed: the point goes with it.
      await journey.tap(journey.inForm(find.text(l10n.p2pMakeLocation)));
      await settle(tester);
      await tester.tap(find.byKey(LocationMapDialog.mapKey));
      await settle(tester);
      await tester.tap(find.widgetWithText(TradeButton, l10n.p2pMapSave));
      await settle(tester);
      expect(find.textContaining('Point sent:'), findsOneWidget);
      await journey.tap(
        journey.inForm(find.byTooltip(l10n.p2pMakeRemoveMethod('Cash F2F'))),
      );
      await settle(tester);
      expect(find.textContaining('Point sent:'), findsNothing);
      await journey.close();
    },
  );

  // « Show tiles » on the meeting point's map (#246), in both languages, with a tile provider of the test: never a request, never a real tile.
  for (final words in const [_english, _french]) {
    testWidgets(
      '${words.locale}: « Show tiles » on the meeting point\'s map is off in a new form, asks the reference\'s dialog, stays as left while the form is, and the point sent is moved exactly as without tiles',
      (tester) async {
        final tiles = FakeMapTiles();
        final draws = [0.75, 0.25];
        var drawn = 0;
        final journey = await _Journey.start(
          tester,
          words.locale,
          draws: () => draws[drawn++ % draws.length],
          tiles: tiles,
        );
        final l10n = journey.l10n;
        await journey.fillForm(method: 'Meet F2F');
        await journey.waitFor(find.byType(LocationMapDialog), seconds: 5);
        final toggle = find.descendant(
          of: find.byType(MapTilesSwitch),
          matching: find.byType(Switch),
        );
        expect(find.byTooltip(l10n.p2pMapShowTiles), findsOneWidget);
        expect(tester.widget<Switch>(toggle).value, isFalse);
        // Zoomed in and out, the switch off: nothing asked.
        await tester.tap(find.byTooltip(l10n.p2pChartZoomIn));
        await tester.pump();
        await tester.tap(find.byTooltip(l10n.p2pChartZoomOut));
        await settle(tester);
        expect(tiles.sessions, isEmpty);
        // The reference's dialog; « Close » leaves the tiles off.
        await tester.tap(toggle);
        await settle(tester);
        expect(find.text(l10n.p2pMapTilesTitle), findsOneWidget);
        expect(
          find.text(
            'By doing so, you will be fetching map tiles from a third-party provider. Depending on your setup, private information might be leaked to servers outside the RoboSats federation.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text(l10n.p2pMapTilesClose));
        await settle(tester);
        expect(tiles.sessions, isEmpty);
        expect(tester.widget<Switch>(toggle).value, isFalse);
        // « Acknowledged »: the tiles of the view, at the zoom the map opens at without a point.
        await tester.tap(toggle);
        await settle(tester);
        await tester.tap(find.text(l10n.p2pMapTilesAcknowledged));
        await _settleTiles(tester);
        expect(tester.widget<Switch>(toggle).value, isTrue);
        expect(tiles.sessions, hasLength(1));
        expect(tiles.asked, isNotEmpty);
        expect(tiles.asked.map((tile) => tile.z).toSet(), {
          LocationMapDialog.worldZoom.round(),
        });
        expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
        // Protected from capture while the tiles show, and only then (#246, security review).
        expect(journey.privacy, ['screenshotOff']);
        // A tap at the centre, opened on 0°, 0°, then « Save »: the point moved by the same draws as without tiles.
        await tester.tap(find.byKey(LocationMapDialog.mapKey));
        await settle(tester);
        await tester.tap(find.widgetWithText(TradeButton, l10n.p2pMapSave));
        await settle(tester);
        expect(find.byType(LocationMapDialog), findsNothing);
        expect(tiles.sessions.single.closed, isTrue);
        expect(journey.privacy, ['screenshotOff', 'screenshotOn']);
        expect(drawn, 2);
        expect(find.text(words.pointSent), findsOneWidget);
        // Opened again from the same form: on, without the dialog, as the reference's dialog stays mounted in its form; its tiles asked again in a new session, nothing having been kept.
        final asked = tiles.asked.length;
        await journey.tap(journey.inForm(find.text(l10n.p2pMakeLocation)));
        await settle(tester);
        await _settleTiles(tester);
        expect(find.text(l10n.p2pMapTilesTitle), findsNothing);
        expect(tester.widget<Switch>(toggle).value, isTrue);
        expect(tiles.sessions, hasLength(2));
        expect(tiles.sessions.last.asked, isNotEmpty);
        expect(tiles.asked.length, greaterThan(asked));
        expect(journey.privacy.last, 'screenshotOff');
        // Turned off, then the map closed and opened again: off, nothing asked.
        await tester.tap(toggle);
        await settle(tester);
        expect(tiles.sessions.last.closed, isTrue);
        expect(journey.privacy.last, 'screenshotOn');
        final closeMap = find.byTooltip(
          MaterialLocalizations.of(
            tester.element(find.byType(LocationMapDialog)),
          ).closeButtonTooltip,
        );
        await tester.tap(closeMap);
        await settle(tester);
        final afterOff = tiles.asked.length;
        await journey.tap(journey.inForm(find.text(l10n.p2pMakeLocation)));
        await settle(tester);
        await _settleTiles(tester);
        expect(tester.widget<Switch>(toggle).value, isFalse);
        expect(tiles.asked, hasLength(afterOff));
        expect(tiles.sessions, hasLength(2));
        // On again: no dialog, it was acknowledged in this form.
        await tester.tap(toggle);
        await settle(tester);
        expect(find.text(l10n.p2pMapTilesTitle), findsNothing);
        await _settleTiles(tester);
        expect(tiles.sessions, hasLength(3));
        await tester.tap(
          find.byTooltip(
            MaterialLocalizations.of(
              tester.element(find.byType(LocationMapDialog)),
            ).closeButtonTooltip,
          ),
        );
        await settle(tester);
        expect(tiles.sessions.last.closed, isTrue);
        // A new form starts off and asks the dialog again.
        await journey.tap(
          find
              .descendant(
                of: find.byType(BullTopBar),
                matching: find.byType(IconButton),
              )
              .first,
        );
        await settle(tester);
        expect(find.byType(CreateOrderScreen), findsNothing);
        await journey.tap(find.text(l10n.p2pNavCreate));
        await settle(tester);
        final beforeNewForm = tiles.asked.length;
        await journey.tap(journey.inForm(find.text(l10n.p2pMakeLocation)));
        await settle(tester);
        await _settleTiles(tester);
        expect(tester.widget<Switch>(toggle).value, isFalse);
        expect(tiles.asked, hasLength(beforeNewForm));
        expect(tiles.sessions, hasLength(3));
        await tester.tap(toggle);
        await settle(tester);
        expect(find.text(l10n.p2pMapTilesTitle), findsOneWidget);
        await tester.tap(find.text(l10n.p2pMapTilesClose));
        await settle(tester);
        expect(tiles.sessions, hasLength(3));
        await journey.close();
      },
    );
  }

  testWidgets(
    'when the platform cannot protect the meeting point\'s map from capture, its tiles stay off',
    (tester) async {
      final tiles = FakeMapTiles();
      final journey = await _Journey.start(
        tester,
        const Locale('en'),
        tiles: tiles,
      );
      journey.protects = false;
      final l10n = journey.l10n;
      await journey.fillForm(method: 'Meet F2F');
      await journey.waitFor(find.byType(LocationMapDialog), seconds: 5);
      final toggle = find.descendant(
        of: find.byType(MapTilesSwitch),
        matching: find.byType(Switch),
      );
      await tester.tap(toggle);
      await settle(tester);
      await tester.tap(find.text(l10n.p2pMapTilesAcknowledged));
      await _settleTiles(tester);
      expect(journey.privacy, ['screenshotOff', 'screenshotOn']);
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(tiles.sessions, isEmpty);
      await journey.close();
    },
  );
}

/// Lets the tiles that came be decoded: the pictures are decoded out of the test's fake time.
Future<void> _settleTiles(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}
