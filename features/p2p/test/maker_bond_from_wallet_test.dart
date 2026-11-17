import 'package:p2p/p2p.dart';
import 'package:p2p/src/data/trade_payment_repository_impl.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/trade_payment_repository.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_payment.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/domain/trade/wallet_rate_check.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/bond_payments_in_flight.dart';
import 'package:p2p/src/domain/usecases/trade/pay_bond_from_wallet_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/testing.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';
import 'support/trade_harness.dart' show AppKilled, TradeHarness;

T _some<T>(T? value) => value ?? (throw StateError('missing'));

/// Payments whose wallet id cannot be written because the app is killed right then: after the wallet answered, before its id is recorded.
final class _KilledAfterPayment implements TradePaymentRepository {
  final TradePaymentRepository inner;

  _KilledAfterPayment(this.inner);

  @override
  Future<Result<TradePaymentRecord?, P2pFailure>> paymentOf(
    TradeRecord trade,
    InvoiceStep step, {
    int take = 0,
  }) => inner.paymentOf(trade, step, take: take);

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
  }) => throw AppKilled();
}

/// An order made here, at its maker bond (0), and the wallet's payment of that bond.
final class _Made {
  final MakeHarness harness;
  final TradeRecord record;
  final FakeP2pWalletPort fake;
  final TradePaymentRepositoryImpl payments;
  final PayBondFromWalletUsecase payBond;

  _Made(this.harness, this.record, this.fake, this.payments, this.payBond);

  /// The order of the owner's example by default: 100 USD at a premium of +3.5 %, a bond of 3 %, the coordinator's price [price]; the wallet's price [rate].
  static Future<_Made> start({
    String code = 'USD',
    double price = 71657,
    double premium = 3.5,
    P2pWalletBitcoinRate? rate,
    void Function(MakeHarness harness)? before,
    TradePaymentRepository Function(TradePaymentRepository stored)? payments,
  }) async {
    final harness = await MakeHarness.start();
    final currency = _some(RobosatsCurrency.fromCode(code));
    harness.coordinator.prices[currency.id] = price;
    before?.call(harness);
    final record = await _make(harness, currency: currency, premium: premium);
    final fake = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
      ..rate = rate ?? P2pWalletRateRead(71657);
    final stored = TradePaymentRepositoryImpl(harness.database);
    return _Made(
      harness,
      record,
      fake,
      stored,
      _payBondOf(harness, fake, payments?.call(stored) ?? stored),
    );
  }

  static Future<TradeRecord> _make(
    MakeHarness harness, {
    required RobosatsCurrency currency,
    required double premium,
  }) async => switch (await harness.makeOrder(
    MakeHarness.request(currency: currency, premium: premium),
  )) {
    Ok(value: final MakeStarted started) => started.record,
    final other => throw StateError('not made: $other'),
  };

  static PayBondFromWalletUsecase _payBondOf(
    MakeHarness harness,
    P2pWalletPort wallet,
    TradePaymentRepository payments, {
    InvoiceStep step = InvoiceStep.bond,
  }) => PayBondFromWalletUsecase(
    harness.reader,
    harness.limiter,
    payments,
    wallet,
    harness.locks,
    BondPaymentsInFlight(),
    step: step,
  );

  /// The status the watch shows now.
  Future<TradeSeen> seen([TradeRecord? of]) async {
    final run = harness.watchOf(of ?? record);
    await harness.settle();
    await run.subscription.cancel();
    return run.lastStatus.seen;
  }

  /// The invoice the status shown holds, as the wallet's port would take it.
  Future<CheckedBolt11Invoice> invoiceShown([TradeRecord? of]) async {
    final shown = await seen(of);
    final invoice = shown.status.invoice;
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
    payin: Sats(invoice.amount.value + BigInt.from(120)),
    networkFee: Sats.fromInt(27),
    balance: Sats.fromInt(5000000),
    quotedAt: harness.now,
  );

