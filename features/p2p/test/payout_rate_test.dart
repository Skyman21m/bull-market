import 'dart:async';

import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/maker_terms.dart';
import 'package:p2p/src/domain/trade/payout_trace.dart';
import 'package:p2p/src/domain/trade/shown_alerts.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_rate_check.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/check_payout_rate_usecase.dart';
import 'package:p2p/src/presentation/payout_rate_cubit.dart';
import 'package:p2p/testing.dart' show FakeP2pWalletPort;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsCurrency;
import 'package:test/test.dart';

import 'support/make_harness.dart';

/// The owner's payment rule on a maker buyer's side (#182, design note § 3.3): the use case over the real records and state machine of an order made and taken (`ScriptedMakerCoordinator`, never a real one), the wallet's price from the wallet's fake port, and the cubit's reads.
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

  /// The payout of contract [take] of [record] recorded as given from this wallet (#204), as a « Submit » of an invoice this wallet gave records it.
  Future<void> givenHere(
    MakeHarness harness,
    TradeRecord record, {
    int take = 0,
  }) async => expect(
    await harness.payouts.recordPayout(
      record,
      take: take,
      source: PayoutTraceSource.thisWallet,
      kind: PayoutTraceKind.invoice,
      at: harness.now,
    ),
    isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'written', isTrue),
  );

  FakeP2pWalletPort wallet(P2pWalletBitcoinRate rate) =>
      FakeP2pWalletPort(Ok(Sats.fromInt(50000)))..rate = rate;

  Future<MakerTerms> termsOf(MakeHarness harness, TradeRecord record) async =>
      switch (await CheckPayoutRateUsecase(
        harness.reader,
        wallet(P2pWalletRateRead(91711.15)),
      ).termsOf(record)) {
        MakerPayoutTerms(:final maker) => maker,
        _ => throw StateError('no terms'),
      };

  PayoutRateCompared comparedOf(PayoutRateSubject? subject) =>
      switch (subject) {
        final PayoutRateCompared compared => compared,
        final other => throw StateError('nothing compared: $other'),
      };

  /// The cubit over [record] and [harness]'s records, the wallet's price from [port], each read counted in [reads].
  PayoutRateCubit cubitOf(
    MakeHarness harness,
    TradeRecord record,
    FakeP2pWalletPort port, {
    List<Object>? reads,
    PayoutRateMemory? memory,
    Future<P2pWalletBitcoinRate> Function()? held,
  }) {
    final usecase = CheckPayoutRateUsecase(harness.reader, port);
    final cubit = PayoutRateCubit(
      record,
      terms: usecase.termsOf,
      price: (record, maker) {
        reads?.add(record);
        return held?.call() ?? usecase.priceOf(record, maker);
      },
      memory: memory ?? PayoutRateMemory(),
      now: () => harness.now,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  group('the use case', () {
    test(
      'at 6, the sats of the invoice the payout panel asks (`PayoutAsk.buyerSats`) against the contract\'s amount; the price read through the port for the order\'s currency',
      () async {
        final (harness, record, seen) = await taken();
        expect(seen.status, isA<WaitingForBoth>());
        final port = wallet(P2pWalletRateRead(91711.15));
        final usecase = CheckPayoutRateUsecase(harness.reader, port);
        final maker = await termsOf(harness, record);
        final subject = comparedOf(
          CheckPayoutRateUsecase.subjectAt(record, maker, seen),
        );
        final ask = valueOf(PayoutAsk.of(record, seen));
        expect(subject.received, ask.buyerSats);
        expect(subject.keep, ask.buyerSats);
        final check = CheckPayoutRateUsecase.compare(
          maker,
          subject,
          await usecase.priceOf(record, MakerPayoutTerms(maker)),
        );
        expect(check, isA<WalletRateAtWallet>());
        expect(check.side, WalletRateSide.receives);
        expect(port.ratesAsked.single.$2.code, 'EUR');
        expect(port.ratesAsked.single.$1, record.network);
      },
    );

    test(
      'at 9, where the coordinator gives no `trade_satoshis` (`api/views.py:346-356`): the order\'s `last_satoshis` less the maker fee, the same sats as the invoice of 8; without them kept, said as the coordinator\'s figure of now',
      () async {
        final (harness, record, six) = await taken();
        harness.coordinator.lockEscrow(record.orderId);
        final eight = await readOf(harness, record);
        expect(eight.status, isA<WaitingForPayout>());
        final invoice = valueOf(PayoutAsk.of(record, eight)).buyerSats;
        harness.coordinator.order(record.orderId).status = 9;
        final nine = await readOf(harness, record);
        expect(nine.status, isA<Chatting>());
        // The fake gives what the reference gives at 9: no `trade_satoshis`.
        expect(nine.order?.tradeSatoshis, isNull);
        expect(nine.order?.satoshisNow, isNotNull);
        final maker = await termsOf(harness, record);
        final kept = comparedOf(
          CheckPayoutRateUsecase.subjectAt(record, maker, nine, asked: invoice),
        );
        expect(kept.received, invoice);
        expect(kept.basis, const PayoutRateAsked());
        final told = comparedOf(
          CheckPayoutRateUsecase.subjectAt(record, maker, nine),
        );
        expect(told.received, invoice);
        expect(told.basis, const PayoutRateToldNow());
      },
    );

    test(
      'at 9, a figure of now above the invoice kept: the smaller compared, and the two said',
      () async {
        final (harness, record, six) = await taken();
        harness.coordinator.order(record.orderId).status = 9;
        final nine = await readOf(harness, record);
        final maker = await termsOf(harness, record);
        final asked = Sats.fromInt(49988);
        final subject = comparedOf(
          CheckPayoutRateUsecase.subjectAt(record, maker, nine, asked: asked),
        );
        expect(subject.received, asked);
        expect(
          subject.basis,
          PayoutRateTold(
            told: maker.payoutAt(nine.order?.satoshisNow ?? Sats.fromInt(0)),
            asked: asked,
          ),
        );
      },
    );

    test(
      'nothing for a status not marked stored; a record said taken here over a make\'s records cannot be opened: « unreadable », never silence (#237)',
      () async {
        final (harness, record, six) = await taken();
        final maker = await termsOf(harness, record);
        expect(
          CheckPayoutRateUsecase.subjectAt(
            record,
            maker,
            TradeSeen(six.status, order: six.order, stored: false),
          ),
          isNull,
        );
        final port = wallet(P2pWalletRateRead(91711.15));
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
        // Its terms are a maker's, which a record taken here does not have: the records cannot be restored, said as unreadable (#237).
        expect(
          await CheckPayoutRateUsecase(harness.reader, port).termsOf(taker),
          isA<PayoutRateTermsUnreadable>(),
        );
        expect(port.ratesAsked, isEmpty);
      },
    );

    test('a currency the wallet does not price, a price not read', () async {
      final (harness, record, seen) = await taken();
      final maker = await termsOf(harness, record);
      final subject = comparedOf(
        CheckPayoutRateUsecase.subjectAt(record, maker, seen),
      );
      expect(
        CheckPayoutRateUsecase.compare(
          maker,
          subject,
          const P2pWalletRateNotPriced(),
        ),
        isA<WalletRateNotPriced>(),
      );
      expect(
        CheckPayoutRateUsecase.compare(
          maker,
          subject,
          const P2pWalletRateUnavailable(),
        ),
        isA<WalletRateUnverified>(),
      );
    });
  });

  group(
    'a maker buyer beside an alert of the state machine that is not about the terms nor the amounts (C1 of the functional review of #249): a reassuring comparison is not drawn, a red one is',
    () {
      Future<TradeSeen> deadline(
        MakeHarness harness,
        TradeRecord record,
      ) async {
        harness.coordinator.orderChanges[record.orderId] = {
          'expires_at': harness.now
              .add(const Duration(minutes: 1))
              .toIso8601String(),
        };
        return readOf(harness, record);
      }

      Future<TradeSeen> inconsistent(
        MakeHarness harness,
        TradeRecord record,
      ) async {
        harness.coordinator.orderChanges[record.orderId] = {
          // Another taker under the same contract (`TradeTakerChanged`, a breach of trust, refused as an answer).
          'taker_hash_id': harness.robot(3).hashId.hex,
          'taker_nick': harness.robot(3).nickname,
        };
        final broken = await readOf(harness, record);
        expect(broken.status.has<TradeTakerChanged>(), isTrue);
        harness.coordinator.orderChanges.remove(record.orderId);
        final again = await readOf(harness, record);
        expect(again.status, isA<WaitingForBoth>());
        return again;
      }

      test(
        'at 9, the payout not given from this wallet (#204): within the threshold, the alert alone; red, the comparison (security review of #249, C2)',
        () async {
          final (harness, record, _) = await taken();
          harness.coordinator.lockEscrow(record.orderId);
          await readOf(harness, record);
          harness.coordinator.order(record.orderId).status = 9;
          final nine = await readOf(harness, record);
          expect(nine.status, isA<Chatting>());
          expect(ShownAlerts.payoutTrace(nine), isTrue);
          final quiet = cubitOf(
            harness,
            record,
            wallet(P2pWalletRateRead(91711.15)),
          );
          await quiet.show(nine, appeared: true);
          await harness.settle();
          expect(quiet.state, isA<PayoutRateAlertAlone>());
          final loud = cubitOf(
            harness,
            record,
            wallet(P2pWalletRateRead(45000)),
          );
          await loud.show(nine, appeared: true);
          await harness.settle();
          expect(
            loud.state,
            isA<PayoutRateChecked>().having(
              (s) => s.check.warns,
              'warns',
              true,
            ),
          );
        },
      );

      for (final (name, alerted) in [
        ('a deadline moved back', deadline),
        ('a coordinator that broke the trade\'s history', inconsistent),
      ]) {
        test(
          '$name: within the threshold, the alert alone; red, the comparison',
          () async {
            final (harness, record, _) = await taken();
            final seen = await alerted(harness, record);
            expect(ShownAlerts.stateMachine(seen.status), isTrue);
            final quiet = cubitOf(
              harness,
              record,
              wallet(P2pWalletRateRead(91711.15)),
            );
            await quiet.show(seen, appeared: true);
            await harness.settle();
            expect(quiet.state, isA<PayoutRateAlertAlone>());
            final loud = cubitOf(
              harness,
              record,
              wallet(P2pWalletRateRead(45000)),
            );
            await loud.show(seen, appeared: true);
            await harness.settle();
            expect(
              loud.state,
              isA<PayoutRateChecked>().having(
                (s) => s.check.warns,
                'warns',
                true,
              ),
            );
          },
        );
      }
    },
  );

  group('the cubit', () {
    test(
      'one read for 6, 8 and 9 within 3 minutes, the price kept; « Retry » only after a price not read',
      () async {
        final (harness, record, six) = await taken();
        final reads = <Object>[];
        final port = wallet(const P2pWalletRateUnavailable());
        final cubit = cubitOf(harness, record, port, reads: reads);
        await cubit.show(six, appeared: true);
        expect(reads, hasLength(1));
        expect(
          (cubit.state as PayoutRateChecked).check,
          isA<WalletRateUnverified>(),
        );
        // Shown again within 3 minutes: no read.
        await cubit.show(six, appeared: true);
        expect(reads, hasLength(1));
        // « Retry »: read again.
        port.rate = P2pWalletRateRead(91711.15);
        await cubit.retry();
        expect(reads, hasLength(2));
        expect(
          (cubit.state as PayoutRateChecked).check,
          isA<WalletRateAtWallet>(),
        );
        // « Retry » after a price read: nothing.
        await cubit.retry();
        expect(reads, hasLength(2));
        // 8, then 9, within 3 minutes: compared with the price read.
        harness.coordinator.lockEscrow(record.orderId);
        await cubit.show(await readOf(harness, record));
        // The payout given from this wallet: no trace of #204 drawn at 9, beside which a comparison within the threshold would be silent (security review of #249, C2).
        await givenHere(harness, record, take: 0);
        harness.coordinator.order(record.orderId).status = 9;
        final nine = await readOf(harness, record);
        await cubit.show(nine);
        expect(reads, hasLength(2));
        expect(cubit.state, isA<PayoutRateChecked>());
        expect((cubit.state as PayoutRateChecked).step.fiatSent, isTrue);
        expect(
          (cubit.state as PayoutRateChecked).basis,
          const PayoutRateAsked(),
        );
      },
    );

    test(
      'read again only when the step appears anew (the screen built or shown again, the app back) or its status moves (8 an hour after 6) with a read 3 minutes old; a new read of the same status never reads again',
      () async {
        final (harness, record, six) = await taken();
        final reads = <Object>[];
        final cubit = cubitOf(
          harness,
          record,
          wallet(P2pWalletRateRead(91711.15)),
          reads: reads,
        );
        await cubit.show(six, appeared: true);
        expect(reads, hasLength(1));
        await harness.elapse(const Duration(minutes: 2, seconds: 59));
        await cubit.show(six, appeared: true);
        expect(reads, hasLength(1));
        await harness.elapse(const Duration(seconds: 1));
        // The watch's next read of the same status: never a read by itself.
        await cubit.show(six);
        expect(reads, hasLength(1));
        // The screen shown again: read again, once.
        await cubit.show(six, appeared: true);
        expect(reads, hasLength(2));
        await cubit.show(six, appeared: true);
        expect(reads, hasLength(2));
        // 8 an hour later, the same step at another status.
        harness.coordinator.lockEscrow(record.orderId);
        await harness.elapse(const Duration(hours: 1));
        final eight = await readOf(harness, record);
        expect(eight.status, isA<WaitingForPayout>());
        await cubit.show(eight);
        expect(reads, hasLength(3));
        await cubit.show(eight);
        expect(reads, hasLength(3));
      },
    );

    group(
      '#283: after a read that failed, a step shown for the first time reads once, as before; a step already shown that comes back reads again only once the last read is 3 minutes old (security review of #237, R3; review of #283, C1); « Retry » always reads; a price service that answers, as before',
      () {
        /// An order made and taken, its invoice given here, then at 9 and 10: the statuses the coordinator makes come and go (10 has no step of the rule).
        Future<(MakeHarness, TradeRecord, TradeSeen, TradeSeen, TradeSeen)>
        atNine() async {
          final (harness, record, six) = await taken();
          harness.coordinator.lockEscrow(record.orderId);
          await readOf(harness, record);
          await givenHere(harness, record, take: 0);
          harness.coordinator.order(record.orderId).status = 9;
          final nine = await readOf(harness, record);
          harness.coordinator.order(record.orderId).status = 10;
          final ten = await readOf(harness, record);
          expect(PayoutRateStep.of(ten.status), isNull);
          return (harness, record, six, nine, ten);
        }

        test(
          'the service failing: 9 shown for the first time 10 seconds after a failed read at 6 reads once; twelve returns 10 → 9 read once in all, the first past 3 minutes after the read at 9; « Retry » reads at once',
          () async {
            final (harness, record, six, nine, ten) = await atNine();
            final reads = <Object>[];
            final port = wallet(const P2pWalletRateUnavailable());
            final cubit = cubitOf(harness, record, port, reads: reads);
            await cubit.show(six, appeared: true);
            expect(reads, hasLength(1));
            await harness.elapse(const Duration(seconds: 10));
            await cubit.show(nine);
            expect(reads, hasLength(2));
            expect(
              cubit.state,
              isA<PayoutRateChecked>()
                  .having((s) => s.step.fiatSent, 'at 9', isTrue)
                  .having((s) => s.check, 'check', isA<WalletRateUnverified>()),
            );
            for (var i = 0; i < 12; i++) {
              await harness.elapse(const Duration(seconds: 10));
              await cubit.show(ten);
              expect(cubit.state, isA<PayoutRateNone>());
              await harness.elapse(const Duration(seconds: 10));
              await cubit.show(nine);
            }
            // The read at 9 at 10 seconds; the returns at 30 seconds, 50, … 4 minutes 10: the first 3 minutes after that read (at 3 minutes 10) read once, the three after it nothing; before #283 every return read, 14 reads in all.
            expect(reads, hasLength(3));
            // « Retry » reads at once, the last read a few seconds old.
            await cubit.retry();
            expect(reads, hasLength(4));
            await cubit.retry();
            expect(reads, hasLength(5));
            port.rate = P2pWalletRateRead(91711.15);
            await cubit.retry();
            expect(reads, hasLength(6));
            expect(
              cubit.state,
              isA<PayoutRateChecked>().having(
                (s) => s.check,
                'check',
                isA<WalletRateAtWallet>(),
              ),
            );
          },
        );

        test(
          'the review\'s probe: the price failing at 6, then the service back with a price 30 % below; 9 shown a minute later reads it at once, and the red alert with its figures is there before « Confirm … sent »',
          () async {
            final (harness, record, six, nine, _) = await atNine();
            final reads = <Object>[];
            final port = wallet(const P2pWalletRateUnavailable());
            final cubit = cubitOf(harness, record, port, reads: reads);
            await cubit.show(six, appeared: true);
            expect(reads, hasLength(1));
            port.rate = P2pWalletRateRead(64000);
            await harness.elapse(const Duration(seconds: 60));
            await cubit.show(nine);
            expect(reads, hasLength(2));
            expect(
              cubit.state,
              isA<PayoutRateChecked>()
                  .having((s) => s.step.fiatSent, 'at 9', isTrue)
                  .having(
                    (s) => s.check,
                    'check',
                    isA<WalletRateCompared>().having(
                      (c) => c.warns,
                      'warns',
                      isTrue,
                    ),
                  ),
            );
          },
        );

        /// An order made and taken, its collateral locked (8), then 9, 10 and 13, and 15 once the failed invoice expired: 6, 8, 13 and 15 as the cubit is shown them.
        Future<
          (MakeHarness, TradeRecord, TradeSeen, TradeSeen, TradeSeen, TradeSeen)
        >
        atFifteen() async {
          final (harness, record, six) = await taken();
          harness.coordinator.lockEscrow(record.orderId);
          final eight = await readOf(harness, record);
          expect(eight.status, isA<WaitingForPayout>());
          await givenHere(harness, record, take: 0);
          for (final status in const [9, 10]) {
            harness.coordinator.order(record.orderId).status = status;
            await readOf(harness, record);
          }
          harness.coordinator.order(record.orderId).status = 13;
          final thirteen = await readOf(harness, record);
          expect(PayoutRateStep.of(thirteen.status), isNull);
          harness.coordinator.failPayout(record.orderId, expired: true);
          final fifteen = await readOf(harness, record);
          expect(
            PayoutRateStep.of(fifteen.status),
            PayoutRateStep.of(six.status),
          );
          return (harness, record, six, eight, thirteen, fifteen);
        }

        test(
          'the service failing: the first 15 within 3 minutes of a failed read at 6, of the same step at another status, reads once; twelve round trips 15 → 13 → 15 read once in all, the first past 3 minutes after the read at 15 (verification of the review of #283, V-R1)',
          () async {
            final (harness, record, six, _, thirteen, fifteen) =
                await atFifteen();
            final reads = <Object>[];
            final port = wallet(const P2pWalletRateUnavailable());
            final cubit = cubitOf(harness, record, port, reads: reads);
            await cubit.show(six, appeared: true);
            expect(reads, hasLength(1));
            await harness.elapse(const Duration(seconds: 10));
            await cubit.show(thirteen);
            expect(cubit.state, isA<PayoutRateNone>());
            await harness.elapse(const Duration(seconds: 10));
            await cubit.show(fifteen);
            expect(reads, hasLength(2));
            expect(
              cubit.state,
              isA<PayoutRateChecked>()
                  .having((s) => s.step.fiatSent, 'payout', isFalse)
                  .having((s) => s.check, 'check', isA<WalletRateUnverified>()),
            );
            for (var i = 0; i < 12; i++) {
              await harness.elapse(const Duration(seconds: 10));
              await cubit.show(thirteen);
              expect(cubit.state, isA<PayoutRateNone>());
              await harness.elapse(const Duration(seconds: 10));
              await cubit.show(fifteen);
            }
            // The read at the first 15 at 20 seconds; the returns at 40 seconds, 1 minute, … 4 minutes 20: the first past 3 minutes after that read reads once, none after it; with the step kept without its status, the first 15 read nothing (2 reads in all); with no bound, every return read (14 in all).
            expect(reads, hasLength(3));
          },
        );

        test(
          'the service failing: 8 after a failed read at 6, the same step at another status, reads nothing within 3 minutes, as before #283 (a status that moves reads only once the last read is 3 minutes old); « Amount not checked » and its « Retry » stay',
          () async {
            final (harness, record, six, eight, _, _) = await atFifteen();
            final reads = <Object>[];
            final port = wallet(const P2pWalletRateUnavailable());
            final cubit = cubitOf(harness, record, port, reads: reads);
            await cubit.show(six, appeared: true);
            expect(reads, hasLength(1));
            await harness.elapse(const Duration(seconds: 10));
            await cubit.show(eight);
            expect(reads, hasLength(1));
            expect(
              cubit.state,
              isA<PayoutRateChecked>().having(
                (s) => s.check,
                'check',
                isA<WalletRateUnverified>(),
              ),
            );
            await cubit.retry();
            expect(reads, hasLength(2));
          },
        );

        test(
          'the service failing: 8 after 13 after a failed read at 6, the first 8 shown after a status outside the rule, is a step shown anew and reads once (2 reads in all); only 8 directly after 6 waits (review of #287)',
          () async {
            final (harness, record, six, eight, thirteen, _) =
                await atFifteen();
            final reads = <Object>[];
            final port = wallet(const P2pWalletRateUnavailable());
            final cubit = cubitOf(harness, record, port, reads: reads);
            await cubit.show(six, appeared: true);
            expect(reads, hasLength(1));
            await harness.elapse(const Duration(seconds: 10));
            await cubit.show(thirteen);
            expect(cubit.state, isA<PayoutRateNone>());
            expect(reads, hasLength(1));
            await harness.elapse(const Duration(seconds: 10));
            await cubit.show(eight);
            expect(reads, hasLength(2));
            expect(
              cubit.state,
              isA<PayoutRateChecked>().having(
                (s) => s.check,
                'check',
                isA<WalletRateUnverified>(),
              ),
            );
          },
        );

        test(
          'the service answering: the first 15 and twelve round trips 15 → 13 → 15 read as before, nothing at the first 15 (the price fresh), once on the first return past 3 minutes after the read at 6',
          () async {
            final (harness, record, six, _, thirteen, fifteen) =
                await atFifteen();
            final reads = <Object>[];
            final cubit = cubitOf(
              harness,
              record,
              wallet(P2pWalletRateRead(91711.15)),
              reads: reads,
            );
            await cubit.show(six, appeared: true);
            expect(reads, hasLength(1));
            await harness.elapse(const Duration(seconds: 10));
            await cubit.show(thirteen);
            await harness.elapse(const Duration(seconds: 10));
            await cubit.show(fifteen);
            expect(reads, hasLength(1));
            for (var i = 0; i < 12; i++) {
              await harness.elapse(const Duration(seconds: 10));
              await cubit.show(thirteen);
              await harness.elapse(const Duration(seconds: 10));
              await cubit.show(fifteen);
            }
            expect(reads, hasLength(2));
          },
        );

        test(
          'the service answering: the same returns read exactly as before #283, once at 6, once on the first return past 3 minutes',
          () async {
            final (harness, record, six, nine, ten) = await atNine();
            final reads = <Object>[];
            final cubit = cubitOf(
              harness,
              record,
              wallet(P2pWalletRateRead(91711.15)),
              reads: reads,
            );
            await cubit.show(six, appeared: true);
            expect(reads, hasLength(1));
            await harness.elapse(const Duration(seconds: 10));
            await cubit.show(nine);
            expect(reads, hasLength(1));
            for (var i = 0; i < 12; i++) {
              await harness.elapse(const Duration(seconds: 10));
              await cubit.show(ten);
              await harness.elapse(const Duration(seconds: 10));
              await cubit.show(nine);
            }
            expect(reads, hasLength(2));
            // « Retry » after a price read: nothing, as before.
            await cubit.retry();
            expect(reads, hasLength(2));
          },
        );
      },
    );

    test(
      'a price read for a step lands on the step shown when it lands, never on the one it was asked for',
      () async {
        final (harness, record, six) = await taken();
        harness.coordinator.lockEscrow(record.orderId);
        await readOf(harness, record);
        // The payout given from this wallet: no trace of #204 drawn at 9, beside which a comparison within the threshold would be silent (security review of #249, C2).
        await givenHere(harness, record, take: 0);
        harness.coordinator.order(record.orderId).status = 9;
        final nine = await readOf(harness, record);
        final answers = <Completer<P2pWalletBitcoinRate>>[];
        final cubit = cubitOf(
          harness,
          record,
          wallet(P2pWalletRateRead(91711.15)),
          held: () {
            final answer = Completer<P2pWalletBitcoinRate>();
            answers.add(answer);
            return answer.future;
          },
        );
        unawaited(cubit.show(six, appeared: true));
        await harness.settle();
        unawaited(cubit.show(nine));
        await harness.settle();
        // One read at a time.
        expect(answers, hasLength(1));
        expect(cubit.state, isA<PayoutRateReading>());
        answers.single.complete(P2pWalletRateRead(91711.15));
        await harness.settle();
        expect((cubit.state as PayoutRateChecked).step.fiatSent, isTrue);
      },
    );

    test(
      'before « Submit » or « Confirm … sent »: a price 3 minutes old read again; the same line goes on, another stops the press once',
      () async {
        final (harness, record, six) = await taken();
        final reads = <Object>[];
        final port = wallet(P2pWalletRateRead(91711.15));
        final cubit = cubitOf(harness, record, port, reads: reads);
        await cubit.show(six, appeared: true);
        expect(reads, hasLength(1));
        // Fresh: nothing read, the press goes on.
        expect(await cubit.beforeAct(), isTrue);
        expect(reads, hasLength(1));
        // Old, the same line: read again, the press goes on.
        await harness.elapse(const Duration(minutes: 3));
        expect(await cubit.beforeAct(), isTrue);
        expect(reads, hasLength(2));
        // Old, another line: read again, the press stops, a second press goes on.
        await harness.elapse(const Duration(minutes: 3));
        port.rate = const P2pWalletRateNotPriced();
        expect(await cubit.beforeAct(), isFalse);
        expect(reads, hasLength(3));
        expect(
          (cubit.state as PayoutRateChecked).check,
          isA<WalletRateNotPriced>(),
        );
        expect(await cubit.beforeAct(), isTrue);
        expect(reads, hasLength(3));
      },
    );

    test(
      'before « Submit »: a line become « within the margin » never stops the press (« rate not checked » before, third functional pass of #182, #207); a line become any other one does, once',
      () async {
        final (harness, record, six) = await taken();
        final reads = <Object>[];
        final port = wallet(const P2pWalletRateUnavailable());
        final cubit = cubitOf(harness, record, port, reads: reads);
        await cubit.show(six, appeared: true);
        expect(
          (cubit.state as PayoutRateChecked).check,
          isA<WalletRateUnverified>(),
        );
        // Within the margin now: read again, the press goes on.
        await harness.elapse(const Duration(minutes: 3));
        port.rate = P2pWalletRateRead(91711.15);
        expect(await cubit.beforeAct(), isTrue);
        expect(reads, hasLength(2));
        final within = (cubit.state as PayoutRateChecked).check;
        expect(within, isA<WalletRateCompared>());
        expect(within.warns, isFalse);
        // « Rate not checked » again: the press stops once.
        await harness.elapse(const Duration(minutes: 3));
        port.rate = const P2pWalletRateUnavailable();
        expect(await cubit.beforeAct(), isFalse);
        expect(await cubit.beforeAct(), isTrue);
        // « Rate not checked » of another kind: another line, the press stops once too.
        await harness.elapse(const Duration(minutes: 3));
        port.rate = const P2pWalletRateNotPriced();
        expect(await cubit.beforeAct(), isFalse);
        expect(
          (cubit.state as PayoutRateChecked).check,
          isA<WalletRateNotPriced>(),
        );
        expect(await cubit.beforeAct(), isTrue);
        expect(reads, hasLength(4));
      },
    );

    test(
      'a contract seen late whose invoice was never seen here is an alert whatever else the line says (#207), a comparison within the margin included (security review of #208, R2)',
      () async {
        const step = PayoutRateStep(1, fiatSent: true);
        final (harness, record, six) = await taken();
        final maker = await termsOf(harness, record);
        final within = CheckPayoutRateUsecase.compare(
          maker,
          comparedOf(CheckPayoutRateUsecase.subjectAt(record, maker, six)),
          P2pWalletRateRead(91711.15),
        );
        expect(within.warns, isFalse);
        expect(
          PayoutRateCubit.verdictOf(
            PayoutRateChecked(step, within, basis: const PayoutRateNotSeen()),
          ),
          PayoutRateVerdict.warns,
        );
        expect(
          PayoutRateCubit.verdictOf(
            PayoutRateChecked(step, within, basis: const PayoutRateAsked()),
          ),
          PayoutRateVerdict.within,
        );
        for (final state in [
          const PayoutRateSatsMissing(step, notSeen: true),
          const PayoutRateAmountsDisagree(step, notSeen: true),
        ]) {
          expect(PayoutRateCubit.verdictOf(state), PayoutRateVerdict.warns);
        }
        expect(
          PayoutRateCubit.verdictOf(const PayoutRateAmountsDisagree(step)),
          PayoutRateVerdict.disagree,
        );
        expect(
          PayoutRateCubit.verdictOf(const PayoutRateSatsMissing(step)),
          PayoutRateVerdict.satsMissing,
        );
      },
    );

    test(
      'before « Submit » during a read: its end awaited; a line with no warning goes on, a line that warns stops',
      () async {
        for (final (rate, goesOn) in [
          (P2pWalletRateRead(91711.15) as P2pWalletBitcoinRate, true),
          (const P2pWalletRateUnavailable() as P2pWalletBitcoinRate, false),
        ]) {
          final (harness, record, six) = await taken();
          final answers = <Completer<P2pWalletBitcoinRate>>[];
          final cubit = cubitOf(
            harness,
            record,
            wallet(rate),
            held: () {
              final answer = Completer<P2pWalletBitcoinRate>();
              answers.add(answer);
              return answer.future;
            },
          );
          unawaited(cubit.show(six, appeared: true));
          await harness.settle();
          expect(cubit.state, isA<PayoutRateReading>());
          final pressed = cubit.beforeAct();
          await harness.settle();
          expect(answers, hasLength(1));
          answers.single.complete(rate);
          expect(await pressed, goesOn);
        }
      },
    );

    test(
      'the invoice\'s sats asked at 6 or 8 outlive the page (a cubit of another page compares 9 with them), never the app',
      () async {
        final (harness, record, six) = await taken();
        final memory = PayoutRateMemory();
        final port = wallet(P2pWalletRateRead(91711.15));
        final first = cubitOf(harness, record, port, memory: memory);
        await first.show(six, appeared: true);
        await first.close();
        // The payout given from this wallet: no trace of #204 drawn at 9, beside which a comparison within the threshold would be silent (security review of #249, C2).
        await givenHere(harness, record, take: 0);
        harness.coordinator.order(record.orderId).status = 9;
        final nine = await readOf(harness, record);
        final again = cubitOf(harness, record, port, memory: memory);
        await again.show(nine, appeared: true);
        expect(
          (again.state as PayoutRateChecked).basis,
          const PayoutRateAsked(),
        );
        // A new memory, as after a restart: the coordinator's figure of now, said.
        final restarted = cubitOf(harness, record, port);
        await restarted.show(nine, appeared: true);
        expect(
          (restarted.state as PayoutRateChecked).basis,
          const PayoutRateToldNow(),
        );
      },
    );

    test(
      'another figure at the same status (8, then 8): compared again at once, with the price read (N06)',
      () async {
        final (harness, record, six) = await taken();
        harness.coordinator.lockEscrow(record.orderId);
        final eight = await readOf(harness, record);
        final reads = <Object>[];
        final cubit = cubitOf(
          harness,
          record,
          wallet(P2pWalletRateRead(91711.15)),
          reads: reads,
        );
        await cubit.show(eight, appeared: true);
        final first = (cubit.state as PayoutRateChecked).check.asked;
        harness.coordinator.order(record.orderId).lastSatoshis = 50000;
        final halved = await readOf(harness, record);
        expect(halved.status, isA<WaitingForPayout>());
        await cubit.show(halved);
        final check = (cubit.state as PayoutRateChecked).check;
        expect(check.asked, isNot(first));
        expect(check.asked, valueOf(PayoutAsk.of(record, halved)).buyerSats);
        expect(check.warns, isTrue);
        expect(reads, hasLength(1));
      },
    );

    test(
      'the invoice kept is the contract\'s own: a next contract never inherits the one of the contract before (N12)',
      () async {
        final (harness, record, _) = await taken();
        final memory = PayoutRateMemory();
        final port = wallet(P2pWalletRateRead(91711.15));
        final cubit = cubitOf(harness, record, port, memory: memory);
        // Contract 0 asks an invoice of half.
        harness.coordinator.order(record.orderId).lastSatoshis = 50000;
        await cubit.show(await readOf(harness, record), appeared: true);
        // Back in the book, taken again honestly: contract 1.
        harness.coordinator.backToBook(record.orderId);
        await readOf(harness, record);
        await harness.elapse(const Duration(minutes: 1));
        harness.coordinator.take(record.orderId, harness.robot(5));
        final six = await readOf(harness, record);
        expect(six.status.trail.take, 1);
        await cubit.show(six);
        // The payout given from this wallet: no trace of #204 drawn at 9, beside which a comparison within the threshold would be silent (security review of #249, C2).
        await givenHere(harness, record, take: 1);
        harness.coordinator.order(record.orderId).status = 9;
        final nine = await readOf(harness, record);
        await cubit.show(nine);
        expect(
          (cubit.state as PayoutRateChecked).basis,
          const PayoutRateAsked(),
        );
      },
    );

    test('a step outside the rule shows nothing and reads nothing', () async {
      final harness = await MakeHarness.start();
      final record = (valueOf(await harness.makeOrder()) as MakeStarted).record;
      final atZero = await readOf(harness, record);
      final reads = <Object>[];
      final cubit = cubitOf(
        harness,
        record,
        wallet(P2pWalletRateRead(91711.15)),
        reads: reads,
      );
      await cubit.show(atZero, appeared: true);
      expect(reads, isEmpty);
      expect(cubit.state, isA<PayoutRateNone>());
    });

    test(
      'a trade said taken here whose records cannot be restored (a maker\'s terms): « Amount not checked », never silence, nothing read, not even « reading » (#237; a taker buyer\'s own terms are compared since #249, `taken_price_usecases_test.dart`)',
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
        final reads = <Object>[];
        final cubit = cubitOf(
          harness,
          taker,
          wallet(P2pWalletRateRead(91711.15)),
          reads: reads,
        );
        final sub = cubit.stream.listen(states.add);
        addTearDown(sub.cancel);
        await cubit.show(six, appeared: true);
        await harness.settle();
        expect(reads, isEmpty);
        expect(states, [isA<PayoutRateTermsUnread>()]);
        expect(await cubit.beforeAct(), isTrue);
      },
    );
  });

  group('the three gaps of #237 (design note § 3.3 bis)', () {
    /// An order of 100 GBP at a premium of 0, a currency the Bull wallet does not price, made at the coordinator's 50,000 GBP/BTC (200,000 sats at the rate of the creation), bought here ([sell] sold), taken at the coordinator's [at], its sats [sats] when given: its record and its status at 6.
    Future<(MakeHarness, TradeRecord, TradeSeen)> takenInGbp({
      required double at,
      int? sats,
      bool sell = false,
    }) async {
      final harness = await MakeHarness.start();
      final gbp = RobosatsCurrency.fromId(4) ?? (throw StateError('GBP'));
      harness.coordinator.prices[4] = 50000;
      final record =
          (valueOf(
                    await harness.makeOrder(
                      MakeHarness.request(
                        currency: gbp,
                        premium: 0,
                        sell: sell,
                      ),
                    ),
                  )
                  as MakeStarted)
              .record;
      harness.coordinator
        ..lockMakerBond(record.orderId)
        ..prices[4] = at
        ..take(record.orderId, harness.robot(4));
      if (sats != null) {
        harness.coordinator.order(record.orderId).lastSatoshis = sats;
      }
      return (harness, record, await readOf(harness, record));
    }

    Matcher notPricedWith(int? against) => isA<PayoutRateChecked>()
        .having((s) => s.check, 'check', isA<WalletRateNotPriced>())
        .having(
          (s) => s.against,
          'against',
          against == null ? isNull : BigInt.from(against),
        );

    group(
      'point 2: a currency the Bull wallet does not price, an order made here: the gap against the buyer since the order was made, beyond the owner\'s threshold only, in sats',
      () {
        for (final (label, at, sats, against) in <(String, double, int?, int?)>[
          ('taken at 56,000: 178,571 sats, 10.72 % fewer', 56000, null, 1072),
          (
            'taken at 55,500: 180,180 sats, 9.91 % fewer: nothing',
            55500,
            null,
            null,
          ),
          (
            '179,999 sats, just beyond the threshold: 10.01 %',
            56000,
            179999,
            1001,
          ),
          ('180,000 sats, exactly 10 % fewer: nothing', 56000, 180000, null),
          (
            'taken at 45,000: 222,222 sats, more for the buyer: nothing',
            45000,
            null,
            null,
          ),
        ]) {
          test(label, () async {
            final (harness, record, six) = await takenInGbp(at: at, sats: sats);
            expect(six.status.warnings, isEmpty);
            final port = wallet(const P2pWalletRateNotPriced());
            final cubit = cubitOf(harness, record, port);
            await cubit.show(six, appeared: true);
            await harness.settle();
            expect(cubit.state, notPricedWith(against));
            expect(
              PayoutRateCubit.verdictOf(cubit.state),
              against == null
                  ? PayoutRateVerdict.notPriced
                  : PayoutRateVerdict.notPricedAgainst,
            );
          });
        }

        test(
          'at 9, the coordinator\'s figure of now: the same gap since the order was made',
          () async {
            final (harness, record, six) = await takenInGbp(at: 56000);
            harness.coordinator.lockEscrow(record.orderId);
            await readOf(harness, record);
            harness.coordinator.order(record.orderId).status = 9;
            final nine = await readOf(harness, record);
            expect(nine.status, isA<Chatting>());
            final cubit = cubitOf(
              harness,
              record,
              wallet(const P2pWalletRateNotPriced()),
            );
            await cubit.show(nine, appeared: true);
            await harness.settle();
            expect(cubit.state, notPricedWith(1072));
          },
        );

        test(
          'never for a currency the Bull wallet prices, nor beside a price that could not be read: the creation\'s rate is never compared then',
          () async {
            final (harness, record, six) = await takenInGbp(at: 56000);
            for (final rate in <P2pWalletBitcoinRate>[
              P2pWalletRateRead(50000),
              const P2pWalletRateUnavailable(),
            ]) {
              final cubit = cubitOf(harness, record, wallet(rate));
              await cubit.show(six, appeared: true);
              await harness.settle();
              expect(
                cubit.state,
                isA<PayoutRateChecked>()
                    .having(
                      (s) => s.check,
                      'check',
                      isNot(isA<WalletRateNotPriced>()),
                    )
                    .having((s) => s.against, 'against', isNull),
              );
            }
          },
        );
      },
    );

    group('point 1: the trade\'s records cannot be opened now', () {
      test(
        'while the terms of an order made here are being read: « reading », never « Amount not checked » (functional review of #237, R1)',
        () async {
          final (harness, record, six) = await taken();
          final port = wallet(P2pWalletRateRead(91711.15));
          final usecase = CheckPayoutRateUsecase(harness.reader, port);
          final held = Completer<void>();
          final cubit = PayoutRateCubit(
            record,
            terms: (record) async {
              await held.future;
              return usecase.termsOf(record);
            },
            price: usecase.priceOf,
            memory: PayoutRateMemory(),
            now: () => harness.now,
          );
          addTearDown(cubit.close);
          final states = <PayoutRateState>[];
          final sub = cubit.stream.listen(states.add);
          addTearDown(sub.cancel);
          final shown = cubit.show(six, appeared: true);
          await harness.settle();
          expect(cubit.state, isA<PayoutRateReading>());
          expect(
            PayoutRateCubit.verdictOf(cubit.state),
            PayoutRateVerdict.reading,
          );
          held.complete();
          await shown;
          await harness.settle();
          expect(cubit.state, isA<PayoutRateChecked>());
          expect(states.whereType<PayoutRateTermsUnread>(), isEmpty);
          expect(states.first, isA<PayoutRateReading>());
        },
      );

      test(
        'the vault gives no Garage Key: « Amount not checked », never silence, nothing read; the watch\'s next read does not open them again; « Retry » does, and once the vault is back the step is compared and the terms kept',
        () async {
          final (harness, record, six) = await taken();
          final port = wallet(P2pWalletRateRead(91711.15));
          final usecase = CheckPayoutRateUsecase(harness.reader, port);
          final opened = <TradeRecord>[];
          final cubit = PayoutRateCubit(
            record,
            terms: (record) {
              opened.add(record);
              return usecase.termsOf(record);
            },
            price: usecase.priceOf,
            memory: PayoutRateMemory(),
            now: () => harness.now,
          );
          addTearDown(cubit.close);
          harness.deleteKey();
          await cubit.show(six, appeared: true);
          await harness.settle();
          final given = valueOf(PayoutAsk.of(record, six)).buyerSats;
          expect(
            cubit.state,
            isA<PayoutRateTermsUnread>().having((s) => s.given, 'given', given),
          );
          expect(
            PayoutRateCubit.verdictOf(cubit.state),
            PayoutRateVerdict.termsUnread,
          );
          expect(port.ratesAsked, isEmpty);
          expect(opened, hasLength(1));
          // The same status read again by the watch: nothing opened again, the line kept.
          await cubit.show(six);
          await harness.settle();
          expect(opened, hasLength(1));
          expect(cubit.state, isA<PayoutRateTermsUnread>());
          // « Submit » goes on: nothing is ever blocked.
          expect(await cubit.beforeAct(), isTrue);
          // « Retry » with the vault still refusing: opened again, the same line.
          await cubit.retry();
          await harness.settle();
          expect(opened, hasLength(2));
          expect(cubit.state, isA<PayoutRateTermsUnread>());
          expect(port.ratesAsked, isEmpty);
          // The vault back: « Retry » compares.
          harness.restoreKey();
          await cubit.retry();
          await harness.settle();
          expect(opened, hasLength(3));
          expect(
            cubit.state,
            isA<PayoutRateChecked>().having(
              (s) => s.check,
              'check',
              isA<WalletRateAtWallet>(),
            ),
          );
          expect(port.ratesAsked, hasLength(1));
          await cubit.show(six, appeared: true);
          await harness.settle();
          expect(opened, hasLength(3));
        },
      );

      test(
        'at 9, where no invoice is asked: « Amount not checked » without sats; a step shown anew (9 after 6) opens the records again',
        () async {
          final (harness, record, six) = await taken();
          final port = wallet(P2pWalletRateRead(91711.15));
          final opened = <TradeRecord>[];
          final usecase = CheckPayoutRateUsecase(harness.reader, port);
          final cubit = PayoutRateCubit(
            record,
            terms: (record) {
              opened.add(record);
              return usecase.termsOf(record);
            },
            price: usecase.priceOf,
            memory: PayoutRateMemory(),
            now: () => harness.now,
          );
          addTearDown(cubit.close);
          harness.deleteKey();
          await cubit.show(six, appeared: true);
          await harness.settle();
          harness.restoreKey();
          harness.coordinator.order(record.orderId).status = 9;
          final nine = await readOf(harness, record);
          harness.deleteKey();
          await cubit.show(nine);
          await harness.settle();
          expect(opened, hasLength(2));
          expect(
            cubit.state,
            isA<PayoutRateTermsUnread>()
                .having((s) => s.given, 'given', isNull)
                .having((s) => s.step.fiatSent, 'fiat sent', isTrue),
          );
        },
      );
    });

    group('point 3: status 15, a new invoice asked after a failed payout', () {
      /// [record]'s trade from 6 to 15 as the reference moves it (8, 9, 10, 13, then 15), each read in turn; [expired] whether the failed invoice expired.
      Future<TradeSeen> toFifteen(
        MakeHarness harness,
        TradeRecord record, {
        required bool expired,
      }) async {
        harness.coordinator.lockEscrow(record.orderId);
        await readOf(harness, record);
        for (final status in const [9, 10, 13]) {
          harness.coordinator.order(record.orderId).status = status;
          await readOf(harness, record);
        }
        harness.coordinator.failPayout(record.orderId, expired: expired);
        return readOf(harness, record);
      }

      test(
        'once the invoice expired: the same red check as at 6 for the same sats, the same sum as the invoice kept from 6 (#281); while the coordinator retries, nothing',
        () async {
          final (harness, record, six) = await taken();
          final port = wallet(P2pWalletRateRead(80000));
          // One run of the app: the invoice of 6 kept for 15 (#281).
          final memory = PayoutRateMemory();
          final cubit = cubitOf(harness, record, port, memory: memory);
          await cubit.show(six, appeared: true);
          await harness.settle();
          final atSix = switch (cubit.state) {
            PayoutRateChecked(check: final WalletRateAtWallet check) => check,
            final other => fail('$other'),
          };
          expect(atSix.warns, isTrue);
          final retrying = await toFifteen(harness, record, expired: false);
          expect(retrying.status, isA<RoutingFailed>());
          final later = cubitOf(harness, record, port, memory: memory);
          await later.show(retrying, appeared: true);
          await harness.settle();
          expect(later.state, isA<PayoutRateNone>());
          harness.coordinator.order(record.orderId).payoutExpired = true;
          final fifteen = await readOf(harness, record);
          expect(
            fifteen.status,
            isA<RoutingFailed>().having(
              (s) => s.invoiceExpired,
              'expired',
              isTrue,
            ),
          );
          expect(
            PayoutRateStep.of(fifteen.status),
            PayoutRateStep(0, fiatSent: false),
          );
          await later.show(fifteen);
          await harness.settle();
          expect(
            later.state,
            isA<PayoutRateChecked>()
                .having((s) => s.basis, 'basis', const PayoutRateAskedNow())
                .having(
                  (s) => s.check,
                  'check',
                  isA<WalletRateAtWallet>()
                      .having((c) => c.asked, 'asked', atSix.asked)
                      .having((c) => c.expected, 'expected', atSix.expected)
                      .having(
                        (c) => c.gapHundredths,
                        'gap',
                        atSix.gapHundredths,
                      )
                      .having((c) => c.warns, 'warns', isTrue),
                ),
          );
        },
      );

      test(
        'at 15, the Bull wallet\'s price unreadable: « rate not checked »; a currency it does not price: « not quoted », with the gap since the order was made beyond the threshold',
        () async {
          final (harness, record, _) = await taken();
          final fifteen = await toFifteen(harness, record, expired: true);
          final unread = cubitOf(
            harness,
            record,
            wallet(const P2pWalletRateUnavailable()),
          );
          await unread.show(fifteen, appeared: true);
          await harness.settle();
          expect(
            unread.state,
            isA<PayoutRateChecked>().having(
              (s) => s.check,
              'check',
              isA<WalletRateUnverified>(),
            ),
          );
          final (gbpHarness, gbpRecord, _) = await takenInGbp(at: 56000);
          final gbpFifteen = await toFifteen(
            gbpHarness,
            gbpRecord,
            expired: true,
          );
          final notPriced = cubitOf(
            gbpHarness,
            gbpRecord,
            wallet(const P2pWalletRateNotPriced()),
          );
          await notPriced.show(gbpFifteen, appeared: true);
          await gbpHarness.settle();
          expect(notPriced.state, notPricedWith(1072));
        },
      );
    });
  });

  group(
    '#281: at 15, the new invoice against the one asked at 6 or 8 (design note § 3.3 bis, point 4)',
    () {
      /// [record]'s trade moved from where it stands to 15 (8, 9, 10, 13, then 15, the failed invoice expired), each read in turn; [last] the coordinator's `last_satoshis` from 13 on, when given (a coordinator that lowers the contract's sats before 15).
      Future<TradeSeen> toFifteen(
        MakeHarness harness,
        TradeRecord record, {
        int? last,
      }) async {
        harness.coordinator.lockEscrow(record.orderId);
        await readOf(harness, record);
        for (final status in const [9, 10, 13]) {
          harness.coordinator.order(record.orderId).status = status;
          await readOf(harness, record);
        }
        if (last != null) {
          harness.coordinator.order(record.orderId).lastSatoshis = last;
        }
        harness.coordinator.failPayout(record.orderId);
        return readOf(harness, record);
      }

      Sats askedAt(TradeRecord record, TradeSeen seen) =>
          valueOf(PayoutAsk.of(record, seen)).buyerSats;

      test(
        'the use case: at 6 the invoice kept for 15 (`keepFirst`); at 15 nothing kept, and against the largest of 6 and 8: fewer by one sat is an alert, as many or more is as at 6, nothing kept is said',
        () async {
          final (harness, record, six) = await taken();
          final maker = await termsOf(harness, record);
          final atSix = comparedOf(
            CheckPayoutRateUsecase.subjectAt(record, maker, six),
          );
          expect(atSix.keepFirst, askedAt(record, six));
          expect(atSix.basis, const PayoutRateAskedNow());
          final first = askedAt(record, six);
          final fifteen = await toFifteen(harness, record);
          final asked = askedAt(record, fifteen);
          expect(asked, first, reason: 'the reference asks the same sum');
          PayoutRateCompared at(Sats? kept) => comparedOf(
            CheckPayoutRateUsecase.subjectAt(
              record,
              maker,
              fifteen,
              asked: kept,
              first: kept,
            ),
          );
          final same = at(first);
          expect(same.basis, const PayoutRateAskedNow());
          expect(same.keep, isNull);
          expect(same.keepFirst, isNull);
          expect(same.received, asked);
          // One sat more kept: the sum of 15 is one sat fewer.
          final oneMore = Sats(first.value + BigInt.one);
          expect(at(oneMore).basis, PayoutRateBelowFirst(oneMore));
          // One sat fewer kept: more at 15, nothing more said.
          expect(
            at(Sats(first.value - BigInt.one)).basis,
            const PayoutRateAskedNow(),
          );
          expect(at(null).basis, const PayoutRateFirstUnknown());
        },
      );

      test(
        'the cubit: 6 honest, 15 asks 9 % fewer: the alert, whatever the price says; 15 keeps nothing, so 15 → 13 → 15 still says it; the verdict warns, and nothing within the threshold is silenced as « reassuring » beside it',
        () async {
          final (harness, record, six) = await taken();
          final memory = PayoutRateMemory();
          final port = wallet(P2pWalletRateRead(91711.15));
          final cubit = cubitOf(harness, record, port, memory: memory);
          await cubit.show(six, appeared: true);
          await harness.settle();
          final first = askedAt(record, six);
          expect(memory.firstOf(record, 0), first);
          final kept = memory.askedOf(record, 0);
          final last = harness.coordinator.order(record.orderId).lastSatoshis;
          final fifteen = await toFifteen(
            harness,
            record,
            last: last * 91 ~/ 100,
          );
          await cubit.show(fifteen);
          await harness.settle();
          final now = askedAt(record, fifteen);
          expect(now.value < first.value, isTrue);
          expect(
            cubit.state,
            isA<PayoutRateChecked>().having(
              (s) => s.basis,
              'basis',
              PayoutRateBelowFirst(first),
            ),
          );
          expect(
            PayoutRateCubit.verdictOf(cubit.state),
            PayoutRateVerdict.warns,
          );
          // 15 keeps nothing: neither the smallest for 9 nor the first for 15.
          expect(memory.firstOf(record, 0), first);
          expect(memory.askedOf(record, 0), kept);
          // 15 → 13 → 15: compared again with 6, never with the 15 before.
          harness.coordinator.order(record.orderId).status = 13;
          await cubit.show(await readOf(harness, record));
          harness.coordinator.order(record.orderId).status = 15;
          await cubit.show(await readOf(harness, record), appeared: true);
          await harness.settle();
          expect(
            (cubit.state as PayoutRateChecked).basis,
            PayoutRateBelowFirst(first),
          );
        },
      );

      test(
        'a 15 that carries an alert of the screen (the trace of terms shown otherwise, #231) and a gap within the threshold: fewer sats is still said, never silenced as « reassuring » (functional review C1, security review C2 of #281)',
        () async {
          final (harness, record, six) = await taken();
          final memory = PayoutRateMemory();
          final port = wallet(P2pWalletRateRead(91711.15));
          final cubit = cubitOf(harness, record, port, memory: memory);
          await cubit.show(six, appeared: true);
          await harness.settle();
          final first = askedAt(record, six);
          // One read with another premium, then the order's own again: the trace stays to the end.
          harness.coordinator.orderChanges[record.orderId] = {
            'premium': '9.00',
          };
          await readOf(harness, record);
          harness.coordinator.orderChanges.remove(record.orderId);
          final last = harness.coordinator.order(record.orderId).lastSatoshis;
          final fifteen = await toFifteen(
            harness,
            record,
            last: last * 95 ~/ 100,
          );
          expect(ShownAlerts.any(fifteen), isTrue);
          await cubit.show(fifteen);
          await harness.settle();
          final state = cubit.state;
          expect(
            state,
            isA<PayoutRateChecked>().having(
              (s) => s.basis,
              'basis',
              PayoutRateBelowFirst(first),
            ),
          );
          final check = (state as PayoutRateChecked).check;
          // Within the threshold: beside an alert this comparison alone would have been silenced.
          expect(check, isA<WalletRateCompared>());
          expect((check as WalletRateCompared).warns, isFalse);
          expect(
            CheckPayoutRateUsecase.reassuresBesideAlert(
              fifteen,
              check,
              const PayoutRateAskedNow(),
            ),
            isTrue,
          );
        },
      );

      test(
        'the panel asks a smaller sum at 8 than at 6 (the large one first): no alert at 6 nor 8; the reference stays the largest, so 15 asking the smaller is said (functional review R1, security review R3 of #281)',
        () async {
          final (harness, record, six) = await taken();
          final memory = PayoutRateMemory();
          final port = wallet(P2pWalletRateRead(91711.15));
          final cubit = cubitOf(harness, record, port, memory: memory);
          await cubit.show(six, appeared: true);
          await harness.settle();
          final first = askedAt(record, six);
          expect(
            (cubit.state as PayoutRateChecked).basis,
            const PayoutRateAskedNow(),
          );
          final order = harness.coordinator.order(record.orderId);
          final smaller = order.lastSatoshis * 95 ~/ 100;
          order.lastSatoshis = smaller;
          harness.coordinator.lockEscrow(record.orderId);
          final eight = await readOf(harness, record);
          expect(eight.status, isA<WaitingForPayout>());
          await cubit.show(eight);
          await harness.settle();
          expect(askedAt(record, eight).value < first.value, isTrue);
          expect(
            (cubit.state as PayoutRateChecked).basis,
            const PayoutRateAskedNow(),
          );
          expect(memory.firstOf(record, 0), first);
          for (final status in const [9, 10, 13]) {
            order.status = status;
            await readOf(harness, record);
          }
          harness.coordinator.failPayout(record.orderId);
          final fifteen = await readOf(harness, record);
          expect(askedAt(record, fifteen), askedAt(record, eight));
          await cubit.show(fifteen);
          await harness.settle();
          expect(
            (cubit.state as PayoutRateChecked).basis,
            PayoutRateBelowFirst(first),
          );
        },
      );

      /// An order of a range of 50 to 150 EUR, made and taken for [amount]: its record and its status at 6.
      Future<(MakeHarness, TradeRecord, TradeSeen)> takenRange({
        required double amount,
      }) async {
        final harness = await MakeHarness.start();
        final record =
            (valueOf(
                      await harness.makeOrder(
                        MakeHarness.request(range: (50, 150)),
                      ),
                    )
                    as MakeStarted)
                .record;
        harness.coordinator
          ..lockMakerBond(record.orderId)
          ..take(record.orderId, harness.robot(4), amount: amount);
        return (harness, record, await readOf(harness, record));
      }

      for (final seenAtSix in const [true, false]) {
        test(
          'two contracts of a range (150 EUR, then 100 EUR taken again), the second ${seenAtSix ? 'seen' : 'not seen'} at 6: the invoice of the first contract never serves the second (functional review R1 of #281)',
          () async {
            final (harness, record, six) = await takenRange(amount: 150);
            expect(six.status.trail.take, 0);
            final memory = PayoutRateMemory();
            final port = wallet(P2pWalletRateRead(91711.15));
            final cubit = cubitOf(harness, record, port, memory: memory);
            await cubit.show(six, appeared: true);
            await harness.settle();
            final firstOfZero = askedAt(record, six);
            expect(memory.firstOf(record, 0), firstOfZero);
            // Back in the book, taken again for 100 EUR: contract 1, fewer sats honestly.
            harness.coordinator.backToBook(record.orderId);
            await readOf(harness, record);
            await harness.elapse(const Duration(minutes: 1));
            harness.coordinator.take(
              record.orderId,
              harness.robot(5),
              amount: 100,
            );
            final sixOfOne = await readOf(harness, record);
            expect(sixOfOne.status.trail.take, 1);
            if (seenAtSix) {
              await cubit.show(sixOfOne);
              await harness.settle();
              expect(memory.firstOf(record, 1), askedAt(record, sixOfOne));
            }
            final fifteen = await toFifteen(harness, record);
            expect(fifteen.status.trail.take, 1);
            expect(askedAt(record, fifteen).value < firstOfZero.value, isTrue);
            await cubit.show(fifteen, appeared: true);
            await harness.settle();
            expect(
              (cubit.state as PayoutRateChecked).basis,
              seenAtSix
                  ? const PayoutRateAskedNow()
                  : const PayoutRateFirstUnknown(),
            );
          },
        );
      }

      test(
        'several invoices at 6 and 8: the largest is the reference, so that a smaller one shown first cannot make the same smaller one at 15 look unchanged; 9 still takes the smallest',
        () async {
          final (harness, record, six) = await taken();
          final memory = PayoutRateMemory();
          final port = wallet(P2pWalletRateRead(91711.15));
          final cubit = cubitOf(harness, record, port, memory: memory);
          final order = harness.coordinator.order(record.orderId);
          final honest = order.lastSatoshis;
          // At 6 a read 5 % smaller, then the honest one.
          order.lastSatoshis = honest * 95 ~/ 100;
          final small = await readOf(harness, record);
          await cubit.show(small, appeared: true);
          await harness.settle();
          order.lastSatoshis = honest;
          final big = await readOf(harness, record);
          await cubit.show(big);
          await harness.settle();
          expect(memory.firstOf(record, 0), askedAt(record, big));
          expect(memory.askedOf(record, 0), askedAt(record, small));
          final fifteen = await toFifteen(
            harness,
            record,
            last: honest * 95 ~/ 100,
          );
          expect(askedAt(record, fifteen), askedAt(record, small));
          await cubit.show(fifteen);
          await harness.settle();
          expect(
            (cubit.state as PayoutRateChecked).basis,
            PayoutRateBelowFirst(askedAt(record, big)),
          );
        },
      );

      test(
        'nothing kept (a new memory, as after a restart): the Bull wallet\'s comparison and « not compared with the first invoice », never an invented comparison; a currency not priced and a price not read keep their lines',
        () async {
          final (harness, record, _) = await taken();
          final fifteen = await toFifteen(harness, record);
          for (final (rate, kind) in <(P2pWalletBitcoinRate, Type)>[
            (P2pWalletRateRead(91711.15), WalletRateAtWallet),
            (const P2pWalletRateUnavailable(), WalletRateUnverified),
          ]) {
            final cubit = cubitOf(harness, record, wallet(rate));
            await cubit.show(fifteen, appeared: true);
            await harness.settle();
            final state = cubit.state as PayoutRateChecked;
            expect(state.basis, const PayoutRateFirstUnknown());
            expect(state.check.runtimeType, kind);
          }
        },
      );
    },
  );
}
