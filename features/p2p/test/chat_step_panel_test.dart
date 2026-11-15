import 'dart:async';

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
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
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

  Future<Result<CancelOutcome, CancelRefusal>> call(
    TradeRecord record,
    TradeSeen seen, {
    BondLossAcknowledged? bondLoss,
  }) async {
    asked.add(seen);
    return Ok(CancelDone(record, seen));
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
final _record = TradeScreenStatuses.record;

TradeWatchStatus _watched(String name) =>
    TradeScreenStatuses.watched(_seen[name] ?? (throw StateError(name)));

Future<TradeCubit> _show(
  WidgetTester tester, {
  required _Watch watch,
  _Cancels? cancels,
  _FiatSent? fiatSent,
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
    _seen = {
      'nine': await _statuses.chatting(),
      'ten': await _statuses.fiatSent(),
      'thirteen': await _statuses.sendingSats(),
      'fourteen': await _statuses.succeeded(),
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
      await cubit.confirmFiatSent(_seen['nine']!);
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
      await cubit.cancel(_seen['nine']!);
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
      find.text(
        'The order moved on before your confirmation: nothing was sent.',
      ),
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
