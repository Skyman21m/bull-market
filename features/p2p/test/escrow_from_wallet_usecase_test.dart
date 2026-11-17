import 'package:p2p/p2p.dart';
import 'package:p2p/src/data/trade_payment_repository_impl.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_payment.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/bond_payments_in_flight.dart';
import 'package:p2p/src/domain/usecases/trade/pay_bond_from_wallet_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/testing.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/src/domain/repositories/trade_payment_repository.dart';
import 'package:p2p/src/domain/robot_request_limiter.dart';
import 'package:p2p/src/domain/usecases/trade/trade_take_locks.dart';
import 'package:p2p/src/p2p_locator.dart';
import 'package:p2p/src/presentation/bond_payment_cubit.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// The seller's escrow paid from the wallet (#97): the bond's use case for the escrow's step, over the coordinator the tests play and the wallet's fake port (never a real coordinator, never a swap service, never money).
final class _Seller {
  final TradeHarness app;
  final TradeRecord record;
  final TradePaymentRepositoryImpl payments;
  final FakeP2pWalletPort wallet;
  final BondPaymentsInFlight inFlight;
  final PayBondFromWalletUsecase escrow;
  final PayBondFromWalletUsecase bond;

  _Seller(
    this.app,
    this.record,
    this.payments,
    this.wallet,
    this.inFlight,
    this.escrow,
    this.bond,
  );

  /// A buy order taken, its bond locked by another wallet: the trade at 6, or at [status] (7).
  static Future<_Seller> at({
    int? status,
    void Function(TradeHarness)? before,
  }) async {
    final app = await TradeHarness.start(orderType: 0);
    before?.call(app);
    final taken = await app.takeShown();
    expect(
      taken,
      isA<Ok<TakeOutcome, TakeRefusal>>().having(
        (ok) => ok.value,
        'outcome',
        isA<TakeStarted>(),
      ),
    );
    final record = TradeHarness.recordOf(taken);
    expect(record.role, TradeRole.seller);
    final run = app.watchOf(record);
    await app.settle();
    app.coordinator.lockBond(app.robot(0));
    if (status != null) app.coordinator.moveTo(status);
    await app.elapse(const Duration(seconds: 10));
    await run.subscription.cancel();
    final payments = TradePaymentRepositoryImpl(app.database);
    final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(500000)));
    final inFlight = BondPaymentsInFlight();
    PayBondFromWalletUsecase of(InvoiceStep step) => PayBondFromWalletUsecase(
      app.reader,
      app.limiter,
      payments,
      wallet,
      app.locks,
      inFlight,
      step: step,
    );
    return _Seller(
      app,
      record,
      payments,
      wallet,
      inFlight,
      of(InvoiceStep.escrow),
      of(InvoiceStep.bond),
    );
  }

  Future<TradeSeen> seen() async {
    final run = app.watchOf(record);
    await app.settle();
    await run.subscription.cancel();
    return run.lastStatus.seen;
  }

  Future<CheckedBolt11Invoice> offered() async =>
      switch (await escrow.checkBond(record, await seen())) {
        Ok(:final value) => value.walletInvoice,
        Err(:final failure) => throw StateError('not offered: $failure'),
      };

  P2pWalletQuote quoteOf(CheckedBolt11Invoice invoice) => P2pWalletQuote(
    invoice: invoice,
    payin: Sats(invoice.amount.value + BigInt.from(300)),
    networkFee: Sats.fromInt(27),
    balance: Sats.fromInt(500000),
    quotedAt: app.now,
  );

  Future<P2pWalletQuote> quoted() async {
    final invoice = await offered();
    wallet.scriptQuote(Ok(quoteOf(invoice)));
    return switch (await escrow.quoteBond(record, await seen())) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('no quote: $failure'),
    };
  }

  Future<TradePaymentRecord?> recorded(InvoiceStep step) async =>
      switch (await payments.paymentOf(record, step)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  Future<TradeTerms<TakenSide>> terms() async =>
      switch (await app.reader.open(record)) {
        TradeOpened(trade: OpenTrade(terms: final TradeTerms<TakenSide> terms)) =>
          terms,
        _ => throw StateError('not opened'),
      };
}

