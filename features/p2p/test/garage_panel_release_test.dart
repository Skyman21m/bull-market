import 'dart:async';

import 'package:p2p/src/domain/coordinator_sessions_port.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_request_limiter.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/close_robot_sessions_usecase.dart';
import 'package:p2p/src/domain/usecases/release_robot_usecase.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// The sessions of the transport, whose closes the tests note.
final class _Sessions implements CoordinatorSessionsPort {
  final List<RobotSessionKey> closed = [];

  @override
  Future<void> closeSessions() async {}

  @override
  Future<void> closeRobotSessions(RobotSessionKey robot) async =>
      closed.add(robot);
}

/// The Garage's panel of a trade's robot closing while the trade goes on (#251, security review of PR 274, C1): its release stops the panel's calls only, never the watch of the trade's page, its chat, or an action of the trade in flight or waiting for its place; the robot's sessions are closed once the trade's last call has ended. Over the real use cases, limiter, records and trails of the harness, the coordinator played by `ScriptedCoordinator`.
void main() {
  int sent(TradeHarness app, ScriptedRequest kind) =>
      app.coordinator.received.where((k) => k == kind).length;

  /// A trade taken here at [status], its page's watch running, as the trade screen keeps it.
  Future<(TradeHarness, TradeRecord, TradeSeen, WatchRun)> watchedAt(
    int status,
  ) async {
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
    expect(last.stored, isTrue);
    return (app, last.record, last.seen, run);
  }

  /// The Garage's panel of the trade's robot closing: a release of that panel's calls, as `RobotCoordinatorCubit.close` makes it.
  Future<void> panelCloses(TradeHarness app, _Sessions sessions) async {
    final robot = switch (await app.robots.robotOfSlot(
      (await app.activeRecords()).single.robot,
    )) {
      Ok(:final value) => value,
      Err(:final failure) => fail('$failure'),
    };
    final owner = RobotCallOwner();
    // The panel's own call, waiting on the trade's robot when it closes.
    final panelCall = app.limiter.open(robot.identity.sessionKey, owner: owner);
    await ReleaseRobotUsecase(
      app.limiter,
      CloseRobotSessionsUsecase(sessions),
    ).execute(robot, owner: owner);
    expect(
      await panelCall.send(
        app.network,
        app.coordinator.coordinator,
        () async => 'panel',
        isBusy: (_) => false,
      ),
      isA<Err<String, P2pFailure>>().having(
        (err) => err.failure,
        'failure',
        isA<RobotReleasedFailure>(),
      ),
    );
  }

  test(
    'the page\'s watch reads on, as often as without the panel, and its sessions are closed only once the page is gone',
    () async {
      final (app, _, _, run) = await watchedAt(9);
      final sessions = _Sessions();
      final before = sent(app, ScriptedRequest.order);
      await panelCloses(app, sessions);
      for (var i = 0; i < 24; i++) {
        await app.elapse(const Duration(seconds: 5));
      }
      final reads = sent(app, ScriptedRequest.order) - before;
      // The cadence at 9 on screen: a read every 10 s or less.
      expect(reads, greaterThanOrEqualTo(10));
      expect(run.lastStatus.failedReads, 0);
      expect(run.lastStatus.lastReadFailure, isNull);
      expect(sessions.closed, isEmpty);
      // The peer moves the trade on: the page shows it.
      app.coordinator.moveTo(10);
      await app.elapse(const Duration(seconds: 15));
      expect(run.lastStatus.seen.status.position.name, 'fiatSent');
      await run.subscription.cancel();
      await app.settle();
      expect(sessions.closed, [app.robot(0).sessionKey]);
    },
  );

  test(
    'the chat of the trade reads on: one read in flight when the panel closes ends with its page, and the next one leaves',
    () async {
      final (app, record, seen, run) = await watchedAt(9);
      final sessions = _Sessions();
      app.coordinator.failNext(
        ScriptedRequest.chat,
        ScriptedFault.answerDelayed,
      );
      final reading = app.chatRead.read(record, seen);
      await app.settle();
      expect(sent(app, ScriptedRequest.chat), 1);
      await panelCloses(app, sessions);
      app.coordinator.deliverDelayed();
      expect(await reading, isA<Ok<Object?, Object?>>());
      expect(
        await app.chatRead.read(record, seen),
        isA<Ok<Object?, Object?>>(),
      );
      expect(sent(app, ScriptedRequest.chat), 2);
      expect(sessions.closed, isEmpty);
      await run.subscription.cancel();
    },
  );

  test(
    'an action of the trade in flight when the panel closes is answered and kept',
    () async {
      final (app, record, seen, run) = await watchedAt(9);
      final sessions = _Sessions();
      app.coordinator.failNext(
        ScriptedRequest.cancel,
        ScriptedFault.answerDelayed,
      );
      final asking = app.cancel.execute(record, seen);
      await app.settle();
      expect(sent(app, ScriptedRequest.cancel), 1);
      await panelCloses(app, sessions);
      app.coordinator.deliverDelayed();
      expect(
        await asking,
        isA<Ok<CancelOutcome, CancelRefusal>>().having(
          (ok) => ok.value,
          'outcome',
          isA<CancelDone>(),
        ),
      );
      expect(sessions.closed, isEmpty);
      await run.subscription.cancel();
    },
  );

  test(
    'an action of the trade waiting for its place when the panel closes leaves once a place is free, and is answered',
    () async {
      final (app, record, seen, run) = await watchedAt(9);
      final sessions = _Sessions();
      // Both places of the coordinator held by requests of other robots.
      final gates = [Completer<String>(), Completer<String>()];
      final holding = [
        for (var i = 0; i < 2; i++)
          app.limiter
              .open(app.robot(i + 1).sessionKey)
              .send(
                app.network,
                app.coordinator.coordinator,
                () => gates[i].future,
                isBusy: (_) => false,
              ),
      ];
      await app.settle();
      final sentBefore = app.coordinator.received.length;
      final asking = app.cancel.execute(record, seen);
      await app.settle();
      // Waiting: nothing of it left yet.
      expect(app.coordinator.received.length, sentBefore);
      await panelCloses(app, sessions);
      gates[0].complete('1');
      gates[1].complete('2');
      await Future.wait(holding);
      expect(
        await asking,
        isA<Ok<CancelOutcome, CancelRefusal>>().having(
          (ok) => ok.value,
          'outcome',
          isA<CancelDone>(),
        ),
      );
      expect(sent(app, ScriptedRequest.cancel), 1);
      expect(sessions.closed, isEmpty);
      await run.subscription.cancel();
    },
  );
}
