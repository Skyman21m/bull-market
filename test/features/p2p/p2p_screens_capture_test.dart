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

/// The `no_screenshot` plugin behind the capture protection of the Garage answers on this channel.
const _privacyChannel = MethodChannel('com.flutterplaza.no_screenshot_methods');

/// Answers each coordinator with its recorded `/api/book/` and `/api/info/`, a recorded `not_found` book with status 404, and as unreachable when nothing was recorded (lake on testnet, gumpellite).
final class _RecordedTransport implements CoordinatorTransport {
  final RobosatsNetwork network;

  /// Coordinators that answer as unreachable whatever was recorded.
  final Set<String> offline;

  /// Coordinators that do not answer during the captures, so that their book is still loading.
  final Set<String> held;

  const _RecordedTransport(
    this.network, {
    this.offline = const {},
    this.held = const {},
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

      Future<StreamController<P2pTorState>> show(
        RobosatsNetwork network, {
        Set<String> offline = const {},
        Set<String> held = const {},
      }) async {
        final locator = GetIt.asNewInstance();
        final tor = StreamController<P2pTorState>.broadcast();
        addTearDown(tor.close);
        addTearDown(locator.reset);
        setUpP2pForTesting(
          locator,
          transport: _RecordedTransport(network, offline: offline, held: held),
          torStates: () => tor.stream,
          clock: () => _now,
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

      // The wait for Tor, on testnet so that its banner shows as in the mock-up.
      var tor = await show(RobosatsNetwork.testnet);
      tor.add(P2pTorState.notStarted);
      await settle();
      await capture('tor-initialisation');
      tor.add(P2pTorState.connecting);
      await settle();
      await capture('tor');
      tor.add(P2pTorState.failed);
      await settle();
      await capture('tor-erreur');
      tor.add(P2pTorState.ready);
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
    testWidgets(
      'captures of the Garage in ${locale.languageCode}',
      skip: directory == null,
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
        await capture('garage-profil');
        await tester.tap(find.text(l10n.p2pGarageKeyReveal));
        await settle();
        await capture('garage-pin-factice');
        await tester.tap(find.text('PIN'));
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
