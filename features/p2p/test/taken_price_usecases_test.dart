import 'package:p2p/p2p.dart';
import 'package:p2p/src/data/trade_payment_repository_impl.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_rate_check.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/bond_payments_in_flight.dart';
import 'package:p2p/src/domain/usecases/trade/check_payout_rate_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/pay_bond_from_wallet_usecase.dart';
import 'package:p2p/src/presentation/payout_rate_cubit.dart';
import 'package:p2p/testing.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// The owner's payment rule for an order taken here (#249; design note `docs/design/phase-3-taken-order-price-check.md` § 3, § 8 slices 1 and 3) through the real use cases, records and state machine of a take, the coordinator played by `ScriptedCoordinator` (never a real one), the wallet `FakeP2pWalletPort` (no swap service, no price service, no money): what `PayBondFromWalletUsecase.rateOfBond` answers at the bond and at a taker seller's escrow, and what `CheckPayoutRateUsecase` and `PayoutRateCubit` compare for a taker buyer.
///
/// The order is the owner's example: 100 USD at +3.5 %, a bond of 3 %, its sats at the coordinator's price [_App.start]'s `sats` (134,834 by default, the Bull wallet's price of 71,657 USD/BTC); the taker fee the reference's default, 0.175 %.
final class _App {
  final TradeHarness app;
  final TradeRecord record;
  final FakeP2pWalletPort wallet;
  final PayBondFromWalletUsecase bond;
  final PayBondFromWalletUsecase escrow;

  _App(this.app, this.record, this.wallet, this.bond, this.escrow);

  /// A sell order (this robot the buyer) or, with [seller], a buy order, taken at the pre-take (3).
  static Future<_App> start({
    bool seller = false,
    int sats = 134834,
    int currency = 1,
    P2pWalletBitcoinRate? rate,
  }) async {
    final app = await TradeHarness.start(orderType: seller ? 0 : 1);
    app.coordinator
      ..currency = currency
      ..premium = 3.5
      ..satoshisNow = sats
      ..price = 74165;
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
    final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
      ..rate = rate ?? P2pWalletRateRead(71657);
    final payments = TradePaymentRepositoryImpl(app.database);
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
    return _App(
      app,
      record,
      wallet,
      of(InvoiceStep.bond),
      of(InvoiceStep.escrow),
    );
  }

  Future<TradeSeen> seen() async {
    final run = app.watchOf(record);
    await app.settle();
    await run.subscription.cancel();
    return run.lastStatus.seen;
  }

  /// The bond locked: the trade at 6, read.
  Future<TradeSeen> locked() async {
    final run = app.watchOf(record);
    await app.settle();
    app.coordinator.lockBond(app.robot(0));
    await app.elapse(const Duration(seconds: 10));
    await run.subscription.cancel();
    return seen();
  }

  P2pWalletQuote quoteOf(CheckedBolt11Invoice invoice) => P2pWalletQuote(
    invoice: invoice,
    payin: Sats(invoice.amount.value + BigInt.from(300)),
    networkFee: Sats.fromInt(27),
    balance: Sats.fromInt(5000000),
    quotedAt: app.now,
  );

  /// The quote of the invoice [use] offers at [seen].
  Future<P2pWalletQuote> quoted(
    PayBondFromWalletUsecase use,
    TradeSeen seen,
  ) async {
    final offered = switch (await use.checkBond(record, seen)) {
      Ok(:final value) => value.walletInvoice,
      Err(:final failure) => throw StateError('not offered: $failure'),
    };
    return quoteOf(offered);
  }
}

Matcher _compared({
  required int expected,
  required int asked,
  required bool warns,
  WalletRateSide side = WalletRateSide.pays,
}) => isA<Ok<WalletRateCheck?, BondPayRefusal>>().having(
  (ok) => ok.value,
  'value',
  isA<WalletRateAtWallet>()
      .having((c) => c.expected, 'expected', Sats.fromInt(expected))
      .having((c) => c.asked, 'asked', Sats.fromInt(asked))
      .having((c) => c.warns, 'warns', warns)
      .having((c) => c.side, 'side', side),
);

void main() {
  group('the taker bond, in the confirmation of « Pay with this wallet »', () {
    test(
      'the owner\'s example: the bond of 4,045 sats against 4,045 expected at the Bull wallet\'s price, read once for the order\'s currency',
      () async {
        final app = await _App.start();
        final seen = await app.seen();
        expect(seen.status, isA<WaitingForTakerBond>());
        final quote = await app.quoted(app.bond, seen);
        expect(quote.amount, Sats.fromInt(4045));
        expect(
          await app.bond.rateOfBond(app.record, quote),
          _compared(expected: 4045, asked: 4045, warns: false),
        );
        expect(app.wallet.ratesAsked, hasLength(1));
        expect(app.wallet.ratesAsked.single.$2.code, 'USD');
        expect(app.wallet.paid, isEmpty);
      },
    );

    test(
      'its bounds: 4,449 sats shown without a warning, 4,450 with it (the coordinator\'s sats 148,300 and 148,334)',
      () async {
        for (final (sats, bond, warns) in [
          (148300, 4449, false),
          (148334, 4450, true),
        ]) {
          final app = await _App.start(sats: sats);
          final quote = await app.quoted(app.bond, await app.seen());
          expect(quote.amount, Sats.fromInt(bond));
          expect(
            await app.bond.rateOfBond(app.record, quote),
            _compared(expected: 4045, asked: bond, warns: warns),
          );
        }
      },
    );

    test(
      'a price that could not be read, then read: « rate not checked », then the comparison; a currency the Bull wallet does not price: not compared',
      () async {
        final app = await _App.start(rate: const P2pWalletRateUnavailable());
        final quote = await app.quoted(app.bond, await app.seen());
        expect(
          await app.bond.rateOfBond(app.record, quote),
          isA<Ok<WalletRateCheck?, BondPayRefusal>>().having(
            (ok) => ok.value,
            'value',
            isA<WalletRateUnverified>(),
          ),
        );
        app.wallet.rate = P2pWalletRateRead(71657);
        expect(
          await app.bond.rateOfBond(app.record, quote),
          _compared(expected: 4045, asked: 4045, warns: false),
        );
        // CHF (id 7): the Bull wallet does not price it.
        final chf = await _App.start(
          currency: 7,
          rate: const P2pWalletRateNotPriced(),
        );
        final chfQuote = await chf.quoted(chf.bond, await chf.seen());
        expect(
          await chf.bond.rateOfBond(chf.record, chfQuote),
          isA<Ok<WalletRateCheck?, BondPayRefusal>>().having(
            (ok) => ok.value,
            'value',
            isA<WalletRateNotPriced>(),
          ),
        );
        expect(chf.wallet.ratesAsked.single.$2.code, 'CHF');
      },
    );

    test(
      'the terms the take stored, of version 1 as phase 2 writes them, are those compared',
      () async {
        final app = await _App.start(sats: 1348344);
        final history = switch (await app.app.trails.historyOf(app.record)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(history.terms?.version, 1);
        expect(history.terms?.premiumPercent, 3.5);
        expect(history.terms?.amount, 100);
        // Ten times too low a price: a bond of 40,450 sats, red.
        final quote = await app.quoted(app.bond, await app.seen());
        expect(
          await app.bond.rateOfBond(app.record, quote),
          _compared(expected: 4045, asked: 40450, warns: true),
        );
      },
    );
  });

  group('a taker seller\'s escrow, in the confirmation of « Pay with this wallet »', () {
    test(
      'the honest escrow of 135,070 sats against 134,834 expected (+0.18 %), the escrow the trail pins',
      () async {
        final app = await _App.start(seller: true);
        final six = await app.locked();
        expect(six.status, isA<WaitingForBoth>());
        final quote = await app.quoted(app.escrow, six);
        expect(quote.amount, Sats.fromInt(135070));
        expect(
          await app.escrow.rateOfBond(app.record, quote),
          _compared(expected: 134834, asked: 135070, warns: false),
        );
      },
    );

    test(
      'its bounds: 148,317 sats shown without a warning, 148,318 with it (the coordinator\'s sats 148,058 and 148,059)',
      () async {
        for (final (sats, escrow, warns) in [
          (148058, 148317, false),
          (148059, 148318, true),
        ]) {
          final app = await _App.start(seller: true, sats: sats);
          final quote = await app.quoted(app.escrow, await app.locked());
          expect(quote.amount, Sats.fromInt(escrow));
          expect(
            await app.escrow.rateOfBond(app.record, quote),
            _compared(expected: 134834, asked: escrow, warns: warns),
          );
        }
      },
    );

    test(
      'a quote of another invoice than the escrow the trail pins: refused as an invoice changed, the price never asked',
      () async {
        final app = await _App.start(seller: true);
        final six = await app.locked();
        final pinned = (await app.quoted(app.escrow, six)).invoice;
        final other = checkedBolt11InvoiceForTesting(
          bolt11: pinned.bolt11,
          amount: pinned.amount,
          network: RobosatsNetwork.testnet,
          paymentHash:
              'cd00000000000000000000000000000000000000000000000000000000000000',
          expiresAt: app.app.now.add(const Duration(hours: 3)),
          now: app.app.now,
        );
        if (other == null) fail('not a payable invoice');
        expect(
          await app.escrow.rateOfBond(app.record, app.quoteOf(other)),
          isA<Err<WalletRateCheck?, BondPayRefusal>>().having(
            (err) => err.failure,
            'failure',
            isA<BondPayInvoiceChanged>(),
          ),
        );
        expect(app.wallet.ratesAsked, isEmpty);
      },
    );

    test(
      'a taker buyer has no escrow to compare: nothing, the price never asked',
      () async {
        final app = await _App.start();
        final bondQuote = await app.quoted(app.bond, await app.seen());
        final six = await app.locked();
        expect(six.status, isA<WaitingForBoth>());
        expect(
          await app.escrow.rateOfBond(app.record, bondQuote),
          isA<Ok<WalletRateCheck?, BondPayRefusal>>().having(
            (ok) => ok.value,
            'value',
            isNull,
          ),
        );
        expect(app.wallet.ratesAsked, isEmpty);
      },
    );
  });

  group('a taker buyer\'s payout', () {
    test(
      'the rule applies to a taker buyer: its terms as taken, never a seller\'s, and nothing read to find them',
      () async {
        final buyer = await _App.start();
        final usecase = CheckPayoutRateUsecase(buyer.app.reader, buyer.wallet);
        final terms = await usecase.termsOf(buyer.record);
        expect(terms, isA<TakerPayoutTerms>());
        expect(switch (terms) {
          final TakerPayoutTerms taken => taken.currency.code,
          _ => null,
        }, 'USD');
        final seller = await _App.start(seller: true);
        expect(
          await CheckPayoutRateUsecase(
            seller.app.reader,
            seller.wallet,
          ).termsOf(seller.record),
          isNull,
        );
        expect(buyer.wallet.ratesAsked, isEmpty);
        expect(seller.wallet.ratesAsked, isEmpty);
      },
    );

    test(
      'at 6, the payout of a price 20 % too high (112,165 sats against 134,834) warns; « Confirm … sent » at 9 after a restart compares the coordinator\'s figure of now, said as such',
      () async {
        final buyer = await _App.start(sats: 112362);
        final six = await buyer.locked();
        final usecase = CheckPayoutRateUsecase(buyer.app.reader, buyer.wallet);
        final memory = PayoutRateMemory();
        PayoutRateCubit cubitOf(PayoutRateMemory memory) => PayoutRateCubit(
          buyer.record,
          terms: usecase.termsOf,
          price: usecase.priceOf,
          memory: memory,
          now: () => buyer.app.now,
        );
        final cubit = cubitOf(memory);
        addTearDown(cubit.close);
        await cubit.show(six, appeared: true);
        await buyer.app.settle();
        expect(
          cubit.state,
          isA<PayoutRateChecked>()
              .having((s) => s.basis, 'basis', const PayoutRateAskedNow())
              .having(
                (s) => s.check,
                'check',
                isA<WalletRateAtWallet>()
                    .having((c) => c.asked, 'asked', Sats.fromInt(112165))
                    .having((c) => c.expected, 'expected', Sats.fromInt(134834))
                    .having((c) => c.warns, 'warns', true),
              ),
        );
        expect(PayoutRateCubit.verdictOf(cubit.state), PayoutRateVerdict.warns);
        // The escrow locked and the chat started; the app started again: nothing of the invoice kept.
        buyer.app.coordinator
          ..lockEscrow()
          ..moveTo(9);
        final run = buyer.app.watchOf(buyer.record);
        await buyer.app.elapse(const Duration(seconds: 30));
        await run.subscription.cancel();
        final nine = await buyer.seen();
        expect(nine.status, isA<Chatting>());
        final restarted = cubitOf(PayoutRateMemory());
        addTearDown(restarted.close);
        await restarted.show(nine, appeared: true);
        await buyer.app.settle();
        expect(
          restarted.state,
          isA<PayoutRateChecked>()
              .having((s) => s.basis, 'basis', const PayoutRateToldNow())
              .having(
                (s) => s.check,
                'check',
                isA<WalletRateAtWallet>()
                    .having((c) => c.asked, 'asked', Sats.fromInt(112165))
                    .having((c) => c.warns, 'warns', true),
              ),
        );
      },
    );
  });

  group(
    '#237, for an order taken here (design note `docs/design/phase-3-making-an-order.md` § 3.3 bis)',
    () {
      test(
        'status 15 once the invoice expired: the same red check as at 6 for the same sats; while the coordinator retries, nothing',
        () async {
          final buyer = await _App.start(sats: 112362);
          final six = await buyer.locked();
          final usecase = CheckPayoutRateUsecase(
            buyer.app.reader,
            buyer.wallet,
          );
          PayoutRateCubit cubitOf() => PayoutRateCubit(
            buyer.record,
            terms: usecase.termsOf,
            price: usecase.priceOf,
            memory: PayoutRateMemory(),
            now: () => buyer.app.now,
          );
          final atSix = cubitOf();
          addTearDown(atSix.close);
          await atSix.show(six, appeared: true);
          await buyer.app.settle();
          final check = switch (atSix.state) {
            PayoutRateChecked(check: final WalletRateAtWallet check) => check,
            final other => fail('$other'),
          };
          expect(check.warns, isTrue);
          Future<TradeSeen> read() async {
            final run = buyer.app.watchOf(buyer.record);
            await buyer.app.elapse(const Duration(seconds: 30));
            await run.subscription.cancel();
            return buyer.seen();
          }

          buyer.app.coordinator.lockEscrow();
          for (final status in const [9, 10, 13, 15]) {
            buyer.app.coordinator.moveTo(status);
            await read();
          }
          final retrying = await buyer.seen();
          expect(
            retrying.status,
            isA<RoutingFailed>().having(
              (s) => s.invoiceExpired,
              'expired',
              isFalse,
            ),
          );
          final atFifteen = cubitOf();
          addTearDown(atFifteen.close);
          await atFifteen.show(retrying, appeared: true);
          await buyer.app.settle();
          expect(atFifteen.state, isA<PayoutRateNone>());
          buyer.app.coordinator.payoutExpired = true;
          final fifteen = await read();
          expect(
            fifteen.status,
            isA<RoutingFailed>().having(
              (s) => s.invoiceExpired,
              'expired',
              isTrue,
            ),
          );
          await atFifteen.show(fifteen);
          await buyer.app.settle();
          expect(
            atFifteen.state,
            isA<PayoutRateChecked>().having(
              (s) => s.check,
              'check',
              isA<WalletRateAtWallet>()
                  .having((c) => c.asked, 'asked', Sats.fromInt(112165))
                  .having((c) => c.expected, 'expected', check.expected)
                  .having((c) => c.gapHundredths, 'gap', check.gapHundredths)
                  .having((c) => c.warns, 'warns', true),
            ),
          );
        },
      );

      test(
        'a currency the Bull wallet does not price: the « not priced » line alone, never the gap since the order was made, even with the trade\'s sats far from the read the take was made on (the owner\'s decision of 2026-11-24)',
        () async {
          final buyer = await _App.start(rate: const P2pWalletRateNotPriced());
          final six = await buyer.locked();
          final usecase = CheckPayoutRateUsecase(
            buyer.app.reader,
            buyer.wallet,
          );
          final cubit = PayoutRateCubit(
            buyer.record,
            terms: usecase.termsOf,
            price: usecase.priceOf,
            memory: PayoutRateMemory(),
            now: () => buyer.app.now,
          );
          addTearDown(cubit.close);
          await cubit.show(six, appeared: true);
          await buyer.app.settle();
          expect(
            cubit.state,
            isA<PayoutRateChecked>()
                .having((s) => s.check, 'check', isA<WalletRateNotPriced>())
                .having((s) => s.against, 'against', isNull),
          );
          // A take whose sats the coordinator fixed at the bond's lock a quarter below the read the take was made on (the state machine warns of it, `TradePriceOutsideOrder`, and the rule compares nothing beside it): still no gap since « the creation » for a take.
          final other = await _App.start(rate: const P2pWalletRateNotPriced());
          other.app.coordinator.satoshisNow = 100000;
          final moved = await other.locked();
          expect(moved.order?.satoshisNow, Sats.fromInt(100000));
          final terms = await CheckPayoutRateUsecase(
            other.app.reader,
            other.wallet,
          ).termsOf(other.record);
          final taken = switch (terms) {
            final TakerPayoutTerms taken => taken,
            final found => fail('$found'),
          };
          expect(
            CheckPayoutRateUsecase.againstOf(
              taken,
              WalletRateCheck.ofTakerPayout(
                taken.terms,
                received: Sats.fromInt(99825),
                wallet: const P2pWalletRateNotPriced(),
              ),
              moved,
            ),
            isNull,
          );
        },
      );
    },
  );
}
