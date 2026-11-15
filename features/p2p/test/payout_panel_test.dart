import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_payout_outcome.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/presentation/payout_cubit.dart';
import 'package:p2p/src/ui/trade/payout_panel.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart' show Bolt11TestDecoder, Bolt11TestInvoice;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/harness.dart';
import 'support/key_output.dart';
import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

/// The payout panel of #91 and its cubit, over statuses the trade's state machine makes from the reference coordinator's answers, the checks of `SubmitPayoutUsecase` run for real, and a payout « sent » to a fake that records what it was given: never a coordinator, never a real invoice, address or key.
void main() {
  final record = TradeScreenStatuses.record;
  // The buyer's amount of the book's order (106,900 sats less the taker fee of 187), and the invoice asked with the default budget of 1,000 ppm.
  final buyerSats = payoutOf(bookSats);
  const asked = 106606;
  // When the statuses were read, and the panel's clock.
  final readAt = tradeNow.add(const Duration(seconds: 30));
  // BIP-173's own test vector, which no wallet of the project holds.
  const mainnetAddress = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
  const coordinatorName = 'Temple of Sats';

  Bolt11TestInvoice payoutInvoice({
    int sats = asked,
    int seed = 70,
    Bolt11Network network = Bolt11Network.mainnet,
    Duration expiry = const Duration(days: 2),
  }) => Bolt11TestInvoice(
    network: network,
    sats: sats,
    seed: seed,
    createdAt: tradeNow,
    expiry: expiry,
  );

  final invoice = payoutInvoice();
  final wrongAmount = payoutInvoice(sats: asked + 1, seed: 71);
  final testnetInvoice = payoutInvoice(
    seed: 72,
    network: Bolt11Network.testnet,
  );
  final wholeAmount = payoutInvoice(sats: buyerSats, seed: 73);
  final reader = Bolt11Reader(
    Bolt11TestDecoder([invoice, wrongAmount, testnetInvoice, wholeAmount]),
  );

  late TradeScreenStatuses statuses;
  late TradeSeen six;
  late TradeSeen sixSwap;
  late TradeSeen seven;
  late TradeSeen fifteenExpired;
  late TradeSeen fifteenRetrying;

  setUpAll(() async {
    statuses = await TradeScreenStatuses.make();
    six = await statuses.waitingForBoth();
    sixSwap = await statuses.read(
      await statuses.bondStep(),
      orderJson(
        6,
        changes: {
          'swap_allowed': true,
          'swap_failure_reason': null,
          'suggested_mining_fee_rate': 3.5,
          'swap_fee_rate': 0.75,
        },
      ),
    );
    seven = await statuses.waitingForEscrow();
    fifteenExpired = await statuses.read(
      await statuses.waitingForPayout(),
      orderJson(15),
    );
    fifteenRetrying = await statuses.read(
      await statuses.waitingForPayout(),
      orderJson(15, changes: {'invoice_expired': null}),
    );
  });

  Result<CheckedPayout, PayoutCheckRefusal> check(
    TradeRecord record,
    TradeSeen seen,
    PayoutDestination destination,
  ) => switch (PayoutAsk.of(record, seen)) {
    Err(:final failure) => Err(failure),
    Ok(:final value) => value.check(destination, now: readAt, reader: reader),
  };

  // The app's clock, the one the reads are dated with: a second after the statuses were read.
  DateTime clock() => readAt.add(const Duration(seconds: 1));

  PayoutCubit cubitOf(_Sender sender, [_Holds? holds]) {
    final cubit = PayoutCubit(
      record,
      PayoutAsk.of,
      check,
      sender.call,
      (holds ?? _Holds()).call,
      now: clock,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  group('the cubit', () {
    test(
      'gives the very payout shown, once, and says each wait as it starts',
      () async {
        final sender = _Sender()
          ..answer = (shown) => Ok(PayoutGiven(record, seven));
        final cubit = cubitOf(sender)..show(six);
        final ask = switch (cubit.state.ask) {
          Ok(:final value) => value,
          final other => throw StateError('$other'),
        };
        expect(ask.buyerSats, Sats.fromInt(buyerSats));
        expect(
          ask.invoiceSatsFor(RoutingBudgetPpm.referenceDefault),
          Sats.fromInt(asked),
        );
        // Nothing pasted: nothing to give.
        expect(cubit.state.submittable(PayoutKind.lightning), isNull);
        await cubit.submitShown(PayoutKind.lightning);
        expect(sender.sent, isEmpty);

        cubit.editInvoice(invoice.text);
        final shown = cubit.state.submittable(PayoutKind.lightning);
        expect(shown, isA<CheckedPayoutInvoice>());
        // A check is no confirmation: nothing is given without « Submit ».
        await pumpEventQueue();
        expect(sender.sent, isEmpty);
        final phases = <PayoutPhase>[];
        final listening = cubit.stream.listen((s) => phases.add(s.phase));
        final gate = Completer<void>();
        sender.gate = gate.future;
        final first = cubit.submitShown(PayoutKind.lightning);
        // A second « Submit » while the first is given does nothing.
        await cubit.submitShown(PayoutKind.lightning);
        await pumpEventQueue();
        expect(cubit.state.phase, isA<PayoutSending>());
        gate.complete();
        await first;
        await pumpEventQueue();
        await listening.cancel();
        expect(sender.sent, hasLength(1));
        expect(identical(sender.sent.single, shown), isTrue);
        expect(
          [
            for (final phase in phases)
              if (phase case PayoutSending(:final step)) step,
          ],
          [
            PayoutProgress.opening,
            PayoutProgress.unlockingKey,
            PayoutProgress.readingOrder,
            PayoutProgress.sending,
            PayoutProgress.readingAfter,
          ],
        );
        expect(
          cubit.state.phase,
          isA<PayoutEditing>().having(
            (p) => p.notice,
            'notice',
            isA<PayoutNoticeGiven>(),
          ),
        );
      },
    );

    test(
      'a change since it was shown: the form checked again against the fresh read is shown, and only a new submit gives it',
      () async {
        final fresh = switch (check(
          record,
          six,
          PayoutInvoiceText(
            invoice.text,
            budget: RoutingBudgetPpm.referenceDefault,
          ),
        )) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        // The use case's fresh read, later than the status shown.
        final freshRead = await statuses.read(
          await statuses.bondStep(),
          orderJson(6),
          after: const Duration(seconds: 40),
        );
        final sender = _Sender();
        sender.answer = (shown) => sender.sent.length == 1
            ? Err(PayoutChangedSinceShown(fresh, freshRead))
            : Ok(PayoutGiven(record, seven));
        final cubit = cubitOf(sender)
          ..show(six)
          ..editInvoice(invoice.text);
        final shown = cubit.state.submittable(PayoutKind.lightning);
        await cubit.submitShown(PayoutKind.lightning);
        expect(identical(sender.sent.single, shown), isTrue);
        final again = cubit.state.submittable(PayoutKind.lightning);
        expect(again, isNotNull);
        expect(again?.text, invoice.text);
        // Checked again against the fresh read, which the panel now works from.
        expect(identical(again, shown), isFalse);
        expect(cubit.state.seen, same(freshRead));
        // A status read before it, shown late, changes nothing.
        cubit.show(six);
        expect(cubit.state.seen, same(freshRead));
        expect(
          cubit.state.phase,
          isA<PayoutEditing>().having(
            (p) => p.notice,
            'notice',
            isA<PayoutNoticeNotSent>().having(
              (n) => n.change,
              'change',
              PayoutChange.other,
            ),
          ),
        );
        await pumpEventQueue();
        expect(sender.sent, hasLength(1));
        await cubit.submitShown(PayoutKind.lightning);
        expect(sender.sent, hasLength(2));
        expect(identical(sender.sent.last, again), isTrue);
      },
    );

    test(
      'an outcome unknown is never given again by the cubit, nor offered until a later read still asks',
      () async {
        final sender = _Sender()
          ..answer = (shown) => Ok(PayoutOutcomeUnknown(record, six));
        final cubit = cubitOf(sender)
          ..show(six)
          ..editInvoice(invoice.text);
        await cubit.submitShown(PayoutKind.lightning);
        await pumpEventQueue();
        expect(sender.sent, hasLength(1));
        expect(
          cubit.state.phase,
          isA<PayoutEditing>().having(
            (p) => p.notice,
            'notice',
            isA<PayoutNoticeUnknown>(),
          ),
        );
        expect(cubit.state.submittable(PayoutKind.lightning), isNull);
        await cubit.submitShown(PayoutKind.lightning);
        expect(sender.sent, hasLength(1));
        // A status read no later than what it told (an older read shown late) offers nothing.
        cubit.show(TradeSeen(six.status, order: six.order, stored: true));
        expect(cubit.state.submittable(PayoutKind.lightning), isNull);
        // A read with no time of sending, answered after it: not after the outcome, the safe side.
        final later = await statuses.read(
          await statuses.bondStep(),
          orderJson(6),
          after: const Duration(minutes: 2),
        );
        expect(later.requestedAt, isNull);
        cubit.show(later);
        expect(cubit.state.submittable(PayoutKind.lightning), isNull);
        // A read sent after it, at 6 still: the payout is asked again, and offered.
        cubit.show(
          TradeSeen(
            later.status,
            order: later.order,
            stored: true,
            requestedAt: later.status.seenAt,
          ),
        );
        expect(cubit.state.submittable(PayoutKind.lightning), isNotNull);
      },
    );

    test(
      'a status shown while a payout is given leaves the payout running',
      () async {
        final gate = Completer<void>();
        final sender = _Sender()
          ..gate = gate.future
          ..answer = (shown) => Ok(PayoutGiven(record, seven));
        final cubit = cubitOf(sender)
          ..show(six)
          ..editInvoice(invoice.text);
        final running = cubit.submitShown(PayoutKind.lightning);
        await pumpEventQueue();
        cubit.show(
          await statuses.read(
            await statuses.bondStep(),
            orderJson(6),
            after: const Duration(minutes: 1),
          ),
        );
        expect(cubit.state.phase, isA<PayoutSending>());
        expect(cubit.state.submittable(PayoutKind.lightning), isNull);
        gate.complete();
        await running;
        expect(sender.sent, hasLength(1));
      },
    );

    test(
      'a status not stored, or one that asks nothing, gives nothing to submit',
      () async {
        final sender = _Sender();
        final cubit = cubitOf(sender)
          ..show(TradeSeen(six.status, order: six.order))
          ..editInvoice(invoice.text);
        expect(
          cubit.state.ask,
          isA<Err<PayoutAsk, PayoutCheckRefusal>>().having(
            (e) => e.failure,
            'refusal',
            isA<PayoutNeedsARead>(),
          ),
        );
        expect(cubit.state.submittable(PayoutKind.lightning), isNull);
        // The status moves on: the invoice kept in the form is checked again against it.
        cubit.show(six);
        expect(cubit.state.submittable(PayoutKind.lightning), isNotNull);
        cubit.show(seven);
        expect(
          cubit.state.invoice,
          isA<Err<CheckedPayout, PayoutCheckRefusal>>().having(
            (e) => e.failure,
            'refusal',
            isA<PayoutNotAsked>(),
          ),
        );
        await cubit.submitShown(PayoutKind.lightning);
        expect(sender.sent, isEmpty);
      },
    );

    test(
      'holds the key once, lets it go, and lets it go when closed',
      () async {
        final holds = _Holds();
        final cubit = PayoutCubit(
          record,
          PayoutAsk.of,
          check,
          _Sender().call,
          holds.call,
          now: clock,
        );
        cubit
          ..hold()
          ..hold();
        expect(holds.held, 1);
        expect(cubit.holdsKey, isTrue);
        cubit
          ..release()
          ..release();
        expect(holds.released, 1);
        cubit.hold();
        await cubit.close();
        expect(holds.held, 2);
        expect(holds.released, 2);
        expect(cubit.holdsKey, isFalse);
      },
    );

    test(
      'no on-chain payout for an order in bitcoin, as the reference disables its tab',
      () async {
        final swapOrder = await statuses.read(
          await statuses.bondStep(),
          orderJson(
            6,
            changes: {
              'swap_allowed': true,
              'swap_failure_reason': null,
              'suggested_mining_fee_rate': 3.5,
              'swap_fee_rate': 0.75,
              'currency': 1000,
            },
          ),
        );
        final ask = switch (PayoutAsk.of(record, swapOrder)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        expect(ask.isSwapOrder, isTrue);
        expect(ask.onchain, isNull);
        expect(ask.onchainRefusal, isNull);
        expect(switch (PayoutAsk.of(record, sixSwap)) {
          Ok(:final value) => value.onchain,
          Err() => null,
        }, isNotNull);
      },
    );
  });

  test(
    'nothing printed or logged by the cubit: no invoice, no address',
    () async {
      final sender = _Sender()
        ..answer = (shown) => Ok(PayoutGiven(record, seven));
      final cubit = cubitOf(sender);
      final output = await captureKeyOutput(() async {
        cubit
          ..show(sixSwap)
          ..editInvoice(invoice.text)
          ..editAddress(mainnetAddress)
          ..editFee('4');
        await cubit.submitShown(PayoutKind.lightning);
        // The values print their kind only.
        Zone.current.print(
          '${cubit.state.invoice} ${cubit.state.address} ${cubit.state.phase}',
        );
      });
      expect(output.contains(invoice.text.substring(0, 30)), isFalse);
      expect(output.contains(mainnetAddress), isFalse);
    },
  );

  group('the panel', () {
    late String? clipboard;
    late List<String> copied;

    setUp(() {
      clipboard = null;
      copied = [];
    });

    void mockClipboard(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          switch (call.method) {
            case 'Clipboard.getData':
              return {'text': clipboard};
            case 'Clipboard.setData':
              final arguments = call.arguments;
              if (arguments is Map) copied.add('${arguments['text']}');
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
    }

    Future<int> show(
      WidgetTester tester,
      PayoutCubit cubit,
      TradeSeen seen, {
      Locale locale = const Locale('en'),
      Size size = const Size(390, 844),
      double textScale = 1,
      DateTime? now,
    }) async {
      tester.view
        ..physicalSize = size * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // A fresh tree, so that a panel shown with another cubit is a new panel.
      await tester.pumpWidget(const SizedBox.shrink());
      var told = 0;
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
            body: BlocProvider.value(
              value: cubit,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: PayoutTold(
                  onTold: () => told++,
                  child: PayoutPanel(
                    request: PayoutPanelRequest(
                      record: record,
                      seen: seen,
                      coordinator: coordinatorName,
                      now: now ?? readAt,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return told;
    }

    Future<void> reveal(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pump();
    }

    Finder submitButton() => find.widgetWithText(TradeButton, 'Submit');

    bool enabled(WidgetTester tester, Finder button) =>
        tester.widget<TradeButton>(button).onPressed != null;

    testWidgets(
      '6, Lightning: the amount asked, the invoice read, « Submit » gives it, and each wait says what it waits for',
      (tester) async {
        final gate = Completer<void>();
        final sender = _Sender()
          ..gate = gate.future
          ..answer = (shown) => Ok(PayoutGiven(record, seven));
        final cubit = cubitOf(sender);
        var told = 0;
        tester.view
          ..physicalSize = const Size(390, 844) * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          harness(
            BlocProvider.value(
              value: cubit,
              child: SingleChildScrollView(
                child: PayoutTold(
                  onTold: () => told++,
                  child: PayoutPanel(
                    request: PayoutPanelRequest(
                      record: record,
                      seen: six,
                      coordinator: coordinatorName,
                      now: readAt,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Lightning'), findsOneWidget);
        expect(find.text('Onchain'), findsOneWidget);
        expect(
          find.text('Temple of Sats does not offer swaps.'),
          findsOneWidget,
        );
        expect(find.text('Submit invoice for 106,606 Sats'), findsOneWidget);
        expect(enabled(tester, submitButton()), isFalse);

        await tester.enterText(
          find.byKey(PayoutPanel.invoiceField),
          invoice.text,
        );
        await tester.pump();
        expect(find.text('106,606 Sats'), findsOneWidget);
        expect(find.text('Bitcoin'), findsOneWidget);
        expect(enabled(tester, submitButton()), isTrue);
        // Valid two days, past the step and a day: no warning.
        expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

        await reveal(tester, submitButton());
        await tester.tap(submitButton());
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(sender.sent, hasLength(1));
        expect(sender.sent.single.text, invoice.text);
        expect(
          find.text('Sending your payout info to Temple of Sats…'),
          findsOneWidget,
        );
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        // After 30 s, that it still waits.
        await tester.pump(PayoutCubit.stillWaitingAfter);
        expect(
          find.text('Still waiting for Temple of Sats. Tor can take a minute.'),
          findsOneWidget,
        );
        gate.complete();
        await tester.pump();
        await tester.pump();
        expect(
          find.text('Temple of Sats received your payout info.'),
          findsOneWidget,
        );
        expect(told, 1);
        expect(sender.sent, hasLength(1));
        // Received: « Submit » is not offered again.
        expect(enabled(tester, submitButton()), isFalse);
      },
    );

    testWidgets(
      '« Paste » reads the clipboard once, and the copy copies the amount',
      (tester) async {
        mockClipboard(tester);
        clipboard = '${invoice.text}\n';
        final cubit = cubitOf(_Sender());
        await show(tester, cubit, six);
        await tester.tap(find.byTooltip('Paste'));
        await tester.pump();
        await tester.pump();
        expect(find.text('106,606 Sats'), findsOneWidget);
        expect(
          cubit.state.submittable(PayoutKind.lightning)?.text,
          invoice.text,
        );
        await tester.tap(find.byTooltip('Copy the amount'));
        await tester.pump();
        expect(copied, ['106606']);
        expect(find.text('Copied!'), findsWidgets);
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'the routing budget changes the amount asked, and says when it is above 1 %',
      (tester) async {
        final cubit = cubitOf(_Sender());
        await show(tester, cubit, six);
        expect(find.text('Routing Budget'), findsNothing);
        await tester.tap(find.byType(BullSwitch));
        await tester.pump();
        expect(find.text('Routing Budget'), findsOneWidget);
        await tester.enterText(find.byKey(PayoutPanel.budgetField), '0');
        await tester.pump();
        expect(find.text('Submit invoice for 106,713 Sats'), findsOneWidget);
        await tester.enterText(
          find.byKey(PayoutPanel.invoiceField),
          wholeAmount.text,
        );
        await tester.pump();
        expect(enabled(tester, submitButton()), isTrue);
        await tester.enterText(find.byKey(PayoutPanel.budgetField), '20000');
        await tester.pump();
        expect(find.text('Too high! (That is more than 1%)'), findsOneWidget);
        // In red, as the reference's helper text.
        expect(
          tester
              .widget<Text>(find.text('Too high! (That is more than 1%)'))
              .style
              ?.color,
          testTheme.extension<BullTheme>()?.error,
        );
        // As the reference takes it: 99,999 ppm or more is refused, the field keeping the budget applied; an empty field is 0.
        await tester.enterText(find.byKey(PayoutPanel.budgetField), '99999');
        await tester.pump();
        expect(_fieldText(tester, PayoutPanel.budgetField), '20000');
        expect(cubit.state.form.budget, RoutingBudgetPpm.of(20000));
        await tester.enterText(find.byKey(PayoutPanel.budgetField), '');
        await tester.pump();
        expect(_fieldText(tester, PayoutPanel.budgetField), '0');
        expect(cubit.state.form.budget, RoutingBudgetPpm.of(0));
        await tester.enterText(find.byKey(PayoutPanel.budgetField), '20000');
        await tester.pump();
        // The whole amount is no longer the one asked.
        expect(find.text('Invalid invoice amount'), findsOneWidget);
        expect(enabled(tester, submitButton()), isFalse);
        // Off: the default budget again.
        await tester.tap(find.byType(BullSwitch));
        await tester.pump();
        expect(find.text('Submit invoice for 106,606 Sats'), findsOneWidget);
      },
    );

    testWidgets(
      'each refusal of the check has its text, and « Submit » stays off',
      (tester) async {
        final cubit = cubitOf(_Sender());
        await show(tester, cubit, six);
        for (final (text, said) in [
          (wrongAmount.text, 'Invalid invoice amount'),
          (
            testnetInvoice.text,
            'This invoice is for another network than the trade\'s.',
          ),
          (
            'lnbc1notaninvoice',
            'This is not a Lightning invoice this app can read.',
          ),
        ]) {
          await tester.enterText(find.byKey(PayoutPanel.invoiceField), text);
          await tester.pump();
          expect(find.text(said), findsOneWidget, reason: text);
          expect(enabled(tester, submitButton()), isFalse, reason: text);
        }
      },
    );

    testWidgets(
      'an invoice that may expire first is said, and can still be given',
      (tester) async {
        final short = payoutInvoice(seed: 74, expiry: const Duration(hours: 1));
        final local = Bolt11Reader(Bolt11TestDecoder([short]));
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
          _Sender().call,
          _Holds().call,
          now: clock,
        );
        addTearDown(cubit.close);
        await show(tester, cubit, six);
        await tester.enterText(
          find.byKey(PayoutPanel.invoiceField),
          short.text,
        );
        await tester.pump();
        expect(find.textContaining('This invoice expires on'), findsOneWidget);
        expect(enabled(tester, submitButton()), isTrue);
      },
    );

    testWidgets(
      'Onchain: the swap\'s fees and the final amount, the mining fee checked, the address given',
      (tester) async {
        final sender = _Sender()
          ..answer = (shown) => Ok(PayoutGiven(record, seven));
        final cubit = cubitOf(sender);
        await show(tester, cubit, sixSwap);
        await tester.tap(find.text('Onchain'));
        await tester.pump();
        expect(
          find.text(
            'RoboSats coordinator will do a swap and send the Sats to your onchain address.',
          ),
          findsOneWidget,
        );
        // `floor(106713 × 0.75 / 100)`, `int(3.5 × 280)`, `int(106713 − 800.3475 − 980)`.
        expect(find.text('800 Sats (0.75%)'), findsOneWidget);
        expect(find.text('980 Sats (3.5 Sats/vByte)'), findsOneWidget);
        expect(find.text('104,932 Sats'), findsOneWidget);
        expect(enabled(tester, submitButton()), isFalse);
        await tester.enterText(
          find.byKey(PayoutPanel.addressField),
          mainnetAddress,
        );
        await tester.pump();
        expect(enabled(tester, submitButton()), isTrue);
        await tester.enterText(find.byKey(PayoutPanel.feeField), '600');
        await tester.pump();
        expect(find.text('Invalid'), findsOneWidget);
        expect(enabled(tester, submitButton()), isFalse);
        await tester.enterText(find.byKey(PayoutPanel.feeField), '4');
        await tester.pump();
        await reveal(tester, submitButton());
        await tester.tap(submitButton());
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(
          sender.sent.single,
          isA<CheckedPayoutAddress>()
              .having((a) => a.text, 'text', mainnetAddress)
              .having((a) => a.rate, 'rate', MiningFeeRate.of(4)),
        );
      },
    );

    testWidgets(
      'the coordinator\'s refusals are its own words, under the field; a refused invoice is not offered again until it changes',
      (tester) async {
        for (final (cause, said, underField, offeredAgain)
            in <(Failure, String, bool, bool)>[
              // The amount the coordinator expects, from its own message (review of #132).
              (
                const PayoutInvoiceRefused(
                  PayoutInvoiceRefusal.wrongAmount,
                  expectedSats: 106700,
                ),
                'The invoice provided is not for 106,700 Sats',
                true,
                false,
              ),
              (
                const PayoutInvoiceRefused(PayoutInvoiceRefusal.wrongAmount),
                'Invalid invoice amount',
                true,
                false,
              ),
              (
                const PayoutInvoiceRefused(
                  PayoutInvoiceRefusal.alreadySubmitted,
                ),
                'You must submit a NEW invoice',
                true,
                false,
              ),
              (
                const PayoutSignatureRefused(),
                'The PGP signed cleartext message is not valid.',
                true,
                true,
              ),
              // Never reached the coordinator: said under « Submit », and a new « Submit » is the user's own.
              (
                const RobotCoordinatorBusyFailure(),
                'Your payout info did not reach Temple of Sats: nothing was recorded. You can submit again.',
                false,
                true,
              ),
            ]) {
          final sender = _Sender()
            ..answer = (shown) => Ok(PayoutNotTaken(record, six, cause: cause));
          final cubit = cubitOf(sender);
          await show(tester, cubit, six);
          await tester.enterText(
            find.byKey(PayoutPanel.invoiceField),
            invoice.text,
          );
          await tester.pump();
          await reveal(tester, submitButton());
          await tester.tap(submitButton());
          for (var i = 0; i < 4; i++) {
            await tester.pump();
          }
          expect(find.text(said), findsOneWidget, reason: '$cause');
          // Under the field: above « Submit »; otherwise under it.
          final saidAt = tester.getTopLeft(find.text(said)).dy;
          final submitAt = tester.getTopLeft(submitButton()).dy;
          expect(saidAt < submitAt, underField, reason: '$cause');
          expect(
            enabled(tester, submitButton()),
            offeredAgain,
            reason: '$cause',
          );
          expect(sender.sent, hasLength(1));
          if (!offeredAgain) {
            // Another invoice, then this one again: offered, the refusal gone with the text it was about.
            await tester.enterText(find.byKey(PayoutPanel.invoiceField), '');
            await tester.pump();
            await tester.enterText(
              find.byKey(PayoutPanel.invoiceField),
              invoice.text,
            );
            await tester.pump();
            expect(find.text(said), findsNothing, reason: '$cause');
            expect(enabled(tester, submitButton()), isTrue, reason: '$cause');
          }
        }
      },
    );

    testWidgets('nothing sent: each reason said, and nothing given again', (
      tester,
    ) async {
      for (final (refusal, said) in <(PayoutNotSent, String)>[
        (
          const PayoutKeyUnavailable(CoordinatorUnreachable()),
          'The key of your robot could not be read from Temple of Sats. Nothing was sent.',
        ),
        (
          const PayoutReadFailed(),
          'Could not read the order from Temple of Sats. Nothing was sent.',
        ),
        (
          PayoutNoLongerValid(const PayoutNotAsked(), seven),
          'Temple of Sats does not ask for your payout info now.',
        ),
      ]) {
        final sender = _Sender()..answer = (shown) => Err(refusal);
        final cubit = cubitOf(sender);
        await show(tester, cubit, six);
        await tester.enterText(
          find.byKey(PayoutPanel.invoiceField),
          invoice.text,
        );
        await tester.pump();
        await reveal(tester, submitButton());
        await tester.tap(submitButton());
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(find.text(said), findsOneWidget, reason: '$refusal');
        expect(sender.sent, hasLength(1));
      }
    });

    testWidgets(
      '15, the invoice expired: the reference\'s text, the reason, the Lightning form alone',
      (tester) async {
        final cubit = cubitOf(_Sender());
        await show(tester, cubit, fifteenExpired);
        expect(
          find.text(
            'Your invoice has expired or more than 3 payment attempts have been made. Submit a new invoice.',
          ),
          findsOneWidget,
        );
        expect(find.text('Failure reason:'), findsOneWidget);
        expect(
          find.text('A non-recoverable error has occurred.'),
          findsOneWidget,
        );
        expect(find.text('Onchain'), findsNothing);
        expect(find.text('Submit invoice for 106,606 Sats'), findsOneWidget);
      },
    );

    testWidgets(
      '15 while the coordinator retries: the reason and the next attempt\'s countdown',
      (tester) async {
        final cubit = cubitOf(_Sender());
        // `next_retry_time` 09:10:00, the clock at 09:08:30.
        await show(
          tester,
          cubit,
          fifteenRetrying,
          now: DateTime.utc(2026, 11, 13, 9, 8, 30),
        );
        expect(find.text('Next attempt in'), findsOneWidget);
        expect(find.text('01m 30s'), findsOneWidget);
        expect(find.byKey(PayoutPanel.invoiceField), findsNothing);
        await show(
          tester,
          cubit,
          fifteenRetrying,
          now: DateTime.utc(2026, 11, 13, 9, 10, 1),
        );
        expect(find.text('Retrying!'), findsOneWidget);
      },
    );

    testWidgets('a status not stored: no form, and a line that says to wait', (
      tester,
    ) async {
      final cubit = cubitOf(_Sender());
      await show(tester, cubit, TradeSeen(six.status, order: six.order));
      expect(
        find.text(
          'Wait until the order is read again to give your payout info.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(PayoutPanel.invoiceField), findsNothing);
    });

    testWidgets(
      'the key is held while the panel is shown in the foreground, let go when the app is hidden or the panel leaves',
      (tester) async {
        final holds = _Holds();
        final cubit = cubitOf(_Sender(), holds);
        await show(tester, cubit, six);
        expect(holds.held, 1);
        expect(cubit.holdsKey, isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump();
        expect(cubit.holdsKey, isFalse);
        expect(holds.released, 1);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(cubit.holdsKey, isTrue);
        expect(holds.held, 2);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(cubit.holdsKey, isFalse);
        expect(holds.released, 2);
      },
    );

    testWidgets('the key is let go while another tab of the shell is shown', (
      tester,
    ) async {
      final holds = _Holds();
      final cubit = cubitOf(_Sender(), holds);
      Widget panel(bool enabled) => harness(
        TickerMode(
          enabled: enabled,
          child: BlocProvider.value(
            value: cubit,
            child: PayoutPanel(
              request: PayoutPanelRequest(
                record: record,
                seen: six,
                coordinator: coordinatorName,
                now: readAt,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(panel(true));
      expect(cubit.holdsKey, isTrue);
      await tester.pumpWidget(panel(false));
      expect(cubit.holdsKey, isFalse);
      await tester.pumpWidget(panel(true));
      expect(cubit.holdsKey, isTrue);
    });

    testWidgets(
      'a screen reader hears each wait and what it gave, as they appear',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final gate = Completer<void>();
        final sender = _Sender()
          ..gate = gate.future
          ..answer = (shown) => Ok(PayoutOutcomeUnknown(record, six));
        final cubit = cubitOf(sender);
        await show(tester, cubit, six);
        await tester.enterText(
          find.byKey(PayoutPanel.invoiceField),
          invoice.text,
        );
        await tester.pump();
        await reveal(tester, submitButton());
        await tester.tap(submitButton());
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(
          tester.getSemantics(
            find.text('Sending your payout info to Temple of Sats…'),
          ),
          matchesSemantics(
            label: 'Sending your payout info to Temple of Sats…',
            isLiveRegion: true,
          ),
        );
        gate.complete();
        await tester.pump();
        await tester.pump();
        const unknown =
            'Bull Market does not know yet whether Temple of Sats received your payout info. It keeps checking while this screen is open.';
        expect(
          tester.getSemantics(find.text(unknown)),
          matchesSemantics(label: unknown, isLiveRegion: true),
        );
        semantics.dispose();
      },
    );

    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets(
          'nothing cut or overflowing on a phone of 320 points, ${locale.languageCode}, text ×$scale',
          (tester) async {
            for (final (seen, onchainTab) in [
              (six, false),
              (sixSwap, true),
              (fifteenExpired, false),
              (fifteenRetrying, false),
            ]) {
              final cubit = cubitOf(
                _Sender()
                  ..answer = (shown) => Ok(
                    PayoutNotTaken(
                      record,
                      seen,
                      cause: const PayoutInvoiceRefused(
                        PayoutInvoiceRefusal.routeHintsUnpayable,
                      ),
                    ),
                  ),
              );
              await show(
                tester,
                cubit,
                seen,
                locale: locale,
                size: const Size(320, 640),
                textScale: scale,
                now: DateTime.utc(2026, 11, 13, 9, 8, 30),
              );
              if (onchainTab) {
                await tester.tap(find.text('Onchain'));
                await tester.pump();
                await tester.enterText(
                  find.byKey(PayoutPanel.addressField),
                  mainnetAddress,
                );
                await tester.enterText(find.byKey(PayoutPanel.feeField), '4');
                await tester.pump();
              } else if (seen != fifteenRetrying) {
                if (seen == six) {
                  // The advanced options open, a budget above 1 % and the copy's « Copied! ».
                  await tester.tap(find.byType(BullSwitch));
                  await tester.pump();
                  await tester.enterText(
                    find.byKey(PayoutPanel.budgetField),
                    '20000',
                  );
                  await tester.pump();
                  await reveal(tester, find.byTooltip(_copyTooltip(locale)));
                  await tester.tap(find.byTooltip(_copyTooltip(locale)));
                  await tester.pump();
                  _expectNothingCut(
                    tester,
                    'advanced ${locale.languageCode} $scale',
                  );
                  await tester.pump(const Duration(seconds: 3));
                  await reveal(tester, find.byType(BullSwitch));
                  await tester.tap(find.byType(BullSwitch));
                  await tester.pump();
                }
                await tester.enterText(
                  find.byKey(PayoutPanel.invoiceField),
                  invoice.text,
                );
                await tester.pump();
                await reveal(tester, find.byType(TradeButton).first);
                await tester.tap(find.byType(TradeButton).first);
                for (var i = 0; i < 4; i++) {
                  await tester.pump();
                }
              }
              _expectNothingCut(
                tester,
                '${seen.status} ${locale.languageCode} $scale',
              );
            }
          },
        );
      }
    }

    testWidgets(
      'a panel built again shows exactly the form the cubit holds, and « Submit » gives what it shows (review of #132, B1)',
      (tester) async {
        final sender = _Sender()
          ..answer = (shown) => Ok(PayoutGiven(record, seven));
        final cubit = cubitOf(sender);
        await show(tester, cubit, sixSwap);
        await tester.tap(find.byType(BullSwitch));
        await tester.pump();
        await tester.enterText(find.byKey(PayoutPanel.budgetField), '0');
        await tester.enterText(
          find.byKey(PayoutPanel.invoiceField),
          wholeAmount.text,
        );
        await tester.pump();
        await tester.tap(find.text('Onchain'));
        await tester.pump();
        await tester.enterText(
          find.byKey(PayoutPanel.addressField),
          mainnetAddress,
        );
        await tester.enterText(find.byKey(PayoutPanel.feeField), '50');
        await tester.pump();
        // Built again, as another tab of the trade or a line above it does.
        await show(tester, cubit, sixSwap);
        expect(find.text('Onchain'), findsOneWidget);
        expect(_fieldText(tester, PayoutPanel.addressField), mainnetAddress);
        expect(_fieldText(tester, PayoutPanel.feeField), '50');
        // `int(50 × 280)`, `int(106713 − 800.3475 − 14000)`.
        expect(find.text('14,000 Sats (50 Sats/vByte)'), findsOneWidget);
        expect(find.text('91,912 Sats'), findsOneWidget);
        await reveal(tester, submitButton());
        await tester.tap(submitButton());
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(
          sender.sent.single,
          isA<CheckedPayoutAddress>()
              .having((a) => a.text, 'text', mainnetAddress)
              .having((a) => a.rate, 'rate', MiningFeeRate.of(50))
              .having((a) => a.sentSats, 'sent', 91912),
        );
        // The Lightning tab kept its budget and its invoice too.
        await reveal(tester, find.text('Lightning'));
        await tester.tap(find.text('Lightning'));
        await tester.pump();
        expect(_fieldText(tester, PayoutPanel.budgetField), '0');
        expect(_fieldText(tester, PayoutPanel.invoiceField), wholeAmount.text);
        expect(find.text('Submit invoice for 106,713 Sats'), findsOneWidget);
      },
    );

    testWidgets(
      'Onchain: the suggestion taken once, as the reference does, not changed by a later read; the figures shown are the check\'s (review of #132, B2)',
      (tester) async {
        final later = await statuses.read(
          await statuses.bondStep(),
          orderJson(
            6,
            changes: {
              'swap_allowed': true,
              'swap_failure_reason': null,
              'suggested_mining_fee_rate': 40,
              'swap_fee_rate': 0.75,
            },
          ),
          after: const Duration(seconds: 31),
        );
        final sender = _Sender()
          ..answer = (shown) => Ok(PayoutGiven(record, seven));
        final cubit = cubitOf(sender);
        await show(tester, cubit, sixSwap);
        await tester.tap(find.text('Onchain'));
        await tester.pump();
        await tester.enterText(
          find.byKey(PayoutPanel.addressField),
          mainnetAddress,
        );
        await tester.pump();
        // What « Submit » gives: the address checked and its network.
        expect(find.text(mainnetAddress), findsWidgets);
        expect(find.text('Bitcoin'), findsOneWidget);
        await show(tester, cubit, later);
        expect(_fieldText(tester, PayoutPanel.feeField), '3.5');
        expect(find.text('980 Sats (3.5 Sats/vByte)'), findsOneWidget);
        expect(find.textContaining('40 Sats/vByte'), findsNothing);
        await reveal(tester, submitButton());
        await tester.tap(submitButton());
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(
          (sender.sent.single as CheckedPayoutAddress).rate,
          MiningFeeRate.of(3.5),
        );
      },
    );

    test(
      'the suggestion is taken when the on-chain payout is first offered, and a rate typed stays',
      () async {
        final later = await statuses.read(
          await statuses.bondStep(),
          orderJson(
            6,
            changes: {
              'swap_allowed': true,
              'swap_failure_reason': null,
              'suggested_mining_fee_rate': 40,
              'swap_fee_rate': 0.75,
            },
          ),
          after: const Duration(seconds: 31),
        );
        // No swap offered at first: nothing taken yet.
        final cubit = cubitOf(_Sender())..show(six);
        expect(cubit.state.form.fee, isNull);
        cubit.show(sixSwap);
        expect(cubit.state.form.fee, '3.5');
        cubit.show(later);
        expect(cubit.state.form.fee, '3.5');
        expect(cubit.state.rate, MiningFeeRate.of(3.5));
        cubit
          ..selectKind(PayoutKind.onchain)
          ..editAddress(mainnetAddress)
          ..editFee('4');
        cubit.show(
          await statuses.read(
            await statuses.bondStep(),
            orderJson(
              6,
              changes: {
                'swap_allowed': true,
                'swap_failure_reason': null,
                'suggested_mining_fee_rate': 12,
                'swap_fee_rate': 0.75,
              },
            ),
            after: const Duration(seconds: 32),
          ),
        );
        expect(cubit.state.rate, MiningFeeRate.of(4));
        expect(
          (cubit.state.submittable(PayoutKind.onchain) as CheckedPayoutAddress?)
              ?.rate,
          MiningFeeRate.of(4),
        );
      },
    );

    test(
      'while a payout is given, a status shown changes nothing it shows; it is applied once the payout told something',
      () async {
        final later = await statuses.read(
          await statuses.bondStep(),
          orderJson(
            6,
            changes: {
              'swap_allowed': true,
              'swap_failure_reason': null,
              'suggested_mining_fee_rate': 40,
              'swap_fee_rate': 1.5,
            },
          ),
          after: const Duration(seconds: 31),
        );
        final gate = Completer<void>();
        final sender = _Sender()
          ..gate = gate.future
          ..answer = (shown) => Ok(
            PayoutNotTaken(
              record,
              sixSwap,
              cause: const RobotCoordinatorBusyFailure(),
            ),
          );
        final cubit = cubitOf(sender)
          ..show(sixSwap)
          ..selectKind(PayoutKind.onchain)
          ..editAddress(mainnetAddress);
        final running = cubit.submitShown(PayoutKind.onchain);
        await pumpEventQueue();
        cubit
          ..show(later)
          // Edits wait too.
          ..editAddress('')
          ..editFee('9');
        expect(cubit.state.rate, MiningFeeRate.of(3.5));
        expect(cubit.state.form.address, mainnetAddress);
        expect(
          (cubit.state.address as Ok<CheckedPayout, PayoutCheckRefusal>?)
              ?.value,
          isA<CheckedPayoutAddress>()
              .having((a) => a.rate, 'rate', MiningFeeRate.of(3.5))
              .having((a) => a.swapFeePercent, 'swap fee', 0.75),
        );
        expect(cubit.state.seen, same(sixSwap));
        gate.complete();
        await running;
        // Applied once the payout told something; the rate, taken once, stays.
        expect(cubit.state.seen, same(later));
        expect(cubit.state.rate, MiningFeeRate.of(3.5));
        expect(
          (cubit.state.submittable(PayoutKind.onchain) as CheckedPayoutAddress?)
              ?.swapFeePercent,
          1.5,
        );
      },
    );

    test(
      '« Submit » is off for a check that is not what the fields show',
      () async {
        final cubit = cubitOf(_Sender())
          ..show(sixSwap)
          ..editInvoice(invoice.text);
        final checked = cubit.state.submittable(PayoutKind.lightning);
        expect(checked, isNotNull);
        expect(cubit.state.form.invoice, invoice.text);
        // The prefix of the reference is taken off the field itself.
        cubit.editInvoice('lightning:${invoice.text}');
        expect(cubit.state.form.invoice, invoice.text);
        expect(
          cubit.state.submittable(PayoutKind.lightning)?.text,
          invoice.text,
        );
      },
    );

    test(
      'execute that throws: the payout may have left, said so, never given again, and the fault goes on up (review of #132, P7)',
      () async {
        final cubit = PayoutCubit(
          record,
          PayoutAsk.of,
          check,
          (record, shown, {onProgress}) async => throw StateError('a fault'),
          _Holds().call,
          now: clock,
        );
        addTearDown(cubit.close);
        cubit
          ..show(six)
          ..editInvoice(invoice.text);
        await expectLater(
          cubit.submitShown(PayoutKind.lightning),
          throwsA(isA<StateError>()),
        );
        expect(
          cubit.state.phase,
          isA<PayoutEditing>().having(
            (p) => p.notice,
            'notice',
            isA<PayoutNoticeUnknown>(),
          ),
        );
        expect(cubit.state.submittable(PayoutKind.lightning), isNull);
        // A read sent after the fault, still asking: offered again, and said.
        final later = await statuses.read(
          await statuses.bondStep(),
          orderJson(6),
          after: const Duration(minutes: 2),
        );
        cubit.show(
          TradeSeen(
            later.status,
            order: later.order,
            stored: true,
            requestedAt: clock().add(const Duration(seconds: 1)),
          ),
        );
        expect(cubit.state.submittable(PayoutKind.lightning), isNotNull);
      },
    );

    test(
      'a read sent before the outcome came back offers nothing again; one sent after it, still asking, says so (review of #132, M-d)',
      () async {
        final sender = _Sender()
          ..answer = (shown) => Ok(PayoutOutcomeUnknown(record, six));
        final cubit = cubitOf(sender)
          ..show(six)
          ..editInvoice(invoice.text);
        await cubit.submitShown(PayoutKind.lightning);
        final read = await statuses.read(
          await statuses.bondStep(),
          orderJson(6),
          after: const Duration(minutes: 2),
        );
        // Answered after the outcome, sent before it.
        cubit.show(
          TradeSeen(
            read.status,
            order: read.order,
            stored: true,
            requestedAt: clock().subtract(const Duration(seconds: 1)),
          ),
        );
        expect(cubit.state.submittable(PayoutKind.lightning), isNull);
        // Sent the very instant the outcome came back: not after it.
        cubit.show(
          TradeSeen(
            read.status,
            order: read.order,
            stored: true,
            requestedAt: clock(),
          ),
        );
        expect(cubit.state.submittable(PayoutKind.lightning), isNull);
        cubit.show(
          TradeSeen(
            read.status,
            order: read.order,
            stored: true,
            requestedAt: clock().add(const Duration(seconds: 1)),
          ),
        );
        expect(cubit.state.submittable(PayoutKind.lightning), isNotNull);
        expect(
          cubit.state.phase,
          isA<PayoutEditing>().having(
            (p) => p.notice,
            'notice',
            isA<PayoutNoticeAskedAgain>(),
          ),
        );
      },
    );

    testWidgets(
      'while the trade is being cancelled, « Submit » is off and says why',
      (tester) async {
        final cubit = cubitOf(_Sender());
        await tester.pumpWidget(
          harness(
            BlocProvider.value(
              value: cubit,
              child: SingleChildScrollView(
                child: PayoutPanel(
                  request: PayoutPanelRequest(
                    record: record,
                    seen: six,
                    coordinator: coordinatorName,
                    now: readAt,
                    cancelling: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.enterText(
          find.byKey(PayoutPanel.invoiceField),
          invoice.text,
        );
        await tester.pump();
        expect(cubit.state.submittable(PayoutKind.lightning), isNotNull);
        expect(enabled(tester, submitButton()), isFalse);
        expect(
          find.byTooltip('Submit is off while the trade is being cancelled.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a screen reader hears the switch\'s name, each field\'s label and the wait of the progress bar',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final gate = Completer<void>();
        final sender = _Sender()
          ..gate = gate.future
          ..answer = (shown) => Ok(PayoutGiven(record, seven));
        final cubit = cubitOf(sender);
        await show(tester, cubit, six);
        final toggle = tester.getSemantics(find.byType(Switch));
        expect(toggle.label, 'Advanced options');
        expect(
          toggle.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(
          tester.getSemantics(find.byKey(PayoutPanel.invoiceField)).label,
          contains('Payout Lightning Invoice'),
        );
        await tester.enterText(
          find.byKey(PayoutPanel.invoiceField),
          invoice.text,
        );
        await tester.pump();
        await reveal(tester, submitButton());
        await tester.tap(submitButton());
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(
          tester.getSemantics(find.byType(LinearProgressIndicator)).label,
          'Sending your payout info to Temple of Sats…',
        );
        gate.complete();
        await tester.pump();
        await tester.pump();
        semantics.dispose();
      },
    );

    test('what changed since it was shown is told: the expiry', () async {
      // The step ends later at the fresh read: the invoice of two days now expires before its end and a day.
      final late = await statuses.read(
        await statuses.bondStep(),
        orderJson(6, expiresAt: tradeNow.add(const Duration(days: 3))),
      );
      CheckedPayout checkedAt(TradeSeen seen) => switch (check(
        record,
        seen,
        PayoutInvoiceText(
          invoice.text,
          budget: RoutingBudgetPpm.referenceDefault,
        ),
      )) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
      expect(
        PayoutChange.between(checkedAt(six), checkedAt(late)),
        PayoutChange.expiry,
      );
      expect(
        PayoutChange.between(checkedAt(six), checkedAt(six)),
        PayoutChange.other,
      );
    });

    test(
      'a check that is not of the text the field shows is never offered',
      () async {
        // A checker that checks another text than the one it is given: « Submit » trusts the fields, not it.
        final cubit = PayoutCubit(
          record,
          PayoutAsk.of,
          (record, seen, destination) => check(
            record,
            seen,
            PayoutInvoiceText(
              invoice.text,
              budget: RoutingBudgetPpm.referenceDefault,
            ),
          ),
          _Sender().call,
          _Holds().call,
          now: clock,
        );
        addTearDown(cubit.close);
        cubit
          ..show(six)
          ..editInvoice(wrongAmount.text);
        expect(
          cubit.state.invoice,
          isA<Ok<CheckedPayout, PayoutCheckRefusal>>(),
        );
        expect(cubit.state.submittable(PayoutKind.lightning), isNull);
      },
    );

    test(
      'a check made with another budget than the form\'s is never offered',
      () async {
        // A checker that checks with no routing budget whatever the form says: « Submit » trusts the form's budget, not it.
        final cubit = PayoutCubit(
          record,
          PayoutAsk.of,
          (record, seen, destination) => switch (destination) {
            PayoutInvoiceText(:final text) => check(
              record,
              seen,
              PayoutInvoiceText(
                text,
                budget: RoutingBudgetPpm.of(0) ?? (throw StateError('0')),
              ),
            ),
            _ => check(record, seen, destination),
          },
          _Sender().call,
          _Holds().call,
          now: clock,
        );
        addTearDown(cubit.close);
        cubit
          ..show(six)
          ..editInvoice(wholeAmount.text);
        expect(cubit.state.form.budget, RoutingBudgetPpm.referenceDefault);
        expect(
          cubit.state.invoice,
          isA<Ok<CheckedPayout, PayoutCheckRefusal>>(),
        );
        expect(cubit.state.submittable(PayoutKind.lightning), isNull);
      },
    );

    testWidgets(
      'a suggestion of more than 3 decimals: shown as it is with « Invalid », no figure computed from it, nothing to submit',
      (tester) async {
        final odd = await statuses.read(
          await statuses.bondStep(),
          orderJson(
            6,
            changes: {
              'swap_allowed': true,
              'swap_failure_reason': null,
              'suggested_mining_fee_rate': 3.14159,
              'swap_fee_rate': 0.75,
            },
          ),
        );
        final cubit = cubitOf(_Sender());
        await show(tester, cubit, odd);
        await tester.tap(find.text('Onchain'));
        await tester.pump();
        await tester.enterText(
          find.byKey(PayoutPanel.addressField),
          mainnetAddress,
        );
        await tester.pump();
        // As the coordinator sent it, not rounded into another rate.
        expect(_fieldText(tester, PayoutPanel.feeField), '3.14159');
        expect(find.text('Invalid'), findsOneWidget);
        expect(find.text('Mining fee'), findsNothing);
        expect(find.text('Final amount you will receive'), findsNothing);
        expect(enabled(tester, submitButton()), isFalse);
      },
    );

    for (final (name, outcome, said) in <(String, bool, String)>[
      ('received', true, 'Temple of Sats received your payout info.'),
      (
        'may have been received',
        false,
        'Bull Market does not know yet whether Temple of Sats received your payout info. It keeps checking while this screen is open.',
      ),
    ]) {
      testWidgets(
        'a payout $name, the read after it at 7: what it told and its form stay, read-only, not « does not ask » (second review of #132)',
        (tester) async {
          final sender = _Sender()
            ..answer = (shown) => Ok(
              outcome
                  ? PayoutGiven(record, seven)
                  : PayoutOutcomeUnknown(record, seven),
            );
          final cubit = cubitOf(sender);
          await show(tester, cubit, six);
          await tester.enterText(
            find.byKey(PayoutPanel.invoiceField),
            invoice.text,
          );
          await tester.pump();
          await reveal(tester, submitButton());
          await tester.tap(submitButton());
          for (var i = 0; i < 4; i++) {
            await tester.pump();
          }
          expect(
            cubit.state.ask,
            isA<Err<PayoutAsk, PayoutCheckRefusal>>().having(
              (e) => e.failure,
              'refusal',
              isA<PayoutNotAsked>(),
            ),
          );
          expect(find.text(said), findsOneWidget);
          expect(
            find.text('Temple of Sats does not ask for your payout info now.'),
            findsNothing,
          );
          expect(_fieldText(tester, PayoutPanel.invoiceField), invoice.text);
          expect(
            tester
                .widget<TextField>(find.byKey(PayoutPanel.invoiceField))
                .enabled,
            isFalse,
          );
          expect(enabled(tester, submitButton()), isFalse);
          // Built again with that status, as long as the screen still shows the panel: the same.
          await show(tester, cubit, seven);
          expect(find.text(said), findsOneWidget);
          expect(_fieldText(tester, PayoutPanel.invoiceField), invoice.text);
          cubit.editInvoice('');
          expect(cubit.state.form.invoice, invoice.text);
          expect(sender.sent, hasLength(1));
        },
      );
    }

    test(
      'a payout received: the outcome is dated when it came back, not by the read after it (second security review of #132)',
      () async {
        final sender = _Sender()
          ..answer = (shown) => Ok(PayoutGiven(record, seven));
        final cubit = cubitOf(sender)
          ..show(six)
          ..editInvoice(invoice.text);
        await cubit.submitShown(PayoutKind.lightning);
        final stale = await statuses.read(
          await statuses.bondStep(),
          orderJson(6),
          after: const Duration(minutes: 2),
        );
        // Sent after the read after the payout (at 7), but before the outcome came back: still not after it.
        cubit.show(
          TradeSeen(
            stale.status,
            order: stale.order,
            stored: true,
            requestedAt: seven.status.seenAt.add(
              const Duration(milliseconds: 500),
            ),
          ),
        );
        expect(cubit.state.submittable(PayoutKind.lightning), isNull);
      },
    );

    testWidgets(
      'a payout received at 8, the read after it at 9: said, not « does not ask »',
      (tester) async {
        final eight = await statuses.waitingForPayout();
        final nine = await statuses.chatting();
        final sender = _Sender()
          ..answer = (shown) => Ok(PayoutGiven(record, nine));
        final cubit = cubitOf(sender);
        await show(tester, cubit, eight);
        await tester.enterText(
          find.byKey(PayoutPanel.invoiceField),
          invoice.text,
        );
        await tester.pump();
        await reveal(tester, submitButton());
        await tester.tap(submitButton());
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(
          find.text('Temple of Sats received your payout info.'),
          findsOneWidget,
        );
        expect(
          find.text('Temple of Sats does not ask for your payout info now.'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'the on-chain figures shown are the check\'s own, whatever the field says',
      (tester) async {
        // A checker that checks at 4 sat/vB whatever the field: the figures follow it, and « Submit » stays off since it is not what the field shows.
        final cubit = PayoutCubit(
          record,
          PayoutAsk.of,
          (record, seen, destination) => switch (destination) {
            PayoutAddressText(:final text) => check(
              record,
              seen,
              PayoutAddressText(
                text,
                rate: MiningFeeRate.of(4) ?? (throw StateError('4')),
              ),
            ),
            _ => check(record, seen, destination),
          },
          _Sender().call,
          _Holds().call,
          now: clock,
        );
        addTearDown(cubit.close);
        await show(tester, cubit, sixSwap);
        await tester.tap(find.text('Onchain'));
        await tester.pump();
        await tester.enterText(
          find.byKey(PayoutPanel.addressField),
          mainnetAddress,
        );
        await tester.pump();
        expect(_fieldText(tester, PayoutPanel.feeField), '3.5');
        // `int(4 × 280)`.
        expect(find.text('1,120 Sats (4 Sats/vByte)'), findsOneWidget);
        expect(find.text('980 Sats (3.5 Sats/vByte)'), findsNothing);
        expect(enabled(tester, submitButton()), isFalse);
      },
    );

    testWidgets('the panel prints nothing: no invoice, no address', (
      tester,
    ) async {
      final printed = <String>[];
      final debugPrintBefore = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add('$message');
      final sender = _Sender()
        ..answer = (shown) => Ok(PayoutGiven(record, seven));
      final cubit = cubitOf(sender);
      await show(tester, cubit, sixSwap);
      await tester.enterText(
        find.byKey(PayoutPanel.invoiceField),
        invoice.text,
      );
      await tester.pump();
      await reveal(tester, submitButton());
      await tester.tap(submitButton());
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      await tester.tap(find.text('Onchain'));
      await tester.pump();
      await tester.enterText(
        find.byKey(PayoutPanel.addressField),
        mainnetAddress,
      );
      await tester.pump();
      debugPrint = debugPrintBefore;
      final all = printed.join('\n');
      expect(all.contains(invoice.text.substring(0, 30)), isFalse);
      expect(all.contains(mainnetAddress), isFalse);
    });
  });
}

/// The payout « sent »: records what it was given, tells each step, waits for [gate], and answers [answer].
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
    await Future<void>.microtask(() {});
    onProgress?.call(PayoutProgress.readingOrder);
    await Future<void>.microtask(() {});
    onProgress?.call(PayoutProgress.sending);
    if (gate case final gate?) await gate;
    onProgress?.call(PayoutProgress.readingAfter);
    final answer = this.answer;
    if (answer == null) throw StateError('no answer scripted');
    return answer(shown);
  }
}

/// The key's holds: counted.
final class _Holds {
  int held = 0;
  int released = 0;

  void Function() call(TradeRecord record) {
    held++;
    return () => released++;
  }
}

/// The spoken name of the amount's copy.
String _copyTooltip(Locale locale) =>
    locale.languageCode == 'fr' ? 'Copier le montant' : 'Copy the amount';

/// The text of the field of [key].
String _fieldText(WidgetTester tester, Key key) =>
    tester.widget<TextField>(find.byKey(key)).controller?.text ?? '';

/// Every paragraph on the screen laid out without being cut, and no overflow.
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

/// « Submit » as the panel's button gives it: the payout the tab offers now.
extension on PayoutCubit {
  Future<void> submitShown(PayoutKind kind) =>
      submit(kind, shown: state.submittable(kind));
}
