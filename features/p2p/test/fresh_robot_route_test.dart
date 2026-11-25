import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/garage_opening.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/repositories/trade_record_repository.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/make_order_usecase.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/garage_cubit.dart';
import 'package:p2p/src/presentation/garage_state.dart';
import 'package:p2p/src/ui/garage/garage_profile.dart';
import 'package:p2p/src/ui/trade/trade_record_row.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';
import 'support/make_harness.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// The Garage moves to a fresh robot after a trade that served, as the reference's (#251, design note `docs/design/phase-3-fresh-robot.md` § 4.1), on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`): the real router, records, use cases and pages, by real gestures, the orders made by the composition's own make use case at the coordinator played by `ScriptedMakerCoordinator` (never a real one), in English and in French.
const _net = RobosatsNetwork.testnet;

/// The `no_screenshot` plugin behind the Garage's `PrivacyScreen`: the protection is said on, so the Garage draws.
const _privacyChannel = MethodChannel('com.flutterplaza.no_screenshot_methods');

/// The scripted maker coordinator for every robot's request and the anonymous information and limits; the book, to an empty fake.
final class _Coordinators implements CoordinatorTransport {
  final ScriptedMakerCoordinator maker;
  final FakeTransport rest = FakeTransport(network: _net);

  /// Every request sent, in order.
  final List<CoordinatorRequest> sent = [];

  _Coordinators(this.maker);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    sent.add(request);
    final path = request.url.path;
    if (request.robot != null ||
        path == '/api/info/' ||
        path == '/api/limits/' ||
        path == '/api/make/') {
      return maker.send(request);
    }
    return rest.send(request);
  }
}

final class _App {
  final WidgetTester tester;
  final GetIt locator;
  final GoRouter router;
  final ScriptedMakerCoordinator coordinator;
  final _Coordinators transport;
  final P2pLocalizations l10n;

  _App(
    this.tester,
    this.locator,
    this.router,
    this.coordinator,
    this.transport,
    this.l10n,
  );

