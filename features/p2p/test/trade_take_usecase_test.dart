import 'dart:convert';

import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// The take of an order as its taker (#87): what it reads before, the robot it spends, what it writes before its request leaves, and what each answer gives; the app killed between each pair of steps, then started again.
void main() {
  const read = ScriptedRequest.order;
  const take = ScriptedRequest.take;

  group('a take that starts a trade', () {
    test(
      'reads the order and the fee again, spends one fresh robot, writes before it sends, and starts at the pre-take',
      () async {
        final app = await TradeHarness.start();

        final taken = await app.takeShown();

        final started = switch (taken) {
          Ok(value: final TakeStarted started) => started,
          final other => fail('not started: $other'),
        };
        expect(started.status, isA<WaitingForTakerBond>());
        expect(started.status.warnings, isEmpty);
        expect(started.recordProblem, isNull);
        expect(started.record.confirmedAt, isNotNull);
        expect(started.record.closedAt, isNull);
        expect(started.record.origin, TradeOrigin.takenHere);
        expect(started.record.robot.accountIndex, isNonNegative);
        // The book shown, the fresh book and info, the robot read back (unknown) then its first contact, the take: nothing else, once.
        expect(app.coordinator.received, [
          ScriptedRequest.book,
          ScriptedRequest.book,
          ScriptedRequest.info,
          ScriptedRequest.robot,
          ScriptedRequest.robot,
          take,
        ]);
        expect(app.coordinator.holdsPreTake(app.robot(0)), isTrue);
        final history = switch (await app.trails.historyOf(started.record)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(history.trail?.position, 'bondStep');
        expect(
          history.trail?.bondHash,
          app.coordinator.bondOf(app.robot(0))?.facts.paymentHash,
        );
        expect(history.terms?.takerFee, 0.00175);
      },
    );

    test(
      'the take\'s body is the reference\'s: the action and an amount of 0 for a fixed order',
      () async {
        final app = await TradeHarness.start();
        await app.takeShown();
        final post = app.coordinator.requests.last;
        expect(post.method, CoordinatorHttpMethod.post);
        expect(jsonDecode(utf8.decode(post.body ?? const [])), {
          'action': 'take',
          'amount': 0,
        });
      },
    );
  });

  group('a take that is not sent', () {
    test('a taker fee above the ceiling: no robot, nothing written', () async {
      final app = await TradeHarness.start(takerFee: 0.02);
      expect(
        await app.takeShown(),
        isA<Err<TakeOutcome, TakeRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<TakeTermsRefused>().having(
            (r) => r.reason,
            'reason',
            isA<TakerFeeTooHigh>(),
          ),
        ),
      );
      expect(app.coordinator.received, [
        ScriptedRequest.book,
        ScriptedRequest.book,
        ScriptedRequest.info,
      ]);
      expect(await app.allTrades(), isEmpty);
      expect(
        await app.database.customSelect('SELECT * FROM robot_bindings').get(),
        isEmpty,
      );
    });

    test('a buy order, whose taker would sell: nothing sent at all', () async {
      final app = await TradeHarness.start(orderType: 0);
      final shown = await app.shownOrder();
      final before = app.coordinator.requests.length;
      expect(
        await app.take.execute(shown, network: app.network),
        isA<Err<TakeOutcome, TakeRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<TakeOfBuyOrderRefused>(),
        ),
      );
      expect(app.coordinator.requests, hasLength(before));
    });

    test('an order no longer in the book: no robot', () async {
      final app = await TradeHarness.start();
      final shown = await app.shownOrder();
      app.coordinator.takenByAnother();
      expect(
        await app.take.execute(shown, network: app.network),
        isA<Err<TakeOutcome, TakeRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<TakeOrderGone>(),
        ),
      );
      expect(await app.allTrades(), isEmpty);
    });

    test('an amount for a fixed order', () async {
      final app = await TradeHarness.start();
      expect(
        await app.takeShown(amount: TakeAmount.tryCreate(50)),
        isA<Err<TakeOutcome, TakeRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<TakeAmountRefused>(),
        ),
      );
      expect(await app.allTrades(), isEmpty);
    });

    test('a coordinator that cannot be read just before the take', () async {
      final app = await TradeHarness.start();
      final shown = await app.shownOrder();
      app.coordinator.failNext(ScriptedRequest.info, ScriptedFault.unreachable);
      expect(
        await app.take.execute(shown, network: app.network),
        isA<Err<TakeOutcome, TakeRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<TakeCoordinatorUnreadable>(),
        ),
      );
      expect(await app.allTrades(), isEmpty);
    });

    test(
      'a first contact that fails: the robot stays bound, no take, no record',
      () async {
        final app = await TradeHarness.start();
        app.coordinator
          ..failNext(ScriptedRequest.robot, ScriptedFault.unreachable)
          ..failNext(ScriptedRequest.robot, ScriptedFault.unreachable);
        final taken = await app.takeShown();
        expect(
          taken,
          isA<Err<TakeOutcome, TakeRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<TakeRobotNotPut>(),
          ),
        );
        expect(app.coordinator.received, isNot(contains(take)));
        expect(await app.allTrades(), isEmpty);
      },
    );

    test(
      'terms that cannot be written: the take is refused, the pending take closed',
      () async {
        final app = await TradeHarness.start();
        app.trails.termsFailure = const P2pStorageFailure();
        expect(
          await app.takeShown(),
          isA<Err<TakeOutcome, TakeRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<TakeNotRecorded>(),
          ),
        );
        expect(app.coordinator.received, isNot(contains(take)));
        expect(await app.activeRecords(), isEmpty);
        expect(await app.allTrades(), [
          isA<Map<String, Object?>>().having(
            (row) => row['closed_at'],
            'closed',
            isNotNull,
          ),
        ]);
      },
    );
  });

  group('a take answered without a trade', () {
    test(
      'the order as it is, this robot not its taker: the pending take closed',
      () async {
        final app = await TradeHarness.start();
        app.coordinator.takesNotMade = true;
        final taken = await app.takeShown();
        expect(
          taken,
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeNotMade>()
                .having((n) => n.refusal, 'refusal', isNull)
                .having((n) => n.record.closedAt, 'closed', isNotNull),
          ),
        );
        expect(await app.activeRecords(), isEmpty);
      },
    );

    test(
      'a busy transport every time: never sent, the pending take closed',
      () async {
        final app = await TradeHarness.start();
        for (var i = 0; i < 4; i++) {
          app.coordinator.failNext(take, ScriptedFault.busy);
        }
        final taken = await app.takeShown();
        expect(
          taken,
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeNotMade>().having(
              (n) => n.refusal,
              'refusal',
              isA<RobotCoordinatorBusyFailure>(),
            ),
          ),
        );
        expect(app.busyWaits, hasLength(3));
        expect(await app.activeRecords(), isEmpty);
      },
    );
  });

  group('a take whose answer was lost, resolved by the next read', () {
    test(
      'the take happened: the read shows the pre-take, and the record is confirmed',
      () async {
        final app = await TradeHarness.start();
        app.coordinator.failNext(take, ScriptedFault.answerLost);
        final taken = await app.takeShown();
        expect(
          taken,
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeOutcomeUnknown>(),
          ),
        );
        final record = TradeHarness.recordOf(taken);
        expect(record.isPendingTake, isTrue);

        final run = app.watchOf(record);
        await app.settle();
        expect(run.lastStatus.seen.status, isA<WaitingForTakerBond>());
        expect(run.lastStatus.record.confirmedAt, isNotNull);
        expect(run.lastStatus.takePending, isFalse);
        await run.subscription.cancel();
      },
    );

    test(
      'the take did not happen: the reads go on until the time to lock a bond is over, then it is closed',
      () async {
        final app = await TradeHarness.start();
        app.coordinator.failNext(take, ScriptedFault.timedOut);
        final record = TradeHarness.recordOf(await app.takeShown());

        final run = app.watchOf(record);
        await app.settle();
        // The order public, this robot no participant: not the end yet.
        expect(run.lastStatus.takePending, isTrue);
        expect(run.lastStatus.seen.status, isA<StatusUnknown>());
        expect(run.done, isFalse);
        await app.elapse(const Duration(minutes: 30));
        expect(run.lastStatus.takePending, isTrue);
        expect(await app.activeRecords(), hasLength(1));

        await app.elapse(const Duration(minutes: 1, seconds: 5));
        expect(run.lastStatus.seen.status, isA<PreTakeEnded>());
        expect(run.lastStatus.record.closedAt, isNotNull);
        expect(run.done, isTrue);
        expect(await app.activeRecords(), isEmpty);
        expect(app.activeTimers, isEmpty);
      },
    );
  });

  group('the app killed and started again', () {
    test(
      'after the reservation: no record, the robot spent, no take ever sent',
      () async {
        final app = await TradeHarness.start();
        app.coordinator.onRequest = (request) {
          if (request.url.path == '/api/robot/') throw AppKilled();
        };
        await expectLater(app.takeShown(), throwsA(isA<AppKilled>()));
        app.coordinator.onRequest = null;

        final again = app.restart();
        expect(await again.activeRecords(), isEmpty);
        // A new take is the user's: it takes the next robot, and the first was never sent a take.
        final taken = await again.takeShown();
        expect(taken, isA<Ok<TakeOutcome, TakeRefusal>>());
        expect(TradeHarness.recordOf(taken).robot.accountIndex, isNot(0));
        expect(
          app.coordinator.received.where((kind) => kind == take),
          hasLength(1),
        );
      },
    );

    test(
      'after the pending take: the take never left, and the record is closed once its time is over',
      () async {
        final app = await TradeHarness.start();
        app.kill = KillAt.afterPendingTake;
        await expectLater(app.takeShown(), throwsA(isA<AppKilled>()));

        final again = app.restart();
        final [record] = await again.activeRecords();
        final run = again.watchOf(record);
        await again.settle();
        expect(run.last, isA<TradeWatchTakeNeverSent>());
        await again.elapse(const Duration(minutes: 32));
        expect(
          run.last,
          isA<TradeWatchTakeNeverSent>().having(
            (s) => s.closed,
            'closed',
            isTrue,
          ),
        );
        expect(await again.activeRecords(), isEmpty);
        expect(app.coordinator.received, isNot(contains(take)));
      },
    );

    test(
      'after the terms: resumed on the trail of a pending take, never a fresh trade',
      () async {
        final app = await TradeHarness.start();
        app.kill = KillAt.afterTerms;
        await expectLater(app.takeShown(), throwsA(isA<AppKilled>()));

        final again = app.restart();
        final [record] = await again.activeRecords();
        final run = again.watchOf(record);
        await again.settle();
        expect(run.lastStatus.takePending, isTrue);
        await again.elapse(const Duration(minutes: 32));
        expect(run.lastStatus.seen.status, isA<PreTakeEnded>());
        expect(await again.activeRecords(), isEmpty);
        expect(app.coordinator.received, isNot(contains(take)));
      },
    );

    test(
      'after the request left: the next run reads the pre-take, with the same robot',
      () async {
        final app = await TradeHarness.start();
        app.coordinator.failNext(take, ScriptedFault.answerLost);
        final record = TradeHarness.recordOf(await app.takeShown());

        final again = app.restart();
        expect(await again.activeRecords(), [record]);
        final run = again.watchOf(record);
        await again.settle();
        expect(run.lastStatus.seen.status, isA<WaitingForTakerBond>());
        expect(run.lastStatus.record.robot, record.robot);
        expect(
          app.coordinator.received.where((kind) => kind == take),
          hasLength(1),
        );
        await run.subscription.cancel();
      },
    );

    test(
      'after the answer, before its trail: the next run resumes from the pending trail',
      () async {
        final app = await TradeHarness.start();
        app.kill = KillAt.beforeTrailOfAnswer;
        await expectLater(app.takeShown(), throwsA(isA<AppKilled>()));

        final again = app.restart();
        final [record] = await again.activeRecords();
        expect(record.isPendingTake, isTrue);
        final run = again.watchOf(record);
        await again.settle();
        expect(run.lastStatus.seen.status, isA<WaitingForTakerBond>());
        expect(run.lastStatus.record.confirmedAt, isNotNull);
        expect(
          app.coordinator.received.where((kind) => kind == take),
          hasLength(1),
        );
        expect(app.coordinator.received.last, read);
        await run.subscription.cancel();
      },
    );
  });
}
