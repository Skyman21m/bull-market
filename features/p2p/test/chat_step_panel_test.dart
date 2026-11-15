import 'dart:async';

import 'package:bull_ui/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_chat_step.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/trade/chat_step_panel.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:primitives/primitives.dart' show Failure;
import 'package:robosats/robosats.dart';

import 'support/fakes.dart' show FakeTransport, coordinator, testNow;
import 'support/harness.dart';
import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

/// The watch of the trade, played by the test.
final class _Watch {
  final _states = StreamController<TradeWatchState>.broadcast();
  final List<TradeWatchSignal> signals = [];

  Stream<TradeWatchState> call(
    TradeRecord record, {
    Stream<TradeWatchSignal> signals = const Stream.empty(),
    bool onScreen = true,
  }) {
    late final StreamController<TradeWatchState> out;
    StreamSubscription<TradeWatchState>? forwarded;
    StreamSubscription<TradeWatchSignal>? told;
    out = StreamController(
      onListen: () {
        told = signals.listen(this.signals.add);
        forwarded = _states.stream.listen(out.add);
      },
      onCancel: () async {
        await told?.cancel();
        await forwarded?.cancel();
      },
    );
    return out.stream;
  }

  void emit(TradeWatchState state) => _states.add(state);
}

/// The cancels the screen asks for: none is expected here.
final class _Cancels {
  final List<TradeSeen> asked = [];

  /// What the cancel waits for, when set, and what it answers.
  Completer<void>? gate;
  Result<CancelOutcome, CancelRefusal> Function(TradeRecord, TradeSeen)? answer;

  Future<Result<CancelOutcome, CancelRefusal>> call(
    TradeRecord record,
    TradeSeen seen, {
    BondLossAcknowledged? bondLoss,
  }) async {
    asked.add(seen);
    if (gate case final gate?) await gate.future;
    return (answer ?? (record, seen) => Ok(CancelDone(record, seen)))(
      record,
      seen,
    );
  }
}

/// The « fiat sent » the screen asks for, held by [gate] and answered as the test says.
final class _FiatSent {
  final List<TradeSeen> asked = [];
  Completer<Result<ChatStepOutcome, ChatStepRefusal>>? gate;
  void Function(ChatStepProgress step)? progress;

  Future<Result<ChatStepOutcome, ChatStepRefusal>> call(
    TradeRecord record,
    TradeSeen seen, {
    void Function(ChatStepProgress step)? onProgress,
  }) {
    asked.add(seen);
    progress = onProgress;
    return (gate ??= Completer()).future;
  }
}

late TradeScreenStatuses _statuses;
late Map<String, TradeSeen> _seen;

/// 9 for terms of a long amount, 1,234,567.1234 EUR.
late TradeSeen _longNine;
final _record = TradeScreenStatuses.record;

TradeWatchStatus _watched(String name) =>
    TradeScreenStatuses.watched(_seen[name] ?? (throw StateError(name)));

