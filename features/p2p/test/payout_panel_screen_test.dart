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
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_payout_outcome.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/payout_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/trade/payout_panel.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart' show Bolt11TestDecoder, Bolt11TestInvoice;
import 'package:robosats/robosats.dart';

import 'support/fakes.dart' show FakeTransport, coordinator, testNow;
import 'support/harness.dart';
import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

/// The payout panel in the trade screen as the route builds it (`P2pRouter.tradePage`): the security review of #132 found that a panel built again (another tab of the trade, a line added above it) showed an empty field while « Submit » gave what it no longer showed, and that the on-chain figures came from the field rather than from the check. Its probes P1 to P7, kept here, now hold the other way; never a coordinator, never a real invoice, address or key.
void main() {
  final record = TradeScreenStatuses.record;
  const asked = 106606;
  final readAt = tradeNow.add(const Duration(seconds: 30));
  // BIP-173's own test vector, which no wallet of the project holds.
  const mainnetAddress = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
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

  late TradeScreenStatuses statuses;
  late TradeSeen six;
  late TradeSeen sixSwap;
  late TradeSeen sixSwapLater;
  late TradeSeen fifteenExpired;
  late TradeSeen seven;

  setUpAll(() async {
    statuses = await TradeScreenStatuses.make();
    six = await statuses.waitingForBoth();
    // What the coordinator shows once it received the invoice at 6.
    seven = await statuses.waitingForEscrow();
    Map<String, Object?> swap(double suggested) => {
      'swap_allowed': true,
      'swap_failure_reason': null,
      'suggested_mining_fee_rate': suggested,
      'swap_fee_rate': 0.75,
    };
    sixSwap = await statuses.read(
      await statuses.bondStep(),
      orderJson(6, changes: swap(3.5)),
    );
    sixSwapLater = await statuses.read(
      await statuses.bondStep(),
      orderJson(6, changes: swap(40)),
      after: const Duration(minutes: 1),
    );
    fifteenExpired = await statuses.read(
      await statuses.waitingForPayout(),
      orderJson(15),
      after: const Duration(minutes: 5),
    );
  });

  Finder submitButton() => find.widgetWithText(TradeButton, 'Submit');
  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<TradeButton>(button).onPressed != null;
  String fieldText(WidgetTester tester, Key key) =>
      tester.widget<TextField>(find.byKey(key)).controller?.text ?? '';

  /// The trade page as the route builds it, over a locator of the test: the watch [_Watch], the cancel [cancel], and the payout « sent » to [sender].
  Future<_Page> showPage(
    WidgetTester tester,
    TradeSeen seen, {
    _Sender? sender,
    Future<Result<CancelOutcome, CancelRefusal>> Function(
      TradeRecord record,
      TradeSeen seen, {
      BondLossAcknowledged? bondLoss,
    })?
    cancel,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 1800) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final watch = _Watch();
    final payouts =
        sender ?? (_Sender()..answer = (s) => Ok(PayoutGiven(record, seven)));
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final cubits = <PayoutCubit>[];
    final reads = FakeTransport();
    locator
      ..registerSingleton<P2pClock>(P2pClock(() => tradeNow))
      ..registerFactoryParam<TradeCubit, TradeRecord, void>(
        (record, _) => TradeCubit(
          record,
          watch.call,
          cancel ??
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
      ..registerFactoryParam<PayoutCubit, TradeRecord, void>((record, _) {
        final cubit = PayoutCubit(
          record,
          PayoutAsk.of,
          check,
          payouts.call,
          (_) => () {},
          now: () => readAt.add(const Duration(seconds: 1)),
        );
        cubits.add(cubit);
        return cubit;
      });
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
    watch.emit(TradeScreenStatuses.watched(seen));
    await tester.pump();
    await tester.pump();
    return _Page(watch, payouts, cubits.single);
  }

  Future<void> orderTabAndBack(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(BullSegmented).first,
        matching: find.text('Order'),
      ),
    );
    await tester.pump();
    expect(find.byKey(PayoutPanel.invoiceField), findsNothing);
    await tester.tap(find.text('Contract'));
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(submitButton());
    await tester.pump();
    await tester.tap(submitButton());
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'P1: « Order » then « Contract »: the field shows the invoice kept, and « Submit » gives that one',
    (tester) async {
      final page = await showPage(tester, six);
      await tester.enterText(
        find.byKey(PayoutPanel.invoiceField),
        invoice.text,
      );
      await tester.pump();
      await orderTabAndBack(tester);
      expect(fieldText(tester, PayoutPanel.invoiceField), invoice.text);
      expect(enabled(tester, submitButton()), isTrue);
      await submit(tester);
      expect(page.sender.sent.single.text, invoice.text);
    },
  );

  testWidgets(
    'P1 bis: a field emptied, then the panel built again: « Submit » off, nothing hidden is given',
    (tester) async {
      final page = await showPage(tester, six);
      await tester.enterText(
        find.byKey(PayoutPanel.invoiceField),
        invoice.text,
      );
      await tester.pump();
      await tester.enterText(find.byKey(PayoutPanel.invoiceField), '');
      await tester.pump();
      await orderTabAndBack(tester);
      expect(fieldText(tester, PayoutPanel.invoiceField), isEmpty);
      expect(enabled(tester, submitButton()), isFalse);
      expect(page.cubit.state.submittable(PayoutKind.lightning), isNull);
    },
  );

  testWidgets(
    'P2: a line « cannot reach » added above keeps the panel and what it shows',
    (tester) async {
      final page = await showPage(tester, six);
      await tester.enterText(
        find.byKey(PayoutPanel.invoiceField),
        invoice.text,
      );
      await tester.pump();
      final before = tester.state(find.byType(PayoutPanel));
      page.watch.emit(TradeScreenStatuses.watched(six, failedReads: 3));
      await tester.pump();
      await tester.pump();
      // The same panel (keyed), and in any case the same text.
      expect(identical(tester.state(find.byType(PayoutPanel)), before), isTrue);
      expect(fieldText(tester, PayoutPanel.invoiceField), invoice.text);
      expect(enabled(tester, submitButton()), isTrue);
    },
  );

  testWidgets(
    'P3: Onchain, a rate typed, the panel built again: the screen shows that rate and its figures, and « Submit » gives them',
    (tester) async {
      final page = await showPage(tester, sixSwap);
      await tester.tap(find.text('Onchain'));
      await tester.pump();
      await tester.enterText(
        find.byKey(PayoutPanel.addressField),
        mainnetAddress,
      );
      await tester.enterText(find.byKey(PayoutPanel.feeField), '50');
      await tester.pump();
      await orderTabAndBack(tester);
      // Still on Onchain, as the form was left.
      expect(fieldText(tester, PayoutPanel.addressField), mainnetAddress);
      expect(fieldText(tester, PayoutPanel.feeField), '50');
      expect(find.text('14,000 Sats (50 Sats/vByte)'), findsOneWidget);
      expect(find.text('91,912 Sats'), findsOneWidget);
      expect(find.text('980 Sats (3.5 Sats/vByte)'), findsNothing);
      await submit(tester);
      final sent = page.sender.sent.single as CheckedPayoutAddress;
      expect(sent.rate, MiningFeeRate.of(50));
      expect(sent.sentSats, 91912);
    },
  );

  testWidgets(
    'P3 bis: a routing budget typed, the panel built again: the budget and the amount it asks are shown, and given',
    (tester) async {
      final whole = Bolt11TestInvoice(
        network: Bolt11Network.mainnet,
        sats: 106713,
        seed: 73,
        createdAt: tradeNow,
        expiry: const Duration(days: 2),
      );
      final local = Bolt11Reader(Bolt11TestDecoder([whole]));
      final sender = _Sender()..answer = (s) => Ok(PayoutGiven(record, seven));
      final cubit = PayoutCubit(
        record,
        PayoutAsk.of,
        (record, seen, destination) => switch (PayoutAsk.of(record, seen)) {
          Err(:final failure) => Err(failure),
          Ok(:final value) => value.check(
            destination,
            now: readAt,
            reader: local,
          ),
        },
        sender.call,
        (_) => () {},
        now: () => readAt.add(const Duration(seconds: 1)),
      );
      addTearDown(cubit.close);
      Widget panel() => harness(
        BlocProvider.value(
          value: cubit,
          child: SingleChildScrollView(
            child: PayoutPanel(
              request: PayoutPanelRequest(
                record: record,
                seen: six,
                coordinator: 'Temple of Sats',
                now: readAt,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(panel());
      await tester.pump();
      await tester.tap(find.byType(BullSwitch));
      await tester.pump();
      await tester.enterText(find.byKey(PayoutPanel.budgetField), '0');
      await tester.enterText(find.byKey(PayoutPanel.invoiceField), whole.text);
      await tester.pump();
      // Built again.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(panel());
      await tester.pump();
      expect(fieldText(tester, PayoutPanel.budgetField), '0');
      expect(find.text('Submit invoice for 106,713 Sats'), findsOneWidget);
      expect(fieldText(tester, PayoutPanel.invoiceField), whole.text);
      await submit(tester);
      final sent = sender.sent.single as CheckedPayoutInvoice;
      expect(sent.budget, RoutingBudgetPpm.of(0));
      expect(sent.text, whole.text);
    },
  );

  testWidgets(
    'P4: the coordinator\'s suggestion changes at a later read: taken once, as the reference does, the screen keeps showing the rate it gives, and « Submit » gives it',
    (tester) async {
      final page = await showPage(tester, sixSwap);
      await tester.tap(find.text('Onchain'));
      await tester.pump();
      await tester.enterText(
        find.byKey(PayoutPanel.addressField),
        mainnetAddress,
      );
      await tester.pump();
      page.watch.emit(TradeScreenStatuses.watched(sixSwapLater));
      await tester.pump();
      await tester.pump();
      expect(fieldText(tester, PayoutPanel.feeField), '3.5');
      expect(find.text('980 Sats (3.5 Sats/vByte)'), findsOneWidget);
      expect(find.textContaining('40 Sats/vByte'), findsNothing);
      await submit(tester);
      final sent = page.sender.sent.single as CheckedPayoutAddress;
      expect(sent.rate, MiningFeeRate.of(3.5));
    },
  );

  testWidgets(
    '15 on a screen open since 6: the invoice kept is checked again against 15, its field showing it, and « Submit » gives only that one',
    (tester) async {
      final page = await showPage(tester, six);
      await tester.enterText(
        find.byKey(PayoutPanel.invoiceField),
        invoice.text,
      );
      await tester.pump();
      page.watch.emit(TradeScreenStatuses.watched(fifteenExpired));
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Your invoice has expired or more than 3 payment attempts have been made. Submit a new invoice.',
        ),
        findsOneWidget,
      );
      expect(fieldText(tester, PayoutPanel.invoiceField), invoice.text);
      // As the reference keeps its form above its prompts: the coordinator refuses the same invoice (3002), the user's to change.
      expect(page.cubit.state.seen, same(fifteenExpired));
      expect(enabled(tester, submitButton()), isTrue);
      await submit(tester);
      expect(page.sender.sent.single.text, invoice.text);
    },
  );

  testWidgets(
    'P5: what is pasted: one invoice only, the lowercase prefix taken off the field itself, the cursor at its start',
    (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async =>
            call.method == 'Clipboard.getData' ? {'text': clipboard} : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final page = await showPage(tester, six);
      final half = invoice.text.length ~/ 2;
      for (final pasted in [
        '${invoice.text.substring(0, half)}\u200b${invoice.text.substring(half)}',
        '${invoice.text}\n${invoice.text}',
        'LIGHTNING:${invoice.text}',
        'lightning:${invoice.text}?amount=1',
        '\u2066${invoice.text}\u2069',
        invoice.text.toUpperCase(),
      ]) {
        clipboard = pasted;
        await tester.tap(find.byTooltip('Paste'));
        await tester.pump();
        await tester.pump();
        expect(
          page.cubit.state.submittable(PayoutKind.lightning),
          isNull,
          reason: '${pasted.length}',
        );
      }
      clipboard = 'lightning:${invoice.text}';
      await tester.tap(find.byTooltip('Paste'));
      await tester.pump();
      await tester.pump();
      expect(
        page.cubit.state.submittable(PayoutKind.lightning)?.text,
        invoice.text,
      );
      final field = tester.widget<TextField>(
        find.byKey(PayoutPanel.invoiceField),
      );
      expect(field.controller?.text, invoice.text);
      expect(
        field.controller?.selection,
        const TextSelection.collapsed(offset: 0),
      );
    },
  );

  testWidgets(
    'P6: an address: hidden characters, an URI, a space before are refused; capitals are given as typed',
    (tester) async {
      final page = await showPage(tester, sixSwap);
      await tester.tap(find.text('Onchain'));
      await tester.pump();
      for (final (typed, given) in [
        ('bc1qw508d6qejxtdg4y5r3za\u200brvary0c5xw7kv8f3t4', false),
        ('bitcoin:$mainnetAddress', false),
        ('bitcoin:$mainnetAddress?amount=1', false),
        (' $mainnetAddress', false),
        (mainnetAddress.toUpperCase(), true),
      ]) {
        await tester.enterText(find.byKey(PayoutPanel.addressField), typed);
        await tester.pump();
        final offered = page.cubit.state.submittable(PayoutKind.onchain);
        expect(offered != null, given, reason: '${typed.length}');
        if (offered != null) expect(offered.text, typed);
      }
    },
  );

  testWidgets(
    'the route: « Cancel » is off while a payout is given, and once it told something the watch is asked to read at once (review of #132, M-a)',
    (tester) async {
      final gate = Completer<void>();
      final sender = _Sender()
        ..gate = gate.future
        ..answer = (s) => Ok(PayoutGiven(record, seven));
      final page = await showPage(tester, six, sender: sender);
      await tester.enterText(
        find.byKey(PayoutPanel.invoiceField),
        invoice.text,
      );
      await tester.pump();
      await submit(tester);
      final cancel = find.widgetWithText(TradeButton, 'Cancel');
      await tester.ensureVisible(cancel);
      await tester.pump();
      expect(tester.widget<TradeButton>(cancel).onPressed, isNull);
      // Seen from the « Order » tab too: the send goes on, and « Cancel » comes back with it.
      final readsBefore = page.watch.signals
          .where((s) => s == TradeWatchSignal.readNow)
          .length;
      await tester.tap(
        find.descendant(
          of: find.byType(BullSegmented).first,
          matching: find.text('Order'),
        ),
      );
      await tester.pump();
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(
        page.watch.signals.where((s) => s == TradeWatchSignal.readNow).length,
        readsBefore + 1,
      );
      await tester.tap(find.text('Contract'));
      await tester.pump();
      await tester.ensureVisible(cancel);
      await tester.pump();
      expect(tester.widget<TradeButton>(cancel).onPressed, isNotNull);
      expect(sender.sent, hasLength(1));
    },
  );
}

final class _Page {
  final _Watch watch;
  final _Sender sender;
  final PayoutCubit cubit;

  const _Page(this.watch, this.sender, this.cubit);
}

/// The trade's watch: emits what the test gives it and records the signals.
final class _Watch {
  final _states = StreamController<TradeWatchState>.broadcast();
  final List<TradeWatchSignal> signals = [];

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
        told = signals.listen(this.signals.add);
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

/// The payout « sent »: records what it was given, waits for [gate], and answers [answer].
final class _Sender {
  final List<CheckedPayout> sent = [];
  Future<void>? gate;
  Result<PayoutSubmission, PayoutNotSent> Function(CheckedPayout shown)? answer;

  Future<Result<PayoutSubmission, PayoutNotSent>> call(
    TradeRecord record,
    CheckedPayout shown, {
    void Function(PayoutProgress step)? onProgress,
  }) async {
    sent.add(shown);
    onProgress?.call(PayoutProgress.unlockingKey);
    if (gate case final gate?) await gate;
    final answer = this.answer;
    if (answer == null) throw StateError('no answer scripted');
    return answer(shown);
  }
}