  /// The quote the user confirmed, after the tap of « Pay with this wallet ».
  Future<P2pWalletQuote> quoted([TradeRecord? of]) async {
    final shown = await seen(of);
    final offered = switch (await payBond.checkBond(of ?? record, shown)) {
      Ok(:final value) => value.walletInvoice,
      Err(:final failure) => throw StateError('not offered: $failure'),
    };
    fake.scriptQuote(Ok(quoteOf(offered)));
    return switch (await payBond.quoteBond(of ?? record, shown)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('no quote: $failure'),
    };
  }

  /// What `rateOfBond` gives for [quote].
  Future<WalletRateCheck?> rateOf(P2pWalletQuote quote) async =>
      switch (await payBond.rateOfBond(record, quote)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  /// What `rateOfBond` gives for [quote], which the test expects to be a comparison.
  Future<WalletRateCompared> comparedOf(P2pWalletQuote quote) async =>
      switch (await rateOf(quote)) {
        final WalletRateCompared compared => compared,
        final other => throw StateError('not compared: $other'),
      };

  Future<TradePaymentRecord?> recorded([TradeRecord? of]) async =>
      switch (await payments.paymentOf(of ?? record, InvoiceStep.bond)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  /// Every way of paying the bond refuses, and neither the swap service nor the wallet is asked.
  Future<void> neverPaid() async {
    final shown = await seen();
    expect(shown.stored, isTrue);
    expect(shown.status, isA<WaitingForMakerBond>());
    final invoice = await invoiceShown();
    fake
      ..scriptQuote(Ok(quoteOf(invoice)))
      ..scriptPayment(
        const Ok(P2pWalletPayment(id: 'never-asked', paymentHash: 'none')),
      );
    expect(
      await payBond.checkBond(record, shown),
      isA<Err<Object?, BondPayRefusal>>(),
    );
    expect(
      await payBond.quoteBond(record, shown),
      isA<Err<Object?, BondPayRefusal>>(),
    );
    expect(
      await payBond.payBond(record, accepted: quoteOf(invoice)),
      isA<Err<Object?, BondPayRefusal>>(),
    );
    expect(fake.quoted, isEmpty);
    expect(fake.paid, isEmpty);
    expect(await recorded(), isNull);
  }
}

void main() {
  group('the maker bond at 0, from this wallet (#180)', () {
    test(
      'offered within the terms\' bond ceiling, quoted, compared with the wallet\'s price, then paid once, recorded before the wallet is asked',
      () async {
        final made = await _Made.start();
        final shown = await made.seen();
        expect(shown.status, isA<WaitingForMakerBond>());
        final offered = switch (await made.payBond.checkBond(
          made.record,
          shown,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        // The coordinator's bond of the example: int(134,834 × 3 / 100) = 4,045; the ceiling, the bond at the creation's price with 2 % and 1 sat, rounded down: floor(4,045.035 × 1.02 + 1) = 4,126.
        expect(offered.walletInvoice.amount, Sats.fromInt(4045));
        expect(offered.accepted, Sats.fromInt(4126));
        expect(offered.take, 0);
        final quote = await made.quoted();
        expect(made.fake.quoted.single.paymentHash, quote.invoice.paymentHash);
        final rate = await made.comparedOf(quote);
        expect(rate, isA<WalletRateAtWallet>());
        expect(rate.expected, Sats.fromInt(4045));
        expect(rate.warns, isFalse);
        expect(made.fake.ratesAsked.single.$1, made.harness.network);
        expect(made.fake.ratesAsked.single.$2.code, 'USD');
        final hash = quote.invoice.paymentHash;
        made.fake.scriptPayment(
          Ok(P2pWalletPayment(id: 'swap-m1', paymentHash: hash)),
        );
        expect(made.fake.paid, isEmpty);
        final paid = await made.payBond.payBond(made.record, accepted: quote);
        expect(paid, isA<Ok<P2pWalletPayment, BondPayRefusal>>());
        expect(made.fake.paid.single.$1.paymentHash, hash);
        final recorded = await made.recorded();
        expect(recorded?.paymentHash, hash);
        expect(recorded?.walletPaymentId, 'swap-m1');
        // The price was asked once, for the confirmation; the payment never reads it.
        expect(made.fake.ratesAsked, hasLength(1));
      },
    );

    test(
      'a bond beyond the owner\'s threshold is said in red and still paid on the user\'s confirmation: the rule never stops a payment',
      () async {
        // The wallet's price 79,000, the coordinator's 71,657: 3,669 expected, 4,045 asked, +10.25 %.
        final made = await _Made.start(rate: P2pWalletRateRead(79000));
        final quote = await made.quoted();
        final rate = await made.comparedOf(quote);
        expect(rate.warns, isTrue);
        expect(rate.asked, Sats.fromInt(4045));
        expect(rate.expected, Sats.fromInt(3669));
        made.fake.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-m2',
              paymentHash: quote.invoice.paymentHash,
            ),
          ),
        );
        expect(
          await made.payBond.payBond(made.record, accepted: quote),
          isA<Ok<P2pWalletPayment, BondPayRefusal>>(),
        );
        expect(made.fake.paid, hasLength(1));
      },
    );

    test(
      'a coordinator that announced a price ten times too low: its bond agrees with its own estimate, and the wallet\'s price warns of it; without the wallet\'s price, nothing reassuring is said (review of #180, C1)',
      () async {
        // 7,165.7 announced and used for the bond: 40,450 sats, within the coordinator's estimate, so offered; the wallet's 71,657 expects 4,045.
        final made = await _Made.start(price: 7165.7);
        final quote = await made.quoted();
        expect(quote.amount, Sats.fromInt(40450));
        final rate = await made.comparedOf(quote);
        expect(rate, isA<WalletRateAtWallet>());
        expect(rate.expected, Sats.fromInt(4045));
        expect(rate.warns, isTrue);
        made.fake.rate = const P2pWalletRateUnavailable();
        expect(await made.rateOf(quote), isA<WalletRateUnverified>());
      },
    );

    test(
      'a currency the wallet does not price: compared with the price of the creation, said weaker',
      () async {
        final made = await _Made.start(
          code: 'GBP',
          price: 60000,
          rate: const P2pWalletRateNotPriced(),
        );
        final quote = await made.quoted();
        final rate = await made.comparedOf(quote);
        expect(rate, isA<WalletRateAtCreation>());
        expect(rate.price, 60000);
        expect(rate.warns, isFalse);
        expect(made.fake.ratesAsked.single.$2.code, 'GBP');
      },
    );

    test(
      'the wallet\'s price could not be read: nothing compared, the payment still possible; read again, the comparison comes',
      () async {
        final made = await _Made.start(rate: const P2pWalletRateUnavailable());
        final quote = await made.quoted();
        expect(await made.rateOf(quote), isA<WalletRateUnverified>());
        // « Retry »: the same quote, the price read again.
        made.fake.rate = P2pWalletRateRead(71657);
        final again = await made.comparedOf(quote);
        expect(again, isA<WalletRateAtWallet>());
        expect(again.expected, Sats.fromInt(4045));
        expect(made.fake.ratesAsked, hasLength(2));
        expect(made.fake.quoted, hasLength(1));
        made.fake.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-m3',
              paymentHash: quote.invoice.paymentHash,
            ),
          ),
        );
        expect(
          await made.payBond.payBond(made.record, accepted: quote),
          isA<Ok<P2pWalletPayment, BondPayRefusal>>(),
        );
      },
    );

