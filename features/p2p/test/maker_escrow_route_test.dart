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
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:bull_ui/bull_ui.dart' show BullTheme;
import 'package:p2p/src/ui/trade/pay_confirmation_card.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/price_check_lines.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';
import 'support/lean_confirmation.dart';
import 'support/make_harness.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// A maker seller's escrow on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`), #187: the real router, records, use cases, state machine and trade screen, the coordinator played by `ScriptedMakerCoordinator` (never a real one), the wallet `FakeP2pWalletPort`.
///
/// The sell order is made by the composition's own make use case, as « Create order » makes it (the form's gestures are `maker_sell_route_test.dart`'s, #188). The escrow panel is the one a taker seller has had since #97, with a maker seller's confirmation since #188: its « Pay » passes the contract it states, built from the quote it pays.
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
  static Future<_App> start(
    WidgetTester tester, {
    (double, double)? range,
    double? takenAmount,
    bool sell = true,
    bool taken = true,
    String currency = 'EUR',
    Locale locale = const Locale('en'),
  }) async {
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
    final ofOrder = switch (RobosatsCurrency.fromCode(currency)) {
      final found? => found,
      null => throw StateError('no currency $currency'),
    };
    coordinator.prices[ofOrder.id] = 50000;
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
    await tester.pumpWidget(routerHarness(router, locale: locale));
    tor.add(P2pTorState.ready);
    await app.settle();
    final request = MakeHarness.request(
      sell: sell,
      range: range,
      currency: ofOrder,
    );
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
    if (!taken) return app;
    coordinator
      ..lockMakerBond(app.record.orderId)
      ..take(
        app.record.orderId,
        TradeHarness.robotsOf(_net)[5],
        amount: takenAmount,
      );
    return app;
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle();
    await tester.pump(const Duration(seconds: 61));
  }
}

/// Waits, the clock running, until [done].
Future<void> _until(_App app, bool Function() done) async {
  for (var i = 0; i < 240; i++) {
    if (done()) return;
    app.advance(const Duration(milliseconds: 250));
    await app.tester.pump(const Duration(milliseconds: 250));
  }
  fail('never done');
}

/// The coordinator shows the order with another premium for a read, then puts its own back (#231): the alert of terms changed comes and goes, the trace of terms shown otherwise stays.
Future<void> _termsShownOtherwise(_App app) async {
  final alert = find.text(
    'The terms of the order are not those of the order taken.',
  );
  app.coordinator.orderChanges[app.record.orderId] = {'premium': '9.00'};
  await _until(app, () => alert.evaluate().isNotEmpty);
  app.coordinator.orderChanges.remove(app.record.orderId);
  await _until(app, () => alert.evaluate().isEmpty);
  await app.settle();
}

/// A quote of [invoice] scripted, then « Pay with this wallet » ([pay], in the app's language): its confirmation, and the quote it states.
Future<P2pWalletQuote> _confirm(
  _App app,
  Bolt11TestInvoice invoice, {
  String pay = 'Pay with this wallet',
  String goBack = 'Go back',
}) async {
  final checked = checkedBolt11InvoiceForTesting(
    bolt11: invoice.text,
    amount: invoice.facts.amount,
    network: _net,
    paymentHash: invoice.facts.paymentHash,
    expiresAt: invoice.facts.createdAt.add(invoice.facts.expiry),
    now: DateTime.utc(2026, 11, 14, 9),
  );
  if (checked == null) fail('not a payable invoice');
  final quote = P2pWalletQuote(
    invoice: checked,
    payin: Sats(checked.amount.value + BigInt.from(500)),
    networkFee: Sats.fromInt(27),
    balance: Sats.fromInt(5000000),
    quotedAt: DateTime.utc(2026, 11, 14, 9),
  );
  app.wallet.scriptQuote(Ok(quote));
  await _tap(app.tester, find.text(pay));
  await app.settle();
  expect(find.text(goBack), findsOneWidget);
  return quote;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// Opens the confirmation's detail (« Show details », #250), so that what it says, or does not say, is on screen.
Future<void> _detail(WidgetTester tester) async {
  await _tap(tester, find.text('Show details'));
  await tester.pump();
  expect(find.text('Hide details'), findsOneWidget);
}

void main() {
  testWidgets(
    'contract 0: « Pay with this wallet » offered for a maker seller\'s escrow, and the panel\'s « Pay » pays it under the contract its confirmation states (#188)',
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
      // The confirmation of contract 0: no new contract, no alert, the comparison with the Bull wallet's price, the fee included (in the detail, #250).
      expect(find.textContaining('New contract'), findsNothing);
      expect(find.text('Gap to the Bull price (indicative)'), findsOneWidget);
      await _detail(tester);
      expect(
        find.text(
          'Bull Wallet redoes the calculation with its own price: 100 EUR at 50,000 EUR/BTC, premium included, come to 196,078 sats. The coordinator asks 0.03% more, its fees included.',
        ),
        findsOneWidget,
      );
      await _tap(tester, confirm);
      await app.settle();
      // Paid once, under contract 0, the very quote confirmed.
      expect(app.wallet.paid, hasLength(1));
      expect(
        find.text('The order moved on before the payment. Nothing was paid.'),
        findsNothing,
      );
      final rows = switch (await app.wait(
        () => app.locator<TradePaymentRepository>().paymentsOfTrade(app.record),
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(
        [for (final row in rows) (row.step, row.take)],
        [(InvoiceStep.escrow, 0)],
      );
      await app.close();
    },
  );

  testWidgets(
    'a new contract while the escrow of contract 0, paid from this wallet, is held: « Pay with this wallet » is offered, no lock',
    (tester) async {
      final app = await _App.start(tester);
      // Contract 0's escrow paid from this wallet through the composition's own use case, with the confirmation of its contract (as the panel gives it since #188), from the status the trade screen stored.
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
      // No lock (the owner's decision of 2026-11-19): contract 1 is offered; the alert with contract 0's sats is its confirmation's (`maker_sell_route_test.dart`).
      expect(find.text('Pay with this wallet'), findsOneWidget);
      expect(
        find.textContaining('Pay this collateral with another wallet'),
        findsNothing,
      );
      expect(app.wallet.quoted, hasLength(1));
      expect(app.wallet.paid, hasLength(1));
      await app.close();
    },
  );

  group(
    'beside the trace of terms shown otherwise (#231) or of a payout not given from this wallet (#204), an order made here: no comparison within the threshold (security review of #249, C1 and C2)',
    () {
      testWidgets('the maker bond at 0', (tester) async {
        final app = await _App.start(tester, taken: false);
        await app.openTrade();
        expect(find.text('Pay with this wallet'), findsOneWidget);
        await _termsShownOtherwise(app);
        final bond = app.coordinator.order(app.record.orderId).bond;
        if (bond == null) fail('no bond');
        await _confirm(app, bond);
        expect(app.wallet.ratesAsked, isNotEmpty);
        expect(find.text('Gap to the Bull price (indicative)'), findsNothing);
        await _detail(tester);
        expect(find.textContaining('this bond is worth'), findsNothing);
        expect(find.textContaining('A small gap is normal'), findsNothing);
        expect(app.wallet.paid, isEmpty);
        await app.close();
      });

      testWidgets('a maker seller\'s escrow', (tester) async {
        final app = await _App.start(tester);
        await app.openTrade();
        expect(find.text('Pay with this wallet'), findsOneWidget);
        await _termsShownOtherwise(app);
        final escrow = app.coordinator.order(app.record.orderId).escrow;
        if (escrow == null) fail('no escrow invoice');
        await _confirm(app, escrow);
        expect(app.wallet.ratesAsked, isNotEmpty);
        expect(find.text('Gap to the Bull price (indicative)'), findsNothing);
        await _detail(tester);
        expect(find.textContaining('100 EUR at'), findsNothing);
        expect(find.textContaining('100 EUR are worth'), findsNothing);
        expect(find.textContaining('A small gap is normal'), findsNothing);
        expect(app.wallet.paid, isEmpty);
        await app.close();
      });

      testWidgets('a maker buyer\'s payout before « Submit »', (tester) async {
        final app = await _App.start(tester, sell: false);
        await app.openTrade();
        // At 6 the comparison is the payout breakdown's gap line (#250).
        final line = find.text('Gap to the Bull price (indicative)');
        await _until(app, () => line.evaluate().isNotEmpty);
        await _termsShownOtherwise(app);
        await _until(app, () => line.evaluate().isEmpty);
        expect(line, findsNothing);
        await app.close();
      });

      testWidgets('a maker buyer at 9, its payout not given from Bull Market', (
        tester,
      ) async {
        final app = await _App.start(tester, sell: false);
        await app.openTrade();
        // At 6 the comparison is the payout breakdown's gap line (#250); at 9, the rule's sentence.
        await _until(
          app,
          () => find
              .text('Gap to the Bull price (indicative)')
              .evaluate()
              .isNotEmpty,
        );
        final line = find.textContaining('At the Bull wallet\'s price');
        app.coordinator.lockEscrow(app.record.orderId);
        app.coordinator.order(app.record.orderId).status = 9;
        await _until(
          app,
          () => find
              .text(
                'This contract\'s payout invoice or address was not given from Bull Market: check where the sats will arrive.',
              )
              .evaluate()
              .isNotEmpty,
        );
        await app.settle();
        expect(line, findsNothing);
        await app.close();
      });
    },
  );

  group(
    'an alert never silences another (security review of #249, C5): a red comparison stays beside an alert of the state machine, « Pay » offered, an order made here',
    () {
      Finder pay(String total) => find.text('Pay $total sats');

      testWidgets(
        'a maker seller\'s red escrow: beside an alert of the amounts, then of terms changed and its trace',
        (tester) async {
          final app = await _App.start(tester);
          // The Bull wallet's price ten times the coordinator's: the escrow ten times the sats expected.
          app.wallet.rate = P2pWalletRateRead(500000);
          await app.openTrade();
          final escrow = app.coordinator.order(app.record.orderId).escrow;
          if (escrow == null) fail('no escrow invoice');
          await _confirm(app, escrow);
          // The red alert's two lines (#250): 100 EUR at 500,000 EUR/BTC with +2 % come to 19,607 sats.
          final red = find.text(
            'Bull Wallet expected 19,607 sats, the coordinator asks 196,127.',
          );
          expect(red, findsOneWidget);
          expect(find.text('Gap against you'), findsOneWidget);
          final amounts = find.text(
            'The amounts Temple of Sats gives do not add up.',
          );
          app.coordinator.orderChanges[app.record.orderId] = {
            'trade_satoshis': 100000,
          };
          await _until(app, () => amounts.evaluate().isNotEmpty);
          await app.settle();
          expect(red, findsOneWidget);
          expect(find.text('Gap against you'), findsOneWidget);
          app.coordinator.orderChanges.remove(app.record.orderId);
          await _until(app, () => amounts.evaluate().isEmpty);
          await _termsShownOtherwise(app);
          expect(red, findsOneWidget);
          expect(pay('196,654'), findsOneWidget);
          expect(app.wallet.paid, isEmpty);
          await app.close();
        },
      );

      for (final (currency, rate, line) in [
        (
          'EUR',
          const P2pWalletRateUnavailable() as P2pWalletBitcoinRate,
          'Amount not checked',
        ),
        (
          'CHF',
          const P2pWalletRateNotPriced() as P2pWalletBitcoinRate,
          'not quoted',
        ),
      ]) {
        testWidgets(
          'a maker seller\'s escrow in $currency, its line « rate not checked » beside an alert of terms changed: it stays (security review of #249, C6)',
          (tester) async {
            final app = await _App.start(tester, currency: currency);
            app.wallet.rate = rate;
            await app.openTrade();
            final escrow = app.coordinator.order(app.record.orderId).escrow;
            if (escrow == null) fail('no escrow invoice');
            await _confirm(app, escrow);
            final shown = find.text(line);
            expect(shown, findsOneWidget);
            final terms = find.text(
              'The terms of the order are not those of the order taken.',
            );
            app.coordinator.orderChanges[app.record.orderId] = {
              'premium': '9.00',
            };
            await _until(app, () => terms.evaluate().isNotEmpty);
            await app.settle();
            expect(shown, findsOneWidget);
            app.coordinator.orderChanges.remove(app.record.orderId);
            await _until(app, () => terms.evaluate().isEmpty);
            await app.settle();
            expect(shown, findsOneWidget);
            expect(find.text('Go back'), findsOneWidget);
            expect(app.wallet.paid, isEmpty);
            await app.close();
          },
        );
      }

      testWidgets('the maker bond in red: beside an alert of terms changed', (
        tester,
      ) async {
        final app = await _App.start(tester, taken: false);
        app.wallet.rate = P2pWalletRateRead(500000);
        await app.openTrade();
        final bond = app.coordinator.order(app.record.orderId).bond;
        if (bond == null) fail('no bond');
        await _confirm(app, bond);
        final red = find.text('Gap against you');
        expect(red, findsOneWidget);
        final terms = find.text(
          'The terms of the order are not those of the order taken.',
        );
        app.coordinator.orderChanges[app.record.orderId] = {'premium': '9.00'};
        await _until(app, () => terms.evaluate().isNotEmpty);
        await app.settle();
        expect(red, findsOneWidget);
        app.coordinator.orderChanges.remove(app.record.orderId);
        await _until(app, () => terms.evaluate().isEmpty);
        await app.settle();
        expect(red, findsOneWidget);
        expect(find.textContaining('Pay '), findsWidgets);
        expect(app.wallet.paid, isEmpty);
        await app.close();
      });
    },
  );

  group(
    'the contract\'s amount the confirmation names (functional review of #188, C1)',
    () {
      Future<void> openConfirmation(_App app) async {
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
        app.wallet.scriptQuote(
          Ok(
            P2pWalletQuote(
              invoice: checked,
              payin: Sats(checked.amount.value + BigInt.from(500)),
              networkFee: Sats.fromInt(27),
              balance: Sats.fromInt(5000000),
              quotedAt: DateTime.utc(2026, 11, 14, 9),
            ),
          ),
        );
        await _tap(app.tester, find.text('Pay with this wallet'));
        await app.settle();
      }

      testWidgets('a range: the amount its take chose, kept with the contract', (
        tester,
      ) async {
        final app = await _App.start(
          tester,
          range: (50, 150),
          takenAmount: 120,
        );
        await app.openTrade();
        await openConfirmation(app);
        await _detail(tester);
        // 120 EUR at 50,000 EUR/BTC with +2 %: 235,294 sats.
        expect(
          find.textContaining(
            '120 EUR at 50,000 EUR/BTC, premium included, come to 235,294 sats',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('150 EUR'), findsNothing);
        await app.close();
      });

      testWidgets(
        'a fixed amount the coordinator reads otherwise, the confirmation open: the terms\' alert alone, no comparison beside it, nothing paid (security review of #188, C2)',
        (tester) async {
          final app = await _App.start(tester);
          await app.openTrade();
          await openConfirmation(app);
          await _detail(tester);
          expect(
            find.textContaining(
              '100 EUR at 50,000 EUR/BTC, premium included, come to 196,078 sats',
            ),
            findsOneWidget,
          );
          app.coordinator.orderChanges[app.record.orderId] = {
            'amount': '1000.00000000',
          };
          for (var i = 0; i < 15; i++) {
            app.advance(const Duration(seconds: 1));
            await tester.pump(const Duration(seconds: 1));
          }
          await app.settle();
          expect(
            find.text(
              'The terms of the order are not those of the order taken.',
            ),
            findsOneWidget,
          );
          // The detail still open: neither the comparison's sentence nor « A small gap is normal » (#250).
          expect(find.text('Hide details'), findsOneWidget);
          expect(find.textContaining('come to'), findsNothing);
          expect(find.textContaining('are worth'), findsNothing);
          expect(find.textContaining('fees included'), findsNothing);
          expect(find.textContaining('A small gap is normal'), findsNothing);
          expect(find.text('Gap to the Bull price (indicative)'), findsNothing);
          expect(find.textContaining('1,000 EUR'), findsNothing);
          expect(app.wallet.paid, isEmpty);
          await app.close();
        },
      );

      testWidgets(
        'a range\'s amount taken the coordinator reads otherwise, the confirmation open: no comparison and no figure of it, the state machine\'s alert alone',
        (tester) async {
          final app = await _App.start(
            tester,
            range: (50, 150),
            takenAmount: 120,
          );
          await app.openTrade();
          await openConfirmation(app);
          await _detail(tester);
          expect(
            find.textContaining(
              '120 EUR at 50,000 EUR/BTC, premium included, come to 235,294 sats',
            ),
            findsOneWidget,
          );
          app.coordinator.orderChanges[app.record.orderId] = {
            'amount': '130.00000000',
          };
          for (var i = 0; i < 15; i++) {
            app.advance(const Duration(seconds: 1));
            await tester.pump(const Duration(seconds: 1));
          }
          await app.settle();
          expect(find.text('Hide details'), findsOneWidget);
          expect(find.textContaining('come to'), findsNothing);
          expect(find.textContaining('are worth'), findsNothing);
          expect(find.textContaining('130 EUR'), findsNothing);
          expect(find.textContaining('fees included'), findsNothing);
          expect(find.textContaining('A small gap is normal'), findsNothing);
          expect(app.wallet.paid, isEmpty);
          await app.close();
        },
      );
    },
  );
  for (final locale in const [Locale('en'), Locale('fr')]) {
    final code = locale.languageCode;
    group('the lean confirmation of an order made here (#250), $code', () {
      P2pLocalizations l10nOf() => lookupP2pLocalizations(locale);

      /// The maker bond's confirmation at 0 ([bond]), or a maker seller's collateral's.
      Future<(_App, LeanConfirmation, P2pWalletQuote, Bolt11TestInvoice)> open(
        WidgetTester tester, {
        required bool bond,
        P2pWalletBitcoinRate? rate,
        String currency = 'EUR',
      }) async {
        final l10n = l10nOf();
        final app = await _App.start(
          tester,
          taken: !bond,
          currency: currency,
          locale: locale,
        );
        if (rate != null) app.wallet.rate = rate;
        await app.openTrade();
        final order = app.coordinator.order(app.record.orderId);
        final invoice = bond ? order.bond : order.escrow;
        if (invoice == null) fail('no invoice');
        final quote = await _confirm(
          app,
          invoice,
          pay: l10n.p2pPayWithThisWallet,
          goBack: l10n.p2pCommonGoBack,
        );
        return (app, LeanConfirmation(tester, locale), quote, invoice);
      }

      for (final bond in [true, false]) {
        final name = bond ? 'the maker bond' : 'a maker seller\'s collateral';
        testWidgets(
          '$name: the card on arrival, the gap « (indicative) », the detail opened and closed with the buttons still; « Pay » pays the quote shown, once',
          (tester) async {
            final (app, lean, quote, invoice) = await open(tester, bond: bond);
            final l10n = l10nOf();
            lean.expectArrival(quote, escrow: !bond);
            expect(
              lean.row(PriceCheckLines.gapRow),
              startsWith('${l10n.p2pPayoutBreakdownGap} | '),
            );
            lean.expectAboveButtons(find.byKey(PriceCheckLines.gapRow));
            await lean.toggleDetail(
              quote,
              whileOpen: () {
                lean.expectDetailRows(quote);
                final sentence = find.byKey(PayConfirmationCard.rateParagraph);
                expect(sentence, findsOneWidget);
                final words = tester.widget<Text>(
                  find.descendant(of: sentence, matching: find.byType(Text)),
                );
                // The bond keeps its sentence; a collateral asked above the sats expected, the validated one, the fee said included.
                expect(
                  words.data,
                  bond
                      ? contains(lean.formats.orderRate(50000))
                      : l10n.p2pPayRateDetail(
                          '100',
                          'EUR',
                          lean.formats.orderRate(50000),
                          lean.formats.bigSats(BigInt.from(196078)),
                          lean.formats.gapSize(BigInt.from(3)),
                        ),
                );
                expect(
                  find.byKey(PayConfirmationCard.smallGap),
                  findsOneWidget,
                );
                expect(
                  find.byKey(PayConfirmationCard.heldParagraph),
                  bond ? findsNothing : findsOneWidget,
                );
                expect(
                  find.text(
                    bond
                        ? l10n.p2pTradeHoldInvoiceBond
                        : l10n.p2pTradeHoldInvoiceEscrow('EUR'),
                  ),
                  findsOneWidget,
                );
              },
            );
            app.wallet.scriptPayment(
              Ok(
                P2pWalletPayment(
                  id: 'swap-lean',
                  paymentHash: invoice.facts.paymentHash,
                ),
              ),
            );
            final pay = lean.payOf(quote);
            await tester.ensureVisible(pay);
            await tester.pump();
            await tester.tap(pay);
            await tester.tap(pay, warnIfMissed: false);
            await app.settle();
            expect(app.wallet.paid, hasLength(1));
            final (paidInvoice, paidQuote) = app.wallet.paid.single;
            expect(paidInvoice.paymentHash, invoice.facts.paymentHash);
            expect(paidQuote.total, quote.total);
            expect(paidQuote.amount, quote.amount);
            await app.close();
          },
        );

        testWidgets(
          '$name ten times the sats expected: the red alert\'s two lines above the buttons, the explanation in the detail; « Pay » offered',
          (tester) async {
            final (app, lean, quote, _) = await open(
              tester,
              bond: bond,
              rate: P2pWalletRateRead(500000),
            );
            final l10n = l10nOf();
            lean.expectArrival(quote, escrow: !bond);
            final figures = lean.inCard(
              find.byKey(PriceCheckLines.alertFigures),
            );
            final text = tester.widget<Text>(
              find.descendant(of: figures, matching: find.byType(Text)),
            );
            final asked = lean.formats.bigSats(quote.amount.value);
            final expected = text.data?.split(' ')[3];
            if (expected == null) fail('no figure');
            lean.expectRed(
              lean.row(PriceCheckLines.alertRow).split(' | ').last,
              l10n.p2pPayAgainstFigures(expected, asked),
            );
            await lean.toggleDetail(
              quote,
              whileOpen: () {
                expect(
                  find.text(
                    l10n.p2pPayAgainstDetail(
                      lean.formats.orderRate(500000),
                      'EUR',
                      lean.formats.threshold(0.1),
                    ),
                  ),
                  findsOneWidget,
                );
                expect(find.byKey(PayConfirmationCard.smallGap), findsNothing);
              },
            );
            expect(
              tester.widget<TradeButton>(lean.payOf(quote)).onPressed,
              isNotNull,
            );
            await app.close();
          },
        );

        testWidgets(
          '$name, the Bull wallet\'s price not read: « Amount not checked » above the buttons, « Retry », the explanation in the detail; « Retry » brings the comparison',
          (tester) async {
            final (app, lean, quote, _) = await open(
              tester,
              bond: bond,
              rate: const P2pWalletRateUnavailable(),
            );
            final l10n = l10nOf();
            lean.expectArrival(quote, escrow: !bond);
            lean.expectAboveButtons(
              lean.inCard(find.text(l10n.p2pPayoutBreakdownUnverifiedLine)),
            );
            await lean.toggleDetail(
              quote,
              whileOpen: () => expect(
                find.text(l10n.p2pPayUnverifiedDetail),
                findsOneWidget,
              ),
            );
            app.wallet.rate = P2pWalletRateRead(50000);
            await _tap(tester, lean.inCard(find.text(l10n.p2pCommonRetry)));
            await app.settle();
            expect(find.text(l10n.p2pPayoutBreakdownUnverified), findsNothing);
            expect(
              lean.inCard(find.byKey(PriceCheckLines.gapRow)),
              findsOneWidget,
            );
            expect(app.wallet.paid, isEmpty);
            await app.close();
          },
        );

        testWidgets(
          '$name in a currency the Bull wallet does not price (CHF): the grey « not quoted » line alone',
          (tester) async {
            final (app, lean, quote, _) = await open(
              tester,
              bond: bond,
              currency: 'CHF',
              rate: const P2pWalletRateNotPriced(),
            );
            final l10n = l10nOf();
            lean.expectArrival(quote, escrow: !bond);
            expect(
              lean.row(PriceCheckLines.notPricedRow),
              '${l10n.p2pPayoutBreakdownGapNotPriced} | ${l10n.p2pPayoutBreakdownNotPriced}',
            );
            final value = lean.inCard(
              find.text(l10n.p2pPayoutBreakdownNotPriced),
            );
            final colors = Theme.of(
              tester.element(value),
            ).extension<BullTheme>();
            expect(tester.widget<Text>(value).style?.color, colors?.textMuted);
            expect(
              lean.inCard(find.byIcon(Icons.warning_amber_rounded)),
              findsNothing,
            );
            await lean.toggleDetail(
              quote,
              whileOpen: () {
                expect(
                  find.byKey(PayConfirmationCard.rateParagraph),
                  findsNothing,
                );
                expect(find.byKey(PayConfirmationCard.smallGap), findsNothing);
              },
            );
            await app.close();
          },
        );
      }
    });
  }
}
