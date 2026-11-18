import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/presentation/active_trades_cubit.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/order_details_screen.dart';
import 'package:p2p/src/ui/widgets/offer_row.dart';
import 'package:p2p/testing.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show bookOrder, testNow;
import 'support/harness.dart';
import 'support/trade_harness.dart' show tradeKey;

/// « Existing orders match yours! » on the app's real composition and navigation (#186): the tab's book, « Create », the form filled by gestures, « Submit », an order opened from the list and the way back; every request counted, so that the search is seen to ask nothing of anyone.
///
/// The coordinators are played by [_Coordinators], never real ones.
void main() {
  /// The book of temple: USD orders, of which #11 (a sell order at 1 %) and #12 (a sell order at 1.5 %, a range) match « Buy », 100 USD, Revolut, 2 %; #13 is a buy order, #14 a sell order at 3 %.
  final templeBook = [
    bookOrder(id: 11, currency: 1, premium: 1),
    bookOrder(
      id: 12,
      currency: 1,
      premium: 1.5,
      amount: null,
      minAmount: 50,
      maxAmount: 400,
    ),
    bookOrder(id: 13, currency: 1, type: 0),
    bookOrder(id: 14, currency: 1, premium: 3),
  ];

  /// The tab over the real composition, the device's active trades listed as [active] (the composition's lister replaced, as `maker_tab_routes_test.dart` does), everything else the composition's own.
  Future<(_Coordinators, GoRouter)> open(
    WidgetTester tester, {
    List<ActiveTrade>? active,
  }) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 2400 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    final coordinators = _Coordinators({'temple': templeBook});
    setUpP2pForTesting(
      locator,
      transport: coordinators,
      torStates: () => tor.stream,
      clock: () => testNow,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
    );
    if (active != null) {
      locator
        ..unregister<ActiveTradesCubit>()
        ..registerFactoryParam<ActiveTradesCubit, RobosatsNetwork, void>(
          (network, _) => ActiveTradesCubit(
            network,
            (network) => Stream<Result<List<ActiveTrade>, P2pFailure>>.value(
              Ok(List.of(active)),
            ),
          ),
        );
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
    await tester.pumpWidget(routerHarness(router));
    tor.add(P2pTorState.ready);
    await settle(tester);
    await settle(tester);
    return (coordinators, router);
  }

  Finder inForm(Finder finder) =>
      find.descendant(of: find.byType(CreateOrderScreen), matching: finder);

  /// « Buy », 100, « Revolut » added as a custom method, 2 %, typed in the form as the user does.
  Future<void> fill(WidgetTester tester) async {
    await tester.tap(inForm(find.text('Buy')));
    await tester.enterText(inForm(find.byType(TextField)).at(0), '100');
    await settle(tester);
    await tester.tap(inForm(find.byTooltip('Add custom payment method')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Revolut');
    await tester.pump();
    await tester.tap(find.text('Add payment method'));
    await settle(tester);
    await tester.enterText(inForm(find.byType(TextField)).at(1), '2');
    await settle(tester);
  }

  List<int> shown(WidgetTester tester) => [
    for (final row in tester.widgetList<OfferRow>(
      inForm(find.byType(OfferRow)),
    ))
      row.order.id,
  ];

  testWidgets(
    '« Create », the form filled, « Submit »: the orders of the book that match, asking nothing; a tap opens one with « Take Order », back is the form with its list',
    (tester) async {
      final (coordinators, _) = await open(tester);
      final atBook = coordinators.requested.length;
      expect(
        coordinators.requested.where((r) => r.contains('/api/book')),
        isNotEmpty,
      );
      await tester.tap(find.text('Create'));
      await settle(tester);
      expect(find.byType(CreateOrderScreen), findsOneWidget);
      await fill(tester);
      // What the form itself read when it opened (each coordinator's information, the chosen one's limits): no book, nothing more for the search.
      final atForm = [...coordinators.requested.skip(atBook)];
      expect(atForm.where((r) => r.contains('/api/book')), isEmpty);
      expect(
        atForm.every(
          (r) => r.endsWith('/api/info/') || r.endsWith('/api/limits/'),
        ),
        isTrue,
        reason: '$atForm',
      );
      expect(inForm(find.text('Submit')), findsOneWidget);
      await tester.tap(inForm(find.text('Submit')));
      await settle(tester);
      expect(inForm(find.text('Existing orders match yours!')), findsOneWidget);
      // Two match, of which the reference's table shows one (`MatchingOrders.rowsShown`): the lowest premium.
      expect(shown(tester), [11]);
      expect(inForm(find.text('Create order')), findsOneWidget);
      expect(inForm(find.byTooltip('Edit order')), findsOneWidget);
      // The search and « Submit » asked nothing of anyone.
      expect(coordinators.requested.skip(atBook), atForm);

      await tester.tap(inForm(find.byType(OfferRow)).first);
      await settle(tester);
      await settle(tester);
      expect(find.byType(OrderDetailsScreen), findsOneWidget);
      expect(
        tester
            .widget<OrderDetailsScreen>(find.byType(OrderDetailsScreen))
            .canTake,
        isTrue,
      );
      // The system's back, as on the phone.
      await tester.binding.handlePopRoute();
      await settle(tester);
      await settle(tester);
      expect(find.byType(OrderDetailsScreen), findsNothing);
      expect(inForm(find.text('Existing orders match yours!')), findsOneWidget);
      expect(shown(tester), [11]);
    },
  );

  testWidgets(
    'an order of the book this device holds a trade of is never offered: « Order », « Create order », the form filled, « Submit » shows the other one',
    (tester) async {
      final held = TradeRecord(
        robot: RobotSlot(
          RobosatsNetwork.mainnet,
          switch (GarageKeyFingerprint.of(tradeKey)) {
            Ok(:final value) => value,
            Err(:final failure) => throw StateError('$failure'),
          },
          2,
        ),
        coordinatorAlias: 'temple',
        coordinatorOnion:
            Federation.robosats.byAlias('temple')?.mainnet.onion ??
            (throw StateError('temple')),
        orderId: 11,
        role: TradeRole.buyer,
        origin: TradeOrigin.takenHere,
        takenAt: testNow,
        confirmedAt: testNow,
        closedAt: null,
      );
      await open(
        tester,
        active: [ActiveTrade(held, const ActiveTradeTakeNeverSent())],
      );
      await tester.tap(find.text('Order'));
      await settle(tester);
      await tester.tap(find.text('Create order'));
      await settle(tester);
      expect(find.byType(CreateOrderScreen), findsOneWidget);
      await fill(tester);
      await tester.tap(inForm(find.text('Submit')));
      await settle(tester);
      expect(shown(tester), [12]);
    },
  );
}

/// Every coordinator of the federation as the reference answers anonymous reads, never a real one: `GET /api/book/` with the test's elements for the aliases it names (`BookView`, `api/views.py:776-826`, as `support/fakes.dart` writes them) and `404` with the reference's `not_found` for the others (`:797-801`), `/api/info/` and `/api/limits/` as [ScriptedMakerCoordinator] answers them, its price of a USD bitcoin 100,000 (`LimitView`, `api/views.py:1177-1197`). Every request is counted, by alias and path.
final class _Coordinators implements CoordinatorTransport {
  final Map<String, List<Map<String, Object?>>> books;
  final Map<String, ScriptedMakerCoordinator> _scripted = {};
  final List<String> requested = [];

  _Coordinators(this.books);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final alias = _aliasOf(request.url.host);
    requested.add('$alias${request.url.path}');
    if (request.url.path.startsWith('/api/book')) {
      final book = books[alias];
      return Ok(
        book == null
            ? _json(404, {
                'not_found': 'No orders found, be the first to make one',
              })
            : _json(200, book),
      );
    }
    final scripted = _scripted[alias] ??= ScriptedMakerCoordinator(
      network: RobosatsNetwork.mainnet,
      robots: const [],
      clock: () => testNow,
      alias: alias,
    )..prices[1] = 100000;
    return scripted.send(request);
  }

  static String _aliasOf(String host) {
    for (final coordinator in Federation.robosats.on(RobosatsNetwork.mainnet)) {
      if (Uri.parse(
            coordinator.origins(RobosatsNetwork.mainnet).onion ?? '',
          ).host ==
          host) {
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