    test(
      'a quote presented twice pays once: the second is refused, nothing sent again',
      () async {
        final made = await _Made.start();
        final quote = await made.quoted();
        made.fake.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-m4',
              paymentHash: quote.invoice.paymentHash,
            ),
          ),
        );
        final results = await Future.wait([
          made.payBond.payBond(made.record, accepted: quote),
          made.payBond.payBond(made.record, accepted: quote),
        ]);
        expect(
          results.whereType<Ok<P2pWalletPayment, BondPayRefusal>>(),
          hasLength(1),
        );
        expect((await made.recorded())?.walletPaymentId, 'swap-m4');
      },
    );

    test(
      'the app killed between the wallet\'s answer and its record: after the restart the payment is found by its hash and followed, and never paid again',
      () async {
        final made = await _Made.start(payments: _KilledAfterPayment.new);
        final quote = await made.quoted();
        final hash = quote.invoice.paymentHash;
        final payment = P2pWalletPayment(id: 'swap-m5', paymentHash: hash);
        made.fake.scriptPayment(Ok(payment));
        await expectLater(
          made.payBond.payBond(made.record, accepted: quote),
          throwsA(isA<AppKilled>()),
        );
        // What the run left: the start recorded, the wallet's id not.
        expect((await made.recorded())?.paymentHash, hash);
        expect((await made.recorded())?.walletPaymentId, isNull);
        // The wallet's own records hold the payment, which survive the app.
        made.fake
          ..setFound(
            hash,
            P2pWalletPaymentFound(
              payment: payment,
              progress: const P2pWalletPaymentSent(),
            ),
          )
          ..setProgress(payment, const Ok(P2pWalletPaymentSent()));
        final again = made.harness.restart();
        final payBond = _Made._payBondOf(again, made.fake, made.payments);
        final first = await payBond.followBond(made.record).first;
        expect(
          first,
          isA<BondPaymentFollowed>().having(
            (f) => f.progress,
            'progress',
            isA<P2pWalletPaymentSent>(),
          ),
        );
        expect((await made.recorded())?.walletPaymentId, 'swap-m5');
        // A new tap, a new quote: the wallet refuses an invoice it already paid, and nothing leaves twice.
        made.fake.scriptQuote(Ok(made.quoteOf(quote.invoice)));
        final run = again.watchOf(made.record);
        await again.settle();
        final shown = run.lastStatus.seen;
        await run.subscription.cancel();
        expect(shown.status, isA<WaitingForMakerBond>());
        final requoted = switch (await payBond.quoteBond(made.record, shown)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        final paid = await payBond.payBond(made.record, accepted: requoted);
        expect(
          paid,
          isA<Err<P2pWalletPayment, BondPayRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<BondPayWalletRefused>().having(
              (r) => r.refusal,
              'refusal',
              isA<P2pWalletPaymentExists>(),
            ),
          ),
        );
      },
    );
  });

  group('still refused at 0, as for a taker: « Pay with this wallet » does not pay', () {
    test(
      'the bond outside the coordinator\'s own estimate (BondAmountOutsideOrder)',
      () async {
        final made = await _Made.start(
          before: (harness) => harness.coordinator.onRequest = (request) {
            // The price moves by 5 % between the limits read and the order's first read: the bond is no longer the order's.
            if (request.url.path.endsWith('/api/make/')) {
              harness.coordinator.prices[1] = 71657 * 1.05;
            }
          },
        );
        expect(
          (await made.seen()).status.has<BondAmountOutsideOrder>(),
          isTrue,
        );
        await made.neverPaid();
      },
    );

    test(
      'an invoice that is not the bond the order says (InvoiceAmountMismatch)',
      () async {
        final made = await _Made.start();
        made.harness.coordinator.orderChanges[made.record.orderId] = {
          'bond_satoshis': 4046,
        };
        await made.neverPaid();
      },
    );

    test('the order\'s terms changed (TradeTermsChanged)', () async {
      final made = await _Made.start();
      made.harness.coordinator.orderChanges[made.record.orderId] = {
        'premium': '4.00',
      };
      expect((await made.seen()).status.has<TradeTermsChanged>(), isTrue);
      await made.neverPaid();
    });

    test(
      'too late: the bond\'s end within the wallet\'s margin, nothing offered, nothing paid',
      () async {
        final made = await _Made.start();
        final early = await made.seen();
        final invoice = await made.invoiceShown();
        await made.harness.elapse(const Duration(seconds: 245));
        // The status a screen kept, by the clock: too late.
        expect(
          await made.payBond.checkBond(made.record, early),
          isA<Err<WalletPaymentOffered, BondPayRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<BondPayNotOffered>().having(
              (n) => n.reason,
              'reason',
              WalletPaymentRefusal.tooLate,
            ),
          ),
        );
        // A read now: the state machine says it expires soon, which the wallet never pays.
        final shown = await made.seen();
        expect(shown.status, isA<WaitingForMakerBond>());
        expect(shown.status.has<InvoiceExpiringSoon>(), isTrue);
        expect(
          await made.payBond.checkBond(made.record, shown),
          isA<Err<WalletPaymentOffered, BondPayRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<BondPayNotOffered>(),
          ),
        );
        made.fake.scriptPayment(
          const Ok(P2pWalletPayment(id: 'never-asked', paymentHash: 'none')),
        );
        expect(
          await made.payBond.payBond(
            made.record,
            accepted: made.quoteOf(invoice),
          ),
          isA<Err<P2pWalletPayment, BondPayRefusal>>(),
        );
        expect(made.fake.paid, isEmpty);
      },
    );

    test(
      'a payment hash already paid for another order: refused before the wallet is asked',
      () async {
        // Order 42 is made and its bond paid from this wallet; then order 43, of another robot, is served the very same invoice.
        final made = await _Made.start();
        final quote = await made.quoted();
        made.fake.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-m6',
              paymentHash: quote.invoice.paymentHash,
            ),
          ),
        );
        expect(
          await made.payBond.payBond(made.record, accepted: quote),
          isA<Ok<P2pWalletPayment, BondPayRefusal>>(),
        );
        final coordinator = made.harness.coordinator;
        coordinator.onRequest = (request) {
          if (coordinator.orders[43] case final second?
              when second.bond == null) {
            second.bond = coordinator.order(42).bond;
          }
        };
        final other = await _Made._make(
          made.harness,
          currency: _some(RobosatsCurrency.fromCode('USD')),
          premium: 3.5,
        );
        expect(other.orderId, 43);
        final shown = await made.seen(other);
        final invoice = await made.invoiceShown(other);
        expect(invoice.paymentHash, quote.invoice.paymentHash);
        expect(shown.status, isA<WaitingForMakerBond>());
        // Offered by the state machine and quoted (the trail of order 43 knows nothing of order 42), but its payment records nothing, and the wallet is never asked.
        final requote = await made.quoted(other);
        final paid = await made.payBond.payBond(other, accepted: requote);
        expect(
          paid,
          isA<Err<P2pWalletPayment, BondPayRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<BondPayNotRecorded>(),
          ),
        );
        expect(made.fake.paid, hasLength(1));
        expect(await made.recorded(other), isNull);
      },
    );

    test(
      'the escrow\'s instance never pays a maker bond, nor reads the wallet\'s price',
      () async {
        final made = await _Made.start();
        final escrow = _Made._payBondOf(
          made.harness,
          made.fake,
          made.payments,
          step: InvoiceStep.escrow,
        );
        final shown = await made.seen();
        expect(
          await escrow.checkBond(made.record, shown),
          isA<Err<WalletPaymentOffered, BondPayRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<BondPayNotAtBondStep>(),
          ),
        );
        final invoice = await made.invoiceShown();
        expect(
          await escrow.rateOfBond(made.record, made.quoteOf(invoice)),
          isA<Ok<WalletRateCheck?, BondPayRefusal>>().having(
            (r) => r.value,
            'value',
            isNull,
          ),
        );
        expect(made.fake.ratesAsked, isEmpty);
      },
    );
  });

  group('a maker seller\'s escrow stays refused (#187)', () {
    for (final status in [6, 7]) {
      test(
        'at $status: never offered, quoted or paid, by the escrow\'s instance or the bond\'s',
        () async {
          final harness = await MakeHarness.start();
          final record = switch (await harness.makeOrder(
            MakeHarness.request(sell: true),
          )) {
            Ok(value: final MakeStarted started) => started.record,
            final other => fail('$other'),
          };
          harness.coordinator
            ..lockMakerBond(record.orderId)
            ..take(record.orderId, harness.robot(5));
          harness.coordinator.order(record.orderId).status = status;
          final run = harness.watchOf(record);
          await harness.settle();
          final seen = run.lastStatus.seen;
          await run.subscription.cancel();
          expect(seen.stored, isTrue);
          final fake = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)));
          for (final step in InvoiceStep.values) {
            final payBond = _Made._payBondOf(
              harness,
              fake,
              TradePaymentRepositoryImpl(harness.database),
              step: step,
            );
            expect(
              await payBond.checkBond(record, seen),
              isA<Err<WalletPaymentOffered, BondPayRefusal>>(),
              reason: step.name,
            );
            expect(
              await payBond.quoteBond(record, seen),
              isA<Err<P2pWalletQuote, BondPayRefusal>>(),
              reason: step.name,
            );
          }
          expect(fake.quoted, isEmpty);
          expect(fake.paid, isEmpty);
          expect(fake.ratesAsked, isEmpty);
        },
      );

      test(
        'at $status, a coordinator that fixes a tiny trade, coherent everywhere (1,000 sats): no warning, an escrow under the bond\'s ceiling, and still never offered nor quoted by either instance (security review of #180, C1)',
        () async {
          final harness = await MakeHarness.start();
          final record = switch (await harness.makeOrder(
            MakeHarness.request(sell: true),
          )) {
            Ok(value: final MakeStarted started) => started.record,
            final other => fail('$other'),
          };
          harness.coordinator
            ..lockMakerBond(record.orderId)
            ..take(record.orderId, harness.robot(5));
          final made = harness.coordinator.order(record.orderId)
            ..lastSatoshis = 1000
            ..status = status;
          expect(made.lastSatoshis, 1000);
          final run = harness.watchOf(record);
          await harness.settle();
          final seen = run.lastStatus.seen;
          await run.subscription.cancel();
          // What makes the case: the state machine finds nothing wrong (no warning on the trade's sats, § 3.3), and the escrow is below the maker bond's ceiling, so only the guard of the maker's side refuses it.
          expect(seen.stored, isTrue);
          expect(seen.status.warnings, isEmpty);
          final invoice = seen.status.invoice;
          expect(invoice, isA<CheckedInvoice>());
          if (invoice is! CheckedInvoice) return;
          expect(invoice.step, InvoiceStep.escrow);
          expect(invoice.passedEveryCheck, isTrue);
          final ceiling = switch (await harness.reader.open(record)) {
            TradeOpened(:final trade) => trade.terms.bondCeiling,
            final other => fail('$other'),
          };
          expect(invoice.amount.value, lessThan(ceiling.value));
          final fake = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)));
          for (final step in InvoiceStep.values) {
            final payBond = _Made._payBondOf(
              harness,
              fake,
              TradePaymentRepositoryImpl(harness.database),
              step: step,
            );
            expect(
              await payBond.checkBond(record, seen),
              isA<Err<WalletPaymentOffered, BondPayRefusal>>().having(
                (e) => e.failure,
                'failure',
                isA<BondPayNotAtBondStep>(),
              ),
              reason: step.name,
            );
            expect(
              await payBond.quoteBond(record, seen),
              isA<Err<P2pWalletQuote, BondPayRefusal>>(),
              reason: step.name,
            );
          }
          expect(fake.quoted, isEmpty);
          expect(fake.paid, isEmpty);
          expect(fake.ratesAsked, isEmpty);
        },
      );
    }
  });

  test(
    'a take is unchanged: no price of the wallet is asked, and no comparison given',
    () async {
      final harness = await TradeHarness.start();
      final record = TradeHarness.recordOf(await harness.takeShown());
      final fake = FakeP2pWalletPort(Ok(Sats.fromInt(500000)))
        ..rate = P2pWalletRateRead(71657);
      final payBond = PayBondFromWalletUsecase(
        harness.reader,
        harness.limiter,
        TradePaymentRepositoryImpl(harness.database),
        fake,
        harness.locks,
        BondPaymentsInFlight(),
      );
      final run = harness.watchOf(record);
      await harness.settle();
      final seen = run.lastStatus.seen;
      await run.subscription.cancel();
      final offered = switch (await payBond.checkBond(record, seen)) {
        Ok(:final value) => value.walletInvoice,
        Err(:final failure) => fail('$failure'),
      };
      final quote = P2pWalletQuote(
        invoice: offered,
        payin: Sats(offered.amount.value + BigInt.from(120)),
        networkFee: Sats.fromInt(27),
        balance: Sats.fromInt(500000),
        quotedAt: harness.now,
      );
      expect(
        await payBond.rateOfBond(record, quote),
        isA<Ok<WalletRateCheck?, BondPayRefusal>>().having(
          (r) => r.value,
          'value',
          isNull,
        ),
      );
      expect(fake.ratesAsked, isEmpty);
    },
  );
}
