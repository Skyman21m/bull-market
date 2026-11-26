import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bull_ui/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/p2p_clock.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_chat.dart';
import 'package:p2p/src/domain/trade/trade_chat_step.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/domain/trade/trade_host_rating.dart';
import 'package:p2p/src/presentation/chat_cubit.dart';
import 'package:p2p/src/presentation/host_rating_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/garage/robosats_links.dart' show simplexGroupUrl;
import 'package:p2p/src/ui/coordinator_details_dialog.dart'
    show CoordinatorContacts;
import 'package:p2p/src/ui/trade/chat_actions.dart';
import 'package:p2p/src/ui/trade/chat_panel.dart';
import 'package:p2p/src/ui/trade/chat_step_panel.dart';
import 'package:p2p/src/ui/trade/host_rating_section.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/coordinator_link_sheet.dart';
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

/// The ratings the screen sends, held by [gate] and answered as the test says.
final class _Rates {
  final List<(TradeSeen, int)> asked = [];
  Completer<Result<ChatStepOutcome, ChatStepRefusal>>? gate;
  void Function(ChatStepProgress step)? progress;

  Future<Result<ChatStepOutcome, ChatStepRefusal>> call(
    TradeRecord record,
    TradeSeen seen,
    PlatformRating rating, {
    void Function(ChatStepProgress step)? onProgress,
  }) {
    asked.add((seen, rating.stars));
    progress = onProgress;
    return (gate ??= Completer()).future;
  }
}

/// « Rate your host » (#95) as its use case answers the tests: the token given when [token] completes, every publication kept.
final class _HostRates {
  final List<TradeSeen> asked = [];
  final List<(TradeSeen, HostReviewToken, int)> published = [];
  final Completer<Result<HostReviewToken, HostTokenNotGiven>> token =
      Completer();

  late final HostRatingCubit cubit = HostRatingCubit(
    _record,
    (record, seen) {
      asked.add(seen);
      return token.future;
    },
    (record, seen, token, rating) async =>
        published.add((seen, token, rating.stars)),
  );

  static final HostReviewToken given =
      HostReviewToken.parse('ab' * 64) ?? (throw StateError('token'));

  void give() => token.complete(Ok(given));

  void refuse() => token.complete(const Err(HostTokenNotGiven()));
}

late TradeScreenStatuses _statuses;

/// The watch of the trade screen last shown by « Open Dispute »'s tests, to give it a new read.
_Watch? _lastWatch;
late Map<String, TradeSeen> _seen;

/// 9 for terms of a long amount, 1,234,567.1234 EUR.
late TradeSeen _longNine;
final _record = TradeScreenStatuses.record;

/// The app's own font (`assets/fonts/GolosText.ttf`), loaded once: the checks of words broken are made in it, since Flutter's test font draws every glyph as a square of the text's size, words about twice as wide as the app draws them.
final _appTheme = testTheme.copyWith(
  textTheme: testTheme.textTheme.apply(fontFamily: 'Golos Text'),
);

Future<void> _loadAppFont() async {
  final golos = FontLoader('Golos Text')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('../../assets/fonts/GolosText.ttf').readAsBytesSync(),
        ),
      ),
    );
  await golos.load();
}

TradeWatchStatus _watched(String name) =>
    TradeScreenStatuses.watched(_seenOf(name));

/// The status [name] of the tests, with no non-null assertion.
TradeSeen _seenOf(String name) => _seen[name] ?? (throw StateError(name));

