// Renders the screens of the P2P tab to PNG files, with the real widgets, the dark theme and fonts of the app, and the books recorded from the live federation, then the Garage over a vault in memory with the public example key of the RoboSats tests.
// They are review material, compared by eye with the validated mock-up: nothing is asserted on the pixels.
// Skipped unless P2P_CAPTURE_DIR names the folder to write to, for example:
// P2P_CAPTURE_DIR=/tmp/captures fvm flutter test test/features/p2p/p2p_screens_capture_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_failure.dart';
import 'package:bb_mobile/features/p2p_garage_key/derived_garage_key_adapter.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/testing.dart';
import 'package:secrets/secrets.dart' show GarageKeySlot, Secrets;
import 'package:secrets/testing.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

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

  /// Coordinators that answer an empty book (`not_found`, status 404) when nothing was recorded for them.
  final Set<String> empty;

  /// The coordinators of the robot captures, which answer the requests of the robots: none without them.
  final _Robots? robots;

  const _RecordedTransport(
    this.network, {
    this.offline = const {},
    this.held = const {},
    this.empty = const {},
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
    final path = request.url.path;
    final endpoint = path.contains('info')
        ? 'info'
        : path.contains('limits')
        ? 'limits'
        : 'book';
    final file = File('$_fixtures/$alias-${network.name}-$endpoint.json');
    if (!file.existsSync() && endpoint == 'book' && empty.contains(alias)) {
      return Ok(
        CoordinatorResponse(
          statusCode: 404,
          headers: const {'content-type': 'application/json'},
          body: utf8.encode('{"not_found": "No orders found"}'),
        ),
      );
    }
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

/// The books of the map captures: orders of the test's own, each in a city, paid in cash face to face, or without their positions unless [located]; a coordinator not listed answers an empty book, and those of [offline] answer as unreachable.
final class _MapTransport implements CoordinatorTransport {
  final Set<String> offline;
  final bool located;

  const _MapTransport({this.offline = const {}, this.located = true});

  /// By coordinator: the id, the type (0 buy, 1 sell), the currency id, the amount, the latitude and the longitude of each order.
  static const _books = <String, List<(int, int, int, String, String, String)>>{
    'temple': [
      (1, 1, 2, '150', '48.8566', '2.3522'),
      (2, 0, 2, '300', '52.5200', '13.4050'),
      (3, 1, 2, '80', '40.4168', '-3.7038'),
      (4, 0, 2, '200', '41.9028', '12.4964'),
      (5, 1, 2, '120', '52.3676', '4.9041'),
      (6, 1, 2, '100', '38.7223', '-9.1393'),
      (7, 0, 2, '250', '38.7223', '-9.1393'),
      (8, 1, 2, '60', '38.7223', '-9.1393'),
    ],
    'lake': [
      (1, 1, 1, '500', '40.7128', '-74.0060'),
      (2, 0, 1, '150', '41.8781', '-87.6298'),
      (3, 1, 15, '2000', '19.4326', '-99.1332'),
      (4, 0, 20, '600', '-23.5505', '-46.6333'),
      (5, 1, 30, '90000', '-34.6037', '-58.3816'),
    ],
    'bazaar': [
      (1, 1, 46, '10000', '-1.2921', '36.8219'),
      (2, 0, 50, '80000', '6.5244', '3.3792'),
      (3, 1, 3, '20000', '35.6762', '139.6503'),
    ],
    'freeport': [
      (1, 0, 5, '200', '-33.8688', '151.2093'),
      (2, 1, 4, '100', '51.5074', '-0.1278'),
      (3, 0, 7, '150', '47.3769', '8.5417'),
    ],
  };

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final alias = Federation.robosats
        .on(RobosatsNetwork.mainnet)
        .firstWhere(
          (c) =>
              Uri.parse(c.origins(RobosatsNetwork.mainnet).onion ?? '').host ==
              request.url.host,
        )
        .shortAlias;
    if (offline.contains(alias)) return const Err(CoordinatorUnreachable());
    CoordinatorResponse json(int status, Object body) => CoordinatorResponse(
      statusCode: status,
      headers: const {'content-type': 'application/json'},
      body: utf8.encode(jsonEncode(body)),
    );
    final book = _books[alias];
    if (book == null) return Ok(json(404, {'not_found': 'No orders found'}));
    return Ok(
      json(200, [
        for (final (id, type, currency, amount, latitude, longitude) in book)
          {
            'id': id,
            'created_at': _now
                .subtract(const Duration(hours: 3))
                .toIso8601String(),
            'expires_at': _now.add(const Duration(hours: 20)).toIso8601String(),
            'type': type,
            'currency': currency,
            'amount': amount,
            'has_range': false,
            'min_amount': null,
            'max_amount': null,
            'payment_method': 'Cash F2F',
            'is_explicit': false,
            'premium': '${(id % 5) - 1}.5',
            'satoshis': null,
            'maker': 1,
            'escrow_duration': 10800,
            'bond_size': '3.0',
            'latitude': located ? latitude : null,
            'longitude': located ? longitude : null,
            // A maker of the test: a hash id drawn from the coordinator and the order, no robot of anyone.
            'maker_hash_id': sha256
                .convert(utf8.encode('troc map capture $alias $id'))
                .toString(),
            'satoshis_now': 150000,
            'price': null,
            'maker_status': 'Active',
          },
      ]),
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
        Set<String> empty = const {},
        StreamController<P2pTorReport>? reports,
      }) async {
        final locator = GetIt.asNewInstance();
        final tor = StreamController<P2pTorState>.broadcast();
        addTearDown(tor.close);
        addTearDown(locator.reset);
        setUpP2pForTesting(
          locator,
          transport: _RecordedTransport(
            network,
            offline: offline,
            held: held,
            empty: empty,
          ),
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

      /// Lets the book ask again, after 5 then 15 seconds, the coordinators that gave no answer, until they are shown offline.
      Future<void> settleAttempts() async {
        for (var i = 0; i < 22; i++) {
          await tester.pump(const Duration(seconds: 1));
          await settle();
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
      // Lake on testnet, which answers nothing recorded, is shown offline after its attempts.
      await settleAttempts();
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

      // The row of the coordinators: TheBigLake and LibreBazaar do not answer, and Gumpellite has nothing recorded; first they are asked again, then shown offline with « Retry ».
      tor = await show(RobosatsNetwork.mainnet, offline: {'lake', 'bazaar'});
      tor.add(P2pTorState.ready);
      await settle();
      await capture('offres-redemande');
      await settleAttempts();
      await capture('offres-hors-ligne');

      // Every coordinator answered: Gumpellite answers an empty book here.
      tor = await show(RobosatsNetwork.mainnet, empty: {'gumpellite'});
      tor.add(P2pTorState.ready);
      await settle();
      await capture('offres-tous-repondu');

      // The recorded mainnet books, Gumpellite offline once asked again.
      tor = await show(RobosatsNetwork.mainnet);
      tor.add(P2pTorState.ready);
      await settle();
      await settleAttempts();
      await capture('offres-tous');
      // The filter sentence with nothing chosen: each selector names its subject (#101).
      await capture('filtres-rien');

      final l10n = lookupP2pLocalizations(locale);
      // The close button of the filter's sheet.
      final close = find.byIcon(Icons.close).last;
      String host(String alias) =>
          Federation.robosats.byAlias(alias)?.longAlias ?? alias;
      // The depth chart of every order received, then back to the list.
      await tester.tap(find.text(l10n.p2pBookViewChart));
      await settle();
      // Lets the view bar slide to its new segment.
      await tester.pump(const Duration(seconds: 1));
      await capture('graphique-tous');
      await tester.tap(find.text(l10n.p2pBookViewList));
      await settle();

      // « I want to Buy and use EUR », the choices of the mock-up.
      await tester.tap(find.text(l10n.p2pBookFilterAnyType));
      await settle();
      await tester.tap(find.text(l10n.p2pBookFilterBuy).last);
      await settle();
      await tester.tap(find.text(l10n.p2pBookFilterAnyCurrency));
      await settle();
      await tester.tap(find.text('EUR').last);
      await settle();
      await tester.tap(close);
      await settle();
      await capture('offres');

      // The payment method sheet with « Buy » and « EUR » chosen (#118): the methods of these orders first with their counts, the others dimmed under a heading.
      await tester.tap(find.text(l10n.p2pBookFilterAnyMethod));
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('filtres-feuille-modes');
      // Two of them ticked, then the sentence that names the first and counts the other, then the sheet opened again with them first.
      final methodSheet = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'FilterSheet<String>',
      );
      final methodRows = find.descendant(
        of: methodSheet,
        matching: find.byWidgetPredicate(
          (widget) => widget.key is ValueKey<String>,
        ),
      );
      final ticked = [
        for (final index in [1, 0])
          (tester.widget(methodRows.at(index)).key as ValueKey<String>?)
                  ?.value ??
              '',
      ];
      for (final index in [1, 0]) {
        await tester.tap(methodRows.at(index));
        await settle();
      }
      await tester.pump(const Duration(seconds: 1));
      await capture('filtres-feuille-plusieurs');
      await tester.tapAt(const Offset(4, 4));
      await settle();
      await capture('filtres-paiements');
      final chosenMethods = find.text(l10n.p2pBookFilterMore(ticked.first, 1));
      await tester.tap(chosenMethods);
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('filtres-feuille-rouverte');
      // The search, as the official client's list filters: « rev ».
      final search = find.descendant(
        of: methodSheet,
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'rev');
      await settle();
      await capture('filtres-feuille-recherche');
      await tester.enterText(search, '');
      await settle();
      // « Any payment method » at the top of the sheet clears the choice.
      await tester.tap(find.text(l10n.p2pBookFilterAnyMethod).last);
      await settle();
      await tester.tapAt(const Offset(4, 4));
      await settle();

      // Several hosts, then back to every host, so that the chart below shows every coordinator's euro orders as before.
      await tester.tap(find.text(l10n.p2pBookFilterAnyHost));
      await settle();
      await tester.tap(find.text(host('temple')).last);
      await settle();
      await tester.tap(find.text(host('bazaar')).last);
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('filtres-feuille-hotes');
      await tester.tap(close);
      await settle();
      await capture('filtres-hotes');
      await tester.tap(find.text('${host('temple')} +1'));
      await settle();
      await tester.tap(find.text(l10n.p2pBookFilterAnyHost).last);
      await settle();
      await tester.tap(close);
      await settle();

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

      // The same search while the book of temple is still awaited: the dialog waits for it.
      tor = await show(RobosatsNetwork.mainnet, held: {'temple'});
      tor.add(P2pTorState.ready);
      await settle();
      await tester.tap(find.text(l10n.p2pCommonSearch));
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField), '$temple/order/temple/1');
      await tester.tap(find.text(l10n.p2pCommonSearch).last);
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('recherche-attente');

      // The chart on a small phone, 320 by 568 points, with five coordinators offline above it (Gumpellite answers nothing recorded): the row scrolls with the chart.
      tester.view.physicalSize = const Size(640, 1136);
      tor = await show(
        RobosatsNetwork.mainnet,
        offline: {'lake', 'bazaar', 'freeport', 'ammanaya'},
      );
      tor.add(P2pTorState.ready);
      await settle();
      await settleAttempts();
      await tester.tap(find.text(l10n.p2pBookViewChart));
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('graphique-hors-ligne-petit');
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -600),
      );
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('graphique-hors-ligne-petit-bas');

      // The row on that small phone with the text twice as large: asked again, then offline with « Retry ».
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tor = await show(RobosatsNetwork.mainnet, offline: {'lake', 'bazaar'});
      tor.add(P2pTorState.ready);
      await settle();
      // The filter sentence takes most of the screen at that size: the book is scrolled to put the row at its top.
      final book = find.byType(CustomScrollView).first;
      tester
          .state<ScrollableState>(
            find.descendant(of: book, matching: find.byType(Scrollable)).first,
          )
          .position
          .jumpTo(
            tester.getRect(find.text(l10n.p2pBookFilterHostedBy)).bottom -
                tester.getRect(book).top +
                8,
          );
      await settle();
      await capture('offres-petit-texte2-redemande');
      await settleAttempts();
      await capture('offres-petit-texte2-hors-ligne');

      // The filter sentence on that small phone with the text twice as large: nothing chosen, then two currencies and two hosts, each selector wrapping inside its box rather than being cut.
      tester
          .state<ScrollableState>(
            find.descendant(of: book, matching: find.byType(Scrollable)).first,
          )
          .position
          .jumpTo(0);
      await settle();
      await capture('filtres-petit-texte2-rien');
      await tester.tap(find.text(l10n.p2pBookFilterAnyCurrency));
      await settle();
      await tester.tap(find.text('EUR').last);
      await settle();
      await tester.tap(find.text('USD').last);
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('filtres-petit-texte2-feuille');
      // A tap above the sheet closes it, its title and button having scrolled away with the rows.
      await tester.tapAt(const Offset(4, 4));
      await settle();
      await tester.ensureVisible(find.text(l10n.p2pBookFilterAnyHost));
      await settle();
      await tester.tap(find.text(l10n.p2pBookFilterAnyHost));
      await settle();
      await tester.tap(find.text(host('temple')).last);
      await settle();
      await tester.ensureVisible(find.text(host('lake')).last);
      await settle();
      await tester.tap(find.text(host('lake')).last);
      await settle();
      await tester.tapAt(const Offset(4, 4));
      await settle();
      // The end of the sentence, the two hosts, at the top of the book.
      final scroll = tester
          .state<ScrollableState>(
            find.descendant(of: book, matching: find.byType(Scrollable)).first,
          )
          .position;
      scroll.jumpTo(
        scroll.pixels +
            tester.getRect(find.text(l10n.p2pBookFilterHostedBy)).top -
            tester.getRect(book).top -
            8,
      );
      await settle();
      await capture('filtres-petit-texte2-plusieurs');

      // The payment method sheet on that phone, then its search with the keyboard up: the sheet stands on the keyboard and its rows scroll above it.
      final anyMethod = find.text(l10n.p2pBookFilterAnyMethod);
      await tester.ensureVisible(anyMethod);
      await settle();
      await tester.tap(anyMethod);
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('filtres-petit-texte2-modes');
      tester.view.viewInsets = const FakeViewPadding(bottom: 260 * 2);
      await tester.enterText(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == 'FilterSheet<String>',
          ),
          matching: find.byType(TextField),
        ),
        'pay',
      );
      await settle();
      await capture('filtres-petit-texte2-recherche-clavier');
      tester.view.resetViewInsets();
      await settle();
      await tester.tapAt(const Offset(4, 4));
      await settle();

      // The same phone with the text three times as large: the sheets of the hosts and of the payment methods, whose close button then goes above the title.
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      await settle();
      final hosts = find.text('${host('temple')} +1');
      await tester.ensureVisible(hosts);
      await settle();
      await tester.tap(hosts);
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('filtres-petit-texte3-hotes');
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -900),
      );
      await settle();
      await capture('filtres-petit-texte3-hotes-bas');
      await tester.tapAt(const Offset(4, 4));
      await settle();
      final methods = find.text(l10n.p2pBookFilterAnyMethod);
      await tester.ensureVisible(methods);
      await settle();
      await tester.tap(methods);
      await settle();
      await tester.pump(const Duration(seconds: 1));
      await capture('filtres-petit-texte3-paiements');
      await tester.tapAt(const Offset(4, 4));
      await settle();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  // The « Map » view, over books the test makes: of the recorded orders one only has a position, 0° and 0°, so these orders, their places and their robots are the test's own.
  // The map as it opens, an order under the finger, a group zoomed in on, the list of a group zooming cannot part, the same orders without their positions, the recorded books, and a small phone with the text three times as large.
  for (final locale in const [Locale('fr'), Locale('en')]) {
    testWidgets(
      'captures of the map in ${locale.languageCode}',
      skip: directory == null,
      (tester) async {
        final out = Directory(directory ?? '.')..createSync(recursive: true);
        tester.view
          ..physicalSize = const Size(780, 1688)
          ..devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final l10n = lookupP2pLocalizations(locale);

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

        /// The tab on mainnet over [transport], Tor ready, then the « Map » view.
        Future<void> showMap(CoordinatorTransport transport) async {
          final locator = GetIt.asNewInstance();
          final tor = StreamController<P2pTorState>.broadcast();
          addTearDown(tor.close);
          addTearDown(locator.reset);
          setUpP2pForTesting(
            locator,
            transport: transport,
            torStates: () => tor.stream,
            clock: () => _now,
            shuffle: _phrasesFromTheSecond,
          );
          await tester.pumpWidget(
            _App(
              locale: locale,
              locator: locator,
              network: RobosatsNetwork.mainnet,
            ),
          );
          await tester.pump();
          tor.add(P2pTorState.ready);
          await settle();
          await tester.tap(find.text(l10n.p2pBookViewMap));
          await settle();
        }

        final paint = find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is MapChartPainter,
        );

        /// Where on the screen the first mark that [matches] is drawn.
        Offset markAt(bool Function(MapMark mark) matches) {
          final painter = tester.widget<CustomPaint>(paint).painter;
          if (painter is! MapChartPainter) throw StateError('no map');
          for (final (mark, at) in painter.layout.drawn) {
            if (matches(mark)) return tester.getTopLeft(paint) + at;
          }
          throw StateError('no such mark');
        }

        bool holds(MapMark mark, String alias, int id) => switch (mark) {
          MapPin(:final order) =>
            order.coordinator.shortAlias == alias && order.id == id,
          MapGroup(:final pins) => pins.any(
            (pin) =>
                pin.order.coordinator.shortAlias == alias && pin.order.id == id,
          ),
        };

        await showMap(const _MapTransport());
        await capture('carte');

        // A long press on the pin of the seller in Nairobi shows its order.
        final finger = await tester.startGesture(
          markAt((mark) => mark is MapPin && holds(mark, 'bazaar', 1)) +
              const Offset(0, -19),
        );
        await tester.pump(const Duration(milliseconds: 700));
        await capture('carte-ordre');
        await finger.up();
        await settle();

        // A tap on the group over Europe zooms in where it parts.
        await tester.tapAt(
          markAt((mark) => mark is MapGroup && holds(mark, 'temple', 1)),
        );
        await settle();
        await capture('carte-zoom');

        // The three orders in Lisbon stay together however near: a tap lists them.
        for (var tap = 0; tap < 8; tap++) {
          if (find.text(l10n.p2pMapOrdersHere(3)).evaluate().isNotEmpty) break;
          await tester.tapAt(
            markAt((mark) => mark is MapGroup && holds(mark, 'temple', 6)),
          );
          await settle();
        }
        await capture('carte-liste');
        await tester.tap(find.byIcon(Icons.close).last);
        await settle();

        // The same orders without their positions: the map says so.
        await showMap(const _MapTransport(located: false));
        await capture('carte-sans-position');

        // The recorded books: one order of Temple of Sats says 0.000000 and 0.000000, and is drawn there, as the official client draws it.
        await showMap(
          const _RecordedTransport(
            RobosatsNetwork.mainnet,
            empty: {'gumpellite'},
          ),
        );
        await capture('carte-carnets-enregistres');

        // A phone of 320 by 568 points with the text three times as large, two coordinators offline: the row scrolls with the map, which keeps its height.
        tester.view.physicalSize = const Size(640, 1136);
        tester.platformDispatcher.textScaleFactorTestValue = 3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await showMap(const _MapTransport(offline: {'lake', 'bazaar'}));
        for (var i = 0; i < 22; i++) {
          await tester.pump(const Duration(seconds: 1));
          await settle();
        }
        await capture('carte-petit-texte3');
        // Scrolled to its end by the book itself: a drag on the map would move the map.
        final scroll = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(CustomScrollView).first,
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        scroll.jumpTo(scroll.maxScrollExtent);
        await settle();
        await capture('carte-petit-texte3-bas');
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      },
    );
  }

  // The Garage Keys (#81), the seven plates of the mock-up decided on 2026-11-26, over a vault in memory, on testnet, with the public test phrase « abandon ×11 about » as the default wallet's words (never a real wallet's), derived by the app's own adapter, in each language, dark and light.
  // First a new install: internal key 0 and its card, its explanation, « New Garage Key », the key shown after the PIN (the public vector of key 0), « Import an external Garage Key » and « Robot recovery », the public example key of the RoboSats frontend tests imported as the external Garage Key (never revealed), its card, its explanation, « Back to internal Garage Keys », « Switch to the external Garage Key », « Delete the external Garage Key? ».
  // Then an update: a book of schema 9 whose key, the same public example key, has a trade in progress and finished trades, opened by the app: « Your Garage Keys » once, the line of the trade on an internal key, the history with each order's key and robot, and the delete that names the trade; last, that trade's row damaged, the delete that says the trades could not be read.
  for (final (locale, theme) in const [
    (Locale('fr'), AppThemeType.dark),
    (Locale('en'), AppThemeType.dark),
    (Locale('fr'), AppThemeType.light),
    (Locale('en'), AppThemeType.light),
  ]) {
    testWidgets(
      'captures of the Garage in ${locale.languageCode}, ${theme.name}',
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
        final prefix = theme == AppThemeType.dark
            ? locale.languageCode
            : '${locale.languageCode}-clair';

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
              '${out.path}/$prefix-$name.png',
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

        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await settle();
          await tester.tap(finder);
          await settle();
        }

        // Each reading of the keys reads the vault slot of the external Garage Key, whose empty slot the vault settles with its full budget (#81).
        Future<void> letTheVaultSettle() async {
          await tester.pump(const Duration(seconds: 6));
          await settle();
        }

        Finder needed(Finder finder, String what) {
          if (finder.evaluate().isEmpty) throw StateError('not shown: $what');
          return finder;
        }

        FakeSecureStoragePlatform().install();
        final secrets = Secrets(scratchDirectory: () async => '.');
        final imported = await tester.runAsync(
          () => secrets.import(words: _abandonWords),
        );
        final fingerprint = switch (imported) {
          Ok(:final value) => value.id.hex,
          _ => throw StateError('the test words were not stored'),
        };
        final books = Directory.systemTemp.createTempSync(
          'p2p-garage-capture-',
        );
        addTearDown(() => books.deleteSync(recursive: true));
        final l10n = lookupP2pLocalizations(locale);

        /// The app over the book at [file], the Garage shown.
        Future<(GetIt, StreamController<P2pTorState>)> open(File file) async {
          final locator = GetIt.asNewInstance();
          final tor = StreamController<P2pTorState>.broadcast();
          setUpP2pForTesting(
            locator,
            transport: const _RecordedTransport(RobosatsNetwork.testnet),
            torStates: () => tor.stream,
            clock: () => _now,
            garageKeys: secrets.garageKeys(),
            derivedGarageKeys: DerivedGarageKeyAdapter(
              secrets,
              () => _DefaultWallet(fingerprint),
            ),
            databaseOpener: () => NativeDatabase(file),
          );
          await tester.pumpWidget(
            _App(
              locale: locale,
              locator: locator,
              network: RobosatsNetwork.testnet,
              theme: theme,
            ),
          );
          tor.add(P2pTorState.ready);
          await settle();
          await tester.tap(find.text(l10n.p2pNavGarage));
          await settle();
          tor.add(P2pTorState.ready);
          await settle();
          await letTheVaultSettle();
          return (locator, tor);
        }

        Future<void> close(
          GetIt locator,
          StreamController<P2pTorState> tor,
        ) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await settle();
          await tor.close();
          await tester.runAsync(locator.reset);
        }

        // A new install.
        final fresh = File('${books.path}/fresh.sqlite');
        var (locator, tor) = await open(fresh);
        // Plate 1: the Garage on internal key 0, then its card, the import link under it.
        await capture('garage-p1-cle-interne');
        await tester.ensureVisible(
          needed(find.text(l10n.p2pGarageKeyNumber(0)), 'internal key 0'),
        );
        await settle();
        await capture('garage-p1-carte-sans-externe');
        // Plate 7: the explanation of the internal Garage Keys.
        await tap(find.byTooltip(l10n.p2pGarageKeyExplain));
        await capture('garage-p7-info-interne');
        await tap(find.text(l10n.p2pCommonAcknowledged));
        // Plate 2: « New Garage Key », then internal key 1 and back to key 0.
        await tap(find.text(l10n.p2pGarageNewKey));
        await capture('garage-p2-nouvelle-cle');
        await tap(find.text(l10n.p2pGarageNewKeyConfirm(1)));
        tor.add(P2pTorState.ready);
        await settle();
        await letTheVaultSettle();
        await tester.ensureVisible(
          needed(find.text(l10n.p2pGarageKeyNumber(1)), 'internal key 1'),
        );
        await settle();
        await capture('garage-p2-plusieurs-cles');
        await tap(find.byTooltip(l10n.p2pGaragePreviousKey));
        tor.add(P2pTorState.ready);
        await settle();
        await letTheVaultSettle();
        await tap(find.byTooltip(l10n.p2pGarageKeyReveal));
        await capture('garage-p2-pin-factice');
        await tester.tap(find.text('PIN'));
        await settle();
        final shown = needed(
          find.text(_abandonTestnetKey0),
          'the public key 0 after the PIN',
        );
        await tester.ensureVisible(shown);
        await settle();
        await capture('garage-p2-cle-affichee');
        // Plate 4: « Import an external Garage Key », « Robot recovery », the key imported.
        await tester.ensureVisible(
          needed(find.text(l10n.p2pGarageImportExternal), 'the import link'),
        );
        await settle();
        await capture('garage-p4-lien-import');
        await tap(find.text(l10n.p2pGarageImportExternal));
        await capture('garage-p4-recuperation');
        // The field of the dialog, drawn over the Garage: the last one.
        await tester.enterText(
          find.byType(TextField).last,
          _exampleGarageKey(),
        );
        await settle();
        await tap(find.text(l10n.p2pRecoveryRecover));
        tor.add(P2pTorState.ready);
        await settle();
        await letTheVaultSettle();
        // Plate 3 and 4: the Garage on the external Garage Key, then its card.
        final external = needed(
          find.text(l10n.p2pGarageExternalKey),
          'the key imported as the external Garage Key',
        );
        await capture('garage-p3-cle-externe');
        await tester.ensureVisible(external);
        await settle();
        await capture('garage-p4-apres-import');
        // Plate 7: the explanation of the external Garage Key.
        await tap(find.byTooltip(l10n.p2pGarageKeyExplain));
        await capture('garage-p7-info-externe');
        await tap(find.text(l10n.p2pCommonAcknowledged));
        // Plate 4: « Delete the external Garage Key? », then « Cancel ».
        await tap(find.text(l10n.p2pGarageDeleteExternal));
        await capture('garage-p4-supprimer');
        await tap(find.text(l10n.p2pCommonCancel));
        // Plate 3: back to the last internal key shown, key 0, and its button to the external one.
        await tap(find.text(l10n.p2pGarageBackToInternal));
        tor.add(P2pTorState.ready);
        await settle();
        await letTheVaultSettle();
        await tester.ensureVisible(
          needed(find.text(l10n.p2pGarageSwitchToExternal), 'the switch'),
        );
        await settle();
        await capture('garage-p3-retour-interne');
        await close(locator, tor);

        // An update: the book of an earlier version, its key in the vault, a trade of it in progress and its finished ones.
        final updated = File('${books.path}/updated.sqlite');
        (locator, tor) = await open(updated);
        await close(locator, tor);
        // The fingerprints the app recorded: the key imported in the first book, internal key 0 in this one; never computed here.
        String fingerprintIn(File file, String query) {
          final database = sqlite3.open(file.path);
          try {
            return database.select(query).single.values.single as String;
          } finally {
            database.dispose();
          }
        }

        final externalHex = fingerprintIn(
          fresh,
          "SELECT key_fingerprint FROM garage_key_histories WHERE network = 'testnet' AND origin = 'imported'",
        );
        final internalHex = fingerprintIn(
          updated,
          "SELECT key_fingerprint FROM derived_garage_keys WHERE network = 'testnet' AND key_index = 0",
        );
        _toSchema9(updated, [
          for (final (hex, origin) in [
            (externalHex, 'imported'),
            (internalHex, 'generated'),
          ])
            "INSERT OR IGNORE INTO garage_key_histories (network, key_fingerprint, origin, recorded_at) VALUES ('testnet', '$hex', '$origin', 1)",
          for (final (hex, robot, order, role, closed) in [
            (externalHex, 3, 48120, 'seller', null),
            (externalHex, 2, 47655, 'buyer', 1764000000000),
            (internalHex, 2, 47990, 'seller', 1764100000000),
            (internalHex, 5, 48731, 'seller', 1764200000000),
          ]) ...[
            "INSERT INTO robot_bindings (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, coordinator_node_keys, coordinator_nostr_key, bound_at, provenance) VALUES ('testnet', '$hex', $robot, 'temple', 'http://temple.onion', '', 'nostr', 2, 'acknowledged')",
            "INSERT INTO trades (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at) VALUES ('testnet', '$hex', $robot, 'temple', 'http://temple.onion', $order, '$role', 'takenHere', ${(closed ?? 1764300000000) - 3600000}, ${(closed ?? 1764300000000) - 3500000}, ${closed ?? 'NULL'})",
          ],
        ]);
        (locator, tor) = await open(updated);
        // Plate 5: « Your Garage Keys », once, over the Garage on the external Garage Key.
        needed(find.text(l10n.p2pGarageNoticeTitle), '« Your Garage Keys »');
        await capture('garage-p5-vos-cles');
        await tap(find.text(l10n.p2pCommonAcknowledged));
        // Plate 4: its delete names its trade in progress.
        await tap(find.text(l10n.p2pGarageDeleteExternal));
        await capture('garage-p4-supprimer-pendant-echange');
        await tap(find.text(l10n.p2pCommonCancel));
        // Plate 6: on internal key 0, the line of the trade of the external Garage Key, then the history.
        await tap(find.text(l10n.p2pGarageBackToInternal));
        tor.add(P2pTorState.ready);
        await settle();
        await letTheVaultSettle();
        needed(
          find.text(l10n.p2pGarageTradeInProgress('48120')),
          'the trade of another key',
        );
        await capture('garage-p6-echange-ailleurs');
        await tap(find.text(l10n.p2pHistoryShow));
        // The history opened, from its toggle at the top of the screen.
        await tester.runAsync(
          () => Scrollable.ensureVisible(
            tester.element(find.text(l10n.p2pHistoryHide)),
            alignment: 0.05,
          ),
        );
        await settle();
        await capture('garage-p6-historique');
        await close(locator, tor);

        // The trades that cannot be read (review of #292, R-3): the row of the trade in progress damaged, one this app never writes; on the external Garage Key, « Delete the external Garage Key? » says a trade in progress may use it, « Delete » enabled.
        _unreadableTrade(updated, 48120);
        (locator, tor) = await open(updated);
        await tap(find.text(l10n.p2pGarageSwitchToExternal));
        tor.add(P2pTorState.ready);
        await settle();
        await letTheVaultSettle();
        await tap(find.text(l10n.p2pGarageDeleteExternal));
        needed(
          find.text(l10n.p2pGarageDeleteExternalUnread),
          'the line of the trades not read',
        );
        await capture('garage-r3-supprimer-echanges-illisibles');
        await tap(find.text(l10n.p2pCommonCancel));
        await close(locator, tor);
      },
    );
  }

  // The robot panel of the Garage, on mainnet so that « Select Host » lists every coordinator (Gumpellite, not recorded, shows as offline), over the public example key, pasted, so of unknown history: Tor on its way, a robot without a coordinator, « Select Host » and its « Robots from elsewhere », asked once for the key, the confirmation, the first contact and its long wait, the card of a robot in its states, every failure with a text, a coordinator closed by its refusals, and a robot read back.
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

        // The example key, stored in the slot of the network, which the test seam takes as key 0 of the words (#81): a key activated here, recorded as drawn here. « Robots from elsewhere », asked for a pasted key, is not reachable in this version (the paste of a key comes back with #79), so it has no capture here.
        await tester.runAsync(
          () => Secrets(scratchDirectory: () async => '.').garageKeys().import(
            slot: GarageKeySlot.mainnet,
            bytes: example.revealBytes(),
          ),
        );
        await tester.tap(find.text(l10n.p2pNavGarage));
        await settle();
        await tester.ensureVisible(find.text(l10n.p2pRobotSelectHost));
        await settle();
        await capture('robot-attente-tor');

        tor.add(P2pTorState.ready);
        await settle();
        await capture('robot-sans-coordinateur');

        // The book of the tab asks Gumpellite again, after 5 then 15 seconds, before it shows it offline: the sheet says so once it does.
        for (var i = 0; i < 22; i++) {
          await tester.pump(const Duration(seconds: 1));
          await settle();
        }

        // « Select Host »: the sheet, then the confirmation, and the first contact with Temple of Sats, which takes its time.
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

  // The bond paid from this wallet (#100), on mainnet, the same path as the trade screen's below with a wallet's port the test writes (`_CaptureWallet`): its balance, its quotes and its payments are the test's, made of demonstration figures; nothing reaches a swap service and no money moves.
  for (final locale in const [Locale('fr'), Locale('en')]) {
    testWidgets(
      'captures of the bond paid from this wallet in ${locale.languageCode}',
      skip: directory == null,
      timeout: const Timeout(Duration(minutes: 15)),
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

        Future<void> waitFor(Finder finder) async {
          for (var i = 0; i < 1200 && finder.evaluate().isEmpty; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump(const Duration(milliseconds: 200));
          }
          if (finder.evaluate().isEmpty) throw StateError('not shown: $finder');
          await settle();
        }

        final l10n = lookupP2pLocalizations(locale);
        final now = DateTime.utc(2026, 11, 14, 9);
        final transport = _TradeTransport(now);
        final wallet = _CaptureWallet(now);

        FakeSecureStoragePlatform().install();
        final locator = GetIt.asNewInstance();
        final tor = StreamController<P2pTorState>.broadcast();
        addTearDown(tor.close);
        addTearDown(locator.reset);
        addTearDown(wallet.close);
        setUpP2pForTesting(
          locator,
          transport: transport,
          torStates: () => tor.stream,
          clock: () => now,
          garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
          bolt11Decoder: transport,
          wallet: wallet,
        );
        await tester.pumpWidget(
          _App(
            locale: locale,
            locator: locator,
            network: RobosatsNetwork.mainnet,
          ),
        );
        await settle();

        // The Garage Key of the trades of this test (#81): key 0 of the public test phrase « abandon ×11 about » on mainnet, the design note's vector, stored in the slot of the network, which the test seam takes as key 0 of the words; it is never captured.
        final key = switch (GarageKey.parse(_abandonMainnetKey0)) {
          Ok(:final value) => value,
          Err() => throw StateError('not a key'),
        };
        await tester.runAsync(
          () => Secrets(scratchDirectory: () async => '.').garageKeys().import(
            slot: GarageKeySlot.mainnet,
            bytes: key.revealBytes(),
          ),
        );
        await tester.tap(find.text(l10n.p2pNavGarage));
        await settle();
        final identities = [
          for (var i = 0; i < 12; i++)
            if (key.deriveIdentity(i) case Ok(:final value)) value,
        ];
        final coordinator = ScriptedCoordinator(
          network: RobosatsNetwork.mainnet,
          robots: identities,
          clock: () => now,
        );
        transport.temple = coordinator;
        tor.add(P2pTorState.ready);
        await settle();

        Future<void> nextRead() async {
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(seconds: 1));
            await settle();
          }
        }

        // The take, then the panel at 3.
        await tester.tap(find.text(l10n.p2pNavOffers));
        await settle();
        final row = find.text('100 EUR', findRichText: true);
        await waitFor(row);
        await tester.tap(row);
        await settle();
        await tester.ensureVisible(find.text(l10n.p2pTakeOrder));
        await settle();
        // The take in two steps (#119): « Take Order » has the robot read the order, then « Continue » and « Done ».
        await tester.tap(find.text(l10n.p2pTakeOrder));
        await waitFor(find.text(l10n.p2pTakerBond));
        // The wallet of this test gives no Bitcoin price, so the read order shows « Price not verified » (#249), which puts « Continue » below the screen: scrolled into view as a user would, on the page that holds the read.
        await capture('lecture-prix-non-verifie');
        // Its explanation folded behind « Show details » (#270): opened, captured, folded again.
        await tester.ensureVisible(find.text(l10n.p2pDetailShow));
        await settle();
        await tester.tap(find.text(l10n.p2pDetailShow));
        await settle();
        await capture('lecture-prix-non-verifie-detail');
        await tester.tap(find.text(l10n.p2pDetailHide));
        await settle();
        await tester.scrollUntilVisible(
          find.text(l10n.p2pCommonContinue),
          200,
          scrollable: find
              .ancestor(
                of: find.text(l10n.p2pTakerBond),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await settle();
        await capture('lecture-continuer');
        await tester.tap(find.text(l10n.p2pCommonContinue));
        await settle();
        await tester.tap(find.text(l10n.p2pCommonDone));
        await waitFor(find.text(l10n.p2pPayWithThisWallet));
        await capture('paiement-pret');

        // A refusal first (the service's minimum), then the confirmation.
        wallet.refuseNext = true;
        await tester.tap(find.text(l10n.p2pPayWithThisWallet));
        await settle();
        await capture('paiement-refus');
        await tester.ensureVisible(find.text(l10n.p2pPayWithThisWallet));
        await settle();
        await tester.tap(find.text(l10n.p2pPayWithThisWallet));
        await settle();
        final parts = l10n.p2pPayConfirm('§').split('§');
        final pay = find.textContaining(
          RegExp(
            '^${RegExp.escape(parts.first)}.+${RegExp.escape(parts.last)}\$',
          ),
        );
        await waitFor(pay);
        await capture('paiement-confirmation');
        await tester.ensureVisible(pay.last);
        await settle();
        await capture('paiement-confirmation-bas');

        // The payment, held until it is captured as sending.
        await tester.tap(pay.last);
        await settle();
        await capture('paiement-envoi');
        wallet.finishPayment();
        await settle();
        await nextRead();
        await capture('paiement-envoye');

        // At 3, a swap service that could not pay the invoice (demonstration progress), then back to the payment in progress.
        wallet.progress(const P2pWalletPaymentRefundPending());
        await settle();
        await capture('paiement-service-n-a-pas-paye');
        wallet.progress(const P2pWalletPaymentRefunded());
        await settle();
        await capture('paiement-rembourse-3');
        wallet.progress(const P2pWalletPaymentPending());
        await settle();

        // The coordinator sees the bond locked: 6, the payment in progress for this wallet.
        final taker = identities.firstWhere(coordinator.holdsPreTake);
        coordinator.lockBond(taker);
        wallet.progress(const P2pWalletPaymentPending());
        await nextRead();
        await capture('paiement-caution-bloquee');
        // The same status from its top: « Submit payout info (2/4) », the reference's own bond line and nothing of ours (#135), then the payout panel (#91).
        await tester.ensureVisible(
          find.textContaining(l10n.p2pTradeTitlePayout),
        );
        await settle();
        await tester.drag(find.byType(ListView).last, const Offset(0, 2000));
        await settle();
        await capture('paiement-reception-2-4');

        // The bond lost by a cancel at 6: the coordinator keeps it, and the wallet reports the invoice settled (demonstration progress).
        await tester.ensureVisible(find.text(l10n.p2pCommonCancel).last);
        await settle();
        await tester.tap(find.text(l10n.p2pCommonCancel).last);
        await settle();
        await tester.tap(find.text(l10n.p2pTradeConfirmCancel));
        await settle();
        await nextRead();
        // The order cancelled, the wallet not yet told of the bond's fate: the payment is in progress.
        await capture('paiement-en-cours-apres');
        wallet.progress(const P2pWalletPaymentPaid());
        await settle();
        await capture('paiement-caution-conservee');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 3)),
        );
        await tester.pump(const Duration(seconds: 11));
      },
    );

    // Status 15 with the owner's payment rule (#283), as the app shows it, the wallet's port lent: a taker buyer whose payout failed and whose invoice expired, the new invoice compared with the Bull wallet's price (the gap « (indicative) »), then, the coordinator asking fewer sats than at 6, the red alert « Fewer sats than the first invoice » (#281). The wallet of the test gives the Bull wallet's price only: no wallet, no swap service, no money.
    testWidgets(
      'captures of status 15 with the payment rule in ${locale.languageCode}',
      skip: directory == null,
      timeout: const Timeout(Duration(minutes: 15)),
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

        Future<void> waitFor(Finder finder) async {
          for (var i = 0; i < 1200 && finder.evaluate().isEmpty; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump(const Duration(milliseconds: 200));
          }
          if (finder.evaluate().isEmpty) throw StateError('not shown: $finder');
          await settle();
        }

        final l10n = lookupP2pLocalizations(locale);
        final now = DateTime.utc(2026, 11, 14, 9);
        final transport = _TradeTransport(now);
        // The Bull wallet's price of the order's 106,900 sats for 100 EUR at a premium of 2 % (93,545 EUR/BTC with it): 91,711 EUR/BTC, a gap of −0.18 % (rounded away from zero) for the 106,713 sats paid.
        final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(50000)))
          ..rate = P2pWalletRateRead(91711);

        FakeSecureStoragePlatform().install();
        final locator = GetIt.asNewInstance();
        final tor = StreamController<P2pTorState>.broadcast();
        addTearDown(tor.close);
        addTearDown(locator.reset);
        setUpP2pForTesting(
          locator,
          transport: transport,
          torStates: () => tor.stream,
          clock: () => now,
          garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
          bolt11Decoder: transport,
          wallet: wallet,
        );
        await tester.pumpWidget(
          _App(
            locale: locale,
            locator: locator,
            network: RobosatsNetwork.mainnet,
          ),
        );
        await settle();

        // The Garage Key of the trades of this test (#81): key 0 of the public test phrase « abandon ×11 about » on mainnet, the design note's vector, stored in the slot of the network, which the test seam takes as key 0 of the words; it is never captured.
        final key = switch (GarageKey.parse(_abandonMainnetKey0)) {
          Ok(:final value) => value,
          Err() => throw StateError('not a key'),
        };
        await tester.runAsync(
          () => Secrets(scratchDirectory: () async => '.').garageKeys().import(
            slot: GarageKeySlot.mainnet,
            bytes: key.revealBytes(),
          ),
        );
        await tester.tap(find.text(l10n.p2pNavGarage));
        await settle();
        final identities = [
          for (var i = 0; i < 12; i++)
            if (key.deriveIdentity(i) case Ok(:final value)) value,
        ];
        final coordinator = ScriptedCoordinator(
          network: RobosatsNetwork.mainnet,
          robots: identities,
          clock: () => now,
        );
        transport.temple = coordinator;
        tor.add(P2pTorState.ready);
        await settle();

        Future<void> nextRead() async {
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(seconds: 1));
            await settle();
          }
        }

        // The take: « Take Order », the order read by the robot, « Continue » brought into view, « Done ».
        await tester.tap(find.text(l10n.p2pNavOffers));
        await settle();
        final row = find.text('100 EUR', findRichText: true);
        await waitFor(row);
        await tester.tap(row);
        await settle();
        await tester.ensureVisible(find.text(l10n.p2pTakeOrder));
        await settle();
        await tester.tap(find.text(l10n.p2pTakeOrder));
        await waitFor(find.text(l10n.p2pTakerBond));
        await tester.scrollUntilVisible(
          find.text(l10n.p2pCommonContinue),
          200,
          scrollable: find
              .ancestor(
                of: find.text(l10n.p2pTakerBond),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await settle();
        await tester.tap(find.text(l10n.p2pCommonContinue));
        await settle();
        await tester.tap(find.text(l10n.p2pCommonDone));
        await waitFor(find.text(l10n.p2pTradeTabContract));

        // The bond locked by the coordinator (6): the payout's breakdown with the gap, the largest sum asked kept for 15; then the escrow locked (8), the chat (9), « fiat sent » (10) and the payout tried (13).
        final taker = identities.firstWhere(coordinator.holdsPreTake);
        coordinator.lockBond(taker);
        await nextRead();
        await waitFor(find.text(l10n.p2pPayoutBreakdownGap));
        coordinator.lockEscrow();
        await nextRead();
        for (final status in const [9, 10, 13]) {
          coordinator.moveTo(status);
          await nextRead();
        }

        // 15, the invoice expired: the same sum asked as at 6, compared with the Bull wallet's price.
        coordinator
          ..payoutExpired = true
          ..moveTo(15);
        await nextRead();
        final breakdown = find.text(l10n.p2pPayoutBreakdownTitle);
        await waitFor(breakdown);
        await waitFor(find.text(l10n.p2pPayoutBreakdownGap));
        await tester.ensureVisible(breakdown);
        await settle();
        await capture('reception-15-regle');

        // A new invoice tried (13), failed again (15) with 105,000 sats fixed (−1.78 %, within the state machine's 2 %): 104,816 paid, fewer than the 106,713 of 6.
        coordinator.moveTo(13);
        await nextRead();
        coordinator
          ..lastSatoshis = 105000
          ..moveTo(15);
        await nextRead();
        await waitFor(find.text(l10n.p2pPayoutFirstFewer));
        await tester.ensureVisible(breakdown);
        await settle();
        await capture('reception-15-moins-de-sats');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 3)),
        );
        await tester.pump(const Duration(seconds: 11));
      },
    );
  }

  // The take and the trade screen (#88), on mainnet, the whole path of the app: a Garage Key drawn in the Garage (so recorded as drawn here, which a take needs), the book, the order details with « Take Order », « Store your garage key », the take for a fresh robot of the key, then each panel as the coordinator moves the order on.
  // Temple of Sats is the `ScriptedCoordinator` of the test seam, which plays the reference backend with invoices made by the tests; the other coordinators answer an empty book, but Lake, whose book holds one range order of the test for the amount field. Nothing leaves the test, no money moves, and the key, drawn in memory, is never captured.
  for (final locale in const [Locale('fr'), Locale('en')]) {
    testWidgets(
      'captures of the trade screen in ${locale.languageCode}',
      skip: directory == null,
      timeout: const Timeout(Duration(minutes: 15)),
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

        // A robot's key pair is made in an isolate, and the database answers on the event loop: real time passes for them.
        Future<void> waitFor(Finder finder) async {
          for (var i = 0; i < 1200 && finder.evaluate().isEmpty; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump(const Duration(milliseconds: 200));
          }
          if (finder.evaluate().isEmpty) {
            throw StateError(
              'not shown: $finder; shown: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).join(' | ')}',
            );
          }
          await settle();
        }

        final l10n = lookupP2pLocalizations(locale);
        final now = DateTime.utc(2026, 11, 14, 9);
        final transport = _TradeTransport(now);

        FakeSecureStoragePlatform().install();
        final locator = GetIt.asNewInstance();
        final tor = StreamController<P2pTorState>.broadcast();
        addTearDown(tor.close);
        addTearDown(locator.reset);
        setUpP2pForTesting(
          locator,
          transport: transport,
          torStates: () => tor.stream,
          clock: () => now,
          garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
          bolt11Decoder: transport,
          // The robots' keys dated by the screen's clock, so that the chat's messages sign and verify at it (#93).
          robotKeys: _DatedRobotKeys(() => now),
        );
        await tester.pumpWidget(
          _App(
            locale: locale,
            locator: locator,
            network: RobosatsNetwork.mainnet,
          ),
        );
        // Tor is told ready only once the scripted coordinator is in place, so that the book is read from it.
        await settle();

        // A Garage Key drawn here: the robots of a take come from it. Its text, shown for backup right after the draw, gives the test the robots the scripted coordinator knows; it is never captured.
        // The Garage Key of the trades of this test (#81): key 0 of the public test phrase « abandon ×11 about » on mainnet, the design note's vector, stored in the slot of the network, which the test seam takes as key 0 of the words; it is never captured.
        final key = switch (GarageKey.parse(_abandonMainnetKey0)) {
          Ok(:final value) => value,
          Err() => throw StateError('not a key'),
        };
        await tester.runAsync(
          () => Secrets(scratchDirectory: () async => '.').garageKeys().import(
            slot: GarageKeySlot.mainnet,
            bytes: key.revealBytes(),
          ),
        );
        await tester.tap(find.text(l10n.p2pNavGarage));
        await settle();
        final identities = [
          for (var i = 0; i < 24; i++)
            if (key.deriveIdentity(i) case Ok(:final value)) value,
        ];
        // The maker: a robot of the RoboSats example key, with the key the official client would make for it, so that its chat messages are its own (#93).
        final maker = switch (GarageKey.parse(_exampleGarageKey())) {
          Ok(:final value) => switch (value.deriveIdentity(0)) {
            Ok(:final value) => value,
            Err() => throw StateError('no maker'),
          },
          Err() => throw StateError('not a key'),
        };
        final makerKey = switch (RobotPgpKey.generateWith(
          maker,
          now: now,
          random: Random(93),
        )) {
          Ok(:final value) => switch (value.unlock(maker)) {
            Ok(:final value) => value,
            Err() => throw StateError('not unlocked'),
          },
          Err() => throw StateError('no maker key'),
        };
        final coordinator = ScriptedCoordinator(
          network: RobosatsNetwork.mainnet,
          robots: identities,
          clock: () => now,
          maker: maker,
        );
        transport.temple = coordinator;
        tor.add(P2pTorState.ready);
        await settle();

        // The book: the order of Temple of Sats, then its details with « Take Order ».
        Future<void> openTempleOrder() async {
          await tester.tap(find.text(l10n.p2pNavOffers));
          await settle();
          final row = find.text('100 EUR', findRichText: true);
          await waitFor(row);
          await tester.tap(row);
          await settle();
        }

        /// The robot that holds the pre-take now.
        RobotIdentity taker() =>
            identities.firstWhere(coordinator.holdsPreTake);

        /// The list of the page shown, which builds what is below the screen once scrolled to.
        Finder pageList() => find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .first;

        /// Scrolls the page shown until [finder] is built and in view.
        Future<void> reveal(Finder finder) async {
          await tester.scrollUntilVisible(finder, 200, scrollable: pageList());
          await settle();
        }

        /// « Take Order »: the robot reads the order (#119), whose read the order details then show, brought into view.
        Future<void> prepare() async {
          await openTempleOrder();
          await tester.ensureVisible(find.text(l10n.p2pTakeOrder));
          await settle();
          await tester.tap(find.text(l10n.p2pTakeOrder));
          await waitFor(find.text(l10n.p2pTakerBond));
        }

        /// « Continue », then « Done » of « Store your garage key »: the take sent.
        Future<void> send() async {
          await reveal(find.text(l10n.p2pCommonContinue));
          await tester.tap(find.text(l10n.p2pCommonContinue));
          await settle();
          await tester.tap(find.text(l10n.p2pCommonDone));
        }

        /// [send], then its trade.
        Future<void> confirm() async {
          await send();
          await waitFor(find.text(l10n.p2pTradeTabContract));
        }

        Future<void> take() async {
          await prepare();
          await confirm();
        }

        /// Lets the trade's watch read again, at the reference's cadence.
        Future<void> nextRead() async {
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(seconds: 1));
            await settle();
          }
        }

        /// Back from the page shown, as its top bar's arrow does.
        Future<void> backToTab() async {
          GoRouter.of(tester.element(find.text(l10n.p2pNavOrder).first)).pop();
          await settle();
        }

        // The range order of Lake: the amount field, then the estimate.
        await tester.tap(find.text(l10n.p2pNavOffers));
        await settle();
        final rangeRow = find.text('50-200 EUR', findRichText: true);
        await waitFor(rangeRow);
        await tester.tap(rangeRow);
        await settle();
        await tester.ensureVisible(find.text(l10n.p2pTakeOrder));
        await settle();
        await capture('echange-montant');
        await tester.enterText(find.byType(TextField), '10');
        await settle();
        await capture('echange-montant-trop-bas');
        await tester.enterText(find.byType(TextField), '120');
        await settle();
        await tester.ensureVisible(find.text(l10n.p2pTakeOrder));
        await settle();
        await capture('echange-montant-estimation');
        await backToTab();

        // Take 1: the order details, the wait of each step, the order read by the robot with the maker's description (#119), « Store your garage key », the order changed at « Done » and read again, then 3, 6, 7 and the end at 5.
        coordinator.description = locale.languageCode == 'fr'
            ? 'Revolut uniquement, sans note dans le virement.'
            : 'Revolut only, no notes in the transfer.';
        await openTempleOrder();
        await capture('echange-ordre');
        await tester.ensureVisible(find.text(l10n.p2pTakeOrder));
        await settle();
        await capture('echange-ordre-bas');
        // Each request waits for its gate: the wait is captured at its first two steps.
        var gate = Completer<void>();
        coordinator.hold = gate.future;
        Future<void> letGo() async {
          final passing = gate;
          gate = Completer<void>();
          coordinator.hold = gate.future;
          passing.complete();
          await settle();
        }

        await tester.tap(find.text(l10n.p2pTakeOrder));
        await settle();
        await tester.ensureVisible(find.text(l10n.p2pTakeOrder));
        await settle();
        await capture('prise-attente-verification');
        await letGo();
        await capture('prise-attente-robot');
        coordinator.hold = null;
        gate.complete();
        await waitFor(find.text(l10n.p2pTakerBond));
        await capture('prise-lecture-description');
        await reveal(find.text(l10n.p2pCommonContinue));
        await capture('prise-lecture-bas');
        await tester.tap(find.text(l10n.p2pCommonContinue));
        await settle();
        await capture('echange-sauvegarder-cle');
        // The maker changes the description before « Done »: the order is read again, the read seen kept meanwhile, then the new read with its changed rows marked, never taken by itself.
        coordinator.description = locale.languageCode == 'fr'
            ? 'Revolut uniquement. Paiement sous 30 minutes.'
            : 'Revolut only. Pay within 30 minutes.';
        final changed = coordinator.description ?? '';
        // The read again at « Done » goes through; the new preparation's first request waits for its gate.
        gate = Completer<void>();
        var reads = 0;
        coordinator.onRequest = (request) {
          if (request.url.path == '/api/book/' && ++reads == 1) {
            coordinator.hold = gate.future;
          }
        };
        await tester.tap(find.text(l10n.p2pCommonDone));
        await waitFor(find.text(l10n.p2pTakeOrderChangedRead));
        await reveal(find.text(l10n.p2pTakeOrderChangedRead));
        await capture('prise-relecture');
        coordinator
          ..onRequest = null
          ..hold = null;
        gate.complete();
        await waitFor(find.text(changed));
        await capture('prise-chiffres-changes');
        await reveal(find.text(l10n.p2pTakeOrderChangedRead));
        await capture('prise-chiffres-changes-bas');
        // « Continue », « Store your garage key » in the reference's order, then « Done »: the wait after « Done » says its steps, then the trade screen says what it waits for before its first read; each request waits for its gate.
        await reveal(find.text(l10n.p2pCommonContinue));
        await tester.tap(find.text(l10n.p2pCommonContinue));
        await settle();
        await capture('prise-sauvegarder-cle');
        gate = Completer<void>();
        coordinator.hold = gate.future;
        await tester.tap(find.text(l10n.p2pCommonDone));
        final again = find.text(l10n.p2pTakeStepReadingOrderAgain);
        await waitFor(again);
        await reveal(again);
        await capture('prise-attente-apres-fait');
        // The trade screen opens on the status the take has just read and kept (#152, #154: `TradeCubit` keeps what this run read), not on the wait of a first read, which shows only for a trade opened with no status kept (#205).
        coordinator.hold = null;
        gate.complete();
        await waitFor(find.text(l10n.p2pTradeTabContract));
        await capture('echange-3');
        await tester.ensureVisible(find.text(l10n.p2pTradeCopyToClipboard));
        await settle();
        await capture('echange-3-bas');
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await settle();
        await capture('echange-3-texte2');
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await settle();
        await tester.ensureVisible(find.text(l10n.p2pCommonCancel).last);
        await settle();
        await capture('echange-3-annuler');
        await tester.tap(find.text(l10n.p2pCommonCancel).last);
        await settle();
        await capture('echange-3-dialogue-annuler');
        await tester.tap(find.text(l10n.p2pTradeCancelBack));
        await settle();
        await tester.tap(find.text(l10n.p2pNavOrder).last);
        await settle();
        await capture('echange-3-onglet-ordre');
        await tester.tap(find.text(l10n.p2pTradeTabContract));
        await settle();

        // The coordinator offers the on-chain payout too, for the payout panel's captures (#91).
        coordinator.swapAllowed = true;
        coordinator.lockBond(taker());
        await nextRead();
        await waitFor(find.textContaining(l10n.p2pTradeTitlePayout));
        await capture('echange-6');
        await tester.ensureVisible(find.text(l10n.p2pCommonCancel).last);
        await settle();
        await capture('echange-6-bas');
        await tester.tap(find.text(l10n.p2pCommonCancel).last);
        await settle();
        await capture('echange-6-dialogue-annuler');
        await tester.tap(find.text(l10n.p2pCommonGoBack));
        await settle();

        // The payout panel (#91), through the app's own payout use case and keyring, the scripted coordinator checking the signature: Lightning, an invoice of the test pasted, the routing budget, Onchain, an address refused by the coordinator (its mining fee under the coordinator's minimum), then the invoice given, and the trade at 7.
        final buyerSats =
            ScriptedCoordinator.bookSats -
            (ScriptedCoordinator.bookSats * 0.00175).round();
        final payoutInvoice = Bolt11TestInvoice(
          network: Bolt11Network.mainnet,
          sats: (buyerSats - buyerSats * 1000 / 1000000).floor(),
          seed: 500,
          createdAt: now,
          expiry: const Duration(days: 2),
        );
        coordinator.decoder.add(payoutInvoice);
        await tester.ensureVisible(find.text(l10n.p2pPayoutTabLightning));
        await settle();
        await capture('reception-6');
        await tester.enterText(
          find.byType(TextField).first,
          payoutInvoice.text,
        );
        await settle();
        await tester.ensureVisible(find.text(l10n.p2pTradeInvoiceNetwork));
        await settle();
        await capture('reception-facture');
        final advanced = find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == 'BullSwitch',
        );
        await tester.ensureVisible(advanced);
        await settle();
        await tester.tap(advanced);
        await settle();
        await capture('reception-budget');
        await tester.tap(advanced);
        await settle();
        await tester.ensureVisible(find.text(l10n.p2pPayoutTabOnchain));
        await settle();
        await tester.tap(find.text(l10n.p2pPayoutTabOnchain));
        await settle();
        await capture('reception-onchain');
        coordinator.minimumMiningFeeRate = 10;
        await tester.enterText(
          find.byType(TextField).first,
          'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4',
        );
        await settle();
        await tester.ensureVisible(find.text(l10n.p2pPayoutSubmit));
        await settle();
        await tester.tap(find.text(l10n.p2pPayoutSubmit));
        await tester.pump();
        await tester.pump();
        await capture('reception-attente');
        await waitFor(find.text(l10n.p2pPayoutRefusedFeeTooLow('10')));
        await capture('reception-refus');
        await tester.ensureVisible(find.text(l10n.p2pPayoutTabLightning));
        await settle();
        await tester.tap(find.text(l10n.p2pPayoutTabLightning));
        await settle();
        await tester.ensureVisible(find.text(l10n.p2pPayoutSubmit));
        await settle();
        await tester.tap(find.text(l10n.p2pPayoutSubmit));
        await waitFor(find.textContaining(l10n.p2pTradeTitleInfoGood));
        await capture('reception-donnee');

        // The entry « Order » of the tab while the trade runs, which opens it again.
        await backToTab();
        await tester.tap(find.text(l10n.p2pNavOffers));
        await settle();
        await capture('echange-entree-ordre');
        // « Order » opens « Active trades », « Create order » at its top (#182), then the trade.
        await tester.tap(find.text(l10n.p2pNavOrder));
        await settle();
        await capture('echange-liste-ordres');
        await tester.tap(
          find.text(l10n.p2pActiveOrder('${coordinator.orderId}')),
        );
        await waitFor(find.text(l10n.p2pTradeTabContract));

        coordinator.moveTo(7);
        await nextRead();
        await waitFor(find.textContaining(l10n.p2pTradeTitleInfoGood));
        await capture('echange-7');
        coordinator.expire();
        await nextRead();
        await waitFor(find.text(l10n.p2pTradeExpiredInvoice));
        await capture('echange-expire');
        await backToTab();

        // Take 2: an order without a description, then cancelled at 3, the order public again.
        coordinator
          ..backToPublic()
          ..description = null;
        await prepare();
        await capture('prise-lecture-sans-description');
        await confirm();
        await tester.ensureVisible(find.text(l10n.p2pCommonCancel).last);
        await settle();
        await tester.tap(find.text(l10n.p2pCommonCancel).last);
        await settle();
        await tester.tap(find.text(l10n.p2pTradeConfirmCancellation));
        await waitFor(find.text(l10n.p2pOrderHost));
        await capture('echange-public');
        await backToTab();

        // An order the maker cancels between the read and « Done »: not available, nothing taken, « Take Order » disabled.
        coordinator.backToPublic();
        await prepare();
        coordinator.cancelByMaker();
        await send();
        await waitFor(find.text(l10n.p2pOrderNotAvailable));
        await tester.ensureVisible(find.text(l10n.p2pOrderNotAvailable));
        await settle();
        await capture('prise-ordre-disparu');
        await backToTab();

        // Take 3: the bond locked, then the maker cancels.
        coordinator.backToPublic();
        await take();
        coordinator.lockBond(taker());
        await nextRead();
        coordinator.cancelByMaker();
        await nextRead();
        await waitFor(find.text(l10n.p2pOrderCancelled));
        await capture('echange-annule');
        await backToTab();

        // Take 4: a failed payout (15), while the coordinator retries (#91).
        coordinator
          ..backToPublic()
          ..swapAllowed = false;
        await take();
        coordinator
          ..lockBond(taker())
          ..moveTo(15);
        await nextRead();
        await waitFor(find.text(l10n.p2pPayoutNextAttempt));
        await capture('reception-15-essai');
        // Once the invoice expired, a new one asked: captured with the owner's payment rule in « captures of status 15 with the payment rule » (#283), as the app shows it with the wallet's port lent; this test lends none, a composition the app does not use.
        coordinator.payoutExpired = true;
        await nextRead();
        await waitFor(find.text(l10n.p2pPayoutInvoiceExpiredSubmitNew));
        // The trade ends (14), so that the order's next take is a new trade.
        coordinator.moveTo(14);
        await nextRead();
        await waitFor(find.textContaining(l10n.p2pTradeTitleFinished));
        await backToTab();

        // Take 5: the chat at 9 (#93), in the chat step's place: its first read, the maker's messages encrypted to this robot's key as the official client does, a message sent, its wait, one not confirmed, a refusal, at 320 points, the breach, a history too long, and « Don't trust, verify » with test values.
        coordinator.backToPublic();
        await take();
        final chatter = taker();
        final ownKey = switch (PgpPublicKey.parse(
          coordinator.publicKeyOf(chatter) ?? '',
        )) {
          Ok(:final value) => value,
          Err() => throw StateError('no key'),
        };
        OutgoingChatMessage written(String text, UnlockedRobotPgpKey from) =>
            switch (from.encryptChatMessageToPost(
              text,
              peer: ownKey,
              now: now,
            )) {
              Ok(:final value) => value,
              Err() => throw StateError('not encrypted'),
            };
        final fr = locale.languageCode == 'fr';
        for (final text
            in fr
                ? [
                    'Bonjour ! Je vous envoie les euros par Revolut dans quelques minutes.',
                    'C’est envoyé, la référence est 4821.',
                  ]
                : [
                    'Hi! I am sending the euros with Revolut in a few minutes.',
                    'Sent, the reference is 4821.',
                  ]) {
          coordinator.peerSays(written(text, makerKey));
        }
        // The first read of the chat held, with what follows it, until the test lets them go: its wait is captured.
        final chatRead = Completer<void>();
        coordinator
          ..onRequest = (request) {
            if (request.url.path == '/api/chat/' &&
                request.body == null &&
                !chatRead.isCompleted) {
              coordinator.hold = chatRead.future;
            }
          }
          ..lockBond(chatter)
          ..moveTo(9)
          ..peerPublicKey = makerKey.key.publicKey.armored;
        await nextRead();
        final reading = l10n.p2pChatReading(coordinator.coordinator.longAlias);
        await waitFor(find.text(reading));
        await reveal(find.text(reading));
        await capture('chat-lecture');
        coordinator
          ..onRequest = null
          ..hold = null;
        chatRead.complete();
        await nextRead();
        final own = fr
            ? 'Merci, je vérifie mon compte.'
            : 'Thanks, I am checking my account.';
        Future<void> type(String text) async {
          await tester.enterText(find.byType(TextField).last, text);
          await settle();
        }

        Future<void> pressSend() async {
          final send = find.byIcon(Icons.send);
          await tester.ensureVisible(send);
          await settle();
          await tester.tap(send);
        }

        await type(own);
        await pressSend();
        await waitFor(find.text(own));
        await reveal(find.text(l10n.p2pChatTypeMessage));
        await capture('chat');
        // The same at 320 points.
        tester.view.physicalSize = const Size(640, 1688);
        await settle();
        await reveal(find.text(l10n.p2pChatTypeMessage));
        await capture('chat-320');
        tester.view.physicalSize = const Size(780, 1688);
        await settle();
        // A send held, with what follows it, until the test lets it go: its wait.
        final post = Completer<void>();
        coordinator.onRequest = (request) {
          if (request.url.path == '/api/chat/' && request.body != null) {
            coordinator.hold = post.future;
          }
        };
        await type(fr ? 'Reçu, merci !' : 'Received, thank you!');
        await pressSend();
        final sending = l10n.p2pChatSending(coordinator.coordinator.longAlias);
        await waitFor(find.text(sending));
        await capture('chat-envoi');
        coordinator
          ..onRequest = null
          ..hold = null;
        post.complete();
        await nextRead();
        // A message whose answer is lost and that the next read does not show: not confirmed, sent again only on the user's tap.
        Map<String, Object?>? hidden;
        coordinator
          ..failNext(ScriptedRequest.chatPost, ScriptedFault.answerLost)
          ..onRequest = (request) {
            if (request.url.path == '/api/chat/' &&
                request.body == null &&
                hidden == null &&
                coordinator.chat.isNotEmpty) {
              hidden = coordinator.chat.removeLast();
            }
          };
        await type(fr ? 'Avez-vous reçu ?' : 'Did you get it?');
        await pressSend();
        await waitFor(find.text(l10n.p2pChatSendAgain));
        coordinator.onRequest = null;
        await reveal(find.text(l10n.p2pChatSendAgain));
        await capture('chat-non-confirme');
        await tester.tap(find.text(l10n.p2pChatSendAgain));
        await nextRead();
        // A text over the limit: said as it is typed.
        await type('x' * 3300);
        await reveal(find.text(l10n.p2pChatTooLong));
        await capture('chat-refus');
        await type('');
        // A key forged in the maker's name: the breach.
        final forged = switch (RobotPgpKey.generateWith(
          maker,
          now: now,
          random: Random(94),
        )) {
          Ok(:final value) => value.publicKey.armored,
          Err() => throw StateError('no key'),
        };
        coordinator.peerPublicKey = forged;
        await nextRead();
        await waitFor(find.text(l10n.p2pChatKeyChanged));
        await reveal(find.text(l10n.p2pChatKeyChanged));
        await capture('chat-rupture');
        // A history too long to read from where the chat is (the coordinator's 4 MiB a page may take).
        coordinator.chat.add({
          'index': coordinator.chat.length + 1,
          'time': now.toIso8601String(),
          'message': 'x' * (4 * 1024 * 1024 + 1),
          'nick': maker.nickname,
        });
        await nextRead();
        await waitFor(find.text(l10n.p2pChatHistoryTooLarge));
        await reveal(find.text(l10n.p2pChatHistoryTooLarge));
        await capture('chat-trop-long');
        // « Don't trust, verify »: test values, never a robot's token or key.
        unawaited(
          ChatAuditDialog.show(
            tester.element(find.text(l10n.p2pChatTypeMessage)),
            coordinator: coordinator.coordinator.longAlias,
            exported: () async => {
              'credentials': {
                'own_public_key': ownKey.armored,
                'peer_public_key': makerKey.key.publicKey.armored,
                'encrypted_private_key':
                    '-----BEGIN PGP PRIVATE KEY BLOCK-----\n\n(test value)\n-----END PGP PRIVATE KEY BLOCK-----',
                'passphrase': 'test-value-not-a-token',
              },
              'messages': const <Object?>[],
            },
          ),
        );
        await settle();
        await capture('chat-audit');
        final back = find.descendant(
          of: find.byType(ChatAuditDialog),
          matching: find.text(l10n.p2pCommonGoBack),
        );
        await tester.ensureVisible(back);
        await settle();
        await tester.tap(back);
        await settle();
        // The next takes are new trades: their chats start empty, the maker's key given again.
        coordinator
          ..chat.clear()
          ..peerPublicKey = makerKey.key.publicKey.armored
          ..moveTo(14);
        await nextRead();
        await waitFor(find.textContaining(l10n.p2pTradeTitleFinished));
        await backToTab();

        // Take 6: the buyer's straight path (#95): the chat step with « Confirm … sent » and the reference's dialog, the wait for the seller, then the buyer being paid and the trade finished.
        coordinator.backToPublic();
        await take();
        coordinator
          ..lockBond(taker())
          ..moveTo(9);
        await nextRead();
        final fiatSent = l10n.p2pEndConfirmSent('100', 'EUR');
        await waitFor(find.text(fiatSent));
        await capture('fin-9');
        await tester.ensureVisible(find.text(fiatSent));
        await settle();
        await tester.tap(find.text(fiatSent));
        await settle();
        await capture('fin-9-dialogue');
        // The read before sending held by the coordinator, so that the wait it says is captured.
        final held = Completer<void>();
        coordinator.hold = held.future;
        await tester.tap(find.text(l10n.p2pEndConfirm));
        await waitFor(
          find.text(
            l10n.p2pPayoutStepReading(coordinator.coordinator.longAlias),
          ),
        );
        await settle();
        await capture('fin-9-envoi');
        // 30 s on: the long wait's line.
        await tester.pump(const Duration(seconds: 31));
        await capture('fin-9-attente-longue');
        coordinator.hold = null;
        held.complete();
        await waitFor(find.text(l10n.p2pEndWaitSeller));
        await capture('fin-10');
        coordinator.moveTo(13);
        await nextRead();
        await waitFor(find.textContaining(l10n.p2pTradeTitleSendingSats));
        await capture('fin-13');
        coordinator.moveTo(14);
        await nextRead();
        await waitFor(find.textContaining(l10n.p2pTradeTitleFinished));
        await capture('fin-14');
        await backToTab();

        // Take 7: the notices of « Confirm … sent » (#95): a request that lands late (the answer lost, the order still read at 9), then a confirmation whose order expired before it was sent.
        coordinator.backToPublic();
        await take();
        coordinator
          ..lockBond(taker())
          ..moveTo(9);
        await nextRead();
        await waitFor(find.text(fiatSent));
        coordinator.failNext(ScriptedRequest.confirm, ScriptedFault.landsLate);
        await tester.ensureVisible(find.text(fiatSent));
        await settle();
        await tester.tap(find.text(fiatSent));
        await settle();
        await tester.tap(find.text(l10n.p2pEndConfirm));
        await waitFor(find.text(l10n.p2pEndUnknown));
        await settle();
        await capture('fin-avis-inconnu');
        coordinator.landLate();
        await nextRead();
        await waitFor(find.text(l10n.p2pEndWaitSeller));
        // Back to 9 by « Payment failed? » is the next pull request's: the trade ends here.
        coordinator.moveTo(14);
        await nextRead();
        await waitFor(find.textContaining(l10n.p2pTradeTitleFinished));
        await backToTab();

        coordinator.backToPublic();
        await take();
        coordinator
          ..lockBond(taker())
          ..moveTo(9);
        await nextRead();
        await waitFor(find.text(fiatSent));
        // The order expires while the dialog is open: the read before sending finds it expired.
        await tester.ensureVisible(find.text(fiatSent));
        await settle();
        await tester.tap(find.text(fiatSent));
        await settle();
        coordinator.expire();
        await tester.tap(find.text(l10n.p2pEndConfirm));
        await waitFor(find.text(l10n.p2pEndMovedOn));
        await settle();
        await capture('fin-avis-non-envoye');
        await backToTab();

        // Take 7: « Payment failed? » (#95): at 10, its button and the reference's dialog with its wait; back at 9, « Order options », the collaborative cancel asked by this robot, then accepted by the peer.
        coordinator.backToPublic();
        await take();
        coordinator
          ..lockBond(taker())
          ..moveTo(9);
        await nextRead();
        await waitFor(find.text(fiatSent));
        coordinator.moveTo(10);
        await nextRead();
        await waitFor(find.text(l10n.p2pEndPaymentFailed));
        await capture('fin-10-paiement-echoue');
        // « Order options » at 10: « Collaborative Cancel » off, and the reference's reason.
        await tester.tap(find.byIcon(Icons.more_horiz));
        await settle();
        await capture('fin-options-10');
        Navigator.of(tester.element(find.text(l10n.p2pEndOrderOptions))).pop();
        await settle();
        await tester.ensureVisible(find.text(l10n.p2pEndPaymentFailed));
        await settle();
        await tester.tap(find.text(l10n.p2pEndPaymentFailed));
        await settle();
        await capture('fin-annuler-confirmation');
        await tester.pump(const Duration(seconds: 61));
        await tester.ensureVisible(find.text(l10n.p2pEndConfirm));
        await settle();
        await tester.tap(find.text(l10n.p2pEndConfirm));
        await waitFor(find.text(fiatSent));
        await tester.tap(find.byIcon(Icons.more_horiz));
        await settle();
        await capture('fin-options');
        await tester.tap(find.text(l10n.p2pEndCollabCancel));
        await settle();
        await capture('fin-annulation-dialogue');
        // The ask held by the coordinator, so that its wait is captured; then it lands after the read that follows it.
        final askHeld = Completer<void>();
        coordinator
          ..hold = askHeld.future
          ..failNext(ScriptedRequest.cancel, ScriptedFault.landsLate);
        await tester.tap(find.text(l10n.p2pEndCollabAsk));
        await waitFor(
          find.text(
            l10n.p2pEndStepSendingRequest(coordinator.coordinator.longAlias),
          ),
        );
        await settle();
        await capture('fin-annulation-attente');
        coordinator.hold = null;
        askHeld.complete();
        await waitFor(find.text(l10n.p2pEndUnknownRequest));
        await settle();
        await capture('fin-avis-demande-inconnue');
        coordinator.landLate();
        await nextRead();
        await waitFor(find.text(l10n.p2pEndCollabAskedAlert));
        await settle();
        await capture('fin-annulation-demandee');
        coordinator.peerAcceptsCancel();
        await nextRead();
        await waitFor(find.text(l10n.p2pOrderCancelled));
        await backToTab();

        // Take 8: the collaborative cancel asked by the peer first: its alert, then « Accept Cancelation » on the user's tap.
        coordinator.backToPublic();
        await take();
        coordinator
          ..lockBond(taker())
          ..moveTo(9)
          ..peerAsksToCancel();
        await nextRead();
        await waitFor(find.textContaining(l10n.p2pEndCollabPeerAlert('')));
        await settle();
        await capture('fin-annulation-pair');
        // « … » opens « Order options », whose « Collaborative Cancel » opens the reference's dialog; the peer's ask turns its button into « Accept Cancelation » (chat_step_panel.dart:271-275, confirm_collab_cancel_dialog.dart:44-51), and each step is waited for rather than tapped blind.
        await reveal(find.byIcon(Icons.more_horiz));
        await tester.tap(find.byIcon(Icons.more_horiz));
        await waitFor(find.text(l10n.p2pEndCollabCancel));
        await tester.ensureVisible(find.text(l10n.p2pEndCollabCancel));
        await settle();
        await tester.tap(find.text(l10n.p2pEndCollabCancel));
        await waitFor(find.text(l10n.p2pEndCollabAccept));
        await tester.ensureVisible(find.text(l10n.p2pEndCollabAccept));
        await settle();
        await capture('fin-annulation-accepter');
        await tester.tap(find.text(l10n.p2pEndCollabAccept));
        await waitFor(find.text(l10n.p2pOrderCancelled));
        await backToTab();

        // Take 9: « Open Dispute » (#95): its time come (the chat ends in an hour), the reference's dialog, the dispute opened (11), both statements in (16), then won (17).
        coordinator.backToPublic();
        await take();
        coordinator
          ..lockBond(taker())
          ..moveTo(9)
          ..moveDeadline(coordinator.clock().add(const Duration(hours: 1)));
        await nextRead();
        await waitFor(find.text(fiatSent));
        await tester.tap(find.byIcon(Icons.more_horiz));
        await settle();
        await capture('fin-options-litige');
        await tester.tap(find.text(l10n.p2pEndOpenDispute));
        await settle();
        await capture('fin-litige-dialogue');
        // The dispute's answer held, so that its step is captured.
        coordinator.failNext(
          ScriptedRequest.dispute,
          ScriptedFault.answerDelayed,
        );
        await tester.ensureVisible(find.text(l10n.p2pEndAgreeDispute));
        await settle();
        await tester.tap(find.text(l10n.p2pEndAgreeDispute));
        await waitFor(
          find.text(
            l10n.p2pEndStepSendingDispute(coordinator.coordinator.longAlias),
          ),
        );
        await settle();
        await capture('fin-litige-envoi');
        coordinator.deliverDelayed();
        await waitFor(find.text(l10n.p2pEndDisputeSaveInfoPeer));
        await settle();
        await capture('fin-litige-11');
        // The watch reads every 100 s at 11 and every 300 s at 16 (the reference's cadence).
        Future<void> slowRead(int seconds) async {
          for (var i = 0; i < seconds ~/ 10 + 1; i++) {
            await tester.pump(const Duration(seconds: 10));
            await settle();
          }
        }

        coordinator.moveTo(16);
        await slowRead(100);
        await waitFor(find.text(l10n.p2pEndDisputeWaitResolution));
        await settle();
        await capture('fin-litige-16');
        coordinator.moveTo(17);
        await slowRead(300);
        await waitFor(find.textContaining(l10n.p2pTradeTitleDisputeWon));
        await settle();
        await capture('fin-litige-17');
        await backToTab();

        // Take 10: a dispute lost (18).
        coordinator.backToPublic();
        await take();
        coordinator
          ..lockBond(taker())
          ..moveTo(11);
        await nextRead();
        await waitFor(find.text(l10n.p2pEndDisputeSaveInfoPeer));
        coordinator.moveTo(18);
        await slowRead(100);
        await waitFor(find.textContaining(l10n.p2pTradeTitleDisputeLost));
        await settle();
        await capture('fin-litige-18');
        await backToTab();

        // Last, another robot's bond locks first: the trade stays open while 1044 may still be a pause, so the order's next take would open it again.
        coordinator.backToPublic();
        await take();
        coordinator.takenByAnother();
        await nextRead();
        await waitFor(find.text(l10n.p2pOrderNotAvailable));
        await capture('echange-indisponible');

        // « Search order » for an order number no coordinator of this test knows, with a Garage Key stored and its records written: the order's page (#245) has its robot read the order, answered as a coordinator answers one it does not know, and the page says it is not available.
        // Last, once no capture follows that a robot of the take could change: the search takes the next robot of the key, which nothing here uses again.
        await backToTab();
        await tester.tap(find.text(l10n.p2pNavOffers));
        await settle();
        final templeOnion = Federation.robosats
            .byAlias('temple')
            ?.mainnet
            .onion;
        transport.unknownOrder = 43;
        await tester.tap(find.text(l10n.p2pCommonSearch));
        await settle();
        await tester.enterText(
          find.byType(TextField),
          '$templeOnion/order/temple/43',
        );
        await settle();
        await tester.tap(find.text(l10n.p2pCommonSearch).last);
        // The order's page, its host row first: the line under it comes once the read is refused.
        await waitFor(find.text('# 43'));
        // The refusal in the page's own list: the search's dialog keeps an invisible copy of that text while it waits (`order_search_miss_dialog.dart:85-92`), which finding the text alone would take for the page's answer before its robot's read is over.
        final refusal = find.descendant(
          of: find.ancestor(
            of: find.text('# 43'),
            matching: find.byType(ListView),
          ),
          matching: find.text(l10n.p2pOrderNotAvailable),
        );
        await waitFor(refusal);
        await tester.ensureVisible(refusal);
        await settle();
        await capture('ordre-indisponible');

        // The screens gone, their cubits closed: the waits they leave (the release of the robots, 10 s at most) run out.
        await backToTab();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 3)),
        );
        await tester.pump(const Duration(minutes: 1));
      },
    );
  }

  // The create form (#181), which no path of the tab opens before #182: built by the testing seam over the recorded coordinators' information and limits (temple, lake, freeport, bazaar and ammanaya on mainnet), the Bull wallet's price played by the test. Nothing is made, no robot exists, no money moves.
  for (final locale in const [Locale('fr'), Locale('en')]) {
    testWidgets(
      'captures of the create form in ${locale.languageCode}',
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

        Future<void> settle() async {
          for (var i = 0; i < 10; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
          await tester.pump(const Duration(seconds: 1));
        }

        Finder list() => find.byType(Scrollable).first;
        Future<void> toBottom() async {
          await tester.drag(list(), const Offset(0, -2000));
          await settle();
        }

        Future<void> toTop() async {
          await tester.drag(list(), const Offset(0, 2000));
          await settle();
        }

        final l10n = lookupP2pLocalizations(locale);
        RobosatsCurrency currency(String code) =>
            RobosatsCurrency.fromCode(code) ?? (throw StateError(code));
        FakeSecureStoragePlatform().install();
        final locator = GetIt.asNewInstance();
        final tor = StreamController<P2pTorState>.broadcast();
        addTearDown(tor.close);
        addTearDown(locator.reset);
        // The Bull wallet's price of the captures: near the recorded coordinators' price of 66,227.95 EUR, then as each capture needs it.
        final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(50000)))
          ..rate = P2pWalletRateRead(66400);
        setUpP2pForTesting(
          locator,
          transport: const _RecordedTransport(RobosatsNetwork.mainnet),
          torStates: () => tor.stream,
          clock: () => _now,
          garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
          wallet: wallet,
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: _frame,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.themeData(AppThemeType.dark),
              locale: locale,
              localizationsDelegates: [
                ...AppLocalizations.localizationsDelegates,
                P2pLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: createOrderPageForTesting(
                  locator,
                  network: RobosatsNetwork.mainnet,
                  currency: currency('EUR'),
                ),
              ),
            ),
          ),
        );
        await settle();
        await settle();
        await capture('creer-vide');
        await toBottom();
        await capture('creer-vide-bas');
        await toTop();

        // Filled: « Buy », 100 EUR, Revolut and a custom method, a premium of 2 %.
        await tester.tap(find.text(l10n.p2pMakeBuy));
        await tester.enterText(find.byType(TextField).at(0), '100');
        await settle();
        await tester.tap(find.byTooltip(l10n.p2pMakeAddCustomMethod));
        await settle();
        await tester.enterText(find.byType(TextField).last, 'Revolut');
        await settle();
        await tester.tap(find.text(l10n.p2pMakeAddPaymentMethod));
        await settle();
        await tester.enterText(find.byType(TextField).at(1), '2');
        await settle();
        await capture('creer-rempli');
        await toBottom();
        await capture('creer-rempli-bas');

        // The custom method refused: a zero width space only.
        await toTop();
        await tester.tap(find.byTooltip(l10n.p2pMakeAddCustomMethod));
        await settle();
        await tester.enterText(
          find.byType(TextField).last,
          String.fromCharCode(0x200B),
        );
        await settle();
        await capture('creer-mode-invisible');
        await tester.tap(find.text(l10n.p2pCommonCancel));
        await settle();

        // The price check: beyond 10 % either way, a currency the Bull wallet does not price, a price it could not read.
        var shown = 'EUR';
        Future<void> showCurrency(String code) async {
          await toTop();
          await tester.tap(find.text(shown).first);
          await settle();
          // The currencies' sheet builds its rows as they scroll into view.
          await tester.scrollUntilVisible(
            find.text(code),
            300,
            scrollable: find.byType(Scrollable).last,
          );
          await settle();
          await tester.tap(find.text(code).last);
          await settle();
          shown = code;
          await toBottom();
        }

        // The recorded price of USD, 73,956.8, more than 10 % below 90,000; that of CAD, 104,648.95, more than 10 % above 90,000. A currency read once is not read again within 3 minutes (security review of #181), so each line has its own currency.
        wallet.rate = P2pWalletRateRead(90000);
        await showCurrency('USD');
        await capture('creer-prix-ecart-bas');
        await showCurrency('CAD');
        await capture('creer-prix-ecart-haut');
        wallet.rate = const P2pWalletRateNotPriced();
        await showCurrency('GBP');
        await capture('creer-prix-non-cote');
        wallet.rate = const P2pWalletRateUnavailable();
        await showCurrency('MXN');
        await capture('creer-prix-illisible');

        // A reason of the disabled button: the amount below the coordinator's smallest order (Ammanaya's is 1,000 sats, about 0.68 EUR with the form's margin).
        await toTop();
        await tester.enterText(find.byType(TextField).at(0), '0.5');
        await settle();
        await capture('creer-montant-trop-bas');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(minutes: 1));
      },
    );
  }
}

