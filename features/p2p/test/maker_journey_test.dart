import 'package:p2p/public/p2p_wallet_port.dart';
import 'package:p2p/src/data/trade_payment_repository_impl.dart';
import 'package:p2p/src/domain/coordinator_lottery.dart';
import 'package:p2p/src/domain/robot_host.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_limits_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/bond_payments_in_flight.dart';
import 'package:p2p/src/domain/usecases/trade/check_make_price_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/pay_bond_from_wallet_usecase.dart';
import 'package:p2p/src/presentation/make_order_cubit.dart';
import 'package:p2p/testing.dart' show Bolt11TestInvoice, FakeP2pWalletPort;
import 'package:robosats/robosats.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/payout_from_wallet_usecase.dart';
import 'package:p2p/src/presentation/trade_panel.dart';
import 'package:primitives/primitives.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';

/// An order made here followed by its watch through the panels of #182, over the real records, use cases and state machine, the coordinator played by `ScriptedMakerCoordinator` (never a real one): made, its bond locked from another wallet, public, taken, back in the book, taken again by another robot (a next contract, with a payout invoice of its own), the app killed and opened again at each point; what each read gives the screen is the view of `TradeView.of`.
///
/// The steps from 8 on are a taker's buyer steps of phase 2, whose coordinator the maker's script does not play: they are drawn from the reference's answers in `maker_panels_test.dart`.
void main() {
  T valueOf<T, F extends Failure>(Result<T, F> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  /// The view the trade screen draws after the watch of [record] read the order once, on [harness].
  Future<(TradeContract, TradeSeen)> read(
    MakeHarness harness,
    TradeRecord record,
  ) async {
    final run = harness.watchOf(record);
    await harness.settle();
    final watch = run.lastStatus;
    await run.subscription.cancel();
    final view = TradeView.of(watch);
    if (view is! TradeContract) throw StateError('$view');
    return (view, watch.seen);
  }

  test(
    'made, its bond locked elsewhere, public, taken, back in the book, taken again: each panel, each contract\'s own payout key, after a restart too',
    () async {
      var harness = await MakeHarness.start();
      final made = valueOf(await harness.makeOrder());
      final record = (made as MakeStarted).record;
      expect(record.origin, TradeOrigin.madeHere);

      var (view, seen) = await read(harness, record);
      expect(view.title, TradeTitle.lockBondToPublish);
      expect(view.step, (1, 5));
      expect(view.cancel, TradeCancelOffer.free);

      // The bond paid from another wallet: the coordinator publishes the order.
      harness.coordinator.lockMakerBond(record.orderId);
      (view, seen) = await read(harness, record);
      expect(seen.status, isA<MakerOrderPublic>());
      expect(view.title, TradeTitle.orderPublic);
      expect(view.prompt, TradePrompt.publicWait);
      expect(view.step, (2, 5));
      expect(view.bondLine, TradeBondLine.locked);
      expect(view.cancel, TradeCancelOffer.immediate);
      expect(view.maker, isTrue);

      // The app killed and opened again: the same panel from the stored trail.
      harness = harness.restart();
      (view, seen) = await read(harness, record);
      expect(view.title, TradeTitle.orderPublic);

      // Taken by a seller.
      harness.coordinator.take(record.orderId, harness.robot(4));
      (view, seen) = await read(harness, record);
      expect(seen.status, isA<WaitingForBoth>());
      expect(view.title, TradeTitle.payout);
      expect(view.step, (3, 5));
      expect(view.cancel, TradeCancelOffer.losesBond);
      expect((seen.status as WaitingForBoth).rateGap, isNotNull);
      final firstKey = PayoutFromWalletUsecase.payoutKey(
        valueOf(PayoutAsk.of(record, seen)),
      );
      expect(seen.status.trail.take, 0);

      // The taker did not act: the order back in the book, its bond still locked.
      harness.coordinator.backToBook(record.orderId);
      (view, seen) = await read(harness, record);
      expect(seen.status, isA<MakerOrderPublic>());
      expect((seen.status as MakerOrderPublic).backInBook, isTrue);
      expect(view.title, TradeTitle.orderPublic);
      expect(view.bondLine, TradeBondLine.locked);

      // Taken again later, while the app is closed, by another robot: a next contract, its own payout invoice.
      await harness.elapse(const Duration(minutes: 10));
      harness = harness.restart();
      harness.coordinator.take(record.orderId, harness.robot(5));
      (view, seen) = await read(harness, record);
      expect(seen.status, isA<WaitingForBoth>());
      expect(seen.status.trail.take, 1);
      expect(seen.status.warnings, isEmpty);
      expect(view.title, TradeTitle.payout);
      final nextKey = PayoutFromWalletUsecase.payoutKey(
        valueOf(PayoutAsk.of(record, seen)),
      );
      expect(nextKey, isNot(firstKey));
      expect(nextKey, '$firstKey:1');

      // Opened again: the contract kept.
      harness = harness.restart();
      (view, seen) = await read(harness, record);
      expect(seen.status.trail.take, 1);
    },
  );

  test(
    'expired at 1 untaken: « The order has expired », no step, no cancel',
    () async {
      final harness = await MakeHarness.start();
      final record = (valueOf(await harness.makeOrder()) as MakeStarted).record;
      harness.coordinator
        ..lockMakerBond(record.orderId)
        ..expire(record.orderId);
      final (view, seen) = await read(harness, record);
      expect(seen.status, isA<Expired>());
      expect(view.title, TradeTitle.expired);
      expect(view.step, isNull);
      expect(view.cancel, TradeCancelOffer.none);
    },
  );

  test(
    'from the form to a successful end: made by the form\'s cubit, the bond paid from the wallet, public, taken, the wallet\'s payout invoice given, the escrow locked, « fiat sent », the end, the bond\'s payment followed',
    () async {
      final harness = await MakeHarness.start();
      final eur = RobosatsCurrency.fromId(2) ?? (throw StateError('EUR'));
      final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
        ..rate = const P2pWalletRateUnavailable();
      final client = CoordinatorClient(harness.coordinator);

      // The form: the coordinators listed, the default drawn, its limits read, the make sent from the press.
      final form = MakeOrderCubit(
        harness.network,
        currency: eur,
        listHosts: (network) => RobotHosts(network, [
          RobotHost(harness.host, refusesFirstContacts: false),
        ]),
        fetchInfo: FetchCoordinatorInfoUsecase(client).execute,
        fetchLimits: FetchCoordinatorLimitsUsecase(client).execute,
        make: harness.make.execute,
        hasGarageKey: (_) async => const Ok(true),
        lottery: CoordinatorLottery(() => 0.5),
        now: () => harness.now,
        checkPrice: CheckMakePriceUsecase(wallet).execute,
      );
      addTearDown(form.close);
      await form.start();
      expect(form.state.coordinator, harness.host);
      final seenAtPress = form.seen() ?? (throw StateError('no price'));
      await form.make(
        MakeHarness.request(),
        coordinator: harness.host,
        seen: seenAtPress,
      );
      final record = switch (form.state.progress) {
        MakeMade(:final record) => record,
        final other => throw StateError('not made: $other'),
      };

      // 0: « Pay with this wallet » pays the maker bond.
      final payments = TradePaymentRepositoryImpl(harness.database);
      final payBond = PayBondFromWalletUsecase(
        harness.reader,
        harness.limiter,
        payments,
        wallet,
        harness.locks,
        BondPaymentsInFlight(),
      );
      var (view, seen) = await read(harness, record);
      expect(view.title, TradeTitle.lockBondToPublish);
      final offered = valueOf(await payBond.checkBond(record, seen));
      wallet.scriptQuote(
        Ok(
          P2pWalletQuote(
            invoice: offered.walletInvoice,
            payin: Sats(offered.walletInvoice.amount.value + BigInt.from(120)),
            networkFee: Sats.fromInt(27),
            balance: Sats.fromInt(5000000),
            quotedAt: harness.now,
          ),
        ),
      );
      final quote = valueOf(await payBond.quoteBond(record, seen));
      final payment = P2pWalletPayment(
        id: 'swap-journey',
        paymentHash: quote.invoice.paymentHash,
      );
      wallet.scriptPayment(Ok(payment));
      valueOf(await payBond.payBond(record, accepted: quote));
      expect(wallet.paid, hasLength(1));
      // The swap service's payment locks the hold invoice: the coordinator publishes the order.
      harness.coordinator.lockMakerBond(record.orderId);
      (view, seen) = await read(harness, record);
      expect(view.title, TradeTitle.orderPublic);

      // Taken by a seller: 6, the wallet's payout invoice, « Submit ».
      harness.coordinator.take(record.orderId, harness.robot(4));
      (view, seen) = await read(harness, record);
      expect(view.title, TradeTitle.payout);
      final ask = valueOf(harness.payout.ask(record, seen));
      final budget = RoutingBudgetPpm.referenceDefault;
      final amount = ask.invoiceSatsFor(budget) ?? (throw StateError('none'));
      final made = Bolt11TestInvoice(
        network: Bolt11Network.testnet,
        sats: amount.value.toInt(),
        seed: 77,
        createdAt: harness.now,
        expiry: const Duration(hours: 24),
        description: 'Bull wallet payout',
      );
      harness.coordinator.decoder.add(made);
      wallet.scriptInvoice(
        Ok(
          P2pWalletInvoice(
            bolt11: made.text,
            amount: amount,
            expiresAt: harness.now.add(const Duration(hours: 24)),
            received: amount,
          ),
        ),
      );
      final given = valueOf(
        await PayoutFromWalletUsecase(wallet).invoice(ask, amount),
      );
      expect(
        wallet.invoicesAsked.single.$3,
        PayoutFromWalletUsecase.payoutKey(ask),
      );
      final checked = valueOf(
        harness.payout.check(
          record,
          seen,
          PayoutInvoiceText(given.bolt11, budget: budget),
        ),
      );
      valueOf(await harness.payout.execute(record, checked));
      (view, seen) = await read(harness, record);
      expect(seen.status, isA<WaitingForEscrow>());
      expect(view.title, TradeTitle.infoGood);

      // The seller locks the escrow: 9, « Confirm … sent ».
      harness.coordinator.lockEscrow(record.orderId);
      (view, seen) = await read(harness, record);
      expect(seen.status, isA<Chatting>());
      expect(view.step, (4, 5));
      valueOf(await harness.chat.confirmFiatSent(record, seen));
      (view, seen) = await read(harness, record);
      expect(view.step, (5, 5));

      // The seller confirms: the end, the maker bond returned by the coordinator; the screen says it from the payment's record only.
      harness.coordinator.sellerConfirms(record.orderId);
      (view, seen) = await read(harness, record);
      expect(seen.status, isA<SendingSats>());
      harness.coordinator.buyerPaid(record.orderId);
      (view, seen) = await read(harness, record);
      expect(seen.status, isA<Succeeded>());
      expect(view.title, TradeTitle.finished);
      expect(harness.coordinator.order(record.orderId).bondReturned, isTrue);
      // The hold invoice released, the swap service refunds its payment: what the wallet's records say, and the only thing the screen says the bond's return from.
      wallet.setFound(
        payment.paymentHash,
        P2pWalletPaymentFound(
          payment: payment,
          progress: const P2pWalletPaymentRefunded(),
        ),
      );
      final followed = await payBond.followBond(record).first;
      expect(
        (followed as BondPaymentFollowed).progress,
        isA<P2pWalletPaymentRefunded>(),
      );
      expect(followed.payment.paymentHash, quote.invoice.paymentHash);
    },
  );
}
