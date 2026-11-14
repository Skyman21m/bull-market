import 'dart:async';

import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/usecases/has_garage_key_usecase.dart';
import 'package:p2p/src/presentation/active_trades_cubit.dart';
import 'package:p2p/src/presentation/take_order_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/key_output.dart';
import 'support/trade_harness.dart';

/// What the vault says of a key, for « Store your garage key » or « You do not have a Garage Key ».
final class _Keys implements GarageKeyRepository {
  final Result<bool, P2pFailure> answer;

  _Keys(this.answer);

  @override
  Future<Result<bool, P2pFailure>> exists(RobosatsNetwork network) async =>
      answer;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TakeOrderCubit _takeCubit(
  TradeHarness harness,
  PublicOrder order, {
  Result<bool, P2pFailure> keys = const Ok(true),
  Duration stillWaitingAfter = TakeOrderCubit.stillWaitingAfter,
}) => TakeOrderCubit(
  order,
  harness.network,
  harness.take.execute,
  HasGarageKeyUsecase(_Keys(keys)).execute,
  stillWaitingAfter: stillWaitingAfter,
);

int _requestsOf(TradeHarness harness, ScriptedRequest kind) =>
    harness.coordinator.received.where((r) => r == kind).length;

/// The seen status of [cubit], which the tests expect to be there.
TradeSeen _seen(TradeCubit cubit) => switch (cubit.state.seen) {
  final seen? => seen,
  null => throw StateError('no status shown'),
};

void main() {
  group('TakeOrderCubit', () {
    test('a sell order: running, then the trade of the take', () async {
      final harness = await TradeHarness.start();
      final cubit = _takeCubit(harness, await harness.shownOrder());
      final states = <TakeOrderState>[];
      final listening = cubit.stream.listen(states.add);

      await cubit.take();
      await harness.settle();

      expect(states.first, isA<TakeRunning>());
      final sent = states.last;
      expect(sent, isA<TakeSent>());
      expect((sent as TakeSent).record.orderId, harness.coordinator.orderId);
      expect(harness.coordinator.holdsPreTake(harness.robot(0)), isTrue);
      await listening.cancel();
      await cubit.close();
    });

    test('a double tap sends one take', () async {
      final harness = await TradeHarness.start();
      final cubit = _takeCubit(harness, await harness.shownOrder());

      await Future.wait([cubit.take(), cubit.take()]);
      await cubit.take();
      await harness.settle();

      expect(_requestsOf(harness, ScriptedRequest.take), 1);
      expect(cubit.state, isA<TakeSent>());
      await cubit.close();
    });

    test('a buy order is refused, nothing sent with a robot', () async {
      final harness = await TradeHarness.start(orderType: 0);
      final cubit = _takeCubit(harness, await harness.shownOrder());

      await cubit.take();

      expect(
        cubit.state,
        isA<TakeIdle>().having(
          (s) => s.problem,
          'problem',
          isA<TakeWasRefused>().having(
            (p) => p.refusal,
            'refusal',
            isA<TakeOfBuyOrderRefused>(),
          ),
        ),
      );
      expect(_requestsOf(harness, ScriptedRequest.take), 0);
      expect(_requestsOf(harness, ScriptedRequest.robot), 0);
      await cubit.close();
    });

    test(
      'a take the coordinator did not make says so, and can be tried again',
      () async {
        final harness = await TradeHarness.start();
        harness.coordinator.takesNotMade = true;
        final cubit = _takeCubit(harness, await harness.shownOrder());

        await cubit.take();

        expect(
          cubit.state,
          isA<TakeIdle>().having(
            (s) => s.problem,
            'problem',
            isA<TakeWasNotMade>().having((p) => p.refusal, 'refusal', isNull),
          ),
        );
        harness.coordinator.takesNotMade = false;
        await cubit.take();
        expect(_requestsOf(harness, ScriptedRequest.take), 2);
        expect(cubit.state, isA<TakeSent>());
        await cubit.close();
      },
    );

    test(
      'a take whose answer was lost opens its trade, for the watch to resolve',
      () async {
        final harness = await TradeHarness.start();
        harness.coordinator.failNext(
          ScriptedRequest.take,
          ScriptedFault.answerLost,
        );
        final cubit = _takeCubit(harness, await harness.shownOrder());

        await cubit.take();

        expect(cubit.state, isA<TakeSent>());
        expect((await harness.activeRecords()).single.isPendingTake, isTrue);
        await cubit.close();
      },
    );

    test('an order gone from the book is refused before any robot', () async {
      final harness = await TradeHarness.start();
      final shown = await harness.shownOrder();
      harness.coordinator.cancelByMaker();
      final cubit = _takeCubit(harness, shown);

      await cubit.take();

      expect(
        (cubit.state as TakeIdle).problem,
        isA<TakeWasRefused>().having(
          (p) => p.refusal,
          'refusal',
          isA<TakeOrderGone>(),
        ),
      );
      expect(_requestsOf(harness, ScriptedRequest.robot), 0);
      await cubit.close();
    });

    test('a take that runs long says it still waits', () async {
      final harness = await TradeHarness.start();
      final hold = Completer<void>();
      final cubit = _takeCubit(
        harness,
        await harness.shownOrder(),
        stillWaitingAfter: const Duration(milliseconds: 20),
      );
      harness.coordinator.hold = hold.future;

      final taking = cubit.take();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        cubit.state,
        isA<TakeRunning>().having((s) => s.slow, 'slow', isTrue),
      );

      harness.coordinator.hold = null;
      hold.complete();
      await taking;
      expect(cubit.state, isA<TakeSent>());
      await cubit.close();
    });

    test('closed while the take runs, it emits nothing more', () async {
      final harness = await TradeHarness.start();
      final hold = Completer<void>();
      final cubit = _takeCubit(harness, await harness.shownOrder());
      harness.coordinator.hold = hold.future;

      final taking = cubit.take();
      await harness.settle();
      await cubit.close();
      harness.coordinator.hold = null;
      hold.complete();
      await taking;

      expect(cubit.state, isA<TakeRunning>());
    });

    test(
      'an order with an open trade here opens that trade, nothing taken again',
      () async {
        final harness = await TradeHarness.start();
        final shown = await harness.shownOrder();
        final first = _takeCubit(harness, shown);
        await first.take();
        final record = (first.state as TakeSent).record;
        await first.close();
        final second = _takeCubit(harness, shown);

        await second.take();

        expect(second.state, isA<TakeSent>());
        expect((second.state as TakeSent).record.robot, record.robot);
        expect(_requestsOf(harness, ScriptedRequest.take), 1);
        await second.close();
      },
    );

    test('the key: none only when the vault says so', () async {
      final harness = await TradeHarness.start();
      final order = await harness.shownOrder();
      for (final (answer, expected) in [
        (const Ok<bool, P2pFailure>(true), true),
        (const Ok<bool, P2pFailure>(false), false),
        (const Err<bool, P2pFailure>(GarageKeyLockedFailure()), true),
      ]) {
        final cubit = _takeCubit(harness, order, keys: answer);
        expect(await cubit.hasGarageKey(), expected, reason: '$answer');
        await cubit.close();
      }
    });
  });

