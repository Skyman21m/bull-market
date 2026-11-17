import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/testing.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';

/// What opens the create form since the maker's panels exist (#182, design note § 2.1, « Order of the pull requests »): « Create » of the tab, enabled where the feature holds robots and the network has no active trade nor pending make, and the route `create`, which needs what the tab hands it; « Create order » of « Active trades » is in `pending_makes_test.dart`.
void main() {
  Future<GoRouter> open(
    WidgetTester tester, {
    required bool withGarage,
  }) async {
    usePhoneScreen(tester);
    FakeSecureStoragePlatform().install();
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    setUpP2pForTesting(
      locator,
      transport: FakeTransport(network: RobosatsNetwork.mainnet),
      torStates: () => tor.stream,
      clock: () => DateTime.utc(2026, 11, 17),
      garageKeys: withGarage
          ? Secrets(scratchDirectory: () async => '.').garageKeys()
          : null,
    );
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
    return router;
  }

  testWidgets('« Create » opens the form, and going back leaves it', (
    tester,
  ) async {
    await open(tester, withGarage: true);
    expect(find.text('Create'), findsOneWidget);
    await tester.tap(find.text('Create'));
    await settle(tester);
    expect(find.byType(CreateOrderScreen), findsOneWidget);
    // The top bar's back.
    await tester.tap(
      find
          .descendant(
            of: find.byType(CreateOrderScreen),
            matching: find.byType(IconButton),
          )
          .first,
    );
    await settle(tester);
    expect(find.byType(CreateOrderScreen), findsNothing);
    expect(find.text('Create'), findsOneWidget);
  });

  testWidgets(
    'without the vault\'s handle the feature holds no robot: « Create » stays disabled',
    (tester) async {
      await open(tester, withGarage: false);
      await tester.tap(find.text('Create'), warnIfMissed: false);
      await settle(tester);
      expect(find.byType(CreateOrderScreen), findsNothing);
    },
  );

  testWidgets(
    'the route `create` without what the tab hands it sends back to the tab, as the tab\'s other pages',
    (tester) async {
      final router = await open(tester, withGarage: true);
      for (final path in ['order', 'trade', 'create']) {
        router.go('${P2pFeature.path}/$path');
        await settle(tester);
        expect(find.byType(CreateOrderScreen), findsNothing, reason: path);
      }
      final locator = GetIt.asNewInstance();
      addTearDown(locator.reset);
      final route = const P2pFeature().route(
        locator,
        network: (_) => RobosatsNetwork.mainnet,
      );
      expect(
        [
          for (final child in route.routes)
            if (child is GoRoute) child.path,
        ],
        ['order', 'trade', 'create'],
      );
    },
  );
}
