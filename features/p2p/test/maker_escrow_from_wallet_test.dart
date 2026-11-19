import 'package:p2p/p2p.dart';
import 'package:p2p/src/data/trade_payment_repository_impl.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/trade_payment_repository.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/trade/escrow_contract.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_payment.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/domain/trade/wallet_rate_check.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/bond_payments_in_flight.dart';
import 'package:p2p/src/domain/usecases/trade/pay_bond_from_wallet_usecase.dart';
import 'package:p2p/testing.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';
import 'support/trade_harness.dart' show AppKilled;

/// A maker seller's escrow paid from this wallet (#187, design note `docs/design/phase-3-making-an-order.md` § 3.3, § 4.3, § 6 row 13), over the real records and use cases, the coordinator played by `ScriptedMakerCoordinator` (`api/views.py:397-412`: the escrow invoice and `escrow_satoshis` to the seller at 6 and 7; `api/logics.py:1205-1227`: a return to the book clears the escrow, the next take asks a new one).
///
/// Nothing here leaves the test: the wallet is `FakeP2pWalletPort`, every invoice the test decoder's.

T _some<T>(T? value) => value ?? (throw StateError('missing'));

/// EUR, the tests' order's currency (`MakeHarness.request`).
const _eur = 2;

/// Payments whose start is written, then the app is killed before the wallet is asked.
final class _KilledBeforeWallet implements TradePaymentRepository {
  final TradePaymentRepository inner;
  bool armed = true;

  _KilledBeforeWallet(this.inner);

  @override
  Future<Result<TradePaymentRecord?, P2pFailure>> paymentOf(
    TradeRecord trade,
    InvoiceStep step, {
    int take = 0,
  }) => inner.paymentOf(trade, step, take: take);

  @override
  Future<Result<List<TradePaymentRecord>, P2pFailure>> paymentsOfTrade(
    TradeRecord trade,
  ) => inner.paymentsOfTrade(trade);

  @override
  Future<Result<bool, P2pFailure>> recordStart(
    TradeRecord trade,
    InvoiceStep step, {
    required String paymentHash,
    required DateTime at,
    int take = 0,
  }) async {
    final written = await inner.recordStart(
      trade,
      step,
      paymentHash: paymentHash,
      at: at,
      take: take,
    );
    if (armed) throw AppKilled();
    return written;
  }

  @override
  Future<Result<bool, P2pFailure>> recordWalletPayment(
    TradeRecord trade,
    InvoiceStep step, {
    required String paymentHash,
    required String walletPaymentId,
    int take = 0,
  }) => inner.recordWalletPayment(
    trade,
    step,
    paymentHash: paymentHash,
    walletPaymentId: walletPaymentId,
    take: take,
  );
}

/// The records as the database holds them, with [extra] rows besides: a payment hash the database would hold for another contract or trade.
final class _WithRows implements TradePaymentRepository {
  final TradePaymentRepository inner;
  final List<TradePaymentRecord> extra;

  _WithRows(this.inner, this.extra);

  @override
  Future<Result<TradePaymentRecord?, P2pFailure>> paymentOf(
    TradeRecord trade,
    InvoiceStep step, {
    int take = 0,
  }) => inner.paymentOf(trade, step, take: take);

  @override
  Future<Result<List<TradePaymentRecord>, P2pFailure>> paymentsOfTrade(
    TradeRecord trade,
  ) async => switch (await inner.paymentsOfTrade(trade)) {
    Ok(:final value) => Ok([...value, ...extra]),
    final Err<List<TradePaymentRecord>, P2pFailure> failed => failed,
  };

  @override
  Future<Result<bool, P2pFailure>> recordStart(
    TradeRecord trade,
    InvoiceStep step, {
    required String paymentHash,
    required DateTime at,
    int take = 0,
  }) => inner.recordStart(
    trade,
    step,
    paymentHash: paymentHash,
    at: at,
    take: take,
  );

  @override
  Future<Result<bool, P2pFailure>> recordWalletPayment(
    TradeRecord trade,
    InvoiceStep step, {
    required String paymentHash,
    required String walletPaymentId,
    int take = 0,
  }) => inner.recordWalletPayment(
    trade,
    step,
    paymentHash: paymentHash,
    walletPaymentId: walletPaymentId,
    take: take,
  );
}

/// A wallet whose records cannot be read for [unreadable] payment hashes: `findPayment` fails closed, as the port does.
final class _Unreadable implements P2pWalletPort {
  final FakeP2pWalletPort inner;
  final Set<String> unreadable = {};

  _Unreadable(this.inner);

