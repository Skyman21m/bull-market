import 'dart:async';
import 'dart:io';

import 'package:p2p/p2p.dart';
import 'package:p2p/src/data/trade_payment_repository_impl.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/trade_payment_repository.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_payment.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/bond_payments_in_flight.dart';
import 'package:p2p/src/domain/usecases/trade/pay_bond_from_wallet_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/testing.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';
import 'support/trade_harness.dart';

/// The wallet's port of the tests, which reads the payments recorded each time it is asked to pay, so that a test sees what was written before the payment.
final class _Wallet implements P2pWalletPort {
  final FakeP2pWalletPort fake;
  final TradePaymentRepository payments;
  final TradeRecord Function() record;

  /// What was recorded for the bond when each payment was asked.
  final List<TradePaymentRecord?> recordedAtPayment = [];

  _Wallet(this.fake, this.payments, this.record);

  @override
  Stream<Result<Sats, P2pWalletRefusal>> instantBalance(network) =>
      fake.instantBalance(network);

  @override
  Future<Result<P2pWalletQuote, P2pWalletRefusal>> quote(invoice) =>
      fake.quote(invoice);

  @override
  Future<Result<P2pWalletPayment, P2pWalletRefusal>> payInvoice(
    invoice, {
    required P2pWalletQuote accepted,
  }) async {
    recordedAtPayment.add(switch (await payments.paymentOf(
      record(),
      InvoiceStep.bond,
    )) {
      Ok(:final value) => value,
      Err() => null,
    });
    return fake.payInvoice(invoice, accepted: accepted);
  }

  @override
  Stream<Result<P2pWalletPaymentProgress, P2pWalletRefusal>> watchPayment(
    payment,
  ) => fake.watchPayment(payment);

  @override
  Future<Result<P2pWalletPaymentFound?, P2pWalletRefusal>> findPayment(
    paymentHash,
  ) => fake.findPayment(paymentHash);

  @override
  Future<Result<P2pWalletInvoice, P2pWalletRefusal>> newLightningInvoice(
    RobosatsNetwork network,
    Sats amount, {
    required String payout,
  }) => fake.newLightningInvoice(network, amount, payout: payout);

  @override
  Future<Result<P2pWalletAddress, P2pWalletRefusal>> newReceiveAddress(
    RobosatsNetwork network,
  ) => fake.newReceiveAddress(network);

  @override
  Future<P2pWalletBitcoinRate> bitcoinRate(
    RobosatsNetwork network,
    RobosatsCurrency currency,
  ) => fake.bitcoinRate(network, currency);
}

/// Payments that cannot be written.
final class _Unwritable implements TradePaymentRepository {
  @override
  Future<Result<TradePaymentRecord?, P2pFailure>> paymentOf(
    trade,
    step, {
    int take = 0,
  }) async => const Ok(null);

  @override
  Future<Result<List<TradePaymentRecord>, P2pFailure>> paymentsOfTrade(
    trade,
  ) async => const Ok([]);

  @override
  Future<Result<bool, P2pFailure>> recordStart(
    trade,
    step, {
    required String paymentHash,
    required DateTime at,
    int take = 0,
  }) async => const Err(P2pStorageFailure());

  @override
  Future<Result<bool, P2pFailure>> recordWalletPayment(
    trade,
    step, {
    required String paymentHash,
    required String walletPaymentId,
    int take = 0,
  }) async => const Err(P2pStorageFailure());
}

final class _Setup {
  final TradeHarness harness;
  final TradeRecord record;
  final TradePaymentRepositoryImpl payments;
  final FakeP2pWalletPort fake;
  final _Wallet wallet;
  final PayBondFromWalletUsecase payBond;

  _Setup(
    this.harness,
    this.record,
    this.payments,
    this.fake,
    this.wallet,
    this.payBond,
  );

