import 'dart:async';

import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_payout_outcome.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/trade_read_order.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_panel.dart';
import 'package:p2p/testing.dart'
    show Bolt11TestInvoice, ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RoutingBudgetPpm;
import 'package:test/test.dart';

import 'support/trade_harness.dart';
import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

/// #152 (from #148): a trade screen whose app was hidden then shown again, or which is opened again in the same run, keeps the last full status this run read while its first read is in flight, silently, as the official client keeps the order it shows while it reads it again (`frontend/src/basic/OrderPage/index.tsx:76-96`, a failed read keeping the order as it is, `frontend/src/models/Order.model.ts:264-281`).
///
/// Over the real watch (`WatchTradeUsecase`, its reader and records, the coordinator played by `ScriptedCoordinator`); what the screen draws is [TradeView.of] of the cubit's watch state, read at each moment.
void main() {
  // The order of the scripted coordinator once the bond locks: the buyer receives 106,713 sats (`trade_payout_test.dart`).
  const buyerSats = 106713;
  var seed = 1520;

  /// The trade's cubit over [harness]'s real watch and actions, as the locator builds it.
  TradeCubit cubitOf(TradeHarness harness, TradeRecord record) => TradeCubit(
    record,
    harness.watch.execute,
    harness.cancel.execute,
    confirmFiatSent: harness.chat.confirmFiatSent,
    lastStored: harness.watch.lastStored,
  );

  /// A take of the coordinator's order by a new robot, and the trade's cubit.
  Future<(TradeHarness, TradeCubit)> taken() async {
    final harness = await TradeHarness.start();
    final record = TradeHarness.recordOf(await harness.takeShown());
    return (harness, cubitOf(harness, record));
  }

  /// [cubit] started and shown at the bond step, then moved on to [status] by the coordinator and read.
  Future<void> shownAt(
    TradeHarness harness,
    TradeCubit cubit,
    int status,
  ) async {
    cubit.start();
    await harness.settle();
    if (status == 3) return;
    harness.coordinator.lockBond(harness.robot(0));
    if (status != 6) harness.coordinator.moveTo(status);
    cubit.signal(TradeWatchSignal.readNow);
    await harness.settle();
  }

  /// What the screen draws for [cubit]'s state now.
  TradeView viewOf(TradeCubit cubit) => TradeView.of(cubit.state.watch);

  /// Every view [cubit] gives while [during] runs.
  Future<List<TradeView>> viewsDuring(
    TradeCubit cubit,
    Future<void> Function() during,
  ) async {
    final views = <TradeView>[];
    final listening = cubit.stream.listen(
      (state) => views.add(TradeView.of(state.watch)),
    );
    await during();
    await listening.cancel();
    return views;
  }

  /// Requests of [kind] the coordinator received.
  int received(TradeHarness harness, ScriptedRequest kind) =>
      harness.coordinator.received.where((r) => r == kind).length;

  group('#152: back in the app, the process alive', () {
    test(
      'the bond step shown, the first read after the return held: the screen keeps the bond step, never the first read\'s wait',
      () async {
        final (harness, cubit) = await taken();
        await shownAt(harness, cubit, 3);
        final shown = cubit.state.seen;
        expect(shown?.status, isA<WaitingForTakerBond>());

        // The buyer leaves to pay the bond with another wallet app.
        await cubit.suspend();
        await harness.elapse(const Duration(seconds: 20));

        // Back in the app: Tor wakes, the first read takes its time.
        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        late TradeView whileReading;
        final views = await viewsDuring(cubit, () async {
          cubit.resume();
          await harness.settle();
          whileReading = viewOf(cubit);
          expect(cubit.state.seen, same(shown));
          held.complete();
          harness.coordinator.hold = null;
          await harness.settle();
        });

        expect(
          views.whereType<TradeWaiting>(),
          isEmpty,
          reason:
              'the screen fell back to « Your robot reads the order » after the return: ${views.map((v) => v.runtimeType).toList()}',
        );
        expect(whileReading, isA<TradeContract>());
        // The read is in: the status shown is that read's.
        expect(cubit.state.seen?.status, isA<WaitingForTakerBond>());
        expect(cubit.state.seen, isNot(same(shown)));
        await cubit.close();
      },
    );

    test(
      'status 6 shown (the payout form), the reads after the return failing: the last status stays with « cannot reach », never the wait',
      () async {
        final (harness, cubit) = await taken();
        await shownAt(harness, cubit, 6);
        expect(cubit.state.seen?.status, isA<WaitingForBoth>());

        await cubit.suspend();
        await harness.elapse(const Duration(minutes: 1));

        // Back in the app: the coordinator cannot be reached, three times.
        for (var i = 0; i < 3; i++) {
          harness.coordinator.failNext(
            ScriptedRequest.order,
            ScriptedFault.unreachable,
          );
        }
        final views = await viewsDuring(cubit, () async {
          cubit.resume();
          await harness.settle();
          for (var i = 0; i < 2; i++) {
            await harness.elapse(const Duration(seconds: 10));
            await harness.settle();
          }
        });

        final watch = cubit.state.watch;
        expect(watch, isA<TradeWatchStatus>());
        expect((watch! as TradeWatchStatus).failedReads, 3);
        expect(
          views.whereType<TradeWaiting>(),
          isEmpty,
          reason:
              'the screen fell back to « Your robot reads the order » after the return: ${views.map((v) => v.runtimeType).toList()}',
        );
        // The status 6 the user saw, with its age: the screen says it cannot reach the coordinator above it (#87).
        expect(cubit.state.seen?.status, isA<WaitingForBoth>());
        await cubit.close();
      },
    );

    test(
      'the bond locked while the buyer was in his other wallet (3 → 6): the watch opened again gives the stored trail at 3, the position shown, never 6',
      () async {
        final (harness, cubit) = await taken();
        await shownAt(harness, cubit, 3);
        final record = cubit.state.record;
        await cubit.suspend();

        // Paid from the other wallet: the coordinator moved on while nothing read.
        harness.coordinator.lockBond(harness.robot(0));
        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        final first = await harness.watch.execute(record).first;

        // Nothing read while away, so the trail on disk is still at the position shown.
        expect(first, isA<TradeWatchStatus>());
        final seen = (first as TradeWatchStatus).seen;
        expect(seen.status, isA<StatusUnknown>());
        expect(seen.status.position, TradePosition.bondStep);
        expect(seen.stored, isFalse);
        held.complete();
        harness.coordinator.hold = null;
        await harness.settle();
        await cubit.close();
      },
    );

    test(
      'the bond locked while away (3 → 6), the first read after the return held: the last status shown stays until the read, then 6',
      () async {
        final (harness, cubit) = await taken();
        await shownAt(harness, cubit, 3);
        await cubit.suspend();
        harness.coordinator.lockBond(harness.robot(0));

        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        late TradeView whileReading;
        final views = await viewsDuring(cubit, () async {
          cubit.resume();
          await harness.settle();
          whileReading = viewOf(cubit);
          held.complete();
          harness.coordinator.hold = null;
          await harness.settle();
        });

        expect(
          views.whereType<TradeWaiting>(),
          isEmpty,
          reason:
              'the screen fell back to « Your robot reads the order » after the return: ${views.map((v) => v.runtimeType).toList()}',
        );
        expect(whileReading, isA<TradeContract>());
        expect(cubit.state.seen?.status, isA<WaitingForBoth>());
        await cubit.close();
      },
    );

    test(
      'a status 6 stored by another screen of this run while away (its read superseding what this one showed): the return shows 6 at once, never the older bond step',
      () async {
        final (harness, cubit) = await taken();
        await shownAt(harness, cubit, 3);
        final record = cubit.state.record;
        await cubit.suspend();

        // Another subscription of this run reads 6 and stores it, then goes.
        harness.coordinator.lockBond(harness.robot(0));
        final other = harness.watchOf(record);
        await harness.settle();
        expect(other.lastStatus.seen.status, isA<WaitingForBoth>());
        await other.subscription.cancel();

        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        final views = await viewsDuring(cubit, () async {
          cubit.resume();
          await harness.settle();
          expect(cubit.state.seen?.status, isA<WaitingForBoth>());
          held.complete();
          harness.coordinator.hold = null;
          await harness.settle();
        });
        expect(views.map((v) => v.runtimeType).toSet(), {
          TradeContract,
        }, reason: 'the views: $views');
        expect(
          views.whereType<TradeContract>().where(
            (v) => v.status is WaitingForTakerBond,
          ),
          isEmpty,
        );
        await cubit.close();
      },
    );

    test(
      'the trade ended while away (the pre-take expired, read by another screen): the return shows its end, not the kept bond step',
      () async {
        final (harness, cubit) = await taken();
        await shownAt(harness, cubit, 3);
        final record = cubit.state.record;
        await cubit.suspend();

        await harness.elapse(const Duration(minutes: 5));
        final other = harness.watchOf(record);
        await harness.settle();
        expect(other.lastStatus.seen.status.isTerminal, isTrue);
        await other.subscription.cancel();
        expect(harness.watch.lastStored(record), isNull);

        final views = await viewsDuring(cubit, () async {
          cubit.resume();
          await harness.settle();
        });
        expect(views, isNotEmpty);
        expect(viewOf(cubit), isA<TradeMessage>());
        expect(
          views.whereType<TradeContract>().where(
            (v) => v.status is WaitingForTakerBond,
          ),
          isEmpty,
        );
        await cubit.close();
      },
    );
  });

  group('#152: after a write that failed, nothing older comes back (review)', () {
    /// The bond step shown, then a read of 6 whose trail cannot be written: the screen shows the wait.
    Future<(TradeHarness, TradeCubit)> failedWriteAtSix() async {
      final (harness, cubit) = await taken();
      await shownAt(harness, cubit, 3);
      expect(
        viewOf(cubit),
        isA<TradeContract>().having((c) => c.payable, 'payable', isTrue),
      );
      harness.trails.storeFailure = const P2pStorageFailure();
      harness.coordinator.lockBond(harness.robot(0));
      cubit.signal(TradeWatchSignal.readNow);
      await harness.settle();
      expect(viewOf(cubit), isA<TradeWaiting>());
      expect(harness.watch.lastStored(cubit.state.record), isNull);
      return (harness, cubit);
    }

    test(
      'then a return, the write working again and the first read held: the wait, never the bond step read before 6',
      () async {
        final (harness, cubit) = await failedWriteAtSix();
        await cubit.suspend();
        harness.trails.storeFailure = null;
        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        cubit.resume();
        await harness.settle();
        expect(viewOf(cubit), isA<TradeWaiting>());
        held.complete();
        harness.coordinator.hold = null;
        await harness.settle();
        expect(cubit.state.seen?.status, isA<WaitingForBoth>());
        await cubit.close();
      },
    );

    test(
      'then a read that fails, with no return: the wait, never the bond step read before 6',
      () async {
        final (harness, cubit) = await failedWriteAtSix();
        harness.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.unreachable,
        );
        cubit.signal(TradeWatchSignal.readNow);
        await harness.settle();
        final watch = cubit.state.watch;
        expect(watch, isA<TradeWatchStatus>());
        expect((watch! as TradeWatchStatus).failedReads, 1);
        expect(viewOf(cubit), isA<TradeWaiting>());
        await cubit.close();
      },
    );

    test(
      'once a later write succeeds, the memory is that status, and a return keeps it',
      () async {
        final (harness, cubit) = await failedWriteAtSix();
        harness.trails.storeFailure = null;
        cubit.signal(TradeWatchSignal.readNow);
        await harness.settle();
        final six = cubit.state.seen;
        expect(six?.status, isA<WaitingForBoth>());
        expect(harness.watch.lastStored(cubit.state.record), same(six));

        await cubit.suspend();
        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        cubit.resume();
        await harness.settle();
        expect(cubit.state.seen, same(six));
        expect(viewOf(cubit), isA<TradeContract>());
        held.complete();
        harness.coordinator.hold = null;
        await harness.settle();
        await cubit.close();
      },
    );
  });

  group('#152: the trade opened again in the same run', () {
    test(
      'the trade\'s route left (the Wallet tab, or back) and opened again by « Order »: once the trade is opened from its records, the last status shown, never the first read\'s wait',
      () async {
        final (harness, first) = await taken();
        await shownAt(harness, first, 3);
        expect(first.state.seen?.status, isA<WaitingForTakerBond>());
        final record = first.state.record;
        // The route is gone with its cubits (`P2pRouter.tradePage`, the shell's `go` to another tab).
        await first.close();

        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        final again = cubitOf(harness, record);
        late TradeView whileReading;
        final views = await viewsDuring(again, () async {
          again.start();
          await harness.settle();
          whileReading = viewOf(again);
          held.complete();
          harness.coordinator.hold = null;
          await harness.settle();
        });

        // Before its first state the new screen has nothing (`watch: null`), for the local opening of the trade only (no network).
        expect(
          views.whereType<TradeWaiting>(),
          isEmpty,
          reason:
              'the trade opened again showed « Your robot reads the order »: ${views.map((v) => v.runtimeType).toList()}',
        );
        expect(whileReading, isA<TradeContract>());
        expect(again.state.seen?.status, isA<WaitingForTakerBond>());
        await again.close();
      },
    );

    test(
      'after a restart of the app nothing is kept: the trade opened again waits for its first read',
      () async {
        final (harness, first) = await taken();
        await shownAt(harness, first, 3);
        final record = first.state.record;
        await first.close();

        final restarted = harness.restart();
        expect(restarted.watch.lastStored(record), isNull);
        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        final again = cubitOf(restarted, record);
        again.start();
        await restarted.settle();
        expect(viewOf(again), isA<TradeWaiting>());
        held.complete();
        harness.coordinator.hold = null;
        await restarted.settle();
        expect(again.state.seen?.status, isA<WaitingForTakerBond>());
        await again.close();
      },
    );

    test(
      'the memory of another trade, robot or order is never given: only this very trade\'s',
      () async {
        final (harness, cubit) = await taken();
        await shownAt(harness, cubit, 3);
        final record = cubit.state.record;
        expect(harness.watch.lastStored(record), same(cubit.state.seen));
        TradeRecord changed({
          int? orderId,
          String? alias,
          String? onion,
          TradeRole? role,
        }) => TradeRecord(
          robot: record.robot,
          coordinatorAlias: alias ?? record.coordinatorAlias,
          coordinatorOnion: onion ?? record.coordinatorOnion,
          orderId: orderId ?? record.orderId,
          role: role ?? record.role,
          origin: record.origin,
          takenAt: record.takenAt,
          confirmedAt: record.confirmedAt,
          closedAt: record.closedAt,
        );
        expect(
          harness.watch.lastStored(changed(orderId: record.orderId + 1)),
          isNull,
        );
        expect(harness.watch.lastStored(changed(alias: 'other')), isNull);
        expect(
          harness.watch.lastStored(changed(onion: 'http://other.onion')),
          isNull,
        );
        expect(
          harness.watch.lastStored(changed(role: TradeRole.seller)),
          isNull,
        );
        final otherRobot = TradeRecord(
          robot: RobotSlot(
            record.robot.network,
            record.robot.keyFingerprint,
            record.robot.accountIndex + 1,
          ),
          coordinatorAlias: record.coordinatorAlias,
          coordinatorOnion: record.coordinatorOnion,
          orderId: record.orderId,
          role: record.role,
          origin: record.origin,
          takenAt: record.takenAt,
          confirmedAt: record.confirmedAt,
          closedAt: record.closedAt,
        );
        expect(harness.watch.lastStored(otherRobot), isNull);
        await cubit.close();
      },
    );
  });

  group('#152: the memory, dropped when the trade ends', () {
    test(
      'a status at an end, or a record closed, is never given: the end is shown from the stored trail',
      () async {
        final statuses = await TradeScreenStatuses.make();
        final record = TradeScreenStatuses.record;
        final bond = await statuses.bondStep();
        final expired = await statuses.expired();
        expect(expired.status.isTerminal, isTrue);
        final closed = TradeRecord(
          robot: record.robot,
          coordinatorAlias: record.coordinatorAlias,
          coordinatorOnion: record.coordinatorOnion,
          orderId: record.orderId,
          role: record.role,
          origin: record.origin,
          takenAt: record.takenAt,
          confirmedAt: record.confirmedAt,
          closedAt: tradeNow,
        );

        final going = TradeReadOrder()..stored(record, bond);
        expect(going.lastStored(record.robot)?.seen, same(bond));
        // An end whose record could not be closed.
        final ended = TradeReadOrder()..stored(record, expired);
        expect(ended.lastStored(record.robot), isNull);
        // A record closed under a status that goes on (as a later close leaves it).
        final shut = TradeReadOrder()..stored(closed, bond);
        expect(shut.lastStored(record.robot), isNull);
      },
    );
  });

  group('#152: the kept status and the stored trail must agree', () {
    /// A cubit over a watch the test plays, the memory giving [memory].
    (TradeCubit, StreamController<TradeWatchState>) played(
      TradeRecord record,
      TradeSeen? memory, {
      TradeCanceller? cancel,
      TradeFiatSender? confirmFiatSent,
    }) {
      final out = StreamController<TradeWatchState>.broadcast();
      final cubit = TradeCubit(
        record,
        (record, {signals = const Stream.empty(), onScreen = true}) {
          // Listened to, as the real watch does, so that closing the cubit ends.
          signals.listen((_) {});
          return out.stream;
        },
        cancel ??
            (record, seen, {bondLoss}) async => throw StateError('not sent'),
        confirmFiatSent: confirmFiatSent,
        lastStored: (_) => memory,
      )..start();
      return (cubit, out);
    }

    /// The watch's status of the stored trail of [seen]: its own status, unmarked, as `TradeReader.open` gives it.
    TradeWatchStatus trailOf(
      TradeRecord record,
      TradeSeen seen, {
      P2pFailure? recordProblem,
    }) => TradeWatchStatus(
      record,
      TradeSeen(TradeStatus.beforeFirstRead(seen.status.trail), order: null),
      recordProblem: recordProblem,
      takePending: false,
    );

    test(
      'the memory kept only over its own trail: another position, the same position stored by a later write, or a write that failed show the wait, as before',
      () async {
        final (harness, cubit) = await taken();
        await shownAt(harness, cubit, 3);
        final bond = cubit.state.seen!;
        harness.coordinator.lockBond(harness.robot(0));
        cubit.signal(TradeWatchSignal.readNow);
        await harness.settle();
        final six = cubit.state.seen!;
        await harness.elapse(const Duration(seconds: 30));
        cubit.signal(TradeWatchSignal.readNow);
        await harness.settle();
        final sixLater = cubit.state.seen!;
        final record = cubit.state.record;
        await cubit.close();
        expect(six.status.position, TradePosition.waitingForBoth);
        expect(sixLater.status.position, TradePosition.waitingForBoth);
        expect(sixLater.status.trail.readAt, isNot(six.status.trail.readAt));

        Future<TradeView> viewOver(TradeWatchStatus watch) async {
          final (played1, out) = played(record, six);
          out.add(watch);
          await Future<void>.delayed(Duration.zero);
          final view = viewOf(played1);
          await played1.close();
          return view;
        }

        // Its own trail: kept.
        expect(await viewOver(trailOf(record, six)), isA<TradeContract>());
        // Another position.
        expect(await viewOver(trailOf(record, bond)), isA<TradeWaiting>());
        // The same position, stored by a later write.
        expect(await viewOver(trailOf(record, sixLater)), isA<TradeWaiting>());
        // Its own trail, under a write that failed.
        expect(
          await viewOver(
            trailOf(record, six, recordProblem: const P2pStorageFailure()),
          ),
          isA<TradeWaiting>(),
        );
      },
    );

    test(
      'kept, then the stored trail\'s own status no longer matching (a write that failed, another position): the wait',
      () async {
        final (harness, cubit) = await taken();
        await shownAt(harness, cubit, 3);
        final bond = cubit.state.seen!;
        harness.coordinator.lockBond(harness.robot(0));
        cubit.signal(TradeWatchSignal.readNow);
        await harness.settle();
        final six = cubit.state.seen!;
        final record = cubit.state.record;
        await cubit.close();
        final (played1, out) = played(record, six);
        out.add(trailOf(record, six));
        await Future<void>.delayed(Duration.zero);
        expect(viewOf(played1), isA<TradeContract>());
        out.add(trailOf(record, six, recordProblem: const P2pStorageFailure()));
        await Future<void>.delayed(Duration.zero);
        expect(viewOf(played1), isA<TradeWaiting>());
        out.add(
          TradeWatchStatus(
            record,
            TradeSeen(
              TradeStatus.beforeFirstRead(six.status.trail),
              order: null,
            ),
            takePending: false,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(viewOf(played1), isA<TradeContract>());
        // Then a stored trail of another position: nothing kept over it.
        out.add(trailOf(record, bond));
        await Future<void>.delayed(Duration.zero);
        expect(viewOf(played1), isA<TradeWaiting>());
        // A status that matches nothing (no memory, nothing shown at its trail).
        final (played2, out2) = played(record, null);
        out2.add(trailOf(record, six));
        await Future<void>.delayed(Duration.zero);
        expect(viewOf(played2), isA<TradeWaiting>());
        await played1.close();
        await played2.close();
      },
    );

    test('a status not marked stored is never kept', () async {
      final (harness, cubit) = await taken();
      await shownAt(harness, cubit, 6);
      final six = cubit.state.seen!;
      final record = cubit.state.record;
      await cubit.close();
      final unmarked = TradeSeen(six.status, order: six.order);
      final (played1, out) = played(record, unmarked);
      out.add(trailOf(record, six));
      await Future<void>.delayed(Duration.zero);
      expect(viewOf(played1), isA<TradeWaiting>());
      await played1.close();
    });
  });

  group('#152: nothing is sent from a kept status alone', () {
    test(
      '« Cancel » from a kept bond step, the bond locked meanwhile: sent with the kept status\'s guard as the reference cancels, refused by the coordinator (1020) and said as today; nothing cancelled',
      () async {
        final (harness, cubit) = await taken();
        await shownAt(harness, cubit, 3);
        await cubit.suspend();
        harness.coordinator.lockBond(harness.robot(0));
        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        cubit.resume();
        await harness.settle();
        final kept = cubit.state.seen!;
        expect(kept.status, isA<WaitingForTakerBond>());
        expect(viewOf(cubit), isA<TradeContract>());

        // A free cancel at 3, as the dialog of the kept status asks it.
        final cancelling = cubit.cancel(kept);
        await harness.settle();
        held.complete();
        harness.coordinator.hold = null;
        await cancelling;
        await harness.settle();

        expect(received(harness, ScriptedRequest.cancel), 1);
        // The guard of 3 against an order at 6: refused, the cancel not done, said as any refusal of the coordinator.
        expect(
          cubit.state.cancel,
          isA<CancelIdle>().having(
            (c) => c.notice,
            'notice',
            isA<CancelWasNotDone>(),
          ),
        );
        expect(cubit.state.seen?.status, isA<WaitingForBoth>());
        await cubit.close();
      },
    );

    test(
      'a payout given from a kept status 8, the invoice given elsewhere meanwhile (9): the payout reads first and sends nothing',
      () async {
        final (harness, cubit) = await taken();
        await shownAt(harness, cubit, 8);
        await cubit.suspend();
        harness.coordinator.moveTo(9);
        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        cubit.resume();
        await harness.settle();
        expect(viewOf(cubit), isA<TradeContract>());
        final kept = cubit.state.seen!;
        expect(kept.status.position, TradePosition.waitingForPayout);

        final invoice = Bolt11TestInvoice(
          network: Bolt11Network.testnet,
          sats: buyerSats,
          seed: seed++,
          createdAt: harness.now,
          expiry: const Duration(days: 2),
        );
        harness.coordinator.decoder.add(invoice);
        final shown = switch (harness.payout.check(
          cubit.state.record,
          kept,
          PayoutInvoiceText(
            invoice.text,
            budget: RoutingBudgetPpm.of(0) ?? RoutingBudgetPpm.referenceDefault,
          ),
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('refused: $failure'),
        };
        final reads = received(harness, ScriptedRequest.order);
        final given = harness.payout.execute(cubit.state.record, shown);
        held.complete();
        harness.coordinator.hold = null;
        final outcome = await given;
        await harness.settle();

        expect(outcome, isA<Err<PayoutSubmission, PayoutNotSent>>());
        expect(received(harness, ScriptedRequest.payout), 0);
        expect(received(harness, ScriptedRequest.order), greaterThan(reads));
        await cubit.close();
      },
    );

    test(
      '« Confirm fiat sent » from a kept status 9, the order moved on meanwhile (10, confirmed elsewhere): the action reads first and sends nothing',
      () async {
        final (harness, cubit) = await taken();
        await shownAt(harness, cubit, 9);
        await cubit.suspend();
        harness.coordinator.moveTo(10);
        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        cubit.resume();
        await harness.settle();
        expect(viewOf(cubit), isA<TradeContract>());
        expect(cubit.state.seen?.status.position, TradePosition.chatting);

        final sending = cubit.confirmFiatSent(cubit.state.seen!);
        await harness.settle();
        held.complete();
        harness.coordinator.hold = null;
        await sending;
        await harness.settle();

        expect(received(harness, ScriptedRequest.confirm), 0);
        expect(cubit.state.chatStep, isA<ChatStepIdle>());
        expect(cubit.state.seen?.status.position, TradePosition.fiatSent);
        await cubit.close();
      },
    );
  });
}