const _frame = ValueKey('p2p-capture-frame');

/// The key work of the app, but a new robot's key dated by the screen's clock, a day back, as the app dates it by the system's: the captures' chat signs and verifies at that clock (#93).
final class _DatedRobotKeys implements RobotKeyComputePort {
  final DateTime Function() now;

  static const _keys = IsolateRobotKeyCompute();

  _DatedRobotKeys(this.now);

  @override
  generate(identity) async => switch (RobotPgpKey.generateWith(
    identity,
    now: now(),
    random: Random.secure(),
  )) {
    Ok(:final value) => Ok(value),
    Err() => throw StateError('the screen\'s clock is outside a key\'s dates'),
  };

  @override
  prove(robot) => _keys.prove(robot);

  @override
  unlock(key, identity) => _keys.unlock(key, identity);

  @override
  decryptChat(key, jobs, {required now}) =>
      _keys.decryptChat(key, jobs, now: now);

  @override
  composeNostrChat(
    sender, {
    required order,
    required coordinator,
    required network,
    required text,
    required now,
  }) => _keys.composeNostrChat(
    sender,
    order: order,
    coordinator: coordinator,
    network: network,
    text: text,
    now: now,
  );

  @override
  composeHostRating(
    sender, {
    required token,
    required coordinator,
    required orderId,
    required rating,
    required now,
  }) => _keys.composeHostRating(
    sender,
    token: token,
    coordinator: coordinator,
    orderId: orderId,
    rating: rating,
    now: now,
  );
}