  static Future<_Setup> start({TradePaymentRepository? payments}) async {
    final harness = await TradeHarness.start();
    final record = TradeHarness.recordOf(await harness.takeShown());
    final stored = TradePaymentRepositoryImpl(harness.database);
    final fake = FakeP2pWalletPort(Ok(Sats.fromInt(500000)));
    final wallet = _Wallet(fake, stored, () => record);
    return _Setup(
      harness,
      record,
      stored,
      fake,
      wallet,
      PayBondFromWalletUsecase(
        harness.reader,
        harness.limiter,
        payments ?? stored,
        wallet,
        harness.locks,
        BondPaymentsInFlight(),
      ),
    );
  }

  /// The status the watch shows now.
  Future<TradeSeen> seen() async {
    final run = harness.watchOf(record);
    await harness.settle();
    await run.subscription.cancel();
    return run.lastStatus.seen;
  }

  /// The invoice `walletPaymentFor` offers at the bond step.
  Future<CheckedBolt11Invoice> offered() async =>
      switch (await payBond.checkBond(record, await seen())) {
        Ok(:final value) => value.walletInvoice,
        Err(:final failure) => throw StateError('not offered: $failure'),
      };

  /// A quote of [invoice], as the wallet would give it.
  P2pWalletQuote quoteOf(CheckedBolt11Invoice invoice) => P2pWalletQuote(
    invoice: invoice,
    payin: Sats(invoice.amount.value + BigInt.from(120)),
    networkFee: Sats.fromInt(27),
    balance: Sats.fromInt(500000),
    quotedAt: harness.now,
  );

  /// The quote the user confirmed, after the tap of « Pay with this wallet ».
  Future<P2pWalletQuote> quoted() async {
    final invoice = await offered();
    fake.scriptQuote(Ok(quoteOf(invoice)));
    return switch (await payBond.quoteBond(record, await seen())) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('no quote: $failure'),
    };
  }

  Future<TradePaymentRecord?> recorded() async =>
      switch (await payments.paymentOf(record, InvoiceStep.bond)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
}

