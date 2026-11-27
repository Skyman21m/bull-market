import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/repositories/trade_record_repository.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/make_order_usecase.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/garage_cubit.dart';
import 'package:p2p/src/presentation/garage_state.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/garage/garage_profile.dart';
import 'package:p2p/src/ui/trade/renew_check_dialog.dart';
import 'package:p2p/src/ui/trade/trade_record_row.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart'
    show GarageKeyMaterial, GarageKeySlot, GarageKeys, Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';
import 'support/lean_confirmation.dart' show loadAppFont;
import 'support/make_harness.dart';
import 'support/signed_bodies.dart';
import 'support/trade_harness.dart'
    show HarnessKeys, TradeHarness, otherTradeKey, tradeKey;

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

  /// When set, every read of an order waits for it before it reaches the coordinator: a slow coordinator.
  Future<void>? holdReads;

  /// Every request sent, to any coordinator, anonymous or of a robot, in order.
  final List<CoordinatorRequest> sent = [];

  _Coordinators(this.maker);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    sent.add(request);
    final path = request.url.path;
    if (holdReads case final hold?
        when path == '/api/order/' &&
            request.method == CoordinatorHttpMethod.get) {
      await hold;
    }
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
  late TradeRecord first;

  _App(
    this.tester,
    this.locator,
    this.router,
    this.coordinator,
    this.transport,
  );

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
    // Up to 20 s of the fake clock: two empty slots of the vault settle in about 9 s (#81 stores a second key at the start).
    for (var i = 0; i < 1000 && !done; i++) {
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
  ///
  /// With [torKnown], each new listener of Tor hears at once that it is ready, as the embedded Tor tells its current state (`WatchP2pTorStateUsecase`), so that a robot panel shown later reads its coordinator; otherwise only the listeners there when Tor became ready hear it.
  static Future<_App> start(
    WidgetTester tester, {
    bool torKnown = false,
  }) async {
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
    final vault = Secrets(scratchDirectory: () async => '.').garageKeys();
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    setUpP2pForTesting(
      locator,
      transport: transport,
      torStates: torKnown
          ? () => Stream.multi((listener) {
              listener.add(P2pTorState.ready);
              listener.addStream(tor.stream).ignore();
            })
          : () => tor.stream,
      clock: () => clock,
      garageKeys: vault,
      derivedGarageKeys: _TwoKeys(vault),
      wallet: FakeP2pWalletPort(Ok(Sats.fromInt(50000)))
        ..rate = P2pWalletRateRead(91711.15),
      robotKeys: HarnessKeys(),
      bolt11Decoder: coordinator.decoder,
    );
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [const P2pFeature().route(locator, network: (_) => _net)],
    );
    final app = _App(tester, locator, router, coordinator, transport);
    // The Garage Key of the tests (fake bytes), recorded as drawn here.
    final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    final keyed = await app.wait(
      () async => (
        await locator<GarageKeyRepository>().import(_net, tradeKey),
        await vault.import(
          slot: GarageKeySlot.mainnet,
          bytes: otherTradeKey.revealBytes(),
        ),
        await locator<RobotBindingRepository>().recordGeneratedKey(
          _net,
          fingerprint,
        ),
      ),
    );
    expect(keyed.$1, isA<Ok<void, Failure>>());
    expect(keyed.$2, isA<Ok<Object?, Failure>>());
    expect(keyed.$3, isA<Ok<void, Failure>>());
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
    jsonDecode(unsignedBodyOf(request.body)) as Map<String, Object?>;

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
      expect(find.byType(RenewCheckDialog), findsNothing);
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
      expect(find.byType(RenewCheckDialog), findsOneWidget);
      expect(find.text('Renew this order?'), findsOneWidget);
      await tester.tap(find.text('Go back'));
      await app.settle();
      expect(find.byType(RenewCheckDialog), findsNothing);
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

  /// « Renew Order », then « Renew this order? » with [reason] and « Renew anyway »: the renewal's page with the kept terms; nothing sent.
  Future<void> renewThroughDialog(
    WidgetTester tester,
    _App app,
    String reason,
  ) async {
    await _tap(tester, _renewOrder);
    await app.settle();
    expect(find.byType(RenewCheckDialog), findsOneWidget);
    expect(find.textContaining(reason), findsOneWidget);
    expect(find.byType(CreateOrderScreen), findsNothing);
    await tester.tap(find.text('Renew anyway'));
    await app.settle(12);
    expect(find.byType(CreateOrderScreen), findsOneWidget);
    expect(find.text('Buy BTC for 100 EUR at a 2% premium'), findsOneWidget);
    expect(app.makes, hasLength(1));
  }

  for (final (name, change, line, reason)
      in <
        (
          String,
          void Function(ScriptedMakerCoordinator coordinator, int id),
          String,
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
          'The end of this order was not confirmed by Temple of Sats.',
        ),
        (
          'the coordinator answering it does not know the order (404)',
          (c, id) => c.orders.remove(id),
          'Temple of Sats answered that it does not know this order: what is shown is what this device kept when it ended, on ',
          'The end of this order was not confirmed by Temple of Sats.',
        ),
        (
          'the coordinator answering the order cancelled (1043)',
          (c, id) => c.order(id).status = 4,
          'Temple of Sats now shows this order otherwise than this device kept it when it ended, on ',
          'Temple of Sats shows this order otherwise than this device kept it.',
        ),
      ]) {
    testWidgets(
      'opened again, $name: the end the records hold, the line true to what the read gave, with the date and the kept terms; « Renew Order » under the text, through « Renew this order? » (functional review of #220, C1, R7; security review of #220, C1)',
      (tester) async {
        final app = await _App.start(tester);
        final id = app.first.orderId;
        change(app.coordinator, id);
        await app.openGarage();
        await _tap(tester, _lastOrder(id));
        await app.settle(12);
        // Not « The order has expired », which the coordinator did not say now: the end the records hold, said as kept here when it was not confirmed, « over » for another end the coordinator showed (security review of #220, N4).
        expect(find.text('The order has expired'), findsNothing);
        final endText = line.contains('otherwise')
            ? 'This trade is over for this robot.'
            : 'This device kept this order as ended on ';
        expect(find.textContaining(endText), findsOneWidget);
        if (!line.contains('otherwise')) {
          expect(find.textContaining('over for this robot'), findsNothing);
        }
        expect(find.textContaining(line), findsOneWidget);
        for (final other in [
          'could not be read again',
          'does not know this order',
          'now shows this order otherwise',
          'still running',
        ]) {
          if (!line.contains(other)) {
            expect(find.textContaining(other), findsNothing, reason: other);
          }
        }
        expect(find.textContaining(_keptLine), findsOneWidget);
        // « Renew Order » under the message, as under the expiry's reason.
        expect(
          tester.getTopLeft(_renewOrder).dy,
          greaterThan(tester.getTopLeft(find.textContaining(endText)).dy),
        );
        await renewThroughDialog(tester, app, reason);
        await app.close();
      },
    );
  }

  for (final (name, change)
      in <(String, void Function(ScriptedMadeOrder order))>[
        ('public again (1)', (order) => order.status = 1),
        (
          'taken, its trade under way (6)',
          (order) => order
            ..taker = TradeHarness.robotsOf(_net)[5]
            ..deadline = DateTime.utc(2026, 11, 14, 12)
            ..status = 6,
        ),
      ]) {
    testWidgets(
      'opened again, the coordinator showing the ended order $name: the alert that it may still be under way and to check it in the official app, never « over »; « Renew Order » through « Renew this order? » saying why (security review of #220, C1)',
      (tester) async {
        final app = await _App.start(tester);
        final id = app.first.orderId;
        change(app.coordinator.order(id));
        await app.openGarage();
        await _tap(tester, _lastOrder(id));
        await app.settle(12);
        expect(
          find.text(
            'Temple of Sats now shows this order as still running: it may still be taken or need an action from you, and sats may still be locked in it. Check it in the official RoboSats app with your Garage Key before you create another.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('over for this robot'), findsNothing);
        expect(
          find.textContaining('This device kept this order as ended on '),
          findsOneWidget,
        );
        expect(find.textContaining('could not be read again'), findsNothing);
        await renewThroughDialog(
          tester,
          app,
          'Temple of Sats shows this order still running: it may still be taken or need an action from you, and sats may still be locked in it.',
        );
        await app.close();
      },
    );
  }

  testWidgets(
    'opened again, a slow coordinator: the order said being read again, never « over », the renewal through « Renew this order? »; the honest answer (5): « The order has expired », the renewal at once (security review of #220, C1)',
    (tester) async {
      final app = await _App.start(tester);
      final id = app.first.orderId;
      final slow = Completer<void>();
      app.transport.holdReads = slow.future;
      await app.openGarage();
      await _tap(tester, _lastOrder(id));
      await app.settle(12);
      expect(
        find.text('Reading this order again from Temple of Sats…'),
        findsOneWidget,
      );
      expect(find.textContaining('over for this robot'), findsNothing);
      await _tap(tester, _renewOrder);
      await app.settle();
      expect(find.byType(RenewCheckDialog), findsOneWidget);
      expect(
        find.textContaining(
          'The end of this order was not confirmed by Temple of Sats.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Go back'));
      await app.settle();
      expect(find.byType(CreateOrderScreen), findsNothing);
      // The coordinator answers, honest: the end confirmed.
      app.transport.holdReads = null;
      slow.complete();
      await app.settle(12);
      expect(find.text('The order has expired'), findsOneWidget);
      expect(find.textContaining('Reading this order again'), findsNothing);
      await _tap(tester, _renewOrder);
      await app.settle(12);
      expect(find.byType(RenewCheckDialog), findsNothing);
      expect(find.byType(CreateOrderScreen), findsOneWidget);
      expect(app.makes, hasLength(1));
      await app.close();
    },
  );

  testWidgets(
    'two quick taps on « Last order #N »: one screen, one read (security review of #220, R4)',
    (tester) async {
      final app = await _App.start(tester);
      final id = app.first.orderId;
      await app.openGarage();
      final before = app.orderReads.length;
      await tester.tap(_lastOrder(id));
      await tester.tap(_lastOrder(id), warnIfMissed: false);
      await app.settle(12);
      expect(app.tradePages(), [id]);
      expect(app.orderReads.length - before, 1);
      // Back to the Garage: a tap opens it again.
      await app.back();
      expect(find.byType(TradeScreen, skipOffstage: false), findsNothing);
      await _tap(tester, _lastOrder(id));
      await app.settle(12);
      expect(app.tradePages(), [id]);
      await app.close();
    },
  );

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
      // The advice of an order made here, and the alert of the panel before the line that says the coordinator shows it otherwise (functional review of #220, R10).
      final advice = find.text(
        'To follow this order safely, open it in the official RoboSats app with your Garage Key, and contact Temple of Sats if something looks wrong.',
      );
      expect(advice, findsOneWidget);
      expect(
        tester
            .getTopLeft(
              find
                  .text(
                    'The terms of the order are not those of the order taken.',
                  )
                  .first,
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(find.textContaining('now shows this order otherwise'))
              .dy,
        ),
      );
      await renewThroughDialog(
        tester,
        app,
        'Temple of Sats shows this order otherwise than this device kept it.',
      );
      await app.close();
    },
  );

  for (final setAside in [false, true]) {
    testWidgets(
      'the renewal\'s make timing out, then ${setAside ? '« Set aside »' : '« Retry » finding it was not made'}: the page free again and saying so, « Create order » sends anew, one order made (security review of #220, N1)',
      (tester) async {
        final app = await _App.start(tester);
        unawaited(
          app.router.pushNamed(
            P2pRouter.tradeName,
            extra: P2pTradeRouteArgs(app.first),
          ),
        );
        await app.settle(12);
        await _tap(tester, _renewOrder);
        await app.settle(12);
        expect(find.byType(CreateOrderScreen), findsOneWidget);
        app.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.timedOut,
        );
        await _tap(tester, _create);
        await app.settle(16);
        expect(app.makes, hasLength(2));
        expect(find.textContaining('does not know yet whether'), findsWidgets);
        if (setAside) {
          // A check that reaches no one leaves it pending, with « Set aside ».
          app.coordinator.failNext(
            ScriptedMakerRequest.robot,
            ScriptedFault.unreachable,
          );
          await _tap(tester, find.text('Retry').first);
          await app.settle(16);
          expect(
            find.textContaining('does not know yet whether'),
            findsWidgets,
          );
          await _tap(tester, find.text('Set aside').first);
          await app.settle();
          await tester.tap(find.text('Set aside').last);
        } else {
          await _tap(tester, find.text('Retry').first);
        }
        await app.settle(16);
        expect(find.byType(CreateOrderScreen), findsOneWidget);
        expect(find.textContaining('does not know yet whether'), findsNothing);
        expect(
          find.textContaining('Go back, then open the order'),
          findsNothing,
        );
        await _tap(tester, _create);
        await app.settle(16);
        expect(app.makes, hasLength(3));
        // One order made by the renewal at the coordinator, beside the order renewed.
        expect(app.coordinator.orders, hasLength(2));
        expect(
          find.byType(CreateOrderScreen, skipOffstage: false),
          findsNothing,
        );
        await app.close();
      },
    );
  }

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
          // A make of the same terms still pending: said, and the renewal through « Renew this order? » (security review of #220, R2).
          expect(
            find.text(
              'An order with the same terms is still being created here.',
            ),
            findsOneWidget,
          );
          await _tap(tester, _renewOrder);
          await app.settle();
          expect(find.byType(RenewCheckDialog), findsOneWidget);
          await tester.tap(find.text('Renew anyway'));
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

  group('« Last order #N » shows its order\'s robot in the Garage (#227)', () {
    /// The cubit of the Garage, shown or under the pages above the tab.
    GarageCubit garageOf(WidgetTester tester) => BlocProvider.of<GarageCubit>(
      tester.element(find.byType(GarageProfile, skipOffstage: false)),
    );

    /// The number of the robot the Garage shows.
    int shown(WidgetTester tester) => switch (garageOf(tester).state) {
      GarageWithKey(:final robot) => robot.index,
      final other => throw StateError('$other'),
    };

    /// The requests sent since the [from]th, each as its method, its path and the number of its robot (`-` when anonymous), in a stable order: what two moments of a test are compared by, never a token or a key.
    List<String> sentSince(_App app, int from) {
      final robots = TradeHarness.robotsOf(_net);
      return [
        for (final request in app.transport.sent.skip(from))
          '${request.method.name} ${request.url.path} ${switch (request.robot) {
            null => '-',
            final robot => '${robots.indexWhere((known) => known.sessionKey == robot)}',
          }}',
      ]..sort();
    }

    /// Where the trail this device stored of [record] stands.
    Future<String?> stored(_App app, TradeRecord record) async =>
        switch (await app.wait(
          () => app.locator<TradeTrailRepository>().historyOf(record),
        )) {
          Ok(:final value) => value.trail?.position,
          Err(:final failure) => throw StateError('$failure'),
        };

    Future<void> next(_App app) async {
      await app.tester.tap(find.byTooltip('Next account'));
      await app.settle();
    }

    Future<void> previous(_App app) async {
      await app.tester.tap(find.byTooltip('Previous account'));
      await app.settle();
    }

    testWidgets(
      'two robots, the Garage on the second: a tap on the first one\'s « Last order #N » shows that robot, then opens the order; back, the Garage shows it; nothing sent for the switch that the arrows would not send',
      (tester) async {
        // What a tap sends without a switch, the Garage already on the order's robot, on a first app.
        final before = await _App.start(tester, torKnown: true);
        final robot = before.first.robot.accountIndex;
        await before.openGarage();
        expect(shown(tester), robot);
        var from = before.transport.sent.length;
        await _tap(tester, _lastOrder(before.first.orderId));
        await before.settle(12);
        expect(before.tradePages(), [before.first.orderId]);
        final withoutSwitch = sentSince(before, from);
        expect(withoutSwitch, contains('get /api/order/ $robot'));
        await before.close();

        // The same app again, the Garage on the second robot.
        final app = await _App.start(tester, torKnown: true);
        final id = app.first.orderId;
        expect(app.first.robot.accountIndex, robot);
        await app.openGarage();
        expect(shown(tester), robot);
        await next(app);
        expect(shown(tester), robot + 1);
        // What showing the order's robot with the arrows sends: its panel's reads.
        from = app.transport.sent.length;
        await previous(app);
        expect(shown(tester), robot);
        final byArrows = sentSince(app, from);
        // The panel of a robot on its coordinator reads it there.
        expect(byArrows, contains('get /api/robot/ $robot'));
        await next(app);
        expect(find.text('Robot #${robot + 1}'), findsOneWidget);
        from = app.transport.sent.length;
        final readsBefore = app.orderReads.length;
        await _tap(tester, _lastOrder(id));
        await app.settle(12);
        // The order opens as before: its screen, read once.
        expect(app.tradePages(), [id]);
        expect(app.orderReads.length - readsBefore, 1);
        expect(shown(tester), robot);
        // The tap sent what it sends without a switch, and what the arrows send for that robot.
        expect(
          sentSince(app, from),
          ([...withoutSwitch, ...byArrows]..sort()),
          reason: 'arrows: $byArrows',
        );
        await app.back();
        expect(find.byType(TradeScreen, skipOffstage: false), findsNothing);
        expect(find.text('Robot #$robot'), findsOneWidget);
        expect(shown(tester), robot);
        await app.close();
      },
    );

    testWidgets(
      'an order of another Garage Key: it opens as before, the Garage does not move',
      (tester) async {
        final app = await _App.start(tester, torKnown: true);
        final id = app.first.orderId;
        // « New key » since the order (#81): key 1 is the key in use, the order's key an earlier one.
        expect(
          await app.wait(_newKey(app)),
          isA<Ok<int, P2pFailure>>().having((ok) => ok.value, 'value', 1),
        );
        await app.openGarage();
        await next(app);
        final before = shown(tester);
        // The order of key 0 stays among the last orders whatever key is shown (the owner's request of 2026-11-26): a tap opens it, and the Garage of key 1 does not move.
        final states = <GarageState>[];
        final listening = garageOf(tester).stream.listen(states.add);
        addTearDown(listening.cancel);
        await _tap(tester, _lastOrder(id));
        await app.settle(12);
        expect(app.tradePages(), [id]);
        expect(states, isEmpty);
        await app.back();
        expect(shown(tester), before);
        await app.close();
      },
    );

    testWidgets(
      'renewed: the Garage stays on the robot it showed while the new order waits for its bond, and shows the new order\'s robot once its bond is locked',
      (tester) async {
        final app = await _App.start(tester, torKnown: true);
        final id = app.first.orderId;
        final robot = app.first.robot.accountIndex;
        // Not moved by hand: the arrows would stop the following (another test).
        await app.openGarage();
        await _tap(tester, _lastOrder(id));
        await app.settle(12);
        expect(shown(tester), robot);
        await _tap(tester, _renewOrder);
        await app.settle(12);
        await _tap(tester, _create);
        await app.settle(16);
        final renewed = app.tradePages().single;
        expect(renewed, isNot(id));
        final made = (await app.active()).single;
        expect(made.orderId, renewed);
        final renewedRobot = made.robot.accountIndex;
        expect(renewedRobot, isNot(robot));
        // Its bond not locked: the new order read at 0 again and again, the Garage where it was.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(seconds: 5));
        }
        await app.settle();
        expect(app.coordinator.order(renewed).status, 0);
        expect(await stored(app, made), 'makerBondStep');
        expect(shown(tester), robot);
        await app.back();
        expect(find.text('Robot #$robot'), findsOneWidget);
        // The new order opened again from « Order », its bond locked: once its screen read it public, the Garage shows its robot.
        await tester.tap(find.text('Order'));
        await app.settle();
        await _tap(tester, find.text('Active order #$renewed'));
        await app.settle(12);
        expect(app.tradePages(), [renewed]);
        app.coordinator.lockMakerBond(renewed);
        for (var i = 0; i < 12 && shown(tester) != renewedRobot; i++) {
          await tester.pump(const Duration(seconds: 5));
          await app.settle(2);
        }
        expect(shown(tester), renewedRobot);
        expect(await stored(app, made), 'public');
        await app.back();
        expect(find.text('Robot #$renewedRobot'), findsOneWidget);
        await app.close();
      },
    );

    testWidgets('two quick taps: one screen, one switch of robot', (
      tester,
    ) async {
      final app = await _App.start(tester, torKnown: true);
      final id = app.first.orderId;
      await app.openGarage();
      await next(app);
      final states = <GarageState>[];
      final listening = garageOf(tester).stream.listen(states.add);
      addTearDown(listening.cancel);
      final before = app.orderReads.length;
      await tester.tap(_lastOrder(id));
      await tester.tap(_lastOrder(id), warnIfMissed: false);
      await app.settle(12);
      expect(app.tradePages(), [id]);
      expect(app.orderReads.length - before, 1);
      expect(states, hasLength(1));
      expect(shown(tester), app.first.robot.accountIndex);
      await app.close();
    });

    /// The page of the trade of [made] opened as the create page opens it, its bond locked at the coordinator, kept open until its screen stored it public, then left.
    Future<void> lockAndRead(_App app, TradeRecord made) async {
      unawaited(
        app.router.pushNamed(
          P2pRouter.tradeName,
          extra: P2pTradeRouteArgs(made),
        ),
      );
      await app.settle(12);
      app.coordinator.lockMakerBond(made.orderId);
      for (var i = 0; i < 12 && await stored(app, made) != 'public'; i++) {
        await app.tester.pump(const Duration(seconds: 5));
        await app.settle(2);
      }
      expect(await stored(app, made), 'public');
      await app.back();
    }

    /// An order of other terms (than the first one's), made as « Create order » makes it.
    Future<TradeRecord> makeOther(_App app, {double amount = 250}) async =>
        switch (await app.make(
          MakeHarness.request(amount: amount, premium: 4),
        )) {
          Ok(value: MakeStarted(:final record)) => record,
          final other => throw StateError('$other'),
        };

    /// « Offers », then « Garage »: the Garage built again, as each time it is shown.
    Future<void> reopenGarage(_App app) async {
      await app.tester.tap(find.text('Offers'));
      await app.settle();
      await app.openGarage();
    }

    Finder inForm(Finder finder) =>
        find.descendant(of: find.byType(CreateOrderScreen), matching: finder);

    testWidgets(
      'a plain creation from « Create »: while its bond waits, the Garage shown or opened again does not move; once its bond is locked, the Garage shown moves to its robot, and opens on it, reading no other robot',
      (tester) async {
        final app = await _App.start(tester, torKnown: true);
        final robot = app.first.robot.accountIndex;
        final usd = RobosatsCurrency.fromCode('USD');
        app.coordinator.prices[usd?.id ?? 1] = 91711.15;
        await app.openGarage();
        expect(shown(tester), robot);
        // « Create », the form filled as the user does, « Create order », « Done ».
        await tester.tap(find.text('Create'));
        await app.settle();
        expect(find.byType(CreateOrderScreen), findsOneWidget);
        await tester.tap(inForm(find.text('Buy')));
        await tester.enterText(inForm(find.byType(TextField)).at(0), '100');
        await app.settle();
        await tester.tap(inForm(find.byTooltip('Add custom payment method')));
        await app.settle();
        await tester.enterText(find.byType(TextField).last, 'Revolut');
        await tester.pump();
        await tester.tap(find.text('Add payment method'));
        await app.settle();
        await tester.enterText(inForm(find.byType(TextField)).at(1), '2');
        await app.settle();
        await _tap(tester, inForm(find.text('Create order')));
        await app.settle();
        await tester.tap(find.text('Done'));
        await app.settle(16);
        expect(app.makes, hasLength(2));
        final made = (await app.active()).single;
        expect(app.tradePages(), [made.orderId]);
        final madeRobot = made.robot.accountIndex;
        expect(madeRobot, isNot(robot));
        // Its bond not locked: read at 0 again and again, the Garage under the page where it was.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(seconds: 5));
        }
        await app.settle();
        expect(await stored(app, made), 'makerBondStep');
        expect(shown(tester), robot);
        await app.back();
        expect(find.text('Robot #$robot'), findsOneWidget);
        await reopenGarage(app);
        expect(find.text('Robot #$robot'), findsOneWidget);
        // Opened again from « Order », its bond locked: once its screen stored it public, the Garage shown under it moves to its robot.
        await tester.tap(find.text('Order'));
        await app.settle();
        await _tap(tester, find.text('Active order #${made.orderId}'));
        await app.settle(12);
        app.coordinator.lockMakerBond(made.orderId);
        for (var i = 0; i < 12 && shown(tester) != madeRobot; i++) {
          await tester.pump(const Duration(seconds: 5));
          await app.settle(2);
        }
        expect(shown(tester), madeRobot);
        expect(await stored(app, made), 'public');
        await app.back();
        expect(find.text('Robot #$madeRobot'), findsOneWidget);
        // Opened again: on its robot at once, the panel of no other robot read.
        final from = app.transport.sent.length;
        await reopenGarage(app);
        expect(find.text('Robot #$madeRobot'), findsOneWidget);
        expect(
          sentSince(app, from).where((sent) => sent.contains('/api/robot/')),
          everyElement(endsWith(' $madeRobot')),
        );
        await app.close();
      },
    );

    testWidgets(
      'a change of #251: the arrows leave the Garage by hand, left and opened again included, and an order\'s bond seen locked while the Garage is under its page now moves it to that order\'s robot (on main the arrows kept it where it was until the Garage was left)',
      (tester) async {
        // On main (#227) this test was « the arrows stop the following until the Garage is left »: after the arrows, an order's bond locked while the Garage was shown did not move it, and only a new visit opened on that order's robot. Since #251 the hand is kept across visits, and a trade of the key whose bond is seen locked after the move gives the hand back to the rule at once, for the arrows as for a « Last order #N » tap, so that the Garage shows the robot of the trade that has just started; the reference stays where the arrows left it, but is already on that robot since its take and make use the robot shown. Kept by the coordinator's decision on the functional review of PR 274 (C1, option b), to confirm with the owner.
        final app = await _App.start(tester, torKnown: true);
        await app.openGarage();
        final made = await makeOther(app);
        // Moved by hand past the new order's robot.
        await next(app);
        await next(app);
        final byHand = shown(tester);
        expect(byHand, isNot(made.robot.accountIndex));
        // Left and opened again: where it was left.
        await reopenGarage(app);
        expect(find.text('Robot #$byHand'), findsOneWidget);
        // The order's bond locked, under its page: the Garage shows its robot, and opens on it again.
        await lockAndRead(app, made);
        expect(shown(tester), made.robot.accountIndex);
        await reopenGarage(app);
        expect(find.text('Robot #${made.robot.accountIndex}'), findsOneWidget);
        await app.close();
      },
    );

    testWidgets(
      'two orders made, their bonds locked: the Garage opens on the newest one\'s robot',
      (tester) async {
        final app = await _App.start(tester, torKnown: true);
        final older = await makeOther(app);
        final newer = await makeOther(app, amount: 300);
        expect(newer.robot.accountIndex, greaterThan(older.robot.accountIndex));
        // The newer one locked first, so that the order of the locks says nothing.
        await lockAndRead(app, newer);
        await lockAndRead(app, older);
        await app.openGarage();
        expect(shown(tester), newer.robot.accountIndex);
        expect(find.text('Robot #${newer.robot.accountIndex}'), findsOneWidget);
        await app.close();
      },
    );

    /// The coordinator ends [made] by [end], then its page is opened as from the records, reads that end and closes its record, and is left: the order is now the device's last finished order.
    Future<void> endAndRead(
      _App app,
      TradeRecord made,
      void Function(ScriptedMadeOrder order) end,
    ) async {
      end(app.coordinator.order(made.orderId));
      unawaited(
        app.router.pushNamed(
          P2pRouter.tradeName,
          extra: P2pTradeRouteArgs(made),
        ),
      );
      await app.settle(12);
      await app.back();
      expect(
        (await app.active()).map((record) => record.orderId),
        isNot(contains(made.orderId)),
      );
    }

    for (final (name, end, position, moves)
        in <(String, void Function(ScriptedMadeOrder order), String, bool)>[
          ('expired', (order) => order.status = 5, 'expired', false),
          ('cancelled', (order) => order.status = 4, 'cancelled', true),
        ]) {
      testWidgets(
        moves
            ? 'an order public, then $name: the Garage opens on the fresh robot, the « Last order #N » line still under it (#251, a cancellation serves)'
            : 'an order public, then $name: the Garage opens on its robot, the one of the « Last order #N » line under it (review of #229, C1)',
        (tester) async {
          final app = await _App.start(tester, torKnown: true);
          final made = await makeOther(app);
          final robot = made.robot.accountIndex;
          expect(robot, isNot(app.first.robot.accountIndex));
          await lockAndRead(app, made);
          await endAndRead(app, made, end);
          expect(await stored(app, made), position);
          await app.openGarage();
          final opened = moves ? robot + 1 : robot;
          expect(shown(tester), opened);
          expect(find.text('Robot #$opened'), findsOneWidget);
          // The line under the robot is that very order's.
          expect(_lastOrder(made.orderId), findsOneWidget);
          await app.close();
        },
      );
    }

    testWidgets(
      'an order locked and still public, and a later one public then expired: the Garage opens on the public one\'s robot (review of #229, C1)',
      (tester) async {
        final app = await _App.start(tester, torKnown: true);
        final active = await makeOther(app);
        await lockAndRead(app, active);
        final ended = await makeOther(app, amount: 300);
        expect(
          ended.robot.accountIndex,
          greaterThan(active.robot.accountIndex),
        );
        await lockAndRead(app, ended);
        await endAndRead(app, ended, (order) => order.status = 5);
        await app.openGarage();
        expect(shown(tester), active.robot.accountIndex);
        expect(_lastOrder(ended.orderId), findsOneWidget);
        await app.close();
      },
    );

    testWidgets(
      'an order made here succeeded, then a later one public then expired: the Garage opens on the later one\'s robot, the one of the « Last order #N » line (review of #229, C3)',
      (tester) async {
        final app = await _App.start(tester, torKnown: true);
        final succeeded = await makeOther(app);
        await lockAndRead(app, succeeded);
        await endAndRead(app, succeeded, (order) {
          app.coordinator.take(order.id, TradeHarness.robotsOf(_net)[5]);
          order.status = 14;
        });
        expect(await stored(app, succeeded), 'succeeded');
        final expired = await makeOther(app, amount: 300);
        expect(
          expired.robot.accountIndex,
          greaterThan(succeeded.robot.accountIndex),
        );
        await lockAndRead(app, expired);
        await endAndRead(app, expired, (order) => order.status = 5);
        await app.openGarage();
        expect(_lastOrder(expired.orderId), findsOneWidget);
        expect(shown(tester), expired.robot.accountIndex);
        expect(
          find.text('Robot #${expired.robot.accountIndex}'),
          findsOneWidget,
        );
        await app.close();
      },
    );

    testWidgets(
      'an order made here at 15, its buyer\'s payment failed, and a later one public then expired: the Garage opens on the one in progress (review of #229, C3)',
      (tester) async {
        final app = await _App.start(tester, torKnown: true);
        final failed = await makeOther(app);
        await lockAndRead(app, failed);
        app.coordinator.take(failed.orderId, TradeHarness.robotsOf(_net)[5]);
        app.coordinator.order(failed.orderId).status = 15;
        unawaited(
          app.router.pushNamed(
            P2pRouter.tradeName,
            extra: P2pTradeRouteArgs(failed),
          ),
        );
        await app.settle(12);
        await app.back();
        expect(await stored(app, failed), 'routingFailed');
        expect(
          (await app.active()).map((record) => record.orderId),
          contains(failed.orderId),
        );
        final expired = await makeOther(app, amount: 300);
        await lockAndRead(app, expired);
        await endAndRead(app, expired, (order) => order.status = 5);
        await app.openGarage();
        expect(_lastOrder(expired.orderId), findsOneWidget);
        expect(shown(tester), failed.robot.accountIndex);
        await app.close();
      },
    );

    testWidgets(
      'the last finished order of another Garage Key: the Garage of the key in use opens on its first robot (review of #229, C1)',
      (tester) async {
        final app = await _App.start(tester, torKnown: true);
        final made = await makeOther(app);
        expect(made.robot.accountIndex, greaterThan(0));
        await lockAndRead(app, made);
        await endAndRead(app, made, (order) => order.status = 5);
        // « New key » since the order (#81): key 1 is the key in use, the order's key an earlier one.
        expect(
          await app.wait(_newKey(app)),
          isA<Ok<int, P2pFailure>>().having((ok) => ok.value, 'value', 1),
        );
        await app.openGarage();
        // The order of key 0 stays among the last orders, on key 1 too (the owner's request of 2026-11-26).
        expect(_lastOrder(made.orderId), findsOneWidget);
        expect(shown(tester), 0);
        await app.close();
      },
    );

    testWidgets(
      'an order of another Garage Key, its bond locked: the Garage of the key in use opens on its first robot',
      (tester) async {
        final app = await _App.start(tester, torKnown: true);
        final made = await makeOther(app);
        expect(made.robot.accountIndex, greaterThan(0));
        await lockAndRead(app, made);
        // « New key » since the order (#81): key 1 is the key in use, the order's key an earlier one.
        expect(
          await app.wait(_newKey(app)),
          isA<Ok<int, P2pFailure>>().having((ok) => ok.value, 'value', 1),
        );
        await app.openGarage();
        expect(shown(tester), 0);
        expect(find.text('Robot #0'), findsOneWidget);
        await app.close();
      },
    );
  });
  // Last in the file: the app's font, loaded here, stays loaded for the tests after it.
  group('#298: a second tap on « Renew Order » as « Renew this order? » opens', () {
    /// The ended order opened again from the Garage, its coordinator showing it cancelled, so that « Renew Order » goes through « Renew this order? »; the view at 390 × 640, with the app's font, « Renew Order » at the top of the page's view.
    Future<_App> opened(WidgetTester tester) async {
      await loadAppFont();
      final app = await _App.start(tester);
      final id = app.first.orderId;
      app.coordinator.order(id).status = 4;
      await app.openGarage();
      await _tap(tester, _lastOrder(id));
      await app.settle(12);
      tester.view.physicalSize = const Size(390 * 3, 640 * 3);
      await tester.pump();
      for (var i = 0; i < 6 && _renewOrder.evaluate().isEmpty; i++) {
        for (final element in find.byType(Scrollable).evaluate().toList()) {
          if (element case StatefulElement(:final ScrollableState state)) {
            state.position.jumpTo(state.position.maxScrollExtent);
          }
        }
        await tester.pump();
      }
      unawaited(
        Scrollable.ensureVisible(tester.element(_renewOrder), alignment: 0),
      );
      await tester.pump();
      await tester.pump(MovedTapGuard.afterMove);
      return app;
    }

    final renewAnyway = find.descendant(
      of: find.byType(RenewCheckDialog),
      matching: find.widgetWithText(TradeButton, 'Renew anyway'),
    );

    for (final gap in const [100, 250]) {
      testWidgets(
        '« Renew Order » tapped twice $gap ms apart: the second tap lands on « Renew anyway » and opens nothing; a tap on it after the delay opens the renewal\'s page, nothing sent',
        (tester) async {
          final app = await opened(tester);
          final viewport = tester.getRect(
            find
                .ancestor(of: _renewOrder, matching: find.byType(Scrollable))
                .first,
          );
          final point = tester.getRect(_renewOrder).intersect(viewport).center;
          await tester.tapAt(point);
          await tester.pump();
          await tester.pump(Duration(milliseconds: gap));
          final path = {
            for (final entry in tester.hitTestOnBinding(point).path)
              entry.target,
          };
          expect(
            renewAnyway.evaluate().any(
              (element) => path.contains(element.renderObject),
            ),
            isTrue,
          );
          await tester.tapAt(point);
          await app.settle();
          expect(find.byType(CreateOrderScreen), findsNothing);
          expect(find.byType(RenewCheckDialog), findsOneWidget);
          await tester.pump(MovedTapGuard.afterMove);
          await tester.tap(renewAnyway);
          await app.settle(12);
          expect(find.byType(CreateOrderScreen), findsOneWidget);
          expect(app.makes, hasLength(1));
          await app.close();
        },
      );
    }

    testWidgets(
      '« Renew Order » tapped once, then « Renew anyway » tapped on purpose 300, 500, 700 and 900 ms after the dialog\'s first frame: the taps within 0.7 s are ignored, the first after opens the renewal\'s page',
      (tester) async {
        final app = await opened(tester);
        await tester.tap(_renewOrder);
        await tester.pump();
        expect(renewAnyway, findsOneWidget);
        final outcomes = <int, bool>{};
        var elapsed = 0;
        for (final ms in const [300, 500, 700, 900]) {
          await tester.pump(Duration(milliseconds: ms - elapsed));
          elapsed = ms;
          await tester.tapAt(tester.getCenter(renewAnyway));
          await tester.pump();
          // Gone on: the dialog's route popped, on its way out.
          outcomes[ms] =
              !(ModalRoute.of(tester.element(renewAnyway))?.isCurrent ?? false);
          if (outcomes[ms] ?? false) break;
        }
        debugPrint(
          'GESTURE « Renew anyway » after « Renew Order »: opened at $outcomes, ${outcomes.values.where((went) => !went).length} ignored',
        );
        expect(outcomes[300], isFalse);
        expect(outcomes[500], isFalse);
        await app.settle(12);
        expect(find.byType(CreateOrderScreen), findsOneWidget);
        expect(app.makes, hasLength(1));
        await app.close();
      },
    );
  });
}

