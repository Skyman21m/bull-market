import 'dart:async';

import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_chat_step.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// « Payment failed? » and the collaborative cancel kept in the order the coordinator served their answers (#141, #95): their reads are ranked as every read of a trade is, so that a read of the watch that left before them and answers after them is superseded, and the watch sends no read while they run; over the coordinator the tests play (never a real coordinator).
void main() {
  /// A trade taken on a fresh run, its bond locked, at [status] as the watch stored it, the peer's ask of a collaborative cancel raised when [peerAsked], the watch still running, told [signals].
  Future<(TradeHarness, TradeRecord, TradeSeen, WatchRun)> watchedAt(
    int status, {
    bool peerAsked = false,
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
    if (peerAsked) app.coordinator.peerAsksToCancel();
    await app.elapse(const Duration(seconds: 5));
    final last = run.lastStatus;
    expect(last.stored, isTrue);
    return (app, last.record, last.seen, run);
  }

  int sent(TradeHarness app, ScriptedRequest kind) =>
      app.coordinator.received.where((k) => k == kind).length;

  int orderReads(TradeHarness app) => sent(app, ScriptedRequest.order);

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

  bool fiatSentShown(TradeSeen seen) => switch (seen.status) {
    Chatting(:final fiatSent) => fiatSent,
    _ => false,
  };

  bool askShown(TradeSeen seen) => switch (seen.status) {
    Chatting(:final askedToCancel) => askedToCancel,
    _ => false,
  };

  group('« Payment failed? »', () {
    test(
      'a read of the watch sent at 10 before the undo, answered after the undo\'s read after stored 9: superseded, nothing written, « fiat sent » not shown again, no breach',
      () async {
        final (app, record, seen, run) = await watchedAt(10);
        expect(ChatStepAction.undoFiatSent.offeredAt(seen), isTrue);
        final states = run.states.length;
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.answerDelayed,
        );
        await app.elapse(const Duration(minutes: 1));
        final done = switch (await app.chat.undoFiatSent(record, seen)) {
          Ok(value: final ChatStepDone done) => done,
          final other => fail('$other'),
        };
        expect(done.seen.stored, isTrue);
        expect(fiatSentShown(done.seen), isFalse);
        expect(await positionOnDisk(app, record), 'chatting');
        await app.elapse(const Duration(seconds: 1));
        app.coordinator.deliverDelayed();
        await app.settle();
        // Superseded: the watch says nothing, nothing is written.
        expect(run.states.length, states);
        expect(await positionOnDisk(app, record), 'chatting');
        expect(await breachOnDisk(app, record), isFalse);
        await app.elapse(const Duration(minutes: 1));
        expect(fiatSentShown(run.lastStatus.seen), isFalse);
        expect(
          run.lastStatus.seen.status.has<CoordinatorInconsistent>(),
          isFalse,
        );
        await run.subscription.cancel();
      },
    );

    test(
      'the screen asks the watch to read while the undo\'s answer is on its way: nothing leaves until the undo ended, then the watch reads',
      () async {
        final signals = StreamController<TradeWatchSignal>.broadcast();
        final (app, record, seen, run) = await watchedAt(
          10,
          signals: signals.stream,
        );
        app.coordinator.failNext(
          ScriptedRequest.undoConfirm,
          ScriptedFault.answerDelayed,
        );
        final reads = orderReads(app);
        final undone = app.chat.undoFiatSent(record, seen);
        await app.settle();
        // The fresh read, then the undo, whose answer is held.
        expect(orderReads(app), reads + 1);
        expect(sent(app, ScriptedRequest.undoConfirm), 1);
        signals.add(TradeWatchSignal.readNow);
        await app.settle();
        // Held back: no read of the watch left.
        expect(orderReads(app), reads + 1);
        app.coordinator.deliverDelayed();
        final done = switch (await undone) {
          Ok(value: final ChatStepDone done) => done,
          final other => fail('$other'),
        };
        expect(done.seen.stored, isTrue);
        expect(fiatSentShown(done.seen), isFalse);
        // The read after, then the watch's once the undo ended.
        await app.settle();
        expect(orderReads(app), reads + 3);
        expect(fiatSentShown(run.lastStatus.seen), isFalse);
        expect(sent(app, ScriptedRequest.undoConfirm), 1);
        await run.subscription.cancel();
        await signals.close();
      },
    );

    test(
      'the undo\'s fresh read superseded by a read of the watch that left before it and answered first: read once more, and sent once from it',
      () async {
        final (app, record, seen, run) = await watchedAt(10);
        app.coordinator
          ..failNext(ScriptedRequest.order, ScriptedFault.answerDelayed)
          ..failNext(ScriptedRequest.order, ScriptedFault.answerDelayed);
        await app.elapse(const Duration(minutes: 1));
        final reads = orderReads(app);
        final undone = app.chat.undoFiatSent(record, seen);
        await app.settle();
        expect(orderReads(app), reads + 1);
        // The watch's answer first, stored; then the undo's fresh read, superseded.
        app.coordinator.deliverDelayed(1);
        await app.settle();
        app.coordinator.deliverDelayed();
        final done = switch (await undone) {
          Ok(value: final ChatStepDone done) => done,
          final other => fail('$other'),
        };
        expect(fiatSentShown(done.seen), isFalse);
        // The fresh read, once more, and the read after.
        expect(orderReads(app), reads + 3);
        expect(sent(app, ScriptedRequest.undoConfirm), 1);
        await run.subscription.cancel();
      },
    );
  });

  group('the collaborative cancel', () {
    test(
      'a read of the watch sent at 9 before the ask, answered after the ask\'s read after showed it: superseded, the ask stays shown, no breach',
      () async {
        final (app, record, seen, run) = await watchedAt(9);
        expect(askShown(seen), isFalse);
        final states = run.states.length;
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.answerDelayed,
        );
        await app.elapse(const Duration(minutes: 1));
        final asked = switch (await app.cancel.execute(record, seen)) {
          Ok(value: final CancelDone done) => done,
          final other => fail('$other'),
        };
        expect(asked.seen.stored, isTrue);
        expect(askShown(asked.seen), isTrue);
        await app.elapse(const Duration(seconds: 1));
        // The watch's answer, read before the ask: this robot's flag down.
        app.coordinator.deliverDelayed();
        await app.settle();
        expect(run.states.length, states);
        expect(await breachOnDisk(app, record), isFalse);
        await app.elapse(const Duration(minutes: 1));
        expect(askShown(run.lastStatus.seen), isTrue);
        expect(sent(app, ScriptedRequest.cancel), 1);
        await run.subscription.cancel();
      },
    );

    test(
      'the peer asked first, this robot\'s ask cancels for both: a read of the watch sent at 9 before it, answered after, never takes the end back',
      () async {
        final (app, record, seen, run) = await watchedAt(9, peerAsked: true);
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.answerDelayed,
        );
        await app.elapse(const Duration(minutes: 1));
        final end = switch (await app.cancel.execute(record, seen)) {
          Ok(value: final CancelDone done) => done,
          final other => fail('$other'),
        };
        expect(end.seen.status, isA<Cancelled>());
        expect(end.record.closedAt, isNotNull);
        app.coordinator.deliverDelayed();
        await app.settle();
        expect(run.lastStatus.seen.status, isA<Cancelled>());
        expect(await breachOnDisk(app, record), isFalse);
        await run.subscription.cancel();
      },
    );

    test(
      'the screen asks the watch to read while the ask\'s answer is on its way: nothing leaves until the ask ended, then the watch reads',
      () async {
        final signals = StreamController<TradeWatchSignal>.broadcast();
        final (app, record, seen, run) = await watchedAt(
          9,
          signals: signals.stream,
        );
        app.coordinator.failNext(
          ScriptedRequest.cancel,
          ScriptedFault.answerDelayed,
        );
        final reads = orderReads(app);
        final asking = app.cancel.execute(record, seen);
        await app.settle();
        expect(sent(app, ScriptedRequest.cancel), 1);
        expect(orderReads(app), reads);
        signals.add(TradeWatchSignal.readNow);
        await app.settle();
        // Held back: no read of the watch left.
        expect(orderReads(app), reads);
        app.coordinator.deliverDelayed();
        final asked = switch (await asking) {
          Ok(value: final CancelDone done) => done,
          final other => fail('$other'),
        };
        expect(asked.seen.stored, isTrue);
        expect(askShown(asked.seen), isTrue);
        // The read after, then the watch's once the ask ended.
        await app.settle();
        expect(orderReads(app), reads + 2);
        expect(askShown(run.lastStatus.seen), isTrue);
        await run.subscription.cancel();
        await signals.close();
      },
    );
  });
}
