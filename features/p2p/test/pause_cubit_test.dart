import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_pause.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedMakerRequest;
import 'package:primitives/primitives.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';

/// The trade screen's cubit over the real pause use case, watch, records and state machine, the coordinator played by `ScriptedMakerCoordinator` (#184): what the screen's taps reach, counted in requests that reached the coordinator.
void main() {
  T valueOf<T>(Result<T, Failure> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => fail('$failure'),
  };

  /// An order made here, its bond locked, followed by a cubit as the trade screen builds it, at its first read: public.
  Future<(MakeHarness, TradeRecord, TradeCubit)> followed() async {
    final harness = await MakeHarness.start();
    final record = (valueOf(await harness.makeOrder()) as MakeStarted).record;
    final first = harness.watchOf(record);
    await harness.settle();
    await first.subscription.cancel();
    harness.coordinator.lockMakerBond(record.orderId);
    final cubit = TradeCubit(
      record,
      harness.watch.execute,
      harness.cancel.execute,
      lastStored: harness.watch.lastStored,
      pause: harness.pause.execute,
    )..start();
    addTearDown(cubit.close);
    await harness.settle();
    final seen = cubit.state.seen;
    expect(
      seen?.status,
      isA<MakerOrderPublic>().having((s) => s.paused, 'paused', false),
    );
    return (harness, record, cubit);
  }

  int pauses(MakeHarness harness) => harness.coordinator.received
      .where((kind) => kind == ScriptedMakerRequest.pause)
      .length;

  test(
    'two pauses asked at once from the same status: one request reaches the coordinator, the order paused, shown paused',
    () async {
      final (harness, record, cubit) = await followed();
      final seen = cubit.state.seen;
      if (seen == null) fail('no status');
      final first = cubit.pause(seen);
      final second = cubit.pause(seen);
      expect(cubit.state.pause, isA<PauseRunning>());
      await Future.wait([first, second]);
      await harness.settle();
      expect(pauses(harness), 1);
      expect(harness.coordinator.order(record.orderId).status, 2);
      expect(
        cubit.state.seen?.status,
        isA<MakerOrderPublic>().having((s) => s.paused, 'paused', true),
      );
      expect(
        cubit.state.pause,
        isA<PauseIdle>()
            .having((p) => p.notice, 'notice', isNull)
            .having((p) => p.pausedHere, 'pausedHere', isTrue),
      );
    },
  );

  test(
    'a second pause asked from the status shown before the first ended: refused by the fresh read, one request',
    () async {
      final (harness, record, cubit) = await followed();
      final seen = cubit.state.seen;
      if (seen == null) fail('no status');
      await cubit.pause(seen);
      // A tap from the status the user saw before the first ended (another screen of the same trade).
      await cubit.pause(seen);
      await harness.settle();
      expect(pauses(harness), 1);
      expect(harness.coordinator.order(record.orderId).status, 2);
      expect(
        cubit.state.pause,
        isA<PauseIdle>().having(
          (p) => p.notice,
          'notice',
          isA<PauseWasRefused>().having(
            (n) => n.refusal,
            'refusal',
            isA<PauseStatusMoved>(),
          ),
        ),
      );
    },
  );

  test(
    'paused here, then unpaused from another app: the next read shows it public, and the cubit says so',
    () async {
      final (harness, record, cubit) = await followed();
      final seen = cubit.state.seen;
      if (seen == null) fail('no status');
      await cubit.pause(seen);
      await harness.settle();
      expect(cubit.state.pause, isA<PauseIdle>());
      // The official app with the same Garage Key resumes it.
      harness.coordinator.pause(record.orderId);
      cubit.signal(TradeWatchSignal.readNow);
      await harness.settle();
      await harness.elapse(const Duration(minutes: 4));
      expect(
        cubit.state.seen?.status,
        isA<MakerOrderPublic>().having((s) => s.paused, 'paused', false),
      );
      expect(
        cubit.state.pause,
        isA<PauseIdle>().having(
          (p) => p.notice,
          'notice',
          isA<PausePublicAgain>(),
        ),
      );
      expect(pauses(harness), 1);
    },
  );

  test(
    'a request whose answer is lost and that did nothing: unknown, the order shown public, nothing sent again by the cubit or the watch',
    () async {
      final (harness, record, cubit) = await followed();
      final seen = cubit.state.seen;
      if (seen == null) fail('no status');
      harness.coordinator.failNext(
        ScriptedMakerRequest.pause,
        ScriptedFault.timedOut,
      );
      await cubit.pause(seen);
      await harness.settle();
      await harness.elapse(const Duration(minutes: 10));
      expect(pauses(harness), 1);
      expect(
        cubit.state.pause,
        isA<PauseIdle>()
            .having((p) => p.notice, 'notice', isA<PauseWasUnknown>())
            .having((p) => p.wanted, 'wanted', PauseWanted.paused),
      );
      expect(showsPublicOrder(cubit.state.seen ?? seen), isTrue);
      expect(harness.coordinator.order(record.orderId).status, 1);
    },
  );

  test(
    'one tap, three requests: the read before, the pause, the read after; the watch reads nothing more at once (functional review of #184, R2: four before)',
    () async {
      final (harness, record, cubit) = await followed();
      final seen = cubit.state.seen;
      if (seen == null) fail('no status');
      final before = harness.coordinator.received.length;
      await cubit.pause(seen);
      await harness.settle();
      expect(harness.coordinator.received.sublist(before), [
        ScriptedMakerRequest.order,
        ScriptedMakerRequest.pause,
        ScriptedMakerRequest.order,
      ]);
    },
  );

  test(
    'an unknown outcome whose request lands, read paused by the watch, then unpaused from another app: said public again (functional review of #184, R6)',
    () async {
      final (harness, record, cubit) = await followed();
      final seen = cubit.state.seen;
      if (seen == null) fail('no status');
      harness.coordinator.failNext(
        ScriptedMakerRequest.pause,
        ScriptedFault.landsLate,
      );
      await cubit.pause(seen);
      await harness.settle();
      expect(
        cubit.state.pause,
        isA<PauseIdle>().having(
          (p) => p.notice,
          'notice',
          isA<PauseWasUnknown>(),
        ),
      );
      harness.coordinator.landLate();
      cubit.signal(TradeWatchSignal.readNow);
      await harness.settle();
      expect(
        cubit.state.seen?.status,
        isA<MakerOrderPublic>().having((s) => s.paused, 'paused', true),
      );
      expect(
        cubit.state.pause,
        isA<PauseIdle>()
            .having((p) => p.notice, 'notice', isNull)
            .having((p) => p.pausedHere, 'pausedHere', isTrue),
      );
      harness.coordinator.pause(record.orderId);
      cubit.signal(TradeWatchSignal.readNow);
      await harness.settle();
      expect(
        cubit.state.pause,
        isA<PauseIdle>().having(
          (p) => p.notice,
          'notice',
          isA<PausePublicAgain>(),
        ),
      );
      expect(pauses(harness), 1);
    },
  );
}
