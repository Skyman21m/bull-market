import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/src/presentation/trade_panel.dart';
import 'package:p2p/testing.dart' show Bolt11TestInvoice;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';

/// The trace a coordinator leaves by showing a trade with other terms, then putting them back (schema 9, #231; design note `docs/design/phase-3-making-an-order.md` § 3.5 bis): set by the state machine in the write of the read that first showed it, kept by the trail to the end, after a restart too, never changed by a later change; and the rule `TradeTrailRecord.whyNotReplace` and `TradeTrail.restore` keep, as the trigger `trade_trails_terms_trace` does. The coordinator is `ScriptedMakerCoordinator` (never a real one), its order's premium changed by the test as a coordinator that lies would.
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

  /// A maker seller's order made, its bond locked elsewhere, taken: at 6, its collateral asked.
  Future<TradeRecord> sellerAtSix(MakeHarness harness) async {
    final made = valueOf(
      await harness.makeOrder(MakeHarness.request(sell: true)),
    );
    final record = (made as MakeStarted).record;
    await read(harness, record);
    harness.coordinator.lockMakerBond(record.orderId);
    await read(harness, record);
    harness.coordinator.take(record.orderId, harness.robot(4));
    final seen = await read(harness, record);
    expect(seen.status, isA<WaitingForBoth>());
    return record;
  }

  /// Shows [premium] (or the order's own again when `null`) to [record] three minutes later, and reads it.
  Future<TradeSeen> show(
    MakeHarness harness,
    TradeRecord record,
    String? premium,
  ) async {
    await harness.elapse(const Duration(minutes: 3));
    final changes = harness.coordinator.orderChanges;
    if (premium == null) {
      changes.remove(record.orderId);
    } else {
      changes[record.orderId] = {'premium': premium};
    }
    return read(harness, record);
  }

  for (final (side, start) in [
    ('maker buyer at 9', atChat),
    ('maker seller at 6', sellerAtSix),
  ]) {
    test(
      '$side: -10 then +7 for the order\'s +2, each put back: both kept, the first time, a premium in between moves nothing, after a restart too (security verification of schema 9, R8)',
      () async {
        final harness = await MakeHarness.start();
        final record = await start(harness);
        final below = await show(harness, record, '-10.00');
        final shownAt = harness.now;
        expect(below.status.has<TradeTermsChanged>(), isTrue);
        expect(below.status.trail.termsChangedAt, shownAt);
        expect(below.status.trail.termsChangedPremiumLow, -10);
        expect(below.status.trail.termsChangedPremiumHigh, -10);
        await show(harness, record, null);
        final above = await show(harness, record, '7.00');
        expect(above.status.trail.termsChangedPremiumLow, -10);
        expect(above.status.trail.termsChangedPremiumHigh, 7);
        await show(harness, record, null);
        final between = await show(harness, record, '1.00');
        expect(between.status.has<TradeTermsChanged>(), isTrue);
        expect(between.status.trail.termsChangedPremiumLow, -10);
        expect(between.status.trail.termsChangedPremiumHigh, 7);
        final back = await show(harness, record, null);
        expect(back.status.has<TradeTermsChanged>(), isFalse);
        expect(back.status.trail.termsChangedAt, shownAt);
        final reopened = switch (await harness.restart().reader.open(record)) {
          TradeOpened(:final trade) => trade.seen,
          final other => throw StateError('$other'),
        };
        expect(reopened.status.trail.termsChangedAt, shownAt);
        expect(reopened.status.trail.termsChangedPremiumLow, -10);
        expect(reopened.status.trail.termsChangedPremiumHigh, 7);
        expect(reopened.ownPremium?.percent, 2);
      },
    );
  }

  test(
    '+7 then -3, each put back: both kept, whichever is farther (security verification of schema 9, R8)',
    () async {
      final harness = await MakeHarness.start();
      final record = await atChat(harness);
      await show(harness, record, '7.00');
      await show(harness, record, null);
      await show(harness, record, '-3.00');
      final back = await show(harness, record, null);
      expect(back.status.trail.termsChangedPremiumLow, -3);
      expect(back.status.trail.termsChangedPremiumHigh, 7);
    },
  );

  test(
    'another term shown otherwise first (the payment method), then a premium: the time of the first, the premium written then (security review of schema 9, C1)',
    () async {
      final harness = await MakeHarness.start();
      final record = await atChat(harness);
      final changes = harness.coordinator.orderChanges;
      changes[record.orderId] = {'payment_method': 'Cash'};
      final changed = await read(harness, record);
      final shownAt = harness.now;
      expect(changed.status.has<TradeTermsChanged>(), isTrue);
      expect(changed.status.trail.termsChangedAt, shownAt);
      expect(changed.status.trail.termsChangedPremiumLow, isNull);
      expect(changed.status.trail.termsChangedPremiumHigh, isNull);
      changes.remove(record.orderId);
      await read(harness, record);
      await show(harness, record, '99.00');
      final after = await show(harness, record, null);
      expect(after.status.trail.termsChangedAt, shownAt);
      expect(after.status.trail.termsChangedPremiumLow, 99);
      expect(after.status.trail.termsChangedPremiumHigh, 99);
    },
  );

  group('the record\'s rule, as the trigger says it', () {
    TradeTrailRecord trail({
      int readAt = 2000,
      int? at,
      double? low,
      double? high,
    }) => TradeTrailRecord(
      version: TradeTrailRecord.currentVersion,
      network: 'testnet',
      coordinatorAlias: 'temple',
      orderId: 7,
      role: 'buyer',
      position: 'chatting',
      readAtMicros: readAt,
      bondHash: null,
      escrowHash: null,
      deadlineMicros: null,
      bondStepSeenAtMicros: null,
      bondStepDeadlineMicros: null,
      breached: false,
      historyUnknown: false,
      termsChangedAtMicros: at,
      termsChangedPremiumLow: low,
      termsChangedPremiumHigh: high,
    );

    test(
      'a trace\'s time is set with its own read\'s only, then never changed; its lowest premium only goes down, its highest only up, neither cleared',
      () {
        final none = trail();
        expect(
          trail(
            readAt: 3000,
            at: 3000,
            low: 7,
            high: 7,
          ).whyNotReplace(none, madeHere: false),
          isNull,
        );
        expect(
          trail(readAt: 3000, at: 3000).whyNotReplace(none, madeHere: false),
          isNull,
        );
        expect(
          trail(readAt: 3000, at: 2500).whyNotReplace(none, madeHere: false),
          TrailReplacementRefusal.termsTraceChanged,
        );
        final set = trail(readAt: 3000, at: 3000, low: -3, high: 7);
        for (final widened in [
          trail(readAt: 4000, at: 3000, low: -3, high: 7),
          trail(readAt: 4000, at: 3000, low: -10, high: 7),
          trail(readAt: 4000, at: 3000, low: -3, high: 99),
          trail(readAt: 4000, at: 3000, low: -10, high: 99),
        ]) {
          expect(widened.whyNotReplace(set, madeHere: false), isNull);
        }
        // A premium added after another term changed first.
        expect(
          trail(
            readAt: 4000,
            at: 3000,
            low: 7,
            high: 7,
          ).whyNotReplace(trail(readAt: 3000, at: 3000), madeHere: false),
          isNull,
        );
        for (final changed in [
          trail(readAt: 4000),
          trail(readAt: 4000, at: 3000),
          trail(readAt: 4000, at: 3000, low: -2, high: 7),
          trail(readAt: 4000, at: 3000, low: -3, high: 6),
          trail(readAt: 4000, at: 4000, low: -3, high: 7),
        ]) {
          expect(
            changed.whyNotReplace(set, madeHere: false),
            TrailReplacementRefusal.termsTraceChanged,
          );
        }
      },
    );
  });
}
