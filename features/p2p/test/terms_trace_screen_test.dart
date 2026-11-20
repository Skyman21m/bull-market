import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/presentation/trade_panel.dart';
import 'package:p2p/testing.dart' show Bolt11TestInvoice;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/src/domain/trade/payout_trace.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart'
    show payoutTraceOf, termsShownOtherwise;

import 'support/harness.dart';
import 'support/make_harness.dart';

/// The line of the trace of terms shown otherwise (#231) says it while the trade lasts and no longer once it ended: an end is no step to act on, as the note's § 3.5 bis says (functional review of schema 9, C5, m19). The coordinator is `ScriptedMakerCoordinator` (never a real one).
void main() {
  T valueOf<T, F extends Failure>(Result<T, F> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  Future<TradeSeen> read(MakeHarness harness, TradeRecord record) async {
    final run = harness.watchOf(record);
    await harness.settle();
    final watch = run.lastStatus;
    await run.subscription.cancel();
    final view = TradeView.of(watch);
    if (view is! TradeContract) throw StateError('$view');
    return watch.seen;
  }

  /// A maker buyer's order made, taken, its payout given and the escrow locked: at 9, « Confirm … sent ».
  Future<TradeRecord> atChat(MakeHarness harness) async {
    final made = valueOf(await harness.makeOrder());
    final record = (made as MakeStarted).record;
    await read(harness, record);
    harness.coordinator.lockMakerBond(record.orderId);
    await read(harness, record);
    harness.coordinator.take(record.orderId, harness.robot(4));
    final seen = await read(harness, record);
    final ask = valueOf(harness.payout.ask(record, seen));
    final amount =
        ask.invoiceSatsFor(RoutingBudgetPpm.referenceDefault) ??
        (throw StateError('no amount'));
    final invoice = Bolt11TestInvoice(
      network: Bolt11Network.testnet,
      sats: amount.value.toInt(),
      seed: 31,
      createdAt: harness.now,
      expiry: const Duration(hours: 24),
      description: 'payout',
    );
    harness.coordinator.decoder.add(invoice);
    final checked = valueOf(
      harness.payout.check(
        record,
        seen,
        PayoutInvoiceText(
          invoice.text,
          budget: RoutingBudgetPpm.referenceDefault,
        ),
      ),
    );
    valueOf(await harness.payout.execute(record, checked));
    harness.coordinator.lockEscrow(record.orderId);
    final chat = await read(harness, record);
    expect(chat.status, isA<Chatting>());
    expect(chat.status.trail.termsChangedAt, isNull);
    return record;
  }

  testWidgets(
    'the trace of a premium shown otherwise is said at « Confirm … sent », from the terms kept here, not while the read shows other terms, and no longer once the trade ended; a payout\'s trace not read or unreadable is « unknown » (security review of schema 9, R1, R6, R7)',
    (tester) async {
      late TradeSeen chat;
      late TradeSeen changed;
      late TradeSeen end;
      await tester.runAsync(() async {
        final harness = await MakeHarness.start();
        final record = await atChat(harness);
        final changes = harness.coordinator.orderChanges;
        changes[record.orderId] = {'premium': '7.00'};
        changed = await read(harness, record);
        changes.remove(record.orderId);
        chat = await read(harness, record);
        valueOf(await harness.chat.confirmFiatSent(record, chat));
        await read(harness, record);
        harness.coordinator.sellerConfirms(record.orderId);
        await read(harness, record);
        harness.coordinator.buyerPaid(record.orderId);
        end = await read(harness, record);
      });
      expect(chat.status, isA<Chatting>());
      expect(end.status, isA<Succeeded>());
      expect(end.status.trail.termsChangedAt, chat.status.trail.termsChangedAt);
      String? lineAtChat;
      String? lineAtEnd;
      String? lineWhileChanged;
      String? lineWithoutRead;
      final payoutLines = <String?>[];
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) {
              lineAtChat = termsShownOtherwise(
                context,
                chat.status,
                'Temple of Sats',
                own: chat.ownPremium,
              );
              lineAtEnd = termsShownOtherwise(
                context,
                end.status,
                'Temple of Sats',
                own: end.ownPremium,
              );
              lineWhileChanged = termsShownOtherwise(
                context,
                changed.status,
                'Temple of Sats',
                own: changed.ownPremium,
              );
              // A status kept from no order (after a restart, before its first read): the order's premium from its terms kept here (R1).
              final unread = TradeSeen(
                chat.status,
                order: null,
                ownPremium: chat.ownPremium,
              );
              lineWithoutRead = termsShownOtherwise(
                context,
                unread.status,
                'Temple of Sats',
                own: unread.ownPremium,
              );
              for (final trace in <PayoutTrace?>[
                null,
                const PayoutTraceUnreadable(),
                const PayoutUnrecorded(),
                PayoutFromThisWallet(PayoutTraceKind.invoice, DateTime.utc(2026)),
              ]) {
                payoutLines.add(
                  payoutTraceOf(context, chat.withPayout(trace), rule: null),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(lineAtChat, startsWith('Temple of Sats showed this trade with other terms from '));
      expect(lineAtChat, endsWith(', up to a premium of +7.0% instead of +2.0%.'));
      expect(lineAtEnd, isNull);
      // While the read shows other terms, the state machine's alert speaks alone (security review, R7).
      expect(changed.status.has<TradeTermsChanged>(), isTrue);
      expect(lineWhileChanged, isNull);
      expect(lineWithoutRead, lineAtChat);
      // Where the payout came from: a trace not read or records unreadable said as unknown, never silence (R6).
      const unknown =
          'Bull Market cannot tell whether this contract\'s payout invoice or address came from this wallet.';
      expect(payoutLines, [unknown, unknown, unknown, null]);
    },
  );
}