Future<TradeCubit> _show(
  WidgetTester tester, {
  required _Watch watch,
  _Cancels? cancels,
  _FiatSent? fiatSent,
  _FiatSent? undoFiatSent,
  _FiatSent? dispute,
  _Rates? rate,
  DateTime Function()? now,
  bool offersFiatSent = true,
  bool moneyActionRunning = false,
  ChatPanelBuilder? chat,
  ChatCubit? chatCubit,
  HostRatingCubit? hostRating,
  TradeWatchState? state,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  double textScale = 1,
  bool appFont = false,
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
    startDispute: dispute?.call,
    rate: rate?.call,
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
      theme: appFont ? _appTheme : testTheme,
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
            // The chat's cubit above the screen, as the route provides it (`P2pRouter.tradePage`).
            if (chatCubit != null) BlocProvider.value(value: chatCubit),
            // « Rate your host »'s cubit, as the route provides it.
            if (hostRating != null) BlocProvider.value(value: hostRating),
          ],
          child: TradeScreen(
            now: now ?? () => tradeNow,
            coordinatorDetails: (_) => throw StateError('not opened'),
            moneyActionRunning: (_) => moneyActionRunning,
            chat:
                chat ??
                (chatCubit == null
                    ? null
                    : (context, request) => ChatPanel(request: request)),
            // As the route gives them.
            chatOptions: chatCubit == null ? null : chatOptionsOf,
            hostRating: hostRating == null
                ? null
                : (context, seen, coordinator) =>
                      HostRatingSection(seen: seen, coordinator: coordinator),
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

/// The chat panel (#93) as the route gives it, over a cubit whose use cases answer an empty chat whose peer's key is not known yet: nothing leaves.
ChatPanelBuilder _chatPanel(WidgetTester tester) {
  final cubit = ChatCubit(
    _record,
    (record, seen) async => const Ok(ChatView(connected: true)),
    (record, seen, text) async => const Err(ChatPeerKeyNotKnown()),
    (record, seen, id) async => const Err(ChatPeerKeyNotKnown()),
    (record, seen) => const Err(ChatSkipNeedsOrderRead()),
    (record) => const ChatView(),
    (record) async => const Err(ChatNotOpen()),
    (record) => () {},
  );
  addTearDown(cubit.close);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const privacy = MethodChannel('com.flutterplaza.no_screenshot_methods');
  messenger.setMockMethodCallHandler(privacy, (call) async => true);
  addTearDown(() => messenger.setMockMethodCallHandler(privacy, null));
  return (context, request) => BlocProvider.value(
    value: cubit,
    child: ChatPanel(request: request),
  );
}

/// The summaries `Logics.summarize_trade` adds at 14 (`api/logics.py:2047-2139`) for this robot, the taker and buyer, paid over Lightning, or on chain with [swap].
Map<String, Object?> _summaryOf({bool swap = false}) => {
  'maker_summary': {
    'trade_fee_percent': 0.00025,
    'bond_size_sats': 4932,
    'bond_size_percent': 3.0,
    'is_buyer': false,
    'sent_sats': 164702,
    'received_fiat': 100.0,
    'trade_fee_sats': 41,
  },
  'taker_summary': {
    'trade_fee_percent': 0.00175,
    'bond_size_sats': 4932,
    'bond_size_percent': 3.0,
    'is_buyer': true,
    'sent_fiat': 100.0,
    'received_sats': 164126,
    if (!swap) ...{'payment_hash': 'f' * 64, 'preimage': 'processing'},
    'trade_fee_sats': 288,
    if (swap) ...{
      'is_swap': true,
      'received_onchain_sats': 160000,
      'address': 'bc1qexampleaddress0',
      'txid': 'a' * 64,
      'mining_fee_sats': 1200,
      'swap_fee_sats': 2926,
      'swap_fee_percent': 1.0,
    },
  },
  'platform_summary': {
    'contract_exchange_rate': 60849.5,
    'contract_timestamp': '2026-11-13T08:03:00Z',
    'contract_total_time': 1234.5,
    if (swap) 'routing_fee_sats': 0 else 'routing_budget_sats': 0.0,
    'trade_revenue_sats': 576,
  },
};

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
    await _loadAppFont();
    _statuses = await TradeScreenStatuses.make();
    _longNine = await (await TradeScreenStatuses.make(
      amount: 1234567.1234,
    )).chatting();
    _seen = {
      'nine': await _statuses.chatting(),
      'ten': await _statuses.fiatSent(),
      'thirteen': await _statuses.sendingSats(),
      'fourteen': await _statuses.succeeded(),
      'fourteenSummary': await _statuses.read(
        await _statuses.sendingSats(),
        orderJson(14, changes: _summaryOf()),
      ),
      'fourteenTxid': await _statuses.read(
        await _statuses.sendingSats(),
        orderJson(
          14,
          changes: {
            ..._summaryOf(swap: true),
            'num_satoshis': 164126,
            'sent_satoshis': 160000,
            'network': 'mainnet',
            'txid': 'a' * 64,
          },
        ),
      ),
      'fourteenQueued': await _statuses.read(
        await _statuses.sendingSats(),
        orderJson(
          14,
          changes: {
            'num_satoshis': 164126,
            'sent_satoshis': 160000,
            'network': 'mainnet',
            'tx_queued': true,
            'address': 'bc1qexampleaddress0',
          },
        ),
      ),
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
      // « Open Dispute »'s time come: the chat ends in an hour.
      'nineDisputable': await _statuses.read(
        await _statuses.waitingForPayout(),
        orderJson(9, expiresAt: tradeNow.add(const Duration(hours: 1))),
      ),
      'tenDisputable': await _statuses.read(
        await _statuses.chatting(),
        orderJson(10, expiresAt: tradeNow.add(const Duration(hours: 1))),
      ),
      // The chat's end moved later by the coordinator: « Open Dispute » in 12 hours.
      'nineLater': await _statuses.read(
        await _statuses.waitingForPayout(),
        orderJson(9, expiresAt: tradeNow.add(const Duration(hours: 30))),
      ),
    };
    final eleven = _seen['eleven']!;
    final sixteen = await _statuses.read(eleven, orderJson(16));
    _seen.addAll({
      'elevenSubmitted': await _statuses.read(
        eleven,
        orderJson(11, changes: {'statement_submitted': true}),
      ),
      'sixteen': sixteen,
      // The taker is the buyer here: 17, « Maker lost dispute », is won; 18 is lost.
      'seventeen': await _statuses.read(sixteen, orderJson(17)),
      'eighteen': await _statuses.read(sixteen, orderJson(18)),
    });
  });

  test('the dispute\'s statuses are those the state machine gives', () {
    expect(
      _seen['eleven']?.status,
      isA<InDispute>().having((d) => d.statementSubmitted, 'statement', false),
    );
    expect(
      _seen['elevenSubmitted']?.status,
      isA<InDispute>().having((d) => d.statementSubmitted, 'statement', true),
    );
    expect(_seen['sixteen']?.status, isA<WaitingDisputeResolution>());
    expect(_seen['seventeen']?.status, isA<DisputeWon>());
    expect(_seen['eighteen']?.status, isA<DisputeLost>());
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

  testWidgets(
    '9 and 10 with the chat panel (#93): in the step\'s place, between the prompt\'s text and the buttons, and nothing shown twice',
    (tester) async {
      final watch = _Watch();
      await _show(
        tester,
        watch: watch,
        chat: _chatPanel(tester),
        state: _watched('nine'),
      );
      await tester.pump();
      final panel = find.byKey(const ValueKey('trade-chat-panel'));
      expect(panel, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChatStepPanel),
          matching: find.byType(ChatPanel),
        ),
        findsOneWidget,
      );
      for (final text in [_hi, '⚠️ Beware scams', _confirmLabel]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('Type a message'), findsOneWidget);
      final top = tester.getTopLeft(panel).dy;
      expect(tester.getBottomLeft(find.text(_hi)).dy, lessThanOrEqualTo(top));
      expect(
        tester.getTopLeft(find.text(_confirmLabel)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(panel).dy),
      );
      watch.emit(_watched('ten'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ChatPanel), findsOneWidget);
      expect(find.text(_waitSeller), findsOneWidget);
      watch.emit(_watched('fourteen'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ChatPanel), findsNothing);
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

  group('14, the end of a successful trade (`Prompts/Successful.tsx`)', () {
    Finder star(int n) => find.byKey(ValueKey('trade-rate-star-$n'));
    IconButton starButton(WidgetTester tester, int n) =>
        tester.widget<IconButton>(star(n));
    late List<String> copied;

    setUp(() {
      copied = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add('${(call.arguments as Map)['text']}');
            }
            return null;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    testWidgets(
      'a star sends « Rate your trade experience » once, for the status shown; off while it runs',
      (tester) async {
        final rates = _Rates();
        final seen = _seenOf('fourteenSummary');
        await _show(
          tester,
          watch: _Watch(),
          rate: rates,
          state: TradeScreenStatuses.watched(seen),
        );
        expect(find.text('Rate your trade experience'), findsOneWidget);
        await _reveal(tester, star(4));
        await tester.tap(star(4));
        await tester.pump();
        expect(rates.asked.single.$2, 4);
        expect(identical(rates.asked.single.$1, seen), isTrue);
        expect(starButton(tester, 5).onPressed, isNull);
        rates.progress?.call(ChatStepProgress.sending);
        await tester.pump();
        expect(find.textContaining('Sending your request to'), findsOneWidget);
        await tester.tap(star(5), warnIfMissed: false);
        await tester.pump();
        expect(rates.asked, hasLength(1));
        rates.gate?.complete(Ok(ChatStepDone(_record, seen)));
        rates.gate = null;
        await tester.pump();
        await tester.pump();
        // Recorded: nothing said, as the reference.
        expect(find.textContaining('Sending your request to'), findsNothing);
        expect(find.textContaining('rating'), findsNothing);
        expect(starButton(tester, 5).onPressed, isNotNull);
        expect(
          tester
              .widget<Icon>(
                find.descendant(of: star(4), matching: find.byType(Icon)),
              )
              .icon,
          Icons.star,
        );
        expect(
          tester
              .widget<Icon>(
                find.descendant(of: star(5), matching: find.byType(Icon)),
              )
              .icon,
          Icons.star_border,
        );
        await tester.tap(star(5));
        await tester.pump();
        expect(rates.asked.map((asked) => asked.$2), [4, 5]);
        rates.gate?.complete(Ok(ChatStepDone(_record, seen)));
        await tester.pump();
        await tester.pump();
      },
    );

    testWidgets('an outcome unknown is said under the stars as such', (
      tester,
    ) async {
      final rates = _Rates();
      final seen = _seenOf('fourteenSummary');
      await _show(
        tester,
        watch: _Watch(),
        rate: rates,
        state: TradeScreenStatuses.watched(seen),
      );
      await _reveal(tester, star(2));
      await tester.tap(star(2));
      await tester.pump();
      rates.gate?.complete(Ok(ChatStepOutcomeUnknown(_record, seen)));
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Bull Market does not know whether your rating went through: the order does not show it. Tap a star to send it again.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('It keeps checking'), findsNothing);
    });

    testWidgets(
      'no stars without the rating; from an order read at 14 even unmarked, never from a status without one',
      (tester) async {
        await _show(
          tester,
          watch: _Watch(),
          state: _watched('fourteenSummary'),
        );
        expect(find.text('Rate your trade experience'), findsNothing);
        expect(star(1), findsNothing);
        final rates = _Rates();
        final seen = _seenOf('fourteenSummary');
        await _show(
          tester,
          watch: _Watch(),
          rate: rates,
          state: TradeScreenStatuses.watched(
            TradeSeen(seen.status, order: seen.order),
          ),
        );
        expect(starButton(tester, 3).onPressed, isNotNull);
        await _show(
          tester,
          watch: _Watch(),
          rate: rates,
          state: TradeScreenStatuses.watched(
            TradeSeen(seen.status, order: null, stored: true),
          ),
        );
        expect(starButton(tester, 3).onPressed, isNull);
        expect(
          find.text('Wait until the order is read again.'),
          findsOneWidget,
        );
        expect(rates.asked, isEmpty);
      },
    );

    testWidgets(
      'the trade summary: this robot\'s side first, the peer\'s and the coordinator\'s, and its export',
      (tester) async {
        final seen = _seenOf('fourteenSummary');
        await _show(
          tester,
          watch: _Watch(),
          state: TradeScreenStatuses.watched(seen),
        );
        await _reveal(tester, find.text('Trade Summary'));
        for (final text in [
          'Buyer',
          'User role',
          '100 EUR',
          'Sent',
          '164,126 Sats',
          'BTC received',
          '288 Sats (0.175%)',
          'Trade fee',
          '4,932 Sats (3%)',
          'Taker bond',
          'Unlocked',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        await tester.tap(find.byKey(const ValueKey('trade-summary-maker')));
        await tester.pump();
        for (final text in [
          'Seller',
          'Received',
          '164,702 Sats',
          'BTC sent',
          '41 Sats (0.025%)',
          'Maker bond',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        expect(find.text('Buyer'), findsNothing);
        final order = seen.order ?? fail('no order');
        // The coordinator's view, named by the coordinator.
        await tester.tap(find.byTooltip(order.coordinator.longAlias));
        await tester.pump();
        for (final text in [
          '576 Sats',
          'Coordinator trade revenue',
          '0 Sats',
          'Routing budget',
          '60,849.50 EUR/BTC',
          'Contract exchange rate',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        await tester.tap(find.byKey(const ValueKey('trade-summary-export')));
        await tester.pump();
        expect(find.text('Copied!'), findsOneWidget);
        final text = copied.single;
        // The text itself, in the reference's order and with JavaScript's numbers (`100`, not `100.0`), as `JSON.stringify(summary, null, 2)` writes it.
        expect(
          text,
          const JsonEncoder.withIndent('  ').convert({
            'coordinator': order.coordinator.longAlias,
            'order_id': order.id,
            'currency': 'EUR',
            'robot': order.taker?.nickname,
            'role': 'taker',
            'maker': {
              'trade_fee_percent': 0.00025,
              'bond_size_sats': 4932,
              'bond_size_percent': 3,
              'is_buyer': false,
              'sent_sats': 164702,
              'received_fiat': 100,
              'trade_fee_sats': 41,
            },
            'taker': {
              'trade_fee_percent': 0.00175,
              'bond_size_sats': 4932,
              'bond_size_percent': 3,
              'is_buyer': true,
              'sent_fiat': 100,
              'received_sats': 164126,
              'payment_hash': 'f' * 64,
              'preimage': 'processing',
              'trade_fee_sats': 288,
            },
            'platform': {
              'contract_exchange_rate': 60849.5,
              'contract_timestamp': '2026-11-13T08:03:00.000Z',
              'contract_total_time': 1234.5,
              'routing_budget_sats': 0,
              'trade_revenue_sats': 576,
            },
          }),
        );
      },
    );

    testWidgets(
      'on chain: the export writes the swap\'s block of this robot\'s side',
      (tester) async {
        final seen = _seenOf('fourteenTxid');
        await _show(tester, watch: _Watch(), state: _watched('fourteenTxid'));
        final export = find.byKey(const ValueKey('trade-summary-export'));
        await _reveal(tester, export);
        await tester.tap(export);
        await tester.pump();
        final order = seen.order ?? fail('no order');
        expect(
          copied.single,
          const JsonEncoder.withIndent('  ').convert({
            'coordinator': order.coordinator.longAlias,
            'order_id': order.id,
            'currency': 'EUR',
            'robot': order.taker?.nickname,
            'role': 'taker',
            'maker': {
              'trade_fee_percent': 0.00025,
              'bond_size_sats': 4932,
              'bond_size_percent': 3,
              'is_buyer': false,
              'sent_sats': 164702,
              'received_fiat': 100,
              'trade_fee_sats': 41,
            },
            'taker': {
              'trade_fee_percent': 0.00175,
              'bond_size_sats': 4932,
              'bond_size_percent': 3,
              'is_buyer': true,
              'sent_fiat': 100,
              'received_sats': 164126,
              'trade_fee_sats': 288,
              'is_swap': true,
              'received_onchain_sats': 160000,
              'address': 'bc1qexampleaddress0',
              'txid': 'a' * 64,
              'mining_fee_sats': 1200,
              'swap_fee_sats': 2926,
              'swap_fee_percent': 1,
            },
            'platform': {
              'contract_exchange_rate': 60849.5,
              'contract_timestamp': '2026-11-13T08:03:00.000Z',
              'contract_total_time': 1234.5,
              'trade_revenue_sats': 576,
            },
          }),
        );
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'a peer\'s side the coordinator gave invalid: no view of it and no export',
      (tester) async {
        final summary = _summaryOf();
        (summary['maker_summary'] as Map<String, Object?>)['is_buyer'] = 'no';
        final seen = await _statuses.read(
          await _statuses.sendingSats(),
          orderJson(14, changes: summary),
        );
        await _show(
          tester,
          watch: _Watch(),
          state: TradeScreenStatuses.watched(seen),
        );
        await _reveal(tester, find.text('Trade Summary'));
        expect(find.text('Buyer'), findsOneWidget);
        expect(find.byKey(const ValueKey('trade-summary-maker')), findsNothing);
        expect(
          find.byKey(const ValueKey('trade-summary-taker')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('trade-summary-export')),
          findsNothing,
        );
      },
    );

    testWidgets('a rating not sent says so in its own words', (tester) async {
      final rates = _Rates();
      final seen = _seenOf('fourteenSummary');
      await _show(
        tester,
        watch: _Watch(),
        rate: rates,
        state: TradeScreenStatuses.watched(seen),
      );
      for (final (refusal, said) in [
        (
          const ChatStepReadFailed(),
          'The order could not be read again from ${seen.order?.coordinator.longAlias}: your rating was not sent.',
        ),
        (const ChatStepNotOffered(), 'Your rating was not sent.'),
      ]) {
        await _reveal(tester, star(3));
        await tester.tap(star(3));
        await tester.pump();
        rates.gate?.complete(Err(refusal));
        rates.gate = null;
        await tester.pump();
        await tester.pump();
        expect(find.text(said), findsOneWidget);
        expect(find.textContaining('confirmation'), findsNothing);
      }
    });

    group('« Rate your host » (#95)', () {
      Finder hostStar(int n) => find.byKey(ValueKey('trade-host-star-$n'));
      IconButton hostButton(WidgetTester tester, int n) =>
          tester.widget<IconButton>(hostStar(n));

      testWidgets(
        'the token asked once; the stars off until it comes; each tap publishes once; the thanks of the reference',
        (tester) async {
          final host = _HostRates();
          addTearDown(host.cubit.close);
          final watch = _Watch();
          final seen = _seenOf('fourteenSummary');
          await _show(
            tester,
            watch: watch,
            rate: _Rates(),
            hostRating: host.cubit,
            state: TradeScreenStatuses.watched(seen),
          );
          expect(find.text('Rate your host'), findsOneWidget);
          expect(find.text('Temple of Sats'), findsWidgets);
          expect(host.asked, [seen]);
          expect(
            find.text(
              'Asking Temple of Sats for permission to publish your rating…',
            ),
            findsOneWidget,
          );
          for (var n = 1; n <= 5; n++) {
            expect(hostButton(tester, n).onPressed, isNull);
          }
          // A new read of the end asks nothing more.
          watch.emit(TradeScreenStatuses.watched(seen));
          await tester.pump();
          expect(host.asked, hasLength(1));
          host.give();
          await tester.pump();
          await tester.pump();
          expect(find.textContaining('permission'), findsNothing);
          expect(hostButton(tester, 5).onPressed, isNotNull);
          // Nothing said before a tap.
          expect(find.textContaining('Thank you'), findsNothing);
          await _reveal(tester, hostStar(5));
          await tester.tap(hostStar(5));
          await tester.pump();
          expect(host.published, hasLength(1));
          expect(identical(host.published.single.$1, seen), isTrue);
          expect(host.published.single.$2, _HostRates.given);
          expect(host.published.single.$3, 5);
          expect(
            find.text('Thank you! Temple of Sats loves you too'),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.favorite), findsOneWidget);
          expect(
            find.text(
              'RoboSats gets better with more liquidity and users. Tell a bitcoiner friend about Robosats!',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('Let us know'), findsNothing);
          // The same star again publishes again, as each tap does.
          await tester.tap(hostStar(5));
          await tester.pump();
          await tester.tap(hostStar(3));
          await tester.pump();
          expect(host.published.map((p) => p.$3), [5, 5, 3]);
          expect(find.text('Thank you for using Robosats!'), findsOneWidget);
          expect(find.textContaining('loves you'), findsNothing);
          expect(find.byIcon(Icons.favorite), findsNothing);
          final improve = find.byKey(const ValueKey('trade-host-improve'));
          expect(
            tester
                .widget<RichText>(
                  find.descendant(of: improve, matching: find.byType(RichText)),
                )
                .text
                .toPlainText(),
            'Let us know how the platform could improve (SimpleX / Matrix / Github)',
          );
          // The platform's stars are not touched by the host's.
          expect(
            tester
                .widget<Icon>(
                  find.descendant(
                    of: find.byKey(const ValueKey('trade-rate-star-1')),
                    matching: find.byType(Icon),
                  ),
                )
                .icon,
            Icons.star_border,
          );
        },
      );

      testWidgets('a link of the thanks is shown for copy, never opened', (
        tester,
      ) async {
        final host = _HostRates();
        addTearDown(host.cubit.close);
        await _show(
          tester,
          watch: _Watch(),
          rate: _Rates(),
          hostRating: host.cubit,
          state: _watched('fourteenSummary'),
        );
        host.give();
        await tester.pump();
        await tester.pump();
        await _reveal(tester, hostStar(2));
        await tester.tap(hostStar(2));
        await tester.pump();
        final improve = find.byKey(const ValueKey('trade-host-improve'));
        await _reveal(tester, improve);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: improve, matching: find.byType(RichText)),
        );
        final links = <String, String>{
          'SimpleX': simplexGroupUrl,
          'Matrix': HostRatingSection.matrixUrl,
          'Github': HostRatingSection.githubUrl,
        };
        for (final MapEntry(key: name, value: url) in links.entries) {
          var tapped = false;
          paragraph.text.visitChildren((span) {
            if (span is TextSpan && span.text == name) {
              final recognizer = span.recognizer;
              if (recognizer is TapGestureRecognizer) {
                recognizer.onTap?.call();
                tapped = true;
              }
            }
            return !tapped;
          });
          expect(tapped, isTrue, reason: name);
          await tester.pumpAndSettle();
          final sheet = find.byType(CoordinatorLinkSheet);
          expect(sheet, findsOneWidget, reason: name);
          expect(tester.widget<CoordinatorLinkSheet>(sheet).value, url);
          expect(tester.widget<CoordinatorLinkSheet>(sheet).title, name);
          Navigator.of(tester.element(sheet)).pop();
          await tester.pumpAndSettle();
        }
      });

      testWidgets(
        'no token: the stars stay off and a line says the rating cannot be published',
        (tester) async {
          final host = _HostRates();
          addTearDown(host.cubit.close);
          await _show(
            tester,
            watch: _Watch(),
            rate: _Rates(),
            hostRating: host.cubit,
            state: _watched('fourteenSummary'),
          );
          host.refuse();
          await tester.pump();
          await tester.pump();
          expect(
            find.text(
              'Your rating cannot be published: Temple of Sats could not be asked for permission, or refused it. Open this trade again to try again.',
            ),
            findsOneWidget,
          );
          for (var n = 1; n <= 5; n++) {
            expect(hostButton(tester, n).onPressed, isNull);
          }
          expect(host.published, isEmpty);
          expect(host.asked, hasLength(1));
        },
      );

      testWidgets(
        'a finished trade opened again: the token asked only once the order is read, the stars off again for a status read from no order',
        (tester) async {
          final host = _HostRates();
          addTearDown(host.cubit.close);
          final watch = _Watch();
          final read = _seenOf('fourteenSummary');
          // The end from the records, before the read of the order: it offers no rating.
          final fromRecords = TradeSeen(read.status, order: null);
          await _show(
            tester,
            watch: watch,
            rate: _Rates(),
            hostRating: host.cubit,
            state: TradeScreenStatuses.watched(fromRecords),
          );
          expect(find.text('Rate your host'), findsOneWidget);
          expect(host.asked, isEmpty);
          expect(find.textContaining('permission'), findsNothing);
          expect(hostButton(tester, 5).onPressed, isNull);
          watch.emit(TradeScreenStatuses.watched(read));
          await tester.pump();
          await tester.pump();
          expect(host.asked, [read]);
          host.give();
          await tester.pump();
          await tester.pump();
          expect(hostButton(tester, 5).onPressed, isNotNull);
          await _reveal(tester, hostStar(4));
          await tester.tap(hostStar(4));
          await tester.pump();
          expect(host.published.map((p) => p.$3), [4]);
          // A later status from no order offers no rating: the host's stars are off again, as the trade's, nothing is asked again, and the star tapped stays shown although the summary went.
          watch.emit(TradeScreenStatuses.watched(fromRecords));
          await tester.pump();
          await tester.pump();
          expect(hostButton(tester, 5).onPressed, isNull);
          expect(host.asked, hasLength(1));
          expect(
            tester
                .widget<Icon>(
                  find.descendant(of: hostStar(4), matching: find.byType(Icon)),
                )
                .icon,
            Icons.star,
          );
          expect(host.published, hasLength(1));
        },
      );

      testWidgets(
        'as the route builds the trade page (`P2pRouter.tradePage`): one cubit per page, closed with it',
        (tester) async {
          tester.view
            ..physicalSize = const Size(390, 1200) * 3
            ..devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final watch = _Watch();
          final made = <_HostRates>[];
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
                rate: _Rates().call,
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
            ..registerFactoryParam<HostRatingCubit, TradeRecord, void>((
              record,
              _,
            ) {
              final host = _HostRates();
              made.add(host);
              return host.cubit;
            });
          await tester.pumpWidget(
            MaterialApp(
              theme: testTheme,
              localizationsDelegates: P2pLocalizations.localizationsDelegates,
              supportedLocales: P2pLocalizations.supportedLocales,
              home: Scaffold(
                body: P2pRouter.tradePage(locator, P2pTradeRouteArgs(_record)),
              ),
            ),
          );
          await tester.pump();
          watch.emit(_watched('fourteenSummary'));
          await tester.pump();
          await tester.pump();
          expect(find.byType(HostRatingSection), findsOneWidget);
          expect(made, hasLength(1));
          expect(made.single.asked, hasLength(1));
          expect(
            tester
                .element(find.byType(HostRatingSection))
                .read<HostRatingCubit>(),
            same(made.single.cubit),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          expect(made.single.cubit.isClosed, isTrue);
        },
      );

      testWidgets(
        'not asked, and not shown, where the screen offers no rating',
        (tester) async {
          final host = _HostRates();
          addTearDown(host.cubit.close);
          await _show(
            tester,
            watch: _Watch(),
            hostRating: host.cubit,
            state: _watched('fourteenSummary'),
          );
          expect(find.text('Rate your host'), findsNothing);
          expect(host.asked, isEmpty);
        },
      );

      for (final locale in const [Locale('en'), Locale('fr')]) {
        for (final scale in const [2.0, 3.0]) {
          testWidgets(
            '${locale.languageCode} at ×$scale on 320 points, in the app font: « Rate your host », its lines and its thanks, nothing cut, no word broken',
            (tester) async {
              final host = _HostRates();
              addTearDown(host.cubit.close);
              await _show(
                tester,
                watch: _Watch(),
                rate: _Rates(),
                hostRating: host.cubit,
                locale: locale,
                size: const Size(320, 640),
                textScale: scale,
                appFont: true,
                state: _watched('fourteenSummary'),
              );
              _expectNothingCut(tester, 'asking');
              _expectNoWordBroken(tester, 'asking');
              host.give();
              await tester.pump();
              await tester.pump();
              for (final n in [5, 3]) {
                await _reveal(tester, hostStar(n));
                await tester.tap(hostStar(n));
                await tester.pump();
                _expectNothingCut(tester, '$n stars');
                _expectNoWordBroken(tester, '$n stars');
              }
              final unavailable = _HostRates();
              addTearDown(unavailable.cubit.close);
              await _show(
                tester,
                watch: _Watch(),
                rate: _Rates(),
                hostRating: unavailable.cubit,
                locale: locale,
                size: const Size(320, 640),
                textScale: scale,
                appFont: true,
                state: _watched('fourteenSummary'),
              );
              unavailable.refuse();
              await tester.pump();
              await tester.pump();
              _expectNothingCut(tester, 'unavailable');
              _expectNoWordBroken(tester, 'unavailable');
            },
          );
        }
      }
    });

    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets(
          '${locale.languageCode} at ×$scale on 320 points, in the app font: no word broken at 14, the stars and each view of the summary',
          (tester) async {
            await _show(
              tester,
              watch: _Watch(),
              rate: _Rates(),
              locale: locale,
              size: const Size(320, 640),
              textScale: scale,
              appFont: true,
              state: _watched('fourteenSummary'),
            );
            _expectNothingCut(tester, 'taker');
            _expectNoWordBroken(tester, 'taker');
            // A row's two figures stacked, each with the row's whole width, rather than shrunk side by side.
            final en = locale.languageCode == 'en';
            expect(
              tester
                  .getTopLeft(
                    find.text(en ? 'Trade fee' : 'Frais de transaction'),
                  )
                  .dy,
              greaterThan(
                tester
                    .getTopLeft(find.text(en ? 'BTC received' : 'BTC reçus'))
                    .dy,
              ),
            );
            for (final view in ['maker', 'platform']) {
              final tile = find.byKey(ValueKey('trade-summary-$view'));
              await _reveal(tester, tile);
              await tester.tap(tile);
              await tester.pump();
              _expectNothingCut(tester, view);
              _expectNoWordBroken(tester, view);
            }
          },
        );
      }
    }

    testWidgets(
      'on chain: « Your TXID » copies the transaction, the swap\'s costs in the summary',
      (tester) async {
        await _show(tester, watch: _Watch(), state: _watched('fourteenTxid'));
        expect(find.text('Your TXID'), findsOneWidget);
        expect(find.text('Sending coins'), findsNothing);
        // The transaction is copied, never written nor opened, as the reference.
        expect(find.textContaining('a' * 64), findsNothing);
        await tester.tap(find.byTooltip('Copy the TXID'));
        await tester.pump();
        expect(copied, ['a' * 64]);
        expect(find.text('Copied!'), findsOneWidget);
        await _reveal(tester, find.text('Trade Summary'));
        for (final text in [
          '2,926 Sats (1%)',
          'Onchain swap fee',
          '1,200 Sats',
          'Mining fee',
        ]) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'on chain, queued: « Sending coins » copies the address; no summary without one',
      (tester) async {
        await _show(tester, watch: _Watch(), state: _watched('fourteenQueued'));
        expect(find.text('Sending coins'), findsOneWidget);
        expect(find.text('Your TXID'), findsNothing);
        expect(find.text('Trade Summary'), findsNothing);
        await tester.tap(find.byTooltip('Copy the address'));
        await tester.pump();
        expect(copied, ['bc1qexampleaddress0']);
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'in French, the reference\'s French and the separators of the language',
      (tester) async {
        await _show(
          tester,
          watch: _Watch(),
          rate: _Rates(),
          locale: const Locale('fr'),
          state: _watched('fourteenSummary'),
        );
        expect(
          find.text('Évaluez votre expérience de trading'),
          findsOneWidget,
        );
        await _reveal(tester, find.text('Résumé de la transaction'));
        expect(find.text('Acheteur'), findsOneWidget);
        expect(find.text('Rôle utilisateur'), findsOneWidget);
        expect(find.textContaining('(0,175%)'), findsOneWidget);
        expect(find.text('Caution du preneur'), findsOneWidget);
        expect(find.text('Débloqué'), findsOneWidget);
      },
    );
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
                  now: () => tradeNow,
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
    testWidgets('a cancel running, from wherever it was asked: « … » off', (
      tester,
    ) async {
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
    });

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
        // The places of « Audit Chat » and « Export »: empty for now; « Open Dispute » not wired in this test.
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

  group('the reviews of « Payment failed? » and the collaborative cancel (#95)', () {
    testWidgets(
      '« … » is one button for a screen reader, with its tap and the reference\'s label',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _show(tester, watch: _Watch(), state: _watched('nine'));
        expect(
          tester.getSemantics(find.bySemanticsLabel('open options')),
          matchesSemantics(
            label: 'open options',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
        expect(find.bySemanticsLabel('Order options'), findsNothing);
        handle.dispose();
      },
    );

    testWidgets(
      'the peer asks while the cancel\'s dialog is open: the button turns into « Accept Cancelation »',
      (tester) async {
        final watch = _Watch();
        final cancels = _Cancels();
        await _show(
          tester,
          watch: watch,
          cancels: cancels,
          state: _watched('nine'),
        );
        await _reveal(tester, find.byIcon(Icons.more_horiz));
        await tester.tap(find.byIcon(Icons.more_horiz));
        await _settleDialog(tester);
        await tester.tap(find.text('Collaborative Cancel'));
        await _settleDialog(tester);
        expect(find.text('Ask for Cancel'), findsOneWidget);
        watch.emit(_watched('ninePeerAsked'));
        await _settleDialog(tester);
        expect(find.text('Ask for Cancel'), findsNothing);
        expect(find.text('Accept Cancelation'), findsOneWidget);
        expect(
          find.textContaining('Your peer has asked for cancellation'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'an ask whose answer was lost: said as a request; gone once the read shows it, or at 10',
      (tester) async {
        const unknown =
            'Bull Market does not know yet whether your request went through. It keeps checking.';
        for (final next in ['nineAsked', 'ten']) {
          final watch = _Watch();
          final cancels = _Cancels()
            ..answer = (record, seen) => Ok(CancelOutcomeUnknown(record, seen));
          await _show(
            tester,
            watch: watch,
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
          expect(find.text(unknown), findsOneWidget, reason: next);
          expect(
            find.textContaining('whether the cancel went through'),
            findsNothing,
          );
          // The same 9 read again: still said.
          watch.emit(_watched('nine'));
          await _settleDialog(tester);
          expect(find.text(unknown), findsOneWidget, reason: next);
          watch.emit(_watched(next));
          await _settleDialog(tester);
          expect(find.text(unknown), findsNothing, reason: next);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      '« Payment failed? » unknown at 10, then the watch reads 10 again: the notice stays',
      (tester) async {
        final watch = _Watch();
        final undo = _FiatSent();
        await _show(
          tester,
          watch: watch,
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
        undo.gate?.complete(Ok(ChatStepOutcomeUnknown(_record, _seen['ten']!)));
        await _settleDialog(tester);
        const unknown =
            'Bull Market does not know yet whether your request went through. It keeps checking.';
        expect(find.text(unknown), findsOneWidget);
        watch.emit(_watched('ten'));
        await _settleDialog(tester);
        expect(find.text(unknown), findsOneWidget);
        watch.emit(_watched('nine'));
        await _settleDialog(tester);
        expect(find.text(unknown), findsNothing);
      },
    );

    for (final (locale, two, one) in const [
      (Locale('en'), 'Wait 2 seconds', 'Wait 1 second'),
      (Locale('fr'), 'Attendez 2 secondes', 'Attendez 1 seconde'),
    ]) {
      testWidgets(
        '${locale.languageCode}: the undo\'s counter read « $two », then « $one » (second pass of the review of #145)',
        (tester) async {
          final handle = tester.ensureSemantics();
          await _show(
            tester,
            watch: _Watch(),
            locale: locale,
            undoFiatSent: _FiatSent(),
            state: _watched('ten'),
          );
          final quiet = find.byType(Expanded).last;
          await _reveal(tester, quiet);
          await tester.tap(quiet);
          await _settleDialog(tester);
          // Built at 60, one tick a second once open, as in the test below.
          await tester.pump(const Duration(seconds: 58));
          expect(find.bySemanticsLabel(two), findsOneWidget);
          await tester.pump(const Duration(seconds: 1));
          expect(find.bySemanticsLabel(one), findsOneWidget);
          handle.dispose();
        },
      );
    }

    testWidgets(
      'the undo\'s counter: kept across openings, running only while open, 300 after « Confirm », read in seconds',
      (tester) async {
        final handle = tester.ensureSemantics();
        final undo = _FiatSent();
        await _show(
          tester,
          watch: _Watch(),
          undoFiatSent: undo,
          state: _watched('ten'),
        );
        Future<void> open() async {
          await _reveal(tester, find.text('Payment failed?'));
          await tester.tap(find.text('Payment failed?'));
          await _settleDialog(tester);
        }

        Future<void> back() async {
          await tester.ensureVisible(find.text('Go back'));
          await tester.pump();
          await tester.tap(find.text('Go back'));
          await _settleDialog(tester);
        }

        await open();
        // The dialog's counter starts once it is built: 20 s, 20 ticks.
        await tester.pump(const Duration(seconds: 20));
        expect(find.text('Wait (40)'), findsOneWidget);
        expect(find.bySemanticsLabel('Wait 40 seconds'), findsOneWidget);
        await back();
        // Closed: the counter does not run.
        await tester.pump(const Duration(seconds: 30));
        await open();
        // Kept from the first opening, not set back to 60.
        expect(
          find.textContaining(RegExp(r'^Wait \((3[5-9]|40)\)$')),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 45));
        await tester.ensureVisible(find.text('Confirm'));
        await tester.pump();
        await tester.tap(find.text('Confirm'));
        await _settleDialog(tester);
        undo.gate?.complete(
          Ok(
            ChatStepNotDone(
              _record,
              _seen['ten']!,
              cause: const CoordinatorTransportBusy(),
            ),
          ),
        );
        await _settleDialog(tester);
        undo.gate = null;
        await open();
        // 300 after « Confirm ».
        expect(
          find.textContaining(RegExp(r'^Wait \((300|29\d)\)$')),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets('the ask\'s wait: a bar, then the long wait\'s line', (
      tester,
    ) async {
      final cancels = _Cancels()..gate = Completer<void>();
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
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      const still = 'Still waiting for Temple of Sats. Tor can take a minute.';
      expect(find.text(still), findsNothing);
      await tester.pump(const Duration(seconds: 31));
      expect(find.text(still), findsOneWidget);
      cancels.gate?.complete();
      await _settleDialog(tester);
      expect(find.text(still), findsNothing);
    });

    testWidgets(
      'at 9 from a status not marked stored: « Collaborative Cancel » off',
      (tester) async {
        final nine = _seen['nine']!;
        await _show(
          tester,
          watch: _Watch(),
          state: TradeScreenStatuses.watched(
            TradeSeen(nine.status, order: nine.order),
          ),
        );
        await _reveal(tester, find.byIcon(Icons.more_horiz));
        await tester.tap(find.byIcon(Icons.more_horiz));
        await _settleDialog(tester);
        await tester.tap(
          find.text('Collaborative Cancel'),
          warnIfMissed: false,
        );
        await _settleDialog(tester);
        expect(find.text('Collaborative cancel the order?'), findsNothing);
      },
    );

    testWidgets(
      'the peer asked, the status kept from no order: the reference\'s words without a nickname',
      (tester) async {
        final seen = _seen['ninePeerAsked']!;
        await _show(
          tester,
          watch: _Watch(),
          state: TradeScreenStatuses.watched(
            TradeSeen(seen.status, order: null, stored: true),
          ),
        );
        expect(
          find.text('Your peer has asked for cancellation'),
          findsOneWidget,
        );
      },
    );

    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets(
          '${locale.languageCode} at ×$scale on 320 points, in the app font: no word broken in « Order options » at 10, the two dialogs and « Payment failed? »',
          (tester) async {
            for (final (name, open) in [
              ('ten', 'options'),
              ('ten', 'undo'),
              ('nine', 'collab'),
            ]) {
              await _show(
                tester,
                watch: _Watch(),
                locale: locale,
                size: const Size(320, 640),
                textScale: scale,
                appFont: true,
                state: _watched(name),
              );
              _expectNoWordBroken(tester, '$name panel');
              final options = find.byIcon(Icons.more_horiz);
              if (open == 'undo') {
                final button = find.byType(Expanded).last;
                await _reveal(tester, button);
                await tester.tap(button);
                await _settleDialog(tester);
              } else {
                await _reveal(tester, options);
                await tester.tap(options);
                await _settleDialog(tester);
                if (open == 'collab') {
                  final collab = find.byIcon(Icons.handshake_outlined);
                  await tester.ensureVisible(collab);
                  await tester.pump();
                  await tester.tap(collab);
                  await _settleDialog(tester);
                }
              }
              _expectNoWordBroken(tester, '$name $open');
              await tester.pumpWidget(const SizedBox.shrink());
            }
          },
        );
      }
    }
  });

  group('« Open Dispute » (#95)', () {
    Future<void> openOptions(WidgetTester tester) async {
      await _reveal(tester, find.byIcon(Icons.more_horiz));
      await tester.tap(find.byIcon(Icons.more_horiz));
      await _settleDialog(tester);
    }

    TradeButton disputeButton(WidgetTester tester) => tester.widget(
      find.ancestor(
        of: find.text('Open Dispute'),
        matching: find.byType(TradeButton),
      ),
    );

    testWidgets(
      'before its time: off in « Order options », the reference\'s wait under it, counting down; a tap sends nothing',
      (tester) async {
        var clock = tradeNow;
        final dispute = _FiatSent();
        await _show(
          tester,
          watch: _Watch(),
          dispute: dispute,
          now: () => clock,
          state: _watched('nine'),
        );
        await openOptions(tester);
        // The chat's 24 hours from the read: open 18 hours before its end.
        expect(disputeButton(tester).onPressed, isNull);
        expect(
          find.text('To open a dispute you need to wait 6h 00m'),
          findsOneWidget,
        );
        clock = clock.add(const Duration(minutes: 61));
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.text('To open a dispute you need to wait 4h 59m'),
          findsOneWidget,
        );
        await tester.tap(find.text('Open Dispute'), warnIfMissed: false);
        await _settleDialog(tester);
        expect(find.text('Do you want to open a dispute?'), findsNothing);
        // Its time comes while the dialog is open: on.
        clock = tradeNow.add(const Duration(hours: 6, seconds: 30));
        await tester.pump(const Duration(seconds: 1));
        expect(disputeButton(tester).onPressed, isNotNull);
        expect(find.textContaining('To open a dispute'), findsNothing);
        expect(dispute.asked, isEmpty);
      },
    );

    for (final name in ['nineDisputable', 'tenDisputable']) {
      testWidgets(
        '$name: « Open Dispute » leads to the reference\'s dialog; « Disagree » sends nothing, « Agree and open dispute » sends once, its step said',
        (tester) async {
          final dispute = _FiatSent();
          await _show(
            tester,
            watch: _Watch(),
            dispute: dispute,
            state: _watched(name),
          );
          await openOptions(tester);
          expect(disputeButton(tester).onPressed, isNotNull);
          expect(find.textContaining('To open a dispute'), findsNothing);
          await tester.tap(find.text('Open Dispute'));
          await _settleDialog(tester);
          expect(find.text('Do you want to open a dispute?'), findsOneWidget);
          expect(
            find.textContaining(
              'The RoboSats staff will examine the statements and evidence provided.',
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining('Make sure to EXPORT the chat log.'),
            findsOneWidget,
          );
          await tester.ensureVisible(find.text('Disagree'));
          await tester.pump();
          await tester.tap(find.text('Disagree'));
          await _settleDialog(tester);
          expect(dispute.asked, isEmpty);
          await openOptions(tester);
          await tester.tap(find.text('Open Dispute'));
          await _settleDialog(tester);
          await tester.ensureVisible(find.text('Agree and open dispute'));
          await tester.pump();
          await tester.tap(find.text('Agree and open dispute'));
          await _settleDialog(tester);
          expect(dispute.asked, [_seen[name]]);
          dispute.progress?.call(ChatStepProgress.sending);
          await tester.pump();
          expect(
            find.text('Opening the dispute at Temple of Sats…'),
            findsOneWidget,
          );
          dispute.gate?.complete(Ok(ChatStepDone(_record, _seen['eleven']!)));
          await _settleDialog(tester);
          expect(dispute.asked, hasLength(1));
        },
      );
    }

    testWidgets('from a status not marked stored: no « Open Dispute »', (
      tester,
    ) async {
      final seen = _seen['nineDisputable']!;
      await _show(
        tester,
        watch: _Watch(),
        dispute: _FiatSent(),
        state: TradeScreenStatuses.watched(
          TradeSeen(seen.status, order: seen.order),
        ),
      );
      await openOptions(tester);
      expect(find.text('Open Dispute'), findsNothing);
    });

    /// « Open Dispute » pressed and agreed to, at 9 with its time come; the use case's answer awaited.
    Future<_FiatSent> agreed(
      WidgetTester tester, {
      DateTime Function()? now,
    }) async {
      final dispute = _FiatSent();
      final watch = _Watch();
      _lastWatch = watch;
      await _show(
        tester,
        watch: watch,
        dispute: dispute,
        now: now,
        state: _watched('nineDisputable'),
      );
      await openOptions(tester);
      await tester.tap(find.text('Open Dispute'));
      await _settleDialog(tester);
      await tester.ensureVisible(find.text('Agree and open dispute'));
      await tester.pump();
      await tester.tap(find.text('Agree and open dispute'));
      await _settleDialog(tester);
      return dispute;
    }

    testWidgets(
      'refused as too early after its fresh read (the chat\'s end moved later): the reference coordinator\'s words, no countdown that stands still, gone at the very second « Open Dispute » turns on (review of #156)',
      (tester) async {
        var clock = tradeNow;
        final dispute = await agreed(tester, now: () => clock);
        final opensAt = tradeNow.add(const Duration(hours: 12));
        dispute.gate?.complete(
          Err(
            ChatStepTooEarly(
              opensAt,
              const Duration(hours: 12),
              seen: _seen['nineLater'],
              record: _record,
            ),
          ),
        );
        await _settleDialog(tester);
        // Shown with the fresh read the refusal carries, before the watch reads again, which may fail (review of #156).
        const tooEarly =
            'Cannot open a dispute yet. You need to wait until 18 hours before expiry.';
        expect(find.textContaining(tooEarly), findsOneWidget);
        expect(find.textContaining('To open a dispute you need'), findsNothing);
        clock = opensAt.subtract(const Duration(seconds: 1));
        await tester.pump(
          const Duration(hours: 12) - const Duration(seconds: 2),
        );
        expect(find.textContaining(tooEarly), findsOneWidget);
        clock = opensAt;
        await tester.pump(const Duration(seconds: 2));
        expect(find.textContaining(tooEarly), findsNothing);
        // « Open Dispute » on at that same time.
        await openOptions(tester);
        expect(disputeButton(tester).onPressed, isNotNull);
      },
    );

    testWidgets(
      'a new read that moves the chat\'s end earlier ends the refusal at once (review of #156)',
      (tester) async {
        final dispute = await agreed(tester);
        dispute.gate?.complete(
          Err(
            ChatStepTooEarly(
              tradeNow.add(const Duration(hours: 12)),
              const Duration(hours: 12),
            ),
          ),
        );
        await _settleDialog(tester);
        _lastWatch!.emit(_watched('nineLater'));
        await tester.pump();
        await tester.pump();
        expect(
          find.textContaining('Cannot open a dispute yet.'),
          findsOneWidget,
        );
        _lastWatch!.emit(_watched('nineDisputable'));
        await tester.pump();
        await tester.pump();
        expect(find.textContaining('Cannot open a dispute yet.'), findsNothing);
      },
    );

    for (final (what, outcome, text)
        in <
          (String, Result<ChatStepOutcome, ChatStepRefusal> Function(), String)
        >[
          (
            'the fresh read failed (Tor)',
            () =>
                const Err(ChatStepReadFailed(cause: CoordinatorUnreachable())),
            'The order could not be read again from Temple of Sats: the dispute was not opened.',
          ),
          (
            'refused as not now (1013)',
            () => Ok(
              ChatStepNotDone(
                _record,
                _seen['thirteen']!,
                cause: const TradeActionNotNow(fromLastRead: false),
              ),
            ),
            'The trade moved on: Temple of Sats did not open the dispute.',
          ),
          (
            'its answer lost',
            () => Ok(ChatStepOutcomeUnknown(_record, _seen['nineDisputable']!)),
            'Bull Market does not know yet whether the dispute was opened. It keeps checking: the dispute shows here once it is open.',
          ),
          // The five others (review of #156).
          (
            'not offered by the status seen',
            () => const Err(ChatStepNotOffered()),
            'Wait until the order is read again. The dispute was not opened.',
          ),
          (
            'the fresh read shows another status',
            () => Err(ChatStepStatusMoved(_seenOf('tenDisputable'))),
            'The trade moved on: the dispute was not opened.',
          ),
          (
            'never sent, the transport busy',
            () => Ok(
              ChatStepNotDone(
                _record,
                _seenOf('nineDisputable'),
                cause: const CoordinatorTransportBusy(),
              ),
            ),
            'Too many requests are waiting for this coordinator. Try again in a moment. The dispute was not opened.',
          ),
          (
            'never sent, the coordinator off the network',
            () => Ok(
              ChatStepNotDone(
                _record,
                _seenOf('nineDisputable'),
                cause: const CoordinatorNotOnNetwork(),
              ),
            ),
            'Temple of Sats is offline: the dispute was not opened.',
          ),
          (
            'refused by the coordinator (1047)',
            () => Ok(
              ChatStepNotDone(
                _record,
                _seenOf('nineDisputable'),
                cause: const OrderNotParticipant(),
              ),
            ),
            'Temple of Sats did not open the dispute.',
          ),
        ]) {
      testWidgets(
        '$what: the dispute named, open, not open or not known (review of #156)',
        (tester) async {
          final dispute = await agreed(tester);
          dispute.gate?.complete(outcome());
          await _settleDialog(tester);
          expect(find.text(text), findsOneWidget);
          expect(find.textContaining('confirmation'), findsNothing);
          expect(find.textContaining('your request'), findsNothing);
        },
      );
    }

    testWidgets(
      '« Open Dispute » turns on at the very second its time comes (review of #156)',
      (tester) async {
        // The chat's 24 hours from the read: open at 6 hours from now.
        final opensAt = (_seen['nine']!.status as Chatting).deadline.subtract(
          const Duration(hours: 18),
        );
        var clock = opensAt.subtract(const Duration(seconds: 1));
        await _show(
          tester,
          watch: _Watch(),
          dispute: _FiatSent(),
          now: () => clock,
          state: _watched('nine'),
        );
        await openOptions(tester);
        expect(disputeButton(tester).onPressed, isNull);
        clock = opensAt;
        await tester.pump(const Duration(seconds: 1));
        expect(disputeButton(tester).onPressed, isNotNull);
      },
    );

    testWidgets(
      'the dialog emphasizes « Disagree », the button with the reference\'s focus (review of #156)',
      (tester) async {
        await _show(
          tester,
          watch: _Watch(),
          dispute: _FiatSent(),
          state: _watched('nineDisputable'),
        );
        await openOptions(tester);
        await tester.tap(find.text('Open Dispute'));
        await _settleDialog(tester);
        TradeButton button(String label) => tester.widget(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(TradeButton),
          ),
        );
        expect(button('Disagree').outlined, isFalse);
        expect(button('Agree and open dispute').outlined, isTrue);
      },
    );

    testWidgets(
      'refused by the coordinator as too early (1054): the reference coordinator\'s own words',
      (tester) async {
        final dispute = _FiatSent();
        await _show(
          tester,
          watch: _Watch(),
          dispute: dispute,
          state: _watched('nineDisputable'),
        );
        await openOptions(tester);
        await tester.tap(find.text('Open Dispute'));
        await _settleDialog(tester);
        await tester.ensureVisible(find.text('Agree and open dispute'));
        await tester.pump();
        await tester.tap(find.text('Agree and open dispute'));
        await _settleDialog(tester);
        dispute.gate?.complete(
          Ok(
            ChatStepNotDone(
              _record,
              _seen['nineDisputable']!,
              cause: const DisputeTooEarly(fromLastRead: false),
            ),
          ),
        );
        await _settleDialog(tester);
        expect(
          find.textContaining(
            'Cannot open a dispute yet. You need to wait until 18 hours before expiry.',
          ),
          findsOneWidget,
        );
      },
    );

    final temple = Federation.robosats.byAlias('temple')!;
    final email = temple.contact.email!;
    for (final (name, texts) in [
      (
        'eleven',
        [
          'Bull Market cannot send a dispute statement yet. Contact Temple of Sats through one of its contacts below, with the information to identify your order.',
          'Please, save the information needed to identify your order and your payments: order ID; payment hashes of the bonds or escrow (check on your lightning wallet); exact amount of satoshis; and robot nickname. You will have to identify yourself using that information if you contact your trade coordinator.',
          'Order ID: 42',
        ],
      ),
      (
        'elevenSubmitted',
        [
          'We are waiting for your trade counterpart statement. If you are hesitant about the state of the dispute or want to add more information, contact your order trade coordinator (the host) via one of their contact methods.',
          'Please, save the information needed to identify your order and your payments: order ID; payment hashes of the bonds or escrow (check on your lightning wallet); exact amount of satoshis; and robot nickname. You will have to identify yourself using that information if you contact your trade coordinator.',
          'Order ID: 42',
        ],
      ),
      (
        'sixteen',
        [
          'Both statements have been received, wait for the staff to resolve the dispute. If you are hesitant about the state of the dispute or want to add more information, contact your order trade coordinator (the host) via one of their contact methods. If you did not provide a contact method, or are unsure whether you wrote it right, write your coordinator immediately.',
          'Please, save the information needed to identify your order and your payments: order ID; payment hashes of the bonds or escrow (check on your lightning wallet); exact amount of satoshis; and robot nickname. You will have to identify yourself as the user involved in this trade via email (or other contact methods).',
          'Order ID: 42',
        ],
      ),
      (
        'seventeen',
        [
          'You can claim the dispute resolution amount (escrow and fidelity bond) from your profile rewards. If there is anything the staff can help with, do not hesitate to contact to $email (or via your provided burner contact method).',
          'Bull Market cannot claim rewards yet: contact Temple of Sats through one of its contacts below.',
        ],
      ),
      (
        'eighteen',
        [
          'Unfortunately you have lost the dispute. If you think this is a mistake you can ask to re-open the case by contacting your coordinator. If you think your coordinator was unfair, please fill a claim via email to $email',
        ],
      ),
    ]) {
      testWidgets(
        '$name: read-only, the reference\'s texts, and the coordinator\'s contacts as its dialog shows them',
        (tester) async {
          await _show(tester, watch: _Watch(), state: _watched(name));
          for (final text in texts) {
            await _reveal(tester, find.text(text));
            expect(find.text(text), findsOneWidget, reason: text);
          }
          // The contacts as the coordinator's dialog shows them: a button for each, its email among them.
          expect(find.byType(CoordinatorContacts), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(CoordinatorContacts),
              matching: find.byTooltip('Send Email'),
            ),
            findsOneWidget,
          );
          // Nothing to press: no action of the chat step, no « … ».
          expect(find.byIcon(Icons.more_horiz), findsNothing);
          expect(find.byType(TradeButton), findsNothing);
        },
      );
    }

    // A coordinator missing from the app's list, a status kept from no order: no contact to show, so none is said to be below (review of #156).
    for (final (name, text) in [
      (
        'eleven',
        'Bull Market cannot send a dispute statement yet. Contact gone with the information to identify your order.',
      ),
      ('seventeen', 'Bull Market cannot claim rewards yet: contact gone.'),
    ]) {
      testWidgets(
        '$name, the coordinator not in the app\'s list: no « contacts below » (review of #156)',
        (tester) async {
          final watch = _Watch();
          await _show(tester, watch: watch);
          final gone = TradeRecord(
            robot: _record.robot,
            coordinatorAlias: 'gone',
            coordinatorOnion: _record.coordinatorOnion,
            orderId: _record.orderId,
            role: _record.role,
            origin: _record.origin,
            takenAt: _record.takenAt,
            confirmedAt: _record.confirmedAt,
            closedAt: null,
          );
          watch.emit(
            TradeWatchStatus(
              gone,
              TradeSeen(_seenOf(name).status, order: null),
              takePending: false,
            ),
          );
          await tester.pump();
          await tester.pump();
          await _reveal(tester, find.text(text));
          expect(find.text(text), findsOneWidget);
          expect(find.textContaining('contacts below'), findsNothing);
          expect(find.byType(CoordinatorContacts), findsNothing);
        },
      );
    }
  });

  group('« Audit Chat » and « Export » in « Order options » (#157)', () {
    /// The chat's cubit as the route provides it, whose reads answer an empty chat, and whose export gives test values (never a robot's token or key), counted.
    ChatCubit chatCubit(
      WidgetTester tester, {
      required List<TradeRecord> exports,
      required List<TradeSeen> reads,
      bool closedByTest = true,
    }) {
      final cubit = ChatCubit(
        _record,
        (record, seen) async {
          reads.add(seen);
          return const Ok(ChatView(connected: true));
        },
        (record, seen, text) async => const Err(ChatPeerKeyNotKnown()),
        (record, seen, id) async => const Err(ChatPeerKeyNotKnown()),
        (record, seen) => const Err(ChatSkipNeedsOrderRead()),
        (record) => const ChatView(),
        (record) async {
          exports.add(record);
          return const Ok({
            'credentials': {
              'own_public_key': 'test-own-key',
              'encrypted_private_key': 'test-encrypted-key',
              'passphrase': 'test-value-not-a-token',
            },
            'messages': <Object?>[],
          });
        },
        (record) => () {},
      );
      if (closedByTest) addTearDown(cubit.close);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const privacy = MethodChannel('com.flutterplaza.no_screenshot_methods');
      messenger.setMockMethodCallHandler(privacy, (call) async => true);
      addTearDown(() => messenger.setMockMethodCallHandler(privacy, null));
      return cubit;
    }

    Future<void> openOptions(WidgetTester tester) async {
      await _reveal(tester, find.byIcon(Icons.more_horiz));
      await tester.tap(find.byIcon(Icons.more_horiz));
      await _settleDialog(tester);
    }

    testWidgets(
      'first, in the reference\'s order and words: « Audit Chat », « Export », then « Open Dispute » and « Collaborative Cancel »',
      (tester) async {
        await _show(
          tester,
          watch: _Watch(),
          dispute: _FiatSent(),
          chatCubit: chatCubit(tester, exports: [], reads: []),
          state: _watched('nineDisputable'),
        );
        await openOptions(tester);
        final labels = [
          'Order options',
          'Audit Chat',
          'Export',
          'Open Dispute',
          'Collaborative Cancel',
        ];
        final tops = [
          for (final label in labels) tester.getTopLeft(find.text(label)).dy,
        ];
        for (var i = 1; i < tops.length; i++) {
          expect(tops[i], greaterThan(tops[i - 1]), reason: labels[i]);
        }
        expect(find.byType(ChatAuditButton), findsOneWidget);
        expect(find.byType(ChatExportButton), findsOneWidget);
      },
    );

    testWidgets('in French, the texts of the reference\'s place', (
      tester,
    ) async {
      await _show(
        tester,
        watch: _Watch(),
        chatCubit: chatCubit(tester, exports: [], reads: []),
        locale: const Locale('fr'),
        state: _watched('nine'),
      );
      await openOptions(tester);
      expect(find.text('Auditer le chat'), findsOneWidget);
      expect(find.text('Exporter'), findsOneWidget);
    });

    testWidgets(
      '« Export » copies the export of the chat panel\'s own cubit, once, on the tap: no second watch of the chat',
      (tester) async {
        final exports = <TradeRecord>[];
        final reads = <TradeSeen>[];
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
        final cubit = chatCubit(tester, exports: exports, reads: reads);
        await _show(
          tester,
          watch: _Watch(),
          chatCubit: cubit,
          state: _watched('nine'),
        );
        expect(find.byType(ChatPanel), findsOneWidget);
        await openOptions(tester);
        // The very cubit the panel shows, provided once above the screen as the route provides it: no second one, so no second watch and no second decryption.
        expect(
          identical(
            tester
                .widget<ChatExportButton>(find.byType(ChatExportButton))
                .cubit,
            cubit,
          ),
          isTrue,
        );
        expect(
          identical(
            tester.widget<ChatAuditButton>(find.byType(ChatAuditButton)).cubit,
            cubit,
          ),
          isTrue,
        );
        expect(
          identical(
            tester.element(find.byType(ChatPanel)).read<ChatCubit>(),
            cubit,
          ),
          isTrue,
        );
        expect(cubit.polling, isTrue);
        final readsBefore = reads.length;
        expect(exports, isEmpty);
        await tester.tap(find.text('Export'));
        await _settleDialog(tester);
        expect(exports, [_record]);
        expect(
          copied,
          const JsonEncoder.withIndent('  ').convert({
            'credentials': {
              'own_public_key': 'test-own-key',
              'encrypted_private_key': 'test-encrypted-key',
              'passphrase': 'test-value-not-a-token',
            },
            'messages': <Object?>[],
          }),
        );
        expect(find.text('Copied!'), findsOneWidget);
        // The export reads nothing: the panel's watch alone reads, every 5 s.
        expect(reads.length, readsBefore);
      },
    );

    testWidgets(
      '« Audit Chat » opens « Don\'t trust, verify » over the same cubit\'s export',
      (tester) async {
        final exports = <TradeRecord>[];
        await _show(
          tester,
          watch: _Watch(),
          chatCubit: chatCubit(tester, exports: exports, reads: []),
          state: _watched('nine'),
        );
        await openOptions(tester);
        await tester.tap(find.text('Audit Chat'));
        await _settleDialog(tester);
        expect(find.byType(ChatAuditDialog), findsOneWidget);
        expect(find.text('Don\'t trust, verify'), findsOneWidget);
        expect(exports, [_record]);
      },
    );

    testWidgets(
      'as the route builds the trade page (`P2pRouter.tradePage`): both shown, over the one chat cubit it provides to the panel',
      (tester) async {
        tester.view
          ..physicalSize = const Size(390, 1200) * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final watch = _Watch();
        final made = <ChatCubit>[];
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
          ..registerFactoryParam<ChatCubit, TradeRecord, void>((record, _) {
            // Closed by the route's provider with the page, as in the app.
            final cubit = chatCubit(
              tester,
              exports: [],
              reads: [],
              closedByTest: false,
            );
            made.add(cubit);
            return cubit;
          });
        await tester.pumpWidget(
          MaterialApp(
            theme: testTheme,
            localizationsDelegates: P2pLocalizations.localizationsDelegates,
            supportedLocales: P2pLocalizations.supportedLocales,
            home: Scaffold(
              body: P2pRouter.tradePage(locator, P2pTradeRouteArgs(_record)),
            ),
          ),
        );
        await tester.pump();
        watch.emit(_watched('nine'));
        await tester.pump();
        await tester.pump();
        expect(find.byType(ChatPanel), findsOneWidget);
        await openOptions(tester);
        expect(made, hasLength(1));
        expect(
          tester.widget<ChatAuditButton>(find.byType(ChatAuditButton)).cubit,
          same(made.single),
        );
        expect(
          tester.widget<ChatExportButton>(find.byType(ChatExportButton)).cubit,
          same(made.single),
        );
        expect(
          tester.element(find.byType(ChatPanel)).read<ChatCubit>(),
          same(made.single),
        );
      },
    );

    // The reference has « Order options » only in its chat prompt, at 9 and 10 (`TradeBox/index.tsx:538-545`, `Prompts/Chat.tsx`): elsewhere neither « … » nor the chat's buttons.
    for (final name in ['eleven', 'thirteen', 'fourteen', 'sixteen']) {
      testWidgets(
        'at $name, past the chat step: no « Order options », so neither button',
        (tester) async {
          await _show(
            tester,
            watch: _Watch(),
            chatCubit: chatCubit(tester, exports: [], reads: []),
            state: _watched(name),
          );
          expect(find.byIcon(Icons.more_horiz), findsNothing);
          expect(find.byType(ChatAuditButton), findsNothing);
          expect(find.byType(ChatExportButton), findsNothing);
        },
      );
    }

    testWidgets(
      'without the chat (the feature holds no robot): « Order options » without them',
      (tester) async {
        await _show(tester, watch: _Watch(), state: _watched('nine'));
        await openOptions(tester);
        expect(find.text('Order options'), findsOneWidget);
        expect(find.text('Audit Chat'), findsNothing);
        expect(find.text('Export'), findsNothing);
      },
    );
  });

  group('on a phone of 320 points, the text larger', () {
    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets(
          '${locale.languageCode} at ×$scale: 9 with the chat panel in its place, nothing cut',
          (tester) async {
            await _show(
              tester,
              watch: _Watch(),
              chat: _chatPanel(tester),
              locale: locale,
              size: const Size(320, 640),
              textScale: scale,
              state: _watched('nine'),
            );
            await tester.pump();
            expect(find.byType(ChatPanel), findsOneWidget);
            _expectNothingCut(tester, 'nine with the chat');
          },
        );

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
            Widget app(ThemeData theme) => MaterialApp(
              theme: theme,
              // The app's font at once, not over the theme's animation.
              themeAnimationDuration: Duration.zero,
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
                      now: () => tradeNow,
                      offersFiatSent: true,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpWidget(app(testTheme));
            await tester.pump();
            _expectNothingCut(tester, 'long');
            // The reviewer's case (second pass of #145): « Confirmer l'envoi de 1 234 567,1234 EUR », the amount's groups joined by non-breaking spaces, one word, never broken inside; checked in the app's font.
            if (locale.languageCode == 'fr') {
              expect(
                find.byWidgetPredicate(
                  (w) =>
                      w is TradeButton &&
                      RegExp(
                        '^Confirmer l\'envoi de 1[\u00a0\u202f]234[\u00a0\u202f]567,1234 EUR\$',
                      ).hasMatch(w.label),
                ),
                findsOneWidget,
              );
            }
            await tester.pumpWidget(app(_appTheme));
            await tester.pump();
            _expectNoWordBroken(tester, 'long');
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

/// Every paragraph of the chat step's panel and of the dialog open breaks its lines between words only, never inside one (letter by letter at the larger text sizes); the screen's own chrome (its tabs) is not this pull request's.
void _expectNoWordBroken(WidgetTester tester, String reason) {
  // The buttons and the dialogs of this step; the panel's prose is laid out at the test font's width, where every glyph is a square of the text's size.
  final ours = find.byWidgetPredicate(
    (w) => const {
      'OrderOptionsDialog',
      'TradeDialogBody',
      'TradeButton',
      '_QuietButton',
      // The end's panel, its stars and its summary (#95).
      'SuccessfulPanel',
    }.contains(w.runtimeType.toString()),
  );
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.descendant(of: ours, matching: find.byType(RichText)),
  )) {
    final text = paragraph.text.toPlainText();
    final style = paragraph.text.style;
    final room = paragraph.constraints.maxWidth;
    // A word wider than the paragraph's room can only break letter by letter.
    // Split as the line breaks: at breaking spaces only, a group joined by a non-breaking space (U+00A0, U+202F) being one word.
    for (final word in text.split(RegExp(r'[ \t\n]+'))) {
      if (word.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      expect(
        width <= room + 0.5,
        isTrue,
        reason:
            '$reason: « $word » ($width > $room) of « $text » is wider than its room',
      );
    }
  }
}
