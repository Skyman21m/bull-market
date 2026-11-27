import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/repositories/trade_payout_repository.dart';
import 'package:p2p/src/domain/trade/payout_trace.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/harness.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// Schema 9 (#204, #231, #233) on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`), by the user's gestures, with the app started again: a new composition over the same database file, nothing of the earlier run's memory kept (`setUpP2pForTesting(databaseOpener:)`).
///
/// The coordinators are played by [ScriptedMakerCoordinator] (never real ones); the wallet is [FakeP2pWalletPort]: nothing is paid. The tests' coordinator checks a payout's clear signature against a key the fake robot keys of a composition do not sign for (see `maker_sell_route_test.dart`, #234): a payout submitted here is refused, so a payout taken from this device is recorded through the composition's own repository as `SubmitPayoutUsecase` records it (`payout_trace_test.dart` drives that use case over the real records), and a payout given from another app is the coordinator moving to 7 by itself.
const _net = RobosatsNetwork.testnet;

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
      return Ok(_json(404, {'not_found': 'No orders found'}));
    }
    if (path.startsWith('/api/chat')) {
      return Ok(_json(400, {'bad_request': 'not played'}));
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

  static CoordinatorResponse _json(int status, Object body) =>
      CoordinatorResponse(
        statusCode: status,
        headers: const {'content-type': 'application/json'},
        body: utf8.encode(jsonEncode(body)),
      );
}

/// One run of the app over [file]: its own locator, router and memory; the coordinator, the wallet and the keystore are the world's, kept across runs.
final class _Run {
  final WidgetTester tester;
  final GetIt locator;
  final GoRouter router;
  final _World world;

  _Run(this.tester, this.locator, this.router, this.world);

