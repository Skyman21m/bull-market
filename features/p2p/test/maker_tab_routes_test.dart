import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/active_trades_cubit.dart';
import 'package:p2p/src/presentation/pending_makes_cubit.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/order_details_screen.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/testing.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport, bookOrder;
import 'support/harness.dart';
import 'support/trade_harness.dart' show tradeKey;

/// What the tab of the real composition does with an order made here and a pending make (#182, functional review C3): the book opens an order this device made as its trade, never « Take Order »; « Order » is the middle entry while the network has only a pending make; the create form resolves the network's pending makes when it opens. The records' lists are played by the test (the cubits' listers replaced in the composition), everything else is the composition's.
void main() {
  final slot = RobotSlot(RobosatsNetwork.mainnet, switch (GarageKeyFingerprint.of(
    tradeKey,
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  }, 3);
  final onion =
      Federation.robosats.byAlias('temple')?.mainnet.onion ??
      (throw StateError('temple'));
  final made = TradeRecord(
    robot: slot,
    coordinatorAlias: 'temple',
    coordinatorOnion: onion,
    orderId: 48213,
    role: TradeRole.buyer,
    origin: TradeOrigin.madeHere,
    takenAt: DateTime.utc(2026, 11, 17),
    confirmedAt: DateTime.utc(2026, 11, 17),
    closedAt: null,
  );
  final pendingMake = PendingMake(
    robot: slot,
    coordinatorAlias: 'temple',
    coordinatorOnion: onion,
    role: TradeRole.buyer,
    writtenAt: DateTime.utc(2026, 11, 17),
    closedAt: null,
  );

  /// The tab over the real composition, the active trades [active] and the pending makes [pending] as the records would list them; the pending makes resolved go to [resolved].
  Future<(GetIt, GoRouter)> open(
    WidgetTester tester, {
    List<ActiveTrade> active = const [],
    List<ActivePendingMake> pending = const [],
    List<PendingMake>? resolved,
  }) async {
    usePhoneScreen(tester);
    FakeSecureStoragePlatform().install();
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    setUpP2pForTesting(
      locator,
      transport: FakeTransport(
        books: {
          'temple': [bookOrder(id: 48213)],
        },
      ),
      torStates: () => tor.stream,
      clock: () => DateTime.utc(2026, 11, 17),
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
    );
    locator
      ..unregister<ActiveTradesCubit>()
      ..registerFactoryParam<ActiveTradesCubit, RobosatsNetwork, void>(
        (network, _) => ActiveTradesCubit(
          network,
          (network) => Stream.value(Ok(List.of(active))),
        ),
      )
      ..unregister<PendingMakesCubit>()
      ..registerFactoryParam<PendingMakesCubit, RobosatsNetwork, void>(
        (network, _) => PendingMakesCubit(
          network,
          (network) => Stream.value(Ok(List.of(pending))),
          (make) async {
            resolved?.add(make);
            return MakePending(make, MakePendingReason.unread);
          },
          (make) async => const Ok(true),
        ),
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
    await settle(tester);
    return (locator, router);
  }

  testWidgets(
    'an order of the book this device made opens its trade, never « Take Order » (§ 3.7)',
    (tester) async {
      await open(
        tester,
        active: [ActiveTrade(made, const ActiveTradeTakeNeverSent())],
      );
      await tester.tap(find.text('100 EUR', findRichText: true).first);
      await settle(tester);
      expect(find.byType(TradeScreen), findsOneWidget);
      expect(find.byType(OrderDetailsScreen), findsNothing);
      expect(find.text('Take Order'), findsNothing);
    },
  );

  testWidgets('another order of the book opens its details', (tester) async {
    await open(tester);
    await tester.tap(find.text('100 EUR', findRichText: true).first);
    await settle(tester);
    expect(find.byType(OrderDetailsScreen), findsOneWidget);
    expect(find.byType(TradeScreen), findsNothing);
  });

  testWidgets(
    'a pending make alone: the middle entry is « Order », which opens the list with « Create order »',
    (tester) async {
      await open(
        tester,
        pending: [ActivePendingMake(pendingMake, neverSent: false)],
      );
      expect(find.text('Order'), findsOneWidget);
      expect(find.text('Create'), findsNothing);
      await tester.tap(find.text('Order'));
      await settle(tester);
      expect(find.text('Create order'), findsOneWidget);
      expect(find.text('Creating your order…'), findsOneWidget);
    },
  );

  testWidgets(
    'the create form resolves the network\'s pending makes when it opens, with no press',
    (tester) async {
      final resolved = <PendingMake>[];
      final (locator, _) = await open(
        tester,
        pending: [ActivePendingMake(pendingMake, neverSent: false)],
        resolved: resolved,
      );
      // The tab resolves nothing by itself.
      expect(resolved, isEmpty);
      await tester.pumpWidget(
        routerHarness(
          GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => P2pRouter.createPage(
                  locator,
                  P2pCreateRouteArgs(
                    RobosatsNetwork.mainnet,
                    currency:
                        RobosatsCurrency.fromCode('EUR') ??
                        (throw StateError('EUR')),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(CreateOrderScreen), findsOneWidget);
      expect(resolved, [pendingMake]);
    },
  );

  testWidgets(
    'while the records are being read, « Create » does not open the form',
    (tester) async {
      usePhoneScreen(tester);
      FakeSecureStoragePlatform().install();
      final locator = GetIt.asNewInstance();
      addTearDown(locator.reset);
      final tor = StreamController<P2pTorState>.broadcast();
      addTearDown(tor.close);
      setUpP2pForTesting(
        locator,
        transport: FakeTransport(),
        torStates: () => tor.stream,
        clock: () => DateTime.utc(2026, 11, 17),
        garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      );
      final never = StreamController<Result<List<ActiveTrade>, P2pFailure>>();
      addTearDown(never.close);
      locator
        ..unregister<ActiveTradesCubit>()
        ..registerFactoryParam<ActiveTradesCubit, RobosatsNetwork, void>(
          (network, _) => ActiveTradesCubit(network, (_) => never.stream),
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
      await tester.tap(find.text('Create'), warnIfMissed: false);
      await settle(tester);
      expect(find.byType(CreateOrderScreen), findsNothing);
    },
  );
}