  @override
  Future<Result<P2pWalletPaymentFound?, P2pWalletRefusal>> findPayment(
    String paymentHash,
  ) async {
    if (unreadable.contains(paymentHash)) {
      return const Err(P2pWalletUnavailable());
    }
    return inner.findPayment(paymentHash);
  }

  @override
  Future<P2pWalletBitcoinRate> bitcoinRate(
    RobosatsNetwork network,
    RobosatsCurrency currency,
  ) => inner.bitcoinRate(network, currency);

  @override
  Stream<Result<Sats, P2pWalletRefusal>> instantBalance(
    RobosatsNetwork network,
  ) => inner.instantBalance(network);

  @override
  Future<Result<P2pWalletInvoice, P2pWalletRefusal>> newLightningInvoice(
    RobosatsNetwork network,
    Sats amount, {
    required String payout,
  }) => inner.newLightningInvoice(network, amount, payout: payout);

  @override
  Future<Result<P2pWalletAddress, P2pWalletRefusal>> newReceiveAddress(
    RobosatsNetwork network,
  ) => inner.newReceiveAddress(network);

  @override
  Future<Result<P2pWalletPayment, P2pWalletRefusal>> payInvoice(
    CheckedBolt11Invoice invoice, {
    required P2pWalletQuote accepted,
  }) => inner.payInvoice(invoice, accepted: accepted);

  @override
  Future<Result<P2pWalletQuote, P2pWalletRefusal>> quote(
    CheckedBolt11Invoice invoice,
  ) => inner.quote(invoice);

  @override
  Stream<Result<P2pWalletPaymentProgress, P2pWalletRefusal>> watchPayment(
    P2pWalletPayment payment,
  ) => inner.watchPayment(payment);
}

/// A sell order made here, taken, at its escrow (6), and the escrow's instance of the wallet's payment over the run's records.
final class _Seller {
  final MakeHarness harness;
  final TradeRecord record;
  final FakeP2pWalletPort fake;
  final _Unreadable wallet;
  final TradePaymentRepositoryImpl stored;
  final PayBondFromWalletUsecase escrow;

  _Seller(
    this.harness,
    this.record,
    this.fake,
    this.wallet,
    this.stored,
    this.escrow,
  );

  /// 100 EUR at +2 % (`MakeHarness.request`), made at the coordinator's price of 50,000 EUR/BTC and taken at [takenAt] (the same by default) by robot 5, a range of [range] taken for [amount] if given; the wallet's price [rate].
  static Future<_Seller> start({
    double takenAt = 50000,
    P2pWalletBitcoinRate? rate,
    (double, double)? range,
    double? amount,
    TradePaymentRepository Function(TradePaymentRepository stored)? payments,
  }) async {
    final harness = await MakeHarness.start();
    harness.coordinator.prices[_eur] = 50000;
    final record = switch (await harness.makeOrder(
      MakeHarness.request(sell: true, range: range),
    )) {
      Ok(value: final MakeStarted started) => started.record,
      final other => throw StateError('not made: $other'),
    };
    harness.coordinator
      ..lockMakerBond(record.orderId)
      ..prices[_eur] = takenAt
      ..take(record.orderId, harness.robot(5), amount: amount);
    final fake = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
      ..rate = rate ?? P2pWalletRateRead(50000);
    final wallet = _Unreadable(fake);
    final stored = TradePaymentRepositoryImpl(harness.database);
    return _Seller(
      harness,
      record,
      fake,
      wallet,
      stored,
      payOf(harness, wallet, payments?.call(stored) ?? stored),
    );
  }

  static PayBondFromWalletUsecase payOf(
    MakeHarness harness,
    P2pWalletPort wallet,
    TradePaymentRepository payments, {
    InvoiceStep step = InvoiceStep.escrow,
  }) => PayBondFromWalletUsecase(
    harness.reader,
    harness.limiter,
    payments,
    wallet,
    harness.locks,
    BondPaymentsInFlight(),
    step: step,
  );

  ScriptedMadeOrder get order => harness.coordinator.order(record.orderId);

  /// The status the watch shows now.
  Future<TradeSeen> seen() async {
    final run = harness.watchOf(record);
    await harness.settle();
    await run.subscription.cancel();
    return run.lastStatus.seen;
  }

  /// The order goes back to the book and is taken again, a minute later, by robot [taker]: a new contract, its own escrow.
  Future<void> takenAgain({int taker = 4}) async {
    harness.coordinator.backToBook(record.orderId);
    await harness.elapse(const Duration(minutes: 1));
    harness.coordinator.take(record.orderId, harness.robot(taker));
  }