/// « New key » of the Garage of [app]'s network, after key 0 (#81).
Future<Result<int, P2pFailure>> Function() _newKey(_App app) =>
    () => app.locator<GarageKeyRepository>().activateNext(_net, after: 0);

/// Key 0 of the words as the key the test stored in the testnet slot ([tradeKey]), key 1 as the one it stored in the mainnet slot ([otherTradeKey]): for the tests of an order of an earlier key (#81), never a derivation.
final class _TwoKeys implements P2pGarageKeyPort {
  final GarageKeys _vault;

  const _TwoKeys(this._vault);

  @override
  Future<Result<GarageKeyMaterial, P2pGarageKeyRefusal>> garageKey(
    RobosatsNetwork network, {
    required int index,
  }) async {
    final slot = switch (index) {
      0 => GarageKeySlot.testnet,
      1 => GarageKeySlot.mainnet,
      _ => null,
    };
    if (slot == null) {
      return const Err(
        P2pGarageKeyRefusal(P2pGarageKeyRefusalReason.unreadable),
      );
    }
    return switch (await _vault.read(slot: slot)) {
      Ok(:final value) => Ok(value),
      Err() => const Err(
        P2pGarageKeyRefusal(P2pGarageKeyRefusalReason.unreadable),
      ),
    };
  }
}