/// The coordinators of the trade captures: Temple of Sats is [temple], the scripted coordinator of the test seam once the test knows the robots of the key it drew, Lake answers a book of one range order of the test, the others an empty book; every invoice is read by [temple]'s decoder.
final class _TradeTransport implements CoordinatorTransport, Bolt11Decoder {
  final DateTime now;
  ScriptedCoordinator? temple;

  /// The number of an order no coordinator of this test knows, answered as a coordinator answers one it does not know (`api/views.py`, 1042 on a `404`): the scripted coordinator would give its own order whatever the number asked.
  int? unknownOrder;

  _TradeTransport(this.now);

  /// The maker of Lake's range order: a robot of no one, its hash id drawn from a fixed text.
  static final _lakeMakerHash = sha256
      .convert(utf8.encode('troc trade capture lake maker'))
      .toString();

  @override
  Result<Bolt11Invoice, Bolt11Refusal> decode(String invoice) =>
      switch (temple) {
        final temple? => temple.decoder.decode(invoice),
        null => const Err(Bolt11Malformed()),
      };

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final alias = Federation.robosats
        .on(RobosatsNetwork.mainnet)
        .firstWhere(
          (c) =>
              Uri.parse(c.origins(RobosatsNetwork.mainnet).onion ?? '').host ==
              request.url.host,
        )
        .shortAlias;
    CoordinatorResponse json(int status, Object body) => CoordinatorResponse(
      statusCode: status,
      headers: const {'content-type': 'application/json'},
      body: utf8.encode(jsonEncode(body)),
    );
    final temple = this.temple;
    final unknown = unknownOrder;
    if (unknown != null &&
        request.url.path == '/api/order/' &&
        request.url.queryParameters['order_id'] == '$unknown') {
      return Ok(
        json(404, {'error_code': 1042, 'bad_request': 'Invalid Order Id'}),
      );
    }
    if (alias == 'temple' && temple != null) return temple.send(request);
    if (alias == 'lake' && request.url.path.contains('book')) {
      return Ok(
        json(200, [
          {
            'id': 7,
            'created_at': now
                .subtract(const Duration(hours: 2))
                .toIso8601String(),
            'expires_at': now.add(const Duration(hours: 20)).toIso8601String(),
            'type': 1,
            'currency': 2,
            'amount': null,
            'has_range': true,
            'min_amount': '50',
            'max_amount': '200',
            'payment_method': 'Revolut Instant SEPA',
            'is_explicit': false,
            'premium': '2.0',
            'satoshis': null,
            'maker': 1,
            'escrow_duration': 10800,
            'bond_size': '3.0',
            'latitude': null,
            'longitude': null,
            'maker_hash_id': _lakeMakerHash,
            'satoshis_now': 213800,
            'price': 93545,
            'maker_status': 'Active',
          },
        ]),
      );
    }
    if (request.url.path.contains('book')) {
      return Ok(json(404, {'not_found': 'No orders found'}));
    }
    return const Err(CoordinatorUnreachable());
  }
}

