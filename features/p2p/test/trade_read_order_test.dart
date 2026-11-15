import 'dart:async';
import 'dart:convert';

import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_chat_step.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_payout_outcome.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/trade_read_order.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/testing.dart'
    show Bolt11TestInvoice, ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// The answers of a trade kept in the order the coordinator served them (#141): an answer replaces the stored status only if its request left after the stored status's answer arrived, the watch sends no read while an action of the trade runs, and what each caller does with an answer superseded; over the coordinator the tests play.
void main() {
  // The order of the scripted coordinator once the bond locks: the buyer receives 106,713 sats (`trade_payout_test.dart`).
  const buyerSats = 106713;
  var seed = 951;

  /// A trade taken on a fresh run, its bond locked, at [status] as the watch stored it, the watch still running, told [signals].
  Future<(TradeHarness, TradeRecord, TradeSeen, WatchRun)> watchedAt(
    int status, {
    Stream<TradeWatchSignal> signals = const Stream.empty(),
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
    final run = app.watchOf(record, signals: signals);
    await app.settle();
    app.coordinator.lockBond(app.robot(0));
    app.coordinator.moveTo(status);
    await app.elapse(const Duration(seconds: 5));
    final last = run.lastStatus;
    expect(last.stored, isTrue);
    return (app, last.record, last.seen, run);
  }

  Future<OpenTrade> opened(TradeHarness app, TradeRecord record) async =>
      switch (await app.reader.open(record)) {
        TradeOpened(:final trade) => trade,
        final other => fail('not opened: $other'),
      };

  /// A read of [record]'s order through the reader's ranks: it leaves now, is served after [served] (at once without it), and its answer arrives after [arrives] (at once without it).
  Future<TradeAnswer> read(
    TradeHarness app,
    TradeRecord record,
    RequestTimes times, {
    Future<void>? served,
    Future<void>? arrives,
  }) async {
    final answer = await app.reader.timed(times, () async {
      if (served != null) await served;
      final read = await CoordinatorClient(app.coordinator).fetchOrder(
        app.coordinator.coordinator,
        app.network,
        identity: app.robot(0),
        orderId: record.orderId,
      );
      if (arrives != null) await arrives;
      return read;
    });
    return TradeAnswer.ofRead(answer) ?? fail('no answer');
  }

  Future<String?> positionOnDisk(TradeHarness app, TradeRecord record) async =>
      switch (await app.trails.historyOf(record)) {
        Ok(:final value) => value.trail?.position,
        Err(:final failure) => fail('$failure'),
      };

  Future<bool?> breachOnDisk(TradeHarness app, TradeRecord record) async =>
      switch (await app.trails.historyOf(record)) {
        Ok(:final value) => value.trail?.breached,
        Err(:final failure) => fail('$failure'),
      };

  int orderReads(TradeHarness app) => app.coordinator.received
      .where((kind) => kind == ScriptedRequest.order)
      .length;

  CheckedPayout shownPayout(
    TradeHarness app,
    TradeRecord record,
    TradeSeen seen,
  ) {
    final invoice = Bolt11TestInvoice(
      network: Bolt11Network.testnet,
      sats: buyerSats,
      seed: seed++,
      createdAt: app.now,
      expiry: const Duration(days: 2),
    );
    app.coordinator.decoder.add(invoice);
    return switch (app.payout.check(
      record,
      seen,
      PayoutInvoiceText(
        invoice.text,
        budget: RoutingBudgetPpm.of(0) ?? RoutingBudgetPpm.referenceDefault,
      ),
    )) {
      Ok(:final value) => value,
      Err(:final failure) => fail('refused: $failure'),
    };
  }

  bool fiatSentShown(TradeSeen seen) => switch (seen.status) {
    Chatting(:final fiatSent) => fiatSent,
    _ => false,
  };

  group('TradeReadOrder', () {
    test(
      'of two requests whose flights overlap, the later answer is superseded, whichever left first; a request that left after an answer arrived is not',
      () async {
        final order = TradeReadOrder();
        final app = await TradeHarness.start();
        final record = TradeHarness.recordOf(await app.takeShown());
        final now = DateTime.utc(2026, 11, 15, 12);
        // The first leaves, the second leaves, the second's answer arrives first.
        final first = order.request();
        final second = order.request();
        final firstArrives = Completer<void>();
        final firstAnswer = order.send(first, now, () => firstArrives.future);
        await order.send(second, now, () async {});
        expect(order.claim(record.robot, second), isNull);
        firstArrives.complete();
        await firstAnswer;
        expect(order.claim(record.robot, first), isNotNull);
        // A third leaves after both arrived: it is not.
        final third = order.request();
        await order.send(third, now, () async {});
        expect(order.claim(record.robot, third), isNull);
        // The mirror: the fourth leaves first, the fifth after, the fourth's answer arrives first; the fifth's, later, is superseded.
        final fourth = order.request();
        final fifth = order.request();
        final fifthArrives = Completer<void>();
        final fourthArrives = Completer<void>();
        final fourthAnswer = order.send(
          fourth,
          now,
          () => fourthArrives.future,
        );
        final fifthAnswer = order.send(fifth, now, () => fifthArrives.future);
        fourthArrives.complete();
        await fourthAnswer;
        expect(order.claim(record.robot, fourth), isNull);
        fifthArrives.complete();
        await fifthAnswer;
        expect(order.claim(record.robot, fifth), isNotNull);
        // A request never sent, or not answered, cannot be judged.
        expect(
          () => order.claim(record.robot, order.request()),
          throwsStateError,
        );
      },
    );

    test(
      'a request sent again (a busy answer) is ranked by its last attempt: its earlier attempt does not make it older',
      () async {
        final order = TradeReadOrder();
        final app = await TradeHarness.start();
        final record = TradeHarness.recordOf(await app.takeShown());
        final now = DateTime.utc(2026, 11, 15, 12);
        final retried = order.request();
        // The first attempt is answered busy, before another request leaves and is answered.
        await order.send(retried, now, () async {});
        final other = order.request();
        await order.send(other, now, () async {});
        expect(order.claim(record.robot, other), isNull);
        // The attempt that is answered leaves after the other's answer arrived.
        await order.send(retried, now, () async {});
        expect(order.claim(record.robot, retried), isNull);
      },
    );

    test(
      'the superseded answer is given the newest stored status, with the furthest record known; another trade is not concerned',
      () async {
        final order = TradeReadOrder();
        final app = await TradeHarness.start();
        final record = TradeHarness.recordOf(await app.takeShown());
        final trade = await opened(app, record);
        final now = DateTime.utc(2026, 11, 15, 12);
        final early = order.request();
        final late = order.request();
        final earlyArrives = Completer<void>();
        final earlyAnswer = order.send(early, now, () => earlyArrives.future);
        await order.send(late, now, () async {});
        expect(order.claim(record.robot, late), isNull);
        order.stored(record, trade.seen);
        final closed = TradeRecord(
          robot: record.robot,
          coordinatorAlias: record.coordinatorAlias,
          coordinatorOnion: record.coordinatorOnion,
          orderId: record.orderId,
          role: record.role,
          origin: record.origin,
          takenAt: record.takenAt,
          confirmedAt: record.takenAt,
          closedAt: record.takenAt,
        );
        order.noted(closed);
        // An older record noted after does not take its place.
        order.noted(record);
        earlyArrives.complete();
        await earlyAnswer;
        final superseded = order.claim(record.robot, early);
        expect(superseded?.seen, same(trade.seen));
        expect(superseded?.record?.closedAt, isNotNull);
      },
    );

    test('an action of a trade: running, then ended', () async {
      final order = TradeReadOrder();
      final app = await TradeHarness.start();
      final record = TradeHarness.recordOf(await app.takeShown());
      expect(order.actionRunning(record.robot), isFalse);
      final release = Completer<void>();
      final action = order.duringAction(record.robot, () => release.future);
      expect(order.actionRunning(record.robot), isTrue);
      var ended = false;
      unawaited(order.actionEnded(record.robot).then((_) => ended = true));
      await pumpEventQueue();
      expect(ended, isFalse);
      release.complete();
      await action;
      await pumpEventQueue();
      expect(ended, isTrue);
      expect(order.actionRunning(record.robot), isFalse);
    });
  });

  group('two answers of a trade in the wrong order', () {
    test(
      'a read served at 9 whose answer arrives after a later read stored 10: superseded, nothing written, 10 stays (an edge back the trade may take)',
      () async {
        final (app, record, _, run) = await watchedAt(9);
        await run.subscription.cancel();
        final trade = await opened(app, record);
        expect(
          TradeEdges.allows(
            TradeRole.buyer,
            TradePosition.fiatSent,
            TradePosition.chatting,
          ),
          isTrue,
        );
        final earlyTimes = app.reader.request();
        final earlyArrives = Completer<void>();
        final early = read(
          app,
          record,
          earlyTimes,
          arrives: earlyArrives.future,
        );
        await app.settle();
        app.coordinator.moveTo(10);
        await app.elapse(const Duration(seconds: 10));
        final lateTimes = app.reader.request();
        final newer = await app.reader.advance(
          trade,
          await read(app, record, lateTimes),
          at: app.now,
          request: lateTimes,
          keepsTime: true,
        );
        expect(newer.stored, isTrue);
        expect(fiatSentShown(newer.trade.seen), isTrue);

        await app.elapse(const Duration(seconds: 1));
        earlyArrives.complete();
        final stale = await app.reader.advance(
          trade,
          await early,
          at: app.now,
          request: earlyTimes,
          keepsTime: true,
        );
        expect(stale.superseded, isTrue);
        expect(stale.stored, isFalse);
        expect(stale.recordProblem, isNull);
        expect(stale.trade.seen, same(newer.trade.seen));
        expect(await positionOnDisk(app, record), 'fiatSent');

        // A read that leaves after it is stored as always: the undo of « fiat sent » shows.
        app.coordinator.moveTo(9);
        final thirdTimes = app.reader.request();
        final undone = await app.reader.advance(
          stale.trade,
          await read(app, record, thirdTimes),
          at: app.now.add(const Duration(seconds: 1)),
          request: thirdTimes,
        );
        expect(undone.stored, isTrue);
        expect(undone.trade.seen.status.position, TradePosition.chatting);
      },
    );

    test(
      'the mirror: a read that left after the payout\'s request but was served before it, at 8, answers after the payout\'s answer at 9: superseded, no breach (review of #142, R3)',
      () async {
        final (app, record, _, run) = await watchedAt(8);
        await run.subscription.cancel();
        final trade = await opened(app, record);
        // The payout's request leaves first and is served later; the watch's leaves after it, is served at once, at 8, and its answer is held.
        final postTimes = app.reader.request();
        final postServed = Completer<void>();
        final post = read(app, record, postTimes, served: postServed.future);
        final watchTimes = app.reader.request();
        final watchArrives = Completer<void>();
        final watch = read(
          app,
          record,
          watchTimes,
          arrives: watchArrives.future,
        );
        await app.settle();
        app.coordinator.moveTo(9);
        postServed.complete();
        final stored = await app.reader.advance(
          trade,
          await post,
          at: app.now,
          request: postTimes,
        );
        expect(stored.stored, isTrue);
        expect(stored.trade.seen.status.position, TradePosition.chatting);
        await app.elapse(const Duration(seconds: 1));
        watchArrives.complete();
        final late = await app.reader.advance(
          stored.trade,
          await watch,
          at: app.now,
          request: watchTimes,
          keepsTime: true,
        );
        expect(late.superseded, isTrue);
        expect(late.trade.seen.status.has<TradeStatusUnexpected>(), isFalse);
        expect(await breachOnDisk(app, record), isFalse);
        expect(await positionOnDisk(app, record), 'chatting');
      },
    );

    test(
      'the older answer arrives while the newer one is still being written: judged against it all the same (review of #142, R4)',
      () async {
        final (app, record, _, run) = await watchedAt(9);
        await run.subscription.cancel();
        final trade = await opened(app, record);
        final earlyTimes = app.reader.request();
        final earlyArrives = Completer<void>();
        final early = read(
          app,
          record,
          earlyTimes,
          arrives: earlyArrives.future,
        );
        await app.settle();
        app.coordinator.moveTo(10);
        await app.elapse(const Duration(seconds: 10));
        final lateTimes = app.reader.request();
        final late = await read(app, record, lateTimes);
        earlyArrives.complete();
        final earlyAnswer = await early;
        // Both kept at once: the newer first, the older while the newer's writes run.
        final newerF = app.reader.advance(
          trade,
          late,
          at: app.now,
          request: lateTimes,
        );
        final staleF = app.reader.advance(
          trade,
          earlyAnswer,
          at: app.now.add(const Duration(milliseconds: 20)),
          request: earlyTimes,
        );
        final newer = await newerF;
        final stale = await staleF;
        expect(newer.stored, isTrue);
        expect(stale.superseded, isTrue);
        expect(await positionOnDisk(app, record), 'fiatSent');
      },
    );

    test(
      'a read that left before the end, answered after it: the end stays, with its record closed',
      () async {
        final (app, record, _, run) = await watchedAt(9);
        await run.subscription.cancel();
        final trade = await opened(app, record);
        final earlyTimes = app.reader.request();
        final earlyArrives = Completer<void>();
        final early = read(
          app,
          record,
          earlyTimes,
          arrives: earlyArrives.future,
        );
        await app.settle();
        app.coordinator.cancelByMaker();
        await app.elapse(const Duration(seconds: 10));
        final endTimes = app.reader.request();
        final end = await app.reader.advance(
          trade,
          await read(app, record, endTimes),
          at: app.now,
          request: endTimes,
        );
        expect(end.trade.seen.status.isTerminal, isTrue);
        expect(end.trade.record.closedAt, isNotNull);
        earlyArrives.complete();
        final stale = await app.reader.advance(
          trade,
          await early,
          at: app.now.add(const Duration(seconds: 1)),
          request: earlyTimes,
        );
        expect(stale.superseded, isTrue);
        expect(stale.trade.seen, same(end.trade.seen));
        expect(stale.trade.record.closedAt, isNotNull);
      },
    );

    test(
      'a run started again remembers nothing: its first read is stored over what the previous run stored',
      () async {
        final (app, record, _, run) = await watchedAt(9);
        await run.subscription.cancel();
        app.coordinator.moveTo(10);
        await app.elapse(const Duration(seconds: 10));
        final beforeTimes = app.reader.request();
        final before = await app.reader.advance(
          await opened(app, record),
          await read(app, record, beforeTimes),
          at: app.now,
          request: beforeTimes,
        );
        expect(fiatSentShown(before.trade.seen), isTrue);
        app.coordinator.moveTo(9);
        await app.elapse(const Duration(seconds: 1));
        final again = app.restart();
        final times = again.reader.request();
        final step = await again.reader.advance(
          await opened(again, record),
          await read(again, record, times),
          at: again.now,
          request: times,
        );
        expect(step.stored, isTrue);
        expect(step.trade.seen.status.position, TradePosition.chatting);
      },
    );
  });

  group('the watch and the actions of its trade', () {
    test(
      'the payout\'s fresh read left first, its answer held; the screen asks the watch to read: nothing leaves while the payout runs, the payout goes on, and the watch reads once it ended (review of #142, R1)',
      () async {
        final signals = StreamController<TradeWatchSignal>.broadcast();
        final (app, record, seen, run) = await watchedAt(
          8,
          signals: signals.stream,
        );
        final shown = shownPayout(app, record, seen);
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.answerDelayed,
        );
        final reads = orderReads(app);
        final given = app.payout.execute(record, shown);
        await app.settle();
        expect(orderReads(app), reads + 1);
        signals.add(TradeWatchSignal.readNow);
        await app.settle();
        // Held back: no read of the watch left.
        expect(orderReads(app), reads + 1);
        app.coordinator.deliverDelayed();
        final outcome = await given;
        expect(
          outcome,
          isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
            (ok) => ok.value,
            'outcome',
            isA<PayoutGiven>(),
          ),
        );
        // The fresh read, then the read after: the watch's comes once the payout ended.
        await app.settle();
        expect(orderReads(app), reads + 3);
        expect(run.lastStatus.seen.status.position, TradePosition.chatting);
        await run.subscription.cancel();
        await signals.close();
      },
    );

    test(
      'a read of the watch sent at 8 before the payout began, answered after the payout\'s read after at 9: superseded, the watch says nothing, then shows 9 at its next read; no breach',
      () async {
        final (app, record, seen, run) = await watchedAt(8);
        final states = run.states.length;
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.answerDelayed,
        );
        await app.elapse(const Duration(minutes: 1));
        final given = await app.payout.execute(
          record,
          shownPayout(app, record, seen),
        );
        expect(
          given,
          isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
            (ok) => ok.value,
            'outcome',
            isA<PayoutGiven>().having(
              (g) => g.seen.status.position,
              'position',
              TradePosition.chatting,
            ),
          ),
        );
        await app.elapse(const Duration(seconds: 1));
        app.coordinator.deliverDelayed();
        await app.settle();
        // Superseded: nothing said, nothing written.
        expect(run.states.length, states);
        expect(await positionOnDisk(app, record), 'chatting');
        expect(await breachOnDisk(app, record), isFalse);
        await app.elapse(const Duration(minutes: 1));
        expect(run.lastStatus.seen.status.position, TradePosition.chatting);
        expect(
          run.lastStatus.seen.status.has<CoordinatorInconsistent>(),
          isFalse,
        );
        await run.subscription.cancel();
      },
    );

    test(
      'the payout\'s fresh read superseded by a read of the watch that left before the payout began and answered first: read once more, and the payout goes on from it',
      () async {
        final (app, record, seen, run) = await watchedAt(8);
        // The watch's read, then the payout's fresh read: both answers held.
        app.coordinator
          ..failNext(ScriptedRequest.order, ScriptedFault.answerDelayed)
          ..failNext(ScriptedRequest.order, ScriptedFault.answerDelayed);
        await app.elapse(const Duration(minutes: 1));
        final reads = orderReads(app);
        final given = app.payout.execute(
          record,
          shownPayout(app, record, seen),
        );
        await app.settle();
        expect(orderReads(app), reads + 1);
        // The watch's answer first, stored; then the payout's, superseded.
        app.coordinator.deliverDelayed(1);
        await app.settle();
        app.coordinator.deliverDelayed();
        final outcome = await given;
        expect(
          outcome,
          isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
            (ok) => ok.value,
            'outcome',
            isA<PayoutGiven>(),
          ),
        );
        // The fresh read, once more, and the read after.
        expect(orderReads(app), reads + 3);
        expect(app.coordinator.payoutsRecorded, hasLength(1));
        await run.subscription.cancel();
      },
    );

    test(
      'the screen asks the watch to read between the payout and its read after: nothing leaves then, and the read after is stored (no read can overtake it)',
      () async {
        final signals = StreamController<TradeWatchSignal>.broadcast();
        final (app, record, seen, run) = await watchedAt(
          8,
          signals: signals.stream,
        );
        var asked = false;
        app.coordinator.onRequest = (request) {
          final body = request.body;
          final decoded = body == null ? null : jsonDecode(utf8.decode(body));
          if (decoded is Map<String, Object?> &&
              decoded['action'] == 'update_invoice') {
            signals.add(TradeWatchSignal.readNow);
            asked = true;
          }
        };
        final reads = orderReads(app);
        final given = await app.payout.execute(
          record,
          shownPayout(app, record, seen),
        );
        app.coordinator.onRequest = null;
        expect(asked, isTrue);
        final after = switch (given) {
          Ok(value: PayoutGiven(:final seen)) => seen,
          final other => fail('$other'),
        };
        expect(after.stored, isTrue);
        expect(after.status.position, TradePosition.chatting);
        await app.settle();
        // The fresh read, the read after, then the watch's, once the payout ended.
        expect(orderReads(app), reads + 3);
        await run.subscription.cancel();
        await signals.close();
      },
    );

    test(
      'a read that left between the payout\'s request and its read after, answered after that read: superseded, the read after stays',
      () async {
        final (app, record, seen, run) = await watchedAt(8);
        await run.subscription.cancel();
        RequestTimes? otherTimes;
        Future<TradeAnswer>? other;
        final otherArrives = Completer<void>();
        var payoutIn = false;
        app.coordinator.onRequest = (request) {
          final body = request.body;
          final decoded = body == null ? null : jsonDecode(utf8.decode(body));
          if (decoded is Map<String, Object?> &&
              decoded['action'] == 'update_invoice') {
            final times = otherTimes = app.reader.request();
            other = read(app, record, times, arrives: otherArrives.future);
            payoutIn = true;
          } else if (payoutIn &&
              body == null &&
              request.url.path.endsWith('/api/order/')) {
            app.coordinator.moveTo(10);
          }
        };
        final given = await app.payout.execute(
          record,
          shownPayout(app, record, seen),
        );
        app.coordinator.onRequest = null;
        final after = switch (given) {
          Ok(value: PayoutGiven(:final seen)) => seen,
          final other => fail('$other'),
        };
        expect(fiatSentShown(after), isTrue);
        otherArrives.complete();
        final stale = await app.reader.advance(
          await opened(app, record),
          await (other ?? fail('no other read')),
          at: app.now.add(const Duration(seconds: 1)),
          request: otherTimes ?? fail('no other read'),
        );
        expect(stale.superseded, isTrue);
        expect(fiatSentShown(stale.trade.seen), isTrue);
        expect(await positionOnDisk(app, record), 'fiatSent');
      },
    );

    test(
      'a read of the watch sent at 9 before « fiat sent », answered after it stored 10: superseded, nothing written, « Confirm … sent » not offered again, no breach',
      () async {
        final (app, record, seen, run) = await watchedAt(9);
        expect(ChatStepAction.confirmFiatSent.offeredAt(seen), isTrue);
        final states = run.states.length;
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.answerDelayed,
        );
        await app.elapse(const Duration(minutes: 1));
        final done = switch (await app.chat.confirmFiatSent(record, seen)) {
          Ok(value: final ChatStepDone done) => done,
          final other => fail('$other'),
        };
        expect(fiatSentShown(done.seen), isTrue);
        final trailBefore = switch (await app.trails.historyOf(record)) {
          Ok(:final value) => value.trail,
          Err(:final failure) => fail('$failure'),
        };
        await app.elapse(const Duration(seconds: 1));
        app.coordinator.deliverDelayed();
        await app.settle();
        expect(run.states.length, states);
        final trailAfter = switch (await app.trails.historyOf(record)) {
          Ok(:final value) => value.trail,
          Err(:final failure) => fail('$failure'),
        };
        expect(trailAfter, trailBefore);
        expect(await breachOnDisk(app, record), isFalse);
        await app.elapse(const Duration(minutes: 1));
        expect(fiatSentShown(run.lastStatus.seen), isTrue);
        expect(
          ChatStepAction.confirmFiatSent.offeredAt(run.lastStatus.seen),
          isFalse,
        );
        await run.subscription.cancel();
      },
    );

    test(
      '« fiat sent » that landed late, found by a second tap\'s read: a read of the watch sent at 9 before both, answered after, never takes 10 back',
      () async {
        final (app, record, seen, run) = await watchedAt(9);
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.answerDelayed,
        );
        await app.elapse(const Duration(minutes: 1));
        app.coordinator.failNext(
          ScriptedRequest.confirm,
          ScriptedFault.landsLate,
        );
        final unknown = switch (await app.chat.confirmFiatSent(record, seen)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(fiatSentShown(unknown.seen), isFalse);
        app.coordinator.landLate();
        final done = switch (await app.chat.confirmFiatSent(
          record,
          unknown.seen,
        )) {
          Ok(value: final ChatStepDone done) => done,
          final other => fail('$other'),
        };
        expect(fiatSentShown(done.seen), isTrue);
        await app.elapse(const Duration(seconds: 1));
        app.coordinator.deliverDelayed();
        await app.settle();
        await app.elapse(const Duration(minutes: 1));
        expect(fiatSentShown(run.lastStatus.seen), isTrue);
        expect(await positionOnDisk(app, record), 'fiatSent');
        expect(await breachOnDisk(app, record), isFalse);
        await run.subscription.cancel();
      },
    );

    test(
      'the fresh read of « fiat sent » superseded by a read of the watch that left before it and answered first: read once more, and sent from it',
      () async {
        final (app, record, seen, run) = await watchedAt(9);
        app.coordinator
          ..failNext(ScriptedRequest.order, ScriptedFault.answerDelayed)
          ..failNext(ScriptedRequest.order, ScriptedFault.answerDelayed);
        await app.elapse(const Duration(minutes: 1));
        final reads = orderReads(app);
        final confirmed = app.chat.confirmFiatSent(record, seen);
        await app.settle();
        expect(orderReads(app), reads + 1);
        app.coordinator.deliverDelayed(1);
        await app.settle();
        app.coordinator.deliverDelayed();
        final done = switch (await confirmed) {
          Ok(value: final ChatStepDone done) => done,
          final other => fail('$other'),
        };
        expect(fiatSentShown(done.seen), isTrue);
        expect(orderReads(app), reads + 3);
        expect(
          app.coordinator.received
              .where((kind) => kind == ScriptedRequest.confirm)
              .length,
          1,
        );
        await run.subscription.cancel();
      },
    );

    test(
      'a read of the watch sent before a cancel, answered after the cancel\'s read after: superseded, the cancel\'s end stays',
      () async {
        final app = await TradeHarness.start();
        final taken = await app.takeShown();
        final record = TradeHarness.recordOf(taken);
        final run = app.watchOf(record);
        await app.settle();
        final seen = run.lastStatus.seen;
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.answerDelayed,
        );
        await app.elapse(const Duration(seconds: 10));
        final cancelled = await app.cancel.execute(run.lastStatus.record, seen);
        final end = switch (cancelled) {
          Ok(value: CancelDone(:final seen)) => seen,
          final other => fail('$other'),
        };
        expect(end.status.isTerminal, isTrue);
        app.coordinator.deliverDelayed();
        await app.settle();
        expect(run.lastStatus.seen.status.isTerminal, isTrue);
        expect(await breachOnDisk(app, record), isFalse);
        await run.subscription.cancel();
      },
    );
  });
}
