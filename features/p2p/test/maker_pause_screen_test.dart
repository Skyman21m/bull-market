import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_pause.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/holding_transport.dart';
import 'support/make_harness.dart';
import 'support/fakes.dart'
    show FakeTransport, bookOrder, coordinator, parseOrders, testNow;
import 'support/harness.dart';
import 'support/maker_orders.dart';
import 'support/trade_harness.dart' show tradeKey;
import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

/// The pause button of a maker's public order and « Unpause Order » of its paused order on the trade screen (#184, `TradeBox/Prompts/PublicWait.tsx:116-132`, `Prompts/Paused.tsx:22-35`, `TradeBox/index.tsx:310-313`): one tap, no dialog, by real gestures (a tap, two quick taps, a tap while the request runs), what the use case is asked counted; and what the screen says of each outcome, so that an order the user believes paused and that is public is seen.
///
/// Every status comes from the state machine reading the reference's answers to a maker (`support/maker_orders.dart`), never built by hand.

final _record = TradeRecord(
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
  orderId: tradeOrderId,
  role: TradeRole.buyer,
  origin: TradeOrigin.madeHere,
  takenAt: madeAt,
  confirmedAt: madeAt,
  closedAt: null,
);

final _reader = Bolt11Reader(Bolt11TestDecoder([makerBondInvoice()]));

/// The statuses of the reference's answers read one after the other by the state machine, from the order's first read, each marked stored as the reader stores it.
Future<List<TradeSeen>> _chain(List<Map<String, Object?>> answers) async {
  final made = madeTerms();
  final seen = <TradeSeen>[];
  TradeStatus? status;
  for (final json in answers) {
    final order = await readOrder(json);
    final answer = TradeOrderRead(order);
    status = status == null
        ? TradeStatus.afterMake(
            answer,
            terms: made,
            now: tradeNow,
            reader: _reader,
          )
        : TradeStatus.from(
            previous: status,
            answer: answer,
            terms: made,
            now: tradeNow,
            reader: _reader,
          );
    seen.add(TradeSeen(status, order: order, stored: true));
  }
  return seen;
}

/// The order public (1), then paused (2), then public again (1).
Future<(TradeSeen, TradeSeen, TradeSeen)> _statuses() async {
  final seen = await _chain([
    makerOrderJson(0),
    makerOrderJson(1),
    makerOrderJson(2),
    makerOrderJson(1),
  ]);
  return (seen[1], seen[2], seen[3]);
}

const _pauseTooltip = 'Pause the public order';

/// What the screen asked of the cubit's pause.
final class _Pauses {
  final List<TradeSeen> asked = [];

  /// What each pause gives, the next one first; a pause with none left never ends.
  final List<Completer<Result<PauseOutcome, PauseRefusal>>> answers = [];

  Future<Result<PauseOutcome, PauseRefusal>> call(
    TradeRecord record,
    TradeSeen seen,
  ) {
    asked.add(seen);
    if (answers.isEmpty) return Completer<Never>().future;
    return answers.removeAt(0).future;
  }
}

/// Shows the trade screen of [_record] at [seen], over a cubit whose watch the test feeds and whose pause is [pauses] (none when `null`), with [book] for the figures of a public order.
Future<(TradeCubit, StreamController<TradeWatchState>)> _show(
  WidgetTester tester,
  TradeSeen seen, {
  _Pauses? pauses,
  List<PublicOrder>? book,
  Locale locale = const Locale('en'),
  Future<Result<CancelOutcome, CancelRefusal>> Function()? cancel,
}) async {
  tester.view
    ..physicalSize = const Size(390, 1600) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final watch = StreamController<TradeWatchState>.broadcast();
  addTearDown(watch.close);
  final trade = TradeCubit(
    _record,
    (record, {signals = const Stream.empty(), onScreen = true}) {
      signals.listen((_) {});
      return watch.stream;
    },
    (record, seen, {bondLoss}) => cancel?.call() ?? Completer<Never>().future,
    pause: pauses?.call,
  )..start();
  addTearDown(trade.close);
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
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: trade),
            BlocProvider.value(value: page),
          ],
          child: TradeScreen(
            now: () => tradeNow,
            coordinatorDetails: (_) => throw StateError('not opened'),
            book: book,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  watch.add(TradeScreenStatuses.watched(seen, of: _record));
  await tester.pump();
  await tester.pump();
  return (trade, watch);
}

Finder get _unpause => find.widgetWithText(TradeButton, 'Unpause Order');

