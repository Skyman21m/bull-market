import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/p2p_clock.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/payout_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/trade/payout_panel.dart';
import 'package:p2p/src/ui/trade/trade_first_read_wait.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/trade/wallet_payment_section.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart' show Bolt11TestDecoder, Bolt11TestInvoice;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:robosats/robosats.dart';

import 'support/fakes.dart' show FakeTransport, coordinator, testNow;
import 'support/harness.dart';
import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

/// #152 (from #148, « the app reloads the order each time »): the trade screen when the app is hidden then shown again in the same process, as when the buyer leaves to pay the bond, or to make an invoice, in another wallet app.
///
/// The watch is played by the test, and emits on the return what the real one emits there (`back_in_app_test.dart` shows it over the real watch): the trade opened again from its stored trail, the trail's own status, not marked stored (`TradeReader.open`, `TradeStatus.beforeFirstRead`), then, once the first read over a Tor just woken comes back, the status read.
/// Each test expects what the official client does, its order page keeping what it shows while it reads again (`frontend/src/basic/OrderPage/index.tsx:76-96`).
void main() {
  final record = TradeScreenStatuses.record;
  late TradeScreenStatuses statuses;
  late TradeSeen bond;
  late TradeSeen six;

  setUpAll(() async {
    statuses = await TradeScreenStatuses.make();
    bond = await statuses.bondStep();
    six = await statuses.waitingForBoth();
  });

  /// What the real watch emits first when it opens the trade again at [shown]'s position: the stored trail's own status, with no order and not marked stored (`trade_reader.dart:192`).
  TradeWatchStatus reopenedAt(TradeSeen shown) => TradeScreenStatuses.watched(
    TradeSeen(TradeStatus.beforeFirstRead(shown.status.trail), order: null),
  );

  /// The app left for another app, then back, as Android tells it.
  Future<void> leaveAndComeBack(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  /// The trade screen's list, which scrolls.
  ScrollPosition listPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(TradeScreen),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            )
            .first,
      )
      .position;

  /// Shows the trade screen over [watch], with « Pay with this wallet » offering something (so « Pay with another wallet » starts closed, as in the APK).
  Future<void> showTrade(
    WidgetTester tester,
    _Watch watch, {
    DateTime Function()? now,
    void Function(WalletPaymentRequest request)? onWallet,
    List<TradeSeen>? cancels,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final cubit = TradeCubit(record, watch.call, (
      record,
      seen, {
      bondLoss,
    }) async {
      cancels?.add(seen);
      return Ok<CancelOutcome, CancelRefusal>(CancelDone(record, seen));
    })..start();
    addTearDown(cubit.close);
    final reads = FakeTransport();
    final page = TradeOrderPageCubit(
      coordinator('temple'),
      RobosatsNetwork.mainnet,
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
              BlocProvider.value(value: cubit),
              BlocProvider.value(value: page),
            ],
            child: TradeScreen(
              now: now ?? () => tradeNow,
              coordinatorDetails: (_) => throw StateError('not opened'),
              walletPayment: (context, request) {
                onWallet?.call(request);
                return const WalletPaymentSlot(Text('wallet slot'));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('#152: back in the app, the trade screen', () {
    testWidgets(
      'the bond with its QR code opened and scrolled to: while the first read after the return runs the bond step stays, and after it the QR code is still open and the list where it was',
      (tester) async {
        final watch = _Watch();
        await showTrade(tester, watch);
        watch.emit(TradeScreenStatuses.watched(bond));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('Pay with another wallet'));
        await tester.pump();
        expect(find.byType(QrImageView), findsOneWidget);
        await tester.ensureVisible(find.byType(QrImageView));
        await tester.pump();
        final scrolled = listPosition(tester).pixels;
        expect(scrolled, greaterThan(0));

        // The buyer leaves to pay with another wallet app, and comes back.
        await leaveAndComeBack(tester);
        expect(
          watch.listens,
          2,
          reason: 'the watch starts again on the return',
        );
        watch.emit(reopenedAt(bond));
        await tester.pump();
        await tester.pump();

        // While the first read over a Tor just woken runs.
        // Whether the invoice itself is offered meanwhile is the fix's choice (it may be paid already, the status moved): not asserted here.
        final whileReading = (
          wait: find.byType(TradeFirstReadWait).evaluate().length,
          bondPanel: find.text('You are BUYING BTC').evaluate().length,
        );

        // The read comes back with the same bond step.
        watch.emit(TradeScreenStatuses.watched(bond));
        await tester.pump();
        await tester.pump();
        final afterRead = (
          qr: find.byType(QrImageView).evaluate().length,
          offset: listPosition(tester).pixels,
        );

        // Both moments at once, so that a failure says what each drew.
        expect(
          (whileReading: whileReading, afterRead: afterRead),
          (
            whileReading: (wait: 0, bondPanel: 1),
            afterRead: (qr: 1, offset: scrolled),
          ),
        );
      },
    );

    testWidgets(
      'an invoice the clock says expired while away is not drawn payable from the kept status: no QR code, the bond step stays (the wallet\'s slot is told the invoice expired)',
      (tester) async {
        var clock = tradeNow;
        var expiredTold = false;
        final watch = _Watch();
        await showTrade(
          tester,
          watch,
          now: () => clock,
          onWallet: (request) => expiredTold = request.invoiceExpired,
        );
        watch.emit(TradeScreenStatuses.watched(bond));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('Pay with another wallet'));
        await tester.pump();
        expect(find.byType(QrImageView), findsOneWidget);

        // Away past the invoice's end.
        clock = tradeNow.add(const Duration(days: 2));
        await leaveAndComeBack(tester);
        watch.emit(reopenedAt(bond));
        await tester.pump();
        await tester.pump();

        expect(find.byType(TradeFirstReadWait), findsNothing);
        expect(find.text('You are BUYING BTC'), findsOneWidget);
        expect(find.byType(QrImageView), findsNothing);
        expect(expiredTold, isTrue);
      },
    );

    testWidgets(
      '« Cancel » on a kept status: no dialog, « Wait until the order is read again before cancelling. », nothing sent',
      (tester) async {
        final watch = _Watch();
        final cancels = <TradeSeen>[];
        await showTrade(tester, watch, cancels: cancels);
        watch.emit(TradeScreenStatuses.watched(bond));
        await tester.pump();
        await tester.pump();
        await leaveAndComeBack(tester);
        watch.emit(reopenedAt(bond));
        await tester.pump();
        await tester.pump();

        final cancel = find.widgetWithText(TradeButton, 'Cancel');
        await tester.ensureVisible(cancel);
        await tester.pump();
        await tester.tap(cancel);
        await tester.pump();
        await tester.pump();

        expect(find.byType(Dialog), findsNothing);
        expect(
          find.text('Wait until the order is read again before cancelling.'),
          findsOneWidget,
        );
        expect(cancels, isEmpty);
      },
    );

    testWidgets(
      'the « Order » tab chosen: while the first read after the return runs, the order stays shown',
      (tester) async {
        final watch = _Watch();
        await showTrade(tester, watch);
        watch.emit(TradeScreenStatuses.watched(six));
        await tester.pump();
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.byType(BullSegmented).first,
            matching: find.text('Order'),
          ),
        );
        await tester.pump();
        expect(find.text('Expires in'), findsOneWidget);

        await leaveAndComeBack(tester);
        watch.emit(reopenedAt(six));
        await tester.pump();
        await tester.pump();

        expect(find.byType(TradeFirstReadWait), findsNothing);
        expect(find.text('Expires in'), findsOneWidget);
      },
    );
  });

  group('#152: back in the app, the payout form', () {
    const asked = 106606;
    final readAt = tradeNow.add(const Duration(seconds: 30));
    final invoice = Bolt11TestInvoice(
      network: Bolt11Network.mainnet,
      sats: asked,
      seed: 70,
      createdAt: tradeNow,
      expiry: const Duration(days: 2),
    );
    final reader = Bolt11Reader(Bolt11TestDecoder([invoice]));

    Result<CheckedPayout, PayoutCheckRefusal> check(
      TradeRecord record,
      TradeSeen seen,
      PayoutDestination destination,
    ) => switch (PayoutAsk.of(record, seen)) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => value.check(destination, now: readAt, reader: reader),
    };

    String fieldText(WidgetTester tester) =>
        tester
            .widget<TextField>(find.byKey(PayoutPanel.invoiceField))
            .controller
            ?.text ??
        '';

    /// The trade page as the route builds it (`P2pRouter.tradePage`), over [watch].
    Future<void> showPage(WidgetTester tester, _Watch watch) async {
      tester.view
        ..physicalSize = const Size(390, 1800) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final locator = GetIt.asNewInstance();
      addTearDown(locator.reset);
      final reads = FakeTransport();
      locator
        ..registerSingleton<P2pClock>(P2pClock(() => tradeNow))
        ..registerFactoryParam<TradeCubit, TradeRecord, void>(
          (record, _) => TradeCubit(
            record,
            watch.call,
            (record, seen, {bondLoss}) async =>
                Ok<CancelOutcome, CancelRefusal>(CancelDone(record, seen)),
          ),
        )
        ..registerFactoryParam<TradeOrderPageCubit, TradeRecord, void>(
          (record, _) => TradeOrderPageCubit(
            coordinator('temple'),
            RobosatsNetwork.mainnet,
            FetchCoordinatorInfoUsecase(CoordinatorClient(reads)).execute,
            FindPublicOrderUsecase(
              CoordinatorClient(reads, clock: () => testNow),
            ).execute,
          ),
        )
        ..registerFactoryParam<PayoutCubit, TradeRecord, void>(
          (record, _) => PayoutCubit(
            record,
            PayoutAsk.of,
            check,
            (record, shown, {onProgress}) async =>
                throw StateError('not submitted'),
            (_) => () {},
            now: () => readAt.add(const Duration(seconds: 1)),
          ),
        );
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
      await tester.pump();
    }

    testWidgets(
      'an invoice pasted at 6, the app left to make it and back: while the first read after the return runs, the form and its invoice stay',
      (tester) async {
        final watch = _Watch();
        await showPage(tester, watch);
        watch.emit(TradeScreenStatuses.watched(six));
        await tester.pump();
        await tester.pump();
        await tester.enterText(
          find.byKey(PayoutPanel.invoiceField),
          invoice.text,
        );
        await tester.pump();

        await leaveAndComeBack(tester);
        watch.emit(reopenedAt(six));
        await tester.pump();
        await tester.pump();
        final whileReading = (
          wait: find.byType(TradeFirstReadWait).evaluate().length,
          field: find.byKey(PayoutPanel.invoiceField).evaluate().length,
        );

        watch.emit(TradeScreenStatuses.watched(six));
        await tester.pump();
        await tester.pump();

        // The invoice comes back once the read does: the form lives in its cubit (#132).
        expect(fieldText(tester), invoice.text);
        expect(whileReading, (
          wait: 0,
          field: 1,
        ), reason: 'what the screen drew while the first read ran');
      },
    );
  });
}

/// The trade's watch, played by the test: what it emits goes to the subscription open now.
final class _Watch {
  final _states = StreamController<TradeWatchState>.broadcast();
  int listens = 0;

  Stream<TradeWatchState> call(
    TradeRecord record, {
    Stream<TradeWatchSignal> signals = const Stream.empty(),
    bool onScreen = true,
  }) {
    late final StreamSubscription<TradeWatchSignal> told;
    late final StreamController<TradeWatchState> out;
    StreamSubscription<TradeWatchState>? forwarded;
    out = StreamController(
      onListen: () {
        listens++;
        told = signals.listen((_) {});
        forwarded = _states.stream.listen(out.add);
      },
      onCancel: () async {
        await told.cancel();
        await forwarded?.cancel();
      },
    );
    return out.stream;
  }

  void emit(TradeWatchState state) => _states.add(state);
}
