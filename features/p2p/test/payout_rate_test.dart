import 'dart:async';

import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/trade/maker_terms.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
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

  FakeP2pWalletPort wallet(P2pWalletBitcoinRate rate) =>
      FakeP2pWalletPort(Ok(Sats.fromInt(50000)))..rate = rate;

  Future<MakerTerms> termsOf(MakeHarness harness, TradeRecord record) async =>
      await CheckPayoutRateUsecase(
        harness.reader,
        wallet(P2pWalletRateRead(91711.15)),
      ).termsOf(record) ??
      (throw StateError('no terms'));

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
          await usecase.priceOf(record, maker),
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
      'nothing for a status not marked stored, nor for a taker\'s trade',
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
        expect(
          await CheckPayoutRateUsecase(harness.reader, port).termsOf(taker),
          isNull,
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

    test(
      'a price read for a step lands on the step shown when it lands, never on the one it was asked for',
      () async {
        final (harness, record, six) = await taken();
        harness.coordinator.lockEscrow(record.orderId);
        await readOf(harness, record);
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
        expect(states, isEmpty);
        expect(await cubit.beforeAct(), isTrue);
      },
    );
  });
}
