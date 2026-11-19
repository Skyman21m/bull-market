import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart' show P2pWalletBitcoinRate, P2pWalletRateRead;
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/src/presentation/payout_rate_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/trade/confirm_fiat_sent_dialog.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/testing.dart' show ScriptedMakerRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart' show FakeTransport, coordinator, testNow;
import 'support/harness.dart';
import 'support/make_harness.dart';

/// The dialog of « Confirm … sent » of an order made here, open at 9 while the order changes (#209; security review of #219, C1, C2, its mutant MD): it says what the screen behind it says, from the status shown now, never from the press: the state machine's alerts first, the owner's rule only for the step shown, nothing reassuring left from before; and « Confirm » pressed while a read is refused sends nothing and the screen says so. Over the real path (`MakeOrderUsecase`, `WatchTradeUsecase`, `TradeReader`, `ChatStepActionUsecase`, a `TradeCubit` built as the locator builds it, a `PayoutRateCubit` over the real rule, the real `TradeScreen`), the coordinator played by `ScriptedMakerCoordinator`, made hostile through `orderChanges`; nothing paid, no network.
void main() {
  const termsChanged =
      'The terms of the order are not those of the order taken.';
  const advice =
      'To follow this order safely, open it in the official RoboSats app with your Garage Key, and contact Temple of Sats if something looks wrong.';
  const notSentRefused =
      'Nothing was sent: the order read just now carries the alert shown above.';

  /// An order of 100 EUR made here, its bond locked, taken, the escrow locked: 8, the payout invoice asked (kept for 9).
  Future<(MakeHarness, TradeRecord)> madeAt8(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390, 2400) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final harness = await tester.runAsync(MakeHarness.start);
    if (harness == null) fail('no harness');
    final record = await tester.runAsync(() async {
      final made = await harness.makeOrder();
      final record = switch (made) {
        Ok(value: MakeStarted(:final record)) => record,
        _ => throw StateError('$made'),
      };
      final id = record.orderId;
      harness.coordinator
        ..lockMakerBond(id)
        ..take(id, harness.robot(4))
        ..lockEscrow(id);
      return record;
    });
    if (record == null) fail('no record');
    return (harness, record);
  }

  /// The trade screen of [record], its cubits built as the locator builds them, the Bull wallet's price being [price] at each read.
  Future<(TradeCubit, PayoutRateCubit)> mount(
    WidgetTester tester,
    MakeHarness harness,
    TradeRecord record, {
    required FutureOr<P2pWalletBitcoinRate> Function() price,
  }) async {
    final trade = TradeCubit(
      record,
      harness.watch.execute,
      harness.cancel.execute,
      confirmFiatSent: harness.chat.confirmFiatSent,
      confirmFiatReceived: harness.chat.confirmFiatReceived,
      lastStored: harness.watch.lastStored,
      undoFiatSent: harness.chat.undoFiatSent,
      startDispute: harness.chat.startDispute,
      rate: harness.chat.rate,
      pause: harness.pause.execute,
      pauseRunning: harness.pause.running,
      pauseUncertainty: harness.pause.uncertainty,
    )..start();
    final rate = PayoutRateCubit(
      record,
      terms: (record) async => switch (await harness.reader.open(record)) {
        TradeOpened(:final trade) => switch (trade.terms.side) {
          MadeSide(:final maker) => maker,
          _ => null,
        },
        _ => null,
      },
      price: (_, _) async => await price(),
      memory: PayoutRateMemory(),
      now: () => harness.now,
    );
    final reads = FakeTransport();
    final page = TradeOrderPageCubit(
      coordinator('temple'),
      RobosatsNetwork.testnet,
      FetchCoordinatorInfoUsecase(CoordinatorClient(reads)).execute,
      FindPublicOrderUsecase(
        CoordinatorClient(reads, clock: () => testNow),
      ).execute,
    );
    addTearDown(page.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        localizationsDelegates: P2pLocalizations.localizationsDelegates,
        supportedLocales: P2pLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: trade),
              BlocProvider.value(value: page),
              BlocProvider.value(value: rate),
            ],
            child: TradeScreen(
              now: () => harness.now,
              coordinatorDetails: (_) => throw StateError('not opened'),
              checksPayoutRate: true,
            ),
          ),
        ),
      ),
    );
    return (trade, rate);
  }

  Future<void> settleBoth(WidgetTester tester, MakeHarness harness) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(harness.settle);
      await tester.pump();
    }
  }

  List<String> textsIn(WidgetTester tester, Finder finder) => [
    for (final text in tester.widgetList<Text>(
      find.descendant(of: finder, matching: find.byType(Text)),
    ))
      text.data ?? text.textSpan?.toPlainText() ?? '',
  ];

  List<String> dialogTexts(WidgetTester tester) =>
      textsIn(tester, find.byType(ConfirmFiatSentDialog));

  bool anyContains(List<String> texts, String words) =>
      texts.any((text) => text.contains(words));

  /// 8 shown (the invoice kept), then 9, the dialog of « Confirm 100 EUR sent » opened by a real tap.
  Future<(MakeHarness, TradeRecord, TradeCubit, PayoutRateCubit)> dialogAt9(
    WidgetTester tester, {
    FutureOr<P2pWalletBitcoinRate> Function()? price,
  }) async {
    final (harness, record) = await madeAt8(tester);
    final (trade, rate) = await mount(
      tester,
      harness,
      record,
      price: price ?? () => P2pWalletRateRead(91711.15),
    );
    await settleBoth(tester, harness);
    expect(trade.state.seen?.status, isA<WaitingForPayout>());
    // Into the chat, as the reference moves it once the payout is in.
    harness.coordinator.order(record.orderId).status = 9;
    await tester.runAsync(() => harness.elapse(const Duration(minutes: 3)));
    await settleBoth(tester, harness);
    expect(trade.state.seen?.status, isA<Chatting>());
    final confirm = find.textContaining('Confirm 100 EUR sent');
    await tester.ensureVisible(confirm);
    await tester.pump();
    await tester.tap(confirm);
    await settleBoth(tester, harness);
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmFiatSentDialog), findsOneWidget);
    final honest = dialogTexts(tester);
    expect(anyContains(honest, 'You receive'), isTrue);
    expect(anyContains(honest, termsChanged), isFalse);
    return (harness, record, trade, rate);
  }

  /// « Confirm » of the dialog, by a real tap.
  Future<void> tapDialogConfirm(WidgetTester tester, MakeHarness h) async {
    final go = find.descendant(
      of: find.byType(ConfirmFiatSentDialog),
      matching: find.text('Confirm'),
    );
    expect(go, findsOneWidget);
    await tester.tap(go);
    await tester.pump();
    await settleBoth(tester, h);
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> leaveApp(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  Future<void> backToApp(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  int confirms(MakeHarness harness) => harness.coordinator.received
      .where((kind) => kind == ScriptedMakerRequest.confirm)
      .length;

  Future<void> close(
    WidgetTester tester,
    TradeCubit trade,
    PayoutRateCubit rate,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(trade.close);
    await tester.runAsync(rate.close);
  }

  testWidgets(
    'the app left with the dialog open (to send the fiat) and back while the coordinator shows 1,000 EUR for the 100 asked: the dialog says the alert and what to do, nothing of the comparison before; « Confirm » sends nothing and the wait says so (C1, C2)',
    (tester) async {
      final (harness, record, trade, rate) = await dialogAt9(tester);
      await leaveApp(tester);
      await settleBoth(tester, harness);
      harness.coordinator.orderChanges[record.orderId] = {
        'amount': '1000.00000000',
      };
      await tester.runAsync(() => harness.elapse(const Duration(minutes: 4)));
      await backToApp(tester);
      await settleBoth(tester, harness);
      expect(trade.state.seen?.status, isA<StatusUnknown>());
      expect(trade.state.seen?.status.has<TradeTermsChanged>(), isTrue);
      expect(find.byType(ConfirmFiatSentDialog), findsOneWidget);
      final texts = dialogTexts(tester);
      expect(anyContains(texts, termsChanged), isTrue);
      expect(anyContains(texts, advice), isTrue);
      expect(anyContains(texts, 'You receive'), isFalse);
      expect(anyContains(texts, 'are worth'), isFalse);
      expect(anyContains(texts, 'do not add up'), isFalse);
      expect(anyContains(texts, '1,000'), isFalse);
      // The alerts first, before the reference's text.
      expect(
        texts.indexWhere((t) => t.contains(termsChanged)),
        lessThan(texts.indexWhere((t) => t.contains('Confirming will'))),
      );
      // « Confirm » goes (nothing blocked), the use case reads the order again, refused: nothing sent, said on the wait.
      await tapDialogConfirm(tester, harness);
      expect(confirms(harness), 0);
      expect(harness.coordinator.order(record.orderId).status, 9);
      expect(find.byType(ConfirmFiatSentDialog), findsNothing);
      expect(find.text(termsChanged), findsOneWidget);
      expect(find.text(notSentRefused), findsOneWidget);
      expect(find.textContaining('moved on'), findsNothing);
      await close(tester, trade, rate);
    },
  );

  testWidgets(
    'the dialog open, the next read refused while the watch runs (1,000 EUR for the 100 asked): the alert of terms changed in the dialog, never « do not add up »; « Confirm » sends nothing and says why (C2)',
    (tester) async {
      final (harness, record, trade, rate) = await dialogAt9(tester);
      harness.coordinator.orderChanges[record.orderId] = {
        'amount': '1000.00000000',
      };
      await tester.runAsync(() => harness.elapse(const Duration(minutes: 3)));
      await settleBoth(tester, harness);
      expect(trade.state.seen?.status.has<TradeTermsChanged>(), isTrue);
      final texts = dialogTexts(tester);
      expect(anyContains(texts, termsChanged), isTrue);
      expect(anyContains(texts, 'do not add up'), isFalse);
      expect(anyContains(texts, '1,000'), isFalse);
      await tapDialogConfirm(tester, harness);
      expect(confirms(harness), 0);
      expect(harness.coordinator.order(record.orderId).status, 9);
      expect(find.text(notSentRefused), findsOneWidget);
      await close(tester, trade, rate);
    },
  );

  testWidgets(
    'the dialog open, the coordinator changes the premium at 9: the dialog says the alert the screen shows (C2)',
    (tester) async {
      final (harness, record, trade, rate) = await dialogAt9(tester);
      harness.coordinator.orderChanges[record.orderId] = {'premium': '7.00'};
      await tester.runAsync(() => harness.elapse(const Duration(minutes: 3)));
      await settleBoth(tester, harness);
      expect(trade.state.seen?.status.has<TradeTermsChanged>(), isTrue);
      expect(find.byType(ConfirmFiatSentDialog), findsOneWidget);
      final texts = dialogTexts(tester);
      expect(anyContains(texts, termsChanged), isTrue);
      expect(
        texts.indexWhere((t) => t.contains(termsChanged)),
        lessThan(texts.indexWhere((t) => t.contains('Confirming will'))),
      );
      await close(tester, trade, rate);
    },
  );

  testWidgets(
    'the dialog open, the order moves to 10 from another client: the rule\'s line goes from the dialog as from the screen; « Confirm » sends nothing, the confirmation recorded already (C1)',
    (tester) async {
      final (harness, record, trade, rate) = await dialogAt9(tester);
      harness.coordinator.order(record.orderId)
        ..status = 10
        ..fiatSent = true;
      await tester.runAsync(() => harness.elapse(const Duration(minutes: 3)));
      await settleBoth(tester, harness);
      expect(trade.state.seen?.status, isA<Chatting>());
      expect(rate.state, isA<PayoutRateNone>());
      expect(find.byType(ConfirmFiatSentDialog), findsOneWidget);
      final texts = dialogTexts(tester);
      expect(anyContains(texts, 'You receive'), isFalse);
      expect(anyContains(texts, 'are worth'), isFalse);
      // The order read again shows « fiat sent » recorded already: done, nothing sent again; the screen at 10.
      await tapDialogConfirm(tester, harness);
      expect(confirms(harness), 0);
      expect(find.textContaining('(5/5)'), findsOneWidget);
      await close(tester, trade, rate);
    },
  );

  testWidgets(
    'the dialog open, the app back after more than 3 minutes: the Bull wallet\'s price read again lands while the dialog is open, its red warning in the dialog (the review\'s mutant MD)',
    (tester) async {
      Completer<P2pWalletBitcoinRate>? hold;
      final (harness, _, trade, rate) = await dialogAt9(
        tester,
        price: () => hold?.future ?? P2pWalletRateRead(91711.15),
      );
      hold = Completer<P2pWalletBitcoinRate>();
      await leaveApp(tester);
      await tester.runAsync(() => harness.elapse(const Duration(minutes: 4)));
      await backToApp(tester);
      await settleBoth(tester, harness);
      expect(anyContains(dialogTexts(tester), 'fewer sats than that'), isFalse);
      // The Bull wallet's price now half: twice the sats expected, the red warning.
      hold.complete(P2pWalletRateRead(45000));
      await settleBoth(tester, harness);
      expect(anyContains(dialogTexts(tester), 'fewer sats than that'), isTrue);
      await close(tester, trade, rate);
    },
  );
}
