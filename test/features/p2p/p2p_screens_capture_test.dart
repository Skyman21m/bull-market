// Renders the screens of the P2P tab to PNG files, with the real widgets, the dark theme and fonts of the app, and the books recorded from the live federation, then the Garage over a vault in memory with the public example key of the RoboSats tests.
// They are review material, compared by eye with the validated mock-up: nothing is asserted on the pixels.
// Skipped unless P2P_CAPTURE_DIR names the folder to write to, for example:
// P2P_CAPTURE_DIR=/tmp/captures fvm flutter test test/features/p2p/p2p_screens_capture_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/testing.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

/// The books were recorded on 2026-11-10 between 13:51 and 13:55 UTC: the screens are rendered a few minutes later.
final _now = DateTime.utc(2026, 11, 10, 14);

const _fixtures = 'packages/robosats/test/fixtures/coordinator';

/// The example key of the RoboSats frontend tests, as `packages/robosats` records it: the only key the Garage captures show, never one drawn at random.
String _exampleGarageKey() =>
    ((jsonDecode(
                  File(
                    'packages/robosats/test/fixtures/robot-identity-vectors.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>)['garage_key']
            as Map<String, dynamic>)['garage_key']
        as String;

/// The phrases of the Tor wait in a fixed order, from the second one, « Peeling the onion, layer by layer », so that the captures do not change from one run to the next.
final _phrasesFromTheSecond = P2pShuffle(
  (count) => [for (var i = 0; i < count; i++) (i + 1) % count],
);

/// The `no_screenshot` plugin behind the capture protection of the Garage answers on this channel.
const _privacyChannel = MethodChannel('com.flutterplaza.no_screenshot_methods');

/// Answers each coordinator with its recorded `/api/book/` and `/api/info/`, a recorded `not_found` book with status 404, and as unreachable when nothing was recorded (lake on testnet, gumpellite).
final class _RecordedTransport implements CoordinatorTransport {
  final RobosatsNetwork network;

  /// Coordinators that answer as unreachable whatever was recorded.
  final Set<String> offline;

  /// Coordinators that do not answer during the captures, so that their book is still loading.
  final Set<String> held;

  /// The coordinators of the robot captures, which answer the requests of the robots: none without them.
  final _Robots? robots;

  const _RecordedTransport(
    this.network, {
    this.offline = const {},
    this.held = const {},
    this.robots,
  });

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final alias = Federation.robosats
        .on(network)
        .firstWhere(
          (c) =>
              Uri.parse(c.origins(network).onion ?? '').host ==
              request.url.host,
        )
        .shortAlias;
    if (request.robot != null) {
      return switch (robots) {
        final robots? => robots.answer(alias, request),
        null => const Err(CoordinatorUnreachable()),
      };
    }
    if (offline.contains(alias)) return const Err(CoordinatorUnreachable());
    if (held.contains(alias)) {
      return Completer<
            Result<CoordinatorResponse, CoordinatorTransportFailure>
          >()
          .future;
    }
    final endpoint = request.url.path.contains('info') ? 'info' : 'book';
    final file = File('$_fixtures/$alias-${network.name}-$endpoint.json');
    if (!file.existsSync()) return const Err(CoordinatorUnreachable());
    final body = file.readAsBytesSync();
    final notFound = utf8.decode(body).contains('not_found');
    return Ok(
      CoordinatorResponse(
        statusCode: notFound ? 404 : 200,
        headers: const {'content-type': 'application/json'},
        body: body,
      ),
    );
  }
}

/// The coordinators of the robot captures, for the robots of the example key only: each robot gets the replies the capture gives it, then is answered as the reference coordinator answers, which keeps the key pair of a first contact.
final class _Robots {
  final Map<Object, RobotIdentity> identities;

  /// The next replies to each robot, by its session key: `keep`, `offline`, `busy`, `taken` (7004), `unknown` (7001), `recent` (7002, key too recent), `refused` (7002), `html` or `other` (another robot).
  final Map<Object, List<String>> replies = {};

  /// Fields each answer about a robot carries, by its session key.
  final Map<Object, Map<String, Object?>> fields = {};

  /// What each coordinator keeps of each robot.
  final Map<(String, Object), Map<String, Object?>> kept = {};

  /// When set, every robot request waits for it.
  Completer<void>? hold;

  int requests = 0;

  _Robots(Iterable<RobotIdentity> robots)
    : identities = {for (final robot in robots) robot.sessionKey: robot};

  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> answer(
    String alias,
    CoordinatorRequest request,
  ) async {
    requests++;
    if (hold case final hold?) await hold.future;
    final key = request.robot;
    final identity = identities[key];
    if (key == null || identity == null) throw StateError('no such robot');
    final next = replies[key] ?? const <String>[];
    final reply = next.isEmpty ? 'keep' : next.removeAt(0);
    CoordinatorResponse json(int status, Object body) => CoordinatorResponse(
      statusCode: status,
      headers: const {'content-type': 'application/json'},
      body: utf8.encode(jsonEncode(body)),
    );
    switch (reply) {
      case 'offline':
        return const Err(CoordinatorUnreachable());
      case 'busy':
        return const Err(CoordinatorTransportBusy());
      case 'taken':
        return Ok(json(409, {'error_code': 7004, 'bad_request': 'taken'}));
      case 'unknown':
        return Ok(json(400, {'error_code': 7001, 'bad_request': 'unknown'}));
      case 'recent':
        return Ok(
          json(400, {
            'error_code': 7002,
            'bad_request': "{'error_code': 1056}",
          }),
        );
      case 'refused':
        return Ok(json(400, {'error_code': 7002, 'bad_request': 'refused'}));
      case 'html':
        return Ok(
          CoordinatorResponse(
            statusCode: 200,
            headers: const {'content-type': 'text/html'},
            body: utf8.encode('<html></html>'),
          ),
        );
    }
    final parts = (request.headers['Authorization'] ?? '').split(' | ');
    final place = (alias, key);
    if (parts.length == 4) {
      // A key block travels on one line, a backslash for each line break.
      String armored(String wire) => wire.replaceAll(r'\', '\n');
      kept.putIfAbsent(
        place,
        () => {
          'public_key': armored(parts[1].substring('Public '.length)),
          'encrypted_private_key': armored(
            parts[2].substring('Private '.length),
          ),
          'nostr_pubkey': parts[3].substring('Nostr '.length),
        },
      );
    }
    final robot = kept[place];
    if (robot == null) {
      return Ok(json(400, {'error_code': 7001, 'bad_request': 'unknown'}));
    }
    final shown = reply == 'other'
        ? identities.values.firstWhere((other) => other.sessionKey != key)
        : identity;
    return Ok(
      json(200, {
        'nickname': shown.nickname,
        'hash_id': shown.hashId.hex,
        ...robot,
        ...?fields[key],
      }),
    );
  }
}

Future<void> _loadFonts() async {
  Future<void> load(String family, Iterable<Future<ByteData>> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(file);
    }
    await loader.load();
  }

  await load('Golos Text', [rootBundle.load('assets/fonts/GolosText.ttf')]);
  await load('Bebas Neue', [
    rootBundle.load('assets/fonts/BebasNeue-Regular.ttf'),
  ]);
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(
        Platform.resolvedExecutable,
      ).parent.parent.parent.parent.parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    await load('MaterialIcons', [
      Future.value(ByteData.sublistView(icons.readAsBytesSync())),
    ]);
  }
  // The Garage Key and the robot number are drawn in the platform's monospace family, which a test has not: the Roboto Mono of the SDK's tools stands in for it.
  final mono = File(
    '$flutterRoot/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/Roboto_Mono/RobotoMono-Regular.ttf',
  );
  if (mono.existsSync()) {
    await load('monospace', [
      Future.value(ByteData.sublistView(mono.readAsBytesSync())),
    ]);
  }
}

void main() {
  final directory = Platform.environment['P2P_CAPTURE_DIR'];

  setUpAll(() async {
    if (directory != null) await _loadFonts();
  });

  for (final locale in const [Locale('fr'), Locale('en')]) {
    testWidgets('captures of the P2P tab in ${locale.languageCode}', skip: directory == null, (
      tester,
    ) async {
      final out = Directory(directory ?? '.')..createSync(recursive: true);
      tester.view
        ..physicalSize = const Size(780, 1688)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() async {
          final boundary =
              tester.renderObject(find.byKey(_frame)) as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png == null) throw StateError('no PNG for $name');
          File(
            '${out.path}/${locale.languageCode}-$name.png',
          ).writeAsBytesSync(png.buffer.asUint8List());
        });
      }

      /// The tab on [network]; Tor reports the states added to the controller returned, or the reports added to [reports] when given.
      Future<StreamController<P2pTorState>> show(
        RobosatsNetwork network, {
        Set<String> offline = const {},
        Set<String> held = const {},
        StreamController<P2pTorReport>? reports,
      }) async {
        final locator = GetIt.asNewInstance();
        final tor = StreamController<P2pTorState>.broadcast();
        addTearDown(tor.close);
        addTearDown(locator.reset);
        setUpP2pForTesting(
          locator,
          transport: _RecordedTransport(network, offline: offline, held: held),
          torStates: reports == null ? () => tor.stream : null,
          torReports: reports == null ? null : () => reports.stream,
          clock: () => _now,
          shuffle: _phrasesFromTheSecond,
        );
        await tester.pumpWidget(
          _App(locale: locale, locator: locator, network: network),
        );
        await tester.pump();
        return tor;
      }

      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
      }

      // The wait for Tor, on testnet so that its banner shows as in the mock-up: the first phrase of the fixed order, then Tor at 42 % of its start.
      // Both are shown within the first 2 seconds of the wait, once the phrase has faded in.
      final reports = StreamController<P2pTorReport>.broadcast();
      addTearDown(reports.close);
      var tor = await show(RobosatsNetwork.testnet, reports: reports);
      reports.add(P2pTorReport(P2pTorState.notStarted));
      await settle();
      await tester.pump(const Duration(milliseconds: 300));
      await capture('tor-initialisation');
      reports.add(P2pTorReport(P2pTorState.connecting, progress: 0.42));
      await settle();
      await capture('tor');
      reports.add(P2pTorReport(P2pTorState.failed));
      await settle();
      await capture('tor-erreur');
      reports.add(P2pTorReport(P2pTorState.ready));
      await settle();
      await capture('offres-testnet-vide');

      // The wait for the book: no coordinator has answered yet, then only Temple of Sats has.
      final mainnet = {
        for (final coordinator in Federation.robosats.on(
          RobosatsNetwork.mainnet,
        ))
          coordinator.shortAlias,
      };
      tor = await show(RobosatsNetwork.mainnet, held: mainnet);
      tor.add(P2pTorState.ready);
      await settle();
      await capture('offres-attente');
      tor = await show(
        RobosatsNetwork.mainnet,
        held: mainnet.difference({'temple'}),
      );
      tor.add(P2pTorState.ready);
      await settle();
      await capture('offres-attente-partielle');

      // The recorded mainnet books.
      tor = await show(RobosatsNetwork.mainnet);
      tor.add(P2pTorState.ready);
      await settle();
      await capture('offres-tous');

      final l10n = lookupP2pLocalizations(locale);
      // The depth chart of every order received, then back to the list.
      await tester.tap(find.text(l10n.p2pBookViewChart));
      await settle();
      // Lets the view bar slide to its new segment.
      await tester.pump(const Duration(seconds: 1));
      await capture('graphique-tous');
      await tester.tap(find.text(l10n.p2pBookViewList));
      await settle();

      // « I want to Buy and use EUR », the choices of the mock-up.
      await tester.tap(find.text(l10n.p2pBookFilterAny).first);
      await settle();
      await tester.tap(find.text(l10n.p2pBookFilterBuy).last);
      await settle();
      await tester.tap(find.text(l10n.p2pBookFilterAny).first);
      await settle();
      await tester.tap(find.text('EUR').last);
      await settle();
      await capture('offres');

      // The depth chart under the currency of the filter: on the premium axis, with an order under the finger, then on the price axis.
      await tester.tap(find.text(l10n.p2pBookViewChart));
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('graphique');
      final plot = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_DepthChartPainter',
      );
      final finger = await tester.startGesture(
        tester.getCenter(plot) + const Offset(40, -60),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await settle();
      await capture('graphique-ordre');
      await finger.up();
      await settle();
      await tester.tap(find.text(l10n.p2pBookColumnPremium));
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text(l10n.p2pBookColumnPrice));
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('graphique-prix');
      await tester.tap(find.text(l10n.p2pBookViewList));
      await settle();

      await tester.tap(find.textContaining(' EUR', findRichText: true).first);
      // Lets the page transition end.
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await settle();
      await capture('offre');

      // The reversible payments warning of RoboSats, when the order offers such a method.
      final warning = find.byIcon(Icons.warning_amber_rounded);
      if (warning.evaluate().isNotEmpty) {
        await tester.tap(warning.first);
        await settle();
        await tester.pump(const Duration(seconds: 1));
        await capture('paiements-reversibles');
        await tester.tap(find.text(l10n.p2pCommonAcknowledged));
        await settle();
        await tester.pump(const Duration(seconds: 1));
      }

      // The dialog of the coordinator that hosts the order, then its summary and its statistics.
      await tester.tap(find.text(l10n.p2pOrderHost));
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('coordinateur');
      for (final (section, name) in [
        (l10n.p2pCoordinatorPolicies, 'coordinateur-politiques'),
        (l10n.p2pCoordinatorSummary, 'coordinateur-resume'),
        (l10n.p2pCoordinatorStatsForNerds, 'coordinateur-stats'),
      ]) {
        await tester.ensureVisible(find.text(section));
        await settle();
        await tester.tap(find.text(section));
        await settle();
        await tester.ensureVisible(find.text(section));
        await settle();
        await capture(name);
      }
      // A tap outside closes the dialog, then the back arrow returns to the book.
      await tester.tapAt(const Offset(4, 4));
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byIcon(Icons.arrow_back));
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await settle();

      // « Search », the order URL dialog of RoboSats: empty, refused, then an order the public book does not hold.
      await tester.tap(find.text(l10n.p2pCommonSearch));
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('rechercher');
      final field = find.byType(TextField);
      await tester.enterText(field, 'temple 48213');
      await tester.tap(find.text(l10n.p2pCommonSearch).last);
      await settle();
      await capture('rechercher-erreur');
      final temple = Federation.robosats.byAlias('temple')?.mainnet.onion;
      await tester.enterText(field, '$temple/order/temple/1');
      await tester.tap(find.text(l10n.p2pCommonSearch).last);
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('sans-robot');

      // The chart on a small phone, 320 by 568 points, with four coordinators offline above it (Gumpellite answers nothing recorded): their state scrolls with the chart.
      tester.view.physicalSize = const Size(640, 1136);
      tor = await show(
        RobosatsNetwork.mainnet,
        offline: {'lake', 'bazaar', 'freeport', 'ammanaya'},
      );
      tor.add(P2pTorState.ready);
      await settle();
      await tester.tap(find.text(l10n.p2pBookViewChart));
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('graphique-hors-ligne-petit');
      await tester.drag(
        find.textContaining('TheBigLake').first,
        const Offset(0, -600),
      );
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('graphique-hors-ligne-petit-bas');
    });
  }

  // The Garage, over a vault in memory, on testnet: the welcome, the wizard with the public example key pasted, its robot, the third step, the profile with the key hidden then shown after the PIN, « Delete All » and « Robot recovery », then a key drawn in memory, never shown: its backup alert, and the robot step and profile of a draw whose history could not be recorded.
  for (final locale in const [Locale('fr'), Locale('en')]) {
    testWidgets('captures of the Garage in ${locale.languageCode}', skip: directory == null, (
      tester,
    ) async {
      final out = Directory(directory ?? '.')..createSync(recursive: true);
      tester.view
        ..physicalSize = const Size(780, 1688)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_privacyChannel, (call) async => true);
      addTearDown(
        () => messenger.setMockMethodCallHandler(_privacyChannel, null),
      );

      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() async {
          final boundary =
              tester.renderObject(find.byKey(_frame)) as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png == null) throw StateError('no PNG for $name');
          File(
            '${out.path}/${locale.languageCode}-$name.png',
          ).writeAsBytesSync(png.buffer.asUint8List());
        });
      }

      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        // A page or a dialog opened or closed.
        await tester.pump(const Duration(seconds: 1));
      }

      // An empty slot is believed after the vault's full read budget, about 4.5 s.
      Future<void> vault() async {
        await settle();
        await tester.pump(const Duration(seconds: 6));
        await settle();
      }

      FakeSecureStoragePlatform().install();
      final locator = GetIt.asNewInstance();
      final tor = StreamController<P2pTorState>.broadcast();
      addTearDown(tor.close);
      addTearDown(locator.reset);
      setUpP2pForTesting(
        locator,
        transport: const _RecordedTransport(RobosatsNetwork.testnet),
        torStates: () => tor.stream,
        clock: () => _now,
        garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      );
      await tester.pumpWidget(
        _App(
          locale: locale,
          locator: locator,
          network: RobosatsNetwork.testnet,
        ),
      );
      tor.add(P2pTorState.ready);
      await settle();
      final l10n = lookupP2pLocalizations(locale);
      final example = _exampleGarageKey();

      await tester.tap(find.text(l10n.p2pNavGarage));
      await vault();
      await capture('garage-accueil');
      await tester.tap(find.text(l10n.p2pGarageWelcomeStart));
      await settle();
      await capture('garage-etape1');
      await tester.enterText(find.byType(EditableText), example);
      await settle();
      await capture('garage-etape1-cle-collee');
      await tester.tap(find.text(l10n.p2pCommonContinue));
      await vault();
      await capture('garage-etape2');
      await tester.tap(find.text(l10n.p2pCommonContinue));
      await settle();
      await capture('garage-etape3');
      await tester.tapOnText(
        find.textRange.ofSubstring(l10n.p2pGarageOnboardingHelpLink),
      );
      await settle();
      await capture('garage-lien-simplex');
      await tester.tapAt(const Offset(4, 4));
      await settle();
      await tester.tap(find.text(l10n.p2pGarageSeeProfile));
      await settle();
      // The Tor of the test seam tells its state to the listeners it has when it changes: the robot panel, shown now, is told that Tor is ready.
      tor.add(P2pTorState.ready);
      await settle();
      await capture('garage-profil');
      await tester.tap(find.text(l10n.p2pGarageKeyReveal));
      await settle();
      await capture('garage-pin-factice');
      await tester.tap(find.text('PIN'));
      await settle();
      // The robot panel sits above the key: the key and « Delete All » are scrolled to.
      await tester.ensureVisible(find.text(l10n.p2pGarageProfileDeleteAll));
      await settle();
      await capture('garage-profil-cle');
      await tester.tap(find.text(l10n.p2pGarageProfileDeleteAll));
      await settle();
      await capture('garage-supprimer');
      await tester.tap(find.text(l10n.p2pDeleteKeyConfirm));
      await settle();
      // The pasted key may have robots on a coordinator: the PIN comes after the confirmation.
      await tester.tap(find.text('PIN'));
      await settle();
      await tester.tap(find.text(l10n.p2pGarageWelcomeRecovery));
      await settle();
      await tester.enterText(find.byType(EditableText), example);
      await settle();
      await capture('garage-recuperation');

      // The backup step of a key drawn in memory, after a trip to the background: the alert stays and the key is behind the PIN, so the capture holds no key.
      await tester.tapAt(const Offset(4, 4));
      await settle();
      await tester.tap(find.text(l10n.p2pGarageWelcomeStart));
      await settle();
      await tester.tap(find.text(l10n.p2pGarageOnboardingGenerateKey));
      await vault();
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      await settle();
      if (find.text(l10n.p2pGarageKeyReveal).evaluate().isEmpty) {
        throw StateError('the backup step does not hide the key');
      }
      await capture('garage-alerte-sauvegarde');

      // A draw whose history the feature's database could not record: the robot step and the profile say so.
      // The key is drawn in memory and never captured: hidden by a trip to the background, then shown behind the PIN only to reach « Continue », and captured only on the steps that do not show it.
      FakeSecureStoragePlatform().install();
      final unrecorded = GetIt.asNewInstance();
      addTearDown(unrecorded.reset);
      setUpP2pForTesting(
        unrecorded,
        transport: const _RecordedTransport(RobosatsNetwork.testnet),
        torStates: () => tor.stream,
        clock: () => _now,
        garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
        databaseUnavailable: true,
      );
      await tester.pumpWidget(
        _App(
          locale: locale,
          locator: unrecorded,
          network: RobosatsNetwork.testnet,
        ),
      );
      // The first Garage is gone: its database is closed before the second one opens.
      await locator.reset();
      tor.add(P2pTorState.ready);
      await settle();
      await tester.tap(find.text(l10n.p2pNavGarage));
      await vault();
      await tester.tap(find.text(l10n.p2pGarageWelcomeStart));
      await settle();
      await tester.tap(find.text(l10n.p2pGarageOnboardingGenerateKey));
      await vault();
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      await settle();
      await tester.tap(find.text(l10n.p2pGarageKeyReveal));
      await settle();
      await tester.tap(find.text('PIN'));
      await settle();
      await tester.tap(find.text(l10n.p2pCommonContinue));
      await settle();
      if (find.text(l10n.p2pGarageKeyHistoryNotRecorded).evaluate().isEmpty) {
        throw StateError('the robot step does not say the history');
      }
      await capture('garage-etape2-historique-non-enregistre');
      await tester.tap(find.text(l10n.p2pCommonContinue));
      await settle();
      await tester.tap(find.text(l10n.p2pGarageSeeProfile));
      await settle();
      await capture('garage-profil-historique-non-enregistre');
    });
  }

  // The robot panel of the Garage, on mainnet so that « Select Host » lists every coordinator (Gumpellite, not recorded, shows as offline), over the public example key, pasted, then acknowledged through the test seam as the acknowledgement of a later step will: Tor on its way, a robot without a coordinator, « Select Host », the confirmation, the first contact and its long wait, the card of a robot in its states, every failure with a text, a coordinator closed by its refusals, and a robot read back.
  // The coordinators are fakes that keep the key pair the robot sent: nothing leaves the test.
  for (final locale in const [Locale('fr'), Locale('en')]) {
    testWidgets(
      'captures of the robot panel in ${locale.languageCode}',
      skip: directory == null,
      timeout: const Timeout(Duration(minutes: 10)),
      (tester) async {
        final out = Directory(directory ?? '.')..createSync(recursive: true);
        tester.view
          ..physicalSize = const Size(780, 1688)
          ..devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          _privacyChannel,
          (call) async => true,
        );
        addTearDown(
          () => messenger.setMockMethodCallHandler(_privacyChannel, null),
        );

        Future<void> capture(String name) async {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(() async {
            final boundary =
                tester.renderObject(find.byKey(_frame))
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            if (png == null) throw StateError('no PNG for $name');
            File(
              '${out.path}/${locale.languageCode}-$name.png',
            ).writeAsBytesSync(png.buffer.asUint8List());
          });
        }

        Future<void> settle() async {
          for (var i = 0; i < 10; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
          await tester.pump(const Duration(seconds: 1));
        }

        // The key pair of a first contact is made, and a read back proven, in an isolate: real time passes for them.
        Future<void> waitFor(Finder finder) async {
          for (var i = 0; i < 600 && finder.evaluate().isEmpty; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          if (finder.evaluate().isEmpty) throw StateError('not shown: $finder');
          await settle();
        }

        final l10n = lookupP2pLocalizations(locale);

        final exampleText = _exampleGarageKey();
        final example = switch (GarageKey.parse(exampleText)) {
          Ok(:final value) => value,
          Err() => throw StateError('not a key'),
        };
        final identities = [
          for (var i = 0; i < 13; i++)
            switch (example.deriveIdentity(i)) {
              Ok(:final value) => value,
              Err() => throw StateError('no robot $i'),
            },
        ];
        final robots = _Robots(identities);
        Object robot(int index) => identities[index].sessionKey;

        /// Waits until the coordinators have received [count] robot requests in all.
        Future<void> untilRequests(int count) async {
          for (var i = 0; i < 600 && robots.requests < count; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          if (robots.requests < count) throw StateError('no request');
        }

        FakeSecureStoragePlatform().install();
        final locator = GetIt.asNewInstance();
        final tor = StreamController<P2pTorState>.broadcast();
        addTearDown(tor.close);
        addTearDown(locator.reset);
        setUpP2pForTesting(
          locator,
          transport: _RecordedTransport(
            RobosatsNetwork.mainnet,
            robots: robots,
          ),
          torStates: () => tor.stream,
          clock: () => _now,
          garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
        );
        await tester.pumpWidget(
          _App(
            locale: locale,
            locator: locator,
            network: RobosatsNetwork.mainnet,
          ),
        );
        // The Tor of the test seam tells its state to the listeners it has when the state changes, where the app's Tor also tells a new listener the state it is in: each panel shown after Tor is ready is told so again.
        tor.add(P2pTorState.connecting);
        await settle();

        /// Moves to the next robot, the navigator scrolled to first, and tells its panel that Tor is ready.
        Future<void> nextRobot() async {
          final next = find.byTooltip(l10n.p2pGarageNextAccount);
          await tester.ensureVisible(next);
          await settle();
          await tester.tap(next);
          await settle();
          tor.add(P2pTorState.ready);
          await settle();
        }

        // The example key, pasted from the welcome screen, then acknowledged.
        await tester.tap(find.text(l10n.p2pNavGarage));
        await settle();
        await tester.pump(const Duration(seconds: 6));
        await settle();
        await tester.tap(find.text(l10n.p2pGarageWelcomeRecovery));
        await settle();
        await tester.enterText(find.byType(EditableText), exampleText);
        await settle();
        await tester.tap(find.text(l10n.p2pRecoveryRecover));
        await settle();
        await tester.pump(const Duration(seconds: 6));
        await settle();
        final acknowledged = await tester.runAsync(
          () =>
              acknowledgeGarageKeyForTesting(locator, RobosatsNetwork.mainnet),
        );
        if (acknowledged != true) throw StateError('not acknowledged');
        // The panel reads where its robot stands when it is shown.
        await tester.tap(find.byTooltip(l10n.p2pGarageNextAccount));
        await settle();
        await tester.tap(find.byTooltip(l10n.p2pGaragePreviousAccount));
        await settle();
        await tester.ensureVisible(find.text(l10n.p2pRobotSelectHost));
        await settle();
        await capture('robot-attente-tor');

        tor.add(P2pTorState.ready);
        await settle();
        await capture('robot-sans-coordinateur');

        // « Select Host », its confirmation, then the first contact with Temple of Sats, which takes its time.
        await tester.tap(find.text(l10n.p2pRobotSelectHost));
        await settle();
        await capture('robot-choisir-hote');
        await tester.tap(find.text('Temple of Sats'));
        await settle();
        await capture('robot-envoyer');
        robots.hold = Completer<void>();
        await tester.tap(find.text(l10n.p2pCommonContinue));
        await settle();
        for (var i = 0; i < 600 && robots.requests == 0; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
        await settle();
        await capture('robot-construction');
        await tester.pump(const Duration(seconds: 31));
        await settle();
        await capture('robot-attente-longue');
        robots.hold?.complete();
        robots.hold = null;
        await waitFor(find.text(l10n.p2pRobotNoOrders));
        await capture('robot-temple');

        /// Moves to the next robot, puts it on [host] and waits for [shown].
        Future<void> nextOn(String host, Finder shown) async {
          await nextRobot();
          await tester.ensureVisible(find.text(l10n.p2pRobotSelectHost));
          await settle();
          await tester.tap(find.text(l10n.p2pRobotSelectHost));
          await settle();
          await tester.tap(find.text(host));
          await settle();
          await tester.tap(find.text(l10n.p2pCommonContinue));
          await settle();
          await waitFor(shown);
          await tester.ensureVisible(shown);
          await settle();
        }

        // Robot 1 already lived on TheBigLake, made elsewhere with another key pair: a last order, rewards, and an old Nostr key.
        final pair = await tester.runAsync(
          () async => RobotPgpKey.generate(identities[1]),
        );
        final otherPair = switch (pair) {
          Ok(:final value) => value,
          _ => throw StateError('no pair'),
        };
        robots.kept[('lake', robot(1))] = {
          'public_key': otherPair.publicKey.armored,
          'encrypted_private_key': otherPair.encryptedPrivateKeyArmored,
          'nostr_pubkey': identities[1].nostrKeyPair().publicKeyHex,
        };
        robots.fields[robot(1)] = {
          'last_order_id': 4321,
          'earned_rewards': 3500,
          'nostr_pubkey': identities[1]
              .nostrKeyPair(NostrKeyDerivation.repositoryFixtures)
              .publicKeyHex,
        };
        await nextOn(
          'TheBigLake',
          find.text(l10n.p2pRobotAlreadyExisted('TheBigLake')),
        );
        await capture('robot-deja-connu');

        // Robot 2: an order in progress on LibreBazaar, which holds a Nostr key this app cannot use.
        robots.fields[robot(2)] = {
          'active_order_id': 77,
          'last_order_id': 76,
          'nostr_pubkey': '0' * 64,
        };
        await nextOn('LibreBazaar', find.text(l10n.p2pRobotActiveOrder('77')));
        await capture('robot-ordre-actif');

        // Robot 3: FreePort says its nickname is taken, and again 10 seconds later.
        robots.replies[robot(3)] = ['taken'];
        await nextRobot();
        await tester.ensureVisible(find.text(l10n.p2pRobotSelectHost));
        await settle();
        await tester.tap(find.text(l10n.p2pRobotSelectHost));
        await settle();
        await tester.tap(find.text('FreePort'));
        await settle();
        final beforeTaken = robots.requests;
        await tester.tap(find.text(l10n.p2pCommonContinue));
        await settle();
        // The first contact, then the client's own read with the short header.
        await untilRequests(beforeTaken + 2);
        await tester.pump(const Duration(seconds: 11));
        await waitFor(find.text(l10n.p2pRobotNicknameTaken('FreePort')));
        await capture('robot-nom-pris');

        // Robot 4: Ammanaya cannot be reached; « Retry » reads it back, and it never created the robot.
        robots.replies[robot(4)] = ['offline', 'unknown'];
        await nextOn('Ammanaya', find.text(l10n.p2pCommonRetry));
        await capture('robot-hors-ligne');
        await tester.tap(find.text(l10n.p2pCommonRetry));
        await settle();
        await waitFor(find.text(l10n.p2pRobotNotCreated('Ammanaya')));
        await capture('robot-inconnu');

        // Robots 5 to 9: the other refusals, each with its text.
        robots.replies[robot(5)] = ['recent'];
        await nextOn(
          'Temple of Sats',
          find.text(l10n.p2pRobotKeyTooRecent('Temple of Sats')),
        );
        await capture('robot-cle-trop-recente');
        robots.replies[robot(6)] = ['refused'];
        await nextOn(
          'Temple of Sats',
          find.text(l10n.p2pRobotRefused('Temple of Sats')),
        );
        await capture('robot-refuse');
        robots.replies[robot(7)] = ['other'];
        await nextOn(
          'Temple of Sats',
          find.text(l10n.p2pRobotMismatch('Temple of Sats')),
        );
        await capture('robot-autre-robot');
        robots.replies[robot(8)] = ['html'];
        await nextOn(
          'TheBigLake',
          find.text(l10n.p2pRobotBadAnswer('TheBigLake')),
        );
        await capture('robot-reponse-illisible');
        robots.replies[robot(9)] = ['busy', 'busy', 'busy', 'busy'];
        await nextRobot();
        await tester.ensureVisible(find.text(l10n.p2pRobotSelectHost));
        await settle();
        await tester.tap(find.text(l10n.p2pRobotSelectHost));
        await settle();
        await tester.tap(find.text('TheBigLake'));
        await settle();
        final beforeBusy = robots.requests;
        await tester.tap(find.text(l10n.p2pCommonContinue));
        await settle();
        // Four attempts, after waits of about 2, 4 and 8 seconds.
        for (var attempt = 1; attempt <= 4; attempt++) {
          await untilRequests(beforeBusy + attempt);
          await tester.pump(const Duration(seconds: 10));
        }
        await waitFor(find.text(l10n.p2pRobotBusy));
        await capture('robot-occupe');

        // Robots 10 and 11: two more nicknames taken on FreePort, which then refuses first contacts in this run.
        for (final index in [10, 11]) {
          robots.replies[robot(index)] = ['taken'];
          await nextRobot();
          await tester.ensureVisible(find.text(l10n.p2pRobotSelectHost));
          await settle();
          await tester.tap(find.text(l10n.p2pRobotSelectHost));
          await settle();
          await tester.tap(find.text('FreePort'));
          await settle();
          final before = robots.requests;
          await tester.tap(find.text(l10n.p2pCommonContinue));
          await settle();
          await untilRequests(before + 2);
          await tester.pump(const Duration(seconds: 11));
          await waitFor(find.text(l10n.p2pRobotNicknameTaken('FreePort')));
        }
        await nextRobot();
        await tester.ensureVisible(find.text(l10n.p2pRobotSelectHost));
        await settle();
        await tester.tap(find.text(l10n.p2pRobotSelectHost));
        await settle();
        await capture('robot-hote-ferme');
        await tester.tapAt(const Offset(4, 4));
        await settle();

        // Back to robot 0: read back from Temple of Sats, as at each display; the robots passed on the way are read back too, and let go at once.
        for (var i = 0; i < 11; i++) {
          await tester.ensureVisible(
            find.byTooltip(l10n.p2pGaragePreviousAccount),
          );
          await tester.pump();
          await tester.tap(find.byTooltip(l10n.p2pGaragePreviousAccount));
          await tester.pump();
        }
        await settle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 3)),
        );
        await tester.pump(const Duration(seconds: 11));
        await settle();
        robots.hold = Completer<void>();
        await tester.ensureVisible(
          find.byTooltip(l10n.p2pGaragePreviousAccount),
        );
        await settle();
        await tester.tap(find.byTooltip(l10n.p2pGaragePreviousAccount));
        await settle();
        tor.add(P2pTorState.ready);
        await settle();
        await waitFor(find.text(l10n.p2pRobotLookingForOrders));
        await tester.ensureVisible(find.text(l10n.p2pRobotLookingForOrders));
        await settle();
        await capture('robot-relecture');
        robots.hold?.complete();
        robots.hold = null;
        await waitFor(find.text(l10n.p2pRobotNoOrders));
        await capture('robot-relu');
        // The releases of the robots passed on the way wait for their requests, 10 s at most.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 3)),
        );
        await tester.pump(const Duration(seconds: 11));
      },
    );
  }
}

