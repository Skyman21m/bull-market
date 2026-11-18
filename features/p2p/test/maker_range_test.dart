import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/trade/maker_terms.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_rate_check.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/check_payout_rate_usecase.dart';
import 'package:p2p/testing.dart' show FakeP2pWalletPort;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';

/// An order made here with the advanced options (#183): a range, a description, its durations and bond size, through the make use case, the records and the state machine over `ScriptedMakerCoordinator` (never a real one, nothing paid); the owner's payment rule on it: the maker bond on the range's maximum, then the amount the take chose, kept with the contract, for the buyer's comparison.
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

  final rangeRequest = MakeHarness.request(
    range: (100, 400),
    description: 'Revolut only, please',
    publicDuration: const Duration(minutes: 10),
    escrowDuration: const Duration(hours: 10),
    bondSize: 5,
  );

  Future<(MakeHarness, MakeStarted)> made() async {
    final harness = await MakeHarness.start();
    final started = valueOf(await harness.makeOrder(rangeRequest));
    if (started is! MakeStarted) throw StateError('not made: $started');
    return (harness, started);
  }

  Future<MakerTerms> termsOf(MakeHarness harness, TradeRecord record) async =>
      await CheckPayoutRateUsecase(
        harness.reader,
        FakeP2pWalletPort(Ok(Sats.fromInt(50000))),
      ).termsOf(record) ??
      (throw StateError('no terms'));

  test(
    'the make sends the range, the description, the durations and the bond size, and keeps them as asked',
    () async {
      final (harness, started) = await made();
      final order = harness.coordinator.order(started.record.orderId);
      // What the fake received, as `MakerView.post` reads the body (`api/views.py:90-216`).
      expect(order.body['amount'], isNull);
      expect(order.body['has_range'], isTrue);
      expect(order.body['min_amount'], 100);
      expect(order.body['max_amount'], 400);
      expect(order.body['description'], 'Revolut only, please');
      expect(order.body['public_duration'], 600);
      expect(order.body['escrow_duration'], 36000);
      expect(order.body['bond_size'], 5);
      final terms = await termsOf(harness, started.record);
      expect(terms.request, rangeRequest);
      // The first read at 0 agrees with the terms: no warning, the bond shown.
      expect(started.status, isA<WaitingForMakerBond>());
      expect(started.status.warnings, isEmpty);
    },
  );

  test(
    'the maker bond on the range\'s maximum: the coordinator\'s (`api/logics.py:1266-1268`) agrees, and the owner\'s rule compares with the maximum\'s',
    () async {
      final (harness, started) = await made();
      final terms = await termsOf(harness, started.record);
      final status = started.status as WaitingForMakerBond;
      final bond = harness.coordinator.order(started.record.orderId);
      expect(bond.hasRange, isTrue);
      expect(status.has<BondAmountOutsideOrder>(), isFalse);
      // 400 EUR at 91,711.15 × 1.02, 5 %: 21,379.999… sats; 100 EUR would be 5,344.99….
      final check = WalletRateCheck.ofMakerBond(
        terms,
        asked: Sats.fromInt(21379),
        wallet: P2pWalletRateRead(91711.15),
      );
      expect(check, isA<WalletRateAtWallet>());
      final compared = check as WalletRateAtWallet;
      expect(compared.expected, Sats.fromInt(21379));
      expect(compared.warns, isFalse);
      // More than 10 % above the maximum's bond warns; a bond on the minimum is far below it, never a warning (fewer sats are paid).
      expect(
        WalletRateCheck.ofMakerBond(
          terms,
          asked: Sats.fromInt(23518),
          wallet: P2pWalletRateRead(91711.15),
        ).warns,
        isTrue,
      );
      expect(
        WalletRateCheck.ofMakerBond(
          terms,
          asked: Sats.fromInt(23517),
          wallet: P2pWalletRateRead(91711.15),
        ).warns,
        isFalse,
      );
      expect(terms.bondAgrees(Sats.fromInt(21379)), isTrue);
      expect(terms.bondAgrees(Sats.fromInt(5344)), isFalse);
    },
  );

  group('the amount the take chose', () {
    Future<(MakeHarness, TradeRecord, MakerTerms, TradeSeen)> taken(
      double amount,
    ) async {
      final (harness, started) = await made();
      final record = started.record;
      harness.coordinator
        ..lockMakerBond(record.orderId)
        ..take(record.orderId, harness.robot(4), amount: amount);
      final seen = await readOf(harness, record);
      return (harness, record, await termsOf(harness, record), seen);
    }

    test(
      'kept with the contract, and compared at the Bull wallet\'s price for that amount',
      () async {
        final (_, record, maker, seen) = await taken(250);
        expect(seen.status, isA<WaitingForBoth>());
        expect(seen.status.trail.takenAmount, 250);
        final subject = CheckPayoutRateUsecase.subjectAt(record, maker, seen);
        expect(subject, isA<PayoutRateCompared>());
        final compared = subject as PayoutRateCompared;
        expect(compared.amount.value, 250);
        // 250 EUR at 91,711.15 × 1.02: 267,249.99… sats.
        final check = CheckPayoutRateUsecase.compare(
          maker,
          compared,
          P2pWalletRateRead(91711.15),
        );
        expect((check as WalletRateAtWallet).expected, Sats.fromInt(267249));
      },
    );

    test(
      'another amount shown later within the same contract: said by the state machine, the comparison still on the amount kept',
      () async {
        final (harness, record, maker, _) = await taken(250);
        harness.coordinator.order(record.orderId).takenAmount = 120;
        final seen = await readOf(harness, record);
        expect(seen.status, isA<WaitingForBoth>());
        expect(seen.order?.takenAmount?.value, 120);
        expect(seen.status.has<TradeTermsChanged>(), isTrue);
        expect(seen.status.trail.takenAmount, 250);
        final subject = CheckPayoutRateUsecase.subjectAt(record, maker, seen);
        expect((subject as PayoutRateCompared).amount.value, 250);
      },
    );

    test(
      'an amount outside the range is refused, never compared (`api/logics.py:190-194`)',
      () async {
        final (_, record, maker, seen) = await taken(500);
        expect(seen.status, isNot(isA<WaitingForBoth>()));
        expect(seen.status.trail.takenAmount, isNull);
        expect(
          CheckPayoutRateUsecase.subjectAt(record, maker, seen),
          isNot(isA<PayoutRateCompared>()),
        );
      },
    );

    test(
      'a range\'s contract amount is one within its bounds only, none of its own',
      () async {
        final (_, record, maker, seen) = await taken(250);
        final status = seen.status as WaitingForBoth;
        expect(
          maker.contractAmount(null),
          isNull,
          reason: 'a range has no amount of its own',
        );
        expect(status.trail.takenAmount, isNotNull);
        expect(maker.contractAmount(FiatAmount.tryCreate(400.01)), isNull);
        expect(maker.contractAmount(FiatAmount.tryCreate(99.99)), isNull);
        expect(maker.contractAmount(FiatAmount.tryCreate(100))?.value, 100);
        expect(maker.contractAmount(FiatAmount.tryCreate(400))?.value, 400);
        expect(record.origin, TradeOrigin.madeHere);
      },
    );
  });
}