  static Future<_Run> start(
    WidgetTester tester,
    _World world, {
    bool first = false,
  }) async {
    final locator = GetIt.asNewInstance();
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    setUpP2pForTesting(
      locator,
      transport: _Coordinators(world.coordinator),
      torStates: () => tor.stream,
      clock: () => world.clock,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      wallet: world.wallet,
      robotKeys: HarnessKeys(),
      bolt11Decoder: world.coordinator.decoder,
      databaseOpener: () => NativeDatabase(world.file),
    );
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [const P2pFeature().route(locator, network: (_) => _net)],
    );
    if (first) {
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
    }
    await tester.pumpWidget(routerHarness(router));
    tor.add(P2pTorState.ready);
    await settle(tester);
    await settle(tester);
    return _Run(tester, locator, router, world);
  }

  /// The app stopped: its screens gone, its composition reset (its database closed); then started again over the same file.
  Future<_Run> relaunch() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.runAsync(locator.reset);
    await tester.pump(const Duration(seconds: 61));
    return start(tester, world);
  }

  Future<void> pass(int seconds) async {
    for (var i = 0; i < seconds * 4; i++) {
      world.clock = world.clock.add(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> waitFor(Finder finder, {int seconds = 60}) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (finder.evaluate().isNotEmpty) return;
      world.clock = world.clock.add(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
    fail('never shown: $finder');
  }

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    // A guarded button just shown (« Pay ») ignores taps for a moment (security review of #291, B1): the tap comes later, as a user's.
    if (find
        .ancestor(of: finder, matching: find.byType(MovedTapGuard))
        .evaluate()
        .isNotEmpty) {
      await tester.pump(MovedTapGuard.afterMove);
    }
    await tester.tap(finder);
    await tester.pump();
  }

  /// « Create », « Sell » or « Buy », 100 USD, « Revolut », 2 %, « Create order », « Done »: the trade of the order made, at its maker bond.
  Future<void> makeOrder({required bool buy}) async {
    Finder inForm(Finder finder) =>
        find.descendant(of: find.byType(CreateOrderScreen), matching: finder);
    await tap(find.text('Create'));
    await settle(tester);
    await tap(inForm(find.text(buy ? 'Buy' : 'Sell')));
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
    await tap(inForm(find.text('Create order')));
    await settle(tester);
    await tap(find.text('Done'));
    await waitFor(find.textContaining('PUBL'), seconds: 20);
  }

  /// The trade shown, as its screen's cubit holds it.
  TradeRecord get record => BlocProvider.of<TradeCubit>(
    find.byType(TradeScreen).evaluate().single,
  ).state.record;

  /// [record]'s trade screen opened from the tab, as the list of active trades opens it.
  void open(TradeRecord record) => unawaited(
    router.pushNamed(P2pRouter.tradeName, extra: P2pTradeRouteArgs(record)),
  );

  /// [statements] run on this run's database, as written: what a file of schema 8 held, simulated over the file of this run (a test's own statement, never the app's).
  Future<void> rewrite(List<String> statements) async {
    await tester.runAsync(() async {
      for (final statement in statements) {
        await locator<P2pDatabase>().customStatement(statement);
      }
    });
  }

  Future<String> triggerText(String name) async {
    late String text;
    await tester.runAsync(() async {
      text =
          (await locator<P2pDatabase>()
                  .customSelect(
                    "SELECT sql FROM sqlite_master WHERE name = '$name'",
                  )
                  .getSingle())
              .read<String>('sql');
    });
    return text;
  }
}

final class _World {
  final File file;
  final ScriptedMakerCoordinator coordinator;
  final FakeP2pWalletPort wallet;
  DateTime clock;

  _World(this.file, this.coordinator, this.wallet, this.clock);

  ScriptedMadeOrder get order => coordinator.orders.values.single;

  static Future<_World> of(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 3200 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('p2p-relaunch-'),
    ))!;
    addTearDown(() => directory.deleteSync(recursive: true));
    late _World world;
    final coordinator = ScriptedMakerCoordinator(
      network: _net,
      robots: TradeHarness.robotsOf(_net),
      clock: () => world.clock,
    );
    coordinator.prices[1] = 50000;
    world = _World(
      File('${directory.path}/p2p.sqlite'),
      coordinator,
      FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
        ..rate = P2pWalletRateRead(50000),
      DateTime.utc(2026, 11, 20, 9),
    );
    return world;
  }
}

/// A quote of [invoice] with 500 sats of swap fees and 27 of network fee.
P2pWalletQuote _quoteOf(Bolt11TestInvoice invoice) {
  final checked = checkedBolt11InvoiceForTesting(
    bolt11: invoice.text,
    amount: invoice.facts.amount,
    network: _net,
    paymentHash: invoice.facts.paymentHash,
    expiresAt: invoice.facts.createdAt.add(invoice.facts.expiry),
    now: invoice.facts.createdAt,
  );
  if (checked == null) fail('not a payable invoice');
  return P2pWalletQuote(
    invoice: checked,
    payin: Sats(checked.amount.value + BigInt.from(500)),
    networkFee: Sats.fromInt(27),
    balance: Sats.fromInt(5000000),
    quotedAt: invoice.facts.createdAt,
  );
}

/// One earlier collateral of a known amount, in the two lines the owner validated on 2026-11-24 (#250); its sats in the detail.
const _earlierNotBack = 'A previous collateral has not come back';
const _earlierOut = 'With this one, 393,308 sats will be out of this wallet.';
const _earlierDetail =
    'You already paid, or tried to pay, a collateral of 196,654 sats for this order with this wallet. It has not come back to it yet.';
const _earlierOutUnknown =
    'An earlier collateral of this order, paid or attempted with this wallet, has not come back yet; this device no longer knows its amount. With this one, at least 196,654 sats will be out of this wallet for the collaterals of this order, bond not included.';

