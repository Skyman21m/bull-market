import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_payout_outcome.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/payout_cubit.dart';
import 'package:p2p/src/presentation/payout_rate_cubit.dart';
import 'package:p2p/src/presentation/pending_makes_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/trade/active_trades_sheet.dart';
import 'package:p2p/src/ui/trade/confirm_fiat_sent_dialog.dart';
import 'package:p2p/src/ui/trade/payout_breakdown_view.dart';
import 'package:p2p/src/ui/trade/payout_panel.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/harness.dart';
import 'support/trade_harness.dart' show tradeKey;
import 'support/trade_orders.dart' show orderJson, tradeNow;
import 'support/trade_screens.dart';

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

  testWidgets(
    'a trade taken here (buyer) on the real route and composition, with the wallet\'s port: « Submit » at 6 and « Confirm … sent » at 9 go at the first press, the Bull wallet\'s price never read (functional review of #182, U1)',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 2400) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      FakeSecureStoragePlatform().install();
      final locator = GetIt.asNewInstance();
      addTearDown(locator.reset);
      final tor = StreamController<P2pTorState>.broadcast();
      addTearDown(tor.close);
      final port = FakeP2pWalletPort(Ok(Sats.fromInt(50000)))
        ..rate = P2pWalletRateRead(91711.15);
      setUpP2pForTesting(
        locator,
        transport: FakeTransport(network: RobosatsNetwork.mainnet),
        torStates: () => tor.stream,
        clock: () => tradeNow,
        garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
        wallet: port,
      );
      final statuses = await TradeScreenStatuses.make();
      final six = await statuses.waitingForBoth();
      final nine = await statuses.chatting();
      final taken = TradeScreenStatuses.record;
      expect(taken.origin, TradeOrigin.takenHere);
      // The invoice of what the coordinator asks at 6 with the default routing budget, made by the test from fixed bytes (as `payout_panel_screen_test.dart`).
      final invoice = Bolt11TestInvoice(
        network: Bolt11Network.mainnet,
        sats: 106606,
        seed: 70,
        createdAt: tradeNow,
        expiry: const Duration(days: 2),
      );
      final reader = Bolt11Reader(Bolt11TestDecoder([invoice]));
      final watch = StreamController<TradeWatchState>.broadcast();
      addTearDown(watch.close);
      final sent = <CheckedPayout>[];
      final fiatSent = <TradeSeen>[];
      // The trade's watch, the payout's send and « fiat sent » played by the test; the rule's cubit, the wallet's cubits and the rest are the composition's.
      locator
        ..unregister<TradeCubit>()
        ..registerFactoryParam<TradeCubit, TradeRecord, void>(
          (record, _) => TradeCubit(
            record,
            (record, {signals = const Stream.empty(), onScreen = true}) {
              signals.listen((_) {});
              return watch.stream;
            },
            (record, seen, {bondLoss}) => Completer<Never>().future,
            confirmFiatSent: (record, seen, {onProgress}) {
              fiatSent.add(seen);
              return Completer<Never>().future;
            },
          ),
        )
        ..unregister<PayoutCubit>()
        ..registerFactoryParam<PayoutCubit, TradeRecord, void>(
          (record, _) => PayoutCubit(
            record,
            PayoutAsk.of,
            (record, seen, destination) => switch (PayoutAsk.of(record, seen)) {
              Err(:final failure) => Err(failure),
              Ok(:final value) => value.check(
                destination,
                now: tradeNow,
                reader: reader,
              ),
            },
            (record, shown, {onProgress}) async {
              sent.add(shown);
              return Ok(PayoutGiven(record, six));
            },
            (_) => () {},
            now: () => tradeNow,
          ),
        );
      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          localizationsDelegates: P2pLocalizations.localizationsDelegates,
          supportedLocales: P2pLocalizations.supportedLocales,
          home: Scaffold(
            body: P2pRouter.tradePage(locator, P2pTradeRouteArgs(taken)),
          ),
        ),
      );
      await tester.pump();
      // The rule's cubit is above the screen and its check given to both buttons, for a taken trade too.
      expect(
        tester.widget<TradeScreen>(find.byType(TradeScreen)).checksPayoutRate,
        isTrue,
      );
      watch.add(TradeScreenStatuses.watched(six));
      await tester.pump();
      await tester.pump();
      await tester.enterText(
        find.byKey(PayoutPanel.invoiceField),
        invoice.text,
      );
      await tester.pump();
      final submit = find.widgetWithText(TradeButton, 'Submit');
      await tester.ensureVisible(submit);
      await tester.pump();
      await tester.tap(submit);
      await tester.pump();
      await tester.pump();
      expect(sent, hasLength(1));
      expect(sent.single.text, invoice.text);

      watch.add(TradeScreenStatuses.watched(nine));
      await tester.pump();
      await tester.pump();
      final confirm = find.widgetWithText(TradeButton, 'Confirm 100 EUR sent');
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      await tester.pump();
      expect(find.byType(ConfirmFiatSentDialog), findsOneWidget);
      // The dialog's « Confirm », just shown, ignores taps for a moment (security review of #291, B1): the user's first press comes later.
      await tester.pump(MovedTapGuard.afterMove);
      await tester.tap(
        find.descendant(
          of: find.byType(ConfirmFiatSentDialog),
          matching: find.text('Confirm'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(fiatSent, hasLength(1));
      expect(port.ratesAsked, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 31));
    },
  );

  // The breakdown of the buyer's payout (#228) for a trade taken here, on the trade page as the route builds it over the real composition with the wallet's port: the rule does not run for a taker, so no first line and no gap; the coordinator's figures, its fee, the routing budget, the invoice, and what reaches the wallet once it made the invoice. Then amounts that do not agree: no breakdown at all, the alert alone, and the reference's « Submit invoice for … Sats » so that the amount to ask stays given.
  for (final locale in const [Locale('en'), Locale('fr')]) {
    testWidgets(
      'a trade taken here (buyer) at 6, ${locale.languageCode}: the breakdown without the Bull wallet\'s price, « Generate Invoice » adding what reaches the wallet; amounts that do not agree: the alert alone (#228)',
      (tester) async {
        final english = locale.languageCode == 'en';
        // A negative one with the minus sign (U+2212), as the screens write it (#250).
        String sats(int value) => NumberFormat.decimalPattern(
          locale.languageCode,
        ).format(value).replaceFirst('-', '\u2212');
        tester.view
          ..physicalSize = const Size(390, 2400) * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        FakeSecureStoragePlatform().install();
        final locator = GetIt.asNewInstance();
        addTearDown(locator.reset);
        final tor = StreamController<P2pTorState>.broadcast();
        addTearDown(tor.close);
        final port = FakeP2pWalletPort(Ok(Sats.fromInt(50000)))
          ..rate = P2pWalletRateRead(91711.15);
        setUpP2pForTesting(
          locator,
          transport: FakeTransport(network: RobosatsNetwork.mainnet),
          torStates: () => tor.stream,
          clock: () => tradeNow,
          garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
          wallet: port,
        );
        final statuses = await TradeScreenStatuses.make();
        final six = await statuses.waitingForBoth();
        final disagree = await statuses.read(
          six,
          orderJson(6, changes: {'invoice_amount': 100000}),
          after: const Duration(seconds: 60),
        );
        final taken = TradeScreenStatuses.record;
        final invoice = Bolt11TestInvoice(
          network: Bolt11Network.mainnet,
          sats: 106606,
          seed: 71,
          createdAt: tradeNow,
          expiry: const Duration(days: 2),
        );
        final reader = Bolt11Reader(Bolt11TestDecoder([invoice]));
        final watch = StreamController<TradeWatchState>.broadcast();
        addTearDown(watch.close);
        locator
          ..unregister<TradeCubit>()
          ..registerFactoryParam<TradeCubit, TradeRecord, void>(
            (record, _) => TradeCubit(record, (
              record, {
              signals = const Stream.empty(),
              onScreen = true,
            }) {
              signals.listen((_) {});
              return watch.stream;
            }, (record, seen, {bondLoss}) => Completer<Never>().future),
          )
          ..unregister<PayoutCubit>()
          ..registerFactoryParam<PayoutCubit, TradeRecord, void>(
            (record, _) => PayoutCubit(
              record,
              PayoutAsk.of,
              (record, seen, destination) =>
                  switch (PayoutAsk.of(record, seen)) {
                    Err(:final failure) => Err(failure),
                    Ok(:final value) => value.check(
                      destination,
                      now: tradeNow,
                      reader: reader,
                    ),
                  },
              (record, shown, {onProgress}) => Completer<Never>().future,
              (_) => () {},
              now: () => tradeNow,
            ),
          );
        await tester.pumpWidget(
          MaterialApp(
            theme: testTheme,
            locale: locale,
            localizationsDelegates: P2pLocalizations.localizationsDelegates,
            supportedLocales: P2pLocalizations.supportedLocales,
            home: Scaffold(
              body: P2pRouter.tradePage(locator, P2pTradeRouteArgs(taken)),
            ),
          ),
        );
        await tester.pump();
        watch.add(TradeScreenStatuses.watched(six));
        await tester.pump();
        await tester.pump();
        String row(Key key) => [
          for (final text in tester.widgetList<Text>(
            find.descendant(of: find.byKey(key), matching: find.byType(Text)),
          ))
            text.data ?? '',
        ].last;
        // 106,900 sats fixed at the take, the taker fee of 0.175 % (187), 1,000 ppm of routing budget (107): on arrival the sats paid, the routing fees and what will be received, the invoice's amount (#250); no gap, the rule not on this page.
        expect(find.byKey(PayoutCheckLines.gapRow), findsNothing);
        expect(row(PayoutBreakdownView.givenRow), sats(106713));
        expect(row(PayoutBreakdownView.feesRow), sats(-107));
        expect(row(PayoutBreakdownView.receivedRow), sats(106606));
        expect(find.byKey(PayoutPanel.detail), findsNothing);
        // The detail: the coordinator's fee, the routing budget, « Your invoice ».
        final toggle = find.byKey(PayoutPanel.detailToggle);
        await tester.ensureVisible(toggle);
        await tester.pump();
        await tester.tap(toggle);
        await tester.pump();
        expect(find.byKey(PayoutBreakdownDetail.valueRow), findsNothing);
        expect(row(PayoutBreakdownDetail.feeRow), sats(187));
        expect(row(PayoutBreakdownDetail.budgetRow), sats(-107));
        expect(row(PayoutBreakdownDetail.invoiceRow), sats(106606));
        expect(find.byKey(PayoutBreakdownDetail.swapRow), findsNothing);
        port.scriptInvoice(
          Ok(
            P2pWalletInvoice(
              bolt11: invoice.text,
              amount: Sats.fromInt(106606),
              expiresAt: tradeNow.add(const Duration(days: 2)),
              received: Sats.fromInt(106400),
            ),
          ),
        );
        final generate = find.text(
          english ? 'Generate Invoice' : 'Générer une facture',
        );
        await tester.ensureVisible(generate);
        await tester.pump();
        await tester.tap(generate);
        await tester.pump();
        await tester.pump();
        expect(row(PayoutBreakdownView.feesRow), sats(-313));
        expect(row(PayoutBreakdownView.receivedRow), sats(106400));
        expect(row(PayoutBreakdownDetail.swapRow), sats(-206));
        // The copy of « Your invoice » writes the amount asked, as the reference's copy.
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.tap(
          find.descendant(
            of: find.byKey(PayoutBreakdownDetail.invoiceRow),
            matching: find.byType(IconButton),
          ),
        );
        await tester.pump();
        expect(copied, '106606');
        await tester.pump(const Duration(seconds: 3));

        // Amounts that do not agree: the alert alone, no line of the breakdown, the amount to ask still given.
        watch.add(TradeScreenStatuses.watched(disagree));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(find.byType(PayoutBreakdownView), findsNothing);
        expect(
          find.text(
            english
                ? 'Submit invoice for 106,606 sats'
                : 'Soumettre la facture pour ${sats(106606)} sats',
          ),
          findsOneWidget,
        );
        expect(port.ratesAsked, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 31));
      },
    );
  }
}
