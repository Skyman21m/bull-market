import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/repositories/trade_payment_repository.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/make_order_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/pay_bond_from_wallet_usecase.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
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

/// A maker seller's escrow on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`), #187: the real router, records, use cases, state machine and trade screen, the coordinator played by `ScriptedMakerCoordinator` (never a real one), the wallet `FakeP2pWalletPort`.
///
/// « Sell » is not in the create form before #188: the sell order is made by the composition's own make use case, as « Create order » would make it. The escrow panel is the one a taker seller has had since #97; its confirmation of a maker's escrow (the gap, the new contract's line) is #188's, so here the panel is only seen to offer, to refuse, and never to pay a maker's escrow without the confirmation of its contract.
const _net = RobosatsNetwork.testnet;

/// The scripted maker coordinator for every robot's request and the anonymous information and limits; the book, anonymous and unknown to it, to an empty fake.
final class _Coordinators implements CoordinatorTransport {
  final ScriptedMakerCoordinator maker;
  final FakeTransport rest = FakeTransport(network: _net);

  _Coordinators(this.maker);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
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
  final FakeP2pWalletPort wallet;
  final void Function(Duration) advance;
  late TradeRecord record;

  _App(
    this.tester,
    this.locator,
    this.router,
    this.coordinator,
    this.wallet,
    this.advance,
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

  /// The escrow's instance of the wallet's payment, as the composition registers it.
  PayBondFromWalletUsecase get escrow =>
      locator<PayBondFromWalletUsecase>(instanceName: InvoiceStep.escrow.name);

  /// The trade screen of the order, opened as « Active trades » opens it.
  Future<void> openTrade() async {
    unawaited(
      router.pushNamed(P2pRouter.tradeName, extra: P2pTradeRouteArgs(record)),
    );
    await settle(12);
  }

  /// The system's back, as Android's back gesture.
  Future<void> back() async {
    await tester.binding.handlePopRoute();
    await settle(12);
  }

  /// A sell order of 100 EUR at +2 % made at the coordinator's 50,000 EUR/BTC, its bond locked, taken by robot 5: at 6, the escrow asked of this robot.
  static Future<_App> start(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 2600 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    var clock = DateTime.utc(2026, 11, 14, 9);
    final coordinator = ScriptedMakerCoordinator(
      network: _net,
      robots: TradeHarness.robotsOf(_net),
      clock: () => clock,
    );
    coordinator.prices[2] = 50000;
    final transport = _Coordinators(coordinator);
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
      ..rate = P2pWalletRateRead(50000);
    setUpP2pForTesting(
      locator,
      transport: transport,
      torStates: () => tor.stream,
      clock: () => clock,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      wallet: wallet,
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
      wallet,
      (by) => clock = clock.add(by),
    );
    final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    await app.wait(
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
    await app.settle();
    final request = MakeHarness.request(sell: true);
    app.record = switch (await app.wait(
      () => locator<MakeOrderUsecase>().execute(
        request,
        coordinator: coordinator.coordinator,
        network: _net,
        seen: MakePriceSeen.of(
          currency: request.currency,
          coordinatorPrice: 50000,
        ),
      ),
    )) {
      Ok(value: MakeStarted(:final record)) => record,
      final other => throw StateError('$other'),
    };
    coordinator
      ..lockMakerBond(app.record.orderId)
      ..take(app.record.orderId, TradeHarness.robotsOf(_net)[5]);
    return app;
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await tester.pump(const Duration(seconds: 61));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// The minimal refusal of #187, until the panel's words of #188.
const _earlierHeld =
    'This wallet paid the collateral of an earlier take of this order, and the swap service has not reported it released yet. Pay this collateral with another wallet.';

void main() {
  testWidgets(
    'contract 0: « Pay with this wallet » offered for a maker seller\'s escrow, and the panel without the confirmation of its contract (#188) pays nothing',
    (tester) async {
      final app = await _App.start(tester);
      await app.openTrade();
      expect(find.textContaining('as collateral'), findsWidgets);
      final pay = find.text('Pay with this wallet');
      expect(pay, findsOneWidget);
      // The escrow of 196,127 sats quoted with 500 sats of fees and 27 of network: 196,654 in all.
      final invoice = app.coordinator.order(app.record.orderId).escrow;
      if (invoice == null) fail('no escrow invoice');
      final checked = checkedBolt11InvoiceForTesting(
        bolt11: invoice.text,
        amount: invoice.facts.amount,
        network: _net,
        paymentHash: invoice.facts.paymentHash,
        expiresAt: invoice.facts.createdAt.add(invoice.facts.expiry),
        now: DateTime.utc(2026, 11, 14, 9),
      );
      if (checked == null) fail('not a payable invoice');
      expect(checked.amount, Sats.fromInt(196127));
      app.wallet
        ..scriptQuote(
          Ok(
            P2pWalletQuote(
              invoice: checked,
              payin: Sats.fromInt(196627),
              networkFee: Sats.fromInt(27),
              balance: Sats.fromInt(5000000),
              quotedAt: DateTime.utc(2026, 11, 14, 9),
            ),
          ),
        )
        ..scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'never-asked',
              paymentHash: checked.paymentHash,
            ),
          ),
        );
      await _tap(tester, pay);
      await app.settle();
      expect(app.wallet.quoted, hasLength(1));
      final confirm = find.text('Pay 196,654 sats');
      expect(confirm, findsOneWidget);
      await _tap(tester, confirm);
      await app.settle();
      // Refused before the wallet: the panel gives no contract, which a maker seller's escrow needs.
      expect(app.wallet.paid, isEmpty);
      expect(
        find.text('The order moved on before the payment. Nothing was paid.'),
        findsOneWidget,
      );
      final rows = switch (await app.wait(
        () => app.locator<TradePaymentRepository>().paymentsOfTrade(app.record),
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(rows, isEmpty);
      await app.close();
    },
  );

  testWidgets(
    'a new contract while the escrow of contract 0, paid from this wallet, is held: the panel says it and offers no « Pay with this wallet »; once its refund is pending, offered again',
    (tester) async {
      final app = await _App.start(tester);
      // Contract 0's escrow paid from this wallet through the composition's own use case, with the confirmation of its contract (#188's panel will give it), from the status the trade screen stored.
      await app.openTrade();
      expect(find.text('Pay with this wallet'), findsOneWidget);
      final escrow = app.escrow;
      final seen = switch (BlocProvider.of<TradeCubit>(
        find.byType(TradeScreen).evaluate().single,
      ).state.watch) {
        TradeWatchStatus(:final seen) when seen.stored => seen,
        final other => fail('$other'),
      };
      expect(seen.status, isA<WaitingForBoth>());
      final offered = switch (await app.wait(
        () => escrow.checkBond(app.record, seen),
      )) {
        Ok(:final value) => value.walletInvoice,
        Err(:final failure) => fail('$failure'),
      };
      app.wallet.scriptQuote(
        Ok(
          P2pWalletQuote(
            invoice: offered,
            payin: Sats(offered.amount.value + BigInt.from(500)),
            networkFee: Sats.fromInt(27),
            balance: Sats.fromInt(5000000),
            quotedAt: DateTime.utc(2026, 11, 14, 9),
          ),
        ),
      );
      final quote = switch (await app.wait(
        () => escrow.quoteBond(app.record, seen),
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      final contract = switch (await app.wait(
        () => escrow.escrowContractOf(app.record, quote),
      )) {
        Ok(value: final contract?) => contract,
        final other => fail('$other'),
      };
      final payment = P2pWalletPayment(
        id: 'swap-e0',
        paymentHash: offered.paymentHash,
      );
      app.wallet.scriptPayment(Ok(payment));
      expect(
        await app.wait(
          () => escrow.payBond(app.record, accepted: quote, contract: contract),
        ),
        isA<Ok<P2pWalletPayment, BondPayRefusal>>(),
      );
      app.wallet
        ..setFound(
          payment.paymentHash,
          P2pWalletPaymentFound(
            payment: payment,
            progress: const P2pWalletPaymentPending(),
          ),
        )
        ..setProgress(payment, const Ok(P2pWalletPaymentPending()));
      await app.back();
      // The buyer gave no payout: the escrow returned, the order back in the book, taken again a minute later by another robot (`api/logics.py:445-458`).
      app.coordinator.backToBook(app.record.orderId);
      app.advance(const Duration(minutes: 1));
      app.coordinator.take(app.record.orderId, TradeHarness.robotsOf(_net)[4]);
      await app.openTrade();
      expect(find.textContaining('as collateral'), findsWidgets);
      await tester.ensureVisible(find.text(_earlierHeld));
      expect(find.text(_earlierHeld), findsOneWidget);
      expect(find.text('Pay with this wallet'), findsNothing);
      expect(app.wallet.quoted, hasLength(1));
      expect(app.wallet.paid, hasLength(1));
      await app.back();
      // The swap service reports the first escrow's refund pending: opened again, the panel offers this wallet for contract 1.
      app.wallet
        ..setFound(
          payment.paymentHash,
          P2pWalletPaymentFound(
            payment: payment,
            progress: const P2pWalletPaymentRefundPending(),
          ),
        )
        ..setProgress(payment, const Ok(P2pWalletPaymentRefundPending()));
      await app.openTrade();
      expect(find.text(_earlierHeld), findsNothing);
      expect(find.text('Pay with this wallet'), findsOneWidget);
      // Left as the user leaves it (closing the harness with this page still open never ends the test's teardown, a cause not established, the page left by the back gesture closing its cubits as the app does).
      await app.back();
      await app.close();
    },
  );
}
