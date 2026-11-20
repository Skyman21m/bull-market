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
    'a premium shown otherwise at 9, then put back: the trail keeps which and when to the end, after a restart too, whatever comes later',
    () async {
      final harness = await MakeHarness.start();
      final record = await atChat(harness);
      final changes = harness.coordinator.orderChanges;
      await harness.elapse(const Duration(minutes: 3));
      final shownAt = harness.now;
      changes[record.orderId] = {'premium': '7.00'};
      final changed = await read(harness, record);
      expect(changed.status, isA<Chatting>());
      expect(changed.status.has<TradeTermsChanged>(), isTrue);
      expect(changed.status.trail.termsChangedAt, shownAt);
      expect(changed.status.trail.termsChangedPremium, 7);

      // Put back: the state machine's alert goes, the trace stays.
      await harness.elapse(const Duration(minutes: 3));
      changes.remove(record.orderId);
      final back = await read(harness, record);
      expect(back.status.has<TradeTermsChanged>(), isFalse);
      expect(back.status.trail.termsChangedAt, shownAt);
      expect(back.status.trail.termsChangedPremium, 7);

      // Another premium later: the first trace stays as it was.
      await harness.elapse(const Duration(minutes: 3));
      changes[record.orderId] = {'premium': '9.00'};
      final again = await read(harness, record);
      expect(again.status.has<TradeTermsChanged>(), isTrue);
      expect(again.status.trail.termsChangedAt, shownAt);
      expect(again.status.trail.termsChangedPremium, 7);
      changes.remove(record.orderId);
      await read(harness, record);

      // The app started again: the trace is read back from the records.
      final reopened = switch (await harness.restart().reader.open(record)) {
        TradeOpened(:final trade) => trade.seen,
        final other => throw StateError('$other'),
      };
      expect(reopened.status.trail.termsChangedAt, shownAt);
      expect(reopened.status.trail.termsChangedPremium, 7);
    },
  );

  test(
    'another term shown otherwise (the payment method): the time, no premium',
    () async {
      final harness = await MakeHarness.start();
      final record = await atChat(harness);
      final changes = harness.coordinator.orderChanges;
      changes[record.orderId] = {'payment_method': 'Cash'};
      final changed = await read(harness, record);
      expect(changed.status.has<TradeTermsChanged>(), isTrue);
      expect(changed.status.trail.termsChangedAt, harness.now);
      expect(changed.status.trail.termsChangedPremium, isNull);
      changes.remove(record.orderId);
      final back = await read(harness, record);
      expect(back.status.has<TradeTermsChanged>(), isFalse);
      expect(back.status.trail.termsChangedAt, isNotNull);
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
      'a trace is set with its own read\'s time only, then never changed nor cleared',
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
        expect(
          trail(
            readAt: 4000,
            at: 3000,
            premium: 7,
          ).whyNotReplace(set, madeHere: false),
          isNull,
        );
        for (final changed in [
          trail(readAt: 4000),
          trail(readAt: 4000, at: 3000),
          trail(readAt: 4000, at: 3000, premium: 8),
          trail(readAt: 4000, at: 4000, premium: 7),
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
