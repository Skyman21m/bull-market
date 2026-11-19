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

    for (final (direction, moved) in [
      ('raised to 380', 380.0),
      ('lowered to 120', 120.0),
    ]) {
      test(
        'another amount shown within the same contract, $direction with the sats of it: the state machine\'s alert alone, nothing compared at 6, 8 and 9 (functional review of #183, C5)',
        () async {
          final (harness, record, maker, _) = await taken(250);
          final order = harness.coordinator.order(record.orderId)
            ..takenAmount = moved
            // The sats of that amount at the coordinator's price with the premium.
            ..lastSatoshis = (moved * 100000000 / (91711.15 * 1.02)).floor();
          final six = await readOf(harness, record);
          expect(six.status, isA<WaitingForBoth>());
          expect(six.order?.takenAmount?.value, moved);
          expect(six.status.has<TradeTermsChanged>(), isTrue);
          expect(six.status.trail.takenAmount, 250);
          expect(six.contractAmountMoved, isTrue);
          expect(
            CheckPayoutRateUsecase.subjectAt(record, maker, six),
            isA<PayoutRateMismatch>(),
          );
          harness.coordinator.lockEscrow(record.orderId);
          final eight = await readOf(harness, record);
          expect(eight.status, isA<WaitingForPayout>());
          expect(eight.contractAmountMoved, isTrue);
          expect(
            CheckPayoutRateUsecase.subjectAt(record, maker, eight),
            isA<PayoutRateMismatch>(),
          );
          order.status = 9;
          final nine = await readOf(harness, record);
          expect(nine.status, isA<Chatting>());
          expect(nine.contractAmountMoved, isTrue);
          // Nothing compared, the invoice of 8 kept or not.
          for (final asked in [null, Sats.fromInt(250000)]) {
            expect(
              CheckPayoutRateUsecase.subjectAt(
                record,
                maker,
                nine,
                asked: asked,
              ),
              isA<PayoutRateMismatch>(),
              reason: '$asked',
            );
          }
        },
      );
    }

    test(
      'a contract kept, then read with no amount at 6, 8 and 9: never compared (security review of #183, C3; the trade screen\'s own tests read it in one session, `maker_panels_test.dart`)',
      () async {
        final (harness, record, maker, _) = await taken(250);
        final order = harness.coordinator.order(record.orderId);
        Future<TradeSeen> readWithout() async {
          order.takenAmount = null;
          final seen = await readOf(harness, record);
          order.takenAmount = 250;
          return seen;
        }

        void neverCompared(TradeSeen seen) {
          expect(seen.order, isNotNull);
          expect(seen.order?.takenAmount, isNull);
          expect(seen.status.has<TradeTermsChanged>(), isTrue);
          expect(seen.contractAmountMoved, isTrue);
          for (final asked in [null, Sats.fromInt(250000)]) {
            expect(
              CheckPayoutRateUsecase.subjectAt(
                record,
                maker,
                seen,
                asked: asked,
              ),
              isNot(isA<PayoutRateCompared>()),
            );
          }
        }

        neverCompared(await readWithout());
        harness.coordinator.lockEscrow(record.orderId);
        expect((await readOf(harness, record)).status, isA<WaitingForPayout>());
        neverCompared(await readWithout());
        order.status = 9;
        expect((await readOf(harness, record)).status, isA<Chatting>());
        neverCompared(await readWithout());
      },
    );

    test(
      'the alert and the silence of the rule follow one comparison, at its very tolerance both ways (security review of #183, R1)',
      () async {
        // Kept 200; read 1.1·10⁻⁶ lower is another amount (beyond 5·10⁻⁹ of the read, about 10⁻⁶), 9·10⁻⁷ higher the same.
        for (final (read, moved) in [
          (199.9999989, true),
          (200.0000009, false),
        ]) {
          final (harness, record, maker, _) = await taken(200);
          harness.coordinator.order(record.orderId).takenAmount = read;
          final seen = await readOf(harness, record);
          expect(seen.status, isA<WaitingForBoth>(), reason: '$read');
          expect(seen.status.has<TradeTermsChanged>(), moved, reason: '$read');
          expect(seen.contractAmountMoved, moved, reason: '$read');
          final subject = CheckPayoutRateUsecase.subjectAt(record, maker, seen);
          expect(
            subject,
            moved ? isA<PayoutRateMismatch>() : isA<PayoutRateCompared>(),
            reason: '$read',
          );
        }
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

  group(
    'what was asked here, on the reads of an order made at a fixed amount (#211, security review of #183, R9)',
    () {
      double? askedOf(TradeSeen? seen) => switch (seen?.asked) {
        FixedOrderAmount(:final amount) => amount.value,
        _ => null,
      };

      Future<(MakeHarness, TradeRecord)> fixed() async {
        final harness = await MakeHarness.start();
        final started = valueOf(await harness.makeOrder());
        if (started is! MakeStarted) throw StateError('not made: $started');
        return (harness, started.record);
      }

      test(
        'the make\'s own first read and the reads of the watch carry the amount asked, 100 EUR (its MC4c and MC4d)',
        () async {
          final (harness, record) = await fixed();
          // The make's first read, as the run stored it (`MakeOrderUsecase`, then `TradeReader.keep`).
          final first = harness.watch.lastStored(record);
          expect(first?.stored, isTrue);
          expect(first?.status, isA<WaitingForMakerBond>());
          expect(askedOf(first), 100);
          harness.coordinator
            ..lockMakerBond(record.orderId)
            ..take(record.orderId, harness.robot(4));
          // A read of the real reader, through the watch.
          final six = await readOf(harness, record);
          expect(six.status, isA<WaitingForBoth>());
          expect(askedOf(six), 100);
          expect(six.contractAmount?.value, 100);
          expect(askedOf(harness.watch.lastStored(record)), 100);
        },
      );

      test(
        'a fixed amount read as a range: said moved, the state machine\'s alert, no amount of the contract written (its MC4b)',
        () async {
          final (harness, record) = await fixed();
          harness.coordinator
            ..lockMakerBond(record.orderId)
            ..take(record.orderId, harness.robot(4))
            ..orderChanges[record.orderId] = {
              'has_range': true,
              'min_amount': '50.00000000',
              'max_amount': '200.00000000',
            };
          final six = await readOf(harness, record);
          expect(six.order?.amount, isA<RangeOrderAmount>());
          expect(askedOf(six), 100);
          expect(six.status.has<TradeTermsChanged>(), isTrue);
          expect(six.contractAmountMoved, isTrue);
          expect(six.contractAmount, isNull);
        },
      );
    },
  );
}