void main() {
  test(
    'the bond ceiling is the bond the order implies, with the state machine\'s tolerance',
    () async {
      final setup = await _Setup.start();
      final invoice = await setup.offered();
      // The scripted coordinator's bond is the order's: within the ceiling, which is 2 % and 1 sat above the bond implied.
      final opened = await setup.harness.reader.open(setup.record);
      final terms = switch (opened) {
        TradeOpened(:final trade) => trade.terms,
        _ => throw StateError('not opened'),
      };
      // Written out: the scripted order's bond at the book's price is about 3,207 sats; with 2 % and 1 sat on it, rounded down, 3,272.
      expect(terms.bondCeiling.value.toInt(), 3272);
      expect(
        invoice.amount.value.toInt(),
        lessThanOrEqualTo(terms.bondCeiling.value.toInt()),
      );
    },
  );

  test(
    'the quote is asked for the invoice of the bond step, nothing paid',
    () async {
      final setup = await _Setup.start();
      final quote = await setup.quoted();
      expect(setup.fake.quoted.single.paymentHash, quote.invoice.paymentHash);
      expect(setup.fake.paid, isEmpty);
      expect(await setup.recorded(), isNull);
    },
  );

  test('a status not marked stored is not quoted', () async {
    final setup = await _Setup.start();
    final seen = await setup.seen();
    final unstored = TradeSeen(seen.status, order: seen.order);
    expect(
      await setup.payBond.quoteBond(setup.record, unstored),
      isA<Err<P2pWalletQuote, BondPayRefusal>>().having(
        (e) => e.failure,
        'failure',
        isA<BondPayNotAtBondStep>(),
      ),
    );
    expect(setup.fake.quoted, isEmpty);
  });

  test(
    'paid: the start recorded before the wallet is asked, its id after',
    () async {
      final setup = await _Setup.start();
      final quote = await setup.quoted();
      final hash = quote.invoice.paymentHash;
      setup.fake.scriptPayment(
        Ok(P2pWalletPayment(id: 'swap-1', paymentHash: hash)),
      );
      final paid = await setup.payBond.payBond(setup.record, accepted: quote);
      expect(paid, isA<Ok<P2pWalletPayment, BondPayRefusal>>());
      expect(setup.wallet.recordedAtPayment.single?.paymentHash, hash);
      expect(setup.wallet.recordedAtPayment.single?.walletPaymentId, isNull);
      final recorded = await setup.recorded();
      expect(recorded?.paymentHash, hash);
      expect(recorded?.walletPaymentId, 'swap-1');
      expect(setup.fake.paid.single.$1.paymentHash, hash);
    },
  );

  test(
    'the order moved on before the payment: nothing paid, nothing recorded',
    () async {
      final setup = await _Setup.start();
      final quote = await setup.quoted();
      setup.harness.coordinator.lockBond(setup.harness.robot(0));
      final paid = await setup.payBond.payBond(setup.record, accepted: quote);
      expect(
        paid,
        isA<Err<P2pWalletPayment, BondPayRefusal>>().having(
          (e) => e.failure,
          'failure',
          isA<BondPayNotAtBondStep>(),
        ),
      );
      expect(setup.fake.paid, isEmpty);
      expect(await setup.recorded(), isNull);
    },
  );

  test(
    'a quote made from the bond step a screen kept on its return (#152), the bond locked by another wallet meanwhile: the payment reads first, and nothing is paid',
    () async {
      final setup = await _Setup.start();
      // The quote of the status kept on screen, as `BondPaymentCubit.ask` makes it from the status shown.
      final quote = await setup.quoted();
      setup.harness.coordinator.lockBond(setup.harness.robot(0));
      final reads = setup.harness.coordinator.received
          .where((r) => r == ScriptedRequest.order)
          .length;
      final paid = await setup.payBond.payBond(setup.record, accepted: quote);
      expect(paid, isA<Err<P2pWalletPayment, BondPayRefusal>>());
      expect(setup.fake.paid, isEmpty);
      expect(await setup.recorded(), isNull);
      expect(
        setup.harness.coordinator.received
            .where((r) => r == ScriptedRequest.order)
            .length,
        reads + 1,
      );
    },
  );

  test('the pre-take ended before the payment: nothing paid', () async {
    final setup = await _Setup.start();
    final quote = await setup.quoted();
    await setup.harness.elapse(
      ScriptedCoordinator.preTakeTime + const Duration(seconds: 30),
    );
    final paid = await setup.payBond.payBond(setup.record, accepted: quote);
    expect(paid, isA<Err<P2pWalletPayment, BondPayRefusal>>());
    expect(setup.fake.paid, isEmpty);
    expect(await setup.recorded(), isNull);
  });

  test(
    'a quote of another invoice is not paid: a new confirmation is needed',
    () async {
      final setup = await _Setup.start();
      final invoice = await setup.offered();
      final other = checkedBolt11InvoiceForTesting(
        bolt11: invoice.bolt11,
        amount: invoice.amount,
        network: invoice.network,
        paymentHash: 'cd${'0' * 62}',
        expiresAt: invoice.expiresAt,
        payableUntil: invoice.payableUntil,
        now: setup.harness.now,
      );
      final paid = await setup.payBond.payBond(
        setup.record,
        accepted: setup.quoteOf(other ?? (throw StateError('no invoice'))),
      );
      expect(
        paid,
        isA<Err<P2pWalletPayment, BondPayRefusal>>().having(
          (e) => e.failure,
          'failure',
          isA<BondPayInvoiceChanged>(),
        ),
      );
      expect(setup.fake.paid, isEmpty);
    },
  );

  test(
    'a quote of another invoice text with the same payment hash is not paid either',
    () async {
      final setup = await _Setup.start();
      final invoice = await setup.offered();
      final other = checkedBolt11InvoiceForTesting(
        bolt11: Bolt11TestInvoice(
          network: setup.harness.network == RobosatsNetwork.mainnet
              ? Bolt11Network.mainnet
              : Bolt11Network.testnet,
          sats: invoice.amount.value.toInt(),
          seed: 99,
          createdAt: setup.harness.now,
        ).text,
        amount: invoice.amount,
        network: invoice.network,
        paymentHash: invoice.paymentHash,
        expiresAt: invoice.expiresAt,
        payableUntil: invoice.payableUntil,
        now: setup.harness.now,
      );
      expect(other?.bolt11, isNot(invoice.bolt11));
      final paid = await setup.payBond.payBond(
        setup.record,
        accepted: setup.quoteOf(other ?? (throw StateError('no invoice'))),
      );
      expect(
        paid,
        isA<Err<P2pWalletPayment, BondPayRefusal>>().having(
          (e) => e.failure,
          'failure',
          isA<BondPayInvoiceChanged>(),
        ),
      );
      expect(setup.fake.paid, isEmpty);
    },
  );

  test('a start that cannot be written: the wallet is not asked', () async {
    final setup = await _Setup.start(payments: _Unwritable());
    final quote = await setup.quoted();
    final paid = await setup.payBond.payBond(setup.record, accepted: quote);
    expect(
      paid,
      isA<Err<P2pWalletPayment, BondPayRefusal>>().having(
        (e) => e.failure,
        'failure',
        isA<BondPayNotRecorded>(),
      ),
    );
    expect(setup.fake.paid, isEmpty);
  });

  test(
    'a broadcast whose outcome is unknown: refused as such, its id recorded, the funds may have moved',
    () async {
      final setup = await _Setup.start();
      final quote = await setup.quoted();
      final payment = P2pWalletPayment(
        id: 'swap-2',
        paymentHash: quote.invoice.paymentHash,
      );
      setup.fake.scriptPayment(Err(P2pWalletBroadcastUnknown(payment)));
      final paid = await setup.payBond.payBond(setup.record, accepted: quote);
      final failure = switch (paid) {
        Err(:final failure) => failure,
        Ok() => throw StateError('paid'),
      };
      expect(failure.fundsMayHaveMoved, isTrue);
      expect((await setup.recorded())?.walletPaymentId, 'swap-2');
    },
  );

  test(
    'a refusal that moved nothing may be tried again, after a new quote: one more start, one more payment',
    () async {
      final setup = await _Setup.start();
      final first = await setup.quoted();
      setup.fake.scriptPayment(const Err(P2pWalletServiceUnreachable()));
      final refused = await setup.payBond.payBond(
        setup.record,
        accepted: first,
      );
      expect(refused, isA<Err<P2pWalletPayment, BondPayRefusal>>());
      final firstStart = (await setup.recorded())?.startedAt;
      await setup.harness.elapse(const Duration(seconds: 5));

      final second = await setup.quoted();
      setup.fake.scriptPayment(
        Ok(
          P2pWalletPayment(
            id: 'swap-3',
            paymentHash: second.invoice.paymentHash,
          ),
        ),
      );
      final paid = await setup.payBond.payBond(setup.record, accepted: second);
      expect(paid, isA<Ok<P2pWalletPayment, BondPayRefusal>>());
      expect(setup.fake.paid, hasLength(2));
      final recorded = await setup.recorded();
      expect(recorded?.walletPaymentId, 'swap-3');
      expect(recorded?.startedAt.isAfter(firstStart ?? DateTime(2000)), isTrue);
    },
  );

  test(
    'a quote presented twice pays once: the second is refused, nothing sent again',
    () async {
      final setup = await _Setup.start();
      final quote = await setup.quoted();
      setup.fake.scriptPayment(
        Ok(
          P2pWalletPayment(
            id: 'swap-4',
            paymentHash: quote.invoice.paymentHash,
          ),
        ),
      );
      final results = await Future.wait([
        setup.payBond.payBond(setup.record, accepted: quote),
        setup.payBond.payBond(setup.record, accepted: quote),
      ]);
      expect(
        results.whereType<Ok<P2pWalletPayment, BondPayRefusal>>(),
        hasLength(1),
      );
      expect((await setup.recorded())?.walletPaymentId, 'swap-4');
    },
  );

  test(
    'one action of the order at a time: the payment waits while the take or the payout holds the order',
    () async {
      final setup = await _Setup.start();
      final quote = await setup.quoted();
      setup.fake.scriptPayment(
        Ok(
          P2pWalletPayment(
            id: 'swap-6',
            paymentHash: quote.invoice.paymentHash,
          ),
        ),
      );
      final release = Completer<void>();
      final opened = await setup.harness.reader.open(setup.record);
      final coordinator = switch (opened) {
        TradeOpened(:final trade) => trade.coordinator,
        _ => throw StateError('not opened'),
      };
      final holding = setup.harness.locks.run(
        setup.record.network,
        coordinator,
        setup.record.orderId,
        () => release.future,
      );
      final paying = setup.payBond.payBond(setup.record, accepted: quote);
      await setup.harness.settle();
      expect(setup.fake.paid, isEmpty);
      release.complete();
      await holding;
      expect(await paying, isA<Ok<P2pWalletPayment, BondPayRefusal>>());
      expect(setup.fake.paid, hasLength(1));
    },
  );

  test(
    'a cancel waits while a payment of the bond holds the order: nothing sent to the coordinator meanwhile',
    () async {
      final setup = await _Setup.start();
      final seen = await setup.seen();
      final release = Completer<void>();
      final opened = await setup.harness.reader.open(setup.record);
      final coordinator = switch (opened) {
        TradeOpened(:final trade) => trade.coordinator,
        _ => throw StateError('not opened'),
      };
      final holding = setup.harness.locks.run(
        setup.record.network,
        coordinator,
        setup.record.orderId,
        () => release.future,
      );
      final cancelling = setup.harness.cancel.execute(setup.record, seen);
      await setup.harness.settle();
      expect(
        setup.harness.coordinator.received.where(
          (r) => r == ScriptedRequest.cancel,
        ),
        isEmpty,
      );
      release.complete();
      await holding;
      await cancelling;
      expect(
        setup.harness.coordinator.received.where(
          (r) => r == ScriptedRequest.cancel,
        ),
        hasLength(1),
      );
    },
  );

  group('the records of the payments', () {
    test(
      'a start of another invoice for the same step writes nothing, and does not move the first',
      () async {
        final setup = await _Setup.start();
        final quote = await setup.quoted();
        final first = await setup.payments.recordStart(
          setup.record,
          InvoiceStep.bond,
          paymentHash: quote.invoice.paymentHash,
          at: setup.harness.now,
        );
        expect(
          first,
          isA<Ok<bool, P2pFailure>>().having((r) => r.value, 'value', isTrue),
        );
        final before = await setup.recorded();
        final other = await setup.payments.recordStart(
          setup.record,
          InvoiceStep.bond,
          paymentHash: 'cd${'0' * 62}',
          at: setup.harness.now.add(const Duration(minutes: 1)),
        );
        expect(
          other,
          isA<Ok<bool, P2pFailure>>().having((r) => r.value, 'value', isFalse),
        );
        expect(await setup.recorded(), before);
      },
    );

    test(
      'a payment whose start records nothing is not asked of the wallet',
      () async {
        final setup = await _Setup.start();
        final quote = await setup.quoted();
        final _ = await setup.payments.recordStart(
          setup.record,
          InvoiceStep.bond,
          paymentHash: 'cd${'0' * 62}',
          at: setup.harness.now,
        );
        final paid = await setup.payBond.payBond(setup.record, accepted: quote);
        expect(
          paid,
          isA<Err<P2pWalletPayment, BondPayRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<BondPayNotRecorded>(),
          ),
        );
        expect(setup.fake.paid, isEmpty);
      },
    );
  });

  test(
    'a payment refused leaves no payment running: a screen opened again offers to pay',
    () async {
      final setup = await _Setup.start();
      final quote = await setup.quoted();
      setup.fake.scriptPayment(const Err(P2pWalletServiceUnreachable()));
      final paying = setup.payBond.payBond(setup.record, accepted: quote);
      expect(setup.payBond.bondPaymentRunning(setup.record), isNotNull);
      await paying;
      expect(setup.payBond.bondPaymentRunning(setup.record), isNull);
    },
  );

  test('the ceiling of each step is what walletPaymentFor is asked with', () {
    // A guard against a later change: the payment is offered within the take's terms, never a figure of the coordinator; the escrow's (#97) within its own ceiling.
    final source = File(
      'lib/src/domain/usecases/trade/pay_bond_from_wallet_usecase.dart',
    ).readAsStringSync();
    expect(source, contains('InvoiceStep.bond => terms.bondCeiling,'));
    expect(source, contains('InvoiceStep.escrow => terms.escrowCeiling,'));
  });

  group('a maker\'s trade, opened by the reader since #179', () {
    // The guard of money: since #180 a maker's bond at 0 is paid from this wallet, and since #187 a maker seller's escrow at 6 and 7 under its own rules; tests of behaviour, as this file's earlier pin of its text announced (security review of #179). The maker bond's rules and refusals in full: `maker_bond_from_wallet_test.dart`; the escrow's: `maker_escrow_from_wallet_test.dart`.
    test(
      'the maker bond at 0: offered, quoted and paid since #180, under the step bond, and never by the escrow\'s instance',
      () async {
        final harness = await MakeHarness.start();
        final made = await harness.makeOrder(MakeHarness.request());
        final record = switch (made) {
          Ok(value: final MakeStarted started) => started.record,
          final other => fail('$other'),
        };
        final run = harness.watchOf(record);
        await harness.settle();
        final seen = run.lastStatus.seen;
        await run.subscription.cancel();
        expect(seen.stored, isTrue);
        expect(seen.status, isA<WaitingForMakerBond>());
        final fake = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)));
        final payments = TradePaymentRepositoryImpl(harness.database);
        PayBondFromWalletUsecase payBondOf(InvoiceStep step) =>
            PayBondFromWalletUsecase(
              harness.reader,
              harness.limiter,
              payments,
              fake,
              harness.locks,
              BondPaymentsInFlight(),
              step: step,
            );
        expect(
          await payBondOf(InvoiceStep.escrow).checkBond(record, seen),
          isA<Err<Object?, BondPayRefusal>>(),
        );
        final payBond = payBondOf(InvoiceStep.bond);
        final offered = switch (await payBond.checkBond(record, seen)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        final quote = P2pWalletQuote(
          invoice: offered.walletInvoice,
          payin: Sats(offered.walletInvoice.amount.value + BigInt.from(120)),
          networkFee: Sats.fromInt(27),
          balance: Sats.fromInt(5000000),
          quotedAt: harness.now,
        );
        fake
          ..scriptQuote(Ok(quote))
          ..scriptPayment(
            Ok(
              P2pWalletPayment(
                id: 'swap-made',
                paymentHash: quote.invoice.paymentHash,
              ),
            ),
          );
        expect(
          await payBond.quoteBond(record, seen),
          isA<Ok<P2pWalletQuote, BondPayRefusal>>(),
        );
        expect(
          await payBond.payBond(record, accepted: quote),
          isA<Ok<P2pWalletPayment, BondPayRefusal>>(),
        );
        expect(fake.paid, hasLength(1));
        expect(switch (await payments.paymentOf(record, InvoiceStep.bond)) {
          Ok(:final value) => value?.walletPaymentId,
          Err() => null,
        }, 'swap-made');
      },
    );

    for (final status in [6, 7]) {
      test(
        'a maker seller\'s escrow at $status: offered and quoted since #187, never paid without the confirmation of its contract',
        () async {
          final harness = await MakeHarness.start();
          final record = switch (await harness.makeOrder(
            MakeHarness.request(sell: true),
          )) {
            Ok(value: final MakeStarted started) => started.record,
            final other => fail('$other'),
          };
          harness.coordinator
            ..lockMakerBond(42)
            ..take(42, harness.robot(5));
          harness.coordinator.order(42).status = status;
          final run = harness.watchOf(record);
          await harness.settle();
          final seen = run.lastStatus.seen;
          await run.subscription.cancel();
          expect(seen.stored, isTrue);
          expect(
            seen.status,
            status == 6 ? isA<WaitingForBoth>() : isA<WaitingForEscrow>(),
          );
          final fake = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)));
          final payBond = PayBondFromWalletUsecase(
            harness.reader,
            harness.limiter,
            TradePaymentRepositoryImpl(harness.database),
            fake,
            harness.locks,
            BondPaymentsInFlight(),
            step: InvoiceStep.escrow,
          );
          final offered = switch (await payBond.checkBond(record, seen)) {
            Ok(:final value) => value.walletInvoice,
            Err(:final failure) => fail('$failure'),
          };
          final quote = P2pWalletQuote(
            invoice: offered,
            payin: Sats(offered.amount.value + BigInt.from(120)),
            networkFee: Sats.fromInt(27),
            balance: Sats.fromInt(5000000),
            quotedAt: harness.now,
          );
          fake
            ..scriptQuote(Ok(quote))
            ..scriptPayment(
              const Ok(
                P2pWalletPayment(id: 'never-asked', paymentHash: 'none'),
              ),
            );
          expect(
            await payBond.quoteBond(record, seen),
            isA<Ok<P2pWalletQuote, BondPayRefusal>>(),
          );
          expect(
            await payBond.payBond(record, accepted: quote),
            isA<Err<Object?, BondPayRefusal>>().having(
              (e) => e.failure,
              'failure',
              isA<BondPayContractNotConfirmed>(),
            ),
          );
          expect(fake.paid, isEmpty);
        },
      );
    }
  });

  group('followBond', () {
    test('none recorded: none, and nothing asked of the wallet', () async {
      final setup = await _Setup.start();
      expect(await setup.payBond.followBond(setup.record).toList(), [
        isA<BondPaymentNone>(),
      ]);
      expect(setup.fake.found, isEmpty);
    });

    test('a start recorded the wallet has no payment for: none', () async {
      final setup = await _Setup.start();
      final quote = await setup.quoted();
      final _ = await setup.payments.recordStart(
        setup.record,
        InvoiceStep.bond,
        paymentHash: quote.invoice.paymentHash,
        at: setup.harness.now,
      );
      expect(await setup.payBond.followBond(setup.record).toList(), [
        isA<BondPaymentNone>(),
      ]);
      expect(setup.fake.found, [quote.invoice.paymentHash]);
    });

    test(
      'a payment found: followed as the wallet records it, its id written when missing',
      () async {
        final setup = await _Setup.start();
        final quote = await setup.quoted();
        final hash = quote.invoice.paymentHash;
        final _ = await setup.payments.recordStart(
          setup.record,
          InvoiceStep.bond,
          paymentHash: hash,
          at: setup.harness.now,
        );
        final payment = P2pWalletPayment(id: 'swap-5', paymentHash: hash);
        setup.fake
          ..setFound(
            hash,
            P2pWalletPaymentFound(
              payment: payment,
              progress: const P2pWalletPaymentSent(),
            ),
          )
          ..setProgress(payment, const Ok(P2pWalletPaymentSent()));
        final seen = <BondPaymentWatch>[];
        final following = setup.payBond
            .followBond(setup.record)
            .listen(seen.add);
        for (var i = 0; i < 50 && seen.length < 2; i++) {
          await setup.harness.settle();
        }
        setup.fake.setProgress(payment, const Ok(P2pWalletPaymentPending()));
        for (var i = 0; i < 50 && seen.length < 3; i++) {
          await setup.harness.settle();
        }
        unawaited(following.cancel());
        expect(seen.whereType<BondPaymentFollowed>().map((f) => f.progress), [
          isA<P2pWalletPaymentSent>(),
          isA<P2pWalletPaymentSent>(),
          isA<P2pWalletPaymentPending>(),
        ]);
        expect((await setup.recorded())?.walletPaymentId, 'swap-5');
      },
    );
  });

  test(
    'the use case asks the wallet nothing on its own: no quote and no payment without a call',
    () async {
      final setup = await _Setup.start();
      final run = setup.harness.watchOf(setup.record);
      await setup.harness.elapse(const Duration(seconds: 30));
      await run.subscription.cancel();
      expect(setup.fake.quoted, isEmpty);
      expect(setup.fake.paid, isEmpty);
    },
  );

  group('the payment\'s read and the watch (#141)', () {
    int orderReads(_Setup setup) => setup.harness.coordinator.received
        .where((kind) => kind == ScriptedRequest.order)
        .length;

    test(
      'the payment\'s read left first, its answer held; the screen asks the watch to read: nothing leaves then, and the bond is paid (review of #142, R1)',
      () async {
        final setup = await _Setup.start();
        final quote = await setup.quoted();
        setup.fake.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-1',
              paymentHash: quote.invoice.paymentHash,
            ),
          ),
        );
        final signals = StreamController<TradeWatchSignal>.broadcast();
        final run = setup.harness.watchOf(
          setup.record,
          signals: signals.stream,
        );
        await setup.harness.settle();
        setup.harness.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.answerDelayed,
        );
        final reads = orderReads(setup);
        final paid = setup.payBond.payBond(setup.record, accepted: quote);
        await setup.harness.settle();
        expect(orderReads(setup), reads + 1);
        signals.add(TradeWatchSignal.readNow);
        await setup.harness.settle();
        expect(orderReads(setup), reads + 1);
        setup.harness.coordinator.deliverDelayed();
        expect(await paid, isA<Ok<P2pWalletPayment, BondPayRefusal>>());
        expect(setup.fake.paid, hasLength(1));
        await setup.harness.settle();
        // The watch's read, once the payment's read ended.
        expect(orderReads(setup), reads + 2);
        await run.subscription.cancel();
        await signals.close();
      },
    );

    test(
      'the payment\'s read superseded by a read of the watch that left before it and answered first: read once more, and the bond is paid, never « the order moved on »',
      () async {
        final setup = await _Setup.start();
        final quote = await setup.quoted();
        setup.fake.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-1',
              paymentHash: quote.invoice.paymentHash,
            ),
          ),
        );
        final run = setup.harness.watchOf(setup.record);
        await setup.harness.settle();
        setup.harness.coordinator
          ..failNext(ScriptedRequest.order, ScriptedFault.answerDelayed)
          ..failNext(ScriptedRequest.order, ScriptedFault.answerDelayed);
        await setup.harness.elapse(const Duration(seconds: 10));
        final reads = orderReads(setup);
        final paid = setup.payBond.payBond(setup.record, accepted: quote);
        await setup.harness.settle();
        expect(orderReads(setup), reads + 1);
        setup.harness.coordinator.deliverDelayed(1);
        await setup.harness.settle();
        setup.harness.coordinator.deliverDelayed();
        expect(await paid, isA<Ok<P2pWalletPayment, BondPayRefusal>>());
        expect(orderReads(setup), reads + 2);
        expect(setup.fake.paid, hasLength(1));
        await run.subscription.cancel();
      },
    );
  });
}
