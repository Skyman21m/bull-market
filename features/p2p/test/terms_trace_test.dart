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

  test(
    'premiums shown otherwise at 9, each then put back: the trail keeps the first time and the premium farthest from the order\'s, above or below, never a closer one, after a restart too (security review of schema 9, C1)',
    () async {
      final harness = await MakeHarness.start();
      final record = await atChat(harness);
      final changes = harness.coordinator.orderChanges;
      Future<TradeSeen> show(String? premium) async {
        await harness.elapse(const Duration(minutes: 3));
        if (premium == null) {
          changes.remove(record.orderId);
        } else {
          changes[record.orderId] = {'premium': premium};
        }
        return read(harness, record);
      }

      // First a premium barely beyond the tolerance (2.01 for the order's 2): the time set, the premium kept.
      final first = await show('2.01');
      final shownAt = harness.now;
      expect(first.status.has<TradeTermsChanged>(), isTrue);
      expect(first.status.trail.termsChangedAt, shownAt);
      expect(first.status.trail.termsChangedPremium, 2.01);
      await show(null);
      // Then 99: farther, it replaces the first, the time stays.
      final far = await show('99.00');
      expect(far.status.trail.termsChangedPremium, 99);
      final back = await show(null);
      expect(back.status.has<TradeTermsChanged>(), isFalse);
      expect(back.status.trail.termsChangedAt, shownAt);
      expect(back.status.trail.termsChangedPremium, 99);
      // A closer premium later never replaces it.
      final closer = await show('50.00');
      expect(closer.status.has<TradeTermsChanged>(), isTrue);
      expect(closer.status.trail.termsChangedPremium, 99);
      await show(null);
      // Below the order's, farther still (-97 is 99 points away, 99 was 97): it replaces it.
      final below = await show('-97.00');
      expect(below.status.trail.termsChangedPremium, -97);
      final end = await show(null);
      expect(end.status.trail.termsChangedAt, shownAt);
      expect(end.status.trail.termsChangedPremium, -97);
      // The app started again: the trace is read back from the records.
      final reopened = switch (await harness.restart().reader.open(record)) {
        TradeOpened(:final trade) => trade.seen,
        final other => throw StateError('$other'),
      };
      expect(reopened.status.trail.termsChangedAt, shownAt);
      expect(reopened.status.trail.termsChangedPremium, -97);
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
      expect(changed.status.trail.termsChangedPremium, isNull);
      changes.remove(record.orderId);
      final back = await read(harness, record);
      expect(back.status.has<TradeTermsChanged>(), isFalse);
      expect(back.status.trail.termsChangedAt, shownAt);
      await harness.elapse(const Duration(minutes: 3));
      changes[record.orderId] = {'premium': '99.00'};
      await read(harness, record);
      changes.remove(record.orderId);
      final after = await read(harness, record);
      expect(after.status.trail.termsChangedAt, shownAt);
      expect(after.status.trail.termsChangedPremium, 99);
      final reopened = switch (await harness.restart().reader.open(record)) {
        TradeOpened(:final trade) => trade.seen,
        final other => throw StateError('$other'),
      };
      expect(reopened.status.trail.termsChangedPremium, 99);
      expect(reopened.ownPremium?.percent, 2);
    },
  );

  group('the record\'s rule, as the trigger says it', () {
    TradeTrailRecord trail({int readAt = 2000, int? at, double? premium}) =>
        TradeTrailRecord(
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
          termsChangedPremium: premium,
        );

    test(
      'a trace\'s time is set with its own read\'s only, then never changed; its premium only moves farther from the order\'s, never cleared',
      () {
        final none = trail();
        expect(
          trail(
            readAt: 3000,
            at: 3000,
            premium: 7,
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
        final set = trail(readAt: 3000, at: 3000, premium: 7);
        // The order's own premium is 2: 8 is farther than 7, 6 closer.
        expect(
          trail(
            readAt: 4000,
            at: 3000,
            premium: 7,
          ).whyNotReplace(set, madeHere: false, ownPremium: 2),
          isNull,
        );
        expect(
          trail(
            readAt: 4000,
            at: 3000,
            premium: 8,
          ).whyNotReplace(set, madeHere: false, ownPremium: 2),
          isNull,
        );
        expect(
          trail(
            readAt: 4000,
            at: 3000,
            premium: -4,
          ).whyNotReplace(set, madeHere: false, ownPremium: 2),
          isNull,
        );
        // A premium added after another term changed first.
        expect(
          trail(
            readAt: 4000,
            at: 3000,
            premium: 7,
          ).whyNotReplace(
            trail(readAt: 3000, at: 3000),
            madeHere: false,
            ownPremium: 2,
          ),
          isNull,
        );
        for (final changed in [
          trail(readAt: 4000),
          trail(readAt: 4000, at: 3000),
          trail(readAt: 4000, at: 3000, premium: 6),
          trail(readAt: 4000, at: 3000, premium: -3),
          trail(readAt: 4000, at: 4000, premium: 7),
        ]) {
          expect(
            changed.whyNotReplace(set, madeHere: false, ownPremium: 2),
            TrailReplacementRefusal.termsTraceChanged,
          );
        }
        // Without the order's own premium, no premium moves.
        expect(
          trail(
            readAt: 4000,
            at: 3000,
            premium: 8,
          ).whyNotReplace(set, madeHere: false),
          TrailReplacementRefusal.termsTraceChanged,
        );
      },
    );
  });
}
