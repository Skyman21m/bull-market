import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show bookOrder, testNow;
import 'support/harness.dart';

/// The alert of a protected order on a coordinator older than 0.8.7, or of unknown version, stays on screen whenever a password is sent (#189, independent review C1): under « Password » while the field is in the form, near the summary while it is not (advanced options closed, fields folded away by « Existing orders match yours! »), never both; by gestures on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`).
///
/// The coordinators are played by [_Coordinators], never real ones: `/api/info/` with the version the test gives each, or unreadable; the book of the test for temple, empty elsewhere. Nothing is made.
const _net = RobosatsNetwork.mainnet;

/// A password of the tests, never anyone's.
const _password = 'a test password';

final _other = Federation.robosats
    .on(_net)
    .firstWhere((coordinator) => coordinator.shortAlias != 'temple');

final class _Coordinators implements CoordinatorTransport {
  final Map<String, ({int major, int minor, int patch})> versions;
  final Set<String> unreadable;
  final Map<String, List<Map<String, Object?>>> books;
  final Map<String, ScriptedMakerCoordinator> _scripted = {};

  _Coordinators({
    this.versions = const {},
    this.unreadable = const {},
    this.books = const {},
  });

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final alias = _aliasOf(request.url.host);
    final path = request.url.path;
    if (path.startsWith('/api/book')) {
      final book = books[alias];
      return Ok(
        book == null
            ? _json(404, {
                'not_found': 'No orders found, be the first to make one',
              })
            : _json(200, book),
      );
    }
    if (path == '/api/info/' && unreadable.contains(alias)) {
      return Ok(_json(500, {'bad_request': 'down'}));
    }
    final scripted = _scripted[alias] ??=
        ScriptedMakerCoordinator(
            network: _net,
            robots: const [],
            clock: () => testNow,
            alias: alias,
          )
          ..prices[1] = 100000
          ..version = versions[alias] ?? (major: 0, minor: 8, patch: 8);
    return scripted.send(request);
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

void main() {
  final l10n = lookupP2pLocalizations(const Locale('en'));

  Finder inForm(Finder finder) =>
      find.descendant(of: find.byType(CreateOrderScreen), matching: finder);

  Finder passwordField() => inForm(
    find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == l10n.p2pMakePassword,
    ),
  );