/// The P2P tab inside a bottom bar like the one of the shell: Wallet, P2P, Exchange.
class _App extends StatelessWidget {
  final Locale locale;
  final GetIt locator;
  final RobosatsNetwork network;

  /// The app's theme, dark unless a capture asks the light one.
  final AppThemeType theme;

  const _App({
    required this.locale,
    required this.locator,
    required this.network,
    this.theme = AppThemeType.dark,
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
        theme: AppTheme.themeData(theme),
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

/// The wallet's port of the captures of the bond paid from this wallet: demonstration figures, no wallet, no swap service, no money.
///
/// The balance is 50,000 sats; a quote asks the invoice's amount and 123 sats of the service, and a network fee of 27; the first quote after [refuseNext] is the service's minimum of 25,000 sats; a payment waits for [finishPayment], then is sent, and [progress] moves it on.
final class _CaptureWallet implements P2pWalletPort {
  final DateTime now;
  bool refuseNext = false;
  Completer<void>? _paying;
  P2pWalletPayment? _payment;
  P2pWalletPaymentProgress _progress = const P2pWalletPaymentSent();
  final _changes = StreamController<P2pWalletPaymentProgress>.broadcast();

  _CaptureWallet(this.now);

  void finishPayment() => _paying?.complete();

  void progress(P2pWalletPaymentProgress progress) {
    _progress = progress;
    _changes.add(progress);
  }

  Future<void> close() => _changes.close();

  @override
  Stream<Result<Sats, P2pWalletRefusal>> instantBalance(network) =>
      Stream.value(Ok(Sats.fromInt(50000)));

  @override
  Future<Result<P2pWalletQuote, P2pWalletRefusal>> quote(invoice) async {
    if (refuseNext) {
      refuseNext = false;
      return Err(P2pWalletUnderMinimum(minimum: Sats.fromInt(25000)));
    }
    return Ok(
      P2pWalletQuote(
        invoice: invoice,
        payin: Sats(invoice.amount.value + BigInt.from(123)),
        networkFee: Sats.fromInt(27),
        balance: Sats.fromInt(50000),
        quotedAt: now,
      ),
    );
  }

  @override
  Future<Result<P2pWalletPayment, P2pWalletRefusal>> payInvoice(
    invoice, {
    required P2pWalletQuote accepted,
  }) async {
    final paying = _paying = Completer<void>();
    await paying.future;
    final payment = _payment = P2pWalletPayment(
      id: 'demonstration',
      paymentHash: invoice.paymentHash,
    );
    return Ok(payment);
  }

  @override
  Stream<Result<P2pWalletPaymentProgress, P2pWalletRefusal>> watchPayment(
    payment,
  ) async* {
    yield Ok(_progress);
    yield* _changes.stream.map(Ok.new);
  }

  @override
  Future<Result<P2pWalletPaymentFound?, P2pWalletRefusal>> findPayment(
    paymentHash,
  ) async => Ok(switch (_payment) {
    final payment? when payment.paymentHash == paymentHash =>
      P2pWalletPaymentFound(payment: payment, progress: _progress),
    _ => null,
  });

  // The payout's wallet button (#90) is captured with its own pull request.
  @override
  Future<Result<P2pWalletInvoice, P2pWalletRefusal>> newLightningInvoice(
    RobosatsNetwork network,
    Sats amount, {
    required String payout,
  }) async => const Err(P2pWalletUnavailable());

  @override
  Future<Result<P2pWalletAddress, P2pWalletRefusal>> newReceiveAddress(
    RobosatsNetwork network,
  ) async => const Err(P2pWalletUnavailable());

  @override
  Future<P2pWalletBitcoinRate> bitcoinRate(
    RobosatsNetwork network,
    RobosatsCurrency currency,
  ) async => const P2pWalletRateUnavailable();
}

/// The public test phrase « abandon ×11 about », the default wallet's words of the Garage captures (#81): never a real wallet's.
const _abandonWords = [
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'about',
];

/// Key 0 of those words on mainnet, the design note's vector: the Garage Key of the captures of trades.
const _abandonMainnetKey0 =
    'robo17u5x0ykpntv26907967s76hh058dwwjc8936zq55wcyyk9r3h87qd7k9t2';

/// Key 0 of those words on testnet, the design note's vector (`docs/design/garage-key-from-the-words.md` § 1): the only key text a capture of the Garage shows.
const _abandonTestnetKey0 =
    'robo1vsap3v8a45z0uw66q26hywyyl0kh727q48dqeac9wra7wt2dgg2s3mfwmz';

/// The wallet's repository of the Garage captures: one default Bitcoin wallet on testnet, whose secret is the test words' ([fingerprint]); nothing else is asked of it.
final class _DefaultWallet implements WalletRepository {
  final String fingerprint;

  _DefaultWallet(this.fingerprint);

  @override
  Future<Result<List<Wallet>, WalletFailure>> getWallets({
    Environment? environment,
    bool? onlyDefaults,
    bool? onlyBitcoin,
    bool? onlyLiquid,
    bool sync = false,
  }) async => Ok([
    if (environment == Environment.testnet)
      Wallet(
        origin: 'testnet-default',
        label: 'Secure Bitcoin',
        network: Network.bitcoinTestnet,
        isDefault: true,
        masterFingerprint: fingerprint,
        xpubFingerprint: fingerprint,
        scriptType: ScriptType.bip84,
        xpub: 'tpub',
        externalPublicDescriptor: 'desc',
        internalPublicDescriptor: 'desc',
        signer: SignerEntity.local,
        signerDevice: null,
        balanceSat: BigInt.zero,
      ),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Gives the trade [orderId] of the book at [file] a role this app never writes, as a book damaged on the device: its trades can no longer be read (review of #292, R-3). The trigger that keeps a role is set aside for the change and put back as it was.
void _unreadableTrade(File file, int orderId) {
  final database = sqlite3.open(file.path);
  try {
    final trigger =
        database
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'trades_set_once'",
                )
                .single
                .values
                .single
            as String;
    for (final statement in [
      'DROP TRIGGER trades_set_once',
      'PRAGMA ignore_check_constraints = ON',
      "UPDATE trades SET role = 'unknown' WHERE order_id = $orderId",
      'PRAGMA ignore_check_constraints = OFF',
      trigger,
    ]) {
      database.execute(statement);
    }
  } finally {
    database.dispose();
  }
}

/// The book at [file], written by this version of the app, made a book of schema 9, the one an update finds: the objects of schema 10 dropped and the version set back, then [rows] written.
void _toSchema9(File file, List<String> rows) {
  final database = sqlite3.open(file.path);
  try {
    for (final statement in [
      'DROP TRIGGER IF EXISTS derived_garage_keys_never_deleted',
      'DROP TRIGGER IF EXISTS derived_garage_keys_never_changed',
      'DROP TRIGGER IF EXISTS derived_garage_keys_in_order',
      'DROP TRIGGER IF EXISTS derived_garage_keys_inserted_once',
      'DROP TRIGGER IF EXISTS garage_notices_shown_once',
      'DROP TRIGGER IF EXISTS garage_notices_never_deleted',
      'DROP TABLE IF EXISTS derived_garage_keys',
      'DROP TABLE IF EXISTS selected_garage_keys',
      'DROP TABLE IF EXISTS garage_notices',
      ...rows,
      'PRAGMA user_version = 9',
    ]) {
      database.execute(statement);
    }
  } finally {
    database.dispose();
  }
}