Future<void> _tapPause(WidgetTester tester) async {
  await tester.ensureVisible(find.byTooltip(_pauseTooltip));
  await tester.pump();
  await tester.tap(find.byTooltip(_pauseTooltip));
}

Future<void> _tapUnpause(WidgetTester tester) async {
  await tester.ensureVisible(_unpause);
  await tester.pump();
  await tester.tap(_unpause);
}

/// Lets the long wait's timer of a request that never ends run out (`TradeCubit.stillWaitingAfter`).
Future<void> _waitOut(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 31));

/// Every text shown: none names the project's internal name nor the swap engine.
void _noInternalNames(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(text.data ?? '', isNot(contains('Troc')));
    expect(text.data ?? '', isNot(contains('Boltz')));
  }
}

void main() {
  group('the buttons, by real gestures', () {
    testWidgets(
      'status 1: the pause button beside « Public orders for EUR », its tooltip the reference\'s; one tap asks the pause once, with the status shown, and no dialog',
      (tester) async {
        final (public, _, _) = await _statuses();
        final pauses = _Pauses();
        final book = await tester.runAsync(
          () => parseOrders([
            bookOrder(id: tradeOrderId, type: 0),
            bookOrder(id: 1, type: 0, premium: 1),
          ]),
        );
        await _show(tester, public, pauses: pauses, book: book);
        expect(find.byTooltip(_pauseTooltip), findsOneWidget);
        expect(find.byIcon(Icons.pause_circle), findsOneWidget);
        // On the row of « Public orders for EUR », as the reference puts it.
        expect(
          (tester.getCenter(find.byTooltip(_pauseTooltip)).dy -
                  tester.getCenter(find.text('Public orders for EUR')).dy)
              .abs(),
          lessThan(40),
        );
        await _tapPause(tester);
        await tester.pump();
        expect(pauses.asked, [public]);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        // Spinning while it runs, and off: another tap asks nothing more.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.tap(find.byTooltip(_pauseTooltip), warnIfMissed: false);
        await tester.pump();
        expect(pauses.asked, hasLength(1));
        // After 30 s, the wait says what it waits for, the button still off.
        await tester.pump(const Duration(seconds: 31));
        expect(
          find.text('Still waiting for Temple of Sats. Tor can take a minute.'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip(_pauseTooltip), warnIfMissed: false);
        await tester.pump();
        expect(pauses.asked, hasLength(1));
        _noInternalNames(tester);
      },
    );

    testWidgets(
      'status 1 without a book received: the pause button alone, under the lines',
      (tester) async {
        final (public, _, _) = await _statuses();
        final pauses = _Pauses();
        await _show(tester, public, pauses: pauses);
        expect(find.text('Public orders for EUR'), findsNothing);
        await _tapPause(tester);
        await tester.pump();
        expect(pauses.asked, hasLength(1));
        await _waitOut(tester);
      },
    );

    testWidgets('two quick taps on the pause button: asked once', (
      tester,
    ) async {
      final (public, _, _) = await _statuses();
      final pauses = _Pauses();
      await _show(tester, public, pauses: pauses);
      await tester.ensureVisible(find.byTooltip(_pauseTooltip));
      await tester.pump();
      // Two taps in the same frame, before the screen redraws.
      await tester.tap(find.byTooltip(_pauseTooltip));
      await tester.tap(find.byTooltip(_pauseTooltip));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(find.byTooltip(_pauseTooltip), warnIfMissed: false);
      await tester.pump();
      expect(pauses.asked, hasLength(1));
      await _waitOut(tester);
    });

    testWidgets(
      'status 2: « Unpause Order » under the reference\'s text; a tap asks once with the status shown, two quick taps too, no dialog',
      (tester) async {
        final (_, paused, _) = await _statuses();
        final pauses = _Pauses();
        await _show(tester, paused, pauses: pauses);
        expect(find.text('Your order is paused (2/5)'), findsOneWidget);
        expect(_unpause, findsOneWidget);
        expect(find.byIcon(Icons.play_circle), findsOneWidget);
        expect(find.byTooltip(_pauseTooltip), findsNothing);
        await tester.ensureVisible(_unpause);
        await tester.pump();
        await tester.tap(_unpause);
        await tester.tap(_unpause);
        await tester.pump();
        expect(pauses.asked, [paused]);
        expect(find.byType(AlertDialog), findsNothing);
        await tester.tap(_unpause, warnIfMissed: false);
        await tester.pump();
        expect(pauses.asked, hasLength(1));
        await _waitOut(tester);
      },
    );

    testWidgets(
      'a cancel running: the pause button is off, and the screen says why',
      (tester) async {
        final (public, _, _) = await _statuses();
        final pauses = _Pauses();
        await _show(tester, public, pauses: pauses);
        expect(
          find.text('The order is being cancelled: wait until it ends.'),
          findsNothing,
        );
        await tester.ensureVisible(find.text('Cancel'));
        await tester.pump();
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        expect(
          find.text('The order is being cancelled: wait until it ends.'),
          findsOneWidget,
        );
        await _tapPause(tester);
        await tester.pump();
        expect(pauses.asked, isEmpty);
        await _waitOut(tester);
      },
    );

    testWidgets(
      'status 2, a cancel running: « Unpause Order » off, the screen says why',
      (tester) async {
        final (_, paused, _) = await _statuses();
        final pauses = _Pauses();
        await _show(tester, paused, pauses: pauses);
        await tester.ensureVisible(find.text('Cancel'));
        await tester.pump();
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        expect(
          find.text('The order is being cancelled: wait until it ends.'),
          findsOneWidget,
        );
        expect(tester.widget<TradeButton>(_unpause).onPressed, isNull);
        await tester.tap(_unpause, warnIfMissed: false);
        await tester.pump();
        expect(pauses.asked, isEmpty);
        await _waitOut(tester);
      },
    );

    testWidgets(
      'the app hidden and back while the pause runs: nothing asked again, still spinning',
      (tester) async {
        final (public, _, _) = await _statuses();
        final pauses = _Pauses();
        await _show(tester, public, pauses: pauses);
        await _tapPause(tester);
        await tester.pump();
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pump();
        }
        await tester.tap(find.byTooltip(_pauseTooltip), warnIfMissed: false);
        await tester.pump();
        expect(pauses.asked, hasLength(1));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await _waitOut(tester);
      },
    );
  });

  group('what the screen says of each outcome', () {
    testWidgets(
      'done: « Your order is paused (2/5) », no notice; a later read showing it public says it is public again',
      (tester) async {
        final (public, paused, publicAgain) = await _statuses();
        final pauses = _Pauses();
        final answer = Completer<Result<PauseOutcome, PauseRefusal>>();
        pauses.answers.add(answer);
        final (_, watch) = await _show(tester, public, pauses: pauses);
        await _tapPause(tester);
        await tester.pump();
        answer.complete(Ok(PauseDone(PauseWanted.paused, _record, paused)));
        await tester.pump();
        await tester.pump();
        expect(find.text('Your order is paused (2/5)'), findsOneWidget);
        expect(_unpause, findsOneWidget);
        expect(find.textContaining('robots can'), findsNothing);
        // Unpaused elsewhere (the official app with the same Garage Key): said, the order can be taken.
        watch.add(TradeScreenStatuses.watched(publicAgain, of: _record));
        await tester.pump();
        await tester.pump();
        expect(find.text('Your order is public (2/5)'), findsOneWidget);
        expect(
          find.text(
            'Your order is public again, although it was paused from this app: robots can see it and take it.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'not reached, the order read public: the notice, then « Your order is public: robots can see it and take it. »',
      (tester) async {
        final (public, _, _) = await _statuses();
        final pauses = _Pauses();
        final answer = Completer<Result<PauseOutcome, PauseRefusal>>();
        pauses.answers.add(answer);
        await _show(tester, public, pauses: pauses);
        await _tapPause(tester);
        await tester.pump();
        answer.complete(
          Ok(PauseNotReached(PauseWanted.paused, _record, public)),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('Your order is public (2/5)'), findsOneWidget);
        expect(
          find.text(
            'Temple of Sats accepted the request, but your order is not paused: it is shown as it is now.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Your order is public: robots can see it and take it.'),
          findsOneWidget,
        );
        // The button is back: a new tap is the user's, read again first.
        await _tapPause(tester);
        await tester.pump();
        expect(pauses.asked, hasLength(2));
        await _waitOut(tester);
      },
    );

    testWidgets(
      'unknown: said, never « paused », and the order counted as public until a read shows it paused',
      (tester) async {
        final (public, paused, _) = await _statuses();
        final pauses = _Pauses();
        final answer = Completer<Result<PauseOutcome, PauseRefusal>>();
        pauses.answers.add(answer);
        final (_, watch) = await _show(tester, public, pauses: pauses);
        await _tapPause(tester);
        await tester.pump();
        answer.complete(
          Ok(PauseOutcomeUnknown(PauseWanted.paused, _record, public)),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('Your order is paused (2/5)'), findsNothing);
        expect(
          find.text(
            'Bull Market does not know yet whether your request reached Temple of Sats. It keeps checking, and never sends it again by itself.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Until a read shows it paused, count on your order being public: robots can take it.',
          ),
          findsOneWidget,
        );
        // The watch reads it paused: the notice goes.
        watch.add(TradeScreenStatuses.watched(paused, of: _record));
        await tester.pump();
        await tester.pump();
        expect(find.text('Your order is paused (2/5)'), findsOneWidget);
        expect(find.textContaining('count on your order'), findsNothing);
        expect(pauses.asked, hasLength(1));
      },
    );

    testWidgets(
      'refused by the coordinator (1033): its own words never shown, the app\'s, and the order public',
      (tester) async {
        final (public, _, _) = await _statuses();
        final pauses = _Pauses();
        final answer = Completer<Result<PauseOutcome, PauseRefusal>>();
        pauses.answers.add(answer);
        await _show(tester, public, pauses: pauses);
        await _tapPause(tester);
        await tester.pump();
        answer.complete(
          Ok(
            PauseNotDone(
              PauseWanted.paused,
              _record,
              public,
              cause: const TradeActionNotNow(fromLastRead: false),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.text('Temple of Sats refused the request: nothing changed.'),
          findsOneWidget,
        );
        expect(
          find.text('Your order is public: robots can see it and take it.'),
          findsOneWidget,
        );
        expect(find.textContaining('either public or paused'), findsNothing);
      },
    );

    testWidgets(
      'nothing sent, the order paused elsewhere: said, the fresh status shown with « Unpause Order »',
      (tester) async {
        final (public, paused, _) = await _statuses();
        final pauses = _Pauses();
        final answer = Completer<Result<PauseOutcome, PauseRefusal>>();
        pauses.answers.add(answer);
        await _show(tester, public, pauses: pauses);
        await _tapPause(tester);
        await tester.pump();
        answer.complete(Err(PauseStatusMoved(paused, record: _record)));
        await tester.pump();
        await tester.pump();
        expect(find.text('Your order is paused (2/5)'), findsOneWidget);
        expect(
          find.text(
            'The order changed before your request left: nothing was sent. It is shown as it is now.',
          ),
          findsOneWidget,
        );
        expect(_unpause, findsOneWidget);
        // Paused already: no line says it is public.
        expect(find.textContaining('robots can see it'), findsNothing);
      },
    );

    testWidgets(
      'an unpause not reached, the order still paused: the notice, no public line',
      (tester) async {
        final (_, paused, _) = await _statuses();
        final pauses = _Pauses();
        final answer = Completer<Result<PauseOutcome, PauseRefusal>>();
        pauses.answers.add(answer);
        await _show(tester, paused, pauses: pauses);
        await _tapUnpause(tester);
        await tester.pump();
        answer.complete(
          Ok(PauseNotReached(PauseWanted.public, _record, paused)),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('Your order is paused (2/5)'), findsOneWidget);
        expect(
          find.text(
            'Temple of Sats accepted the request, but your order is not public: it is shown as it is now.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('robots can'), findsNothing);
      },
    );

    testWidgets(
      'in French: the reference\'s words with « ordre », and the project\'s lines',
      (tester) async {
        final (public, _, _) = await _statuses();
        final pauses = _Pauses();
        final answer = Completer<Result<PauseOutcome, PauseRefusal>>();
        pauses.answers.add(answer);
        await _show(tester, public, pauses: pauses, locale: const Locale('fr'));
        expect(
          find.byTooltip('Mettre en pause l’ordre public'),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byTooltip('Mettre en pause l’ordre public'),
        );
        await tester.pump();
        await tester.tap(find.byTooltip('Mettre en pause l’ordre public'));
        await tester.pump();
        answer.complete(
          Ok(PauseOutcomeUnknown(PauseWanted.paused, _record, public)),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.text(
            'Tant qu’une lecture ne le montre pas en pause, considérez votre ordre comme public : les robots peuvent le prendre.',
          ),
          findsOneWidget,
        );
        _noInternalNames(tester);
      },
    );

    testWidgets('in French, at 2: « Reprendre l’ordre »', (tester) async {
      final (_, paused, _) = await _statuses();
      await _show(
        tester,
        paused,
        pauses: _Pauses(),
        locale: const Locale('fr'),
      );
      expect(
        find.widgetWithText(TradeButton, 'Reprendre l’ordre'),
        findsOneWidget,
      );
    });
  });

  group('over the real use case and the coordinator played by the tests', () {
    testWidgets(
      'two quick taps on the pause button, then « Unpause Order »: one pause request each reaches the coordinator, the order paused then public, each shown from a read',
      (tester) async {
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
          final first = harness.watchOf(record);
          await harness.settle();
          await first.subscription.cancel();
          harness.coordinator.lockMakerBond(record.orderId);
          return record;
        });
        if (record == null) fail('no record');
        int pauses() => harness.coordinator.received
            .where((kind) => kind == ScriptedMakerRequest.pause)
            .length;
        final trade = TradeCubit(
          record,
          harness.watch.execute,
          harness.cancel.execute,
          lastStored: harness.watch.lastStored,
          pause: harness.pause.execute,
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
        Future<void> settleBoth() async {
          for (var i = 0; i < 5; i++) {
            await tester.runAsync(harness.settle);
            await tester.pump();
          }
        }

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
        await settleBoth();
        expect(find.text('Your order is public (2/5)'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip(_pauseTooltip));
        await tester.pump();
        await tester.tap(find.byTooltip(_pauseTooltip));
        await tester.tap(find.byTooltip(_pauseTooltip));
        await settleBoth();
        expect(pauses(), 1);
        expect(harness.coordinator.order(record.orderId).status, 2);
        expect(find.text('Your order is paused (2/5)'), findsOneWidget);
        await tester.ensureVisible(_unpause);
        await tester.pump();
        await tester.tap(_unpause);
        await tester.tap(_unpause, warnIfMissed: false);
        await settleBoth();
        expect(pauses(), 2);
        expect(harness.coordinator.order(record.orderId).status, 1);
        expect(find.text('Your order is public (2/5)'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await trade.close();
          await page.close();
        });
      },
    );
  });

  group(
    'a pause held on its way, over the real use cases, by real gestures (functional review of #184)',
    () {
      /// An order made and public on the scripted coordinator, its pause going through a transport that can hold it.
      Future<(MakeHarness, TradeRecord, HoldingTransport)> made(
        WidgetTester tester,
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
          final first = harness.watchOf(record);
          await harness.settle();
          await first.subscription.cancel();
          harness.coordinator.lockMakerBond(record.orderId);
          return record;
        });
        if (record == null) fail('no record');
        return (harness, record, HoldingTransport(harness.coordinator));
      }

      /// The trade screen of [record], its cubit built as the locator builds it, over the harness's use cases and [transport]'s pause.
      Future<TradeCubit> mount(
        WidgetTester tester,
        MakeHarness harness,
        TradeRecord record,
        HoldingTransport transport,
      ) async {
        final pause = pauseThrough(harness, transport);
        final trade = TradeCubit(
          record,
          harness.watch.execute,
          harness.cancel.execute,
          lastStored: harness.watch.lastStored,
          pause: pause.execute,
          pauseRunning: pause.running,
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

      int count(MakeHarness harness, ScriptedMakerRequest kind) =>
          harness.coordinator.received.where((k) => k == kind).length;

      Future<void> tapCancel(WidgetTester tester) async {
        final cancel = find.widgetWithText(TradeButton, 'Cancel');
        await tester.ensureVisible(cancel);
        await tester.pump();
        await tester.tap(cancel);
      }

      testWidgets(
        '« Cancel » during a pause: sent, after the pause, once; refused since the pause moved the status, said; « Cancel » again cancels',
        (tester) async {
          final (harness, record, transport) = await made(tester);
          final trade = await mount(tester, harness, record, transport);
          await settleBoth(tester, harness);
          transport.holdNextPause();
          await tester.ensureVisible(find.byTooltip(_pauseTooltip));
          await tester.pump();
          await tester.tap(find.byTooltip(_pauseTooltip));
          await settleBoth(tester, harness);
          expect(transport.pausesSent, 1);
          // « Cancel » stays on during the pause, as the reference's.
          expect(
            tester
                .widget<TradeButton>(find.widgetWithText(TradeButton, 'Cancel'))
                .onPressed,
            isNotNull,
          );
          await tapCancel(tester);
          await settleBoth(tester, harness);
          // Waiting behind the pause: not lost, not sent yet.
          expect(trade.state.cancel, isA<CancelRunning>());
          expect(count(harness, ScriptedMakerRequest.cancel), 0);
          transport.release();
          await settleBoth(tester, harness);
          expect(count(harness, ScriptedMakerRequest.pause), 1);
          expect(count(harness, ScriptedMakerRequest.cancel), 1);
          expect(harness.coordinator.order(record.orderId).status, 2);
          expect(find.text('Your order is paused (2/5)'), findsOneWidget);
          expect(
            find.text(
              'The order moved on before the cancel: nothing was cancelled.',
            ),
            findsOneWidget,
          );
          // From the status now shown, the cancel goes.
          await tapCancel(tester);
          await settleBoth(tester, harness);
          expect(count(harness, ScriptedMakerRequest.cancel), 2);
          expect(harness.coordinator.order(record.orderId).status, 4);
          expect(find.text('Your order is paused (2/5)'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(trade.close);
        },
      );

      testWidgets(
        'the screen left and opened again while the pause runs: the new screen shows it running, a tap sends nothing, and it says what the pause gave',
        (tester) async {
          final (harness, record, transport) = await made(tester);
          final first = await mount(tester, harness, record, transport);
          await settleBoth(tester, harness);
          transport.holdNextPause();
          await tester.ensureVisible(find.byTooltip(_pauseTooltip));
          await tester.pump();
          await tester.tap(find.byTooltip(_pauseTooltip));
          await settleBoth(tester, harness);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(first.close);
          final second = await mount(tester, harness, record, transport);
          await settleBoth(tester, harness);
          expect(second.state.pause, isA<PauseRunning>());
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          await tester.tap(find.byTooltip(_pauseTooltip), warnIfMissed: false);
          await settleBoth(tester, harness);
          transport.release();
          await settleBoth(tester, harness);
          expect(transport.pausesSent, 1);
          expect(harness.coordinator.order(record.orderId).status, 2);
          expect(find.text('Your order is paused (2/5)'), findsOneWidget);
          expect(
            find.textContaining('changed before your request'),
            findsNothing,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(second.close);
        },
      );

      testWidgets(
        'the same, the answer lost and the request landing late: one request; the new screen says the outcome is unknown and to count the order as public, then shows it paused once it landed',
        (tester) async {
          final (harness, record, transport) = await made(tester);
          final first = await mount(tester, harness, record, transport);
          await settleBoth(tester, harness);
          transport.holdNextPause();
          harness.coordinator.failNext(
            ScriptedMakerRequest.pause,
            ScriptedFault.landsLate,
          );
          await tester.ensureVisible(find.byTooltip(_pauseTooltip));
          await tester.pump();
          await tester.tap(find.byTooltip(_pauseTooltip));
          await settleBoth(tester, harness);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(first.close);
          final second = await mount(tester, harness, record, transport);
          await settleBoth(tester, harness);
          await tester.tap(find.byTooltip(_pauseTooltip), warnIfMissed: false);
          await settleBoth(tester, harness);
          transport.release();
          await settleBoth(tester, harness);
          expect(transport.pausesSent, 1);
          expect(
            find.text(
              'Until a read shows it paused, count on your order being public: robots can take it.',
            ),
            findsOneWidget,
          );
          harness.coordinator.landLate();
          second.signal(TradeWatchSignal.readNow);
          await settleBoth(tester, harness);
          expect(harness.coordinator.order(record.orderId).status, 2);
          expect(find.text('Your order is paused (2/5)'), findsOneWidget);
          expect(transport.pausesSent, 1);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(second.close);
        },
      );

      testWidgets(
        'the app hidden and back while the real pause runs, then a tap: one request, the order paused',
        (tester) async {
          final (harness, record, transport) = await made(tester);
          final trade = await mount(tester, harness, record, transport);
          await settleBoth(tester, harness);
          transport.holdNextPause();
          await tester.ensureVisible(find.byTooltip(_pauseTooltip));
          await tester.pump();
          await tester.tap(find.byTooltip(_pauseTooltip));
          await settleBoth(tester, harness);
          for (final state in [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
            await settleBoth(tester, harness);
          }
          await tester.tap(find.byTooltip(_pauseTooltip), warnIfMissed: false);
          await settleBoth(tester, harness);
          transport.release();
          await settleBoth(tester, harness);
          expect(transport.pausesSent, 1);
          expect(count(harness, ScriptedMakerRequest.pause), 1);
          expect(harness.coordinator.order(record.orderId).status, 2);
          expect(find.text('Your order is paused (2/5)'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(trade.close);
        },
      );
    },
  );
}
