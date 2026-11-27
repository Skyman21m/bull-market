import 'dart:async';

import 'package:p2p/src/domain/p2p_failure.dart';
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
    // The read before, the robot read back for the key the action is signed with (GHSA-22q8-9ghc-jg3h), the action once, the read after.
    expect(app.coordinator.received, [
      ScriptedRequest.order,
      ScriptedRequest.robot,
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
    'an answer lost after the coordinator acted: the read after shows it recorded, so done; nothing sent again',
    () async {
      final (app, record, seen) = await at();
      app.coordinator.failNext(confirms, ScriptedFault.answerLost);
      final result = await app.chat.confirmFiatSent(record, seen);
      final outcome = switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      // The status that shows it recorded settles it: no notice contradicts it.
      expect(outcome, isA<ChatStepDone>());
      expect(fiatSentShown(outcome.seen), isTrue);
      expect(sent(app, confirms), 1);
    },
  );

  test('the read before sending cannot be stored: nothing sent', () async {
    final (app, record, seen) = await at();
    app.trails.storeFailure = const P2pStorageFailure();
    final result = await app.chat.confirmFiatSent(record, seen);
    app.trails.storeFailure = null;
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

  test('the order seen is another trade\'s: nothing read or sent', () async {
    final (app, record, _) = await at();
    final other = await TradeHarness.start(orderId: 43);
    final taken = await other.takeShown();
    final otherRecord = TradeHarness.recordOf(taken);
    final run = other.watchOf(otherRecord);
    await other.settle();
    other.coordinator
      ..lockBond(other.robot(0))
      ..moveTo(9);
    await other.elapse(const Duration(seconds: 5));
    final otherSeen = run.lastStatus.seen;
    await run.subscription.cancel();
    expect(otherSeen.order?.id, 43);
    app.coordinator.requests.clear();
    expect(
      await app.chat.confirmFiatSent(record, otherSeen),
      isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
        (err) => err.failure,
        'refusal',
        isA<ChatStepOfAnotherTrade>(),
      ),
    );
    expect(app.coordinator.requests, isEmpty);
  });

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

  group('« Payment failed? »', () {
    test(
      'sent once from 10, after a fresh read; 9 shown once recorded',
      () async {
        final (app, record, ten) = await at(status: 10);
        final result = await app.chat.undoFiatSent(record, ten);
        final outcome = switch (result) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(outcome, isA<ChatStepDone>());
        expect(outcome.seen.status, isA<Chatting>());
        expect(fiatSentShown(outcome.seen), isFalse);
        expect(app.coordinator.status, 9);
        expect(app.coordinator.revertedFiatSent, isTrue);
        expect(sent(app, ScriptedRequest.undoConfirm), 1);
      },
    );

    test('not offered at 9: nothing read or sent', () async {
      final (app, record, nine) = await at();
      app.coordinator.requests.clear();
      expect(
        await app.chat.undoFiatSent(record, nine),
        isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<ChatStepNotOffered>(),
        ),
      );
      expect(app.coordinator.requests, isEmpty);
    });

    test(
      'the seller confirmed meanwhile: nothing sent, the status now',
      () async {
        final (app, record, ten) = await at(status: 10);
        app.coordinator.moveTo(13);
        expect(
          await app.chat.undoFiatSent(record, ten),
          isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<ChatStepStatusMoved>(),
          ),
        );
        expect(sent(app, ScriptedRequest.undoConfirm), 0);
      },
    );

    test(
      'a request that lands late, then a second tap: done, nothing sent again',
      () async {
        final (app, record, ten) = await at(status: 10);
        app.coordinator.failNext(
          ScriptedRequest.undoConfirm,
          ScriptedFault.landsLate,
        );
        final first = switch (await app.chat.undoFiatSent(record, ten)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(first, isA<ChatStepOutcomeUnknown>());
        expect(fiatSentShown(first.seen), isTrue);
        app.coordinator.landLate();
        final second = switch (await app.chat.undoFiatSent(
          first.record,
          first.seen,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(second, isA<ChatStepDone>());
        expect(fiatSentShown(second.seen), isFalse);
        expect(sent(app, ScriptedRequest.undoConfirm), 1);
      },
    );
  });

  group('« Open Dispute »', () {
    /// [record]'s trade read again by the watch, once the coordinator moved the step's end to [deadlineIn] from now.
    Future<TradeSeen> readWithEnd(
      TradeHarness app,
      TradeRecord record,
      Duration deadlineIn,
    ) async {
      app.coordinator.moveDeadline(app.now.add(deadlineIn));
      final run = app.watchOf(record);
      await app.elapse(const Duration(seconds: 5));
      final last = run.lastStatus;
      await run.subscription.cancel();
      expect(last.stored, isTrue);
      return last.seen;
    }

    test(
      'before its time (the chat\'s end less 18 hours, by this device\'s clock): refused with what is left, nothing read or sent',
      () async {
        final (app, record, nine) = await at();
        // The chat's 24 hours: open in 6 hours.
        expect(ChatStepAction.dispute.offeredAt(nine), isTrue);
        app.coordinator.requests.clear();
        final result = await app.chat.startDispute(record, nine);
        expect(
          result,
          isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<ChatStepTooEarly>()
                .having(
                  (t) => t.opensAt,
                  'opens at',
                  (nine.status as Chatting).deadline.subtract(
                    const Duration(hours: 18),
                  ),
                )
                .having(
                  (t) => t.left,
                  'left',
                  allOf(
                    greaterThan(const Duration(hours: 5, minutes: 59)),
                    lessThanOrEqualTo(const Duration(hours: 6)),
                  ),
                )
                // From the status shown, before any read: no read to show.
                .having((t) => t.seen, 'seen', isNull),
          ),
        );
        expect(app.coordinator.requests, isEmpty);
      },
    );

    for (final status in [9, 10]) {
      test(
        'at $status, its time come: sent once after a fresh read; the dispute shown once recorded',
        () async {
          final (app, record, _) = await at(status: status);
          final seen = await readWithEnd(app, record, const Duration(hours: 1));
          app.coordinator.requests.clear();
          final steps = <ChatStepProgress>[];
          final outcome = switch (await app.chat.startDispute(
            record,
            seen,
            onProgress: steps.add,
          )) {
            Ok(:final value) => value,
            Err(:final failure) => fail('$failure'),
          };
          expect(outcome, isA<ChatStepDone>());
          expect(outcome.seen.status, isA<InDispute>());
          expect(outcome.seen.stored, isTrue);
          expect(app.coordinator.status, 11);
          expect(app.coordinator.received, [
            ScriptedRequest.order,
            ScriptedRequest.robot,
            ScriptedRequest.dispute,
            ScriptedRequest.order,
          ]);
          expect(steps, [
            ChatStepProgress.waitingForOrder,
            ChatStepProgress.readingOrder,
            ChatStepProgress.sending,
            ChatStepProgress.readingAfter,
          ]);
        },
      );
    }

    test(
      'the fresh read shows a later end: refused as too early with that read, for the screen to show it, nothing sent (review of #156)',
      () async {
        final (app, record, _) = await at();
        final seen = await readWithEnd(app, record, const Duration(hours: 1));
        final later = app.now.add(const Duration(hours: 30));
        app.coordinator.moveDeadline(later);
        expect(
          await app.chat.startDispute(record, seen),
          isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<ChatStepTooEarly>()
                .having(
                  (t) => switch (t.seen?.status) {
                    Chatting(:final deadline) =>
                      deadline.difference(later).abs(),
                    _ => null,
                  },
                  'the fresh read\'s end, to the second',
                  lessThan(const Duration(seconds: 1)),
                )
                .having((t) => t.seen?.stored, 'stored', isTrue)
                .having((t) => t.record?.orderId, 'record', record.orderId),
          ),
        );
        expect(sent(app, ScriptedRequest.dispute), 0);
      },
    );

    test(
      'refused by the coordinator as too early (1054): not done, said as such, nothing sent again',
      () async {
        final (app, record, _) = await at();
        final seen = await readWithEnd(app, record, const Duration(hours: 1));
        // The coordinator's end moves later as the request arrives: its clock is the judge.
        app.coordinator.onRequest = (request) {
          if (request.method == CoordinatorHttpMethod.post) {
            app.coordinator.moveDeadline(
              app.now.add(const Duration(hours: 30)),
            );
          }
        };
        final outcome = switch (await app.chat.startDispute(record, seen)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        app.coordinator.onRequest = null;
        expect(
          outcome,
          isA<ChatStepNotDone>().having(
            (n) => n.cause,
            'cause',
            isA<DisputeTooEarly>(),
          ),
        );
        expect(outcome.seen.status, isA<Chatting>());
        expect(sent(app, ScriptedRequest.dispute), 1);
      },
    );

    test(
      'an answer lost, the read after shows the dispute: done, nothing sent again',
      () async {
        final (app, record, _) = await at();
        final seen = await readWithEnd(app, record, const Duration(hours: 1));
        app.coordinator.failNext(
          ScriptedRequest.dispute,
          ScriptedFault.answerLost,
        );
        final outcome = switch (await app.chat.startDispute(record, seen)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(outcome, isA<ChatStepDone>());
        expect(outcome.seen.status, isA<InDispute>());
        expect(sent(app, ScriptedRequest.dispute), 1);
      },
    );

    test(
      'a request that lands late, then a second tap: done, nothing sent again',
      () async {
        final (app, record, _) = await at();
        final seen = await readWithEnd(app, record, const Duration(hours: 1));
        app.coordinator.failNext(
          ScriptedRequest.dispute,
          ScriptedFault.landsLate,
        );
        final first = switch (await app.chat.startDispute(record, seen)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(first, isA<ChatStepOutcomeUnknown>());
        expect(first.seen.status, isA<Chatting>());
        app.coordinator.landLate();
        final second = switch (await app.chat.startDispute(
          first.record,
          first.seen,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(second, isA<ChatStepDone>());
        expect(second.seen.status, isA<InDispute>());
        expect(sent(app, ScriptedRequest.dispute), 1);
      },
    );

    for (final status in [16, 17, 18]) {
      test(
        'the fresh read shows the dispute further on ($status): done, nothing sent (review of #156)',
        () async {
          final (app, record, _) = await at();
          final seen = await readWithEnd(app, record, const Duration(hours: 1));
          app.coordinator
            ..moveTo(11)
            ..moveTo(status);
          final outcome = switch (await app.chat.startDispute(record, seen)) {
            Ok(:final value) => value,
            Err(:final failure) => fail('$failure'),
          };
          expect(outcome, isA<ChatStepDone>());
          expect(sent(app, ScriptedRequest.dispute), 0);
        },
      );
    }

    test(
      'refused by the coordinator as not now (1013, the trade moved on after the fresh read): not done, nothing sent again (review of #156)',
      () async {
        final (app, record, _) = await at();
        final seen = await readWithEnd(app, record, const Duration(hours: 1));
        app.coordinator.onRequest = (request) {
          if (request.method == CoordinatorHttpMethod.post) {
            app.coordinator.moveTo(13);
          }
        };
        final outcome = switch (await app.chat.startDispute(record, seen)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        app.coordinator.onRequest = null;
        expect(
          outcome,
          isA<ChatStepNotDone>().having(
            (n) => n.cause,
            'cause',
            isA<TradeActionNotNow>().having(
              (r) => r.fromLastRead,
              'from the last read',
              isFalse,
            ),
          ),
        );
        expect(outcome.seen.status, isA<SendingSats>());
        expect(sent(app, ScriptedRequest.dispute), 1);
      },
    );

    test(
      'the fresh read fails (Tor, the coordinator): refused, nothing sent (review of #156)',
      () async {
        final (app, record, _) = await at();
        final seen = await readWithEnd(app, record, const Duration(hours: 1));
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.unreachable,
        );
        expect(
          await app.chat.startDispute(record, seen),
          isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<ChatStepReadFailed>(),
          ),
        );
        expect(sent(app, ScriptedRequest.dispute), 0);
      },
    );

    test(
      'not offered from a status not marked stored: nothing read or sent',
      () async {
        final (app, record, _) = await at();
        final seen = await readWithEnd(app, record, const Duration(hours: 1));
        app.coordinator.requests.clear();
        expect(
          await app.chat.startDispute(
            record,
            TradeSeen(seen.status, order: seen.order),
          ),
          isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<ChatStepNotOffered>(),
          ),
        );
        expect(app.coordinator.requests, isEmpty);
      },
    );
  });

  group('« Rate your trade experience »', () {
    PlatformRating stars(int n) => PlatformRating.of(n) ?? fail('no rating');

    test('sent once from 14, after a fresh read, with its stars', () async {
      final (app, record, finished) = await at(status: 14);
      expect(finished.status, isA<Succeeded>());
      app.coordinator.requests.clear();
      final steps = <ChatStepProgress>[];
      final result = await app.chat.rate(
        record,
        finished,
        stars(4),
        onProgress: steps.add,
      );
      final outcome = switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(outcome, isA<ChatStepDone>());
      // The end shown stays: nothing is written at an end, and no read tells a rating.
      expect(identical(outcome.seen, finished), isTrue);
      expect(app.coordinator.platformRating, 4);
      expect(app.coordinator.received, [
        ScriptedRequest.order,
        ScriptedRequest.robot,
        ScriptedRequest.rate,
      ]);
      expect(steps, [
        ChatStepProgress.waitingForOrder,
        ChatStepProgress.readingOrder,
        ChatStepProgress.sending,
      ]);
      // Another tap sends again, as the reference sends each change of its stars; from an unmarked read of the end too.
      expect(
        await app.chat.rate(
          outcome.record,
          TradeSeen(finished.status, order: finished.order),
          stars(5),
        ),
        isA<Ok<ChatStepOutcome, ChatStepRefusal>>(),
      );
      expect(app.coordinator.platformRating, 5);
      expect(sent(app, ScriptedRequest.rate), 2);
    });

    test('the read before no longer shows 14: nothing sent', () async {
      final (app, record, finished) = await at(status: 14);
      app.coordinator.moveTo(13);
      expect(
        await app.chat.rate(record, finished, stars(3)),
        isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<ChatStepStatusMoved>(),
        ),
      );
      expect(sent(app, ScriptedRequest.rate), 0);
    });

    test('the order seen is another trade\'s: nothing read or sent', () async {
      final (app, record, _) = await at(status: 14);
      final other = await TradeHarness.start(orderId: 43);
      final taken = await other.takeShown();
      final run = other.watchOf(TradeHarness.recordOf(taken));
      await other.settle();
      other.coordinator
        ..lockBond(other.robot(0))
        ..moveTo(14);
      await other.elapse(const Duration(seconds: 5));
      final otherSeen = run.lastStatus.seen;
      await run.subscription.cancel();
      expect(otherSeen.order?.id, 43);
      expect(ChatStepAction.rate.offeredAt(otherSeen), isTrue);
      app.coordinator.requests.clear();
      expect(
        await app.chat.rate(record, otherSeen, stars(5)),
        isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<ChatStepOfAnotherTrade>(),
        ),
      );
      expect(app.coordinator.requests, isEmpty);
    });

    test(
      'refused by the coordinator: not done, told apart from an outcome unknown',
      () async {
        final (app, record, finished) = await at(status: 14);
        app.coordinator.failNext(ScriptedRequest.rate, ScriptedFault.refused);
        final outcome = switch (await app.chat.rate(
          record,
          finished,
          stars(2),
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(outcome, isA<ChatStepNotDone>());
        expect(app.coordinator.platformRating, isNull);
      },
    );

    test('the read before fails: nothing sent', () async {
      final (app, record, finished) = await at(status: 14);
      app.coordinator.failNext(
        ScriptedRequest.order,
        ScriptedFault.unreachable,
      );
      expect(
        await app.chat.rate(record, finished, stars(3)),
        isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<ChatStepReadFailed>(),
        ),
      );
      expect(sent(app, ScriptedRequest.rate), 0);
    });

    test(
      'not offered before 14, nor from a status without an order read',
      () async {
        final (app, record, nine) = await at();
        app.coordinator.requests.clear();
        expect(
          await app.chat.rate(record, nine, stars(5)),
          isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<ChatStepNotOffered>(),
          ),
        );
        final (other, otherRecord, finished) = await at(status: 14);
        other.coordinator.requests.clear();
        expect(
          await other.chat.rate(
            otherRecord,
            TradeSeen(finished.status, order: null, stored: true),
            stars(5),
          ),
          isA<Err<ChatStepOutcome, ChatStepRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<ChatStepNotOffered>(),
          ),
        );
        expect(app.coordinator.requests, isEmpty);
        expect(other.coordinator.requests, isEmpty);
      },
    );

    test('an answer lost: an outcome unknown, never sent again', () async {
      final (app, record, finished) = await at(status: 14);
      app.coordinator.failNext(ScriptedRequest.rate, ScriptedFault.answerLost);
      final outcome = switch (await app.chat.rate(record, finished, stars(3))) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(outcome, isA<ChatStepOutcomeUnknown>());
      expect(sent(app, ScriptedRequest.rate), 1);
    });
  });
}
