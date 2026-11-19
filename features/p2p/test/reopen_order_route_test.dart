import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/repositories/trade_record_repository.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/make_order_usecase.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/trade/renew_same_terms_dialog.dart';
import 'package:p2p/src/ui/trade/trade_record_row.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';
import 'support/make_harness.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// Opening again the last finished order made here, and renewing it (#216, #217), on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`): the real router, records, use cases, state machine and pages, by real gestures, from the Garage's « Last order #N » to the makes counted at the coordinator played by `ScriptedMakerCoordinator` (never a real one), which follows the reference's answers to a maker.
///
/// The order is made by the composition's own make use case, its bond locked and its time run out at the coordinator; its trade screen reads it expired, which closes its record, and is left: from then on the order is in no list of trades, which is what #216 is about.
const _net = RobosatsNetwork.testnet;

/// The order of the tests: 100 EUR, Revolut Instant SEPA, 2 %, the defaults.
final MakeOrderRequest _kept = MakeHarness.request();

/// The `no_screenshot` plugin behind the Garage's `PrivacyScreen`: the protection is said on, so the Garage draws.
const _privacyChannel = MethodChannel('com.flutterplaza.no_screenshot_methods');

/// The scripted maker coordinator for every robot's request and the anonymous information and limits; the book, anonymous and unknown to it, to an empty fake.
final class _Coordinators implements CoordinatorTransport {
  final ScriptedMakerCoordinator maker;
  final FakeTransport rest = FakeTransport(network: _net);

  _Coordinators(this.maker);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) {
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
  late TradeRecord first;

  _App(this.tester, this.locator, this.router, this.coordinator);

  /// Every make that reached the coordinator.
  List<CoordinatorRequest> get makes => [
    for (final request in coordinator.requests)
      if (request.url.path == '/api/make/') request,
  ];

  /// Every read of an order that reached the coordinator.
  List<CoordinatorRequest> get orderReads => [
    for (final request in coordinator.requests)
      if (request.url.path == '/api/order/' &&
          request.method == CoordinatorHttpMethod.get)
        request,
  ];

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

  /// Makes [request] with the composition's own make use case, as « Create order » does.
  Future<Result<MakeOutcome, MakeRefusal>> make(MakeOrderRequest request) =>
      wait(
        () => locator<MakeOrderUsecase>().execute(
          request,
          coordinator: coordinator.coordinator,
          network: _net,
          seen: MakePriceSeen.of(
            currency: request.currency,
            coordinatorPrice: coordinator.prices[request.currency.id] ?? 1,
          ),
        ),
      );

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
    await tester.tap(find.text('Garage'));
    await settle();
    await tester.pump(const Duration(seconds: 6));
    await settle();
  }

  /// The order numbers of the trade screens in the tree, shown or not.
  List<int> tradePages() => [
    for (final element
        in find.byType(TradeScreen, skipOffstage: false).evaluate())
      BlocProvider.of<TradeCubit>(element).state.record.orderId,
  ];

  /// The order made, its bond locked and its time run out at the coordinator, its trade screen opened as « Active trades » opens it, which reads it expired and closes its record, then left: the tab is shown again.
  static Future<_App> start(WidgetTester tester) async {
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
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    setUpP2pForTesting(
      locator,
      transport: _Coordinators(coordinator),
      torStates: () => tor.stream,
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
    final app = _App(tester, locator, router, coordinator);
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
    await tester.pumpWidget(routerHarness(router));
    tor.add(P2pTorState.ready);
    await app.settle();
    app.first = switch (await app.make(_kept)) {
      Ok(value: MakeStarted(:final record)) => record,
      final other => throw StateError('$other'),
    };
    coordinator
      ..lockMakerBond(app.first.orderId)
      ..expire(app.first.orderId);
    unawaited(
      router.pushNamed(
        P2pRouter.tradeName,
        extra: P2pTradeRouteArgs(app.first),
      ),
    );
    await app.settle(12);
    expect(find.text('The order has expired'), findsOneWidget);
    await app.back();
    expect(find.byType(TradeScreen, skipOffstage: false), findsNothing);
    // The record is closed: the order is in no list of trades any more.
    expect(await app.active(), isEmpty);
    return app;
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await tester.pump(const Duration(seconds: 61));
  }
}

Finder _lastOrder(int id) =>
    find.widgetWithText(TradeRecordRow, 'Last order #$id');
Finder get _renewOrder => find.widgetWithText(TradeButton, 'Renew Order');
Finder get _create => find.widgetWithText(TradeButton, 'Create order');

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

Map<String, Object?> _body(CoordinatorRequest request) =>
    jsonDecode(utf8.decode(request.body ?? const [])) as Map<String, Object?>;

/// The line of the terms kept, whatever the day it names.
const _keptLine =
    'with the terms kept on this device: Buy BTC for 100 EUR at a 2% premium.';