void main() {
  // A new composition over the same file opens a second database object, as the app started again does.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// A sell order made, its bond locked elsewhere, taken, its collateral of contract 0 paid with this wallet, the swap service still holding it.
  Future<(_Run, TradeRecord)> sellerPaidContract0(WidgetTester tester) async {
    final world = await _World.of(tester);
    final run = await _Run.start(tester, world, first: true);
    await run.makeOrder(buy: false);
    world.coordinator.lockMakerBond(world.order.id);
    await run.waitFor(find.textContaining('Your order is public'), seconds: 20);
    world.coordinator.take(world.order.id, TradeHarness.robotsOf(_net)[5]);
    await run.waitFor(find.text('Pay with this wallet'), seconds: 60);
    final escrow0 = world.order.escrow ?? fail('no escrow invoice');
    final quote = _quoteOf(escrow0);
    world.wallet.scriptQuote(Ok(quote));
    await run.tap(find.text('Pay with this wallet'));
    await settle(tester);
    final payment = P2pWalletPayment(
      id: 'swap-e0',
      paymentHash: escrow0.facts.paymentHash,
    );
    world.wallet
      ..scriptPayment(Ok(payment))
      ..setFound(
        payment.paymentHash,
        P2pWalletPaymentFound(
          payment: payment,
          progress: const P2pWalletPaymentPending(),
        ),
      )
      ..setProgress(payment, const Ok(P2pWalletPaymentPending()));
    await run.tap(
      find.widgetWithText(TradeButton, 'Pay ${_sats(quote.total)} sats'),
    );
    await settle(tester);
    expect(world.wallet.paid, hasLength(1));
    return (run, run.record);
  }

  testWidgets(
    'the app started again between two takes: the earlier collateral\'s exact sats, from its record (#233)',
    (tester) async {
      final (run, record) = await sellerPaidContract0(tester);
      final again = await run.relaunch();
      final world = again.world;
      world.coordinator.backToBook(world.order.id);
      world.clock = world.clock.add(const Duration(minutes: 1));
      world.coordinator.take(world.order.id, TradeHarness.robotsOf(_net)[4]);
      again.open(record);
      await again.waitFor(find.text('Pay with this wallet'), seconds: 30);
      final escrow1 = world.order.escrow ?? fail('no escrow invoice');
      world.wallet.scriptQuote(Ok(_quoteOf(escrow1)));
      await again.tap(find.text('Pay with this wallet'));
      await settle(tester);
      expect(find.text(_earlierNotBack), findsOneWidget);
      expect(find.text(_earlierOut), findsOneWidget);
      // The earlier collateral's exact sats, from its record: in the detail.
      await again.tap(find.text('Show details'));
      await settle(tester);
      expect(find.text(_earlierDetail), findsOneWidget);
      expect(find.textContaining('at least'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  testWidgets(
    'a collateral paid before schema 9 (its amount never kept): after the app started again, « at least », never 0 (#233)',
    (tester) async {
      final (run, record) = await sellerPaidContract0(tester);
      final again = await run.relaunch();
      // What a file of schema 8 held: the payment's row without its amount (simulated: the trigger set aside for this one statement, then made again from its own text).
      final trigger = await again.triggerText('trade_payments_sats_forward');
      await again.rewrite([
        'DROP TRIGGER trade_payments_sats_forward',
        "UPDATE trade_payments SET confirmed_sats = NULL WHERE step = 'escrow'",
        trigger,
      ]);
      final world = again.world;
      world.coordinator.backToBook(world.order.id);
      world.clock = world.clock.add(const Duration(minutes: 1));
      world.coordinator.take(world.order.id, TradeHarness.robotsOf(_net)[4]);
      again.open(record);
      await again.waitFor(find.text('Pay with this wallet'), seconds: 30);
      world.wallet.scriptQuote(
        Ok(_quoteOf(world.order.escrow ?? fail('no escrow invoice'))),
      );
      await again.tap(find.text('Pay with this wallet'));
      await settle(tester);
      expect(find.text(_earlierOutUnknown), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  /// A buy order made, its bond locked elsewhere, taken by robot 5: at 6, the payout asked.
  Future<_Run> buyerAtPayout(WidgetTester tester) async {
    final world = await _World.of(tester);
    final run = await _Run.start(tester, world, first: true);
    await run.makeOrder(buy: true);
    world.coordinator.lockMakerBond(world.order.id);
    await run.waitFor(find.textContaining('Your order is public'), seconds: 20);
    world.coordinator.take(world.order.id, TradeHarness.robotsOf(_net)[5]);
    await run.waitFor(find.text('Generate Invoice'), seconds: 60);
    return run;
  }

  /// The coordinator at 7 with a payout of [hash], then the escrow locked: at 9, « Confirm 100 USD sent ».
  Future<void> toChat(_Run run, String hash) async {
    run.world.order
      ..payoutHash = hash
      ..status = 7;
    await run.waitFor(
      find.textContaining('Your info looks good!'),
      seconds: 30,
    );
    run.world.coordinator.lockEscrow(run.world.order.id);
    await run.waitFor(
      find.widgetWithText(TradeButton, 'Confirm 100 USD sent'),
      seconds: 30,
    );
  }

  const pasted =
      'This contract\'s payout invoice was pasted: the sats will go to the wallet that made it.';
  const notGivenHere =
      'This contract\'s payout invoice or address was not given from Bull Market: check where the sats will arrive.';
  const unknown =
      'Bull Market cannot tell whether this contract\'s payout invoice or address came from this wallet.';

  testWidgets(
    'a payout given from another app: « not given from Bull Market » before « Confirm … sent » and in its dialog, after the app started again too (#204)',
    (tester) async {
      final run = await buyerAtPayout(tester);
      final record = run.record;
      await toChat(run, 'c1' * 32);
      expect(find.text(notGivenHere), findsOneWidget);
      final again = await run.relaunch();
      again.open(record);
      await again.waitFor(
        find.widgetWithText(TradeButton, 'Confirm 100 USD sent'),
        seconds: 30,
      );
      expect(find.text(notGivenHere), findsOneWidget);
      await again.tap(find.widgetWithText(TradeButton, 'Confirm 100 USD sent'));
      await settle(tester);
      expect(find.text(notGivenHere), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  for (final (name, source, line) in [
    ('from this wallet: nothing said', PayoutTraceSource.thisWallet, null),
    ('pasted: said so', PayoutTraceSource.pasted, pasted),
  ]) {
    testWidgets(
      'a payout taken from this device, $name, before « Confirm … sent » after the app started again (#204)',
      (tester) async {
        final run = await buyerAtPayout(tester);
        final record = run.record;
        // Recorded as `SubmitPayoutUsecase` records a payout the coordinator took, through the composition's own repository (see this file's note).
        await tester.runAsync(
          () async => run.locator<TradePayoutRepository>().recordPayout(
            record,
            take: 0,
            source: source,
            kind: PayoutTraceKind.invoice,
            at: run.world.clock,
          ),
        );
        await toChat(run, 'd1' * 32);
        final again = await run.relaunch();
        again.open(record);
        await again.waitFor(
          find.widgetWithText(TradeButton, 'Confirm 100 USD sent'),
          seconds: 30,
        );
        for (final text in [pasted, notGivenHere, unknown]) {
          expect(
            find.text(text),
            text == line ? findsOneWidget : findsNothing,
            reason: text,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
        await tester.pump(const Duration(seconds: 61));
      },
    );
  }

  testWidgets(
    'a contract under way before schema 9: « cannot tell », never « not given from Bull Market » (#204)',
    (tester) async {
      final run = await buyerAtPayout(tester);
      final record = run.record;
      await toChat(run, 'e1' * 32);
      final again = await run.relaunch();
      // The mark the step to schema 9 writes for such a contract (simulated: the trigger that keeps it the step's set aside for this one statement, then made again).
      final trigger = await again.triggerText('trade_payouts_of_their_trade');
      await again.rewrite([
        'DROP TRIGGER trade_payouts_of_their_trade',
        "INSERT INTO trade_payouts (key_fingerprint, robot_index, take, source) VALUES ('${record.robot.keyFingerprint.hex}', ${record.robot.accountIndex}, 0, 'unrecorded')",
        trigger,
      ]);
      again.open(record);
      await again.waitFor(
        find.widgetWithText(TradeButton, 'Confirm 100 USD sent'),
        seconds: 30,
      );
      expect(find.text(unknown), findsOneWidget);
      expect(find.text(notGivenHere), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  testWidgets(
    'a premium shown otherwise, then put back: the screen keeps saying which and when, after the app started again too (#231)',
    (tester) async {
      final run = await buyerAtPayout(tester);
      final record = run.record;
      await toChat(run, 'f1' * 32);
      final world = run.world;
      world.coordinator.orderChanges[world.order.id] = {'premium': '7.00'};
      await run.waitFor(
        find.text('The terms of the order are not those of the order taken.'),
        seconds: 200,
      );
      world.coordinator.orderChanges.remove(world.order.id);
      final trace = find.textContaining(
        'up to a premium of +7.0% instead of +2.0%.',
      );
      await run.waitFor(trace, seconds: 200);
      expect(
        find.text('The terms of the order are not those of the order taken.'),
        findsNothing,
      );
      final again = await run.relaunch();
      again.open(record);
      await again.waitFor(
        find.widgetWithText(TradeButton, 'Confirm 100 USD sent'),
        seconds: 30,
      );
      expect(trace, findsOneWidget);
      await again.tap(find.widgetWithText(TradeButton, 'Confirm 100 USD sent'));
      await settle(tester);
      expect(trace, findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  testWidgets(
    'the line says the order\'s own premium from its terms kept here, never the premium a read shows within the tolerance, on the panel and in the dialog (security review of schema 9, R1)',
    (tester) async {
      final run = await buyerAtPayout(tester);
      await toChat(run, 'f2' * 32);
      final world = run.world;
      world.coordinator.orderChanges[world.order.id] = {'premium': '7.00'};
      await run.waitFor(
        find.text('The terms of the order are not those of the order taken.'),
        seconds: 200,
      );
      // Put back to a premium closer to the order's own than the tolerance: no change of terms, and a read whose premium is not the order's.
      world.coordinator.orderChanges[world.order.id] = {'premium': '2.004'};
      final trace = find.textContaining(
        'up to a premium of +7.0% instead of +2.0%.',
      );
      await run.waitFor(trace, seconds: 200);
      expect(find.textContaining('+2.004%'), findsNothing);
      await run.tap(find.widgetWithText(TradeButton, 'Confirm 100 USD sent'));
      await settle(tester);
      expect(trace, findsNWidgets(2));
      expect(find.textContaining('+2.004%'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  testWidgets(
    'a contract seen late, its payout invoice never seen here: the red line of the payment rule alone, never the line of where the payout came from beside it, before « Confirm … sent » and in its dialog (functional review of schema 9, C2)',
    (tester) async {
      final world = await _World.of(tester);
      final run = await _Run.start(tester, world, first: true);
      await run.makeOrder(buy: true);
      world.coordinator.lockMakerBond(world.order.id);
      await run.waitFor(
        find.textContaining('Your order is public'),
        seconds: 20,
      );
      final record = run.record;
      // Taken (contract 0, seen at 6), then back in the book, taken again by another robot, its payout given from another app and the escrow locked, all before the next read: the next contract is seen late, at 9.
      world.coordinator.take(world.order.id, TradeHarness.robotsOf(_net)[5]);
      await run.waitFor(find.text('Generate Invoice'), seconds: 60);
      world.coordinator.backToBook(world.order.id);
      world.clock = world.clock.add(const Duration(minutes: 1));
      world.coordinator.take(world.order.id, TradeHarness.robotsOf(_net)[4]);
      world.order
        ..payoutHash = 'c2' * 32
        ..status = 7;
      world.coordinator.lockEscrow(world.order.id);
      final confirm = find.widgetWithText(TradeButton, 'Confirm 100 USD sent');
      await run.waitFor(confirm, seconds: 200);
      const notSeen =
          'Bull Market has not seen this contract\'s payout invoice: do not send the money before checking in the official app.';
      await run.waitFor(find.text(notSeen), seconds: 30);
      expect(find.text(notSeen), findsOneWidget);
      expect(find.text(notGivenHere), findsNothing);
      // The trace is there all the same: the screen says the red line alone.
      late PayoutTrace trace;
      await tester.runAsync(() async {
        trace = switch (await run.locator<TradePayoutRepository>().traceOf(
          record,
          take: 1,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
      });
      expect(trace, const PayoutNotGivenHere());
      await run.tap(confirm);
      await settle(tester);
      expect(find.text(notSeen), findsNWidgets(2));
      expect(find.text(notGivenHere), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  testWidgets(
    'the composition\'s wiring: an invoice « Generate Invoice » gave, then « Submit », is traced « from this wallet » by the payout\'s use case, and nothing is said before « Confirm … sent », after the app started again too (functional review of schema 9, C5, m15)',
    (tester) async {
      final run = await buyerAtPayout(tester);
      final record = run.record;
      final world = run.world;
      final order = world.order;
      final payout = _halfEven(
        order.lastSatoshis - order.lastSatoshis * world.coordinator.makerFee,
      );
      final asked = (payout - payout * 1000 / 1000000).truncate();
      final now = world.coordinator.clock();
      final invoice = Bolt11TestInvoice(
        network: Bolt11Network.testnet,
        sats: asked,
        seed: 88,
        createdAt: now,
        expiry: const Duration(hours: 24),
        description: 'Bull wallet payout',
      );
      world.coordinator.decoder.add(invoice);
      world.wallet.scriptInvoice(
        Ok(
          P2pWalletInvoice(
            bolt11: invoice.text,
            amount: Sats.fromInt(asked),
            expiresAt: now.add(const Duration(hours: 24)),
            received: Sats.fromInt(asked),
          ),
        ),
      );
      await run.tap(find.text('Generate Invoice'));
      await settle(tester);
      // The answer lost on its way back: the coordinator may hold it, so its trace is written (the test coordinator would refuse the fake keys' signature, see this file's note).
      world.coordinator.failNext(
        ScriptedMakerRequest.payout,
        ScriptedFault.timedOut,
      );
      await run.tap(find.widgetWithText(TradeButton, 'Submit'));
      await run.pass(10);
      late PayoutTrace trace;
      await tester.runAsync(() async {
        trace = switch (await run.locator<TradePayoutRepository>().traceOf(
          record,
          take: 0,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
      });
      expect(
        trace,
        isA<PayoutFromThisWallet>().having(
          (given) => given.kind,
          'kind',
          PayoutTraceKind.invoice,
        ),
      );
      await toChat(run, invoice.facts.paymentHash);
      final again = await run.relaunch();
      again.open(record);
      await again.waitFor(
        find.widgetWithText(TradeButton, 'Confirm 100 USD sent'),
        seconds: 30,
      );
      for (final text in [pasted, notGivenHere, unknown]) {
        expect(find.text(text), findsNothing, reason: text);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );
}

String _sats(Sats sats) => sats.value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (match) => '${match[1]},',
);

/// Python's round, half to even, as the coordinator rounds the payout (`api/logics.py:666-668`).
int _halfEven(double value) {
  final floor = value.floorToDouble();
  final diff = value - floor;
  if (diff < 0.5) return floor.toInt();
  if (diff > 0.5) return floor.toInt() + 1;
  return floor.toInt().isEven ? floor.toInt() : floor.toInt() + 1;
}