const _frame = ValueKey('p2p-capture-frame');

/// The P2P tab inside a bottom bar like the one of the shell: Wallet, P2P, Exchange.
class _App extends StatelessWidget {
  final Locale locale;
  final GetIt locator;
  final RobosatsNetwork network;

  const _App({
    required this.locale,
    required this.locator,
    required this.network,
  });

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [
        ShellRoute(
          builder: (context, state, child) {
            final colors = Theme.of(context).bottomNavigationBarTheme;
            return Scaffold(
              body: child,
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: 1,
                backgroundColor: colors.backgroundColor,
                type: BottomNavigationBarType.fixed,
                items: [
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.currency_bitcoin),
                    label: AppLocalizations.of(context).navigationTabWallet,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.swap_horiz),
                    label: P2pLocalizations.of(context).p2pTabLabel,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.attach_money),
                    label: AppLocalizations.of(context).navigationTabExchange,
                  ),
                ],
              ),
            );
          },
          routes: [
            const P2pFeature().route(
              locator,
              network: (_) => network,
              // A stand-in for the wallet's PIN screen, which needs the app's own locator: one button that passes.
              reauthenticate: (onAuthenticated) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: onAuthenticated,
                    child: const Text('PIN'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    return RepaintBoundary(
      key: _frame,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.themeData(AppThemeType.dark),
        locale: locale,
        localizationsDelegates: [
          ...AppLocalizations.localizationsDelegates,
          P2pLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }
}