  Future<void> settle([int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Runs [run] outside the fake clock's frames, pumping until it ends.
  Future<T> wait<T>(Future<T> Function() run) async {
    late T value;
    Object? error;
    var done = false;
    unawaited(
      run().then(
        (v) {
          value = v;
          done = true;
        },
        onError: (Object e) {
          error = e;
          done = true;
        },
      ),
    );
    for (var i = 0; i < 400 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    if (error case final error?) throw error;
    if (!done) throw StateError('never done');
    return value;
  }

  /// An order made as « Create order » makes it, of [amount] EUR.
  Future<TradeRecord> make({double amount = 100}) async {
    final request = MakeHarness.request(amount: amount);
    return switch (await wait(
      () => locator<MakeOrderUsecase>().execute(
        request,
        coordinator: coordinator.coordinator,
        network: _net,
        seen: MakePriceSeen.of(
          currency: request.currency,
          coordinatorPrice: coordinator.prices[request.currency.id] ?? 1,
        ),
      ),
    )) {
      Ok(value: MakeStarted(:final record)) => record,
      final other => throw StateError('$other'),
    };
  }

  /// The active trades of the records.
  Future<List<TradeRecord>> active() async => switch (await wait(
    () => locator<TradeRecordRepository>().watchActiveTrades(_net).first,
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  /// The system's back, as Android's back gesture.
  Future<void> back() async {
    await tester.binding.handlePopRoute();
    await settle(12);
  }

  /// « Garage » of the tab, the vault read.
  Future<void> openGarage() async {
    await tester.tap(find.text(l10n.p2pNavGarage));
    await settle();
    await tester.pump(const Duration(seconds: 6));
    await settle();
  }

  /// « Offers », then « Garage »: the Garage built again.
  Future<void> reopenGarage() async {
    await tester.tap(find.text(l10n.p2pNavOffers));
    await settle();
    await openGarage();
  }

  Future<void> previous() async {
    await tester.tap(find.byTooltip(l10n.p2pGaragePreviousAccount));
    await settle(12);
  }

  /// The number of the robot the Garage shows, shown or under the pages above the tab.
  int shown() => switch (BlocProvider.of<GarageCubit>(
    tester.element(find.byType(GarageProfile, skipOffstage: false)),
  ).state) {
    GarageWithKey(:final robot) => robot.index,
    final other => throw StateError('$other'),
  };

  /// The page of [made] opened as from the records, kept until it read what the coordinator now says, then left.
  Future<void> openAndLeave(TradeRecord made) async {
    unawaited(
      router.pushNamed(P2pRouter.tradeName, extra: P2pTradeRouteArgs(made)),
    );
    await settle(12);
    await back();
  }

  /// [made]'s bond locked, its page opened until it read it public.
  Future<void> lock(TradeRecord made) async {
    coordinator.lockMakerBond(made.orderId);
    await openAndLeave(made);
  }

  /// [made], public, taken by another robot and ended at 14 at the coordinator, then read by its page, which closes its record.
  Future<void> succeed(TradeRecord made) async {
    coordinator.take(made.orderId, TradeHarness.robotsOf(_net)[5]);
    coordinator.order(made.orderId).status = 14;
    await openAndLeave(made);
    expect(
      (await active()).map((record) => record.orderId),
      isNot(contains(made.orderId)),
    );
  }

  /// [made] ended at the coordinator by [status] (5 or 4), then read by its page.
  Future<void> endBy(TradeRecord made, int status) async {
    if (status == 5) {
      coordinator.expire(made.orderId);
    } else {
      coordinator.order(made.orderId).status = status;
    }
    await openAndLeave(made);
    expect(
      (await active()).map((record) => record.orderId),
      isNot(contains(made.orderId)),
    );
  }

  static Future<_App> start(WidgetTester tester, Locale locale) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 2600 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_privacyChannel, (call) async => true);
    addTearDown(
      () => messenger.setMockMethodCallHandler(_privacyChannel, null),
    );
    final clock = DateTime.utc(2026, 11, 14, 9);
    final coordinator = ScriptedMakerCoordinator(
      network: _net,
      robots: TradeHarness.robotsOf(_net),
      clock: () => clock,
    );
    final transport = _Coordinators(coordinator);
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    setUpP2pForTesting(
      locator,
      transport: transport,
      // Tor heard ready by each new listener: a robot panel reads its coordinator.
      torStates: () => Stream.value(P2pTorState.ready),
      clock: () => clock,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      wallet: FakeP2pWalletPort(Ok(Sats.fromInt(50000)))
        ..rate = P2pWalletRateRead(91711.15),
      robotKeys: HarnessKeys(),
      bolt11Decoder: coordinator.decoder,
    );
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [const P2pFeature().route(locator, network: (_) => _net)],
    );
    final app = _App(
      tester,
      locator,
      router,
      coordinator,
      transport,
      lookupP2pLocalizations(locale),
    );
    // The Garage Key of the tests (fake bytes), recorded as drawn here.
    final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    final keyed = await app.wait(
      () async => (
        await locator<GarageKeyRepository>().import(_net, tradeKey),
        await locator<RobotBindingRepository>().recordGeneratedKey(
          _net,
          fingerprint,
        ),
      ),
    );
    expect(keyed.$1, isA<Ok<void, Failure>>());
    expect(keyed.$2, isA<Ok<void, Failure>>());
    await tester.pumpWidget(routerHarness(router, locale: locale));
    await app.settle();
    return app;
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await tester.pump(const Duration(seconds: 61));
  }
}

void main() {
  for (final locale in const [Locale('en'), Locale('fr')]) {
    final language = locale.languageCode;

    group('a fresh robot after a trade, in $language (#251)', () {
      Finder lastOrder(_App app, int id) => find.widgetWithText(
        TradeRecordRow,
        app.l10n.p2pRobotLastOrder('$id'),
      );

      testWidgets(
        'opened after a successful trade: the next robot, the « Last order #N » line still there; « Previous account » shows the robot of the trade with the reference\'s sentence, kept when the Garage is left and opened again; an expired order\'s robot has none; another trade ending at 14 applies the rule again, as a new run of the app does; nothing sent for the move',
        (tester) async {
          final app = await _App.start(tester, locale);
          final l10n = app.l10n;
          final expired = await app.make();
          await app.lock(expired);
          await app.endBy(expired, 5);
          final traded = await app.make(amount: 120);
          await app.lock(traded);
          await app.succeed(traded);
          final tradeRobot = traded.robot.accountIndex;
          expect(tradeRobot, greaterThan(expired.robot.accountIndex));

          final before = app.transport.sent.length;
          await app.openGarage();
          // The fresh robot: the one the next trade would reserve, above the robot of the trade, no coordinator knows it.
          expect(app.shown(), tradeRobot + 1);
          expect(find.text('Robot #${tradeRobot + 1}'), findsOneWidget);
          expect(lastOrder(app, traded.orderId), findsOneWidget);
          expect(find.text(l10n.p2pRobotSelectHost), findsOneWidget);
          expect(find.text(l10n.p2pRobotUsedInTrade), findsNothing);
          // The move sent nothing: no request names the fresh robot.
          final fresh = TradeHarness.robotsOf(_net)[tradeRobot + 1];
          expect(
            app.transport.sent
                .skip(before)
                .where((request) => request.robot == fresh.sessionKey),
            isEmpty,
          );

          // « Previous account »: the robot of the trade, and the reference's sentence.
          await app.previous();
          expect(app.shown(), tradeRobot);
          await app.settle(12);
          expect(find.text(l10n.p2pRobotUsedInTrade), findsOneWidget);
          // Left and opened again: still there.
          await app.reopenGarage();
          expect(app.shown(), tradeRobot);
          // The robot of the expired order: its last order held here, not served, no sentence.
          await app.previous();
          expect(app.shown(), expired.robot.accountIndex);
          await app.settle(12);
          expect(find.text(l10n.p2pRobotUsedInTrade), findsNothing);
          // Back on the robot of the trade.
          await app.tester.tap(find.byTooltip(l10n.p2pGarageNextAccount));
          await app.settle(12);
          expect(app.shown(), tradeRobot);

          // Another trade of the key ends at 14 while the Garage is under its page: the rule again, the fresh robot.
          final second = await app.make(amount: 130);
          await app.lock(second);
          // Its bond locked: the Garage shows its robot.
          expect(app.shown(), second.robot.accountIndex);
          await app.succeed(second);
          expect(app.shown(), second.robot.accountIndex + 1);

          // Left by hand again, then a new run of the app (where it was left forgotten): the rule.
          await app.previous();
          expect(app.shown(), second.robot.accountIndex);
          app.locator.resetLazySingleton<GarageNavigation>();
          await app.reopenGarage();
          expect(app.shown(), second.robot.accountIndex + 1);
          await app.close();
        },
      );

      testWidgets(
        'an order that expires while the Garage is shown keeps its robot, without the sentence; one cancelled moves the Garage, its robot with the sentence',
        (tester) async {
          final app = await _App.start(tester, locale);
          final l10n = app.l10n;
          final made = await app.make();
          await app.openGarage();
          await app.lock(made);
          expect(app.shown(), made.robot.accountIndex);
          await app.endBy(made, 5);
          expect(app.shown(), made.robot.accountIndex);
          expect(lastOrder(app, made.orderId), findsOneWidget);
          await app.settle(12);
          expect(find.text(l10n.p2pRobotUsedInTrade), findsNothing);

          final cancelled = await app.make(amount: 120);
          await app.lock(cancelled);
          expect(app.shown(), cancelled.robot.accountIndex);
          await app.endBy(cancelled, 4);
          expect(app.shown(), cancelled.robot.accountIndex + 1);
          await app.previous();
          expect(app.shown(), cancelled.robot.accountIndex);
          await app.settle(12);
          expect(find.text(l10n.p2pRobotUsedInTrade), findsOneWidget);
          expect(find.byType(TradeScreen, skipOffstage: false), findsNothing);
          await app.close();
        },
      );

      testWidgets(
        'step 0: an order ended while the app did not read it, the Garage reads it once when it opens on its robot, then applies its rule; nothing more read when opened again',
        (tester) async {
          final app = await _App.start(tester, locale);
          int orderReads() => app.transport.sent
              .where(
                (request) =>
                    request.url.path == '/api/order/' &&
                    request.method == CoordinatorHttpMethod.get,
              )
              .length;
          for (final (status, moves) in [(5, false), (4, true)]) {
            final made = await app.make(amount: 100.0 + status);
            await app.lock(made);
            // Ended at the coordinator, the app reading nothing.
            if (status == 5) {
              app.coordinator.expire(made.orderId);
            } else {
              app.coordinator.order(made.orderId).status = status;
            }
            expect(
              (await app.active()).map((record) => record.orderId),
              contains(made.orderId),
            );
            final before = orderReads();
            await app.reopenGarage();
            await app.settle(20);
            // One read of that order, by its robot.
            expect(orderReads() - before, 1, reason: '$status');
            expect(
              (await app.active()).map((record) => record.orderId),
              isNot(contains(made.orderId)),
              reason: '$status',
            );
            expect(
              app.shown(),
              moves ? made.robot.accountIndex + 1 : made.robot.accountIndex,
              reason: '$status',
            );
            final after = orderReads();
            await app.reopenGarage();
            await app.settle(20);
            expect(orderReads(), after, reason: '$status');
          }
          await app.close();
        },
      );

      testWidgets(
        'step 0 not for a robot whose panel reads an active order: no read of its order when the Garage opens on it (security review of PR 274, R3)',
        (tester) async {
          final app = await _App.start(tester, locale);
          int orderReads() => app.transport.sent
              .where(
                (request) =>
                    request.url.path == '/api/order/' &&
                    request.method == CoordinatorHttpMethod.get,
              )
              .length;
          final made = await app.make();
          await app.lock(made);
          // Still public at the coordinator: its robot has an active order.
          final before = orderReads();
          final robotReads = app.transport.sent
              .where((request) => request.url.path == '/api/robot/')
              .length;
          await app.reopenGarage();
          await app.settle(20);
          expect(app.shown(), made.robot.accountIndex);
          // The panel read the robot, which has an active order: nothing more.
          expect(
            app.transport.sent
                .where((request) => request.url.path == '/api/robot/')
                .length,
            greaterThan(robotReads),
          );
          expect(
            find.text(app.l10n.p2pRobotActiveOrder('${made.orderId}')),
            findsOneWidget,
          );
          expect(orderReads(), before);
          expect(
            (await app.active()).map((record) => record.orderId),
            contains(made.orderId),
          );
          await app.close();
        },
      );
    });
  }
}