  /// A coordinator that only pretends a next contract: the same taker, the deadline one second later, a fresh escrow, no return to the book.
  Future<void> pretendedAgain() async {
    await harness.elapse(const Duration(seconds: 1));
    final later = harness.now.add(Duration(seconds: order.escrowSeconds));
    order
      ..deadline = later
      ..expiresAt = later
      ..escrow = null
      ..status = 6;
  }

  /// The invoice the status shown holds, as the wallet's port takes it.
  static CheckedBolt11Invoice invoiceOf(MakeHarness harness, TradeSeen seen) {
    final invoice = seen.status.invoice;
    if (invoice is! CheckedInvoice) throw StateError('no checked invoice');
    return _some(
      checkedBolt11InvoiceForTesting(
        bolt11: invoice.bolt11,
        amount: invoice.amount,
        network: harness.network,
        paymentHash: invoice.paymentHash,
        expiresAt: invoice.facts.expiresAt,
        now: harness.now,
      ),
    );
  }

  /// A quote of [invoice], as the wallet would give it.
  P2pWalletQuote quoteOf(CheckedBolt11Invoice invoice) => P2pWalletQuote(
    invoice: invoice,
    payin: Sats(invoice.amount.value + BigInt.from(500)),
    networkFee: Sats.fromInt(27),
    balance: Sats.fromInt(5000000),
    quotedAt: harness.now,
  );

  /// The quote of the escrow shown, after the tap of « Pay with this wallet ».
  Future<P2pWalletQuote> quoted([TradeSeen? at]) async {
    final shown = at ?? await seen();
    final offered = switch (await escrow.checkBond(record, shown)) {
      Ok(:final value) => value.walletInvoice,
      Err(:final failure) => throw StateError('not offered: $failure'),
    };
    fake.scriptQuote(Ok(quoteOf(offered)));
    return switch (await escrow.quoteBond(record, shown)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('no quote: $failure'),
    };
  }

  /// What the confirmation of [quote] says of its contract.
  Future<EscrowContract> contractOf(P2pWalletQuote quote) async =>
      switch (await escrow.escrowContractOf(record, quote)) {
        Ok(value: final contract?) => contract,
        final other => throw StateError('no contract: $other'),
      };

