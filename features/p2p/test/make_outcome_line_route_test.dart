import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/trade/active_trades_sheet.dart';
import 'package:p2p/src/ui/trade/pending_make_lines.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/harness.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// The line of a make that a resolution closed, on the create form of the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`): the real router, records, use cases and form, by the user's gestures, the makes sent by the composition's own make use case to the coordinator played by `ScriptedMakerCoordinator` (never a real one).
///
/// « The order was not created. » stays until the user sends a new make, then goes, so that it is never read as the new make's outcome (seen in a real trial); a press stopped before the make leaves keeps it, and a make still pending keeps its line.
const _net = RobosatsNetwork.testnet;

const _notMade = 'The order was not created.';
const _creating = 'Creating your order…';

/// The coordinators: [maker] for every robot's request, the limits and the make, whatever the host; each coordinator's `/api/info/` under its own alias; the book empty.
final class _Coordinators implements CoordinatorTransport {
  final ScriptedMakerCoordinator maker;
  final Map<String, ScriptedMakerCoordinator> _infos = {};

  _Coordinators(this.maker);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final path = request.url.path;
    if (path.startsWith('/api/book')) {
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
    if (path == '/api/info/' && request.robot == null) {
      final alias = _aliasOf(request.url.host);
      final info = _infos[alias] ??= ScriptedMakerCoordinator(
        network: _net,
        robots: const [],
        clock: () => DateTime.utc(2026, 11, 20, 9),
        alias: alias,
      );
      return info.send(request);
    }
    return maker.send(request);
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

final class _Form {
  final WidgetTester tester;
  final ScriptedMakerCoordinator coordinator;
  final GoRouter router;

  _Form(this.tester, this.coordinator, this.router);

  Finder inForm(Finder finder) =>
      find.descendant(of: find.byType(CreateOrderScreen), matching: finder);

  /// The line of a closed make, as [PendingMakeLines] shows it under the form's top.
  Finder get closedLine => find.descendant(
    of: find.byType(PendingMakeLines),
    matching: find.text(_notMade),
  );

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  static Future<_Form> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 3200 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    final clock = DateTime.utc(2026, 11, 20, 9);
    final coordinator = ScriptedMakerCoordinator(
      network: _net,
      robots: TradeHarness.robotsOf(_net),
      clock: () => clock,
    );
    coordinator.prices[1] = 50000;
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
      wallet: FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
        ..rate = P2pWalletRateRead(50000),
      robotKeys: HarnessKeys(),
      bolt11Decoder: coordinator.decoder,
    );
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [const P2pFeature().route(locator, network: (_) => _net)],
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
    await tester.pumpWidget(routerHarness(router));
    tor.add(P2pTorState.ready);
    await settle(tester);
    await settle(tester);
    final form = _Form(tester, coordinator, router);
    await form.tap(find.text('Create'));
    await settle(tester);
    await form.fill();
    return form;
  }

  /// On the form just opened: « Buy », 100 USD, « Revolut » as a custom method, 2 %.
  Future<void> fill() async {
    expect(find.byType(CreateOrderScreen), findsOneWidget);
    await tap(inForm(find.text('Buy')));
    await tester.enterText(inForm(find.byType(TextField)).at(0), '100');
    await settle(tester);
    await tap(inForm(find.byTooltip('Add custom payment method')));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Revolut');
    await tester.pump();
    await tap(find.text('Add payment method'));
    await settle(tester);
    await tester.enterText(inForm(find.byType(TextField)).at(1), '2');
    await settle(tester);
  }

  Finder inSheet(Finder finder) =>
      find.descendant(of: find.byType(ActiveTradesSheet), matching: finder);

  /// Back from the form (or the trade it opened) to the tab, as the system's back does.
  Future<void> back() async {
    router.pop();
    await settle(tester);
    await settle(tester);
    expect(find.byType(CreateOrderScreen), findsNothing);
  }

