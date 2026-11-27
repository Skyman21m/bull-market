import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/ui/unlisted_order_screen.dart';
import 'package:p2p/src/ui/search_order_dialog.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/harness.dart';
import 'support/signed_bodies.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// A password-protected order taken on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`) by the user's gestures (#245), in English and in French: « Search order » with its URL, the page its robot reads, « Password », « Take Order », « Continue », « Done »; a wrong password, then the right one.
///
/// The order's coordinator is played by [ScriptedCoordinator] (never a real one), which leaves the protected order out of its book, hides its description and place from a robot that takes no part, and refuses a wrong password with error 1045, as the reference does; the other coordinators' books are empty. The password is a test text, never anyone's. Nothing is paid.
const _net = RobosatsNetwork.testnet;

/// A password of the tests.
const _password = 'a test password';

/// Its SHA-256 in lowercase hexadecimal, computed apart (`hashlib.sha256(b'a test password').hexdigest()`).
const _passwordHash =
    '7c8c067cf46835b89fb83f6e9f1faab5bfadabd658aba621d7ecd6b36534d6f8';

/// temple's requests to [temple]; the other coordinators' books empty and their `/api/info/` their own.
final class _Coordinators implements CoordinatorTransport {
  final ScriptedCoordinator temple;
  final Map<String, ScriptedCoordinator> _others = {};

  /// Whether temple's book leaves the order out, as a book read before the order was made.
  final bool bookWithout;

  _Coordinators(this.temple, {this.bookWithout = false});

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final alias = _aliasOf(request.url.host);
    if (alias == temple.coordinator.shortAlias) {
      // An order made after the book was read: its coordinator's book, read when the tab opened, did not hold it.
      if (bookWithout && request.url.path.startsWith('/api/book')) {
        return Ok(
          CoordinatorResponse(
            statusCode: 404,
            headers: const {'content-type': 'application/json'},
            body: utf8.encode(jsonEncode({'not_found': 'No orders found'})),
          ),
        );
      }
      return temple.send(request);
    }
    if (request.url.path.startsWith('/api/book')) {
      return Ok(
        CoordinatorResponse(
          statusCode: 404,
          headers: const {'content-type': 'application/json'},
          body: utf8.encode(
            jsonEncode({
              'not_found': 'No orders found, be the first to make one',
            }),
          ),
        ),
      );
    }
    final other = _others[alias] ??= ScriptedCoordinator(
      network: _net,
      robots: const [],
      clock: () => DateTime.utc(2026, 11, 20, 9),
      alias: alias,
    );
    return other.send(request);
  }

  static String _aliasOf(String host) {
    for (final coordinator in Federation.robosats.on(_net)) {
      if (Uri.parse(coordinator.origins(_net).onion ?? '').host == host) {
        return coordinator.shortAlias;
      }
    }
    throw StateError('unknown host');
  }
}

final class _Journey {
  final WidgetTester tester;
  final ScriptedCoordinator coordinator;
  final void Function(Duration) advance;
  final Locale locale;

  _Journey(this.tester, this.coordinator, this.advance, this.locale);

  P2pLocalizations get l10n => lookupP2pLocalizations(locale);