  group('TradeCubit', () {
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

    test('start: the restored trade then the read, one watch', () async {
      final (harness, cubit) = await taken();
      final states = <TradeScreenState>[];
      final listening = cubit.stream.listen(states.add);

      cubit
        ..start()
        ..start();
      await harness.settle();

      expect(cubit.watching, isTrue);
      expect(_seen(cubit).status, isA<WaitingForTakerBond>());
      // One read at once, for one subscription.
      final reads = _requestsOf(harness, ScriptedRequest.order);
      expect(reads, 1);
      expect(harness.activeTimers, hasLength(1));
      await listening.cancel();
      await cubit.close();
      expect(harness.activeTimers, isEmpty);
    });

    test('off screen five times slower, read now at once', () async {
      final (harness, cubit) = await taken();
      cubit.start();
      await harness.settle();
      final onScreen = harness.activeTimers.single.duration;

      cubit.signal(TradeWatchSignal.offScreen);
      await harness.elapse(onScreen);
      final offScreen = harness.activeTimers.single.duration;
      expect(offScreen, greaterThan(onScreen));

      final before = _requestsOf(harness, ScriptedRequest.order);
      cubit.signal(TradeWatchSignal.readNow);
      await harness.settle();
      expect(_requestsOf(harness, ScriptedRequest.order), before + 1);
      await cubit.close();
    });

    test(
      'suspended while the app is away, nothing runs; resumed, it reads at once',
      () async {
        final (harness, cubit) = await taken();
        cubit.start();
        await harness.settle();

        await cubit.suspend();
        expect(cubit.watching, isFalse);
        expect(harness.activeTimers, isEmpty);
        final before = _requestsOf(harness, ScriptedRequest.order);
        // Within the pre-take, which the coordinator keeps 190 s.
        await harness.elapse(const Duration(seconds: 30));
        expect(_requestsOf(harness, ScriptedRequest.order), before);

        cubit.resume();
        await harness.settle();
        expect(cubit.watching, isTrue, reason: '${cubit.state.watch}');
        // The pre-take stays shown while the watch opens the trade again.
        expect(_seen(cubit).status, isA<WaitingForTakerBond>());
        expect(_requestsOf(harness, ScriptedRequest.order), before + 1);
        await cubit.close();
        expect(harness.activeTimers, isEmpty);
      },
    );

    test('a free cancel at 3: one request, the order public again', () async {
      final (harness, cubit) = await taken();
      cubit.start();
      await harness.settle();
      final seen = _seen(cubit);

      await Future.wait([cubit.cancel(seen), cubit.cancel(seen)]);
      await harness.settle();

      expect(_requestsOf(harness, ScriptedRequest.cancel), 1);
      expect(cubit.state.cancel, isA<CancelIdle>());
      expect((cubit.state.cancel as CancelIdle).notice, isNull);
      expect(_seen(cubit).status, isA<PreTakeEnded>());
      expect(harness.coordinator.holdsPreTake(harness.robot(0)), isFalse);
      await cubit.close();
    });

    test(
      'at 6, a cancel without the acknowledgement is refused and sends nothing',
      () async {
        final (harness, cubit) = await taken();
        cubit.start();
        await harness.settle();
        harness.coordinator.lockBond(harness.robot(0));
        cubit.signal(TradeWatchSignal.readNow);
        await harness.settle();
        expect(_seen(cubit).status, isA<WaitingForBoth>());

        await cubit.cancel(_seen(cubit));

        expect(_requestsOf(harness, ScriptedRequest.cancel), 0);
        expect(
          (cubit.state.cancel as CancelIdle).notice,
          isA<CancelWasRefused>().having(
            (n) => n.refusal,
            'refusal',
            isA<CancelLosesTheBond>(),
          ),
        );
        expect(harness.coordinator.status, 6);
        await cubit.close();
      },
    );

    test('at 6, the confirmed cancel loses the bond: one request', () async {
      final (harness, cubit) = await taken();
      cubit.start();
      await harness.settle();
      harness.coordinator.lockBond(harness.robot(0));
      cubit.signal(TradeWatchSignal.readNow);
      await harness.settle();

      await cubit.cancel(
        _seen(cubit),
        bondLoss: BondLossAcknowledged.fromConfirmationDialog(
          cubit.state.record,
          _seen(cubit),
        ),
      );
      await harness.settle();

      expect(_requestsOf(harness, ScriptedRequest.cancel), 1);
      expect(harness.coordinator.status, 1);
      expect(_seen(cubit).status, isA<BondForfeited>());
      await cubit.close();
    });

    test('a cancel whose answer was lost says it does not know yet', () async {
      final (harness, cubit) = await taken();
      cubit.start();
      await harness.settle();
      harness.coordinator.failNext(
        ScriptedRequest.cancel,
        ScriptedFault.answerLost,
      );

      await cubit.cancel(_seen(cubit));

      expect(
        (cubit.state.cancel as CancelIdle).notice,
        isA<CancelWasUnknown>(),
      );
      await cubit.close();
    });

    test(
      'a cancel the coordinator never received: nothing was cancelled',
      () async {
        final (harness, cubit) = await taken();
        cubit.start();
        await harness.settle();
        for (var i = 0; i < 4; i++) {
          harness.coordinator.failNext(
            ScriptedRequest.cancel,
            ScriptedFault.busy,
          );
        }

        await cubit.cancel(_seen(cubit));

        expect(
          (cubit.state.cancel as CancelIdle).notice,
          isA<CancelWasNotDone>(),
        );
        expect(harness.coordinator.holdsPreTake(harness.robot(0)), isTrue);
        await cubit.close();
      },
    );
  });