  /// « Order », the tab's middle entry: « Active trades » opens, and resolves the pending makes listed.
  Future<void> openSheet() async {
    await tap(find.text('Order'));
    await settle(tester);
    await settle(tester);
    expect(find.byType(ActiveTradesSheet), findsOneWidget);
  }

  /// A make whose request times out, then « Go back » to the tab and « Order »: the sheet's resolution finds that the robot names no order, the make closed as not made there; then « Create order » at the sheet's top, and the form filled again.
  Future<void> makeClosedInSheet() async {
    coordinator.failNext(ScriptedMakerRequest.make, ScriptedFault.timedOut);
    await press();
    expect(inForm(find.text('Retry')), findsOneWidget);
    await back();
    await openSheet();
    expect(inSheet(find.text(_notMade)), findsOneWidget);
    expect(inSheet(find.text(_creating)), findsNothing);
    await tap(inSheet(find.text('Create order')));
    await settle(tester);
    await fill();
  }

  /// « Create order », then « Done » when [done], else « Go back »: the make sent, or the press stopped before it.
  Future<void> press({bool done = true}) async {
    await tap(inForm(find.text('Create order')));
    await settle(tester);
    await tap(find.text(done ? 'Done' : 'Go back'));
    await settle(tester);
    await settle(tester);
  }

  /// A make whose request times out (nothing done at the coordinator), then « Retry » on its pending line: the robot names no order, the make closed as not made.
  Future<void> makeClosedAsNotMade() async {
    coordinator.failNext(ScriptedMakerRequest.make, ScriptedFault.timedOut);
    await press();
    expect(
      inForm(find.text('Retry')),
      findsOneWidget,
      reason: 'the make pending, its line shown',
    );
    await tap(inForm(find.text('Retry')));
    await settle(tester);
    await settle(tester);
    expect(closedLine, findsOneWidget);
    expect(find.text(_creating), findsNothing);
  }
}

