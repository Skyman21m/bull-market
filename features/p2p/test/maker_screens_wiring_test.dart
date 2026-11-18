import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/payout_rate_cubit.dart';
import 'package:p2p/src/presentation/pending_makes_cubit.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/trade/active_trades_sheet.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/testing.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';
import 'support/trade_harness.dart' show tradeKey;

/// The screens of #182 built by the real composition (`setUpP2pForTesting`, the feature's own setup over fakes), with and without the wallet's port, with and without the Garage: the route `create` opened from the tab, « Active trades » over the composition's pending makes, and the trade page of an order made here, each without an exception. A screen that throws on opening on the owner's phone is what this test closes.
void main() {
  Future<(GetIt, GoRouter)> compose(
    WidgetTester tester, {
    required bool garage,
    required bool wallet,
  }) async {
    usePhoneScreen(tester);
    if (garage) FakeSecureStoragePlatform().install();
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    setUpP2pForTesting(
      locator,
      transport: FakeTransport(network: RobosatsNetwork.mainnet),
      torStates: () => tor.stream,
      clock: () => DateTime.utc(2026, 11, 17),
      garageKeys: garage
          ? Secrets(scratchDirectory: () async => '.').garageKeys()
          : null,
      wallet: wallet ? FakeP2pWalletPort(Ok(Sats.fromInt(50000))) : null,
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
    return (locator, router);
  }

  final record = TradeRecord(
    robot: RobotSlot(RobosatsNetwork.mainnet, switch (GarageKeyFingerprint.of(
      tradeKey,
    )) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    }, 0),
    coordinatorAlias: 'temple',
    coordinatorOnion:
        Federation.robosats.byAlias('temple')?.mainnet.onion ??
        (throw StateError('temple')),
    orderId: 42,
    role: TradeRole.buyer,
    origin: TradeOrigin.madeHere,
    takenAt: DateTime.utc(2026, 11, 17),
    confirmedAt: DateTime.utc(2026, 11, 17),
    closedAt: null,
  );

  for (final wallet in [false, true]) {
    testWidgets(
      'with the Garage, ${wallet ? 'with' : 'without'} the wallet\'s port: « Create » opens the form, « Active trades » and the trade page of an order made here build',
      (tester) async {
        final (locator, router) = await compose(
          tester,
          garage: true,
          wallet: wallet,
        );
        expect(locator.isRegistered<PendingMakesCubit>(), isTrue);
        expect(locator.isRegistered<PayoutRateCubit>(), isTrue);
        // One memory for every page of a trade, until the app stops (security review of #182, C2).
        expect(
          identical(locator<PayoutRateMemory>(), locator<PayoutRateMemory>()),
          isTrue,
        );
        await tester.tap(find.text('Create'));
        await settle(tester);
        expect(find.byType(CreateOrderScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        router.pop();
        await settle(tester);
        await settle(tester);

        // « Active trades » over the composition's pending makes.
        final pending = locator<PendingMakesCubit>(
          param1: RobosatsNetwork.mainnet,
        )..start();
        addTearDown(pending.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: testTheme,
            localizationsDelegates: P2pLocalizations.localizationsDelegates,
            supportedLocales: P2pLocalizations.supportedLocales,
            home: Scaffold(
              body: ActiveTradesSheet(
                active: const [],
                onOpen: (_) {},
                onCreate: () {},
                pending: pending,
              ),
            ),
          ),
        );
        await settle(tester);
        expect(find.text('Create order'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // The trade page of an order made here: its cubits as the route builds them, the rule's only with the wallet's port.
        await tester.pumpWidget(
          MaterialApp(
            theme: testTheme,
            localizationsDelegates: P2pLocalizations.localizationsDelegates,
            supportedLocales: P2pLocalizations.supportedLocales,
            home: Scaffold(
              body: P2pRouter.tradePage(locator, P2pTradeRouteArgs(record)),
            ),
          ),
        );
        await settle(tester);
        expect(find.byType(TradeScreen), findsOneWidget);
        expect(
          tester.widget<TradeScreen>(find.byType(TradeScreen)).checksPayoutRate,
          wallet,
        );
        expect(tester.takeException(), isNull);
        // Closed with its page.
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
      },
    );
  }

  testWidgets(
    'without the Garage: no pending makes, « Create » disabled, nothing to build',
    (tester) async {
      final (locator, _) = await compose(tester, garage: false, wallet: false);
      expect(locator.isRegistered<PendingMakesCubit>(), isFalse);
      await tester.tap(find.text('Create'), warnIfMissed: false);
      await settle(tester);
      expect(find.byType(CreateOrderScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