  /// What the confirmation of [quote] compares.
  Future<WalletRateCheck?> rateOf(P2pWalletQuote quote) async =>
      switch (await escrow.rateOfBond(record, quote)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  /// Quotes, confirms and pays the escrow shown, the wallet answering with the payment [id]; then the wallet's records show it at [progress].
  Future<String> pay(
    String id, {
    P2pWalletPaymentProgress progress = const P2pWalletPaymentPending(),
  }) async {
    final quote = await quoted();
    final contract = await contractOf(quote);
    final hash = quote.invoice.paymentHash;
    final payment = P2pWalletPayment(id: id, paymentHash: hash);
    fake.scriptPayment(Ok(payment));
    final paid = await escrow.payBond(
      record,
      accepted: quote,
      contract: contract,
    );
    if (paid is! Ok<P2pWalletPayment, BondPayRefusal>) {
      throw StateError('not paid: $paid');
    }
    found(payment, progress);
    return hash;
  }

  /// The wallet's records show [payment] at [progress].
  void found(P2pWalletPayment payment, P2pWalletPaymentProgress progress) {
    fake
      ..setFound(
        payment.paymentHash,
        P2pWalletPaymentFound(payment: payment, progress: progress),
      )
      ..setProgress(payment, Ok(progress));
  }

  /// Every payment recorded for the trade.
  Future<List<TradePaymentRecord>> rows() async =>
      switch (await stored.paymentsOfTrade(record)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  /// The refusal of the check of the escrow shown.
  Future<BondPayRefusal> refusedAt(TradeSeen shown) async =>
      switch (await escrow.checkBond(record, shown)) {
        Err(:final failure) => failure,
        Ok() => throw StateError('offered'),
      };
}

void main() {
  group('a maker seller\'s escrow at 6, contract 0 (#187)', () {
    test(
      'offered with no ceiling, compared with the wallet\'s price, paid once under its contract after a confirmation that states it, recorded before the wallet is asked',
      () async {
        final seller = await _Seller.start();
        final shown = await seller.seen();
        expect(shown.stored, isTrue);
        expect(shown.status, isA<WaitingForBoth>());
        expect(shown.status.warnings, isEmpty);
        final offered = switch (await seller.escrow.checkBond(
          seller.record,
          shown,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        // `Logics.escrow_amount`: round(196,078 + 196,078 × 0.00025) = 196,127 (`api/logics.py:733-749`); no ceiling, the invoice itself accepted.
        expect(offered.walletInvoice.amount, Sats.fromInt(196127));
        expect(offered.accepted, Sats.fromInt(196127));
        expect(offered.take, 0);
        final quote = await seller.quoted(shown);
        final rate = await seller.rateOf(quote);
        // 100 EUR at the wallet's 50,000 EUR/BTC with +2 %: 196,078.43… sats; the escrow +0.025 %, the maker fee.
        expect(rate, isA<WalletRateAtWallet>());
        if (rate is! WalletRateAtWallet) return;
        expect(rate.expected, Sats.fromInt(196078));
        expect(rate.gapHundredths, BigInt.from(3));
        expect(rate.warns, isFalse);
        expect(seller.fake.ratesAsked.single.$2.code, 'EUR');
        final contract = await seller.contractOf(quote);
        expect(contract.take, 0);
        expect(contract.isNew, isFalse);
        expect(contract.earlier, isEmpty);
        final hash = quote.invoice.paymentHash;
        seller.fake.scriptPayment(
          Ok(P2pWalletPayment(id: 'swap-e0', paymentHash: hash)),
        );
        final paid = await seller.escrow.payBond(
          seller.record,
          accepted: quote,
          contract: contract,
        );
        expect(paid, isA<Ok<P2pWalletPayment, BondPayRefusal>>());
        expect(seller.fake.paid.single.$1.paymentHash, hash);
        final rows = await seller.rows();
        expect(rows.single.step, InvoiceStep.escrow);
        expect(rows.single.take, 0);
        expect(rows.single.paymentHash, hash);
        expect(rows.single.walletPaymentId, 'swap-e0');
      },
    );

    test(
      'without the confirmation\'s contract, or with another one: refused, nothing paid nor recorded',
      () async {
        final seller = await _Seller.start();
        final quote = await seller.quoted();
        seller.fake.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'never',
              paymentHash: quote.invoice.paymentHash,
            ),
          ),
        );
        for (final contract in [
          null,
          EscrowContract(take: 1, earlier: const []),
        ]) {
          expect(
            await seller.escrow.payBond(
              seller.record,
              accepted: quote,
              contract: contract,
            ),
            isA<Err<P2pWalletPayment, BondPayRefusal>>().having(
              (e) => e.failure,
              'failure',
              isA<BondPayContractNotConfirmed>(),
            ),
          );
        }
        expect(seller.fake.paid, isEmpty);
        expect(await seller.rows(), isEmpty);
      },
    );

    test(
      'the owner\'s rule: an escrow more than 10 % above the contract\'s amount at the wallet\'s price warns with both amounts, and is still paid on the confirmation',
      () async {
        // Taken at the coordinator's 40,000 EUR/BTC: 245,098 sats, an escrow of 245,159; the wallet's 50,000 expects 196,078.
        final seller = await _Seller.start(takenAt: 40000);
        final quote = await seller.quoted();
        final rate = await seller.rateOf(quote);
        expect(rate, isA<WalletRateAtWallet>());
        if (rate is! WalletRateAtWallet) return;
        expect(rate.warns, isTrue);
        expect(rate.asked, Sats.fromInt(245159));
        expect(rate.expected, Sats.fromInt(196078));
        final contract = await seller.contractOf(quote);
        seller.fake.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-red',
              paymentHash: quote.invoice.paymentHash,
            ),
          ),
        );
        expect(
          await seller.escrow.payBond(
            seller.record,
            accepted: quote,
            contract: contract,
          ),
          isA<Ok<P2pWalletPayment, BondPayRefusal>>(),
        );
      },
    );

    test(
      'a currency the wallet does not price, a price not read: nothing compared, the creation\'s price never cited, still payable',
      () async {
        for (final rate in [
          const P2pWalletRateNotPriced(),
          const P2pWalletRateUnavailable(),
        ]) {
          final seller = await _Seller.start(rate: rate);
          final quote = await seller.quoted();
          final check = await seller.rateOf(quote);
          expect(
            check,
            rate is P2pWalletRateNotPriced
                ? isA<WalletRateNotPriced>()
                : isA<WalletRateUnverified>(),
          );
          expect(check, isNot(isA<WalletRateCompared>()));
          expect(await seller.contractOf(quote), isA<EscrowContract>());
        }
      },
    );

