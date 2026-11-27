import 'package:get_it/get_it.dart';
import 'package:p2p/src/data/tor_coordinator_transport.dart'
    show coordinatorRequestDeadline;
import 'package:p2p/src/domain/p2p_tor_state.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_pause.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/pauses_in_flight.dart';
import 'package:p2p/testing.dart'
    show ScriptedFault, ScriptedMakerRequest, setUpP2pForTesting;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:test/test.dart';

import 'support/fakes.dart' show FakeTransport;
import 'support/holding_transport.dart';
import 'support/make_harness.dart';
import 'support/signed_bodies.dart';

/// The pause and « Unpause Order » of a public order made here (#184, design note `docs/design/phase-3-making-an-order.md` § 1.6, § 3.4), over the real records, reader, limiter and state machine, the coordinator played by `ScriptedMakerCoordinator` as the reference answers a maker's `pause` (`api/views.py:617-619`, `:686-695`, `Logics.pause_unpause_public_order`, `api/logics.py:1758-1783`).
///
/// The request is a toggle with no direction: every test counts the pause requests that reached the coordinator, and where the order ends, so that a request never leaves twice for one tap, never leaves for an order already where the user asked, and the outcome is never « paused » unless a read says so.
void main() {
  T valueOf<T>(Result<T, Failure> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => fail('$failure'),
  };

  /// An order made and its bond locked (public, 1), paused at the coordinator when [paused], moved by [move], then read by the watch: the harness, the record and the status the user sees.
  Future<(MakeHarness, TradeRecord, TradeSeen)> shown({
    bool paused = false,
    void Function(MakeHarness harness)? move,
  }) async {
    final harness = await MakeHarness.start();
    final made = valueOf(await harness.makeOrder());
    final record = (made as MakeStarted).record;
    // The maker's first read makes the bond at 0, which then locks.
    final first = harness.watchOf(record);
    await harness.settle();
    await first.subscription.cancel();
    harness.coordinator.lockMakerBond(record.orderId);
    if (paused) harness.coordinator.pause(record.orderId);
    move?.call(harness);
    final run = harness.watchOf(record);
    await harness.settle();
    final seen = run.lastStatus.seen;
    await run.subscription.cancel();
    return (harness, record, seen);
  }

  int pauses(MakeHarness harness) => harness.coordinator.received
      .where((kind) => kind == ScriptedMakerRequest.pause)
      .length;

  final deadline = coordinatorRequestDeadline;

  TradeSeen sentAt(TradeSeen of, DateTime when) =>
      TradeSeen(of.status, order: of.order, stored: true, requestedAt: when);

  int statusAt(MakeHarness harness, TradeRecord record) =>
      harness.coordinator.order(record.orderId).status;

  Matcher isPublic({required bool paused}) =>
      isA<MakerOrderPublic>().having((s) => s.paused, 'paused', paused);

  group('one tap, one request, the outcome read', () {
    test(
      'public → paused: the order read, the pause sent once, the read after shows it paused: done',
      () async {
        final (harness, record, seen) = await shown();
        expect(seen.stored, isTrue);
        expect(seen.status, isPublic(paused: false));
        expect(PauseWanted.of(seen), PauseWanted.paused);
        final before = harness.coordinator.received.length;
        final done = valueOf(await harness.pause.execute(record, seen));
        expect(done, isA<PauseDone>());
        expect(done.wanted, PauseWanted.paused);
        expect(done.seen.stored, isTrue);
        expect(done.seen.status, isPublic(paused: true));
        expect(statusAt(harness, record), 2);
        // A read first, the robot read back for the key the pause is signed with (GHSA-22q8-9ghc-jg3h), the pause once, a read after it.
        expect(harness.coordinator.received.sublist(before), [
          ScriptedMakerRequest.order,
          ScriptedMakerRequest.robot,
          ScriptedMakerRequest.pause,
          ScriptedMakerRequest.order,
        ]);
        // The body of both buttons, the reference's (`TradeBox/index.tsx:310-313`).
        final sent = harness.coordinator.requests.firstWhere(
          (r) =>
              r.method == CoordinatorHttpMethod.post &&
              r.url.path == '/api/order/',
        );
        expect(unsignedBodyOf(sent.body), '{"action":"pause"}');
      },
    );

    test(
      'paused → public, « Unpause Order »: the same request, the order public again: done',
      () async {
        final (harness, record, seen) = await shown(paused: true);
        expect(seen.status, isPublic(paused: true));
        expect(PauseWanted.of(seen), PauseWanted.public);
        final done = valueOf(await harness.pause.execute(record, seen));
        expect(done, isA<PauseDone>());
        expect(done.wanted, PauseWanted.public);
        expect(done.seen.status, isPublic(paused: false));
        expect(statusAt(harness, record), 1);
        expect(pauses(harness), 1);
      },
    );

    test(
      'the deadline does not move: a pause and a resume keep the order\'s expiry (`Order.update_status` writes the status only)',
      () async {
        final (harness, record, seen) = await shown();
        final deadline = (seen.status as MakerOrderPublic).deadline;
        final paused = valueOf(await harness.pause.execute(record, seen));
        expect((paused.seen.status as MakerOrderPublic).deadline, deadline);
        final resumed = valueOf(
          await harness.pause.execute(record, paused.seen),
        );
        expect(resumed, isA<PauseDone>());
        expect((resumed.seen.status as MakerOrderPublic).deadline, deadline);
        expect(pauses(harness), 2);
      },
    );

    test(
      'two taps at once: the second waits for the first, reads the order paused and sends nothing',
      () async {
        final (harness, record, seen) = await shown();
        final first = harness.pause.execute(record, seen);
        final second = harness.pause.execute(record, seen);
        final (a, b) = (await first, await second);
        expect(valueOf(a), isA<PauseDone>());
        switch (b) {
          case Err(failure: PauseStatusMoved(:final seen)):
            expect(seen.status, isPublic(paused: true));
          case _:
            fail('$b');
        }
        expect(pauses(harness), 1);
        expect(statusAt(harness, record), 2);
      },
    );
  });

  group('nothing sent when the fresh read is not the status the user saw', () {
    test(
      'paused from another app meanwhile: the toggle would make it public again, so nothing is sent',
      () async {
        final (harness, record, seen) = await shown();
        harness.coordinator.pause(record.orderId);
        final refused = await harness.pause.execute(record, seen);
        switch (refused) {
          case Err(failure: PauseStatusMoved(:final seen)):
            expect(seen.status, isPublic(paused: true));
            expect(seen.stored, isTrue);
          case _:
            fail('$refused');
        }
        expect(pauses(harness), 0);
        expect(statusAt(harness, record), 2);
      },
    );

    test(
      'unpaused from another app meanwhile: « Unpause Order » sends nothing, the order shown public',
      () async {
        final (harness, record, seen) = await shown(paused: true);
        harness.coordinator.pause(record.orderId);
        final refused = await harness.pause.execute(record, seen);
        expect(
          refused,
          isA<Err<PauseOutcome, PauseRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<PauseStatusMoved>().having(
              (m) => m.seen.status,
              'status',
              isPublic(paused: false),
            ),
          ),
        );
        expect(pauses(harness), 0);
        expect(statusAt(harness, record), 1);
      },
    );

    test('taken meanwhile: nothing sent, the trade shown at 6', () async {
      final (harness, record, seen) = await shown();
      harness.coordinator.take(record.orderId, harness.robot(4));
      final refused = await harness.pause.execute(record, seen);
      switch (refused) {
        case Err(failure: PauseStatusMoved(:final seen)):
          expect(seen.status, isA<WaitingForBoth>());
        case _:
          fail('$refused');
      }
      expect(pauses(harness), 0);
    });

    test(
      'expired while paused: « Unpause Order » sends nothing, the order shown expired',
      () async {
        final (harness, record, seen) = await shown(paused: true);
        harness.coordinator.expire(record.orderId);
        final refused = await harness.pause.execute(record, seen);
        switch (refused) {
          case Err(failure: PauseStatusMoved(:final seen)):
            expect(seen.status, isA<Expired>());
          case _:
            fail('$refused');
        }
        expect(pauses(harness), 0);
      },
    );

    test(
      'cancelled meanwhile (1043): nothing sent, the trade shown cancelled',
      () async {
        final (harness, record, seen) = await shown();
        harness.coordinator.order(record.orderId).status = 4;
        final refused = await harness.pause.execute(record, seen);
        switch (refused) {
          case Err(failure: PauseStatusMoved(:final seen)):
            expect(seen.status, isA<Cancelled>());
          case _:
            fail('$refused');
        }
        expect(pauses(harness), 0);
      },
    );

    test('the read before fails: nothing sent, said as such', () async {
      final (harness, record, seen) = await shown();
      harness.coordinator.failNext(
        ScriptedMakerRequest.order,
        ScriptedFault.timedOut,
      );
      final refused = await harness.pause.execute(record, seen);
      expect(
        refused,
        isA<Err<PauseOutcome, PauseRefusal>>().having(
          (e) => e.failure,
          'failure',
          isA<PauseReadFailed>(),
        ),
      );
      expect(pauses(harness), 0);
      expect(statusAt(harness, record), 1);
    });

    test(
      'a status that offers no pause: no request at all, not even a read',
      () async {
        final (harness, record, seen) = await shown();
        final before = harness.coordinator.received.length;
        final notStored = TradeSeen(seen.status, order: seen.order);
        final noOrder = TradeSeen(seen.status, order: null, stored: true);
        for (final status in [notStored, noOrder]) {
          expect(
            await harness.pause.execute(record, status),
            isA<Err<PauseOutcome, PauseRefusal>>().having(
              (e) => e.failure,
              'failure',
              isA<PauseNotOffered>(),
            ),
          );
        }
        // A trade taken here, its read saying otherwise: never a pause.
        final taken = TradeRecord(
          robot: record.robot,
          coordinatorAlias: record.coordinatorAlias,
          coordinatorOnion: record.coordinatorOnion,
          orderId: record.orderId,
          role: record.role,
          origin: TradeOrigin.takenHere,
          takenAt: record.takenAt,
          confirmedAt: record.confirmedAt,
          closedAt: null,
        );
        expect(
          await harness.pause.execute(taken, seen),
          isA<Err<PauseOutcome, PauseRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<PauseNotOffered>(),
          ),
        );
        expect(harness.coordinator.received.length, before);
      },
    );

    test(
      'at the maker bond\'s step (0): no pause offered, nothing sent',
      () async {
        final harness = await MakeHarness.start();
        final record =
            (valueOf(await harness.makeOrder()) as MakeStarted).record;
        final run = harness.watchOf(record);
        await harness.settle();
        final seen = run.lastStatus.seen;
        await run.subscription.cancel();
        expect(seen.status, isA<WaitingForMakerBond>());
        expect(PauseWanted.of(seen), isNull);
        final before = harness.coordinator.received.length;
        expect(
          await harness.pause.execute(record, seen),
          isA<Err<PauseOutcome, PauseRefusal>>(),
        );
        expect(harness.coordinator.received.length, before);
      },
    );
  });

  group('an answer lost, late or refused: never sent again by itself', () {
    test(
      'the answer lost after the toggle: the read after shows it paused, done; one request',
      () async {
        final (harness, record, seen) = await shown();
        harness.coordinator.failNext(
          ScriptedMakerRequest.pause,
          ScriptedFault.answerLost,
        );
        final done = valueOf(await harness.pause.execute(record, seen));
        expect(done, isA<PauseDone>());
        expect(done.seen.status, isPublic(paused: true));
        expect(pauses(harness), 1);
      },
    );

    test(
      'no answer and nothing done: unknown, the order shown public, never sent again',
      () async {
        final (harness, record, seen) = await shown();
        harness.coordinator.failNext(
          ScriptedMakerRequest.pause,
          ScriptedFault.timedOut,
        );
        final unknown = valueOf(await harness.pause.execute(record, seen));
        expect(unknown, isA<PauseOutcomeUnknown>());
        expect(unknown.seen.status, isPublic(paused: false));
        expect(showsPublicOrder(unknown.seen), isTrue);
        expect(pauses(harness), 1);
        expect(statusAt(harness, record), 1);
      },
    );

    test(
      'a request that lands after the read: unknown, then paused at the coordinator; a new tap from the stale status reads it paused and sends nothing, so the order is never toggled back',
      () async {
        final (harness, record, seen) = await shown();
        harness.coordinator.failNext(
          ScriptedMakerRequest.pause,
          ScriptedFault.landsLate,
        );
        final unknown = valueOf(await harness.pause.execute(record, seen));
        expect(unknown, isA<PauseOutcomeUnknown>());
        expect(statusAt(harness, record), 1);
        harness.coordinator.landLate();
        expect(statusAt(harness, record), 2);
        // The user taps again from the status still shown (public).
        final again = await harness.pause.execute(record, unknown.seen);
        switch (again) {
          case Err(failure: PauseStatusMoved(:final seen)):
            expect(seen.status, isPublic(paused: true));
          case _:
            fail('$again');
        }
        expect(pauses(harness), 1);
        expect(statusAt(harness, record), 2);
      },
    );

    test(
      'the transport busy: nothing reached the coordinator, tried again by the limiter; toggled once',
      () async {
        final (harness, record, seen) = await shown();
        harness.coordinator.failNext(
          ScriptedMakerRequest.pause,
          ScriptedFault.busy,
        );
        final done = valueOf(await harness.pause.execute(record, seen));
        expect(done, isA<PauseDone>());
        expect(statusAt(harness, record), 2);
      },
    );

    test(
      'taken between the read and the request: the coordinator refuses (1033), nothing paused, the trade shown at 6',
      () async {
        final (harness, record, seen) = await shown();
        harness.coordinator.onRequest = (request) {
          if (request.method == CoordinatorHttpMethod.post) {
            harness.coordinator.take(record.orderId, harness.robot(4));
          }
        };
        final notDone = valueOf(await harness.pause.execute(record, seen));
        expect(notDone, isA<PauseNotDone>());
        expect(
          (notDone as PauseNotDone).cause,
          isA<TradeActionNotNow>().having(
            (c) => c.fromLastRead,
            'fromLastRead',
            isFalse,
          ),
        );
        expect(notDone.seen.status, isA<WaitingForBoth>());
        expect(statusAt(harness, record), 6);
        expect(pauses(harness), 1);
      },
    );

    for (final (code, cause) in [
      (1032, isA<TradeActionNotMaker>()),
      (1033, isA<TradeActionNotNow>()),
    ]) {
      test(
        'refused with $code: nothing done, said by type, the order shown public',
        () async {
          final (harness, record, seen) = await shown();
          harness.coordinator.pauseRefusals.add(code);
          final notDone = valueOf(await harness.pause.execute(record, seen));
          expect(notDone, isA<PauseNotDone>());
          expect((notDone as PauseNotDone).cause, cause);
          expect(notDone.seen.status, isPublic(paused: false));
          expect(showsPublicOrder(notDone.seen), isTrue);
          expect(pauses(harness), 1);
          expect(statusAt(harness, record), 1);
        },
      );
    }

    test('refused with 1047: nothing done, said by type', () async {
      final (harness, record, seen) = await shown();
      harness.coordinator.failNext(
        ScriptedMakerRequest.pause,
        ScriptedFault.refused,
      );
      final notDone = valueOf(await harness.pause.execute(record, seen));
      expect(notDone, isA<PauseNotDone>());
      expect((notDone as PauseNotDone).cause, isA<OrderNotParticipant>());
      expect(statusAt(harness, record), 1);
    });
  });

  group('the answer compared with what the user asked, never trusted alone', () {
    test(
      'paused from another app between the read and the request: the toggle makes it public again, accepted; the outcome says not reached, the order shown public',
      () async {
        final (harness, record, seen) = await shown();
        harness.coordinator.onRequest = (request) {
          if (request.method == CoordinatorHttpMethod.post) {
            // The official app with the same Garage Key pauses it first.
            harness.coordinator.pause(record.orderId);
          }
        };
        final outcome = valueOf(await harness.pause.execute(record, seen));
        expect(outcome, isA<PauseNotReached>());
        expect(outcome.wanted, PauseWanted.paused);
        expect(outcome.seen.status, isPublic(paused: false));
        expect(showsPublicOrder(outcome.seen), isTrue);
        expect(statusAt(harness, record), 1);
        expect(pauses(harness), 1);
      },
    );

    test(
      'a coordinator that answers « paused » and toggles nothing: the read after shows it public, not reached',
      () async {
        final (harness, record, seen) = await shown();
        harness.coordinator
          ..pauseNotToggled = true
          ..pauseAnswerChanges.add({'status': 2});
        final outcome = valueOf(await harness.pause.execute(record, seen));
        expect(outcome, isA<PauseNotReached>());
        expect(outcome.seen.status, isPublic(paused: false));
        expect(statusAt(harness, record), 1);
      },
    );

    test(
      'a coordinator that answers « paused », toggles nothing, and whose read after is lost: unknown, never done, the order shown public',
      () async {
        final (harness, record, seen) = await shown();
        harness.coordinator
          ..pauseNotToggled = true
          ..pauseAnswerChanges.add({'status': 2});
        harness.coordinator.onRequest = (request) {
          if (request.method == CoordinatorHttpMethod.post) {
            harness.coordinator.failNext(
              ScriptedMakerRequest.order,
              ScriptedFault.timedOut,
            );
          }
        };
        final outcome = valueOf(await harness.pause.execute(record, seen));
        // The answer alone says paused: never taken for the order's status; the status shown stays the read before, public.
        expect(outcome, isA<PauseOutcomeUnknown>());
        expect(outcome.seen.status, isPublic(paused: false));
        expect(statusAt(harness, record), 1);
      },
    );

    test(
      'taken right after a resume, before the read: accepted at 6, not reached; the trade shown taken',
      () async {
        final (harness, record, seen) = await shown(paused: true);
        harness.coordinator.onRequest = (request) {
          if (request.method == CoordinatorHttpMethod.get &&
              harness.coordinator.order(record.orderId).status == 1 &&
              pauses(harness) == 1) {
            harness.coordinator.take(record.orderId, harness.robot(4));
          }
        };
        final outcome = valueOf(await harness.pause.execute(record, seen));
        expect(outcome, isA<PauseNotReached>());
        expect(outcome.seen.status, isA<WaitingForBoth>());
        expect(pauses(harness), 1);
      },
    );
  });

  group('a pause in flight, held on its way (functional review of #184)', () {
    test(
      'the pause and a cancel share the order\'s lock: the cancel reaches the coordinator only after the pause, once, and is refused (1020) since the pause moved the status it guards',
      () async {
        final (harness, record, seen) = await shown();
        final transport = HoldingTransport(harness.coordinator)
          ..holdNextPause();
        final pause = pauseThrough(harness, transport);
        final paused = pause.execute(record, seen);
        await harness.settle();
        expect(transport.pausesSent, 1);
        final cancel = harness.cancel.execute(record, seen);
        await harness.settle();
        // Held behind the pause: nothing of the cancel reached the coordinator.
        expect(
          harness.coordinator.received,
          isNot(contains(ScriptedMakerRequest.cancel)),
        );
        expect(pauses(harness), 0);
        transport.release();
        expect(valueOf(await paused), isA<PauseDone>());
        final cancelled = valueOf(await cancel);
        expect(cancelled, isA<CancelNotDone>());
        expect((cancelled as CancelNotDone).cause, isA<OrderStatusChanged>());
        final kinds = harness.coordinator.received;
        expect(
          kinds.indexOf(ScriptedMakerRequest.pause),
          lessThan(kinds.indexOf(ScriptedMakerRequest.cancel)),
        );
        expect(
          kinds.where((k) => k == ScriptedMakerRequest.cancel),
          hasLength(1),
        );
        expect(statusAt(harness, record), 2);
      },
    );

    test(
      'the watch sends no read while the pause runs, however long it waits',
      () async {
        final (harness, record, seen) = await shown();
        final transport = HoldingTransport(harness.coordinator)
          ..holdNextPause();
        final pause = pauseThrough(harness, transport);
        final run = harness.watchOf(record);
        await harness.settle();
        final paused = pause.execute(record, seen);
        await harness.settle();
        final before = harness.coordinator.received.length;
        await harness.elapse(const Duration(minutes: 10));
        expect(harness.coordinator.received.length, before);
        transport.release();
        expect(valueOf(await paused), isA<PauseDone>());
        await run.subscription.cancel();
      },
    );

    test(
      'known as running while in flight, with what was asked; forgotten once it ends',
      () async {
        final (harness, record, seen) = await shown();
        final transport = HoldingTransport(harness.coordinator)
          ..holdNextPause();
        final pause = pauseThrough(harness, transport);
        expect(pause.running(record), isNull);
        final paused = pause.execute(record, seen);
        await harness.settle();
        final running = pause.running(record);
        expect(running?.wanted, PauseWanted.paused);
        // Another use case object of the same process sees it too.
        expect(harness.pause.running(record), isNotNull);
        transport.release();
        await paused;
        expect(pause.running(record), isNull);
      },
    );
  });

  group('what stays uncertain after an outcome unknown (security review of #184)', () {
    test(
      'a status not stored never counts as paused: neither for the pause wanted nor for the uncertainty (its M12)',
      () async {
        final (harness, record, seen) = await shown();
        final done = valueOf(await harness.pause.execute(record, seen));
        final paused = done.seen;
        expect(paused.stored, isTrue);
        expect(PauseWanted.paused.reachedAt(paused), isTrue);
        final notStored = TradeSeen(
          paused.status,
          order: paused.order,
          requestedAt: paused.requestedAt,
        );
        expect(PauseWanted.paused.reachedAt(notStored), isFalse);
        final readAt = paused.requestedAt;
        if (readAt == null) fail('no request time');
        final uncertain = PauseUncertainty(
          readAt.subtract(const Duration(seconds: 1)),
        );
        expect(
          uncertain
              .observe(
                notStored,
                elapsed: Duration.zero,
                requestDeadline: deadline,
              )
              ?.pausedSinceRequest,
          isFalse,
        );
        expect(
          uncertain
              .observe(
                paused,
                elapsed: Duration.zero,
                requestDeadline: deadline,
              )
              ?.pausedSinceRequest,
          isTrue,
        );
      },
    );

    test(
      'only reads sent after the request count; two reads paused three minutes apart, taken into account three minutes and the transport\'s deadline apart, settle it; a read public restarts it; another status ends it',
      () async {
        final (harness, record, seen) = await shown();
        final done = valueOf(await harness.pause.execute(record, seen));
        final paused = done.seen;
        final readAt = paused.requestedAt;
        if (readAt == null) fail('no request time');
        TradeSeen at(TradeSeen of, DateTime when) => TradeSeen(
          of.status,
          order: of.order,
          stored: true,
          requestedAt: when,
        );
        // Each read taken into account as it is sent, the time that only moves forward with the clock.
        PauseUncertainty? observe(
          PauseUncertainty? uncertain,
          TradeSeen of,
          Duration after,
        ) => uncertain?.observe(
          at(of, readAt.add(after)),
          elapsed: after,
          requestDeadline: deadline,
        );
        final uncertain = PauseUncertainty(readAt);
        // Sent as the request, not after it: nothing.
        expect(
          identical(observe(uncertain, paused, Duration.zero), uncertain),
          isTrue,
        );
        final once = observe(uncertain, paused, const Duration(seconds: 1));
        expect(once?.pausedSinceRequest, isTrue);
        expect(observe(once, paused, const Duration(minutes: 2)), isNotNull);
        // Three minutes: not enough on the time that only moves forward, the second read possibly sent up to the transport's deadline before it was taken into account (security review of #219, R1).
        expect(
          observe(once, paused, const Duration(minutes: 3, seconds: 1)),
          isNotNull,
        );
        expect(
          observe(once, paused, const Duration(minutes: 5, seconds: 13)),
          isNull,
        );
        // Read public meanwhile: the wait starts again.
        final restarted = observe(once, seen, const Duration(minutes: 1));
        expect(restarted?.pausedSinceRequest, isFalse);
        // Taken: nothing left to toggle.
        harness.coordinator
          ..pause(record.orderId)
          ..take(record.orderId, harness.robot(4));
        final run = harness.watchOf(record);
        await harness.settle();
        final taken = run.lastStatus.seen;
        await run.subscription.cancel();
        expect(taken.status, isA<WaitingForBoth>());
        expect(observe(uncertain, taken, const Duration(minutes: 1)), isNull);
      },
    );

    test(
      'the device\'s clock set forward between the two reads paused: not settled until three minutes have passed on the time that only moves forward; set back, kept (security review of #184, R-d, #214)',
      () async {
        final (harness, record, seen) = await shown();
        final done = valueOf(await harness.pause.execute(record, seen));
        final paused = done.seen;
        final readAt = paused.requestedAt;
        if (readAt == null) fail('no request time');
        TradeSeen at(DateTime when) => TradeSeen(
          paused.status,
          order: paused.order,
          stored: true,
          requestedAt: when,
        );
        final uncertain = PauseUncertainty(readAt);
        final once = uncertain.observe(
          at(readAt.add(const Duration(seconds: 1))),
          elapsed: const Duration(seconds: 1),
          requestDeadline: deadline,
        );
        expect(once?.pausedSinceRequest, isTrue);
        // Ten seconds later, the clock set an hour forward: the second read says it was sent an hour after the first.
        final jumped = once?.observe(
          at(readAt.add(const Duration(hours: 1, seconds: 11))),
          elapsed: const Duration(seconds: 11),
          requestDeadline: deadline,
        );
        expect(jumped, isNotNull);
        expect(jumped?.pausedSinceRequest, isTrue);
        // Three real minutes and the transport's deadline after the first: settled.
        expect(
          jumped?.observe(
            at(readAt.add(const Duration(hours: 1, minutes: 5, seconds: 14))),
            elapsed: const Duration(minutes: 5, seconds: 14),
            requestDeadline: deadline,
          ),
          isNull,
        );
        // The clock set back an hour: the read seems sent before the first, minutes later, never settled by it.
        expect(
          once?.observe(
            at(readAt.subtract(const Duration(hours: 1))),
            elapsed: const Duration(minutes: 5, seconds: 14),
            requestDeadline: deadline,
          ),
          isNotNull,
        );
      },
    );

    test(
      'over the real use case and watch: an unknown outcome, the order then read paused twice ten real seconds apart while the device\'s clock jumps an hour forward: the reserve stays (security review of #184, R-d, #214)',
      () async {
        final (harness, record, seen) = await shown();
        harness.coordinator.failNext(
          ScriptedMakerRequest.pause,
          ScriptedFault.landsLate,
        );
        final unknown = valueOf(await harness.pause.execute(record, seen));
        expect(unknown, isA<PauseOutcomeUnknown>());
        expect(harness.pause.uncertainty(record)?.pausedSinceRequest, isFalse);
        // The request lands: the order paused, read so by a read sent after the request; the reserve.
        harness.coordinator.landLate();
        expect(harness.coordinator.order(record.orderId).status, 2);
        await harness.elapse(const Duration(seconds: 5));
        final first = harness.watchOf(record);
        await harness.settle();
        final paused = first.lastStatus.seen;
        await first.subscription.cancel();
        expect(
          harness.pause.uncertainty(record, paused)?.pausedSinceRequest,
          isTrue,
        );
        // Ten real seconds later, the device's clock an hour forward: read paused again, the reserve kept.
        harness.setClockOnly(const Duration(hours: 1));
        await harness.elapse(const Duration(seconds: 10));
        final run = harness.watchOf(record);
        await harness.settle();
        final again = run.lastStatus.seen;
        await run.subscription.cancel();
        expect(again.status, isA<MakerOrderPublic>());
        expect(harness.pause.uncertainty(record, again), isNotNull);
        // More than three real minutes and the transport's deadline after the first read paused: settled.
        await harness.elapse(const Duration(minutes: 5, seconds: 15));
        final later = harness.watchOf(record);
        await harness.settle();
        final settled = later.lastStatus.seen;
        await later.subscription.cancel();
        expect(harness.pause.uncertainty(record, settled), isNull);
      },
    );

    test(
      'the device\'s clock set 140 s forward and the second read answered at the transport\'s deadline: two reads sent 48 real seconds apart do not lift the reserve (security review of #219, R1)',
      () async {
        final (harness, record, seen) = await shown();
        final done = valueOf(await harness.pause.execute(record, seen));
        final paused = done.seen;
        final left = DateTime.utc(2026, 11, 19, 12);
        final once = PauseUncertainty(left).observe(
          sentAt(paused, left.add(const Duration(seconds: 1))),
          elapsed: const Duration(seconds: 1),
          requestDeadline: deadline,
        );
        expect(once?.pausedSinceRequest, isTrue);
        // Sent 48 s later (1 + 48 + 140 s on the clock set forward), answered 132 s after it was sent.
        final second = once?.observe(
          sentAt(paused, left.add(const Duration(seconds: 189))),
          elapsed: const Duration(seconds: 181),
          requestDeadline: deadline,
        );
        expect(second, isNotNull);
        expect(second?.pausedSinceRequest, isTrue);
      },
    );

    test(
      'an honest clock, a read sent 60 s after the first but taken into account long after (a screen opened again on it): the device\'s clock still holds the reserve (the review\'s mutant M4b)',
      () async {
        final (harness, record, seen) = await shown();
        final done = valueOf(await harness.pause.execute(record, seen));
        final paused = done.seen;
        final left = DateTime.utc(2026, 11, 19, 12);
        final once = PauseUncertainty(left).observe(
          sentAt(paused, left.add(const Duration(seconds: 1))),
          elapsed: const Duration(seconds: 1),
          requestDeadline: deadline,
        );
        final second = once?.observe(
          sentAt(paused, left.add(const Duration(seconds: 61))),
          elapsed: const Duration(minutes: 7),
          requestDeadline: deadline,
        );
        expect(second, isNotNull);
        expect(second?.pausedSinceRequest, isTrue);
      },
    );

    test(
      'through the composition (`setUpP2pForTesting`): the device\'s clock an hour forward between two reads paused moments apart, the reserve stays (the review\'s mutant M10: the locator\'s time that only moves forward)',
      () async {
        final (harness, record, seen) = await shown();
        final done = valueOf(await harness.pause.execute(record, seen));
        final paused = done.seen;
        var now = DateTime.utc(2026, 11, 19, 12);
        final locator = GetIt.asNewInstance();
        addTearDown(locator.reset);
        setUpP2pForTesting(
          locator,
          transport: FakeTransport(network: RobosatsNetwork.testnet),
          torStates: () => const Stream<P2pTorState>.empty(),
          clock: () => now,
          garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
        );
        final pauses = locator<PausesInFlight>();
        pauses.unknown(record, now, null);
        expect(pauses.uncertainty(record)?.pausedSinceRequest, isFalse);
        now = now.add(const Duration(seconds: 1));
        pauses.observe(record, sentAt(paused, now));
        expect(pauses.uncertainty(record)?.pausedSinceRequest, isTrue);
        now = now.add(const Duration(hours: 1, seconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(pauses.observe(record, sentAt(paused, now)), isNotNull);
      },
    );

    test(
      'an outcome unknown is kept for every screen of the order, from the time the request left',
      () async {
        final (harness, record, seen) = await shown();
        harness.coordinator.failNext(
          ScriptedMakerRequest.pause,
          ScriptedFault.timedOut,
        );
        final unknown = valueOf(await harness.pause.execute(record, seen));
        expect(unknown, isA<PauseOutcomeUnknown>());
        expect((unknown as PauseOutcomeUnknown).requestLeftAt, isNotNull);
        final uncertain = harness.pause.uncertainty(record);
        expect(uncertain, isNotNull);
        // The read after it showed the order public: not settled, still counted as public.
        expect(uncertain?.pausedSinceRequest, isFalse);
      },
    );

    test(
      'a bug under the use case once the request may have toggled the order (the read after it throws): passed on, the order kept uncertain for every screen, the pause no longer running, the lock given back (security review of #184, mutant N9, #214)',
      () async {
        final (harness, record, seen) = await shown();
        var pauseArrived = false;
        harness.coordinator.onRequest = (request) {
          if (request.method == CoordinatorHttpMethod.post) {
            pauseArrived = true;
          } else if (pauseArrived && request.url.path == '/api/order/') {
            pauseArrived = false;
            throw StateError('a bug below the use case');
          }
        };
        await expectLater(
          harness.pause.execute(record, seen),
          throwsA(isA<StateError>()),
        );
        harness.coordinator.onRequest = null;
        expect(statusAt(harness, record), 2);
        final uncertain = harness.pause.uncertainty(record);
        expect(uncertain, isNotNull);
        expect(uncertain?.pausedSinceRequest, isFalse);
        expect(harness.pause.running(record), isNull);
        // The order's lock given back: a cancel goes.
        final paused = harness.watchOf(record);
        await harness.settle();
        final now = paused.lastStatus.seen;
        await paused.subscription.cancel();
        expect(valueOf(await harness.cancel.execute(record, now)), isNotNull);
        expect(statusAt(harness, record), 4);
      },
    );
  });
}