  Finder get passwordField => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.obscureText,
  );

  /// The bodies of the takes, as sent, oldest first.
  List<String> get takes => [
    for (final request in coordinator.requests)
      if (request.method == CoordinatorHttpMethod.post &&
          request.url.path == '/api/order/')
        unsignedBodyOf(request.body),
  ];

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

  /// [password] `null`: a public order made after the book was read, which the book in memory does not hold; [taken]: an order already taken by another robot.
  static Future<_Journey> start(
    WidgetTester tester,
    Locale locale, {
    String? password = _password,
    bool taken = false,
  }) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 3200 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    var clock = DateTime.utc(2026, 11, 20, 9);
    final coordinator =
        ScriptedCoordinator(
            network: _net,
            robots: TradeHarness.robotsOf(_net),
            clock: () => clock,
            password: password,
          )
          ..description = 'Cash in hand, near the station.'
          ..meetingPoint = (45.76, 4.83)
          // « Cash F2F » for the protected order, as the reference shows the place only for it (`OrderDetails/index.tsx:409`).
          ..paymentMethod = password == null
              ? 'Revolut Instant SEPA'
              : 'Cash F2F';
    if (taken) coordinator.takenByAnother();
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    setUpP2pForTesting(
      locator,
      transport: _Coordinators(coordinator, bookWithout: password == null),
      torStates: () => tor.stream,
      clock: () => clock,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      robotKeys: HarnessKeys(),
      bolt11Decoder: coordinator.decoder,
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

  /// « Search », the order's URL, « Search »: the order's page, read by its robot, until [shown].
  Future<void> searchOrder({Finder? shown}) async {
    await tap(find.text(l10n.p2pCommonSearch));
    await settle(tester);
    final dialog = find.byType(SearchOrderDialog);
    final host = Uri.parse(
      coordinator.coordinator.origins(_net).onion ?? '',
    ).host;
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      'http://$host/order/temple/42',
    );
    await tap(
      find.descendant(of: dialog, matching: find.text(l10n.p2pCommonSearch)),
    );
    await waitFor(shown ?? passwordField);
    await settle(tester);
  }

  /// « Take Order », the robot's read shown, « Continue » and « Done ».
  Future<void> take() async {
    await tap(find.text(l10n.p2pTakeOrder));
    await waitFor(find.text(l10n.p2pTakerBond));
    await tap(find.text(l10n.p2pCommonContinue));
    await settle(tester);
    await tap(find.text(l10n.p2pCommonDone));
    await settle(tester);
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.pump(const Duration(seconds: 61));
  }
}

