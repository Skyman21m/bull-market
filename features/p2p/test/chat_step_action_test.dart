import 'dart:async';

import 'package:p2p/src/domain/trade/trade_chat_step.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// « Confirm {{amount}} {{currencyCode}} sent » (#95): the buyer's « fiat sent » is sent once, from a fresh read that still shows the status the user saw, and a lost answer is resolved by a read, never by a second send; over the coordinator the tests play (never a real coordinator).
void main() {
  const confirms = ScriptedRequest.confirm;

  int sent(TradeHarness app, ScriptedRequest kind) =>
      app.coordinator.received.where((k) => k == kind).length;

  /// A trade taken on a fresh run, its bond locked, moved to [status] (9 by default), and that status as a read stored it.
  Future<(TradeHarness, TradeRecord, TradeSeen)> at({int status = 9}) async {
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
    app.coordinator.moveTo(status);
    await app.elapse(const Duration(seconds: 5));
    final last = run.lastStatus;
    await run.subscription.cancel();
    expect(last.stored, isTrue);
    return (app, last.record, last.seen);
  }

  bool fiatSentShown(TradeSeen seen) => switch (seen.status) {
    Chatting(:final fiatSent) => fiatSent,
    _ => false,
  };

  test('sent once, after a fresh read; 10 shown once recorded', () async {
    final (app, record, seen) = await at();
    expect(fiatSentShown(seen), isFalse);
    final steps = <ChatStepProgress>[];
    app.coordinator.requests.clear();
    final result = await app.chat.confirmFiatSent(
      record,
      seen,
      onProgress: steps.add,
    );
    final outcome = switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => fail('$failure'),
    };
    expect(outcome, isA<ChatStepDone>());
    expect(fiatSentShown(outcome.seen), isTrue);
    expect(outcome.seen.stored, isTrue);
    expect(app.coordinator.status, 10);
    // The read before, the action once, the read after.
    expect(app.coordinator.received, [
      ScriptedRequest.order,
      confirms,
      ScriptedRequest.order,
    ]);
    expect(steps, [
      ChatStepProgress.waitingForOrder,
      ChatStepProgress.readingOrder,
      ChatStepProgress.sending,
      ChatStepProgress.readingAfter,
    ]);
  });

  test(
    'an answer lost after the coordinator acted: the read after shows it recorded, nothing sent again',
    () async {
      final (app, record, seen) = await at();
      app.coordinator.failNext(confirms, ScriptedFault.answerLost);
      final result = await app.chat.confirmFiatSent(record, seen);
      final outcome = switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(outcome, isA<ChatStepOutcomeUnknown>());
      expect(fiatSentShown(outcome.seen), isTrue);
      expect(sent(app, confirms), 1);
    },
  );

  test(
    'no answer and nothing done: the read after still shows 9, nothing sent again',
    () async {
      final (app, record, seen) = await at();
      app.coordinator.failNext(confirms, ScriptedFault.timedOut);
      final result = await app.chat.confirmFiatSent(record, seen);
      final outcome = switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(outcome, isA<ChatStepOutcomeUnknown>());
      expect(fiatSentShown(outcome.seen), isFalse);
      expect(outcome.seen.status, isA<Chatting>());
      expect(sent(app, confirms), 1);
      expect(app.coordinator.status, 9);
    },
  );

  test(
    'a request that lands late, then a second tap: one confirmed state, nothing shown as a failure',
    () async {
      final (app, record, seen) = await at();
      app.coordinator.failNext(confirms, ScriptedFault.landsLate);
      final first = switch (await app.chat.confirmFiatSent(record, seen)) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      // The read after shows 9: it proves nothing, the request may still land.
      expect(first, isA<ChatStepOutcomeUnknown>());
      expect(fiatSentShown(first.seen), isFalse);
      app.coordinator.landLate();
      expect(app.coordinator.status, 10);
      // The user taps again from the 9 shown: the fresh read finds it recorded, nothing is sent again.
      final second = switch (await app.chat.confirmFiatSent(
        first.record,
        first.seen,
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(second, isA<ChatStepDone>());
      expect(fiatSentShown(second.seen), isTrue);
      expect(sent(app, confirms), 1);
    },
  );

  test(
    'a request that lands after the second tap\'s read: both land, one confirmed state',
    () async {
      final (app, record, seen) = await at();
      app.coordinator.failNext(confirms, ScriptedFault.landsLate);
      final first = switch (await app.chat.confirmFiatSent(record, seen)) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      // The late request lands while the second one is on its way: a second « confirm » by the buyer at 10 changes nothing.
      app.coordinator.onRequest = (request) {
        if (app.coordinator.received.last == confirms) {
          app.coordinator.landLate();
        }
      };
      final second = switch (await app.chat.confirmFiatSent(
        first.record,
        first.seen,
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      app.coordinator.onRequest = null;
      expect(second, isA<ChatStepDone>());
      expect(fiatSentShown(second.seen), isTrue);
      expect(sent(app, confirms), 2);
      expect(app.coordinator.status, 10);
    },
  );

  test(
    'the order moved before the tap: nothing sent, the status now',
    () async {
      final (app, record, seen) = await at();
      // The seller confirmed, or a dispute opened, while the dialog was open.
      app.coordinator.moveTo(11);
      final result = await app.chat.confirmFiatSent(record, seen);
      expect(
        result,
        isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<ChatStepStatusMoved>().having(
            (moved) => moved.seen.status,
            'status',
            isA<InDispute>(),
          ),
        ),
      );
      expect(sent(app, confirms), 0);
    },
  );

  test('the read before fails: nothing sent', () async {
    final (app, record, seen) = await at();
    app.coordinator.failNext(ScriptedRequest.order, ScriptedFault.unreachable);
    final result = await app.chat.confirmFiatSent(record, seen);
    expect(
      result,
      isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
        (err) => err.failure,
        'refusal',
        isA<ChatStepReadFailed>(),
      ),
    );
    expect(sent(app, confirms), 0);
  });

  test(
    'not offered: at 10, at 8, from a status not stored or from no order; nothing read or sent',
    () async {
      final (app, record, nine) = await at();
      final (_, _, ten) = await at(status: 10);
      final (_, _, eight) = await at(status: 8);
      for (final (label, rec, seen) in [
        ('10', record, ten),
        ('8', record, eight),
        ('not stored', record, TradeSeen(nine.status, order: nine.order)),
        ('no order', record, TradeSeen(nine.status, order: null, stored: true)),
      ]) {
        app.coordinator.requests.clear();
        expect(
          await app.chat.confirmFiatSent(rec, seen),
          isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<ChatStepNotOffered>(),
          ),
          reason: label,
        );
        expect(app.coordinator.requests, isEmpty, reason: label);
      }
    },
  );

  test(
    'the coordinator refuses (1029, the order moved after the read): nothing done, said so',
    () async {
      final (app, record, seen) = await at();
      app.coordinator.onRequest = (request) {
        if (app.coordinator.received.last == confirms) {
          app.coordinator.moveTo(11);
        }
      };
      final result = await app.chat.confirmFiatSent(record, seen);
      app.coordinator.onRequest = null;
      final outcome = switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(
        outcome,
        isA<ChatStepNotDone>().having(
          (n) => n.cause,
          'cause',
          isA<TradeActionNotNow>(),
        ),
      );
      expect(outcome.seen.status, isA<InDispute>());
      expect(sent(app, confirms), 1);
    },
  );

  test(
    'a busy transport sends nothing: tried again as the limiter says, recorded once',
    () async {
      final (app, record, seen) = await at();
      app.coordinator.failNext(confirms, ScriptedFault.busy);
      final result = await app.chat.confirmFiatSent(record, seen);
      expect(
        result,
        isA<Ok<ChatStepOutcome, ChatStepRefusal>>().having(
          (ok) => ok.value,
          'outcome',
          isA<ChatStepDone>(),
        ),
      );
      expect(app.busyWaits, isNotEmpty);
      expect(app.coordinator.status, 10);
    },
  );

  test(
    'another action of the order holds it: the wait is said, then the action',
    () async {
      final (app, record, seen) = await at();
      final release = Completer<void>();
      final held = app.locks.run(
        record.network,
        app.coordinator.coordinator,
        record.orderId,
        () => release.future,
      );
      final steps = <ChatStepProgress>[];
      final confirming = app.chat.confirmFiatSent(
        record,
        seen,
        onProgress: steps.add,
      );
      await app.settle();
      expect(steps, [ChatStepProgress.waitingForOrder]);
      expect(sent(app, confirms), 0);
      release.complete();
      await held;
      final result = await confirming;
      expect(
        result,
        isA<Ok<ChatStepOutcome, ChatStepRefusal>>().having(
          (ok) => ok.value,
          'outcome',
          isA<ChatStepDone>(),
        ),
      );
      expect(sent(app, confirms), 1);
    },
  );

  test('a progress listener that throws stops nothing', () async {
    final (app, record, seen) = await at();
    final errors = <Object>[];
    final result = await runZonedGuarded(
      () => app.chat.confirmFiatSent(
        record,
        seen,
        onProgress: (_) => throw StateError('listener'),
      ),
      (error, _) => errors.add(error),
    );
    expect(
      result,
      isA<Ok<ChatStepOutcome, ChatStepRefusal>>().having(
        (ok) => ok.value,
        'outcome',
        isA<ChatStepDone>(),
      ),
    );
    expect(errors, hasLength(4));
  });
}
