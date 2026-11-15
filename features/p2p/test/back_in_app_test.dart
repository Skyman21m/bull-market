import 'dart:async';

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
  });
}
