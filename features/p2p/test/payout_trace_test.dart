import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/payout_trace.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_payout_outcome.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/payout_from_wallet_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/src/domain/usecases/trade/wallet_payout_destinations.dart';
import 'package:p2p/src/presentation/trade_panel.dart';
import 'package:p2p/testing.dart'
    show
        Bolt11TestInvoice,
        FakeP2pWalletPort,
        ScriptedFault,
        ScriptedMakerRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';

/// Where the payout of each contract of a maker buyer's order came from (schema 9, #204; design note `docs/design/phase-3-making-an-order.md` § 3.5 bis), over the real records, use cases and state machine, the coordinator played by `ScriptedMakerCoordinator` (never a real one): an invoice of this wallet, a pasted one, a contract taken again whose payout was not given here, each said by the status the reader gives, after a restart of the app too.
void main() {
  T valueOf<T, F extends Failure>(Result<T, F> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  /// The status the watch of [record] read once, on [harness].
  Future<TradeSeen> read(MakeHarness harness, TradeRecord record) async {
    final run = harness.watchOf(record);
    await harness.settle();
    final watch = run.lastStatus;
    await run.subscription.cancel();
    final view = TradeView.of(watch);
    if (view is! TradeContract) throw StateError('$view');
    return watch.seen;
  }

  /// [record] opened again from the records by a new run of the app, before any read.
  Future<TradeSeen> reopened(MakeHarness harness, TradeRecord record) async =>
      switch (await harness.restart().reader.open(record)) {
        TradeOpened(:final trade) => trade.seen,
        final other => throw StateError('$other'),
      };

  /// A maker buyer's order made on [harness], its bond locked elsewhere, taken by robot [taker]: its record and the status at 6.
  Future<(TradeRecord, TradeSeen)> takenBuyOrder(
    MakeHarness harness, {
    int taker = 4,
  }) async {
    final made = valueOf(await harness.makeOrder());
    final record = (made as MakeStarted).record;
    await read(harness, record);
    harness.coordinator.lockMakerBond(record.orderId);
    await read(harness, record);
    harness.coordinator.take(record.orderId, harness.robot(taker));
    final seen = await read(harness, record);
    expect(seen.status, isA<WaitingForBoth>());
    return (record, seen);
  }

  /// An invoice of the amount [seen] asks, the decoder taught it; [seed] makes it another one.
  (Bolt11TestInvoice, Sats) invoiceFor(
    MakeHarness harness,
    TradeRecord record,
    TradeSeen seen, {
    int seed = 77,
  }) {
    final ask = valueOf(harness.payout.ask(record, seen));
    final amount =
        ask.invoiceSatsFor(RoutingBudgetPpm.referenceDefault) ??
        (throw StateError('no amount'));
    final invoice = Bolt11TestInvoice(
      network: Bolt11Network.testnet,
      sats: amount.value.toInt(),
      seed: seed,
      createdAt: harness.now,
      expiry: const Duration(hours: 24),
      description: 'payout',
    );
    harness.coordinator.decoder.add(invoice);
    return (invoice, amount);
  }

  Future<void> submit(
    MakeHarness harness,
    TradeRecord record,
    TradeSeen seen,
    String text,
  ) async {
    final checked = valueOf(
      harness.payout.check(
        record,
        seen,
        PayoutInvoiceText(text, budget: RoutingBudgetPpm.referenceDefault),
      ),
    );
    valueOf(await harness.payout.execute(record, checked));
  }

  test(
    'an invoice this wallet gave is « from this wallet » at « Confirm … sent », after a restart too',
    () async {
      final harness = await MakeHarness.start();
      final (record, seen) = await takenBuyOrder(harness);
      expect(seen.payout, const PayoutNotGivenHere());
      final (invoice, amount) = invoiceFor(harness, record, seen);
      final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
        ..scriptInvoice(
          Ok(
            P2pWalletInvoice(
              bolt11: invoice.text,
              amount: amount,
              expiresAt: harness.now.add(const Duration(hours: 24)),
              received: amount,
            ),
          ),
        );
      final given = valueOf(
        await PayoutFromWalletUsecase(
          wallet,
          given: harness.walletPayouts,
        ).invoice(valueOf(harness.payout.ask(record, seen)), amount),
      );
      // The very text the wallet gave, as the panel puts it in the field.
      await submit(harness, record, seen, given.bolt11);
      final at7 = await read(harness, record);
      expect(
        at7.payout,
        PayoutFromThisWallet(PayoutTraceKind.invoice, harness.now),
      );
      harness.coordinator.lockEscrow(record.orderId);
      final at9 = await read(harness, record);
      expect(at9.status, isA<Chatting>());
      expect(at9.payout, isA<PayoutFromThisWallet>());
      expect(
        (await reopened(harness, record)).payout,
        PayoutFromThisWallet(PayoutTraceKind.invoice, harness.now),
      );
    },
  );

  test(
    'a pasted invoice is « pasted », after a restart too; a payout given again replaces it',
    () async {
      final harness = await MakeHarness.start();
      final (record, seen) = await takenBuyOrder(harness);
      final (invoice, _) = invoiceFor(harness, record, seen);
      await submit(harness, record, seen, invoice.text);
      harness.coordinator.lockEscrow(record.orderId);
      final at9 = await read(harness, record);
      expect(at9.payout, PayoutPasted(PayoutTraceKind.invoice, harness.now));
      final again = await reopened(harness, record);
      expect(again.payout, PayoutPasted(PayoutTraceKind.invoice, harness.now));
      // The next run's wallet gave nothing yet: the registry is in memory only, and a pasted payout stays pasted.
      expect(
        harness.restart().walletPayouts.isInvoiceOfThisWallet(invoice.text),
        isFalse,
      );
    },
  );

  test(
    'a contract taken again after the book: its payout is its own, contract 0\'s never stands for it, after a restart too',
    () async {
      final harness = await MakeHarness.start();
      final (record, seen) = await takenBuyOrder(harness);
      final (invoice, _) = invoiceFor(harness, record, seen);
      await submit(harness, record, seen, invoice.text);
      expect((await read(harness, record)).payout, isA<PayoutPasted>());
      // The taker seller does not lock: back in the book, taken again by another robot, a contract of its own.
      harness.coordinator.backToBook(record.orderId);
      await read(harness, record);
      await harness.elapse(const Duration(minutes: 1));
      harness.coordinator.take(record.orderId, harness.robot(5));
      final next = await read(harness, record);
      expect(next.status.trail.take, 1);
      expect(next.payout, const PayoutNotGivenHere());
      expect(
        (await reopened(harness, record)).payout,
        const PayoutNotGivenHere(),
      );
      // Its own payout, then, is said as its own.
      final (second, _) = invoiceFor(harness, record, next, seed: 78);
      await submit(harness, record, next, second.text);
      expect((await read(harness, record)).payout, isA<PayoutPasted>());
      final records = harness.payouts;
      expect(
        valueOf(await records.traceOf(record, take: 0)),
        isA<PayoutPasted>(),
      );
      expect(
        valueOf(await records.traceOf(record, take: 1)),
        isA<PayoutPasted>(),
      );
    },
  );

  test(
    'a refused payout leaves no trace: the coordinator does not hold it',
    () async {
      final harness = await MakeHarness.start();
      final (record, seen) = await takenBuyOrder(harness);
      final (invoice, _) = invoiceFor(harness, record, seen);
      final checked = valueOf(
        harness.payout.check(
          record,
          seen,
          PayoutInvoiceText(
            invoice.text,
            budget: RoutingBudgetPpm.referenceDefault,
          ),
        ),
      );
      // The order moves on before the payout leaves: it is refused from the fresh read, nothing recorded.
      harness.coordinator.backToBook(record.orderId);
      final outcome = await harness.payout.execute(record, checked);
      expect(outcome, isA<Err<PayoutSubmission, PayoutNotSent>>());
      expect(
        valueOf(await harness.payouts.traceOf(record, take: 0)),
        const PayoutNotGivenHere(),
      );
    },
  );

  test(
    'the wallet\'s texts are compared as their formats read them: an invoice and a segwit address without case, another address exactly',
    () {
      final given = WalletPayoutDestinations()
        ..gaveInvoice('lntb1abcdef')
        ..gaveAddress('tb1qxyz')
        ..gaveAddress('2NAbc');
      expect(given.isInvoiceOfThisWallet('LNTB1ABCDEF'), isTrue);
      expect(given.isInvoiceOfThisWallet('lightning:lntb1abcdef'), isTrue);
      expect(given.isInvoiceOfThisWallet('lntb1abcdeg'), isFalse);
      expect(given.isAddressOfThisWallet('TB1QXYZ'), isTrue);
      expect(given.isAddressOfThisWallet('2NAbc'), isTrue);
      expect(given.isAddressOfThisWallet('2nabc'), isFalse);
      expect('$given', 'WalletPayoutDestinations');
    },
  );

  test(
    'a payout whose answer was lost (an outcome unknown) leaves its trace: the coordinator may hold it (functional review of schema 9, C5, m12)',
    () async {
      final harness = await MakeHarness.start();
      final (record, seen) = await takenBuyOrder(harness);
      final (invoice, _) = invoiceFor(harness, record, seen);
      final checked = valueOf(
        harness.payout.check(
          record,
          seen,
          PayoutInvoiceText(
            invoice.text,
            budget: RoutingBudgetPpm.referenceDefault,
          ),
        ),
      );
      harness.coordinator.failNext(
        ScriptedMakerRequest.payout,
        ScriptedFault.timedOut,
      );
      expect(
        valueOf(await harness.payout.execute(record, checked)),
        isA<PayoutOutcomeUnknown>(),
      );
      expect(
        valueOf(await harness.payouts.traceOf(record, take: 0)),
        PayoutPasted(PayoutTraceKind.invoice, harness.now),
      );
    },
  );

  test(
    'a payout the coordinator refused once it was sent leaves no trace: it does not hold it (functional review of schema 9, C5, m11)',
    () async {
      final harness = await MakeHarness.start();
      final (record, seen) = await takenBuyOrder(harness);
      final (invoice, _) = invoiceFor(harness, record, seen);
      final checked = valueOf(
        harness.payout.check(
          record,
          seen,
          PayoutInvoiceText(
            invoice.text,
            budget: RoutingBudgetPpm.referenceDefault,
          ),
        ),
      );
      harness.coordinator.failNext(
        ScriptedMakerRequest.payout,
        ScriptedFault.refused,
      );
      expect(
        valueOf(await harness.payout.execute(record, checked)),
        isA<PayoutNotTaken>(),
      );
      expect(
        valueOf(await harness.payouts.traceOf(record, take: 0)),
        const PayoutNotGivenHere(),
      );
    },
  );

  test(
    'records that cannot be read say « unknown », never « from this wallet » (functional review of schema 9, C5, m10)',
    () async {
      final harness = await MakeHarness.start();
      final (record, _) = await takenBuyOrder(harness);
      await harness.payouts.recordPayout(
        record,
        take: 0,
        source: PayoutTraceSource.thisWallet,
        kind: PayoutTraceKind.invoice,
        paymentHash: 'a7' * 32,
        at: harness.now,
      );
      // The table of the payouts gone from the file (a test's own statement): every read of it fails.
      await harness.database.customStatement(
        'ALTER TABLE trade_payouts RENAME TO trade_payouts_gone',
      );
      expect(
        await harness.payouts.traceOf(record, take: 0),
        isA<Err<PayoutTrace, P2pFailure>>(),
      );
      final opened = await reopened(harness, record);
      expect(opened.payout, const PayoutTraceUnreadable());
      final again = await read(harness.restart(), record);
      expect(again.payout, const PayoutTraceUnreadable());
    },
  );
}
