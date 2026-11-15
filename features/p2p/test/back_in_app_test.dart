import 'dart:async';

import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_panel.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// Ticket #148, « the app reloads the order each time »: the trade's cubit over the real watch (`WatchTradeUsecase`, its reader and its records, the coordinator played by `ScriptedCoordinator`), the app hidden then shown again in the same process, as when the buyer leaves to pay the bond or make an invoice in another wallet app.
///
/// What the screen draws is [TradeView.of] of the cubit's watch state: these tests read it at each moment, the first read after the return held or failing as over a Tor just woken.
/// Each expects what the official client does (its order page keeps the order it shows while it reads again, `frontend/src/basic/OrderPage/index.tsx:76-96`, a failed read keeping the order as it is, `frontend/src/models/Order.model.ts:264-281`): they fail until #148 is fixed, and are its tests.
void main() {
  /// A take of the coordinator's order by a new robot, and the trade's cubit over the real watch.
  Future<(TradeHarness, TradeCubit)> taken() async {
    final harness = await TradeHarness.start();
    final record = TradeHarness.recordOf(await harness.takeShown());
    final cubit = TradeCubit(
      record,
      harness.watch.execute,
      harness.cancel.execute,
    );
    return (harness, cubit);
  }

  /// What the screen draws for [cubit]'s state now.
  TradeView viewOf(TradeCubit cubit) => TradeView.of(cubit.state.watch);

  group('#148: back in the app, the process alive', () {
    test(
      'the bond step shown, the first read after the return held: the screen keeps the bond step, never the first read\'s wait',
      () async {
        final (harness, cubit) = await taken();
        cubit.start();
        await harness.settle();
        expect(viewOf(cubit), isA<TradeContract>());
        expect(cubit.state.seen?.status, isA<WaitingForTakerBond>());

        // The buyer leaves to pay the bond with another wallet app.
        await cubit.suspend();
        await harness.elapse(const Duration(seconds: 20));

        // Back in the app: Tor wakes, the first read takes its time.
        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        final views = <TradeView>[];
        final listening = cubit.stream.listen(
          (state) => views.add(TradeView.of(state.watch)),
        );
        cubit.resume();
        await harness.settle();

        // What the screen draws while the read is in flight.
        final whileReading = viewOf(cubit);
        held.complete();
        harness.coordinator.hold = null;
        await harness.settle();
        await listening.cancel();

        expect(
          views.whereType<TradeWaiting>(),
          isEmpty,
          reason:
              'the screen fell back to « Your robot reads the order » after the return: ${views.map((v) => v.runtimeType).toList()}',
        );
        expect(whileReading, isA<TradeContract>());
        expect(cubit.state.seen?.status, isA<WaitingForTakerBond>());
        await cubit.close();
      },
    );

    test(
      'status 6 shown (the payout form), the reads after the return failing: the last status stays with « cannot reach », never the wait',
      () async {
        final (harness, cubit) = await taken();
        cubit.start();
        await harness.settle();
        harness.coordinator.lockBond(harness.robot(0));
        cubit.signal(TradeWatchSignal.readNow);
        await harness.settle();
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
        final views = <TradeView>[];
        final listening = cubit.stream.listen(
          (state) => views.add(TradeView.of(state.watch)),
        );
        cubit.resume();
        await harness.settle();
        for (var i = 0; i < 2; i++) {
          await harness.elapse(const Duration(seconds: 10));
          await harness.settle();
        }
        await listening.cancel();

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
        cubit.start();
        await harness.settle();
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
        cubit.start();
        await harness.settle();
        await cubit.suspend();
        harness.coordinator.lockBond(harness.robot(0));

        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        final views = <TradeView>[];
        final listening = cubit.stream.listen(
          (state) => views.add(TradeView.of(state.watch)),
        );
        cubit.resume();
        await harness.settle();
        final whileReading = viewOf(cubit);
        held.complete();
        harness.coordinator.hold = null;
        await harness.settle();
        await listening.cancel();

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
  });

  group('#148: the trade left and opened again, the process alive', () {
    test(
      'the trade\'s route left (the Wallet tab, or back) and the trade opened again by « Order »: the new screen shows the last status shown at once, never the first read\'s wait',
      () async {
        final (harness, first) = await taken();
        first.start();
        await harness.settle();
        expect(first.state.seen?.status, isA<WaitingForTakerBond>());
        final record = first.state.record;
        // The route is gone with its cubits (`P2pRouter.tradePage`, the shell's `go` to another tab).
        await first.close();

        final held = Completer<void>();
        harness.coordinator.hold = held.future;
        final again = TradeCubit(
          record,
          harness.watch.execute,
          harness.cancel.execute,
        );
        final views = <TradeView>[viewOf(again)];
        final listening = again.stream.listen(
          (state) => views.add(TradeView.of(state.watch)),
        );
        again.start();
        await harness.settle();
        held.complete();
        harness.coordinator.hold = null;
        await harness.settle();
        await listening.cancel();

        expect(
          views.whereType<TradeWaiting>(),
          isEmpty,
          reason:
              'the trade opened again showed « Your robot reads the order »: ${views.map((v) => v.runtimeType).toList()}',
        );
        expect(again.state.seen?.status, isA<WaitingForTakerBond>());
        await again.close();
      },
    );
  });
}