  Finder alertOf(Coordinator coordinator, String version) => find.text(
    l10n.p2pMakePasswordOldCoordinator(coordinator.longAlias, version),
  );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  /// The form opened from « Create » on the tab over [coordinators].
  Future<void> open(WidgetTester tester, _Coordinators coordinators) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 3200 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    setUpP2pForTesting(
      locator,
      transport: coordinators,
      torStates: () => tor.stream,
      clock: () => testNow,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
    );
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [const P2pFeature().route(locator, network: (_) => _net)],
    );
    await tester.pumpWidget(routerHarness(router));
    tor.add(P2pTorState.ready);
    await settle(tester);
    await settle(tester);
    await tap(tester, find.text(l10n.p2pNavCreate));
    await settle(tester);
    expect(find.byType(CreateOrderScreen), findsOneWidget);
  }

  /// « Select Host », then [coordinator].
  Future<void> choose(WidgetTester tester, Coordinator coordinator) async {
    await tap(tester, inForm(find.byIcon(Icons.arrow_drop_down)));
    await tap(tester, find.text(coordinator.longAlias).last);
    await settle(tester);
  }

  /// « Buy », 100 USD, « Revolut », 2 %.
  Future<void> fill(WidgetTester tester) async {
    await tap(tester, inForm(find.text(l10n.p2pMakeBuy)));
    await tester.enterText(inForm(find.byType(TextField)).at(0), '100');
    await settle(tester);
    await tester.enterText(inForm(find.byType(TextField)).at(1), '2');
    await settle(tester);
    await tap(tester, inForm(find.byTooltip(l10n.p2pMakeAddCustomMethod)));
    await tester.enterText(find.byType(TextField).last, 'Revolut');
    await tester.pump();
    await tap(tester, find.text(l10n.p2pMakeAddPaymentMethod));
  }

  Future<void> toggleOptions(WidgetTester tester) =>
      tap(tester, inForm(find.byType(Switch)).first);

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.pump(const Duration(seconds: 61));
  }

  testWidgets(
    'a password typed on a coordinator of 0.8.8, the options closed, then a coordinator of 0.8.6 chosen: the alert in one line before « Create order », under the field once the options are open again, never twice',
    (tester) async {
      await open(
        tester,
        _Coordinators(
          versions: {_other.shortAlias: (major: 0, minor: 8, patch: 6)},
        ),
      );
      final temple = Federation.robosats.byAlias('temple') ?? fail('temple');
      await choose(tester, temple);
      await fill(tester);
      await toggleOptions(tester);
      await tester.enterText(passwordField(), _password);
      await settle(tester);
      expect(find.textContaining('0.8.6'), findsNothing);
      // Closed: the field leaves the form, the password is still sent.
      await toggleOptions(tester);
      expect(passwordField(), findsNothing);
      expect(
        inForm(
          find.text(
            l10n.p2pMakeOptionsSentClosed(l10n.p2pMakeOptionSentPassword),
          ),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('0.8.6'), findsNothing);
      await choose(tester, _other);
      // Near the summary, in one line, with its explanation on demand.
      expect(alertOf(_other, '0.8.6'), findsOneWidget);
      expect(
        inForm(find.widgetWithText(TradeButton, l10n.p2pMakeCreateOrder)),
        findsOneWidget,
      );
      expect(find.text(l10n.p2pMakePasswordOldDetail), findsNothing);
      await tap(tester, inForm(find.text(l10n.p2pMakeSeeDetails)).last);
      expect(find.text(l10n.p2pMakePasswordOldDetail), findsOneWidget);
      // The options open again: under the field only.
      await toggleOptions(tester);
      expect(passwordField(), findsOneWidget);
      expect(alertOf(_other, '0.8.6'), findsOneWidget);
      expect(
        find.descendant(
          of: find
              .ancestor(of: passwordField(), matching: find.byType(Column))
              .first,
          matching: alertOf(_other, '0.8.6'),
        ),
        findsOneWidget,
      );
      // No password: no alert anywhere.
      await tester.enterText(passwordField(), '');
      await settle(tester);
      await toggleOptions(tester);
      expect(find.textContaining('0.8.6'), findsNothing);
      await close(tester);
    },
  );

  testWidgets(
    'a coordinator whose version could not be read, the options closed: « version unknown » before « Create order »',
    (tester) async {
      await open(tester, _Coordinators(unreadable: {_other.shortAlias}));
      final temple = Federation.robosats.byAlias('temple') ?? fail('temple');
      await choose(tester, temple);
      await fill(tester);
      await toggleOptions(tester);
      await tester.enterText(passwordField(), _password);
      await settle(tester);
      await toggleOptions(tester);
      await choose(tester, _other);
      expect(
        find.text(l10n.p2pMakePasswordUnknownVersion(_other.longAlias)),
        findsOneWidget,
      );
      await close(tester);
    },
  );

  testWidgets(
    'the fields folded away by « Existing orders match yours! »: the alert stays near the summary',
    (tester) async {
      await open(
        tester,
        _Coordinators(
          versions: {'temple': (major: 0, minor: 8, patch: 6)},
          books: {
            'temple': [bookOrder(id: 11, currency: 1, premium: 1)],
          },
        ),
      );
      final temple = Federation.robosats.byAlias('temple') ?? fail('temple');
      await choose(tester, temple);
      await fill(tester);
      await toggleOptions(tester);
      // The range the options open on: back to the exact amount, which the search uses.
      await tap(tester, inForm(find.byType(Switch)).at(1));
      await tester.enterText(inForm(find.byType(TextField)).at(0), '100');
      await settle(tester);
      await tester.enterText(passwordField(), _password);
      await settle(tester);
      expect(alertOf(temple, '0.8.6'), findsOneWidget);
      await tap(tester, inForm(find.text(l10n.p2pMakeSubmit)));
      expect(inForm(find.text(l10n.p2pMakeMatchesFound)), findsOneWidget);
      expect(passwordField(), findsNothing);
      expect(alertOf(temple, '0.8.6'), findsOneWidget);
      await close(tester);
    },
  );
}
