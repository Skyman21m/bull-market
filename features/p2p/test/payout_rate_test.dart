import 'dart:async';

import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_rate_check.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/check_payout_rate_usecase.dart';
import 'package:p2p/src/presentation/payout_rate_cubit.dart';
import 'package:p2p/testing.dart' show FakeP2pWalletPort;
import 'package:primitives/primitives.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';

/// The owner's payment rule on a maker buyer's side (#182, design note § 3.3): the use case over the real records and state machine of an order made and taken (`ScriptedMakerCoordinator`, never a real one), the wallet's price from the wallet's fake port, and the cubit's reads, once per contract and step.
void main() {
  T valueOf<T, F extends Failure>(Result<T, F> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  Future<TradeSeen> readOf(MakeHarness harness, TradeRecord record) async {
    final run = harness.watchOf(record);
    await harness.settle();
    final seen = run.lastStatus.seen;
    await run.subscription.cancel();
    return seen;
  }

  /// An order made and taken: its record and its status at 6.
  Future<(MakeHarness, TradeRecord, TradeSeen)> taken() async {
    final harness = await MakeHarness.start();
    final record = (valueOf(await harness.makeOrder()) as MakeStarted).record;
    harness.coordinator
      ..lockMakerBond(record.orderId)
      ..take(record.orderId, harness.robot(4));
    return (harness, record, await readOf(harness, record));
  }

  FakeP2pWalletPort wallet(P2pWalletBitcoinRate rate) =>
      FakeP2pWalletPort(Ok(Sats.fromInt(50000)))..rate = rate;

  /// The comparison a finding holds, which the test expects.
  WalletRateCheck checkOf(PayoutRateFinding? finding) => switch (finding) {
    PayoutRateFound(:final check) => check,
    final other => throw StateError('no comparison: $other'),
  };

  group('the use case', () {
    test(
      'at 6, the sats the buyer receives against the contract\'s amount at the wallet\'s price, read once, through the port, for the order\'s currency',
      () async {
        final (harness, record, seen) = await taken();
        expect(seen.status, isA<WaitingForBoth>());
        final port = wallet(P2pWalletRateRead(91711.15));
        final check = checkOf(
          await CheckPayoutRateUsecase(
            harness.reader,
            port,
          ).execute(record, seen),
        );
        expect(check, isA<WalletRateAtWallet>());
        expect(check.side, WalletRateSide.receives);
        expect(check.asked, (seen.status as WaitingForBoth).payoutAmount);
        expect(port.ratesAsked.single.$2.code, 'EUR');
        expect(port.ratesAsked.single.$1, record.network);
      },
    );

    test(
      'at 9, where the coordinator gives no `trade_satoshis` (`api/views.py:346-356`), the order\'s `last_satoshis` less the maker fee: the same sats as the payout of 8',
      () async {
        final (harness, record, six) = await taken();
        harness.coordinator.lockEscrow(record.orderId);
        final eight = await readOf(harness, record);
        expect(eight.status, isA<WaitingForPayout>());
        final payout = (eight.status as WaitingForPayout).payoutAmount;
        harness.coordinator.order(record.orderId).status = 9;
        final nine = await readOf(harness, record);
        expect(nine.status, isA<Chatting>());
        // The fake gives what the reference gives at 9: no `trade_satoshis`.
        expect(nine.order?.tradeSatoshis, isNull);
        expect(nine.order?.satoshisNow, isNotNull);
        final check = checkOf(
          await CheckPayoutRateUsecase(
            harness.reader,
            wallet(P2pWalletRateRead(91711.15)),
          ).execute(record, nine),
        );
        expect(check.asked, payout);
      },
    );

    test(
      'nothing read before the take, nor for a status not marked stored',
      () async {
        final harness = await MakeHarness.start();
        final record =
            (valueOf(await harness.makeOrder()) as MakeStarted).record;
        final port = wallet(P2pWalletRateRead(91711.15));
        final usecase = CheckPayoutRateUsecase(harness.reader, port);
        final atZero = await readOf(harness, record);
        expect(await usecase.execute(record, atZero), isNull);
        final (_, takenRecord, six) = await taken();
        expect(
          await usecase.execute(
            takenRecord,
            TradeSeen(six.status, order: six.order, stored: false),
          ),
          isNull,
        );
        expect(port.ratesAsked, isEmpty);
      },
    );

    test('a currency the wallet does not price, a price not read', () async {
      final (harness, record, seen) = await taken();
      expect(
        checkOf(
          await CheckPayoutRateUsecase(
            harness.reader,
            wallet(const P2pWalletRateNotPriced()),
          ).execute(record, seen),
        ),
        isA<WalletRateNotPriced>(),
      );
      expect(
        checkOf(
          await CheckPayoutRateUsecase(
            harness.reader,
            wallet(const P2pWalletRateUnavailable()),
          ).execute(record, seen),
        ),
        isA<WalletRateUnverified>(),
      );
    });
  });

  group('the cubit', () {
    test(
      'one read per contract and step: 6 then 8 is one read, 9 another, a next contract another; « Retry » only after a price not read',
      () async {
        final (harness, record, six) = await taken();
        final asked = <TradeSeen>[];
        final port = wallet(const P2pWalletRateUnavailable());
        final usecase = CheckPayoutRateUsecase(harness.reader, port);
        final cubit = PayoutRateCubit(record, (record, seen) {
          asked.add(seen);
          return usecase.execute(record, seen);
        }, now: () => harness.now);
        addTearDown(cubit.close);
        await cubit.show(six);
        expect(asked, hasLength(1));
        expect(
          (cubit.state as PayoutRateChecked).check,
          isA<WalletRateUnverified>(),
        );
        // Shown again within 3 minutes: no read.
        await cubit.show(six);
        expect(asked, hasLength(1));
        // « Retry »: read again.
        port.rate = P2pWalletRateRead(91711.15);
        await cubit.retry();
        expect(asked, hasLength(2));
        expect(
          (cubit.state as PayoutRateChecked).check,
          isA<WalletRateAtWallet>(),
        );
        // « Retry » after a price read: nothing.
        await cubit.retry();
        expect(asked, hasLength(2));
        // A next contract after a return to the book: read again.
        harness.coordinator.backToBook(record.orderId);
        await readOf(harness, record);
        await harness.elapse(const Duration(minutes: 1));
        harness.coordinator.take(record.orderId, harness.robot(5));
        final next = await readOf(harness, record);
        expect(next.status.trail.take, 1);
        await cubit.show(next);
        expect(asked, hasLength(3));
      },
    );

    test(
      'read again only when the step appears anew (the screen built or shown again, the app back) or its status moves (8 an hour after 6) with a read 3 minutes old; a new read of the same status never reads again',
      () async {
        final (harness, record, six) = await taken();
        final asked = <TradeSeen>[];
        final usecase = CheckPayoutRateUsecase(
          harness.reader,
          wallet(P2pWalletRateRead(91711.15)),
        );
        final cubit = PayoutRateCubit(record, (record, seen) {
          asked.add(seen);
          return usecase.execute(record, seen);
        }, now: () => harness.now);
        addTearDown(cubit.close);
        await cubit.show(six, appeared: true);
        expect(asked, hasLength(1));
        await harness.elapse(const Duration(minutes: 2, seconds: 59));
        await cubit.show(six, appeared: true);
        expect(asked, hasLength(1));
        await harness.elapse(const Duration(seconds: 1));
        // The watch's next read of the same status: never a read by itself.
        await cubit.show(six);
        expect(asked, hasLength(1));
        // The screen shown again: read again, once.
        await cubit.show(six, appeared: true);
        expect(asked, hasLength(2));
        await cubit.show(six, appeared: true);
        expect(asked, hasLength(2));
        // 8 an hour later, the same step at another status.
        harness.coordinator.lockEscrow(record.orderId);
        await harness.elapse(const Duration(hours: 1));
        final eight = await readOf(harness, record);
        expect(eight.status, isA<WaitingForPayout>());
        await cubit.show(eight);
        expect(asked, hasLength(3));
        await cubit.show(eight);
        expect(asked, hasLength(3));
      },
    );

    test(
      'a late answer of a step no longer shown never replaces the step shown',
      () async {
        final (harness, record, six) = await taken();
        harness.coordinator.lockEscrow(record.orderId);
        await readOf(harness, record);
        harness.coordinator.order(record.orderId).status = 9;
        final nine = await readOf(harness, record);
        final answers = <Completer<PayoutRateFinding?>>[];
        final cubit = PayoutRateCubit(record, (record, seen) {
          final answer = Completer<PayoutRateFinding?>();
          answers.add(answer);
          return answer.future;
        }, now: () => harness.now);
        addTearDown(cubit.close);
        unawaited(cubit.show(six));
        await pumpEventQueue();
        unawaited(cubit.show(nine));
        await pumpEventQueue();
        expect(answers, hasLength(2));
        answers[1].complete(const PayoutRateNoSats());
        await pumpEventQueue();
        expect(cubit.state, isA<PayoutRateSatsMissing>());
        expect((cubit.state as PayoutRateSatsMissing).step.fiatSent, isTrue);
        // The answer of 6 lands late: dropped.
        answers[0].complete(null);
        await pumpEventQueue();
        expect(cubit.state, isA<PayoutRateSatsMissing>());
      },
    );

    test('a step outside the rule shows nothing and reads nothing', () async {
      final harness = await MakeHarness.start();
      final record = (valueOf(await harness.makeOrder()) as MakeStarted).record;
      final atZero = await readOf(harness, record);
      var asked = 0;
      final cubit = PayoutRateCubit(record, (record, seen) async {
        asked++;
        return null;
      }, now: () => harness.now);
      addTearDown(cubit.close);
      await cubit.show(atZero);
      expect(asked, 0);
      expect(cubit.state, isA<PayoutRateNone>());
    });

    test(
      'a taker\'s trade never sees the rule, not even « reading »',
      () async {
        final (harness, record, six) = await taken();
        final taker = TradeRecord(
          robot: record.robot,
          coordinatorAlias: record.coordinatorAlias,
          coordinatorOnion: record.coordinatorOnion,
          orderId: record.orderId,
          role: TradeRole.buyer,
          origin: TradeOrigin.takenHere,
          takenAt: record.takenAt,
          confirmedAt: record.confirmedAt,
          closedAt: null,
        );
        final states = <PayoutRateState>[];
        var asked = 0;
        final cubit = PayoutRateCubit(taker, (record, seen) async {
          asked++;
          return null;
        }, now: () => harness.now);
        addTearDown(cubit.close);
        final sub = cubit.stream.listen(states.add);
        addTearDown(sub.cancel);
        await cubit.show(six);
        await pumpEventQueue();
        expect(asked, 0);
        expect(states, isEmpty);
      },
    );
  });
}