Matcher _refused(Matcher failure) =>
    isA<Err<P2pWalletPayment, BondPayRefusal>>().having(
      (e) => e.failure,
      'failure',
      failure,
    );

void main() {
  test(
    'the escrow ceiling: the trade\'s sats with the price tolerance, plus the announced taker fee and a sat, rounded down',
    () async {
      final seller = await _Seller.at();
      final terms = await seller.terms();
      final invoice = await seller.offered();
      // Written out from the scripted order: its sats at the book's price with 2 % and 1 sat, the announced 0.175 % on them, and 1 sat.
      expect(
        terms.escrowCeiling.value.toInt(),
        ((terms.expectedSatoshis * 1.02 + 1) * (1 + terms.takerFee) + 1)
            .floor(),
      );
      expect(terms.takerFee, 0.00175);
      expect(
        invoice.amount.value.toInt(),
        lessThanOrEqualTo(terms.escrowCeiling.value.toInt()),
      );
      // Above the bond's ceiling by far: the escrow is the whole trade.
      expect(
        terms.escrowCeiling.value.toInt(),
        greaterThan(terms.bondCeiling.value.toInt() * 10),
      );
    },
  );

  test(
    'at 6: the escrow invoice is offered, quoted on the tap, and paid on the confirmation, recorded as the escrow\'s',
    () async {
      final seller = await _Seller.at();
      final seen = await seller.seen();
      expect(seen.status, isA<WaitingForBoth>());
      final quote = await seller.quoted();
      expect(quote.invoice.bolt11, seller.app.coordinator.escrowInvoice?.text);
      expect(seller.wallet.quoted.single.bolt11, quote.invoice.bolt11);
      final hash = quote.invoice.paymentHash;
      seller.wallet.scriptPayment(
        Ok(P2pWalletPayment(id: 'swap-e', paymentHash: hash)),
      );
      final paid = await seller.escrow.payBond(seller.record, accepted: quote);
      expect(paid, isA<Ok<P2pWalletPayment, BondPayRefusal>>());
      expect(seller.wallet.paid, hasLength(1));
      expect(seller.wallet.paid.single.$1.bolt11, quote.invoice.bolt11);
      expect(identical(seller.wallet.paid.single.$2, quote), isTrue);
      final recorded = await seller.recorded(InvoiceStep.escrow);
      expect(recorded?.paymentHash, hash);
      expect(recorded?.walletPaymentId, 'swap-e');
      expect(await seller.recorded(InvoiceStep.bond), isNull);
    },
  );

  test('at 7: the escrow is offered as at 6', () async {
    final seller = await _Seller.at(status: 7);
    final seen = await seller.seen();
    expect(seen.status, isA<WaitingForEscrow>());
    final invoice = await seller.offered();
    expect(invoice.bolt11, seller.app.coordinator.escrowInvoice?.text);
  });

  test(
    'each step\'s use case offers its own invoice only: the bond\'s nothing at 6, the escrow\'s nothing at 3',
    () async {
      final seller = await _Seller.at();
      expect(
        await seller.bond.checkBond(seller.record, await seller.seen()),
        isA<Err<WalletPaymentOffered, BondPayRefusal>>().having(
          (e) => e.failure,
          'failure',
          isA<BondPayNotAtBondStep>(),
        ),
      );

      final app = await TradeHarness.start(orderType: 0);
      final record = TradeHarness.recordOf(await app.takeShown());
      final run = app.watchOf(record);
      await app.settle();
      await run.subscription.cancel();
      expect(run.lastStatus.seen.status, isA<WaitingForTakerBond>());
      final escrowAt3 = PayBondFromWalletUsecase(
        app.reader,
        app.limiter,
        TradePaymentRepositoryImpl(app.database),
        FakeP2pWalletPort(Ok(Sats.fromInt(500000))),
        app.locks,
        BondPaymentsInFlight(),
        step: InvoiceStep.escrow,
      );
      expect(
        await escrowAt3.checkBond(record, run.lastStatus.seen),
        isA<Err<WalletPaymentOffered, BondPayRefusal>>().having(
          (e) => e.failure,
          'failure',
          isA<BondPayNotAtBondStep>(),
        ),
      );
    },
  );

  test(
    'an escrow invoice for more than the trade\'s sats and its fee: never offered to the wallet',
    () async {
      final seller = await _Seller.at(
        before: (app) => app.coordinator.escrowInvoiceSats = 106900 + 500,
      );
      expect(
        await seller.escrow.checkBond(seller.record, await seller.seen()),
        isA<Err<WalletPaymentOffered, BondPayRefusal>>().having(
          (e) => e.failure,
          'failure',
          isA<BondPayNotOffered>().having(
            (r) => r.reason,
            'reason',
            WalletPaymentRefusal.checkFailed,
          ),
        ),
      );
      expect(seller.wallet.quoted, isEmpty);
    },
  );

  test(
    'the escrow locked by another wallet before the confirmation: the payment reads first, and nothing is paid nor recorded',
    () async {
      final seller = await _Seller.at();
      final quote = await seller.quoted();
      seller.app.coordinator.lockEscrow();
      final paid = await seller.escrow.payBond(seller.record, accepted: quote);
      expect(paid, _refused(isA<BondPayNotAtBondStep>()));
      expect(seller.wallet.paid, isEmpty);
      expect(await seller.recorded(InvoiceStep.escrow), isNull);
    },
  );

  test(
    'the escrow invoice replaced before the confirmation: the quoted one is not paid',
    () async {
      final seller = await _Seller.at();
      final quote = await seller.quoted();
      // The coordinator gives a new escrow invoice, another payment hash.
      seller.app.coordinator.escrowInvoice = null;
      final paid = await seller.escrow.payBond(seller.record, accepted: quote);
      expect(paid, isA<Err<P2pWalletPayment, BondPayRefusal>>());
      expect(seller.wallet.paid, isEmpty);
      expect(await seller.recorded(InvoiceStep.escrow), isNull);
    },
  );

  test(
    'a quote of another invoice than the escrow\'s is not paid: a new confirmation is needed',
    () async {
      final seller = await _Seller.at();
      final invoice = await seller.offered();
      final other = checkedBolt11InvoiceForTesting(
        bolt11: invoice.bolt11,
        amount: invoice.amount,
        network: invoice.network,
        paymentHash: 'cd${'0' * 62}',
        expiresAt: invoice.expiresAt,
        payableUntil: invoice.payableUntil,
        now: seller.app.now,
      );
      final paid = await seller.escrow.payBond(
        seller.record,
        accepted: seller.quoteOf(other ?? (throw StateError('no invoice'))),
      );
      expect(paid, _refused(isA<BondPayInvoiceChanged>()));
      expect(seller.wallet.paid, isEmpty);
    },
  );

  test(
    'a second confirmation of the same quote pays nothing more: the wallet takes a quote once',
    () async {
      final seller = await _Seller.at();
      final quote = await seller.quoted();
      final hash = quote.invoice.paymentHash;
      seller.wallet.scriptPayment(
        Ok(P2pWalletPayment(id: 'swap-e', paymentHash: hash)),
      );
      final results = await Future.wait([
        seller.escrow.payBond(seller.record, accepted: quote),
        seller.escrow.payBond(seller.record, accepted: quote),
      ]);
      expect(
        results.whereType<Ok<P2pWalletPayment, BondPayRefusal>>(),
        hasLength(1),
      );
      expect(
        (await seller.recorded(InvoiceStep.escrow))?.walletPaymentId,
        'swap-e',
      );
    },
  );

  test(
    'the escrow\'s payment running is the escrow\'s only: the bond\'s use case sees none',
    () async {
      final seller = await _Seller.at();
      final quote = await seller.quoted();
      seller.wallet.scriptPayment(const Err(P2pWalletServiceUnreachable()));
      final paying = seller.escrow.payBond(seller.record, accepted: quote);
      expect(seller.escrow.bondPaymentRunning(seller.record), isNotNull);
      expect(seller.bond.bondPaymentRunning(seller.record), isNull);
      await paying;
      expect(seller.escrow.bondPaymentRunning(seller.record), isNull);
    },
  );

  test(
    'followBond of the escrow follows the escrow\'s payment, never the bond\'s',
    () async {
      final seller = await _Seller.at();
      final quote = await seller.quoted();
      final hash = quote.invoice.paymentHash;
      expect(await seller.escrow.followBond(seller.record).toList(), [
        isA<BondPaymentNone>(),
      ]);
      final _ = await seller.payments.recordStart(
        seller.record,
        InvoiceStep.escrow,
        paymentHash: hash,
        at: seller.app.now,
      );
      expect(await seller.bond.followBond(seller.record).toList(), [
        isA<BondPaymentNone>(),
      ]);
      expect(seller.wallet.found, isEmpty);
      final payment = P2pWalletPayment(id: 'swap-e', paymentHash: hash);
      seller.wallet.setFound(
        hash,
        P2pWalletPaymentFound(
          payment: payment,
          progress: const P2pWalletPaymentPending(),
        ),
      );
      final first = await seller.escrow.followBond(seller.record).first;
      expect(
        first,
        isA<BondPaymentFollowed>().having(
          (f) => f.progress,
          'progress',
          isA<P2pWalletPaymentPending>(),
        ),
      );
      expect(seller.wallet.found, [hash]);
    },
  );

  test(
    'the records keep a payment of the bond and one of the escrow for the same trade',
    () async {
      final seller = await _Seller.at();
      final bondHash = 'ab${'0' * 62}';
      final escrowHash = 'cd${'0' * 62}';
      expect(
        await seller.payments.recordStart(
          seller.record,
          InvoiceStep.bond,
          paymentHash: bondHash,
          at: seller.app.now,
        ),
        isA<Ok<bool, P2pFailure>>().having((o) => o.value, 'value', isTrue),
      );
      expect(
        await seller.payments.recordStart(
          seller.record,
          InvoiceStep.escrow,
          paymentHash: escrowHash,
          at: seller.app.now,
        ),
        isA<Ok<bool, P2pFailure>>().having((o) => o.value, 'value', isTrue),
      );
      expect((await seller.recorded(InvoiceStep.bond))?.paymentHash, bondHash);
      expect(
        (await seller.recorded(InvoiceStep.escrow))?.paymentHash,
        escrowHash,
      );
    },
  );

  test(
    'the composition gives each cubit its own step\'s use case: the escrow\'s cubit quotes the escrow',
    () async {
      final seller = await _Seller.at();
      final locator = GetIt.asNewInstance();
      addTearDown(locator.reset);
      P2pLocator.registerTrades(
        locator,
        transport: () => throw StateError('no transport'),
        relays: () => throw StateError('no relay'),
        clock: DateTime.now,
      );
      // The trade's reads, records and locks of the harness, over its scripted coordinator: the use cases themselves are the composition's.
      locator
        ..allowReassignment = true
        ..registerSingleton<TradeReader>(seller.app.reader)
        ..registerSingleton<RobotRequestLimiter>(seller.app.limiter)
        ..registerSingleton<TradePaymentRepository>(seller.payments)
        ..registerSingleton<TradeTakeLocks>(seller.app.locks)
        ..registerSingleton<P2pWalletPort>(seller.wallet);
      expect(P2pLocator.paysBondFromWallet(locator), isTrue);
      final bond = locator<BondPaymentCubit>(param1: seller.record);
      final escrow = locator<EscrowPaymentCubit>(param1: seller.record);
      addTearDown(bond.close);
      addTearDown(escrow.close);
      expect(bond, isNot(isA<EscrowPaymentCubit>()));
      expect(bond.step, InvoiceStep.bond);
      expect(escrow.step, InvoiceStep.escrow);
      // The escrow's cubit quotes the escrow's invoice; the bond's offers nothing at 6.
      final invoice = await seller.offered();
      seller.wallet.scriptQuote(Ok(seller.quoteOf(invoice)));
      final seen = await seller.seen();
      escrow.start();
      for (var i = 0; i < 50 && escrow.state.step is! BondPayIdle; i++) {
        await seller.app.settle();
      }
      expect(escrow.state.step, isA<BondPayIdle>());
      await escrow.offerFor(seen);
      expect(escrow.state.offer, isA<Ok<void, BondPayRefusal>>());
      await escrow.ask(seen);
      expect(escrow.state.step, isA<BondPayConfirming>());
      expect(seller.wallet.quoted.last.bolt11, invoice.bolt11);
      await bond.offerFor(seen);
      expect(bond.state.offer, isA<Err<void, BondPayRefusal>>());
    },
  );
}