void main() {
  for (final (locale, wrong, missing) in [
    (const Locale('en'), 'Wrong password', 'Enter the order\'s password.'),
    (
      const Locale('fr'),
      'Mot de passe incorrect',
      'Saisissez le mot de passe de l’ordre.',
    ),
  ]) {
    group('a protected order taken by its URL (#245), ${locale.languageCode}', () {
      testWidgets(
        'its page as its robot read it, « Password » above « Take Order »; empty, nothing starts; wrong, the coordinator\'s refusal and nothing taken; right, the trade, the take carrying the SHA-256 only',
        (tester) async {
          final journey = await _Journey.start(tester, locale);
          final l10n = journey.l10n;
          await journey.searchOrder();

          // The page of the order, its robot's read: no book listed it.
          expect(find.byType(UnlistedOrderScreen), findsOneWidget);
          expect(find.text('# 42'), findsOneWidget);
          expect(find.text(l10n.p2pMakePassword), findsOneWidget);
          expect(find.text(l10n.p2pTakeProtectedHidden), findsOneWidget);
          // Typed hidden, and nothing of it learnt, suggested or corrected by the keyboard.
          final field = tester.widget<TextField>(journey.passwordField);
          expect(field.obscureText, isTrue);
          expect(field.autocorrect, isFalse);
          expect(field.enableSuggestions, isFalse);
          expect(field.enableIMEPersonalizedLearning, isFalse);
          // Its description hidden from a robot that takes no part.
          expect(find.text('Cash in hand, near the station.'), findsNothing);
          expect(journey.takes, isEmpty);

          // Empty: nothing starts, and the reason under the button.
          final before = List.of(journey.coordinator.received);
          await journey.tap(find.text(l10n.p2pTakeOrder));
          await settle(tester);
          expect(find.text(missing), findsOneWidget);
          expect(journey.coordinator.received, before);

          // A wrong password: refused by the coordinator, nothing taken, the field kept to be corrected.
          await tester.enterText(journey.passwordField, 'not the password');
          await settle(tester);
          expect(find.text(missing), findsNothing);
          await journey.take();
          await journey.waitFor(find.text(wrong));
          expect(find.byType(TradeScreen), findsNothing);
          expect(journey.takes, hasLength(1));
          expect(journey.takes.single, isNot(contains('not the password')));
          expect(
            TradeHarness.robotsOf(_net).where(journey.coordinator.holdsPreTake),
            isEmpty,
          );
          expect(find.text(l10n.p2pTakeOrder), findsOneWidget);

          // The right one: the trade, its take carrying the hash only.
          await tester.enterText(journey.passwordField, _password);
          await settle(tester);
          await journey.take();
          await journey.waitFor(find.byType(TradeScreen));
          expect(journey.takes, hasLength(2));
          expect(
            journey.takes.last,
            '{"action":"take","password":"$_passwordHash","amount":0}',
          );
          expect(journey.takes.join(), isNot(contains(_password)));
          expect(
            TradeHarness.robotsOf(_net).where(journey.coordinator.holdsPreTake),
            hasLength(1),
          );

          // The description and the place, given now that the robot takes part, on the « Order » tab.
          await journey.tap(find.text(l10n.p2pNavOrder).last);
          await settle(tester);
          await journey.waitFor(find.text('Cash in hand, near the station.'));
          expect(find.text(l10n.p2pTradeMeetingPoint), findsOneWidget);
          expect(find.text('45.76, 4.83'), findsOneWidget);
          expect(
            find.text(l10n.p2pTradeMeetingPointApproximate),
            findsOneWidget,
          );
          await journey.close();
        },
      );
    });

    group(
      'an order reached by its URL that the book in memory does not hold (#245), ${locale.languageCode}',
      () {
        testWidgets(
          'a public order made after the book was read: its page with no « Password », taken with every comparison, its description on the « Order » tab, no place without « Cash F2F »',
          (tester) async {
            final journey = await _Journey.start(
              tester,
              locale,
              password: null,
            );
            final l10n = journey.l10n;
            await journey.searchOrder(shown: find.text(l10n.p2pTakeOrder));
            expect(find.byType(UnlistedOrderScreen), findsOneWidget);
            expect(journey.passwordField, findsNothing);
            expect(find.text(l10n.p2pMakePassword), findsNothing);
            expect(find.text(l10n.p2pTakeProtectedHidden), findsNothing);
            expect(find.text(l10n.p2pOrderNotAvailable), findsNothing);
            await journey.take();
            await journey.waitFor(find.byType(TradeScreen));
            expect(journey.takes, ['{"action":"take","amount":0}']);
            await journey.tap(find.text(l10n.p2pNavOrder).last);
            await settle(tester);
            await journey.waitFor(find.text('Cash in hand, near the station.'));
            expect(find.text(l10n.p2pTradeMeetingPoint), findsNothing);
            await journey.close();
          },
        );

        testWidgets(
          'an order a coordinator shows to a robot that takes no part although it is no longer public: « This order is not available », nothing to take',
          (tester) async {
            final journey = await _Journey.start(
              tester,
              locale,
              password: null,
            );
            // The reference answers 1044 there (`api/views.py:265-271`); a coordinator that shows the order at 6 all the same is not believed.
            journey.coordinator.robotView['status'] = 6;
            final l10n = journey.l10n;
            await journey.searchOrder(
              shown: find.text(l10n.p2pOrderNotAvailable),
            );
            final page = find.byType(UnlistedOrderScreen);
            expect(
              find.descendant(of: page, matching: find.text(l10n.p2pTakeOrder)),
              findsNothing,
            );
            expect(journey.takes, isEmpty);
            await journey.close();
          },
        );

        testWidgets(
          'an order already taken: « This order is not available », nothing to take',
          (tester) async {
            final journey = await _Journey.start(
              tester,
              locale,
              password: null,
              taken: true,
            );
            final l10n = journey.l10n;
            await journey.searchOrder(
              shown: find.text(l10n.p2pOrderNotAvailable),
            );
            expect(find.byType(UnlistedOrderScreen), findsOneWidget);
            // The page says it alone: no « Take Order », no « Retry » (the tab under it may show its own).
            final page = find.byType(UnlistedOrderScreen);
            expect(
              find.descendant(of: page, matching: find.text(l10n.p2pTakeOrder)),
              findsNothing,
            );
            expect(
              find.descendant(
                of: page,
                matching: find.text(l10n.p2pCommonRetry),
              ),
              findsNothing,
            );
            expect(journey.takes, isEmpty);
            await journey.close();
          },
        );
      },
    );
  }
}
