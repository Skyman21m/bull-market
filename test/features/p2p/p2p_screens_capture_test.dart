// Renders the screens of the P2P tab to PNG files, with the real widgets, the dark theme and fonts of the app, and the books recorded from the live federation.
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

/// The books were recorded on 2026-11-10 between 13:51 and 13:55 UTC: the screens are rendered a few minutes later.
final _now = DateTime.utc(2026, 11, 10, 14);

const _fixtures = 'packages/robosats/test/fixtures/coordinator';

/// Answers each coordinator with its recorded `/api/book/` and `/api/info/`, a recorded `not_found` book with status 404, and as unreachable when nothing was recorded (lake on testnet, gumpellite).
final class _RecordedTransport implements CoordinatorTransport {
  final RobosatsNetwork network;

  const _RecordedTransport(this.network);

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
}

void main() {
  final directory = Platform.environment['P2P_CAPTURE_DIR'];

  setUpAll(() async {
    if (directory != null) await _loadFonts();
  });

  for (final locale in const [Locale('fr'), Locale('en')]) {
    testWidgets(
      'captures of the P2P tab in ${locale.languageCode}',
      skip: directory == null,
      (tester) async {
        final out = Directory(directory ?? '.')..createSync(recursive: true);
        tester.view
          ..physicalSize = const Size(780, 1688)
          ..devicePixelRatio = 2;
        addTearDown(tester.view.reset);

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

        Future<StreamController<P2pTorState>> show(
          RobosatsNetwork network,
        ) async {
          final locator = GetIt.asNewInstance();
          final tor = StreamController<P2pTorState>.broadcast();
          addTearDown(tor.close);
          addTearDown(locator.reset);
          setUpP2pForTesting(
            locator,
            transport: _RecordedTransport(network),
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
          routes: [const P2pFeature().route(locator, network: (_) => network)],
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
