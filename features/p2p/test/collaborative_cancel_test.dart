import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// The collaborative cancel of the chat step (#95): `CancelTradeUsecase` at 9, an ask or the acceptance of the peer's, always guarded with the status seen, so that an ask that lands after « fiat sent » is a refusal, never a cancel; over the coordinator the tests play (never a real coordinator).
void main() {
  const cancels = ScriptedRequest.cancel;

  int sent(TradeHarness app, ScriptedRequest kind) =>
      app.coordinator.received.where((k) => k == kind).length;

  Future<(TradeHarness, TradeRecord, TradeSeen)> at9({
    bool peerAsked = false,
  }) async {
    final app = await TradeHarness.start();
    final taken = await app.takeShown();
    expect(
      taken,
      isA<Ok<TakeOutcome, TakeRefusal>>().having(
        (ok) => ok.value,
        'outcome',
        isA<TakeStarted>(),
      ),
    );
    final record = TradeHarness.recordOf(taken);
    final run = app.watchOf(record);
    await app.settle();
    app.coordinator.lockBond(app.robot(0));
    app.coordinator.moveTo(9);
    if (peerAsked) app.coordinator.peerAsksToCancel();
    await app.elapse(const Duration(seconds: 5));
    final last = run.lastStatus;
    await run.subscription.cancel();
    expect(last.stored, isTrue);
    return (app, last.record, last.seen);
  }

  CancelOutcome outcomeOf(Result<CancelOutcome, CancelRefusal> result) =>
      switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };

  test(
    'asked first by this robot: sent once, guarded with 9, the ask shown',
    () async {
      final (app, record, seen) = await at9();
      expect((seen.status as Chatting).askedToCancel, isFalse);
      final outcome = outcomeOf(await app.cancel.execute(record, seen));
      expect(outcome, isA<CancelDone>());
      expect(
        outcome.seen.status,
        isA<Chatting>().having((c) => c.askedToCancel, 'asked', isTrue),
      );
      expect(sent(app, cancels), 1);
      expect(app.coordinator.takerAskedCancel, isTrue);
      expect(app.coordinator.status, 9);
    },
  );

  test('asked first by the peer: this robot\'s ask cancels for both', () async {
    final (app, record, seen) = await at9(peerAsked: true);
    expect((seen.status as Chatting).peerAskedToCancel, isTrue);
    final outcome = outcomeOf(await app.cancel.execute(record, seen));
    expect(outcome, isA<CancelDone>());
    expect(outcome.seen.status, isA<Cancelled>());
    expect(app.coordinator.status, 12);
  });

  test(
    'asked, then accepted by the peer: the next read shows it cancelled',
    () async {
      final (app, record, seen) = await at9();
      final asked = outcomeOf(await app.cancel.execute(record, seen));
      app.coordinator.peerAcceptsCancel();
      final run = app.watchOf(asked.record);
      await app.elapse(const Duration(seconds: 15));
      expect(run.lastStatus.seen.status, isA<Cancelled>());
      await run.subscription.cancel();
    },
  );

  test(
    'an ask that lands after « fiat sent »: refused by the guard, nothing cancelled, the trade moved on',
    () async {
      final (app, record, seen) = await at9();
      app.coordinator.moveTo(10);
      final outcome = outcomeOf(await app.cancel.execute(record, seen));
      expect(
        outcome,
        isA<CancelNotDone>().having(
          (n) => n.cause,
          'cause',
          isA<OrderStatusChanged>(),
        ),
      );
      expect(
        outcome.seen.status,
        isA<Chatting>().having((c) => c.fiatSent, 'fiat sent', isTrue),
      );
      expect(app.coordinator.status, 10);
      expect(app.coordinator.takerAskedCancel, isFalse);
    },
  );

  test(
    'an answer lost, the read after shows the ask: done, nothing sent again',
    () async {
      final (app, record, seen) = await at9();
      app.coordinator.failNext(cancels, ScriptedFault.answerLost);
      final outcome = outcomeOf(await app.cancel.execute(record, seen));
      // The read after shows this robot's flag: the ask is recorded.
      expect(outcome, isA<CancelDone>());
      expect(
        outcome.seen.status,
        isA<Chatting>().having((c) => c.askedToCancel, 'asked', isTrue),
      );
      expect(sent(app, cancels), 1);
    },
  );

  test(
    'an answer lost, the ask not yet landed: unknown, nothing sent again',
    () async {
      final (app, record, seen) = await at9();
      app.coordinator.failNext(cancels, ScriptedFault.landsLate);
      final outcome = outcomeOf(await app.cancel.execute(record, seen));
      expect(outcome, isA<CancelOutcomeUnknown>());
      expect(sent(app, cancels), 1);
    },
  );

  test('at 9 from a status not marked stored: nothing sent', () async {
    final (app, record, seen) = await at9();
    app.coordinator.requests.clear();
    expect(
      await app.cancel.execute(
        record,
        TradeSeen(seen.status, order: seen.order),
      ),
      isA<Err<CancelOutcome, CancelRefusal>>().having(
        (err) => err.failure,
        'refusal',
        isA<CancelNeedsARead>(),
      ),
    );
    expect(app.coordinator.requests, isEmpty);
  });

  test('at 10, no cancel exists: nothing sent', () async {
    final (app, record, _) = await at9();
    app.coordinator.moveTo(10);
    final run = app.watchOf(record);
    await app.elapse(const Duration(seconds: 15));
    final ten = run.lastStatus.seen;
    await run.subscription.cancel();
    expect((ten.status as Chatting).fiatSent, isTrue);
    app.coordinator.requests.clear();
    expect(
      await app.cancel.execute(record, ten),
      isA<Err<CancelOutcome, CancelRefusal>>().having(
        (err) => err.failure,
        'refusal',
        isA<CancelNotPossible>(),
      ),
    );
    expect(app.coordinator.requests, isEmpty);
  });
}
