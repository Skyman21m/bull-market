import 'dart:async';

import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/has_garage_key_usecase.dart';
import 'package:p2p/src/presentation/active_trades_cubit.dart';
import 'package:p2p/src/presentation/take_order_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/testing.dart'
    show ScriptedCoordinator, ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/key_output.dart';
import 'support/trade_harness.dart';
import 'support/trade_screens.dart';

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

TakeCalls _calls(TradeHarness harness) => TakeCalls(
  prepare: harness.take.prepare,
  confirm: harness.take.confirm,
  abandon: harness.take.abandon,
  abandonOrder: harness.take.abandonOrder,
);

TakeOrderCubit _takeCubit(
  TradeHarness harness,
  PublicOrder order, {
  Result<bool, P2pFailure> keys = const Ok(true),
  Duration stillWaitingAfter = TakeOrderCubit.stillWaitingAfter,
  TakeCalls? calls,
}) => TakeOrderCubit(
  order,
  harness.network,
  calls ?? _calls(harness),
  HasGarageKeyUsecase(_Keys(keys)).execute,
  stillWaitingAfter: stillWaitingAfter,
);

/// Prepares the take, then confirms it, as the user does.
Future<void> _takeAndConfirm(TakeOrderCubit cubit) async {
  await cubit.take();
  await cubit.confirm();
}

int _requestsOf(TradeHarness harness, ScriptedRequest kind) =>
    harness.coordinator.received.where((r) => r == kind).length;

Future<int> _bindings(TradeHarness harness) async =>
    (await harness.database.customSelect('SELECT * FROM robot_bindings').get())
        .length;

/// The prepared take [cubit] shows, which the tests expect.
PreparedTake _readOf(TakeOrderCubit cubit) => switch (cubit.state) {
  TakeReady(:final prepared) => prepared,
  final other => throw StateError('not ready: $other'),
};

/// The seen status of [cubit], which the tests expect to be there.
TradeSeen _seen(TradeCubit cubit) => switch (cubit.state.seen) {
  final seen? => seen,
  null => throw StateError('no status shown'),
};

