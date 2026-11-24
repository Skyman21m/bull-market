import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/payout_breakdown.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/ui/trade/payout_breakdown_view.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'support/harness.dart';
import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

/// The breakdown of the buyer's payout (#228), from the state machine's own statuses of a take answered as the reference answers a buyer (`test/support/trade_orders.dart`: `satoshis_now` the order's `last_satoshis`, `trade_satoshis` and `invoice_amount` the trade's sats less the taker fee, `api/views.py:324`, `:345-371`, `api/logics.py:650-669`): every line, the sums to the sat whatever the sats and the budget, and each line that is missing.
void main() {
  final record = TradeScreenStatuses.record;
  late TradeScreenStatuses statuses;
  late TradeSeen six;

  setUpAll(() async {
    statuses = await TradeScreenStatuses.make();
    six = await statuses.waitingForBoth();
  });

  PayoutAsk askOf(TradeSeen seen) => switch (PayoutAsk.of(record, seen)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  PayoutBreakdown breakdownOf(
    TradeSeen seen, {
    RoutingBudgetPpm budget = RoutingBudgetPpm.referenceDefault,
    ({Sats amount, Sats received})? wallet,
  }) =>
      PayoutBreakdown.of(askOf(seen), budget: budget, wallet: wallet) ??
      (throw StateError('no breakdown'));

  Sats sats(int value) => Sats.fromInt(value);

  test(
    'every line at 6: given, the coordinator\'s fee, the routing budget, the invoice, then the swap service\'s fee and what is received',
    () {
      // 106,900 sats fixed at the take; the taker fee of 0.175 % is 187 sats (`round(187.075)`); 1,000 ppm of 106,713 is 106.713, truncated by the coordinator to an invoice of 106,606.
      expect(six.status.warnings, isEmpty);
      final breakdown = breakdownOf(
        six,
        wallet: (amount: sats(106606), received: sats(106400)),
      );
      expect(breakdown.given, sats(106713));
      expect(breakdown.coordinatorFee, sats(187));
      expect(breakdown.routingBudget, sats(107));
      expect(breakdown.invoice, sats(106606));
      expect(breakdown.swap?.fee, sats(206));
      expect(breakdown.swap?.received, sats(106400));
      expect(breakdown.toString(), 'PayoutBreakdown');
    },
  );

  test('the same at 8, and at 15 once the failed invoice expired', () async {
    final eight = await statuses.waitingForPayout();
    expect(breakdownOf(eight), breakdownOf(six));
    final fifteen = await statuses.read(eight, orderJson(15));
    expect(breakdownOf(fifteen).invoice, sats(106606));
  });

  test(
    'the sums fall to the sat for every sats fixed at the take and every budget, with the reference\'s own roundings',
    () async {
      final bond = await statuses.bondStep();
      for (var last = 104800; last <= 109000; last += 137) {
        final seen = await statuses.read(bond, orderJson(6, last: last));
        expect(seen.status.warnings, isEmpty, reason: '$last');
        for (final ppm in const [0, 1, 999, 1000, 5000, 10000, 33333, 99998]) {
          final budget = RoutingBudgetPpm.of(ppm) ?? fail('$ppm');
          final given = payoutOf(last);
          // The invoice as the reference computes it: `Math.floor(trade − trade × ppm / 10⁶)` (`Forms/LightningPayout.tsx:110-113`), `int(…)` at the coordinator (`api/logics.py:869-872`).
          final invoice = (given - given * (ppm / 1000000)).floor();
          final received = invoice - 1 - (last % 300);
          final breakdown = breakdownOf(
            seen,
            budget: budget,
            wallet: (amount: sats(invoice), received: sats(received)),
          );
          final fee = breakdown.coordinatorFee ?? fail('no fee');
          final routing = breakdown.routingBudget ?? fail('no budget');
          final swap = breakdown.swap ?? fail('no swap');
          expect(breakdown.given, sats(given), reason: '$last $ppm');
          expect(breakdown.invoice, sats(invoice), reason: '$last $ppm');
          expect(breakdown.given.value + fee.value, BigInt.from(last));
          expect(fee, sats(feeOf(last)), reason: '$last');
          expect(
            breakdown.given.value - routing.value,
            breakdown.invoice?.value,
          );
          expect(swap.received.value + swap.fee.value, BigInt.from(invoice));
          expect(swap.received, sats(received));
        }
      }
    },
  );

  test(
    'a half of a sat in the fee: the coordinator\'s own rounding, never another, in the line',
    () async {
      // 106,000 × 0.175 % is 185.5: the figures the coordinator gives decide, the line is their difference.
      final seen = await statuses.read(
        await statuses.bondStep(),
        orderJson(6, last: 106000),
      );
      expect(seen.status.warnings, isEmpty);
      final breakdown = breakdownOf(seen);
      final given = seen.order?.tradeSatoshis ?? fail('no trade_satoshis');
      expect(breakdown.given, given);
      expect(
        breakdown.coordinatorFee?.value,
        BigInt.from(106000) - given.value,
      );
    },
  );

  group('a line missing', () {
    test(
      'no invoice made by this wallet: the lines stop at « Your invoice »',
      () {
        final breakdown = breakdownOf(six);
        expect(breakdown.invoice, sats(106606));
        expect(breakdown.swap, isNull);
      },
    );

    test(
      'an invoice of this wallet for another amount (the budget changed since): no swap lines, never figures of another invoice',
      () {
        final breakdown = breakdownOf(
          six,
          budget: RoutingBudgetPpm.of(0) ?? fail('0'),
          wallet: (amount: sats(106606), received: sats(106400)),
        );
        expect(breakdown.invoice, sats(106713));
        expect(breakdown.routingBudget, sats(0));
        expect(breakdown.swap, isNull);
      },
    );

    test('figures of a wallet that do not hold together: no swap lines', () {
      for (final received in [0, 106607]) {
        expect(
          breakdownOf(
            six,
            wallet: (amount: sats(106606), received: sats(received)),
          ).swap,
          isNull,
          reason: '$received',
        );
      }
    });
  });

  group('amounts that do not agree: no breakdown at all, the alert alone', () {
    Future<void> none(
      Map<String, Object?> changes,
      bool Function(TradeWarning) raised,
    ) async {
      final seen = await statuses.read(
        await statuses.bondStep(),
        orderJson(6, changes: changes),
      );
      expect(seen.status.warnings.any(raised), isTrue);
      expect(PayoutBreakdown.amountsDisagree(seen.status), isTrue);
      final ask = askOf(seen);
      expect(
        PayoutBreakdown.of(ask, budget: RoutingBudgetPpm.referenceDefault),
        isNull,
      );
    }

    test(
      'the payout\'s amount other than the trade\'s',
      () => none({
        'invoice_amount': 100000,
      }, (warning) => warning is PayoutAmountMismatch),
    );

    test(
      'a fee above the one announced (the coordinator gives less than the trade less its fee)',
      () => none({
        'trade_satoshis': 100000,
        'invoice_amount': 100000,
      }, (warning) => warning is TakerFeeAboveAnnounced),
    );

    test(
      'a fee below zero (more given than the trade\'s sats)',
      () => none({
        'trade_satoshis': 107000,
        'invoice_amount': 107000,
      }, (warning) => warning is TakerFeeAboveAnnounced),
    );

    test(
      'no `satoshis_now`: no fee can be said, and the price\'s warning',
      () => none({
        'satoshis_now': null,
      }, (warning) => warning is TradePriceOutsideOrder),
    );
  });

  test(
    'the lean figures (#250): the fees and what is received are the sats paid less one another, to the sat, with or without this wallet\'s invoice',
    () {
      final made = breakdownOf(
        six,
        wallet: (amount: sats(106606), received: sats(106400)),
      );
      expect(made.fees, sats(313));
      expect(made.received, sats(106400));
      expect(
        made.given.value - (made.fees?.value ?? BigInt.zero),
        made.received?.value,
      );
      expect(
        made.fees?.value,
        (made.routingBudget?.value ?? BigInt.zero) +
            (made.swap?.fee.value ?? BigInt.zero),
      );
      final pasted = breakdownOf(six);
      expect(pasted.fees, sats(107));
      expect(pasted.received, sats(106606));
    },
  );

  group('the check drawn (#250)', () {
    PayoutCheck compared(int given, {bool warns = false}) =>
        PayoutCheckCompared(
          given: Sats.fromInt(given),
          expected: Sats.fromInt(107000),
          price: '100 EUR at 91,711 EUR/BTC, premium included',
          gap: warns ? '-15.83%' : '-0.27%',
          warns: warns,
          threshold: '10%',
        );

    Future<void> draw(
      WidgetTester tester,
      PayoutCheck? check, {
      bool detail = false,
    }) => tester.pumpWidget(
      harness(
        SingleChildScrollView(
          child: Column(
            children: [
              PayoutBreakdownView(
                breakdown: breakdownOf(six),
                check: PayoutBreakdownView.drawnOf(breakdownOf(six), check),
              ),
              if (detail)
                PayoutBreakdownDetail(
                  breakdown: breakdownOf(six),
                  check: PayoutBreakdownView.drawnOf(breakdownOf(six), check),
                ),
            ],
          ),
        ),
      ),
    );

    testWidgets(
      'for the very sats paid: the gap line, and in the detail what Bull Wallet expected; for other sats (a figure that changed since the rule compared): neither, never a comparison of another figure',
      (tester) async {
        await draw(tester, compared(106713), detail: true);
        expect(find.byKey(PayoutCheckLines.gapRow), findsOneWidget);
        expect(find.text('Gap to the Bull price (indicative)'), findsOneWidget);
        expect(find.text('-0.27%'), findsOneWidget);
        expect(find.byKey(PayoutBreakdownDetail.valueRow), findsOneWidget);
        expect(
          find.text(
            'A small gap is normal: the coordinator has its own price source.',
          ),
          findsOneWidget,
        );
        await draw(tester, compared(106714), detail: true);
        expect(find.byKey(PayoutCheckLines.gapRow), findsNothing);
        expect(find.byKey(PayoutBreakdownDetail.valueRow), findsNothing);
        expect(find.byKey(PayoutBreakdownDetail.explanation), findsNothing);
        expect(find.byKey(PayoutBreakdownView.givenRow), findsOneWidget);
        await draw(tester, null, detail: true);
        expect(find.byKey(PayoutBreakdownDetail.valueRow), findsNothing);
        expect(find.text('Paid by the coordinator'), findsOneWidget);
        expect(find.text('Routing fees'), findsOneWidget);
        expect(find.text('You will receive'), findsOneWidget);
        expect(find.text('Your invoice'), findsOneWidget);
      },
    );

    testWidgets(
      'the red alert: its bold line in the gap\'s place, without « (indicative) », the two figures under it each named by whom it comes from, the figure paid in red; never « A small gap is normal » beside it',
      (tester) async {
        await draw(tester, compared(106713, warns: true), detail: true);
        expect(find.byKey(PayoutCheckLines.gapRow), findsNothing);
        expect(find.textContaining('(indicative)'), findsNothing);
        expect(find.text('Gap against you'), findsOneWidget);
        expect(find.text('-15.83%'), findsOneWidget);
        expect(
          find.text(
            'Bull Wallet expected 107,000 sats, the coordinator pays 106,713.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('A small gap is normal'), findsNothing);
        expect(
          find.text(
            'Bull Wallet redoes the calculation with its own price, premium included, and warns you beyond a 10% gap. Check the order before going on.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('a narrow phone with a large text: nothing cut', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 2400) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final breakdown = breakdownOf(
        six,
        wallet: (amount: sats(106606), received: sats(106400)),
      );
      for (final check in [
        compared(106713, warns: true),
        compared(106713),
        PayoutCheckUnverified(Sats.fromInt(106713)),
        PayoutCheckNotPriced(Sats.fromInt(106713)),
      ]) {
        for (final scale in const [1.0, 2.0, 3.0]) {
          await tester.pumpWidget(
            harness(
              MediaQuery(
                data: MediaQueryData(
                  size: const Size(320, 2400),
                  textScaler: TextScaler.linear(scale),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      PayoutBreakdownView(
                        breakdown: breakdown,
                        check: check,
                        onRetry: () {},
                      ),
                      PayoutDetailToggle(open: true, onPressed: () {}),
                      PayoutBreakdownDetail(
                        breakdown: breakdown,
                        check: check,
                        onCopy: () {},
                      ),
                    ],
                  ),
                ),
              ),
              locale: const Locale('fr'),
            ),
          );
          expect(tester.takeException(), isNull, reason: '$check $scale');
        }
      }
    });
  });
}
