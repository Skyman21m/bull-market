import 'package:p2p/p2p.dart';
import 'package:p2p/src/data/trade_payment_repository_impl.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/trade_payment_repository.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
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
  Future<Result<bool, P2pFailure>> holdsPaymentHash(String paymentHash) =>
      inner.holdsPaymentHash(paymentHash);

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

/// Payments whose wallet id cannot be written because the app is killed right then: after the wallet answered, before its id is recorded.
final class _KilledAfterWallet implements TradePaymentRepository {
  final TradePaymentRepository inner;
  bool armed;

  _KilledAfterWallet(this.inner, {this.armed = true});

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
  Future<Result<bool, P2pFailure>> holdsPaymentHash(String paymentHash) =>
      inner.holdsPaymentHash(paymentHash);

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
  }) {
    if (armed) {
      armed = false;
      throw AppKilled();
    }
    return inner.recordWalletPayment(
      trade,
      step,
      paymentHash: paymentHash,
      walletPaymentId: walletPaymentId,
      take: take,
    );
  }
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
  Future<Result<bool, P2pFailure>> holdsPaymentHash(String paymentHash) =>
      inner.holdsPaymentHash(paymentHash);

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

  /// The payment hash of the maker bond paid from this wallet at 0, `null` when it was locked from another wallet.
  final String? bondHash;

  _Seller(
    this.harness,
    this.record,
    this.fake,
    this.wallet,
    this.stored,
    this.escrow,
    this.bondHash,
  );

  /// 100 EUR at +2 % (`MakeHarness.request`), made at the coordinator's price of 50,000 EUR/BTC, its maker bond paid from this wallet at 0 and held by the coordinator (the owner's path of APK 3; from another wallet unless [bondFromWallet]), taken at [takenAt] (the same by default) by robot 5, a range of [range] taken for [amount] if given; the wallet's price [rate]. With [harness], a further order of the same Garage Key on that run.
  static Future<_Seller> start({
    double takenAt = 50000,
    P2pWalletBitcoinRate? rate,
    (double, double)? range,
    double? amount,
    bool bondFromWallet = true,
    MakeHarness? harness,
    FakeP2pWalletPort? fake,
    TradePaymentRepository Function(TradePaymentRepository stored)? payments,
  }) async {
    final run = harness ?? await MakeHarness.start();
    run.coordinator.prices[_eur] = 50000;
    final record = switch (await run.makeOrder(
      MakeHarness.request(sell: true, range: range),
    )) {
      Ok(value: final MakeStarted started) => started.record,
      final other => throw StateError('not made: $other'),
    };
    final port =
        fake ??
        (FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
          ..rate = rate ?? P2pWalletRateRead(50000));
    final wallet = _Unreadable(port);
    final stored = TradePaymentRepositoryImpl(run.database);
    final bondHash = bondFromWallet
        ? await _payBond(run, record, port, wallet, stored)
        : null;
    run.coordinator
      ..lockMakerBond(record.orderId)
      ..prices[_eur] = takenAt
      ..take(record.orderId, run.robot(5), amount: amount);
    return _Seller(
      run,
      record,
      port,
      wallet,
      stored,
      payOf(run, wallet, payments?.call(stored) ?? stored),
      bondHash,
    );
  }

  /// The maker bond of [record] at 0 paid from this wallet through the bond's instance, then held by the coordinator for the order's life (`P2pWalletPaymentPending` in the wallet's records); its payment hash.
  static Future<String> _payBond(
    MakeHarness harness,
    TradeRecord record,
    FakeP2pWalletPort fake,
    P2pWalletPort wallet,
    TradePaymentRepository stored,
  ) async {
    final run = harness.watchOf(record);
    await harness.settle();
    final seen = run.lastStatus.seen;
    await run.subscription.cancel();
    final bond = payOf(harness, wallet, stored, step: InvoiceStep.bond);
    final offered = switch (await bond.checkBond(record, seen)) {
      Ok(:final value) => value.walletInvoice,
      Err(:final failure) => throw StateError('bond not offered: $failure'),
    };
    final quote = P2pWalletQuote(
      invoice: offered,
      payin: Sats(offered.amount.value + BigInt.from(120)),
      networkFee: Sats.fromInt(27),
      balance: Sats.fromInt(5000000),
      quotedAt: harness.now,
    );
    final payment = P2pWalletPayment(
      id: 'swap-bond-${record.orderId}',
      paymentHash: offered.paymentHash,
    );
    fake
      ..scriptQuote(Ok(quote))
      ..scriptPayment(Ok(payment));
    if (await bond.quoteBond(record, seen) is! Ok) throw StateError('no quote');
    if (await bond.payBond(record, accepted: quote) is! Ok) {
      throw StateError('bond not paid');
    }
    fake
      ..setFound(
        payment.paymentHash,
        P2pWalletPaymentFound(
          payment: payment,
          progress: const P2pWalletPaymentPending(),
        ),
      )
      ..setProgress(payment, const Ok(P2pWalletPaymentPending()));
    return payment.paymentHash;
  }

  /// The escrows quoted by the wallet, the bond's quote left out.
  List<CheckedBolt11Invoice> get escrowQuotes => [
    for (final invoice in fake.quoted)
      if (invoice.paymentHash != bondHash) invoice,
  ];

  /// The escrows the wallet was asked to pay, the bond's payment left out.
  List<(CheckedBolt11Invoice, P2pWalletQuote)> get escrowPayments => [
    for (final paid in fake.paid)
      if (paid.$1.paymentHash != bondHash) paid,
  ];

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
  Future<List<TradePaymentRecord>> allRows() async =>
      switch (await stored.paymentsOfTrade(record)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  /// Every escrow recorded for the trade.
  Future<List<TradePaymentRecord>> rows() async => [
    for (final row in await allRows())
      if (row.step == InvoiceStep.escrow) row,
  ];

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
        expect(seller.escrowPayments.single.$1.paymentHash, hash);
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
          EscrowContract(take: 1, escrow: quote.total, earlier: const []),
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
        expect(seller.escrowPayments, isEmpty);
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

  group(
    'earlier escrows not back: an alert with their sats, never a lock (#187, the owner\'s decision of 2026-11-19)',
    () {
      test(
        'contract 1 while contract 0\'s escrow is held: offered, its confirmation gives contract 0\'s sats and what will be out, and it is paid, each escrow under its own record',
        () async {
          final seller = await _Seller.start();
          final first = await seller.pay('swap-e0');
          final firstSats = seller.escrowPayments.single.$2.total;
          await seller.takenAgain();
          final shown = await seller.seen();
          expect(shown.stored, isTrue);
          expect(shown.status.trail.take, 1);
          expect(shown.status.warnings, isEmpty);
          expect(
            await seller.escrow.checkBond(seller.record, shown),
            isA<Ok<WalletPaymentOffered, BondPayRefusal>>(),
          );
          final quote = await seller.quoted(shown);
          expect(quote.invoice.paymentHash, isNot(first));
          final contract = await seller.contractOf(quote);
          expect(contract.take, 1);
          expect(contract.isNew, isTrue);
          expect(contract.alerts, isTrue);
          final earlier = contract.earlier.single;
          expect(earlier.take, 0);
          expect(earlier.state, EarlierEscrowCase.notBack);
          expect(earlier.sats, firstSats);
          expect(contract.notBackSats, firstSats);
          expect(contract.notBackUnknown, 0);
          expect(contract.escrow, quote.total);
          expect(contract.outIfPaid, Sats(firstSats.value + quote.total.value));
          expect(contract.kept, isEmpty);
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
          expect(
            [
              for (final row in await seller.rows())
                (row.take, row.walletPaymentId),
            ],
            [(0, 'swap-e0'), (1, 'swap-e1')],
          );
          // The confirmation of contract 0, kept, pays nothing now.
          expect(
            await seller.escrow.payBond(
              seller.record,
              accepted: quote,
              contract: EscrowContract(
                take: 0,
                escrow: quote.total,
                earlier: const [],
              ),
            ),
            isA<Err<P2pWalletPayment, BondPayRefusal>>().having(
              (e) => e.failure,
              'failure',
              isA<BondPayContractNotConfirmed>(),
            ),
          );
        },
      );

      test(
        'each state of the wallet\'s records in its case: back only for a refund done or nothing sent, kept for a payment settled, not back for everything else (a refund pending, a state that cannot be told included); none refuses',
        () async {
          const back = <P2pWalletPaymentProgress>[
            P2pWalletPaymentRefunded(),
            P2pWalletPaymentFailed(P2pWalletFunds.notSent),
            P2pWalletPaymentExpired(P2pWalletFunds.notSent),
          ];
          const notBack = <P2pWalletPaymentProgress>[
            P2pWalletPaymentRefundPending(),
            P2pWalletPaymentPreparing(),
            P2pWalletPaymentSigned(),
            P2pWalletPaymentBroadcastUnknown(),
            P2pWalletPaymentSent(),
            P2pWalletPaymentPending(),
            P2pWalletPaymentUnderReview(),
            P2pWalletPaymentFailed(P2pWalletFunds.maybeSent),
            P2pWalletPaymentFailed(P2pWalletFunds.sent),
            P2pWalletPaymentExpired(P2pWalletFunds.maybeSent),
            P2pWalletPaymentExpired(P2pWalletFunds.sent),
          ];
          for (final progress in back) {
            expect(
              earlierEscrowCaseOf(progress),
              EarlierEscrowCase.back,
              reason: '$progress',
            );
          }
          for (final progress in notBack) {
            expect(
              earlierEscrowCaseOf(progress),
              EarlierEscrowCase.notBack,
              reason: '$progress',
            );
          }
          expect(
            earlierEscrowCaseOf(const P2pWalletPaymentPaid()),
            EarlierEscrowCase.kept,
          );
          final row = TradePaymentRecord(
            step: InvoiceStep.escrow,
            paymentHash: 'a' * 64,
            startedAt: DateTime.utc(2026, 11, 19),
            walletPaymentId: 'swap-e0',
          );
          final noId = TradePaymentRecord(
            step: InvoiceStep.escrow,
            paymentHash: 'a' * 64,
            startedAt: DateTime.utc(2026, 11, 19),
          );
          const payment = P2pWalletPayment(id: 'swap-e0', paymentHash: 'h');
          P2pWalletPaymentFound at(P2pWalletPaymentProgress progress) =>
              P2pWalletPaymentFound(payment: payment, progress: progress);
          EarlierEscrowCase caseOf(
            TradePaymentRecord of,
            Result<P2pWalletPaymentFound?, P2pWalletRefusal> found,
          ) => EarlierEscrow.of(of, found).state;
          expect(
            caseOf(row, Ok(at(const P2pWalletPaymentRefunded()))),
            EarlierEscrowCase.back,
          );
          expect(
            caseOf(row, Ok(at(const P2pWalletPaymentPaid()))),
            EarlierEscrowCase.kept,
          );
          // A recorded wallet id the wallet does not know, or records it cannot read: not back, its state unknown.
          expect(caseOf(row, const Ok(null)), EarlierEscrowCase.notBack);
          expect(
            caseOf(row, const Err(P2pWalletUnavailable())),
            EarlierEscrowCase.notBack,
          );
          // No wallet id: the wallet's order, when it holds one, tells; when it holds none, nothing of this feature left the wallet.
          expect(
            caseOf(noId, Ok(at(const P2pWalletPaymentSent()))),
            EarlierEscrowCase.notBack,
          );
          expect(caseOf(noId, const Ok(null)), EarlierEscrowCase.back);
          expect(
            caseOf(noId, const Err(P2pWalletUnavailable())),
            EarlierEscrowCase.notBack,
          );
          // Through the use case: whatever contract 0 stands at, contract 1 is offered, in the case its state gives.
          final seller = await _Seller.start();
          final first = await seller.pay('swap-e0');
          await seller.takenAgain();
          final shown = await seller.seen();
          final quote = await seller.quoted(shown);
          final payment0 = P2pWalletPayment(id: 'swap-e0', paymentHash: first);
          for (final (progress, state) in [
            for (final progress in back) (progress, EarlierEscrowCase.back),
            for (final progress in notBack)
              (progress, EarlierEscrowCase.notBack),
            (const P2pWalletPaymentPaid(), EarlierEscrowCase.kept),
          ]) {
            seller.found(payment0, progress);
            expect(
              await seller.escrow.checkBond(seller.record, shown),
              isA<Ok<WalletPaymentOffered, BondPayRefusal>>(),
              reason: '$progress',
            );
            expect(
              (await seller.contractOf(quote)).earlier.single.state,
              state,
              reason: '$progress',
            );
          }
          seller.wallet.unreadable.add(first);
          seller.found(payment0, const P2pWalletPaymentRefunded());
          expect(
            (await seller.contractOf(quote)).earlier.single.state,
            EarlierEscrowCase.notBack,
          );
          expect(seller.escrowPayments, hasLength(1));
        },
      );

      test(
        'two real retakes, three escrows paid, the earlier ones not back (security review of #187, SECU1): the sums of each confirmation are right',
        () async {
          final seller = await _Seller.start();
          await seller.pay('swap-e0');
          final sats0 = seller.escrowPayments.last.$2.total;
          await seller.takenAgain();
          final quote1 = await seller.quoted();
          final contract1 = await seller.contractOf(quote1);
          expect(contract1.notBackSats, sats0);
          expect(contract1.outIfPaid, Sats(sats0.value + quote1.total.value));
          await seller.pay('swap-e1');
          final sats1 = seller.escrowPayments.last.$2.total;
          await seller.takenAgain(taker: 3);
          final quote2 = await seller.quoted();
          final contract2 = await seller.contractOf(quote2);
          expect(contract2.take, 2);
          expect([for (final e in contract2.earlier) e.take], [0, 1]);
          expect(contract2.notBackSats, Sats(sats0.value + sats1.value));
          expect(
            contract2.outIfPaid,
            Sats(sats0.value + sats1.value + quote2.total.value),
          );
          await seller.pay('swap-e2');
          expect(seller.escrowPayments, hasLength(3));
        },
      );

      test(
        'a coordinator that pretends 5 next contracts, each with a fresh escrow, a deadline later by one second, the same taker (security review of #187, SECU2): six escrows paid, each after a confirmation whose sums count every earlier one',
        () async {
          final seller = await _Seller.start();
          await seller.pay('swap-e0');
          var out = seller.escrowPayments.last.$2.total.value;
          for (var take = 1; take <= 5; take++) {
            await seller.pretendedAgain();
            final shown = await seller.seen();
            expect(shown.status.trail.take, take);
            expect(shown.status.warnings, isEmpty, reason: '$take');
            final quote = await seller.quoted(shown);
            final contract = await seller.contractOf(quote);
            expect(contract.earlier, hasLength(take));
            expect(contract.notBackSats, Sats(out), reason: '$take');
            expect(contract.outIfPaid, Sats(out + quote.total.value));
            await seller.pay('swap-e$take');
            out += quote.total.value;
          }
          expect(seller.escrowPayments, hasLength(6));
        },
      );

      test(
        'under the payment\'s lock: an earlier escrow « refund pending » found settled since the confirmation (security review of #187, SECU3) asks a new confirmation, which then pays',
        () async {
          final seller = await _Seller.start();
          final first = await seller.pay('swap-e0');
          final payment0 = P2pWalletPayment(id: 'swap-e0', paymentHash: first);
          seller.found(payment0, const P2pWalletPaymentRefundPending());
          await seller.takenAgain();
          final quote = await seller.quoted();
          final contract = await seller.contractOf(quote);
          expect(
            contract.notBack.single.progress,
            isA<P2pWalletPaymentRefundPending>(),
          );
          // The service's failure was provisional: the earlier escrow is now settled, the coordinator kept it.
          seller.found(payment0, const P2pWalletPaymentPaid());
          final paid = await seller.escrow.payBond(
            seller.record,
            accepted: quote,
            contract: contract,
          );
          final again = switch (paid) {
            Err(failure: BondPayConfirmAgain(:final contract)) => contract,
            final other => fail('$other'),
          };
          expect(again.kept.single.take, 0);
          expect(again.notBack, isEmpty);
          expect(seller.escrowPayments, hasLength(1));
          expect([for (final row in await seller.rows()) row.take], [0]);
          // The new confirmation, with the escrow kept, pays.
          final quote2 = await seller.quoted();
          final contract2 = await seller.contractOf(quote2);
          expect(
            contract2.kept.single.sats,
            seller.escrowPayments.single.$2.total,
          );
          seller.fake.scriptPayment(
            Ok(
              P2pWalletPayment(
                id: 'swap-e1',
                paymentHash: quote2.invoice.paymentHash,
              ),
            ),
          );
          expect(
            await seller.escrow.payBond(
              seller.record,
              accepted: quote2,
              contract: contract2,
            ),
            isA<Ok<P2pWalletPayment, BondPayRefusal>>(),
          );
        },
      );

      test(
        'under the payment\'s lock: more out than confirmed (an attempt with no order became an order of the wallet) asks a new confirmation; as much or less out pays',
        () async {
          final seller = await _Seller.start();
          final quote0 = await seller.quoted();
          final contract0 = await seller.contractOf(quote0);
          seller.fake.scriptPayment(const Err(P2pWalletServiceUnreachable()));
          expect(
            await seller.escrow.payBond(
              seller.record,
              accepted: quote0,
              contract: contract0,
            ),
            isA<Err<P2pWalletPayment, BondPayRefusal>>(),
          );
          await seller.takenAgain();
          final quote = await seller.quoted();
          final contract = await seller.contractOf(quote);
          expect(contract.earlier.single.state, EarlierEscrowCase.back);
          expect(contract.alerts, isFalse);
          // The creation that timed out lands: the wallet now holds an order for contract 0's invoice, « creating », never funded but not provably back.
          final late = P2pWalletPayment(
            id: 'swap-late',
            paymentHash: quote0.invoice.paymentHash,
          );
          seller.found(late, const P2pWalletPaymentPreparing());
          final first = await seller.escrow.payBond(
            seller.record,
            accepted: quote,
            contract: contract,
          );
          final again = switch (first) {
            Err(failure: BondPayConfirmAgain(:final contract)) => contract,
            final other => fail('$other'),
          };
          expect(again.notBackSats, quote0.total);
          // Confirmed again with that figure, then less out by the payment (the order expired with nothing sent): it pays.
          seller.found(
            late,
            const P2pWalletPaymentExpired(P2pWalletFunds.notSent),
          );
          final quote2 = await seller.quoted();
          seller.fake.scriptPayment(
            Ok(
              P2pWalletPayment(
                id: 'swap-e1',
                paymentHash: quote2.invoice.paymentHash,
              ),
            ),
          );
          expect(
            await seller.escrow.payBond(
              seller.record,
              accepted: quote2,
              contract: EscrowContract(
                take: again.take,
                escrow: quote2.total,
                earlier: again.earlier,
              ),
            ),
            isA<Ok<P2pWalletPayment, BondPayRefusal>>(),
          );
        },
      );

      test(
        'confirmed with one quote, paid with a dearer one (security review of #187, SECUB1, C4): nothing paid nor recorded, a new confirmation with the quote that would be paid, which then pays; a cheaper one pays at once',
        () async {
          final seller = await _Seller.start();
          await seller.pay('swap-e0');
          final sats0 = seller.escrowPayments.single.$2.total;
          await seller.takenAgain();
          final small = await seller.quoted();
          final contract = await seller.contractOf(small);
          expect(contract.outIfPaid, Sats(sats0.value + small.total.value));
          P2pWalletQuote quoteAt(int fees) => P2pWalletQuote(
            invoice: small.invoice,
            payin: Sats(small.invoice.amount.value + BigInt.from(fees)),
            networkFee: Sats.fromInt(27),
            balance: Sats.fromInt(5000000),
            quotedAt: seller.harness.now,
          );
          final big = quoteAt(90000);
          final paid = await seller.escrow.payBond(
            seller.record,
            accepted: big,
            contract: contract,
          );
          final again = switch (paid) {
            Err(failure: BondPayConfirmAgain(:final contract)) => contract,
            final other => fail('$other'),
          };
          expect(again.escrow, big.total);
          expect(again.outIfPaid, Sats(sats0.value + big.total.value));
          expect(again.notBackSats, sats0);
          expect(seller.escrowPayments, hasLength(1));
          expect([for (final row in await seller.rows()) row.take], [0]);
          // Confirmed with the dearer quote: it pays.
          seller.fake.scriptPayment(
            Ok(
              P2pWalletPayment(
                id: 'swap-e1',
                paymentHash: small.invoice.paymentHash,
              ),
            ),
          );
          expect(
            await seller.escrow.payBond(
              seller.record,
              accepted: big,
              contract: again,
            ),
            isA<Ok<P2pWalletPayment, BondPayRefusal>>(),
          );
          expect(seller.escrowPayments.last.$2.total, big.total);
        },
      );

      test(
        'confirmed with one quote, paid with a cheaper one: less out, it pays',
        () async {
          final seller = await _Seller.start();
          await seller.pay('swap-e0');
          await seller.takenAgain();
          final quote = await seller.quoted();
          final contract = await seller.contractOf(quote);
          final cheaper = P2pWalletQuote(
            invoice: quote.invoice,
            payin: quote.invoice.amount,
            networkFee: Sats.fromInt(10),
            balance: Sats.fromInt(5000000),
            quotedAt: seller.harness.now,
          );
          expect(cheaper.total.value < quote.total.value, isTrue);
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
              accepted: cheaper,
              contract: contract,
            ),
            isA<Ok<P2pWalletPayment, BondPayRefusal>>(),
          );
        },
      );

      test(
        'after a restart, one more escrow of an unknown amount out between the confirmation and the payment (an attempt with no order whose late order lands) asks a new confirmation (functional verification of #187, C2, A05)',
        () async {
          final seller = await _Seller.start();
          final quote0 = await seller.quoted();
          final contract0 = await seller.contractOf(quote0);
          seller.fake.scriptPayment(const Err(P2pWalletServiceUnreachable()));
          expect(
            await seller.escrow.payBond(
              seller.record,
              accepted: quote0,
              contract: contract0,
            ),
            isA<Err<P2pWalletPayment, BondPayRefusal>>(),
          );
          await seller.takenAgain();
          // The app started again: what contract 0's attempt took out is no longer known.
          final restarted = _Seller.payOf(
            seller.harness.restart(),
            seller.wallet,
            seller.stored,
          );
          final shown = await seller.seen();
          final offered = switch (await restarted.checkBond(
            seller.record,
            shown,
          )) {
            Ok(:final value) => value.walletInvoice,
            Err(:final failure) => fail('$failure'),
          };
          final quote = seller.quoteOf(offered);
          final contract = switch (await restarted.escrowContractOf(
            seller.record,
            quote,
          )) {
            Ok(value: final contract?) => contract,
            final other => fail('$other'),
          };
          expect(contract.earlier.single.state, EarlierEscrowCase.back);
          expect(contract.notBackUnknown, 0);
          seller.found(
            P2pWalletPayment(
              id: 'swap-late',
              paymentHash: quote0.invoice.paymentHash,
            ),
            const P2pWalletPaymentPreparing(),
          );
          final paid = await restarted.payBond(
            seller.record,
            accepted: quote,
            contract: contract,
          );
          final again = switch (paid) {
            Err(failure: BondPayConfirmAgain(:final contract)) => contract,
            final other => fail('$other'),
          };
          expect(again.notBackUnknown, 1);
          expect(again.notBackSats, Sats.zero);
          // Only contract 0's refused attempt reached the wallet.
          expect(seller.escrowPayments, hasLength(1));
        },
      );

      test(
        'after the app started again, an earlier escrow\'s sats are not known: said as not known, never as 0',
        () async {
          final seller = await _Seller.start();
          await seller.pay('swap-e0');
          await seller.takenAgain();
          final restarted = _Seller.payOf(
            seller.harness.restart(),
            seller.wallet,
            seller.stored,
          );
          final shown = await seller.seen();
          final offered = switch (await restarted.checkBond(
            seller.record,
            shown,
          )) {
            Ok(:final value) => value.walletInvoice,
            Err(:final failure) => fail('$failure'),
          };
          final contract = switch (await restarted.escrowContractOf(
            seller.record,
            seller.quoteOf(offered),
          )) {
            Ok(value: final contract?) => contract,
            final other => fail('$other'),
          };
          expect(contract.earlier.single.sats, isNull);
          expect(contract.notBackUnknown, 1);
          expect(contract.notBackSats, Sats.zero);
          expect(contract.outIfPaid, seller.quoteOf(offered).total);
        },
      );

      test(
        'the app killed between the record and the wallet, before the wallet made its order: the same escrow may be paid again, and the next contract\'s is payable (the wallet holds no order for it, the record no wallet id)',
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
          expect(seller.escrowPayments, isEmpty);
          final first = (await seller.rows()).single;
          expect(first.walletPaymentId, isNull);
          killed.armed = false;
          // The app started again over the same records: the same escrow is still payable.
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
          // Taken again before anything was paid: the wallet holds no order for contract 0's invoice, so nothing left through it.
          await seller.takenAgain();
          final next = await seller.seen();
          expect(next.status.trail.take, 1);
          final quote1 = await seller.quoted(next);
          final contract1 = await seller.contractOf(quote1);
          expect(contract1.earlier.single.state, EarlierEscrowCase.back);
          expect(contract1.alerts, isFalse);
          expect(seller.fake.found, contains(first.paymentHash));
        },
      );

      test(
        'the app killed after the wallet made and sent its order, before its id was written: the next contract finds it, writes its id, and counts it not back',
        () async {
          final seller = await _Seller.start(
            payments: (stored) => _KilledAfterWallet(stored),
          );
          final quote = await seller.quoted();
          final contract = await seller.contractOf(quote);
          final payment = P2pWalletPayment(
            id: 'swap-e0',
            paymentHash: quote.invoice.paymentHash,
          );
          seller.fake.scriptPayment(Ok(payment));
          await expectLater(
            seller.escrow.payBond(
              seller.record,
              accepted: quote,
              contract: contract,
            ),
            throwsA(isA<AppKilled>()),
          );
          expect(seller.escrowPayments, hasLength(1));
          expect((await seller.rows()).single.walletPaymentId, isNull);
          seller.found(payment, const P2pWalletPaymentPending());
          await seller.takenAgain();
          final next = await seller.seen();
          final contract1 = await seller.contractOf(await seller.quoted(next));
          expect(contract1.earlier.single.state, EarlierEscrowCase.notBack);
          expect(contract1.earlier.single.sats, quote.total);
          // Its wallet id is written now, as the follow writes it.
          expect((await seller.rows()).first.walletPaymentId, 'swap-e0');
        },
      );

      test(
        'the wallet refused with nothing sent and no order (« Pay » tapped, the wallet unavailable), the collateral paid with another wallet, the order taken again: nothing of it counts as out',
        () async {
          final seller = await _Seller.start();
          final quote = await seller.quoted();
          final contract = await seller.contractOf(quote);
          seller.fake.scriptPayment(const Err(P2pWalletUnavailable()));
          expect(
            await seller.escrow.payBond(
              seller.record,
              accepted: quote,
              contract: contract,
            ),
            isA<Err<P2pWalletPayment, BondPayRefusal>>().having(
              (e) => e.failure,
              'failure',
              isA<BondPayWalletRefused>(),
            ),
          );
          expect((await seller.rows()).single.walletPaymentId, isNull);
          await seller.takenAgain();
          final next = await seller.seen();
          expect(next.status.trail.take, 1);
          final quote1 = await seller.quoted(next);
          final contract1 = await seller.contractOf(quote1);
          expect(contract1.earlier.single.state, EarlierEscrowCase.back);
          // But a refusal of the wallet whose order stays in its records (made, never funded) counts as not back until that order ends with nothing sent.
          seller.found(
            P2pWalletPayment(
              id: 'swap-unfunded',
              paymentHash: quote.invoice.paymentHash,
            ),
            const P2pWalletPaymentPreparing(),
          );
          expect(
            (await seller.contractOf(quote1)).earlier.single.state,
            EarlierEscrowCase.notBack,
          );
          seller.found(
            P2pWalletPayment(
              id: 'swap-unfunded',
              paymentHash: quote.invoice.paymentHash,
            ),
            const P2pWalletPaymentExpired(P2pWalletFunds.notSent),
          );
          expect(
            (await seller.contractOf(quote1)).earlier.single.state,
            EarlierEscrowCase.back,
          );
        },
      );

      test(
        'a wallet id repaired for a contract beyond the first, and a recorded id the wallet replaced by a later attempt (functional verification of #187, N5, N6)',
        () async {
          late _KilledAfterWallet killed;
          final seller = await _Seller.start(
            payments: (stored) =>
                killed = _KilledAfterWallet(stored, armed: false),
          );
          final first = await seller.pay('swap-e0');
          await seller.takenAgain();
          final quote1 = await seller.quoted();
          final contract1 = await seller.contractOf(quote1);
          final payment1 = P2pWalletPayment(
            id: 'swap-e1',
            paymentHash: quote1.invoice.paymentHash,
          );
          seller.fake.scriptPayment(Ok(payment1));
          killed.armed = true;
          await expectLater(
            seller.escrow.payBond(
              seller.record,
              accepted: quote1,
              contract: contract1,
            ),
            throwsA(isA<AppKilled>()),
          );
          seller.found(payment1, const P2pWalletPaymentPending());
          // Contract 0's recorded id is not the wallet's latest attempt of its invoice any more.
          seller.found(
            P2pWalletPayment(id: 'swap-e0b', paymentHash: first),
            const P2pWalletPaymentRefundPending(),
          );
          await seller.takenAgain(taker: 3);
          await seller.contractOf(await seller.quoted());
          expect(
            [
              for (final row in await seller.rows())
                (row.take, row.walletPaymentId),
            ],
            [(0, 'swap-e0b'), (1, 'swap-e1')],
          );
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
          expect(seller.escrowQuotes, isEmpty);
        },
      );

      test(
        'an invoice already recorded for another trade is refused before any quote, as presented before (security review of #187, R4)',
        () async {
          final first = await _Seller.start();
          final second = await _Seller.start(
            harness: first.harness,
            fake: first.fake,
          );
          final shown = await second.seen();
          final invoice = _Seller.invoiceOf(second.harness, shown);
          // The first trade holds a payment of the second's escrow invoice (a coordinator serving one invoice to both).
          final firstSeen = await first.seen();
          expect(firstSeen.status.trail.take, 0);
          expect(
            await first.stored.recordStart(
              first.record,
              InvoiceStep.escrow,
              paymentHash: invoice.paymentHash,
              at: first.harness.now,
            ),
            isA<Ok<bool, P2pFailure>>(),
          );
          expect(await second.refusedAt(shown), isA<BondPayEscrowSeenBefore>());
          expect([
            for (final quoted in second.fake.quoted) quoted.paymentHash,
          ], isNot(contains(invoice.paymentHash)));
        },
      );

      test(
        'a pinned escrow found among the trail\'s earlier escrows is refused by the use case itself (security review of #187, R1, M06)',
        () async {
          final seller = await _Seller.start();
          await seller.pay('swap-e0');
          await seller.takenAgain();
          final quote = await seller.quoted();
          final hash = quote.invoice.paymentHash;
          // A trail read back with the pinned escrow among its earlier ones, which the trail's trigger and the state machine never let through.
          seller.harness.trails.historyBack = (stored) => StoredTradeHistory(
            terms: stored.terms,
            trail: switch (stored.trail) {
              final trail? => _withEarlier(
                trail,
                '${trail.earlierEscrows}$hash;',
              ),
              null => null,
            },
            unreadable: stored.unreadable,
          );
          expect(
            await seller.escrow.escrowContractOf(seller.record, quote),
            isA<Err<EscrowContract?, BondPayRefusal>>().having(
              (e) => e.failure,
              'failure',
              isA<BondPayEscrowSeenBefore>(),
            ),
          );
        },
      );
    },
  );

  group('the owner\'s path, and the other trades of the Garage Key (#187)', () {
    test(
      'the maker bond paid from this wallet and held by the coordinator is no escrow: contract 0\'s escrow is offered and paid, and only escrows are followed',
      () async {
        final seller = await _Seller.start();
        final bondHash = seller.bondHash;
        if (bondHash == null) fail('no bond paid');
        expect(
          [
            for (final row in await seller.allRows())
              (row.step, row.take, row.paymentHash == bondHash),
          ],
          [(InvoiceStep.bond, 0, true)],
        );
        final quote = await seller.quoted();
        final contract = await seller.contractOf(quote);
        expect(contract.earlier, isEmpty);
        await seller.pay('swap-e0');
        expect(
          [for (final row in await seller.allRows()) (row.step, row.take)],
          [(InvoiceStep.bond, 0), (InvoiceStep.escrow, 0)],
        );
        final follow = await seller.escrow.followEscrows(seller.record).first;
        if (follow is! EscrowPaymentsFollowed) fail('$follow');
        expect([for (final e in follow.escrows) e.take], [0]);
      },
    );

    test(
      'at 7 (`WaitingForEscrow`): paid as at 6, and with an earlier escrow not back, alerted and paid as at 6',
      () async {
        final seller = await _Seller.start();
        seller.order.status = 7;
        final seven = await seller.seen();
        expect(seven.status, isA<WaitingForEscrow>());
        final first = await seller.pay('swap-e0');
        expect(seller.escrowPayments.single.$1.paymentHash, first);
        await seller.takenAgain();
        seller.order.status = 7;
        final next = await seller.seen();
        expect(next.status, isA<WaitingForEscrow>());
        expect(next.status.trail.take, 1);
        final at7 = await seller.contractOf(await seller.quoted(next));
        expect(at7.earlier.single.state, EarlierEscrowCase.notBack);
        await seller.pay('swap-e1');
        expect(seller.escrowPayments, hasLength(2));
      },
    );

    test(
      'another order of the same Garage Key, its escrow held, holds nothing of this one back: each trade\'s payments are its own robot\'s',
      () async {
        final first = await _Seller.start();
        final second = await _Seller.start(
          harness: first.harness,
          fake: first.fake,
        );
        expect(second.record.robot, isNot(first.record.robot));
        expect(
          second.record.robot.keyFingerprint,
          first.record.robot.keyFingerprint,
        );
        // The second order's escrow paid from this wallet, and held.
        await second.pay('swap-other');
        // The first order seen at its contract 0, then taken again before its own escrow was paid: contract 1, nothing of its own recorded.
        expect((await first.seen()).status.trail.take, 0);
        await first.takenAgain();
        final next = await first.seen();
        expect(next.status.trail.take, 1);
        final quote = await first.quoted(next);
        final contract = await first.contractOf(quote);
        expect(contract.earlier, isEmpty);
        expect(
          [for (final row in await first.allRows()) row.step],
          [InvoiceStep.bond],
        );
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
          [
            (InvoiceStep.bond, 0, seller.bondHash),
            (InvoiceStep.escrow, 0, first),
            (InvoiceStep.escrow, 1, second),
          ],
        );
        // A trade with nothing recorded: none.
        final other = await _Seller.start(bondFromWallet: false);
        expect(await other.allRows(), isEmpty);
      },
    );
  });
}

/// [trail] with [earlierEscrows] in place of its own.
TradeTrailRecord _withEarlier(TradeTrailRecord trail, String earlierEscrows) =>
    TradeTrailRecord(
      version: trail.version,
      network: trail.network,
      coordinatorAlias: trail.coordinatorAlias,
      orderId: trail.orderId,
      role: trail.role,
      position: trail.position,
      readAtMicros: trail.readAtMicros,
      bondHash: trail.bondHash,
      escrowHash: trail.escrowHash,
      deadlineMicros: trail.deadlineMicros,
      bondStepSeenAtMicros: trail.bondStepSeenAtMicros,
      bondStepDeadlineMicros: trail.bondStepDeadlineMicros,
      breached: trail.breached,
      historyUnknown: trail.historyUnknown,
      take: trail.take,
      takeDeadlineMicros: trail.takeDeadlineMicros,
      takerHashId: trail.takerHashId,
      takenAmount: trail.takenAmount,
      earlierEscrows: earlierEscrows,
      seenLate: trail.seenLate,
    );