Future<TradeCubit> _show(
  WidgetTester tester, {
  required _Watch watch,
  _Cancels? cancels,
  _FiatSent? fiatSent,
  _FiatSent? undoFiatSent,
  bool offersFiatSent = true,
  bool moneyActionRunning = false,
  TradeWatchState? state,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final cubit = TradeCubit(
    _record,
    watch.call,
    (cancels ?? _Cancels()).call,
    confirmFiatSent: offersFiatSent ? (fiatSent ?? _FiatSent()).call : null,
    undoFiatSent: offersFiatSent ? (undoFiatSent ?? _FiatSent()).call : null,
  )..start();
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
      locale: locale,
      localizationsDelegates: P2pLocalizations.localizationsDelegates,
      supportedLocales: P2pLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: cubit),
            BlocProvider.value(value: page),
          ],
          child: TradeScreen(
            now: () => tradeNow,
            coordinatorDetails: (_) => throw StateError('not opened'),
            moneyActionRunning: (_) => moneyActionRunning,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  if (state != null) {
    watch.emit(state);
    await tester.pump();
    await tester.pump();
  }
  return cubit;
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

TradeButton _button(WidgetTester tester, String label) => tester.widget(
  find.ancestor(of: find.text(label), matching: find.byType(TradeButton)),
);

const _confirmLabel = 'Confirm 100 EUR sent';
const _hi =
    "Say hi! Ask for payment details and click 'Confirm Sent' as soon as the payment is sent.";
const _waitSeller =
    'Wait for the seller to confirm they have received the payment.';

void main() {
  setUpAll(() async {
    _statuses = await TradeScreenStatuses.make();
    _longNine = await (await TradeScreenStatuses.make(
      amount: 1234567.1234,
    )).chatting();
    _seen = {
      'nine': await _statuses.chatting(),
      'ten': await _statuses.fiatSent(),
      'thirteen': await _statuses.sendingSats(),
      'fourteen': await _statuses.succeeded(),
      'nineAsked': await _statuses.read(
        await _statuses.waitingForPayout(),
        orderJson(9, changes: {'asked_for_cancel': true}),
      ),
      'ninePeerAsked': await _statuses.read(
        await _statuses.waitingForPayout(),
        orderJson(
          9,
          changes: {'pending_cancel': true, 'asked_for_cancel': null},
        ),
      ),
      // The coordinator reads 200 EUR for a trade taken for 100 (review of #95's second pull request).
      'eleven': await _statuses.read(await _statuses.chatting(), orderJson(11)),
      'fiveFromNine': await _statuses.read(
        await _statuses.chatting(),
        orderJson(5, changes: {'expiry_reason': 4}),
      ),
      'nine200': await _statuses.read(
        await _statuses.waitingForPayout(),
        orderJson(9, changes: {'amount': '200.00000000'}),
      ),
    };
  });

  test('the statuses are those the state machine gives', () {
    expect(_seen['nine']?.status, isA<Chatting>());
    expect((_seen['ten']?.status as Chatting).fiatSent, isTrue);
    expect(_seen['thirteen']?.status, isA<SendingSats>());
    expect(_seen['fourteen']?.status, isA<Succeeded>());
  });

  testWidgets(
    '9: the reference\'s prompt, « Beware scams » and « Confirm … sent »',
    (tester) async {
      await _show(tester, watch: _Watch(), state: _watched('nine'));
      expect(find.text('Chat with the seller (3/4)'), findsOneWidget);
      expect(find.text(_hi), findsOneWidget);
      expect(find.text('⚠️ Beware scams'), findsOneWidget);
      expect(find.text(_confirmLabel), findsOneWidget);
      expect(find.text('Your taker bond is locked'), findsOneWidget);
      expect(find.text('Bull Market cannot show this step yet.'), findsNothing);
    },
  );

  testWidgets('the dialog is the reference\'s, and « Go back » sends nothing', (
    tester,
  ) async {
    final fiatSent = _FiatSent();
    await _show(
      tester,
      watch: _Watch(),
      fiatSent: fiatSent,
      state: _watched('nine'),
    );
    await _reveal(tester, find.text(_confirmLabel));
    await tester.tap(find.text(_confirmLabel));
    await tester.pumpAndSettle();
    expect(find.text('✅ Confirm you sent 100 EUR?'), findsOneWidget);
    expect(
      find.text('Confirming will allow your peer to finalize the trade.'),
      findsOneWidget,
    );
    expect(find.text('⚠️ This action cannot be undone!'), findsOneWidget);
    expect(
      find.text(
        'If you have not yet sent it and you still proceed to falsely confirm, you risk losing your bond.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(fiatSent.asked, isEmpty);
  });

  testWidgets(
    '« Confirm » sends once, for the status shown when pressed; meanwhile the button waits and each step is said',
    (tester) async {
      final fiatSent = _FiatSent();
      final cancels = _Cancels();
      final cubit = await _show(
        tester,
        watch: _Watch(),
        cancels: cancels,
        fiatSent: fiatSent,
        state: _watched('nine'),
      );
      await _reveal(tester, find.text(_confirmLabel));
      await tester.tap(find.text(_confirmLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await _settleDialog(tester);
      expect(fiatSent.asked, [_seen['nine']]);
      expect(_button(tester, _confirmLabel).busy, isTrue);
      expect(find.text('Opening the trade…'), findsOneWidget);
      // A second press, and a second call, send nothing more.
      await tester.tap(find.text(_confirmLabel), warnIfMissed: false);
      await _settleDialog(tester);
      expect(find.text('✅ Confirm you sent 100 EUR?'), findsNothing);
      // Not awaited: a second call that sent would wait on the gate, and the test would hang instead of failing.
      unawaited(cubit.confirmFiatSent(_seen['nine']!));
      await tester.pump();
      expect(fiatSent.asked, hasLength(1));
      for (final (step, text) in [
        (
          ChatStepProgress.waitingForOrder,
          'Waiting for another action on this order to end…',
        ),
        (
          ChatStepProgress.readingOrder,
          'Reading the order from Temple of Sats…',
        ),
        (
          ChatStepProgress.sending,
          'Sending your confirmation to Temple of Sats…',
        ),
        (
          ChatStepProgress.readingAfter,
          'Reading the order again from Temple of Sats…',
        ),
      ]) {
        fiatSent.progress?.call(step);
        await tester.pump();
        expect(find.text(text), findsOneWidget, reason: '$step');
      }
      // A cancel meanwhile is not sent either.
      expect(cubit.state.actionRunning, isTrue);
      unawaited(cubit.cancel(_seen['nine']!));
      await tester.pump();
      expect(cancels.asked, isEmpty);
      fiatSent.gate?.complete(Ok(ChatStepDone(_record, _seen['ten']!)));
      await tester.pumpAndSettle();
      expect(find.text(_waitSeller), findsOneWidget);
      expect(find.text(_confirmLabel), findsNothing);
      expect(find.text('Chat with the seller (4/4)'), findsOneWidget);
    },
  );

  testWidgets(
    'an answer lost and the order still at 9: said, the button offered again for a new tap, nothing sent by itself',
    (tester) async {
      final fiatSent = _FiatSent();
      final watch = _Watch();
      await _show(
        tester,
        watch: watch,
        fiatSent: fiatSent,
        state: _watched('nine'),
      );
      await _reveal(tester, find.text(_confirmLabel));
      await tester.tap(find.text(_confirmLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await _settleDialog(tester);
      fiatSent.gate?.complete(
        Ok(ChatStepOutcomeUnknown(_record, _seen['nine']!)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Bull Market does not know yet whether your confirmation went through. It keeps checking.',
        ),
        findsOneWidget,
      );
      expect(_button(tester, _confirmLabel).onPressed, isNotNull);
      expect(fiatSent.asked, hasLength(1));
      // The watch is asked to read at once.
      expect(watch.signals, contains(TradeWatchSignal.readNow));
      // A new tap of the user, the first request having landed meanwhile: done, the notice gone, no failure said.
      fiatSent.gate = null;
      await _reveal(tester, find.text(_confirmLabel));
      await tester.tap(find.text(_confirmLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await _settleDialog(tester);
      expect(fiatSent.asked, hasLength(2));
      fiatSent.gate?.complete(Ok(ChatStepDone(_record, _seen['ten']!)));
      await tester.pumpAndSettle();
      expect(find.text(_waitSeller), findsOneWidget);
      expect(find.textContaining('does not know yet'), findsNothing);
      expect(find.textContaining('nothing was sent'), findsNothing);
    },
  );

  testWidgets('the order moved before sending: said, nothing sent', (
    tester,
  ) async {
    final fiatSent = _FiatSent();
    await _show(
      tester,
      watch: _Watch(),
      fiatSent: fiatSent,
      state: _watched('nine'),
    );
    await _reveal(tester, find.text(_confirmLabel));
    await tester.tap(find.text(_confirmLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await _settleDialog(tester);
    fiatSent.gate?.complete(Err(ChatStepStatusMoved(_seen['ten']!)));
    await tester.pumpAndSettle();
    expect(
      find.text('The order moved on: your confirmation was not sent.'),
      findsOneWidget,
    );
    // The status now is shown: the seller's wait, no button.
    expect(find.text(_waitSeller), findsOneWidget);
    expect(find.text(_confirmLabel), findsNothing);
  });

  testWidgets('another action of the trade running: the button off, and why', (
    tester,
  ) async {
    final fiatSent = _FiatSent();
    await _show(
      tester,
      watch: _Watch(),
      fiatSent: fiatSent,
      moneyActionRunning: true,
      state: _watched('nine'),
    );
    expect(_button(tester, _confirmLabel).onPressed, isNull);
    expect(
      find.text('Waiting for another action on this order to end…'),
      findsOneWidget,
    );
    await tester.tap(find.text(_confirmLabel), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('✅ Confirm you sent 100 EUR?'), findsNothing);
    expect(fiatSent.asked, isEmpty);
  });

  testWidgets('without the action wired, the step shows no button', (
    tester,
  ) async {
    await _show(
      tester,
      watch: _Watch(),
      offersFiatSent: false,
      state: _watched('nine'),
    );
    expect(find.text(_hi), findsOneWidget);
    expect(find.text(_confirmLabel), findsNothing);
  });

  testWidgets('10: the seller\'s wait, no button', (tester) async {
    await _show(tester, watch: _Watch(), state: _watched('ten'));
    expect(find.text(_waitSeller), findsOneWidget);
    expect(find.text('⚠️ Beware scams'), findsOneWidget);
    expect(find.text(_confirmLabel), findsNothing);
  });

  testWidgets(
    '13: « Attempting Lightning Payment » with the reference\'s texts',
    (tester) async {
      await _show(tester, watch: _Watch(), state: _watched('thirteen'));
      expect(find.text('Attempting Lightning Payment'), findsOneWidget);
      expect(
        find.text(
          'RoboSats is trying to pay your lightning invoice. Remember that lightning nodes must be online in order to receive payments.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Taking too long?'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Bull Market cannot show this step yet.'), findsNothing);
    },
  );

  testWidgets('14: « Trade finished! »', (tester) async {
    await _show(tester, watch: _Watch(), state: _watched('fourteen'));
    expect(find.text('Trade finished!'), findsOneWidget);
    expect(find.text('Bull Market cannot show this step yet.'), findsNothing);
  });

  testWidgets(
    'an answer lost, then the watch reads 10: the notice goes, the seller\'s wait stays',
    (tester) async {
      final fiatSent = _FiatSent();
      final watch = _Watch();
      await _show(
        tester,
        watch: watch,
        fiatSent: fiatSent,
        state: _watched('nine'),
      );
      await _reveal(tester, find.text(_confirmLabel));
      await tester.tap(find.text(_confirmLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await _settleDialog(tester);
      fiatSent.gate?.complete(
        Ok(ChatStepOutcomeUnknown(_record, _seen['nine']!)),
      );
      await tester.pumpAndSettle();
      final unknown = find.text(
        'Bull Market does not know yet whether your confirmation went through. It keeps checking.',
      );
      expect(unknown, findsOneWidget);
      // In the warning colour: no failure is said.
      expect(tester.widget<Text>(unknown).style?.color, testBullTheme.warning);
      // The order still at 9, read again: the request may still land, the notice stays.
      watch.emit(_watched('nine'));
      await tester.pumpAndSettle();
      expect(unknown, findsOneWidget);
      watch.emit(_watched('ten'));
      await tester.pumpAndSettle();
      expect(find.text(_waitSeller), findsOneWidget);
      expect(unknown, findsNothing);
    },
  );

  testWidgets(
    'while sent: a bar named by the step, and after 30 s the long wait\'s line',
    (tester) async {
      final fiatSent = _FiatSent();
      await _show(
        tester,
        watch: _Watch(),
        fiatSent: fiatSent,
        state: _watched('nine'),
      );
      await _reveal(tester, find.text(_confirmLabel));
      await tester.tap(find.text(_confirmLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await _settleDialog(tester);
      fiatSent.progress?.call(ChatStepProgress.sending);
      await tester.pump();
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(
        bar.semanticsLabel,
        'Sending your confirmation to Temple of Sats…',
      );
      const still = 'Still waiting for Temple of Sats. Tor can take a minute.';
      expect(find.text(still), findsNothing);
      await tester.pump(const Duration(seconds: 31));
      expect(find.text(still), findsOneWidget);
      fiatSent.gate?.complete(Ok(ChatStepDone(_record, _seen['ten']!)));
      await tester.pumpAndSettle();
      expect(find.text(still), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('at 9 from a status not marked stored: the button off, and why', (
    tester,
  ) async {
    final fiatSent = _FiatSent();
    final nine = _seen['nine']!;
    await _show(
      tester,
      watch: _Watch(),
      fiatSent: fiatSent,
      state: TradeScreenStatuses.watched(
        TradeSeen(nine.status, order: nine.order),
      ),
    );
    expect(_button(tester, _confirmLabel).onPressed, isNull);
    expect(find.text('Wait until the order is read again.'), findsOneWidget);
  });

  testWidgets(
    'a read of another amount: the button and the dialog keep the trade\'s terms, and a line gives both figures',
    (tester) async {
      final nine200 = _seen['nine200']!;
      expect(nine200.stored, isTrue);
      expect(nine200.order?.amount, isA<FixedOrderAmount>());
      await _show(tester, watch: _Watch(), state: _watched('nine200'));
      expect(find.text(_confirmLabel), findsOneWidget);
      expect(find.text('Confirm 200 EUR sent'), findsNothing);
      expect(
        find.text(
          'Temple of Sats now gives 200 EUR; the order was taken for 100 EUR.',
        ),
        findsOneWidget,
      );
      await _reveal(tester, find.text(_confirmLabel));
      await tester.tap(find.text(_confirmLabel));
      await tester.pumpAndSettle();
      expect(find.text('✅ Confirm you sent 100 EUR?'), findsOneWidget);
    },
  );

  testWidgets(
    'a range order read without its amount, or with another: the terms\' figure on the button, the read said',
    (tester) async {
      final nine = _seen['nine']!;
      for (final (range, changes, line) in [
        (
          false,
          // The same amount in another currency.
          {'currency': 1},
          'Temple of Sats now gives 100 USD; the order was taken for 100 EUR.',
        ),
        (
          true,
          {'amount': null},
          'Temple of Sats gives no amount for this order; it was taken for 100 EUR.',
        ),
        (
          true,
          {'amount': '120.00000000'},
          'Temple of Sats now gives 120 EUR; the order was taken for 100 EUR.',
        ),
      ]) {
        final order = await readOrder(
          orderJson(9, range: range, changes: changes),
        );
        final cubit = TradeCubit(
          _record,
          _Watch().call,
          _Cancels().call,
          confirmFiatSent: _FiatSent().call,
        );
        addTearDown(cubit.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: testTheme,
            localizationsDelegates: P2pLocalizations.localizationsDelegates,
            supportedLocales: P2pLocalizations.supportedLocales,
            home: Scaffold(
              body: BlocProvider.value(
                value: cubit,
                child: ChatStepPanel(
                  seen: nine,
                  order: order,
                  coordinator: 'Temple of Sats',
                  chatStep: const ChatStepIdle(),
                  otherActionRunning: false,
                  cancel: const CancelIdle(),
                  offersUndoFiatSent: true,
                  offersCollaborativeCancel: true,
                  offersFiatSent: true,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text(_confirmLabel), findsOneWidget, reason: '$changes');
        expect(find.text(line), findsOneWidget, reason: '$changes');
      }
    },
  );

  testWidgets(
    'a bug of the use case or of the cancel: the buttons free again, the outcome said unknown',
    (tester) async {
      final cubit = TradeCubit(
        _record,
        _Watch().call,
        (record, seen, {bondLoss}) async => throw StateError('cancel bug'),
        confirmFiatSent: (record, seen, {onProgress}) async =>
            throw StateError('use case bug'),
      );
      addTearDown(cubit.close);
      await expectLater(
        cubit.confirmFiatSent(_seen['nine']!),
        throwsStateError,
      );
      expect(cubit.state.chatStep, isA<ChatStepIdle>());
      expect(
        (cubit.state.chatStep as ChatStepIdle).notice,
        isA<ChatStepWasUnknown>(),
      );
      expect(cubit.state.actionRunning, isFalse);
      await expectLater(cubit.cancel(_seen['nine']!), throwsStateError);
      expect(cubit.state.cancel, isA<CancelIdle>());
      expect(cubit.state.actionRunning, isFalse);
    },
  );

  test(
    'a refusal that kept a read takes its record: an end closes it',
    () async {
      final closed = TradeRecord(
        robot: _record.robot,
        coordinatorAlias: _record.coordinatorAlias,
        coordinatorOnion: _record.coordinatorOnion,
        orderId: _record.orderId,
        role: _record.role,
        origin: _record.origin,
        takenAt: _record.takenAt,
        confirmedAt: _record.confirmedAt,
        closedAt: tradeNow.add(const Duration(minutes: 5)),
      );
      final cubit = TradeCubit(
        _record,
        _Watch().call,
        _Cancels().call,
        confirmFiatSent: (record, seen, {onProgress}) async =>
            Err(ChatStepStatusMoved(_seen['fourteen']!, record: closed)),
      );
      addTearDown(cubit.close);
      await cubit.confirmFiatSent(_seen['nine']!);
      expect(cubit.state.record, closed);
    },
  );

  testWidgets(
    'what a refusal says: never « not sent » once the request left, never « not recorded » before it left',
    (tester) async {
      for (final (cause, text) in <(Failure, String)>[
        (
          const OrderNotParticipant(),
          'Temple of Sats did not record your confirmation.',
        ),
        (
          const RobotCredentialsRejected(),
          'Temple of Sats did not record your confirmation.',
        ),
        (
          const TradeActionNotNow(fromLastRead: false),
          'The order moved on: Temple of Sats did not record your confirmation.',
        ),
        (
          const TradeActionNotNow(fromLastRead: true),
          'The order moved on: your confirmation was not sent.',
        ),
        (
          const CoordinatorTransportBusy(),
          'Too many requests are waiting for this coordinator. Try again in a moment. Your confirmation was not sent.',
        ),
        (
          const CoordinatorNotOnNetwork(),
          'Temple of Sats is offline: your confirmation was not sent.',
        ),
      ]) {
        final fiatSent = _FiatSent();
        await _show(
          tester,
          watch: _Watch(),
          fiatSent: fiatSent,
          state: _watched('nine'),
        );
        await _reveal(tester, find.text(_confirmLabel));
        await tester.tap(find.text(_confirmLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm'));
        await _settleDialog(tester);
        fiatSent.gate?.complete(
          Ok(ChatStepNotDone(_record, _seen['nine']!, cause: cause)),
        );
        await tester.pumpAndSettle();
        expect(find.text(text), findsOneWidget, reason: '$cause');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'the order moved to a dispute or an end before sending: the notice said under the new status, read there until the next one',
    (tester) async {
      const movedOn = 'The order moved on: your confirmation was not sent.';
      for (final (name, next) in [('eleven', 'nine'), ('fiveFromNine', null)]) {
        final fiatSent = _FiatSent();
        final watch = _Watch();
        await _show(
          tester,
          watch: watch,
          fiatSent: fiatSent,
          state: _watched('nine'),
        );
        await _reveal(tester, find.text(_confirmLabel));
        await tester.tap(find.text(_confirmLabel));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm'));
        await _settleDialog(tester);
        fiatSent.gate?.complete(Err(ChatStepStatusMoved(_seen[name]!)));
        await tester.pumpAndSettle();
        expect(find.text(movedOn), findsOneWidget, reason: name);
        // The same status read again: still said.
        watch.emit(_watched(name));
        await tester.pumpAndSettle();
        expect(find.text(movedOn), findsOneWidget, reason: name);
        if (next != null) {
          // Another position: gone.
          watch.emit(_watched(next));
          await tester.pumpAndSettle();
          expect(find.text(movedOn), findsNothing, reason: name);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'the coordinator refused because the order moved to a dispute: said under the dispute',
    (tester) async {
      final fiatSent = _FiatSent();
      await _show(
        tester,
        watch: _Watch(),
        fiatSent: fiatSent,
        state: _watched('nine'),
      );
      await _reveal(tester, find.text(_confirmLabel));
      await tester.tap(find.text(_confirmLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await _settleDialog(tester);
      fiatSent.gate?.complete(
        Ok(
          ChatStepNotDone(
            _record,
            _seen['eleven']!,
            cause: const TradeActionNotNow(fromLastRead: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The order moved on: Temple of Sats did not record your confirmation.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('14: the title between the reference\'s two bolts', (
    tester,
  ) async {
    await _show(tester, watch: _Watch(), state: _watched('fourteen'));
    expect(find.byIcon(Icons.bolt), findsNWidgets(2));
  });

  testWidgets('the emoji are not read out', (tester) async {
    final handle = tester.ensureSemantics();
    await _show(tester, watch: _Watch(), state: _watched('nine'));
    expect(find.bySemanticsLabel('Beware scams'), findsOneWidget);
    await _reveal(tester, find.text(_confirmLabel));
    await tester.tap(find.text(_confirmLabel));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Confirm you sent 100 EUR?'), findsOneWidget);
    expect(
      find.bySemanticsLabel('This action cannot be undone!'),
      findsOneWidget,
    );
    handle.dispose();
  });

  group('« Payment failed? » (#95)', () {
    testWidgets(
      '10: the button, the reference\'s dialog in full, « Wait (60) » then « Confirm », sent once',
      (tester) async {
        final undo = _FiatSent();
        await _show(
          tester,
          watch: _Watch(),
          undoFiatSent: undo,
          state: _watched('ten'),
        );
        await _reveal(tester, find.text('Payment failed?'));
        await tester.tap(find.text('Payment failed?'));
        await _settleDialog(tester);
        expect(
          find.text('Revert the confirmation of fiat sent?'),
          findsOneWidget,
        );
        expect(
          find.textContaining('READ. In case your payment'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Make 100% sure your payment has failed'),
          findsOneWidget,
        );
        expect(find.text('Wait (60)'), findsOneWidget);
        await tester.ensureVisible(find.text('Wait (60)'));
        await tester.pump();
        await tester.tap(find.text('Wait (60)'), warnIfMissed: false);
        await tester.pump();
        expect(undo.asked, isEmpty);
        await tester.pump(const Duration(seconds: 30));
        expect(find.text('Wait (30)'), findsOneWidget);
        await tester.pump(const Duration(seconds: 30));
        expect(find.text('Confirm'), findsOneWidget);
        // Under the reference's long text: the dialog scrolls to it.
        await tester.ensureVisible(find.text('Confirm'));
        await tester.pump();
        await tester.tap(find.text('Confirm'));
        await _settleDialog(tester);
        expect(undo.asked, [_seen['ten']]);
        expect(
          find.text('Sending your request to Temple of Sats…'),
          findsNothing,
        );
        undo.progress?.call(ChatStepProgress.sending);
        await tester.pump();
        expect(
          find.text('Sending your request to Temple of Sats…'),
          findsOneWidget,
        );
        undo.gate?.complete(Ok(ChatStepDone(_record, _seen['nine']!)));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text(_confirmLabel), findsOneWidget);
      },
    );

    testWidgets('« Go back » sends nothing', (tester) async {
      final undo = _FiatSent();
      await _show(
        tester,
        watch: _Watch(),
        undoFiatSent: undo,
        state: _watched('ten'),
      );
      await _reveal(tester, find.text('Payment failed?'));
      await tester.tap(find.text('Payment failed?'));
      await _settleDialog(tester);
      await tester.ensureVisible(find.text('Go back'));
      await tester.pump();
      await tester.tap(find.text('Go back'));
      await _settleDialog(tester);
      expect(undo.asked, isEmpty);
    });

    testWidgets('not at 9: no « Payment failed? »', (tester) async {
      await _show(tester, watch: _Watch(), state: _watched('nine'));
      expect(find.text('Payment failed?'), findsNothing);
    });

    testWidgets(
      'the trade moved on: said with « request », the request never left',
      (tester) async {
        final undo = _FiatSent();
        await _show(
          tester,
          watch: _Watch(),
          undoFiatSent: undo,
          state: _watched('ten'),
        );
        await _reveal(tester, find.text('Payment failed?'));
        await tester.tap(find.text('Payment failed?'));
        await _settleDialog(tester);
        await tester.pump(const Duration(seconds: 61));
        await tester.ensureVisible(find.text('Confirm'));
        await tester.pump();
        await tester.tap(find.text('Confirm'));
        await _settleDialog(tester);
        // The read before sending no longer offered it (here, the same 10 not marked stored): the panel stays, and says so.
        undo.gate?.complete(Err(ChatStepStatusMoved(_seen['ten']!)));
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.text('The trade moved on: your request was not sent.'),
          findsOneWidget,
        );
      },
    );
  });

  group('« Order options » and the collaborative cancel (#95)', () {
    testWidgets(
      'a cancel running, from wherever it was asked: « … » off',
      (tester) async {
        final cancels = _Cancels()..gate = Completer<void>();
        final cubit = await _show(
          tester,
          watch: _Watch(),
          cancels: cancels,
          state: _watched('nine'),
        );
        unawaited(cubit.cancel(_seen['nine']!));
        await tester.pump();
        await _reveal(tester, find.byIcon(Icons.more_horiz));
        await tester.tap(find.byIcon(Icons.more_horiz), warnIfMissed: false);
        await _settleDialog(tester);
        expect(find.text('Order options'), findsNothing);
        cancels.gate?.complete();
        await tester.pump(const Duration(milliseconds: 500));
      },
    );

    testWidgets(
      '9: « … » opens « Order options »; « Collaborative Cancel », the reference\'s dialog, « Ask for Cancel » sends once',
      (tester) async {
        final cancels = _Cancels();
        await _show(
          tester,
          watch: _Watch(),
          cancels: cancels,
          state: _watched('nine'),
        );
        await _reveal(tester, find.byIcon(Icons.more_horiz));
        await tester.tap(find.byIcon(Icons.more_horiz));
        await _settleDialog(tester);
        expect(find.text('Order options'), findsOneWidget);
        // The places of « Audit Chat », « Export » and « Open Dispute »: empty for now.
        expect(find.text('Audit Chat'), findsNothing);
        expect(find.text('Export'), findsNothing);
        expect(find.text('Open Dispute'), findsNothing);
        await tester.tap(find.text('Collaborative Cancel'));
        await _settleDialog(tester);
        expect(find.text('Collaborative cancel the order?'), findsOneWidget);
        expect(
          find.text(
            'The trade escrow has been posted. The order can be cancelled only if both, maker and taker, agree to cancel.',
          ),
          findsOneWidget,
        );
        expect(find.text('Accept Cancelation'), findsNothing);
        await tester.tap(find.text('Go back'));
        await _settleDialog(tester);
        expect(cancels.asked, isEmpty);
        await tester.tap(find.byIcon(Icons.more_horiz));
        await _settleDialog(tester);
        await tester.tap(find.text('Collaborative Cancel'));
        await _settleDialog(tester);
        await tester.tap(find.text('Ask for Cancel'));
        await _settleDialog(tester);
        expect(cancels.asked, [_seen['nine']]);
      },
    );

    testWidgets(
      'asked by us: the reference\'s alert says it waits for the peer',
      (tester) async {
        await _show(tester, watch: _Watch(), state: _watched('nineAsked'));
        expect(
          find.text('You asked for a collaborative cancellation'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'asked by the peer: its alert, then « Accept Cancelation » only on the user\'s tap',
      (tester) async {
        final cancels = _Cancels();
        final seen = _seen['ninePeerAsked']!;
        await _show(
          tester,
          watch: _Watch(),
          cancels: cancels,
          state: _watched('ninePeerAsked'),
        );
        final peer = seen.order!.maker.nickname;
        expect(
          find.text('$peer is asking for a collaborative cancel'),
          findsOneWidget,
        );
        expect(cancels.asked, isEmpty);
        await _reveal(tester, find.byIcon(Icons.more_horiz));
        await tester.tap(find.byIcon(Icons.more_horiz));
        await _settleDialog(tester);
        await tester.tap(find.text('Collaborative Cancel'));
        await _settleDialog(tester);
        expect(
          find.textContaining('Your peer has asked for cancellation'),
          findsOneWidget,
        );
        await tester.tap(find.text('Accept Cancelation'));
        await _settleDialog(tester);
        expect(cancels.asked, [seen]);
      },
    );

    testWidgets(
      '10: « Collaborative Cancel » off, with the reference\'s reason',
      (tester) async {
        final cancels = _Cancels();
        await _show(
          tester,
          watch: _Watch(),
          cancels: cancels,
          state: _watched('ten'),
        );
        await _reveal(tester, find.byIcon(Icons.more_horiz));
        await tester.tap(find.byIcon(Icons.more_horiz));
        await _settleDialog(tester);
        expect(
          find.text("Orders can't be cancelled if fiat has been sent."),
          findsOneWidget,
        );
        await tester.tap(
          find.text('Collaborative Cancel'),
          warnIfMissed: false,
        );
        await _settleDialog(tester);
        expect(find.text('Collaborative cancel the order?'), findsNothing);
        expect(cancels.asked, isEmpty);
      },
    );

    testWidgets(
      'while the ask is sent: « … » and « Confirm … sent » off, the wait said; an ask that lands after « fiat sent »: the trade moved on',
      (tester) async {
        final cancels = _Cancels()
          ..gate = Completer<void>()
          ..answer = (record, seen) => Ok(
            CancelNotDone(
              record,
              _seen['ten']!,
              cause: const OrderStatusChanged(),
            ),
          );
        await _show(
          tester,
          watch: _Watch(),
          cancels: cancels,
          state: _watched('nine'),
        );
        await _reveal(tester, find.byIcon(Icons.more_horiz));
        await tester.tap(find.byIcon(Icons.more_horiz));
        await _settleDialog(tester);
        await tester.tap(find.text('Collaborative Cancel'));
        await _settleDialog(tester);
        await tester.tap(find.text('Ask for Cancel'));
        await _settleDialog(tester);
        expect(
          find.text('Sending your request to Temple of Sats…'),
          findsOneWidget,
        );
        expect(_button(tester, _confirmLabel).onPressed, isNull);
        await tester.tap(find.byIcon(Icons.more_horiz), warnIfMissed: false);
        await _settleDialog(tester);
        expect(find.text('Order options'), findsNothing);
        cancels.gate?.complete();
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.text(
            'The order moved on before the cancel: nothing was cancelled.',
          ),
          findsOneWidget,
        );
        expect(cancels.asked, hasLength(1));
      },
    );
  });

  group('on a phone of 320 points, the text larger', () {
    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets('${locale.languageCode} at ×$scale: nothing is cut', (
          tester,
        ) async {
          final fiatSent = _FiatSent();
          await _show(
            tester,
            watch: _Watch(),
            fiatSent: fiatSent,
            locale: locale,
            size: const Size(320, 640),
            textScale: scale,
            state: _watched('nine'),
          );
          _expectNothingCut(tester, 'nine');
          final button = find.byType(TradeButton).first;
          await _reveal(tester, button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          _expectNothingCut(tester, 'dialog');
        });

        testWidgets(
          '${locale.languageCode} at ×$scale: 10, 13, 14, the wait and the notice are not cut',
          (tester) async {
            final watch = _Watch();
            final fiatSent = _FiatSent();
            await _show(
              tester,
              watch: watch,
              fiatSent: fiatSent,
              locale: locale,
              size: const Size(320, 640),
              textScale: scale,
              state: _watched('nine'),
            );
            final button = find.byType(TradeButton).first;
            await _reveal(tester, button);
            await tester.tap(button);
            await tester.pumpAndSettle();
            // The dialog's « Confirm », scrolled into view at the larger sizes.
            final confirm = find.byType(TradeButton).last;
            await tester.ensureVisible(confirm);
            await tester.pump();
            await tester.tap(confirm);
            await _settleDialog(tester);
            expect(fiatSent.asked, hasLength(1));
            fiatSent.progress?.call(ChatStepProgress.readingAfter);
            await tester.pump(const Duration(seconds: 31));
            _expectNothingCut(tester, 'wait');
            fiatSent.gate?.complete(
              Ok(ChatStepOutcomeUnknown(_record, _seen['nine']!)),
            );
            await tester.pumpAndSettle();
            _expectNothingCut(tester, 'notice');
            for (final name in ['ten', 'thirteen', 'fourteen']) {
              watch.emit(_watched(name));
              // 13 spins: no settling.
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 500));
              _expectNothingCut(tester, name);
            }
          },
        );

        testWidgets(
          '${locale.languageCode} at ×$scale: a long coordinator name and a long amount are not cut',
          (tester) async {
            // Terms of a long amount, which the button takes, and a read of another long one, which the warning line gives.
            final nine = _longNine;
            final order = await readOrder(
              orderJson(9, changes: {'amount': '7654321.43210000'}),
            );
            final cubit = TradeCubit(
              _record,
              _Watch().call,
              _Cancels().call,
              confirmFiatSent: _FiatSent().call,
            );
            addTearDown(cubit.close);
            tester.view
              ..physicalSize = const Size(320, 640) * 3
              ..devicePixelRatio = 3;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              MaterialApp(
                theme: testTheme,
                locale: locale,
                localizationsDelegates: P2pLocalizations.localizationsDelegates,
                supportedLocales: P2pLocalizations.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
                home: Scaffold(
                  body: BlocProvider.value(
                    value: cubit,
                    child: SingleChildScrollView(
                      child: ChatStepPanel(
                        seen: nine,
                        order: order,
                        coordinator:
                            'The Very Long Name Of A Coordinator Of The Federation',
                        chatStep: const ChatStepRunning(
                          ChatStepAction.confirmFiatSent,
                          progress: ChatStepProgress.readingOrder,
                          waitedLong: true,
                        ),
                        otherActionRunning: false,
                        cancel: const CancelIdle(),
                        offersUndoFiatSent: true,
                        offersCollaborativeCancel: true,
                        offersFiatSent: true,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            _expectNothingCut(tester, 'long');
            expect(
              find.byWidgetPredicate(
                (w) =>
                    w is TradeButton &&
                    w.label.contains('234') &&
                    w.label.contains('567'),
              ),
              findsOneWidget,
            );
            expect(find.textContaining('654'), findsOneWidget);
          },
        );
      }
    }
  });
}

/// The dialog's route closed or opened, while a button's spinner keeps the screen from settling.
Future<void> _settleDialog(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void _expectNothingCut(WidgetTester tester, String reason) {
  expect(tester.takeException(), isNull, reason: reason);
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.byType(RichText),
  )) {
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '$reason: ${paragraph.text.toPlainText()}',
    );
  }
}
