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

  group('the use case', () {
    test(
      'at 6, the sats the buyer receives against the contract\'s amount at the wallet\'s price, read once, through the port, for the order\'s currency',
      () async {
        final (harness, record, seen) = await taken();
        expect(seen.status, isA<WaitingForBoth>());
        final port = wallet(P2pWalletRateRead(91711.15));
        final check = await CheckPayoutRateUsecase(
          harness.reader,
          port,
        ).execute(record, seen);
        expect(check, isA<WalletRateAtWallet>());
        check as WalletRateAtWallet;
        expect(check.side, WalletRateSide.receives);
        expect(check.asked, (seen.status as WaitingForBoth).payoutAmount);
        expect(port.ratesAsked.single.$2.code, 'EUR');
        expect(port.ratesAsked.single.$1, record.network);
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
        await CheckPayoutRateUsecase(
          harness.reader,
          wallet(const P2pWalletRateNotPriced()),
        ).execute(record, seen),
        isA<WalletRateNotPriced>(),
      );
      expect(
        await CheckPayoutRateUsecase(
          harness.reader,
          wallet(const P2pWalletRateUnavailable()),
        ).execute(record, seen),
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
        });
        addTearDown(cubit.close);
        await cubit.show(six);
        expect(asked, hasLength(1));
        expect(cubit.state, isA<PayoutRateChecked>());
        expect(
          (cubit.state as PayoutRateChecked).check,
          isA<WalletRateUnverified>(),
        );
        // Shown again, or at 8 of the same contract: no read.
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
        await harness.elapse(const Duration(minutes: 10));
        harness.coordinator.take(record.orderId, harness.robot(5));
        final next = await readOf(harness, record);
        expect(next.status.trail.take, 1);
        await cubit.show(next);
        expect(asked, hasLength(3));
      },
    );

    test('a step outside the rule shows nothing and reads nothing', () async {
      final harness = await MakeHarness.start();
      final record =
          (valueOf(await harness.makeOrder()) as MakeStarted).record;
      final atZero = await readOf(harness, record);
      var asked = 0;
      final cubit = PayoutRateCubit(record, (record, seen) async {
        asked++;
        return null;
      });
      addTearDown(cubit.close);
      await cubit.show(atZero);
      expect(asked, 0);
      expect(cubit.state, isA<PayoutRateNone>());
    });
  });
}