    test(
      'a range: compared with the amount the take chose, kept in the trail',
      () async {
        final seller = await _Seller.start(range: (100, 600), amount: 300);
        final shown = await seller.seen();
        expect(shown.status.trail.takenAmount, 300);
        final quote = await seller.quoted(shown);
        final rate = await seller.rateOf(quote);
        if (rate is! WalletRateAtWallet) fail('$rate');
        // 300 EUR at 51,000 EUR/BTC: 588,235.29… sats.
        expect(rate.expected, Sats.fromInt(588235));
        expect(rate.warns, isFalse);
      },
    );

    test(
      'the bond\'s instance never pays the escrow, nor the escrow\'s a quote of another invoice',
      () async {
        final seller = await _Seller.start();
        final shown = await seller.seen();
        final bond = _Seller.payOf(
          seller.harness,
          seller.wallet,
          seller.stored,
          step: InvoiceStep.bond,
        );
        expect(
          await bond.checkBond(seller.record, shown),
          isA<Err<WalletPaymentOffered, BondPayRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<BondPayNotAtBondStep>(),
          ),
        );
        final quote = await seller.quoted(shown);
        expect(
          await bond.escrowContractOf(seller.record, quote),
          isA<Ok<EscrowContract?, BondPayRefusal>>().having(
            (r) => r.value,
            'value',
            isNull,
          ),
        );
        // The bond's own quote, made at 0, is not the escrow the trail pins.
        final other = seller.quoteOf(
          _some(
            checkedBolt11InvoiceForTesting(
              bolt11: seller.order.bond?.text ?? fail('no bond'),
              amount: seller.order.bond?.facts.amount ?? fail('no bond'),
              network: seller.harness.network,
              paymentHash: seller.order.bond?.facts.paymentHash ?? fail(''),
              expiresAt: seller.harness.now.add(const Duration(hours: 1)),
              now: seller.harness.now,
            ),
          ),
        );
        expect(
          await seller.escrow.rateOfBond(seller.record, other),
          isA<Err<WalletRateCheck?, BondPayRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<BondPayInvoiceChanged>(),
          ),
        );
        expect(
          await seller.escrow.escrowContractOf(seller.record, other),
          isA<Err<EscrowContract?, BondPayRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<BondPayInvoiceChanged>(),
          ),
        );
      },
    );

    test('two taps of the confirmation pay once, under one record', () async {
      final seller = await _Seller.start();
      final quote = await seller.quoted();
      final contract = await seller.contractOf(quote);
      final hash = quote.invoice.paymentHash;
      seller.fake.scriptPayment(
        Ok(P2pWalletPayment(id: 'swap-e0', paymentHash: hash)),
      );
      final both = await Future.wait([
        seller.escrow.payBond(
          seller.record,
          accepted: quote,
          contract: contract,
        ),
        seller.escrow.payBond(
          seller.record,
          accepted: quote,
          contract: contract,
        ),
      ]);
      expect(
        both.whereType<Ok<P2pWalletPayment, BondPayRefusal>>(),
        hasLength(1),
      );
      expect((await seller.rows()).single.walletPaymentId, 'swap-e0');
    });
  });

  group('a new contract\'s escrow: one escrow held at a time (#187)', () {
    test(
      'refused while the escrow of contract 0 is held, paid under contract 1 once its refund is pending, each escrow under its own record',
      () async {
        final seller = await _Seller.start();
        final first = await seller.pay('swap-e0');
        await seller.takenAgain();
        final shown = await seller.seen();
        expect(shown.stored, isTrue);
        expect(shown.status.trail.take, 1);
        expect(shown.status.warnings, isEmpty);
        final refusal = await seller.refusedAt(shown);
        expect(refusal, isA<BondPayEarlierEscrowHeld>());
        if (refusal is! BondPayEarlierEscrowHeld) return;
        expect(refusal.contract.take, 1);
        expect(refusal.contract.isNew, isTrue);
        expect(refusal.contract.earlier.single, isA<EarlierEscrowHeld>());
        expect(refusal.contract.earlier.single.take, 0);
        expect(
          await seller.escrow.quoteBond(seller.record, shown),
          isA<Err<P2pWalletQuote, BondPayRefusal>>(),
        );
        expect(seller.fake.quoted, hasLength(1));
        // The coordinator returned the escrow at the return to the book (`api/logics.py:445-458`); the swap service reports its refund pending.
        seller.found(
          P2pWalletPayment(id: 'swap-e0', paymentHash: first),
          const P2pWalletPaymentRefundPending(),
        );
        final quote = await seller.quoted(shown);
        expect(quote.invoice.paymentHash, isNot(first));
        final contract = await seller.contractOf(quote);
        expect(contract.take, 1);
        expect(contract.isNew, isTrue);
        expect(contract.earlier.single, isA<EarlierEscrowReleased>());
        final hash = quote.invoice.paymentHash;
        seller.fake.scriptPayment(
          Ok(P2pWalletPayment(id: 'swap-e1', paymentHash: hash)),
        );
        expect(
          await seller.escrow.payBond(
            seller.record,
            accepted: quote,
            contract: contract,
          ),
          isA<Ok<P2pWalletPayment, BondPayRefusal>>(),
        );
        final rows = await seller.rows();
        expect(
          [for (final row in rows) (row.take, row.walletPaymentId)],
          [(0, 'swap-e0'), (1, 'swap-e1')],
        );
        // The confirmation of contract 0, kept, pays nothing now.
        expect(
          await seller.escrow.payBond(
            seller.record,
            accepted: quote,
            contract: EscrowContract(take: 0, earlier: const []),
          ),
          isA<Err<P2pWalletPayment, BondPayRefusal>>(),
        );
      },
    );

    test(
      'released only by a refund pending or done, or a failure or an expiry with nothing sent; every other state, an unreadable one, and no wallet id count as held',
      () async {
        const released = <P2pWalletPaymentProgress>[
          P2pWalletPaymentRefundPending(),
          P2pWalletPaymentRefunded(),
          P2pWalletPaymentFailed(P2pWalletFunds.notSent),
          P2pWalletPaymentExpired(P2pWalletFunds.notSent),
        ];
        const held = <P2pWalletPaymentProgress>[
          P2pWalletPaymentPreparing(),
          P2pWalletPaymentSigned(),
          P2pWalletPaymentBroadcastUnknown(),
          P2pWalletPaymentSent(),
          P2pWalletPaymentPending(),
          P2pWalletPaymentUnderReview(),
          P2pWalletPaymentPaid(),
          P2pWalletPaymentFailed(P2pWalletFunds.maybeSent),
          P2pWalletPaymentFailed(P2pWalletFunds.sent),
          P2pWalletPaymentExpired(P2pWalletFunds.maybeSent),
          P2pWalletPaymentExpired(P2pWalletFunds.sent),
        ];
        for (final progress in released) {
          expect(escrowNoLongerHeld(progress), isTrue, reason: '$progress');
        }
        for (final progress in held) {
          expect(escrowNoLongerHeld(progress), isFalse, reason: '$progress');
        }
        final row = TradePaymentRecord(
          step: InvoiceStep.escrow,
          paymentHash: 'a' * 64,
          startedAt: DateTime.utc(2026, 11, 19),
          walletPaymentId: 'swap-e0',
        );
        const payment = P2pWalletPayment(id: 'swap-e0', paymentHash: 'h');
        P2pWalletPaymentFound at(P2pWalletPaymentProgress progress) =>
            P2pWalletPaymentFound(payment: payment, progress: progress);
        expect(
          EarlierEscrow.of(row, Ok(at(const P2pWalletPaymentRefunded()))).held,
          isFalse,
        );
        expect(
          EarlierEscrow.of(row, Ok(at(const P2pWalletPaymentPaid()))).held,
          isTrue,
        );
        expect(
          EarlierEscrow.of(row, const Ok(null)),
          isA<EarlierEscrowUnknown>(),
        );
        expect(
          EarlierEscrow.of(row, const Err(P2pWalletUnavailable())),
          isA<EarlierEscrowUnknown>(),
        );
        // No wallet id: held, whatever the wallet would say.
        final noId = TradePaymentRecord(
          step: InvoiceStep.escrow,
          paymentHash: 'a' * 64,
          startedAt: DateTime.utc(2026, 11, 19),
        );
        expect(
          EarlierEscrow.of(noId, Ok(at(const P2pWalletPaymentRefunded()))),
          isA<EarlierEscrowUnknown>(),
        );
        // And through the use case: each held state of contract 0 refuses contract 1, each released one lets it be quoted.
        final seller = await _Seller.start();
        final first = await seller.pay('swap-e0');
        await seller.takenAgain();
        final shown = await seller.seen();
        final payment0 = P2pWalletPayment(id: 'swap-e0', paymentHash: first);
        for (final progress in held) {
          seller.found(payment0, progress);
          expect(
            await seller.refusedAt(shown),
            isA<BondPayEarlierEscrowHeld>(),
            reason: '$progress',
          );
        }
        seller.wallet.unreadable.add(first);
        seller.found(payment0, const P2pWalletPaymentRefunded());
        expect(await seller.refusedAt(shown), isA<BondPayEarlierEscrowHeld>());
        seller.wallet.unreadable.clear();
        for (final progress in released) {
          seller.found(payment0, progress);
          expect(
            await seller.escrow.checkBond(seller.record, shown),
            isA<Ok<WalletPaymentOffered, BondPayRefusal>>().having(
              (o) => o.value.take,
              'take',
              1,
            ),
            reason: '$progress',
          );
        }
        expect(seller.fake.paid, hasLength(1));
      },
    );

    test(
      'a coordinator that pretends 40 next contracts in 40 reads, each with a fresh escrow, a deadline later by one second, the same taker: never more than one escrow held through this wallet',
      () async {
        final seller = await _Seller.start();
        final first = await seller.pay('swap-e0');
        for (var take = 1; take <= 40; take++) {
          await seller.pretendedAgain();
          final shown = await seller.seen();
          expect(shown.stored, isTrue, reason: '$take');
          expect(shown.status.trail.take, take);
          expect(shown.status.warnings, isEmpty, reason: '$take');
          expect(
            await seller.refusedAt(shown),
            isA<BondPayEarlierEscrowHeld>(),
            reason: '$take',
          );
        }
        expect(seller.fake.quoted, hasLength(1));
        expect(seller.fake.paid, hasLength(1));
        // Contract 0's escrow released: contract 40's is paid, and from then on the next one is refused again.
        seller.found(
          P2pWalletPayment(id: 'swap-e0', paymentHash: first),
          const P2pWalletPaymentRefunded(),
        );
        await seller.pay('swap-e40');
        await seller.pretendedAgain();
        final next = await seller.seen();
        expect(next.status.trail.take, 41);
        final refusal = await seller.refusedAt(next);
        if (refusal is! BondPayEarlierEscrowHeld) fail('$refusal');
        expect(
          [for (final e in refusal.contract.earlier) (e.take, e.held)],
          [(0, false), (40, true)],
        );
        expect(seller.fake.paid, hasLength(2));
        expect([for (final row in await seller.rows()) row.take], [0, 40]);
      },
    );

    test(
      'the app killed between the record and the wallet: the same escrow may be paid again, the next contract\'s only from another wallet (a record with no wallet id counts as held)',
      () async {
        late _KilledBeforeWallet killed;
        final seller = await _Seller.start(
          payments: (stored) => killed = _KilledBeforeWallet(stored),
        );
        final quote = await seller.quoted();
        final contract = await seller.contractOf(quote);
        await expectLater(
          seller.escrow.payBond(
            seller.record,
            accepted: quote,
            contract: contract,
          ),
          throwsA(isA<AppKilled>()),
        );
        expect(seller.fake.paid, isEmpty);
        expect((await seller.rows()).single.walletPaymentId, isNull);
        killed.armed = false;
        // The app started again over the same records: the same escrow is still payable, the wallet asked once.
        final again = _Seller.payOf(
          seller.harness.restart(),
          seller.wallet,
          seller.stored,
        );
        final shown = await seller.seen();
        expect(
          await again.checkBond(seller.record, shown),
          isA<Ok<WalletPaymentOffered, BondPayRefusal>>(),
        );
        // Taken again before anything was paid: the record without a wallet id holds contract 1 back.
        await seller.takenAgain();
        final next = await seller.seen();
        expect(next.status.trail.take, 1);
        final refusal = await seller.refusedAt(next);
        if (refusal is! BondPayEarlierEscrowHeld) fail('$refusal');
        expect(refusal.contract.earlier.single, isA<EarlierEscrowUnknown>());
        expect(seller.fake.found, isEmpty);
      },
    );

    test(
      'a payment hash the trade already holds is refused before the wallet is asked, whatever its contract or step',
      () async {
        final rows = <TradePaymentRecord>[];
        final seller = await _Seller.start(
          payments: (stored) => _WithRows(stored, rows),
        );
        final shown = await seller.seen();
        final invoice = _Seller.invoiceOf(seller.harness, shown);
        for (final (step, take) in [
          (InvoiceStep.escrow, 3),
          (InvoiceStep.bond, 0),
        ]) {
          rows
            ..clear()
            ..add(
              TradePaymentRecord(
                step: step,
                paymentHash: invoice.paymentHash,
                startedAt: seller.harness.now,
                walletPaymentId: 'swap-x',
                take: take,
              ),
            );
          expect(
            await seller.refusedAt(shown),
            isA<BondPayEscrowSeenBefore>(),
            reason: '$step $take',
          );
        }
        expect(seller.fake.found, isEmpty);
        expect(seller.fake.quoted, isEmpty);
      },
    );

    test(
      'the payment re-reads every record under the lock: an earlier escrow found held between the confirmation and the payment stops it',
      () async {
        final seller = await _Seller.start();
        final first = await seller.pay('swap-e0');
        final payment0 = P2pWalletPayment(id: 'swap-e0', paymentHash: first);
        seller.found(payment0, const P2pWalletPaymentRefundPending());
        await seller.takenAgain();
        final quote = await seller.quoted();
        final contract = await seller.contractOf(quote);
        expect(contract.earlierHeld, isFalse);
        // The wallet's records now say the earlier escrow is under review (still held).
        seller.found(payment0, const P2pWalletPaymentUnderReview());
        seller.fake.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-e1',
              paymentHash: quote.invoice.paymentHash,
            ),
          ),
        );
        expect(
          await seller.escrow.payBond(
            seller.record,
            accepted: quote,
            contract: contract,
          ),
          isA<Err<P2pWalletPayment, BondPayRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<BondPayEarlierEscrowHeld>(),
          ),
        );
        expect(seller.fake.paid, hasLength(1));
        expect([for (final row in await seller.rows()) row.take], [0]);
      },
    );
  });

  group('following each escrow under its contract (#187)', () {
    test(
      'the current contract\'s escrow in the panel; every contract\'s, after the trail moved on and after the trade ended, after a restart too',
      () async {
        final seller = await _Seller.start();
        final first = await seller.pay('swap-e0');
        final payment0 = P2pWalletPayment(id: 'swap-e0', paymentHash: first);
        seller.found(payment0, const P2pWalletPaymentRefundPending());
        await seller.takenAgain();
        await seller.seen();
        // At contract 1, before its escrow is paid: the panel follows nothing (contract 0's refund is not this contract's payment).
        expect(
          await seller.escrow.followBond(seller.record).first,
          isA<BondPaymentNone>(),
        );
        final second = await seller.pay('swap-e1');
        expect(
          await seller.escrow.followBond(seller.record).first,
          isA<BondPaymentFollowed>().having(
            (f) => f.payment.paymentHash,
            'hash',
            second,
          ),
        );
        // Both bonds settled at 6, the trade ends (`api/logics.py:360-379`): the record is closed.
        seller.harness.coordinator.expire(seller.record.orderId);
        final ended = await seller.seen();
        expect(ended.status, isA<Expired>());
        final restarted = _Seller.payOf(
          seller.harness.restart(),
          seller.wallet,
          TradePaymentRepositoryImpl(seller.harness.database),
        );
        final watches = <EscrowPaymentsWatch>[];
        final follow = restarted
            .followEscrows(seller.record)
            .listen(watches.add);
        await seller.harness.settle();
        List<(int, String)> said() => switch (watches.last) {
          EscrowPaymentsFollowed(:final escrows) => [
            for (final escrow in escrows)
              (escrow.take, escrow.watch.toString()),
          ],
          final other => throw StateError('$other'),
        };
        expect(said(), [
          (0, 'BondPaymentFollowed(P2pWalletPaymentRefundPending)'),
          (1, 'BondPaymentFollowed(P2pWalletPaymentPending)'),
        ]);
        seller.found(payment0, const P2pWalletPaymentRefunded());
        await seller.harness.settle();
        expect(said().first, (
          0,
          'BondPaymentFollowed(P2pWalletPaymentRefunded)',
        ));
        await follow.cancel();
        // The bond's instance follows no escrow.
        final bond = _Seller.payOf(
          seller.harness,
          seller.wallet,
          seller.stored,
          step: InvoiceStep.bond,
        );
        expect(
          await bond.followEscrows(seller.record).first,
          isA<EscrowPaymentsFollowed>().having(
            (f) => f.escrows,
            'escrows',
            isEmpty,
          ),
        );
      },
    );
  });

  group('the records of the payments (#187)', () {
    test(
      'every payment of a trade, ordered by contract then step, the same after a restart over the same database',
      () async {
        final seller = await _Seller.start();
        final first = await seller.pay(
          'swap-e0',
          progress: const P2pWalletPaymentRefunded(),
        );
        await seller.takenAgain();
        final second = await seller.pay('swap-e1');
        final restarted = TradePaymentRepositoryImpl(seller.harness.database);
        final rows = switch (await restarted.paymentsOfTrade(seller.record)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(
          [for (final row in rows) (row.step, row.take, row.paymentHash)],
          [(InvoiceStep.escrow, 0, first), (InvoiceStep.escrow, 1, second)],
        );
        // A trade with nothing recorded: none.
        final other = await _Seller.start();
        expect(await other.rows(), isEmpty);
      },
    );
  });
}