  group('ActiveTradesCubit', () {
    test('none, then the trade of a take, from the records only', () async {
      final harness = await TradeHarness.start();
      final cubit = ActiveTradesCubit(harness.network, harness.list.execute)
        ..start();
      await harness.settle();
      expect(cubit.state, isA<ActiveTradesListed>());
      expect((cubit.state as ActiveTradesListed).active, isEmpty);
      final before = harness.coordinator.requests.length;

      await harness.takeShown();
      await harness.settle();

      final active = (cubit.state as ActiveTradesListed).active;
      expect(active, hasLength(1));
      expect(active.single.standing, isA<ActiveTradeAt>());
      // Listing asks the coordinator nothing: only the take's requests were sent.
      final afterTake = harness.coordinator.requests.length;
      expect(afterTake, greaterThan(before));
      await harness.elapse(const Duration(minutes: 5));
      expect(harness.coordinator.requests.length, afterTake);
      await cubit.close();
    });
  });

  test(
    'a take, the watch and a cancel print and log nothing of the trade',
    () async {
      final harness = await TradeHarness.start();
      String? invoice;
      final output = await captureKeyOutput(() async {
        final take = _takeCubit(harness, await harness.shownOrder());
        await take.take();
        final record = switch (take.state) {
          TakeSent(:final record) => record,
          final other => throw StateError('$other'),
        };
        await take.close();
        invoice = harness.coordinator.bondOf(harness.robot(0))?.text;
        final trade = TradeCubit(
          record,
          harness.watch.execute,
          harness.cancel.execute,
        )..start();
        await harness.settle();
        await trade.cancel(_seen(trade));
        await harness.settle();
        await trade.close();
        final list = ActiveTradesCubit(harness.network, harness.list.execute)
          ..start();
        await harness.settle();
        await list.close();
      });
      expect(invoice, isNotNull);
      expect(output.contains(invoice ?? '-'), isFalse);
      expect(output.contains(harness.robot(0).tokenSha256Hex), isFalse);
      expect(output.contains(harness.robot(0).nickname), isFalse);
      expectNoKeyIn(output, [tradeKey]);
    },
  );
}
