import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/p2p_clock.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_chat.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/chat_cubit.dart';
import 'package:p2p/src/presentation/payout_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/trade/chat_panel.dart';
import 'package:p2p/src/ui/trade/payout_panel.dart';
import 'package:p2p/src/ui/trade/trade_first_read_wait.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/trade/wallet_payment_section.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
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
    ChatCubit? chat,
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
    }, lastStored: (_) => watch.lastStored)..start();
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
              if (chat != null) BlocProvider.value(value: chat),
            ],
            child: TradeScreen(
              now: now ?? () => tradeNow,
              coordinatorDetails: (_) => throw StateError('not opened'),
              chat: chat == null
                  ? null
                  : (context, request) => ChatPanel(request: request),
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
      '« Cancel » on a kept status: the reference\'s dialog, and the cancel asked with the kept status (its guard), as the reference cancels from the order it holds',
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
        expect(find.text('Cancel the order?'), findsOneWidget);
        // The button that goes on ignores a tap for a moment once the dialog is shown (#298).
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Confirm cancellation'));
        await tester.pump();
        await tester.pump();

        expect(cancels, hasLength(1));
        expect(cancels.single, same(bond));
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

  group('#152: back in the app, the chat step', () {
    const privacy = MethodChannel('com.flutterplaza.no_screenshot_methods');
    late List<String> privacyCalls;

    setUp(() {
      privacyCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(privacy, (call) async {
            privacyCalls.add(call.method);
            return true;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(privacy, null),
    );

    testWidgets(
      'at 9 with a draft, the app left and back: the same chat panel, its draft kept, its protection never let go, the key let go while away and held once again on the return, nothing sent',
      (tester) async {
        final nine = await statuses.chatting();
        var held = 0;
        var released = 0;
        var reads = 0;
        final posts = <String>[];
        final chat = ChatCubit(
          record,
          (record, seen) async {
            reads++;
            return const Ok(ChatView());
          },
          (record, seen, text) async {
            posts.add(text);
            return const Ok(ChatSentStored(1));
          },
          (record, seen, id) async => const Ok(ChatSentStored(1)),
          (record, seen) => const Ok(ChatView()),
          (record) => const ChatView(),
          (record) async => const Ok(<String, Object?>{}),
          (record) {
            held++;
            return () => released++;
          },
        );
        addTearDown(chat.close);
        final watch = _Watch();
        await showTrade(tester, watch, chat: chat);
        watch.emit(TradeScreenStatuses.watched(nine));
        await tester.pump();
        await tester.pump();
        final field = find.descendant(
          of: find.byType(ChatPanel),
          matching: find.byType(TextField),
        );
        expect(field, findsOneWidget);
        await tester.enterText(field, 'a draft');
        await tester.pump();
        final panel = tester.state(find.byType(ChatPanel));
        expect((held, released), (1, 0));
        privacyCalls.clear();

        await leaveAndComeBack(tester);
        expect((held, released), (2, 1), reason: 'let go away, held again');
        watch.emit(reopenedAt(nine));
        await tester.pump();
        await tester.pump();

        expect(identical(tester.state(find.byType(ChatPanel)), panel), isTrue);
        expect(tester.widget<TextField>(field).controller?.text, 'a draft');
        expect(chat.state.text, 'a draft');
        expect((held, released), (2, 1));
        expect(chat.holdsKey, isTrue);
        expect(privacyCalls, isNot(contains('screenshotOn')));
        expect(posts, isEmpty);
        expect(reads, greaterThan(0));
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
            lastStored: (_) => watch.lastStored,
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

  /// The newest status marked stored it emitted: what `TradeReadOrder` holds of the run, as `WatchTradeUsecase.lastStored` gives it.
  TradeSeen? lastStored;

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

  void emit(TradeWatchState state) {
    if (state case TradeWatchStatus(:final seen) when seen.stored) {
      lastStored = seen;
    }
    _states.add(state);
  }
}
