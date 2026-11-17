import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';

/// The create form is built (#181) but no one can reach it yet: « Create » of the tab stays disabled until the maker's panels exist (#182, design note § 2.1), and no path of the tab opens it.
void main() {
  testWidgets(
    '« Create » is disabled, and no address of the tab opens the form',
    (tester) async {
      usePhoneScreen(tester);
      final locator = GetIt.asNewInstance();
      addTearDown(locator.reset);
      final tor = StreamController<P2pTorState>.broadcast();
      addTearDown(tor.close);
      setUpP2pForTesting(
        locator,
        transport: FakeTransport(network: RobosatsNetwork.mainnet),
        torStates: () => tor.stream,
        clock: () => DateTime.utc(2026, 11, 17),
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
      expect(find.text('Create'), findsOneWidget);
      await tester.tap(find.text('Create'), warnIfMissed: false);
      await settle(tester);
      expect(find.byType(CreateOrderScreen), findsNothing);
      // The tab's own pages, reached without what they need, send back to it.
      for (final path in ['order', 'trade']) {
        router.go('${P2pFeature.path}/$path');
        await settle(tester);
        expect(find.byType(CreateOrderScreen), findsNothing, reason: path);
      }
      // And the tab has no route of its own for the form.
      final route = const P2pFeature().route(
        locator,
        network: (_) => RobosatsNetwork.mainnet,
      );
      expect(
        [
          for (final child in route.routes)
            if (child is GoRoute) child.path,
        ],
        ['order', 'trade'],
      );
    },
  );
}
