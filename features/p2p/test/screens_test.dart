import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/tor_wait.dart';
import 'package:p2p/src/ui/order_details_screen.dart';
import 'package:p2p/src/ui/tor_wait_view.dart';
import 'package:p2p/testing.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// The recorded `/api/info/` of temple on mainnet, for the fees of the order page.
Map<String, Object?> templeInfo() =>
    jsonDecode(
          File(
            '../../packages/robosats/test/fixtures/coordinator/temple-mainnet-info.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  group('Tor wait', () {
    Future<void> show(
      WidgetTester tester,
      TorWait tor, {
      VoidCallback? onRetry,
    }) => tester.pumpWidget(
      harness(TorWaitView(tor: tor, onRetry: onRetry ?? () {})),
    );

    testWidgets('initializing: the first step is current', (tester) async {
      await show(tester, TorWait.initializing);

      expect(find.text('Connecting to Tor network'), findsNWidgets(2));
      expect(find.text('Initializing Tor daemon'), findsOneWidget);
      expect(find.text('Connected to Tor network'), findsOneWidget);
      expect(
        find.text('Coordinators are only ever reached through Tor.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0,
      );
    });

    testWidgets('connecting: one step done out of three', (tester) async {
      await show(tester, TorWait.connecting);

      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(1 / 3, 0.001),
      );
    });

    testWidgets('failed: the error and a retry', (tester) async {
      var retried = 0;
      await show(tester, TorWait.failed, onRetry: () => retried++);

      expect(find.text('Connection error'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });

    testWidgets('in French', (tester) async {
      await tester.pumpWidget(
        harness(
          TorWaitView(tor: TorWait.connecting, onRetry: () {}),
          locale: const Locale('fr'),
        ),
      );

      expect(find.text('Connexion au réseau Tor'), findsNWidgets(2));
      expect(find.text('Initialisation du service Tor'), findsOneWidget);
      expect(
        find.text('La connexion aux coordinateurs passe uniquement par Tor.'),
        findsOneWidget,
      );
    });
  });

  group('book and order', () {
    late GetIt locator;
    late FakeTransport transport;
    late StreamController<P2pTorState> tor;

    setUp(() {
      locator = GetIt.asNewInstance();
      tor = StreamController<P2pTorState>.broadcast();
      transport = FakeTransport(
        books: {
          'temple': [
            bookOrder(id: 48213, makerSeed: 1),
            bookOrder(
              id: 2,
              minAmount: 50,
              maxAmount: 300,
              premium: 3.5,
              paymentMethod: 'Instant SEPA',
              makerSeed: 2,
            ),
          ],
          'lake': [bookOrder(id: 3, type: 0, premium: 4, makerSeed: 3)],
        },
        failures: {'bazaar': const CoordinatorTimedOut()},
        infos: {'temple': templeInfo()},
      );
      setUpP2pForTesting(
        locator,
        transport: transport,
        torStates: () => tor.stream,
        clock: () => testNow,
      );
    });

    tearDown(() async {
      await tor.close();
      await locator.reset();
    });

    Future<void> open(
      WidgetTester tester, {
      RobosatsNetwork network = RobosatsNetwork.mainnet,
      Locale locale = const Locale('en'),
    }) async {
      usePhoneScreen(tester);
      final router = GoRouter(
        initialLocation: P2pFeature.path,
        routes: [const P2pFeature().route(locator, network: (_) => network)],
      );
      await tester.pumpWidget(routerHarness(router, locale: locale));
      await settle(tester);
    }

    testWidgets('waits for Tor, then lists every offer received', (
      tester,
    ) async {
      await open(tester);
      tor.add(P2pTorState.connecting);
      await settle(tester);
      expect(find.text('Initializing Tor daemon'), findsOneWidget);
      expect(transport.requested, isEmpty);

      tor.add(P2pTorState.ready);
      await settle(tester);

      expect(find.text('Offers'), findsOneWidget);
      expect(find.text('I want to'), findsOneWidget);
      expect(find.text('Seller'), findsNWidgets(2));
      expect(find.text('Buyer'), findsOneWidget);
      expect(find.text('100 EUR', findRichText: true), findsNWidgets(2));
      expect(find.text('50-300 EUR', findRichText: true), findsOneWidget);
      expect(find.textContaining('+3.5%', findRichText: true), findsOneWidget);
      expect(find.text('List'), findsOneWidget);
      expect(find.text('Chart'), findsOneWidget);
    });

    testWidgets('a failed coordinator is shown, and retry asks it again', (
      tester,
    ) async {
      await open(tester);
      tor.add(P2pTorState.ready);
      await settle(tester);

      expect(find.text('LibreBazaar · Coordinator offline'), findsOneWidget);
      expect(find.text('Seller'), findsNWidgets(2));

      transport
        ..failures.clear()
        ..requested.clear();
      await tester.tap(find.text('Retry'));
      await settle(tester);

      expect(transport.requested, ['bazaar/api/book/']);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('the filter sentence narrows the book', (tester) async {
      await open(tester);
      tor.add(P2pTorState.ready);
      await settle(tester);

      await tester.tap(find.text('ANY').first);
      await settle(tester);
      await tester.tap(find.text('Sell').last);
      await settle(tester);

      expect(find.text('Buyer'), findsOneWidget);
      expect(find.text('Seller'), findsNothing);
    });

    testWidgets('an offer opens its details, read-only', (tester) async {
      await open(tester);
      tor.add(P2pTorState.ready);
      await settle(tester);

      await tester.tap(find.text('100 EUR', findRichText: true).first);
      await settle(tester);

      expect(find.text('Order'), findsOneWidget);
      expect(find.text('Temple of Sats'), findsOneWidget);
      expect(find.text('Order host'), findsOneWidget);
      expect(find.text('# 48213'), findsOneWidget);
      expect(find.text('Order Details'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('You send via Instant SEPA · Revolut'), findsNothing);
      expect(find.text('You send via Revolut Instant SEPA'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(OrderDetailsScreen),
          matching: find.text('100 EUR'),
        ),
        findsNWidgets(2),
      );
      expect(find.text('You receive'), findsOneWidget);
      expect(find.text('Accepted payment methods'), findsOneWidget);
      expect(find.text('Price and Premium'), findsOneWidget);
      expect(find.text('93,330 EUR/BTC - Premium: 2.0%'), findsOneWidget);
      expect(find.text('Expires in'), findsOneWidget);
      expect(find.text('17h 00m 00s'), findsOneWidget);
      expect(find.text('Deposit'), findsOneWidget);
      expect(find.text('3h'), findsOneWidget);
      expect(find.text('Order maker · Active'), findsOneWidget);
      final take = tester.widget<BullButton>(find.byType(BullButton));
      expect(take.label, 'Take Order');
      expect(take.disabled, isTrue);
    });

    testWidgets('a reversible payment method shows the warning of RoboSats', (
      tester,
    ) async {
      await open(tester);
      tor.add(P2pTorState.ready);
      await settle(tester);
      // Order 48213 is paid with Revolut, which the community reports as reversible.
      await tester.tap(find.text('100 EUR', findRichText: true).first);
      await settle(tester);

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.warning_amber_rounded));
      await settle(tester);
      expect(find.text('Reversible payments'), findsOneWidget);

      await tester.tap(find.text('Acknowledged'));
      await settle(tester);
      expect(find.text('Reversible payments'), findsNothing);
    });

    testWidgets('a method that cannot be reversed shows no warning', (
      tester,
    ) async {
      await open(tester);
      tor.add(P2pTorState.ready);
      await settle(tester);
      // Order 2 is paid with Instant SEPA only.
      await tester.tap(find.text('50-300 EUR', findRichText: true));
      await settle(tester);

      expect(find.text('Instant SEPA'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('the order page in French, with the fees of the host', (
      tester,
    ) async {
      await open(tester, locale: const Locale('fr'));
      tor.add(P2pTorState.ready);
      await settle(tester);
      await tester.tap(find.text('100 EUR', findRichText: true).first);
      await settle(tester);

      expect(find.text('Ordre'), findsOneWidget);
      expect(find.text("Hôte de l'ordre"), findsOneWidget);
      expect(find.text("Détails de l'ordre"), findsOneWidget);
      expect(find.text('Montant'), findsOneWidget);
      expect(
        find.text('Vous envoyez via Revolut Instant SEPA'),
        findsOneWidget,
      );
      expect(find.text('Vous recevez'), findsOneWidget);
      expect(find.text('Modes de paiement acceptés'), findsOneWidget);
      expect(find.text('Prix et prime'), findsOneWidget);
      expect(find.text('Expire dans'), findsOneWidget);
      expect(find.text('17 h 00 min 00 s'), findsOneWidget);
      expect(find.text('Dépôt'), findsOneWidget);
      expect(find.textContaining('Créateur de l'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text("Prendre l'ordre"),
        200,
        scrollable: find
            .descendant(
              of: find.byType(OrderDetailsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text("Prendre l'ordre"), findsOneWidget);
      expect(find.textContaining('C 0,025'), findsOneWidget);
      // The on-chain payout fee with one decimal, as the official client writes it.
      expect(find.textContaining('3,4\u00a0%'), findsOneWidget);
    });

    testWidgets('testnet shows its banner', (tester) async {
      transport = FakeTransport(network: RobosatsNetwork.testnet);
      await locator.reset();
      setUpP2pForTesting(
        locator,
        transport: transport,
        torStates: () => tor.stream,
        clock: () => testNow,
      );
      await open(tester, network: RobosatsNetwork.testnet);

      expect(find.text('Using Testnet Bitcoin'), findsOneWidget);
      tor.add(P2pTorState.ready);
      await settle(tester);
      expect(find.text('No orders found to buy BTC for ANY'), findsOneWidget);
      expect(find.text('Be the first one to create an order'), findsOneWidget);
    });
  });
}