void main() {
  group('TakeOrderCubit', () {
    test(
      'a sell order: preparing, then the order read by its robot, nothing taken until it is confirmed',
      () async {
        final harness = await TradeHarness.start();
        harness.coordinator.description = 'Revolut only.';
        final cubit = _takeCubit(harness, await harness.shownOrder());
        final states = <TakeOrderState>[];
        final listening = cubit.stream.listen(states.add);

        await cubit.take();
        await harness.settle();

        expect(states.first, isA<TakePreparing>());
        final read = _readOf(cubit);
        expect(read.description, 'Revolut only.');
        expect(
          cubit.state,
          isA<TakeReady>().having((s) => s.changed, 'changed', isFalse),
        );
        expect(_requestsOf(harness, ScriptedRequest.take), 0);
        expect(await harness.allTrades(), isEmpty);

        await cubit.confirm();
        await harness.settle();

        expect(states.whereType<TakeConfirming>(), isNotEmpty);
        final sent = states.last;
        expect(sent, isA<TakeSent>());
        expect((sent as TakeSent).record.orderId, harness.coordinator.orderId);
        // The read stays shown until the trade's screen opens.
        expect(sent.prepared, same(read));
        expect(harness.coordinator.holdsPreTake(harness.robot(0)), isTrue);
        await listening.cancel();
        await cubit.close();
      },
    );

    test('a double tap prepares once, and confirms once', () async {
      final harness = await TradeHarness.start();
      // Counted at the cubit's door: the use case also runs the steps of one order in turn, which would hide a second call.
      var prepares = 0;
      var confirms = 0;
      final take = harness.take;
      final cubit = _takeCubit(
        harness,
        await harness.shownOrder(),
        calls: TakeCalls(
          prepare: (shown, {required network, amount, onStep, garageRobot}) {
            prepares++;
            return take.prepare(
              shown,
              network: network,
              amount: amount,
              onStep: onStep,
            );
          },
          confirm: (prepared, {password, onStep}) {
            confirms++;
            return take.confirm(prepared, onStep: onStep);
          },
          abandon: take.abandon,
          abandonOrder: take.abandonOrder,
        ),
      );

      await Future.wait([cubit.take(), cubit.take()]);
      await Future.wait([cubit.confirm(), cubit.confirm()]);
      await cubit.confirm();
      await cubit.take();
      await harness.settle();

      expect(prepares, 1);
      expect(confirms, 1);
      expect(_requestsOf(harness, ScriptedRequest.take), 1);
      expect(cubit.state, isA<TakeSent>());
      await cubit.close();
    });

    test(
      'a buy order is taken as a sell order is: its taker sells (#96)',
      () async {
        final harness = await TradeHarness.start(orderType: 0);
        final cubit = _takeCubit(harness, await harness.shownOrder());

        await cubit.take();
        await harness.settle();
        expect(cubit.state, isA<TakeReady>());
        expect(_requestsOf(harness, ScriptedRequest.take), 0);

        await cubit.confirm();
        await harness.settle();

        final sent = cubit.state;
        expect(sent, isA<TakeSent>());
        expect((sent as TakeSent).record.role, TradeRole.seller);
        expect(_requestsOf(harness, ScriptedRequest.take), 1);
        expect(harness.coordinator.holdsPreTake(harness.robot(0)), isTrue);
        await cubit.close();
      },
    );

    test(
      'a take the coordinator did not make says so, and can be prepared again with a fresh robot',
      () async {
        final harness = await TradeHarness.start();
        harness.coordinator.takesNotMade = true;
        final cubit = _takeCubit(harness, await harness.shownOrder());

        await _takeAndConfirm(cubit);

        expect(
          cubit.state,
          isA<TakeIdle>().having(
            (s) => s.problem,
            'problem',
            isA<TakeWasNotMade>().having((p) => p.refusal, 'refusal', isNull),
          ),
        );
        harness.coordinator.takesNotMade = false;
        await _takeAndConfirm(cubit);
        expect(_requestsOf(harness, ScriptedRequest.take), 2);
        expect(cubit.state, isA<TakeSent>());
        expect(await _bindings(harness), 2);
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

        await _takeAndConfirm(cubit);

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

    test(
      'the order changed at the confirmation: prepared again with the same robot, its new figures shown, nothing taken',
      () async {
        final harness = await TradeHarness.start();
        final cubit = _takeCubit(harness, await harness.shownOrder());
        await cubit.take();
        final first = _readOf(cubit);
        harness.coordinator.description = 'Now pay first.';
        final states = <TakeOrderState>[];
        final listening = cubit.stream.listen(states.add);

        await cubit.confirm();

        // While the order is read again, the read the user saw stays shown.
        final rereads = states.whereType<TakePreparing>().toList();
        expect(rereads, isNotEmpty);
        expect(rereads.map((s) => s.previous), everyElement(same(first)));
        expect(
          cubit.state,
          isA<TakeReady>()
              .having((s) => s.changed, 'changed', isTrue)
              .having((s) => s.previous, 'previous', same(first)),
        );
        await listening.cancel();
        final again = _readOf(cubit);
        expect(again, isNot(same(first)));
        expect(again.description, 'Now pay first.');
        expect(_requestsOf(harness, ScriptedRequest.take), 0);
        expect(await _bindings(harness), 1);
        // Confirmed only by the user.
        await cubit.confirm();
        expect(cubit.state, isA<TakeSent>());
        await cubit.close();
      },
    );

    test(
      'the payment methods changed between the read and « Done », in the book and for the robot: never taken (second security review of #133, PB6)',
      () async {
        final harness = await TradeHarness.start();
        final cubit = _takeCubit(harness, await harness.shownOrder());
        await cubit.take();
        expect(cubit.state, isA<TakeReady>());
        harness.coordinator.bookView['payment_method'] = 'Wise';
        harness.coordinator.robotView['payment_method'] = 'Wise';

        await cubit.confirm();

        expect(_requestsOf(harness, ScriptedRequest.take), 0);
        expect(cubit.state, isNot(isA<TakeSent>()));
        await cubit.close();
      },
    );

    test(
      'the order changed again at that new preparation: said, nothing taken, never confirmed by itself',
      () async {
        final harness = await TradeHarness.start();
        final cubit = _takeCubit(harness, await harness.shownOrder());
        await cubit.take();
        // 3 % more since the page: the read at confirmation, and the new preparation against the page, both refuse.
        harness.coordinator.satoshisNow = 110107;

        await cubit.confirm();

        expect(
          (cubit.state as TakeIdle).problem,
          isA<TakeWasRefused>().having(
            (p) => p.refusal,
            'refusal',
            isA<TakeOrderChanged>(),
          ),
        );
        expect(_requestsOf(harness, ScriptedRequest.take), 0);
        await cubit.close();
      },
    );

    test(
      'the order gone at the confirmation: « This order is not available », nothing taken',
      () async {
        final harness = await TradeHarness.start();
        final cubit = _takeCubit(harness, await harness.shownOrder());
        await cubit.take();
        harness.coordinator.takenByAnother();

        await cubit.confirm();

        expect(
          (cubit.state as TakeIdle).problem,
          isA<TakeWasRefused>().having(
            (p) => p.refusal,
            'refusal',
            isA<TakeOrderGone>(),
          ),
        );
        expect(_requestsOf(harness, ScriptedRequest.take), 0);
        // An order found gone is not prepared again.
        expect((cubit.state as TakeIdle).orderGone, isTrue);
        final requests = harness.coordinator.requests.length;
        await cubit.take();
        expect(harness.coordinator.requests, hasLength(requests));
        await cubit.close();
      },
    );

    test(
      'the preparation gone at the confirmation (its key deleted): prepared again, waiting for the user',
      () async {
        final harness = await TradeHarness.start();
        final cubit = _takeCubit(harness, await harness.shownOrder());
        await cubit.take();
        final prepares = _requestsOf(harness, ScriptedRequest.book);
        // A key deleted, rather than replaced: since 2026-11-26 (#81) a key replaced by another trades too, so only a key gone still refuses the new preparation.
        harness.deleteKey();

        await cubit.confirm();

        // Prepared again: no key in the vault any more, so that preparation is refused and says why.
        expect(
          _requestsOf(harness, ScriptedRequest.book),
          greaterThan(prepares),
        );
        expect(
          (cubit.state as TakeIdle).problem,
          isA<TakeWasRefused>().having(
            (p) => p.refusal,
            'refusal',
            isA<TakeRobotRefused>(),
          ),
        );
        expect(_requestsOf(harness, ScriptedRequest.take), 0);
        await cubit.close();
      },
    );

    test(
      '« Go back » abandons: nothing sent, the robot never used again',
      () async {
        final harness = await TradeHarness.start();
        final cubit = _takeCubit(harness, await harness.shownOrder());
        await cubit.take();
        final requests = harness.coordinator.requests.length;

        cubit.back();

        expect(
          cubit.state,
          isA<TakeIdle>().having((s) => s.problem, 'problem', isNull),
        );
        expect(harness.coordinator.requests, hasLength(requests));
        await cubit.take();
        expect(await _bindings(harness), 2);
        await cubit.close();
      },
    );

    test(
      'closed with the take prepared (the page left, a system back): abandoned',
      () async {
        final harness = await TradeHarness.start();
        final shown = await harness.shownOrder();
        final cubit = _takeCubit(harness, shown);
        await cubit.take();

        await cubit.close();

        final again = _takeCubit(harness, shown);
        await again.take();
        expect(await _bindings(harness), 2);
        await again.close();
      },
    );

    test(
      'closed after a preparation that failed: the order is abandoned, its robot not kept (review of #126, n2)',
      () async {
        final harness = await TradeHarness.start();
        final shown = await harness.shownOrder();
        final cubit = _takeCubit(harness, shown);
        harness.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.unreachable,
        );
        await cubit.take();
        expect(
          (cubit.state as TakeIdle).problem,
          isA<TakeWasRefused>().having(
            (p) => p.refusal,
            'refusal',
            isA<TakeCoordinatorUnreadable>(),
          ),
        );

        await cubit.close();

        // Kept, the robot would have been used again (one binding): forgotten, a fresh one is reserved.
        final again = _takeCubit(harness, shown);
        await again.take();
        expect(await _bindings(harness), 2);
        await again.close();
      },
    );

    test(
      'closed while the order is read: nothing more emitted, and what was prepared is abandoned',
      () async {
        final harness = await TradeHarness.start();
        final shown = await harness.shownOrder();
        final hold = Completer<void>();
        final cubit = _takeCubit(harness, shown);
        harness.coordinator.hold = hold.future;

        final taking = cubit.take();
        await harness.settle();
        await cubit.close();
        harness.coordinator.hold = null;
        hold.complete();
        await taking;

        expect(cubit.state, isA<TakePreparing>());
        final again = _takeCubit(harness, shown);
        await again.take();
        expect(await _bindings(harness), 2);
        await again.close();
      },
    );

    test(
      'closed while the confirmation runs: the take the user confirmed goes on',
      () async {
        final harness = await TradeHarness.start();
        final cubit = _takeCubit(harness, await harness.shownOrder());
        await cubit.take();
        final hold = Completer<void>();
        harness.coordinator.hold = hold.future;

        final confirming = cubit.confirm();
        await harness.settle();
        await cubit.close();
        harness.coordinator.hold = null;
        hold.complete();
        await confirming;
        await harness.settle();

        expect(_requestsOf(harness, ScriptedRequest.take), 1);
        expect(await harness.activeRecords(), hasLength(1));
      },
    );

    for (final (label, before) in <(String, void Function(TradeHarness))>[
      (
        'the order changed',
        (h) => h.coordinator.description = 'Now pay first.',
      ),
      (
        'the coordinator could not be read',
        (h) => h.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.unreachable,
        ),
      ),
    ]) {
      test(
        'closed while the confirmation runs, which finds $label: the order\'s robot is not kept (security review of #133)',
        () async {
          final harness = await TradeHarness.start();
          final shown = await harness.shownOrder();
          final cubit = _takeCubit(harness, shown);
          await cubit.take();
          before(harness);
          final hold = Completer<void>();
          harness.coordinator.hold = hold.future;

          final confirming = cubit.confirm();
          await harness.settle();
          await cubit.close();
          harness.coordinator.hold = null;
          hold.complete();
          await confirming;
          await harness.settle();

          expect(_requestsOf(harness, ScriptedRequest.take), 0);
          // Kept, the robot would serve a new page of the order (one binding): forgotten, a fresh one is reserved.
          final again = _takeCubit(harness, shown);
          await again.take();
          expect(await _bindings(harness), 2);
          await again.close();
        },
      );
    }

    test(
      'the wait says each step as it starts, in order, and never one that has not started',
      () async {
        final harness = await TradeHarness.start();
        final cubit = _takeCubit(harness, await harness.shownOrder());
        TakeStep? stepOf() => switch (cubit.state) {
          TakePreparing(:final step) => step,
          TakeConfirming(:final step) => step,
          _ => null,
        };
        // Every request waits for its gate: the test lets one go at a time.
        var gate = Completer<void>();
        harness.coordinator.hold = gate.future;
        Future<void> letGo() async {
          final passing = gate;
          gate = Completer<void>();
          harness.coordinator.hold = gate.future;
          passing.complete();
          await harness.settle();
        }

        final taking = cubit.take();
        await harness.settle();
        // The book and the fees asked at once: the order is checked.
        expect(stepOf(), TakeStep.checkingOrder);
        await letGo();
        // The robot read back, on its own session.
        expect(stepOf(), TakeStep.creatingRobot);
        await letGo();
        // Its first contact.
        expect(stepOf(), TakeStep.creatingRobot);
        await letGo();
        // The robot reads the order.
        expect(stepOf(), TakeStep.readingOrder);
        await letGo();
        await taking;
        expect(cubit.state, isA<TakeReady>());

        final confirming = cubit.confirm();
        await harness.settle();
        expect(stepOf(), TakeStep.readingOrderAgain);
        await letGo();
        expect(stepOf(), TakeStep.sendingTake);
        harness.coordinator.hold = null;
        gate.complete();
        await confirming;
        expect(cubit.state, isA<TakeSent>());
        await cubit.close();
      },
    );

    test(
      'a robot kept for the order is not built again: no such step at a new preparation',
      () async {
        final harness = await TradeHarness.start();
        final cubit = _takeCubit(harness, await harness.shownOrder());
        await cubit.take();
        harness.coordinator.description = 'Now pay first.';
        final steps = <TakeStep>[];
        final listening = cubit.stream.listen((state) {
          if (state case TakePreparing(
            :final step?,
          ) when steps.lastOrNull != step) {
            steps.add(step);
          }
        });

        await cubit.confirm();
        await harness.settle();

        expect(steps, [TakeStep.checkingOrder, TakeStep.readingOrder]);
        await listening.cancel();
        await cubit.close();
      },
    );

    test('a step that runs long says it still waits', () async {
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
        isA<TakePreparing>().having((s) => s.slow, 'slow', isTrue),
      );
      harness.coordinator.hold = null;
      hold.complete();
      await taking;

      final again = Completer<void>();
      harness.coordinator.hold = again.future;
      final confirming = cubit.confirm();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        cubit.state,
        isA<TakeConfirming>().having((s) => s.slow, 'slow', isTrue),
      );
      harness.coordinator.hold = null;
      again.complete();
      await confirming;
      expect(cubit.state, isA<TakeSent>());
      await cubit.close();
    });

    test(
      'an order with an open trade here opens that trade, nothing taken again',
      () async {
        final harness = await TradeHarness.start();
        final shown = await harness.shownOrder();
        final first = _takeCubit(harness, shown);
        await _takeAndConfirm(first);
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

    test('closed while a cancel runs, it emits nothing after', () async {
      final statuses = await TradeScreenStatuses.make();
      final seen = await statuses.bondStep();
      final answer = Completer<Result<CancelOutcome, CancelRefusal>>();
      final cubit = TradeCubit(
        TradeScreenStatuses.record,
        (record, {signals = const Stream.empty(), onScreen = true}) =>
            const Stream.empty(),
        (record, seen, {bondLoss}) => answer.future,
      );
      final cancelling = cubit.cancel(seen);
      await cubit.close();
      answer.complete(Ok(CancelDone(TradeScreenStatuses.record, seen)));
      await expectLater(cancelling, completes);
    });

    // The order public again offers « Take Order » on the trade screen (#88): the take rules of #87 let the same order be taken anew once the earlier trade is over, with a fresh robot.
    for (final ending in ['a free cancel at 3', 'a take that expired']) {
      test('after $ending, the order public again is taken anew', () async {
        final (harness, cubit) = await taken();
        cubit.start();
        await harness.settle();
        if (ending == 'a free cancel at 3') {
          await cubit.cancel(_seen(cubit));
          await harness.settle();
        } else {
          await harness.elapse(
            ScriptedCoordinator.preTakeTime + const Duration(seconds: 30),
          );
        }
        expect(_seen(cubit).status, isA<PreTakeEnded>());

        final again = _takeCubit(harness, await harness.shownOrder());
        await _takeAndConfirm(again);
        await harness.settle();

        final sent = again.state;
        expect(sent, isA<TakeSent>());
        final record = (sent as TakeSent).record;
        expect(record.orderId, cubit.state.record.orderId);
        expect(
          record.robot.accountIndex,
          isNot(cubit.state.record.robot.accountIndex),
        );
        expect(harness.coordinator.holdsPreTake(harness.robot(0)), isFalse);
        await again.close();
        await cubit.close();
      });
    }

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
        await _takeAndConfirm(take);
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
