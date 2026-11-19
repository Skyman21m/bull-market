import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart' show FakeTransport, coordinator, testNow;
import 'support/harness.dart';
import 'support/make_harness.dart';
import 'support/trade_harness.dart' show TradeHarness;

/// A read refused because the coordinator shows another amount than the fixed one asked here (#211, security review of #183, R8): over the real path, never a status built by hand nor an order attached by the test (the real `MakeOrderUsecase`, `WatchTradeUsecase`, `TradeReader`, a `TradeCubit` built as the locator builds it, the real `TradeScreen`), the coordinator played by `ScriptedMakerCoordinator`, as the reference answers a maker, then hostile through its `orderChanges`; nothing paid, no network.
///
/// The waiting screen says the alert the status carries, with the words it has under a contract and the advice to open the order in the official app; no figure of the coordinator, no comparison, no button; once the coordinator answers honestly again, the contract is back with « contradicted itself ».
void main() {
  const termsChanged =
      'The terms of the order are not those of the order taken.';
  const advice =
      'To follow this order safely, open it in the official RoboSats app with your Garage Key, and contact Temple of Sats if something looks wrong.';
  const reading = 'Your robot is reading the order from Temple of Sats';

  /// An order of 100 EUR made, its bond locked, taken: 6; then 8 or 9 as [status] says.
  Future<(MakeHarness, TradeRecord)> madeAt(
    WidgetTester tester,
    int status,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 1600) * 3
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
        ..take(id, harness.robot(4));
      // The seller locks the escrow: 6 → 8; the chat, 9, as the reference moves it once the buyer's payout is in.
      if (status >= 8) harness.coordinator.lockEscrow(id);
      if (status == 9) harness.coordinator.order(id).status = 9;
      return record;
    });
    if (record == null) fail('no record');
    return (harness, record);
  }

  /// The trade screen of [record], its cubit built as the locator builds it over the harness's watch, cancel and last stored status.
  Future<TradeCubit> mount(
    WidgetTester tester,
    MakeHarness harness,
    TradeRecord record,
  ) async {
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
            ],
            child: TradeScreen(
              now: () => harness.now,
              coordinatorDetails: (_) => throw StateError('not opened'),
            ),
          ),
        ),
      ),
    );
    return trade;
  }

  Future<void> settleBoth(WidgetTester tester, MakeHarness harness) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(harness.settle);
      await tester.pump();
    }
  }

  for (final amount in ['1000', '10']) {
    for (final status in [6, 8, 9]) {
      testWidgets(
        'at $status, the fixed 100 EUR read as $amount: the wait says the alert and what to do, nothing of the coordinator\'s amount, no button; honest again, the contract is back',
        (tester) async {
          final (harness, record) = await madeAt(tester, status);
          final honest = await mount(tester, harness, record);
          await settleBoth(tester, harness);
          // Honest: the contract of the 100 EUR asked.
          expect(honest.state.seen?.status.warnings, isEmpty);
          expect(
            find.textContaining(
              status == 9
                  ? 'Confirm 100 EUR sent'
                  : 'Before letting you send 100 EUR',
            ),
            findsOneWidget,
          );
          // The screen left; the coordinator shows another amount at every read; the screen opened again (as the app back: the watch opens the trade anew, its first read refused as a whole).
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(honest.close);
          harness.coordinator.orderChanges[record.orderId] = {
            'amount': '$amount.00000000',
          };
          await tester.runAsync(
            () => harness.elapse(const Duration(seconds: 5)),
          );
          final trade = await mount(tester, harness, record);
          await settleBoth(tester, harness);
          final hostile = trade.state.seen;
          expect(hostile?.status, isA<StatusUnknown>());
          expect(hostile?.status.has<TradeTermsChanged>(), isTrue);
          expect(find.text(termsChanged), findsOneWidget);
          expect(find.text(advice), findsOneWidget);
          expect(find.text(reading), findsOneWidget);
          expect(find.textContaining('$amount EUR'), findsNothing);
          expect(find.textContaining('Before letting you send'), findsNothing);
          expect(find.textContaining('Confirm'), findsNothing);
          expect(find.textContaining('are worth'), findsNothing);
          expect(find.byType(TradeButton), findsNothing);
          for (final text in tester.widgetList<Text>(find.byType(Text))) {
            expect(text.data ?? '', isNot(contains('Troc')));
            expect(text.data ?? '', isNot(contains('Boltz')));
          }
          // Honest again: the contract, with the breach said and the advice.
          harness.coordinator.orderChanges.remove(record.orderId);
          await tester.runAsync(
            () => harness.elapse(const Duration(minutes: 3)),
          );
          await settleBoth(tester, harness);
          expect(trade.state.seen?.status, isNot(isA<StatusUnknown>()));
          expect(find.textContaining('contradicted itself'), findsOneWidget);
          expect(find.text(advice), findsOneWidget);
          expect(find.text(reading), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(trade.close);
        },
      );
    }
  }

  testWidgets(
    'a taker whose page is opened again while its coordinator sends a status that does not follow the trade (3 after 6): the alert above the wait, never the advice of an order made here (functional review of #219, its mutant M2)',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 1600) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final app = await tester.runAsync(TradeHarness.start);
      if (app == null) fail('no app');
      final record = await tester.runAsync(() async {
        final taken = await app.takeShown();
        app.coordinator.lockBond(app.robot(0));
        return TradeHarness.recordOf(taken);
      });
      if (record == null) fail('no record');
      expect(record.origin, isNot(TradeOrigin.madeHere));
      Future<TradeCubit> mountTaker() async {
        final trade = TradeCubit(
          record,
          app.watch.execute,
          app.cancel.execute,
          lastStored: app.watch.lastStored,
        )..start();
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
                ],
                child: TradeScreen(
                  now: () => app.now,
                  coordinatorDetails: (_) => throw StateError('not opened'),
                ),
              ),
            ),
          ),
        );
        return trade;
      }

      Future<void> settleApp() async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(app.settle);
          await tester.pump();
        }
      }

      final honest = await mountTaker();
      await settleApp();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(honest.close);
      app.coordinator.moveTo(3);
      await tester.runAsync(() => app.elapse(const Duration(seconds: 5)));
      final trade = await mountTaker();
      await settleApp();
      expect(trade.state.seen?.status, isA<StatusUnknown>());
      expect(
        find.text(
          'Temple of Sats sent a status that does not follow this trade. It was ignored.',
        ),
        findsOneWidget,
      );
      expect(find.text(reading), findsOneWidget);
      expect(find.text(advice), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(trade.close);
    },
  );
}
