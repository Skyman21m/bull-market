import 'dart:async';

import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// A successful end opened again (#95): the watch reads the order once, as the reference reads it whenever its page opens, to show the coordinator's summary, the payment's lines and the rating; nothing is written, the record is not touched, no other read follows, and a read that gives nothing leaves the end as it was, marked not read again, which the screen says (#216); over the coordinator the tests play (never a real coordinator).
void main() {
  const read = ScriptedRequest.order;

  /// The summaries the coordinator adds at 14, for its taker, the buyer.
  const summary = <String, Object?>{
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
      'payment_hash':
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      'preimage': 'processing',
      'trade_fee_sats': 288,
    },
    'platform_summary': {
      'contract_exchange_rate': 60849.5,
      'contract_timestamp': '2026-11-13T08:03:00Z',
      'contract_total_time': 1234.5,
      'routing_budget_sats': 0.0,
      'trade_revenue_sats': 576,
    },
  };

  int readsOf(TradeHarness app) =>
      app.coordinator.received.where((kind) => kind == read).length;

  /// A trade taken, its bond locked, then finished (14) on a first run whose watch closed its record; the app started again.
  Future<(TradeHarness, TradeRecord)> finishedThenRestarted() async {
    final first = await TradeHarness.start();
    final taken = await first.takeShown();
    expect(
      taken,
      isA<Ok<TakeOutcome, TakeRefusal>>().having(
        (ok) => ok.value,
        'outcome',
        isA<TakeStarted>(),
      ),
    );
    final run = first.watchOf(TradeHarness.recordOf(taken));
    await first.settle();
    first.coordinator.lockBond(first.robot(0));
    first.coordinator
      ..tradeSummary = summary
      ..moveTo(14);
    await first.elapse(const Duration(seconds: 5));
    final ended = run.lastStatus;
    await run.subscription.cancel();
    expect(ended.seen.status, isA<Succeeded>());
    expect(ended.record.closedAt, isNotNull);
    final again = first.restart();
    again.coordinator.requests.clear();
    return (again, ended.record);
  }

  test(
    'reopened: one read, the summary shown, nothing written, the record untouched, no other read',
    () async {
      final (app, record) = await finishedThenRestarted();
      final storesBefore = app.trails.stores;
      final signals = StreamController<TradeWatchSignal>();
      addTearDown(signals.close);
      // The read held on its way: the screen asks for a read meanwhile, which sends nothing.
      final held = Completer<void>();
      app.coordinator.hold = held.future;
      final run = app.watchOf(record, signals: signals.stream);
      await app.settle();
      expect(readsOf(app), 1);
      signals.add(TradeWatchSignal.readNow);
      await app.settle();
      app.coordinator.hold = null;
      held.complete();
      await app.settle();
      // The end from the records first, then what the read shows.
      expect(
        (run.states.first as TradeWatchStatus).seen.status,
        isA<StatusUnknown>(),
      );
      final shown = run.lastStatus;
      final status = shown.seen.status;
      expect(status, isA<Succeeded>());
      final own = (status as Succeeded).summary?.own;
      expect(own?.receivedSats?.value.toInt(), 164126);
      expect(shown.seen.order?.id, record.orderId);
      expect(shown.seen.stored, isFalse);
      expect(shown.endReread, isNull);
      expect(readsOf(app), 1);
      expect(app.trails.stores, storesBefore);
      expect(shown.record.closedAt, record.closedAt);
      expect(shown.record.confirmedAt, record.confirmedAt);
      expect(run.done, isTrue);
      // The screen asking, and time passing: no other read.
      if (!signals.isClosed) signals.add(TradeWatchSignal.readNow);
      await app.elapse(const Duration(minutes: 30));
      expect(readsOf(app), 1);
      expect(app.activeTimers, isEmpty);
    },
  );

  test(
    'the coordinator answers that it does not know the order: the end stays, marked so, never « not read » (#216, functional review of #220, C1)',
    () async {
      final (app, record) = await finishedThenRestarted();
      app.coordinator.orderForgotten = true;
      final run = app.watchOf(record);
      await app.settle();
      expect(run.states, hasLength(2));
      expect(run.lastStatus.seen.status, isA<StatusUnknown>());
      expect(run.lastStatus.endReread, isA<TradeEndUnknownToCoordinator>());
      expect(run.lastStatus.failedReads, 0);
      expect(readsOf(app), 1);
      expect(run.done, isTrue);
    },
  );

  test(
    'the read fails: the end stays, marked not read (#216), no retry',
    () async {
      final (app, record) = await finishedThenRestarted();
      app.coordinator.failNext(read, ScriptedFault.unreachable);
      final run = app.watchOf(record);
      await app.settle();
      await app.elapse(const Duration(minutes: 30));
      expect(run.states, hasLength(2));
      expect(run.lastStatus.seen.status, isA<StatusUnknown>());
      expect(run.lastStatus.endReread, isA<TradeEndNotRead>());
      expect(readsOf(app), 1);
    },
  );

  test(
    'an order read no longer at its successful end is not taken: the end stays, marked shown otherwise, never « not read » (#216, functional review of #220, C1)',
    () async {
      final (app, record) = await finishedThenRestarted();
      app.coordinator.moveTo(13);
      final run = app.watchOf(record);
      await app.settle();
      expect(run.states, hasLength(2));
      expect(run.lastStatus.seen.status, isA<StatusUnknown>());
      expect(run.lastStatus.endReread, isA<TradeEndShownOtherwise>());
      expect(readsOf(app), 1);
    },
  );

  test('another end than a success is not read', () async {
    final first = await TradeHarness.start();
    final taken = await first.takeShown();
    final run = first.watchOf(TradeHarness.recordOf(taken));
    await first.settle();
    first.coordinator.lockBond(first.robot(0));
    first.coordinator.moveTo(9);
    await first.elapse(const Duration(seconds: 5));
    first.coordinator.moveTo(12);
    await first.elapse(const Duration(minutes: 5));
    final ended = run.lastStatus;
    await run.subscription.cancel();
    expect(ended.seen.status.isTerminal, isTrue);
    final again = first.restart();
    again.coordinator.requests.clear();
    final reopened = again.watchOf(ended.record);
    await again.settle();
    expect(readsOf(again), 0);
    expect(reopened.done, isTrue);
  });
}