void main() {
  testWidgets(
    '« Last order #N » of the Garage, said once, opens the ended order again: read once, its kept terms, « Renew Order » renews it once; opened again, an order with the same terms said with where it stands, one tap more to renew again, « Open order » opens the new one',
    (tester) async {
      final app = await _App.start(tester);
      final id = app.first.orderId;
      await app.openGarage();
      expect(_lastOrder(id), findsOneWidget);
      // Said once in the Garage, where the reference says it: the robot panel, which shows the robot of that very order, no longer says it as plain text (functional review of #220, R4).
      expect(find.text('Last order #$id'), findsOneWidget);
      final readsBefore = app.orderReads.length;
      await _tap(tester, _lastOrder(id));
      await app.settle(12);
      // The order's screen, from the records, and the coordinator asked once what it says now.
      expect(app.tradePages(), [id]);
      expect(find.text('The order has expired'), findsOneWidget);
      expect(app.orderReads.length - readsBefore, 1);
      expect(find.textContaining(_keptLine), findsOneWidget);
      expect(find.textContaining('could not be read again'), findsNothing);
      expect(find.textContaining('same terms was made'), findsNothing);
      // « Renew Order », then « Create order »: one make, the kept request, another robot; the new trade in place of the old one.
      await _tap(tester, _renewOrder);
      await app.settle(12);
      expect(find.byType(CreateOrderScreen), findsOneWidget);
      expect(find.byType(RenewSameTermsDialog), findsNothing);
      await _tap(tester, _create);
      await tester.tap(_create, warnIfMissed: false);
      await app.settle(16);
      expect(app.makes, hasLength(2));
      expect(_body(app.makes.last), _body(app.makes.first));
      expect(app.makes.last.robot, isNot(app.makes.first.robot));
      expect(find.byType(CreateOrderScreen, skipOffstage: false), findsNothing);
      final renewed = app.tradePages().single;
      expect(renewed, isNot(id));
      // Back to the Garage: the ended order is still its last finished order.
      await app.back();
      expect(find.byType(TradeScreen, skipOffstage: false), findsNothing);
      expect(_lastOrder(id), findsOneWidget);
      await _tap(tester, _lastOrder(id));
      await app.settle(12);
      expect(app.tradePages(), [id]);
      expect(
        find.text(
          'An order with the same terms was made here after this one: order $renewed, still running here.',
        ),
        findsOneWidget,
      );
      // Renewing again asks first; « Go back » opens nothing.
      await _tap(tester, _renewOrder);
      await app.settle();
      expect(find.byType(RenewSameTermsDialog), findsOneWidget);
      expect(find.text('Renew this order?'), findsOneWidget);
      await tester.tap(find.text('Go back'));
      await app.settle();
      expect(find.byType(RenewSameTermsDialog), findsNothing);
      expect(find.byType(CreateOrderScreen), findsNothing);
      // « Renew anyway »: the renewal's page, nothing sent; left, nothing made.
      await _tap(tester, _renewOrder);
      await app.settle();
      await tester.tap(find.text('Renew anyway'));
      await app.settle(12);
      expect(find.byType(CreateOrderScreen), findsOneWidget);
      await app.back();
      expect(find.byType(CreateOrderScreen), findsNothing);
      expect(app.makes, hasLength(2));
      // « Open order N »: the new order's trade in place of the old one.
      await _tap(
        tester,
        find.widgetWithText(TradeButton, 'Open order $renewed'),
      );
      await app.settle(12);
      expect(app.tradePages(), [renewed]);
      expect(app.makes, hasLength(2));
      await app.close();
    },
  );

  for (final (name, change, line)
      in <
        (
          String,
          void Function(ScriptedMakerCoordinator coordinator, int id),
          String,
        )
      >[
        (
          'the coordinator out of reach: the order not read again',
          (c, id) => c
            ..failNext(ScriptedMakerRequest.order, ScriptedFault.unreachable)
            ..failNext(ScriptedMakerRequest.order, ScriptedFault.unreachable)
            ..failNext(ScriptedMakerRequest.order, ScriptedFault.unreachable),
          'This order could not be read again from Temple of Sats: what is shown is what this device kept when it ended, on ',
        ),
        (
          'the coordinator answering it does not know the order (404)',
          (c, id) => c.orders.remove(id),
          'Temple of Sats answered that it does not know this order: what is shown is what this device kept when it ended, on ',
        ),
        (
          'the coordinator answering the order public again (1)',
          (c, id) => c.order(id).status = 1,
          'Temple of Sats now shows this order otherwise than this device kept it when it ended, on ',
        ),
      ]) {
    testWidgets(
      'opened again, $name: the end the records hold, the line true to what the read gave, with the date and the kept terms; « Renew Order » under the text, still offered (functional review of #220, C1, R7)',
      (tester) async {
        final app = await _App.start(tester);
        final id = app.first.orderId;
        change(app.coordinator, id);
        await app.openGarage();
        await _tap(tester, _lastOrder(id));
        await app.settle(12);
        // Not « The order has expired », which the coordinator did not say now: the end the records hold, as the screen words an end of a status it did not read.
        expect(find.text('The order has expired'), findsNothing);
        expect(find.text('This trade is over for this robot.'), findsOneWidget);
        expect(find.textContaining(line), findsOneWidget);
        for (final other in [
          'could not be read again',
          'does not know this order',
          'now shows this order otherwise',
        ]) {
          if (!line.contains(other)) {
            expect(find.textContaining(other), findsNothing, reason: other);
          }
        }
        expect(find.textContaining(_keptLine), findsOneWidget);
        // « Renew Order » under « This trade is over for this robot. », as under the expiry's reason.
        expect(
          tester.getTopLeft(_renewOrder).dy,
          greaterThan(
            tester
                .getTopLeft(find.text('This trade is over for this robot.'))
                .dy,
          ),
        );
        // The renewal the records allow, on its page with the kept terms; nothing sent.
        await _tap(tester, _renewOrder);
        await app.settle(12);
        expect(find.byType(CreateOrderScreen), findsOneWidget);
        expect(
          find.text('Buy BTC for 100 EUR at a 2% premium'),
          findsOneWidget,
        );
        expect(app.makes, hasLength(1));
        await app.close();
      },
    );
  }

  testWidgets(
    'opened again, the coordinator now reads the ended order with other terms: its alert shown, and that it shows the order otherwise; the renewal\'s page still the kept terms (functional review of #220, C1)',
    (tester) async {
      final app = await _App.start(tester);
      final id = app.first.orderId;
      app.coordinator.orderChanges[id] = {'premium': '-20.00'};
      await app.openGarage();
      await _tap(tester, _lastOrder(id));
      await app.settle(12);
      expect(
        find.text('The terms of the order are not those of the order taken.'),
        findsWidgets,
      );
      expect(
        find.textContaining(
          'Temple of Sats now shows this order otherwise than this device kept it when it ended, on ',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('could not be read again'), findsNothing);
      expect(find.textContaining(_keptLine), findsOneWidget);
      await _tap(tester, _renewOrder);
      await app.settle(12);
      expect(find.text('Buy BTC for 100 EUR at a 2% premium'), findsOneWidget);
      await app.close();
    },
  );

  group(
    'a pending make confirmed while the renewal\'s page is open (#217, security review of #185, R3)',
    () {
      /// A make of [request] whose answer was lost: made at the coordinator, pending in the records.
      Future<void> lostMake(_App app, MakeOrderRequest request) async {
        app.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.answerLost,
        );
        final made = await app.make(request);
        expect(made, isA<Ok<MakeOutcome, MakeRefusal>>());
        expect(switch (made) {
          Ok(:final value) => value,
          Err() => null,
        }, isA<MakePending>());
      }

      testWidgets(
        'one unrelated to the renewal: the page stays open, the order to renew stays behind it',
        (tester) async {
          final app = await _App.start(tester);
          final id = app.first.orderId;
          await lostMake(app, MakeHarness.request(amount: 250, premium: 4));
          unawaited(
            app.router.pushNamed(
              P2pRouter.tradeName,
              extra: P2pTradeRouteArgs(app.first),
            ),
          );
          await app.settle(12);
          await _tap(tester, _renewOrder);
          await app.settle(20);
          // The resolution confirmed the other make (its robot read, its order read).
          expect(await app.active(), hasLength(1));
          expect(find.byType(CreateOrderScreen), findsOneWidget);
          expect(app.tradePages(), [id]);
          expect(app.makes, hasLength(2));
          // Left, the order renewed is shown again with its button.
          await app.back();
          expect(app.tradePages(), [id]);
          expect(_renewOrder, findsOneWidget);
          await app.close();
        },
      );

      testWidgets(
        'an earlier try of this very renewal: the page closes with it, its trade in place of the order renewed',
        (tester) async {
          final app = await _App.start(tester);
          final id = app.first.orderId;
          await lostMake(app, _kept);
          unawaited(
            app.router.pushNamed(
              P2pRouter.tradeName,
              extra: P2pTradeRouteArgs(app.first),
            ),
          );
          await app.settle(12);
          await _tap(tester, _renewOrder);
          await app.settle(20);
          expect(
            find.byType(CreateOrderScreen, skipOffstage: false),
            findsNothing,
          );
          final shown = app.tradePages();
          expect(shown, hasLength(1));
          expect(shown.single, isNot(id));
          expect(app.makes, hasLength(2));
          await app.close();
        },
      );
    },
  );
}