void main() {
  testWidgets(
    'a make closed as not made, then a second make refused: the first make\'s line goes when the second is sent, and only the second\'s outcome is said',
    (tester) async {
      final form = await _Form.open(tester);
      await form.makeClosedAsNotMade();
      final makesBefore = form.coordinator.received
          .where((kind) => kind == ScriptedMakerRequest.make)
          .length;

      // The second make held at the coordinator: the old line is gone while it is sent.
      final held = Completer<void>();
      form.coordinator
        ..holdMake = held.future
        ..refuseNextMake(1004);
      await form.press();
      expect(
        form.coordinator.received
            .where((kind) => kind == ScriptedMakerRequest.make)
            .length,
        makesBefore + 1,
      );
      expect(find.text(_creating), findsWidgets);
      expect(form.closedLine, findsNothing);
      expect(find.text(_notMade), findsNothing);

      // Its refusal: said under the button, the old line still gone.
      held.complete();
      await settle(tester);
      await settle(tester);
      expect(find.text(_creating), findsNothing);
      expect(
        find.text('Your order is too big. The order was not created.'),
        findsOneWidget,
      );
      expect(form.closedLine, findsNothing);
      expect(find.text(_notMade), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a make closed as not made, then « Create order » stopped at « Go back »: nothing sent, the line stays',
    (tester) async {
      final form = await _Form.open(tester);
      await form.makeClosedAsNotMade();
      final requests = form.coordinator.requests.length;
      await form.press(done: false);
      expect(form.coordinator.requests, hasLength(requests));
      expect(form.closedLine, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a make closed as not made, then a second make whose outcome is unknown: the old line goes, the second\'s pending line stays with its « Retry »',
    (tester) async {
      final form = await _Form.open(tester);
      await form.makeClosedAsNotMade();
      form.coordinator.failNext(
        ScriptedMakerRequest.make,
        ScriptedFault.timedOut,
      );
      await form.press();
      expect(form.closedLine, findsNothing);
      expect(find.text(_notMade), findsNothing);
      // The second make, pending: its line above the form, with « Retry », and « Creating your order… » under the button.
      expect(
        find.descendant(
          of: find.byType(PendingMakeLines),
          matching: find.text(_creating),
        ),
        findsOneWidget,
      );
      expect(form.inForm(find.text('Retry')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a make closed as not made, then a second make refused before any robot is recorded: the form\'s line goes all the same (the list\'s rule never hears of such a make, #313)',
    (tester) async {
      final form = await _Form.open(tester);
      await form.makeClosedAsNotMade();
      final robots = form.coordinator.received
          .where((kind) => kind == ScriptedMakerRequest.robot)
          .length;
      // The limits the make reads before any robot, unreachable: refused, nothing recorded, no robot's request.
      form.coordinator.failNext(
        ScriptedMakerRequest.limits,
        ScriptedFault.unreachable,
      );
      await form.press();
      expect(
        form.coordinator.received
            .where((kind) => kind == ScriptedMakerRequest.robot)
            .length,
        robots,
      );
      expect(find.text(_creating), findsNothing);
      expect(form.closedLine, findsNothing);
      expect(find.text(_notMade), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  group('« Active trades » of the tab, whose cubit outlives the form (#313)', () {
    testWidgets(
      'a make closed as not made in the sheet, then a new make that stays pending: the old line is no longer in the sheet, the new make\'s line stays with « Retry » and « Set aside », and the form still warns and makes nothing',
      (tester) async {
        final form = await _Form.open(tester);
        await form.makeClosedInSheet();
        form.coordinator.failNext(
          ScriptedMakerRequest.make,
          ScriptedFault.timedOut,
        );
        await form.press();
        expect(form.inForm(find.text('Retry')), findsOneWidget);
        await form.back();
        // The sheet's resolution of the new make reads nothing: it stays pending.
        form.coordinator.failNext(
          ScriptedMakerRequest.robot,
          ScriptedFault.timedOut,
        );
        await form.openSheet();
        expect(form.inSheet(find.text(_notMade)), findsNothing);
        expect(find.text(_notMade), findsNothing);
        expect(form.inSheet(find.text(_creating)), findsOneWidget);
        expect(form.inSheet(find.text('Retry')), findsOneWidget);
        expect(form.inSheet(find.text('Set aside')), findsOneWidget);
        // « Create order » at the sheet's top, the form's own resolution reading nothing either: the form says a make is pending, shows its line, and makes nothing.
        form.coordinator.failNext(
          ScriptedMakerRequest.robot,
          ScriptedFault.timedOut,
        );
        final requests = form.coordinator.requests.length;
        await form.tap(form.inSheet(find.text('Create order')));
        await settle(tester);
        await settle(tester);
        expect(
          form.inForm(find.textContaining('is still being created')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(PendingMakeLines),
            matching: find.text(_creating),
          ),
          findsOneWidget,
        );
        expect(form.closedLine, findsNothing);
        await form.fill();
        await form.tap(form.inForm(find.text('Create order')));
        await settle(tester);
        expect(find.text('Done'), findsNothing);
        expect(
          form.coordinator.requests
              .skip(requests)
              .where((request) => request.url.path == '/api/make/'),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a make closed as not made in the sheet, then a new make that makes its order: the old line is not shown above the new order',
      (tester) async {
        final form = await _Form.open(tester);
        await form.makeClosedInSheet();
        await form.press();
        // The order made: its trade opened in place of the form.
        expect(find.byType(CreateOrderScreen), findsNothing);
        await form.back();
        await form.openSheet();
        final orderId = form.coordinator.orders.keys.single;
        expect(
          form.inSheet(find.text('Active order #$orderId')),
          findsOneWidget,
        );
        expect(form.inSheet(find.text(_notMade)), findsNothing);
        expect(form.inSheet(find.text(_creating)), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
