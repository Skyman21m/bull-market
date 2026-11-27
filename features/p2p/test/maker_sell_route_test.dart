import 'dart:async';
import 'dart:convert';

import 'package:bull_ui/bull_ui.dart' show BullTheme;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:p2p/generated/l10n/p2p_localizations.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/repositories/trade_payment_repository.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/ui/create_order_screen.dart';
import 'package:p2p/src/ui/trade/pay_confirmation_card.dart';
import 'package:p2p/src/ui/trade/payout_breakdown_view.dart';
import 'package:p2p/src/ui/trade/payout_panel.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/harness.dart';
import 'support/lean_confirmation.dart';
import 'support/trade_harness.dart' show HarnessKeys, TradeHarness, tradeKey;

/// Making a sell order and running it to its end on the app's real composition (`P2pFeature().route` over `setUpP2pForTesting`), by the user's gestures (#188): « Create », « Sell », the form, « Create order », the maker bond paid with this wallet, the order taken, the collateral of the first take paid with this wallet, the order taken again while the page stays open, the second take's collateral with the alert of the first, a confirmation to make again, « Confirm … received » and its dialog, in English and in French.
///
/// The coordinators are played by [ScriptedMakerCoordinator] (never real ones): one answers every robot's request, the limits and the make, whatever the host, and each coordinator's `/api/info/` is answered under its own alias; the book is empty. The wallet is [FakeP2pWalletPort]: nothing is paid, every quote and payment is the test's.
const _net = RobosatsNetwork.testnet;

/// Texts of the journey in each language, the figures written as the screens write them.
final class _Words {
  final Locale locale;
  final String create;
  final String sell;
  final String addMethod;
  final String addMethodButton;
  final String createOrder;
  final String done;
  final String payWithThisWallet;
  final String payTotal;
  final String newContract;
  final String newContractLine;
  final String feeIncluded;
  final String earlierNotBack;
  final String earlierOut;
  final String bondHeld;
  final String confirmAgain;
  final String confirmAgainLine;
  final String showDetails;
  final String kept;
  final String earlierTitle;
  final String chat;
  final String received;
  final String confirm;
  final String finished;
  final String payoutWaitMaker;
  final String sellSummary;
  final String public;
  final String renew;
  final String collateralBack;

  const _Words({
    required this.locale,
    required this.create,
    required this.sell,
    required this.addMethod,
    required this.addMethodButton,
    required this.createOrder,
    required this.done,
    required this.payWithThisWallet,
    required this.payTotal,
    required this.newContract,
    required this.newContractLine,
    required this.feeIncluded,
    required this.earlierNotBack,
    required this.earlierOut,
    required this.bondHeld,
    required this.confirmAgain,
    required this.confirmAgainLine,
    required this.showDetails,
    required this.kept,
    required this.earlierTitle,
    required this.chat,
    required this.received,
    required this.confirm,
    required this.finished,
    required this.payoutWaitMaker,
    required this.sellSummary,
    required this.public,
    required this.renew,
    required this.collateralBack,
  });

  /// A negative one with the minus sign (U+2212), as the screens write it (#250).
  String sats(int value) => NumberFormat.decimalPattern(
    locale.languageCode,
  ).format(value).replaceFirst('-', '\u2212');
}

const _english = _Words(
  locale: Locale('en'),
  create: 'Create',
  sell: 'Sell',
  addMethod: 'Add custom payment method',
  addMethodButton: 'Add payment method',
  createOrder: 'Create order',
  done: 'Done',
  payWithThisWallet: 'Pay with this wallet',
  payTotal: 'Pay {n} sats',
  newContract: 'New contract',
  newContractLine:
      'The previous take of this order did not go through. This collateral is for the new contract.',
  feeIncluded: 'its fees included',
  earlierNotBack: 'A previous collateral has not come back',
  earlierOut: 'With this one, {b} sats will be out of this wallet.',
  bondHeld:
      'Your order\'s bond was paid with this wallet: it is out of this wallet too until the order ends, and is not in this total.',
  confirmAgain: 'The amounts have changed',
  confirmAgainLine: 'Check them, then confirm again.',
  showDetails: 'Show details',
  kept:
      'The collateral of an earlier take ({a} sats) was kept by {c}: check this order in the official RoboSats app before paying another one.',
  earlierTitle:
      'Collaterals of earlier takes of this order, paid or attempted with this wallet:',
  chat: 'Chat with the buyer',
  received: 'Confirm 100 USD received',
  confirm: 'Confirm',
  finished: 'Trade finished!',
  payoutWaitMaker:
      'For an order you made: if the buyer does not cooperate, your collateral comes back, but your order goes back to the book and your bond stays locked.',
  sellSummary: 'Sell BTC for 100 USD at a 2% premium',
  public: 'Your order is public',
  renew: 'Renew',
  collateralBack:
      'Your collateral was paid with this wallet: once returned, it comes back through the swap service, less its fees, after a delay.',
);

const _french = _Words(
  locale: Locale('fr'),
  create: 'Créer',
  sell: 'Vendre',
  addMethod: 'Ajouter un mode de paiement personnalisé',
  addMethodButton: 'Ajouter un mode de paiement',
  createOrder: 'Créer l’ordre',
  done: 'Fait',
  payWithThisWallet: 'Payer avec ce portefeuille',
  payTotal: 'Payer {n} sats',
  newContract: 'Nouveau contrat',
  newContractLine:
      'La prise précédente de cet ordre n’a pas abouti. Cette garantie vaut pour le nouveau contrat.',
  feeIncluded: 'ses frais compris',
  earlierNotBack: 'Une garantie précédente n’est pas revenue',
  earlierOut: 'Avec celle-ci, {b} sats seront hors de ce portefeuille.',
  bondHeld:
      'La caution de votre ordre a été payée avec ce portefeuille : elle est aussi hors de ce portefeuille jusqu’à la fin de l’ordre, et n’est pas dans ce total.',
  confirmAgain: 'Les montants ont changé',
  confirmAgainLine: 'Vérifiez-les, puis confirmez à nouveau.',
  showDetails: 'Voir le détail',
  kept:
      'La garantie d’une prise précédente ({a} sats) a été encaissée par {c} : vérifiez cet ordre dans l’application officielle RoboSats avant d’en payer une autre.',
  earlierTitle:
      'Garanties des prises précédentes de cet ordre, payées ou tentées avec ce portefeuille :',
  chat: 'Discutez avec l\'acheteur',
  received: 'Confirmer la réception de 100 USD',
  confirm: 'Confirmer',
  finished: 'Échange terminé !',
  payoutWaitMaker:
      'Pour un ordre que vous avez créé : si l’acheteur ne coopère pas, votre garantie revient, mais votre ordre retourne dans le carnet et votre caution reste bloquée.',
  sellSummary: 'Vendre BTC pour 100 USD à une prime de 2 %',
  public: 'Votre ordre est public',
  renew: 'Renouveler',
  collateralBack:
      'Votre garantie a été payée avec ce portefeuille : une fois rendue, elle revient par le service de swap, moins ses frais, après un délai.',
);

/// The coordinators: [maker] for every robot's request, the limits and the make whatever the host; each coordinator's `/api/info/` under its own alias; the book empty (`404` with the reference's `not_found`, `api/views.py:797-801`); the chat refused (`400`), which the chat panel says, as `/api/chat/` is not played.
final class _Coordinators implements CoordinatorTransport {
  final ScriptedMakerCoordinator maker;
  final Map<String, ScriptedMakerCoordinator> _infos = {};

  _Coordinators(this.maker);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async {
    final path = request.url.path;
    if (path.startsWith('/api/book')) {
      return Ok(
        _json(404, {'not_found': 'No orders found, be the first to make one'}),
      );
    }
    if (path.startsWith('/api/chat')) {
      return Ok(_json(400, {'bad_request': 'not played'}));
    }
    if (path == '/api/info/' && request.robot == null) {
      final alias = _aliasOf(request.url.host);
      final info = _infos[alias] ??= ScriptedMakerCoordinator(
        network: _net,
        robots: const [],
        clock: () => DateTime.utc(2026, 11, 20, 9),
        alias: alias,
      );
      return info.send(request);
    }
    return maker.send(request);
  }

  static String _aliasOf(String host) {
    for (final coordinator in Federation.robosats.on(_net)) {
      if (Uri.parse(coordinator.origins(_net).onion ?? '').host == host) {
        return coordinator.shortAlias;
      }
    }
    throw StateError('unknown host');
  }

  static CoordinatorResponse _json(int status, Object body) =>
      CoordinatorResponse(
        statusCode: status,
        headers: const {'content-type': 'application/json'},
        body: utf8.encode(jsonEncode(body)),
      );
}

final class _Journey {
  final WidgetTester tester;
  final GetIt locator;
  final GoRouter router;
  final ScriptedMakerCoordinator coordinator;
  final FakeP2pWalletPort wallet;
  final void Function(Duration) advance;
  final _Words words;

  _Journey(
    this.tester,
    this.locator,
    this.router,
    this.coordinator,
    this.wallet,
    this.advance,
    this.words,
  );

  /// The order made, at the coordinator.
  ScriptedMadeOrder get order => coordinator.orders.values.single;

  /// Pumps frames for [seconds] seconds of the screen's clock, the coordinator's clock moving with it.
  Future<void> pass(int seconds) async {
    for (var i = 0; i < seconds * 4; i++) {
      advance(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  /// Pumps until [finder] finds something, the clocks moving, at most [seconds].
  Future<void> waitFor(Finder finder, {int seconds = 60}) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (finder.evaluate().isNotEmpty) return;
      advance(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }
    fail('never shown: $finder');
  }

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    // A guarded button just shown (« Pay ») ignores taps for a moment (security review of #291, B1): the tap comes later, as a user's.
    if (find
        .ancestor(of: finder, matching: find.byType(MovedTapGuard))
        .evaluate()
        .isNotEmpty) {
      await tester.pump(MovedTapGuard.afterMove);
    }
    await tester.tap(finder);
    await tester.pump();
  }

  /// A quote of [invoice] with 500 sats of swap fees and 27 of network fee.
  P2pWalletQuote quoteOf(Bolt11TestInvoice invoice) {
    final checked = checkedBolt11InvoiceForTesting(
      bolt11: invoice.text,
      amount: invoice.facts.amount,
      network: _net,
      paymentHash: invoice.facts.paymentHash,
      expiresAt: invoice.facts.createdAt.add(invoice.facts.expiry),
      now: invoice.facts.createdAt,
    );
    if (checked == null) fail('not a payable invoice');
    return P2pWalletQuote(
      invoice: checked,
      payin: Sats(checked.amount.value + BigInt.from(500)),
      networkFee: Sats.fromInt(27),
      balance: Sats.fromInt(5000000),
      quotedAt: invoice.facts.createdAt,
    );
  }

  /// The wallet's payment of [invoice], found by the wallet's records at [progress] from now on.
  P2pWalletPayment paidAt(
    Bolt11TestInvoice invoice,
    String id,
    P2pWalletPaymentProgress progress,
  ) {
    final payment = P2pWalletPayment(
      id: id,
      paymentHash: invoice.facts.paymentHash,
    );
    wallet
      ..setFound(
        payment.paymentHash,
        P2pWalletPaymentFound(payment: payment, progress: progress),
      )
      ..setProgress(payment, Ok(progress));
    return payment;
  }

  /// The trade's records of its payments, by step and contract.
  Future<List<(InvoiceStep, int)>> rows(TradeRecord record) async {
    late List<(InvoiceStep, int)> rows;
    await tester.runAsync(() async {
      rows = switch (await locator<TradePaymentRepository>().paymentsOfTrade(
        record,
      )) {
        Ok(:final value) => [for (final row in value) (row.step, row.take)],
        Err(:final failure) => fail('$failure'),
      };
    });
    return rows;
  }

  static Future<_Journey> start(WidgetTester tester, _Words words) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 3200 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FakeSecureStoragePlatform().install();
    var clock = DateTime.utc(2026, 11, 20, 9);
    final coordinator = ScriptedMakerCoordinator(
      network: _net,
      robots: TradeHarness.robotsOf(_net),
      clock: () => clock,
    );
    coordinator.prices[1] = 50000;
    final locator = GetIt.asNewInstance();
    addTearDown(locator.reset);
    final tor = StreamController<P2pTorState>.broadcast();
    addTearDown(tor.close);
    final wallet = FakeP2pWalletPort(Ok(Sats.fromInt(5000000)))
      ..rate = P2pWalletRateRead(50000);
    setUpP2pForTesting(
      locator,
      transport: _Coordinators(coordinator),
      torStates: () => tor.stream,
      clock: () => clock,
      garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      wallet: wallet,
      robotKeys: HarnessKeys(),
      bolt11Decoder: coordinator.decoder,
    );
    final router = GoRouter(
      initialLocation: P2pFeature.path,
      routes: [const P2pFeature().route(locator, network: (_) => _net)],
    );
    final journey = _Journey(
      tester,
      locator,
      router,
      coordinator,
      wallet,
      (by) => clock = clock.add(by),
      words,
    );
    final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    await tester.runAsync(
      () async => (
        await locator<GarageKeyRepository>().import(_net, tradeKey),
        await locator<RobotBindingRepository>().recordGeneratedKey(
          _net,
          fingerprint,
        ),
      ),
    );
    await tester.pumpWidget(routerHarness(router, locale: words.locale));
    tor.add(P2pTorState.ready);
    await settle(tester);
    await settle(tester);
    return journey;
  }

  /// « Create », « Sell », 100 USD, « Revolut » as a custom method, 2 %, « Create order », « Done »: the trade of the order made, at its maker bond.
  Future<void> makeSellOrder({bool buy = false}) async {
    Finder inForm(Finder finder) =>
        find.descendant(of: find.byType(CreateOrderScreen), matching: finder);
    await tap(find.text(words.create));
    await settle(tester);
    expect(find.byType(CreateOrderScreen), findsOneWidget);
    await tap(
      inForm(
        find.text(
          buy
              ? (words.locale.languageCode == 'en' ? 'Buy' : 'Acheter')
              : words.sell,
        ),
      ),
    );
    await tester.enterText(inForm(find.byType(TextField)).at(0), '100');
    await settle(tester);
    await tap(inForm(find.byTooltip(words.addMethod)));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Revolut');
    await tester.pump();
    await tap(find.text(words.addMethodButton));
    await settle(tester);
    await tester.enterText(inForm(find.byType(TextField)).at(1), '2');
    await settle(tester);
    if (!buy) expect(inForm(find.text(words.sellSummary)), findsOneWidget);
    await tap(inForm(find.text(words.createOrder)));
    await settle(tester);
    await tap(find.text(words.done));
    await waitFor(find.textContaining('PUBL'), seconds: 20);
  }

  /// The order made by [makeSellOrder], its maker bond locked from another wallet, taken by robot 5 at the coordinator's price now: at 6, the collateral asked, « Pay with this wallet » offered.
  Future<void> toFirstTake() async {
    await makeSellOrder();
    coordinator.lockMakerBond(order.id);
    await waitFor(find.textContaining(words.public), seconds: 20);
    coordinator.take(order.id, TradeHarness.robotsOf(_net)[5]);
    await waitFor(find.text(words.payWithThisWallet), seconds: 60);
  }

  /// « Pay with this wallet » for the collateral shown, quoted as [quoteOf] quotes it: the confirmation open.
  Future<P2pWalletQuote> openConfirmation() async {
    final escrow = order.escrow ?? fail('no escrow invoice');
    final walletQuote = quoteOf(escrow);
    wallet.scriptQuote(Ok(walletQuote));
    await tap(find.text(words.payWithThisWallet));
    await settle(tester);
    // « Pay » just shown ignores taps for a moment (security review of #291, B1).
    await tester.pump(MovedTapGuard.afterMove);
    return walletQuote;
  }

  /// The confirmation's « Pay {total} sats » for [walletQuote].
  Finder payOf(P2pWalletQuote walletQuote) => find.widgetWithText(
    TradeButton,
    words.payTotal.replaceAll(
      '{n}',
      words.sats(walletQuote.total.value.toInt()),
    ),
  );

  /// The order back in the book (the buyer gave no payout) and taken again a minute later by robot 4.
  void takenAgain() {
    coordinator.backToBook(order.id);
    advance(const Duration(minutes: 1));
    coordinator.take(order.id, TradeHarness.robotsOf(_net)[4]);
  }

  /// The trade shown, as its screen's cubit holds it.
  TradeRecord get record => BlocProvider.of<TradeCubit>(
    find.byType(TradeScreen).evaluate().single,
  ).state.record;

  /// [record]'s coordinator as the panel names it.
  String coordinatorNameOf(TradeRecord record) =>
      Federation.robosats.byAlias(record.coordinatorAlias)?.longAlias ??
      record.coordinatorAlias;

  /// The trade's coordinator as the panel names it.
  String get coordinatorName =>
      Federation.robosats.byAlias(record.coordinatorAlias)?.longAlias ??
      record.coordinatorAlias;
}

void main() {
  for (final words in [_english, _french]) {
    testWidgets(
      '${words.locale}: a sell order from « Create » to « Confirm … received », the bond and two collaterals paid with this wallet, the second after the alert of the first and a confirmation made again',
      (tester) async {
        final journey = await _Journey.start(tester, words);
        await journey.makeSellOrder();
        final order = journey.order;
        expect(order.type, 1);
        // The maker bond, paid with this wallet from its panel at 0.
        final bond = order.bond ?? fail('no bond invoice');
        journey.wallet.scriptQuote(Ok(journey.quoteOf(bond)));
        await journey.waitFor(find.text(words.payWithThisWallet), seconds: 10);
        await journey.tap(find.text(words.payWithThisWallet));
        await settle(tester);
        final bondTotal = bond.facts.amount.value.toInt() + 527;
        journey.wallet.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-bond',
              paymentHash: bond.facts.paymentHash,
            ),
          ),
        );
        // The wallet's records hold the payment once it is made: found by the follow that starts at its end.
        journey.paidAt(bond, 'swap-bond', const P2pWalletPaymentPending());
        await journey.tap(
          find.text(words.payTotal.replaceAll('{n}', words.sats(bondTotal))),
        );
        await settle(tester);
        expect(journey.wallet.paid, hasLength(1));
        journey.coordinator.lockMakerBond(order.id);
        await journey.waitFor(find.textContaining(words.public), seconds: 20);

        // Taken: the collateral of the first take, 196,127 sats, quoted 196,654 in all.
        journey.coordinator.take(order.id, TradeHarness.robotsOf(_net)[5]);
        await journey.waitFor(find.text(words.payWithThisWallet), seconds: 60);
        final escrow0 = order.escrow ?? fail('no escrow invoice');
        expect(escrow0.facts.amount, Sats.fromInt(196127));
        journey.wallet.scriptQuote(Ok(journey.quoteOf(escrow0)));
        await journey.tap(find.text(words.payWithThisWallet));
        await settle(tester);
        final pay0 = find.text(
          words.payTotal.replaceAll('{n}', words.sats(196654)),
        );
        expect(pay0, findsOneWidget);
        // The first take: no new contract, no alert, the comparison with the fee said (in the detail, #250).
        expect(find.textContaining(words.newContract), findsNothing);
        expect(find.textContaining(words.feeIncluded), findsNothing);
        await journey.tap(find.text(words.showDetails));
        await settle(tester);
        expect(find.textContaining(words.feeIncluded), findsOneWidget);
        expect(find.textContaining(words.earlierTitle), findsNothing);
        journey.wallet.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-e0',
              paymentHash: escrow0.facts.paymentHash,
            ),
          ),
        );
        final payment0 = journey.paidAt(
          escrow0,
          'swap-e0',
          const P2pWalletPaymentPending(),
        );
        await journey.tap(pay0);
        await settle(tester);
        expect(journey.wallet.paid, hasLength(2));

        // The buyer gives no payout: the escrow returned, the order back in the book and taken again a minute later, the page left open.
        journey.coordinator.backToBook(order.id);
        journey.advance(const Duration(minutes: 1));
        journey.coordinator.take(order.id, TradeHarness.robotsOf(_net)[4]);
        await journey.waitFor(find.text(words.earlierTitle), seconds: 60);
        await journey.waitFor(find.text(words.payWithThisWallet), seconds: 20);
        final escrow1 = order.escrow ?? fail('no second escrow invoice');
        expect(escrow1.facts.paymentHash, isNot(escrow0.facts.paymentHash));
        journey.wallet.scriptQuote(Ok(journey.quoteOf(escrow1)));
        await journey.tap(find.text(words.payWithThisWallet));
        await settle(tester);
        // The confirmation of the second take: a new contract, the red alert in two lines with the total out (the first collateral's sats in the detail, #250), the bond paid with this wallet beside it.
        expect(find.text(words.newContract), findsOneWidget);
        expect(find.text(words.newContractLine), findsOneWidget);
        expect(find.text(words.earlierNotBack), findsOneWidget);
        expect(
          find.text(
            words.earlierOut
                .replaceAll('{a}', words.sats(196654))
                .replaceAll('{b}', words.sats(393308)),
          ),
          findsOneWidget,
        );
        expect(find.text(words.bondHeld), findsOneWidget);
        // Before « Pay », the coordinator keeps the first collateral: under the payment's lock, more is out than confirmed.
        journey.wallet
          ..setFound(
            payment0.paymentHash,
            P2pWalletPaymentFound(
              payment: payment0,
              progress: const P2pWalletPaymentPaid(),
            ),
          )
          ..setProgress(payment0, const Ok(P2pWalletPaymentPaid()));
        journey.wallet.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-e1',
              paymentHash: escrow1.facts.paymentHash,
            ),
          ),
        );
        // The screen takes in what the wallet now says, which may move « Pay » (a guarded button ignores taps for a moment after a move, security review of #291): the user taps once it is still.
        await settle(tester);
        await journey.tap(
          find.text(words.payTotal.replaceAll('{n}', words.sats(196654))),
        );
        await settle(tester);
        await settle(tester);
        // Nothing paid: the confirmation again, with the figures now.
        expect(journey.wallet.paid, hasLength(2));
        expect(find.text(words.confirmAgain), findsOneWidget);
        expect(find.text(words.confirmAgainLine), findsOneWidget);
        expect(
          find.text(
            words.kept
                .replaceAll('{a}', words.sats(196654))
                .replaceAll('{c}', journey.coordinatorName),
          ),
          findsOneWidget,
        );
        expect(find.text(words.bondHeld), findsNothing);
        journey.paidAt(escrow1, 'swap-e1', const P2pWalletPaymentPending());
        await journey.tap(
          find.text(words.payTotal.replaceAll('{n}', words.sats(196654))),
        );
        await settle(tester);
        expect(journey.wallet.paid, hasLength(3));
        expect(await journey.rows(journey.record), [
          (InvoiceStep.bond, 0),
          (InvoiceStep.escrow, 0),
          (InvoiceStep.escrow, 1),
        ]);

        // The collateral locked, the buyer's invoice, the chat.
        journey.coordinator.lockEscrow(order.id);
        await journey.waitFor(find.text(words.payoutWaitMaker), seconds: 30);
        // What comes back through the swap service at 8, for a maker seller: the collateral only, the bond staying locked (functional review of #188, R3, P).
        expect(find.text(words.collateralBack), findsOneWidget);
        journey.coordinator.buyerGivesInvoice(order.id);
        await journey.waitFor(find.textContaining(words.chat), seconds: 30);
        journey.coordinator.buyerSentFiat(order.id);
        final received = find.widgetWithText(TradeButton, words.received);
        for (var i = 0; i < 30 * 4; i++) {
          if (received.evaluate().isNotEmpty &&
              tester.widget<TradeButton>(received).onPressed != null) {
            break;
          }
          await journey.pass(1);
        }
        expect(tester.widget<TradeButton>(received).onPressed, isNotNull);
        // Two presses of the button within one frame (a second tap is absorbed by the navigator until the next frame, functional review of #188, C3): one dialog, the reference's, held by the panel's own guard.
        await tester.ensureVisible(received);
        await tester.pump();
        final press = tester.widget<TradeButton>(received).onPressed;
        if (press == null) fail('« Confirm … received » off');
        press();
        press();
        await settle(tester);
        expect(find.byType(Dialog), findsOneWidget);
        expect(journey.coordinator.sellerConfirmations, 0);
        await tester.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text(words.confirm),
          ),
        );
        await journey.waitFor(find.textContaining(words.finished), seconds: 30);
        expect(journey.coordinator.sellerConfirmations, 1);
        expect(journey.order.status, 13);
        // A maker seller is offered « Renew » at 13, where the buyer is still being paid (`TradeBox/index.tsx:602-631`, #185).
        expect(find.text(words.renew), findsOneWidget);
        // « Renew »: the renewal's page with « Sell » kept, and a new sell order made (functional review of #188, R7).
        await journey.tap(find.text(words.renew));
        await settle(tester);
        await settle(tester);
        Finder inForm(Finder finder) => find.descendant(
          of: find.byType(CreateOrderScreen),
          matching: finder,
        );
        await journey.waitFor(
          inForm(find.text(words.sellSummary)),
          seconds: 20,
        );
        await journey.tap(inForm(find.text(words.createOrder)));
        await journey.waitFor(find.textContaining('PUBL'), seconds: 30);
        expect(journey.coordinator.orders, hasLength(2));
        expect(journey.coordinator.orders.values.last.type, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
        await tester.pump(const Duration(seconds: 61));
      },
    );
  }

  testWidgets(
    'a confirmation left open while the order is taken again: said stale, its « Pay » off, nothing paid; « Go back » offers the new take\'s collateral',
    (tester) async {
      final journey = await _Journey.start(tester, _english);
      await journey.toFirstTake();
      final walletQuote = await journey.openConfirmation();
      expect(
        tester.widget<TradeButton>(journey.payOf(walletQuote)).onPressed,
        isNotNull,
      );
      journey.takenAgain();
      const stale = 'The order was taken again meanwhile';
      await journey.waitFor(find.text(stale), seconds: 30);
      expect(
        find.text('This confirmation is no longer valid. Go back.'),
        findsOneWidget,
      );
      // Never with « The amounts have changed ».
      expect(find.text(_english.confirmAgain), findsNothing);
      expect(
        tester.widget<TradeButton>(journey.payOf(walletQuote)).onPressed,
        isNull,
      );
      await tester.tap(journey.payOf(walletQuote), warnIfMissed: false);
      await settle(tester);
      expect(journey.wallet.paid, isEmpty);
      await journey.tap(find.text('Go back'));
      await settle(tester);
      expect(find.text(stale), findsNothing);
      expect(find.text(_english.payWithThisWallet), findsOneWidget);
      expect(await journey.rows(journey.record), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  testWidgets('two quick taps on the confirmation\'s « Pay »: one payment', (
    tester,
  ) async {
    final journey = await _Journey.start(tester, _english);
    await journey.toFirstTake();
    final walletQuote = await journey.openConfirmation();
    final escrow = journey.order.escrow ?? fail('no escrow invoice');
    journey.wallet
      ..scriptPayment(
        Ok(
          P2pWalletPayment(
            id: 'swap-e0',
            paymentHash: escrow.facts.paymentHash,
          ),
        ),
      )
      ..scriptPayment(
        Ok(
          P2pWalletPayment(
            id: 'swap-e0b',
            paymentHash: escrow.facts.paymentHash,
          ),
        ),
      );
    final pay = journey.payOf(walletQuote);
    await tester.ensureVisible(pay);
    await tester.tap(pay);
    await tester.tap(pay, warnIfMissed: false);
    await settle(tester);
    await settle(tester);
    expect(journey.wallet.paid, hasLength(1));
    expect(await journey.rows(journey.record), [(InvoiceStep.escrow, 0)]);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets(
    'a collateral more than 10 % above the contract\'s amount at the Bull wallet\'s price: the comparison and its warning in red, the fee said included, « Pay » still offered',
    (tester) async {
      final journey = await _Journey.start(tester, _english);
      await journey.makeSellOrder();
      journey.coordinator.lockMakerBond(journey.order.id);
      await journey.waitFor(find.textContaining(_english.public), seconds: 20);
      // The coordinator fixes the trade at 40,000 USD/BTC at the take, the Bull wallet's price 50,000.
      journey.coordinator.prices[1] = 40000;
      journey.coordinator.take(
        journey.order.id,
        TradeHarness.robotsOf(_net)[5],
      );
      await journey.waitFor(find.text(_english.payWithThisWallet), seconds: 60);
      final walletQuote = await journey.openConfirmation();
      expect(walletQuote.amount, Sats.fromInt(245159));
      // One red alert in two lines, the mock-up's figures (#250): « Gap against you +25.04% », then both amounts; never « (indicative) ».
      final line = find.text(
        'Bull Wallet expected 196,078 sats, the coordinator asks 245,159.',
      );
      expect(line, findsOneWidget);
      expect(find.text('Gap against you'), findsOneWidget);
      expect(find.text('+25.04%'), findsOneWidget);
      expect(find.text('Gap to the Bull price (indicative)'), findsNothing);
      final colors = Theme.of(tester.element(line)).extension<BullTheme>();
      expect(tester.widget<Text>(line).style?.color, colors?.error);
      expect(
        tester.widget<Text>(find.text('Gap against you')).style?.color,
        colors?.error,
      );
      // Just above the buttons, visible without a tap; the swap service's facts in the detail, under the buttons (functional review of #188, C2).
      expect(
        tester.getTopLeft(line).dy,
        lessThan(tester.getTopLeft(find.text('Go back')).dy),
      );
      expect(find.textContaining('Until the trade ends'), findsNothing);
      await journey.tap(find.text('Show details'));
      await settle(tester);
      // The alert's explanation, in red, in place of the comparison's sentence: never a neutral line of the price beside the alert.
      final explanation = find.text(
        'Bull Wallet redoes the calculation with its own price (50,000 USD/BTC, premium included) and warns you beyond a 10% gap. Check the order before paying.',
      );
      expect(explanation, findsOneWidget);
      expect(tester.widget<Text>(explanation).style?.color, colors?.error);
      expect(
        tester.getTopLeft(find.textContaining('Until the trade ends')).dy,
        greaterThan(tester.getTopLeft(journey.payOf(walletQuote)).dy),
      );
      expect(find.textContaining('come to'), findsNothing);
      expect(find.textContaining('are worth'), findsNothing);
      expect(find.textContaining('A small gap is normal'), findsNothing);
      expect(
        tester.widget<TradeButton>(journey.payOf(walletQuote)).onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  testWidgets(
    'the earlier take\'s collateral: a refund pending held again is an alert; a payment the wallet does not know is « state unknown » and counted not back',
    (tester) async {
      final journey = await _Journey.start(tester, _english);
      await journey.toFirstTake();
      final walletQuote = await journey.openConfirmation();
      final escrow0 = journey.order.escrow ?? fail('no escrow invoice');
      // Paid, its wallet id recorded, but the wallet's records hold no payment of it.
      journey.wallet.scriptPayment(
        Ok(
          P2pWalletPayment(
            id: 'swap-e0',
            paymentHash: escrow0.facts.paymentHash,
          ),
        ),
      );
      await journey.tap(journey.payOf(walletQuote));
      await settle(tester);
      expect(journey.wallet.paid, hasLength(1));
      journey.takenAgain();
      await journey.waitFor(find.text(_english.earlierTitle), seconds: 60);
      const unknown =
          'Take 1: state unknown, this device cannot tell where it stands';
      expect(find.text(unknown), findsOneWidget);
      // Counted not back, in the colour of a collateral not back (security review of #188, M14).
      final palette = Theme.of(
        tester.element(find.text(unknown)),
      ).extension<BullTheme>();
      expect(
        tester.widget<Text>(find.text(unknown)).style?.color,
        palette?.warning,
      );
      await journey.waitFor(find.text(_english.payWithThisWallet), seconds: 20);
      await journey.openConfirmation();
      expect(
        find.text(
          _english.earlierOut
              .replaceAll('{a}', _english.sats(196654))
              .replaceAll('{b}', _english.sats(393308)),
        ),
        findsOneWidget,
      );
      // Beside the alert of the earlier collateral not back, the comparison within the threshold is not drawn, on arrival nor in the detail: an alert speaks alone (security review of #249, C1).
      expect(find.text('Gap to the Bull price (indicative)'), findsNothing);
      await journey.tap(find.text('Show details'));
      await settle(tester);
      expect(find.textContaining(_english.feeIncluded), findsNothing);
      expect(find.textContaining('A small gap is normal'), findsNothing);
      // The earlier collateral's explanation, with its sats.
      expect(
        find.text(
          'You already paid, or tried to pay, a collateral of 196,654 sats for this order with this wallet. It has not come back to it yet.',
        ),
        findsOneWidget,
      );
      expect(journey.wallet.ratesAsked, isNotEmpty);
      await journey.tap(find.text('Go back'));
      await settle(tester);
      // The wallet finds it now, its refund pending, then the coordinator holding it again.
      final payment0 = journey.paidAt(
        escrow0,
        'swap-e0',
        const P2pWalletPaymentRefundPending(),
      );
      await journey.pass(12);
      expect(
        find.text('Take 1: not back yet, the swap service is refunding it'),
        findsOneWidget,
      );
      journey.wallet.setProgress(payment0, const Ok(P2pWalletPaymentPending()));
      await settle(tester);
      expect(
        find.text(
          'The collateral of take 1 was being refunded, and is now held by ${journey.coordinatorName} again: check this order in the official RoboSats app.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  testWidgets(
    'the trade left and opened again between two takes: the earlier collateral\'s sats come from its record (schema 9, #233), exact',
    (tester) async {
      final journey = await _Journey.start(tester, _english);
      await journey.toFirstTake();
      final walletQuote = await journey.openConfirmation();
      final escrow0 = journey.order.escrow ?? fail('no escrow invoice');
      journey.wallet.scriptPayment(
        Ok(
          P2pWalletPayment(
            id: 'swap-e0',
            paymentHash: escrow0.facts.paymentHash,
          ),
        ),
      );
      journey.paidAt(escrow0, 'swap-e0', const P2pWalletPaymentPending());
      await journey.tap(journey.payOf(walletQuote));
      await settle(tester);
      // Left: nothing of the amount is kept in memory since schema 9 (#233), its record holds it; the relaunch of the app itself is `schema9_relaunch_test.dart`'s.
      final record = journey.record;
      await tester.binding.handlePopRoute();
      await settle(tester);
      journey.takenAgain();
      unawaited(
        journey.router.pushNamed(
          P2pRouter.tradeName,
          extra: P2pTradeRouteArgs(record),
        ),
      );
      await journey.waitFor(find.text(_english.payWithThisWallet), seconds: 30);
      await journey.openConfirmation();
      expect(
        find.text(
          _english.earlierOut
              .replaceAll('{a}', _english.sats(196654))
              .replaceAll('{b}', _english.sats(393308)),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('at least'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  testWidgets(
    'the form\'s price check for a seller: a coordinator\'s price too low warns in a seller\'s words; too high warns a buyer, never a seller',
    (tester) async {
      final journey = await _Journey.start(tester, _english);
      // The coordinator's 50,000 against the Bull wallet's 60,000: 16.67 % below.
      journey.wallet.rate = P2pWalletRateRead(60000);
      Finder inForm(Finder finder) =>
          find.descendant(of: find.byType(CreateOrderScreen), matching: finder);
      await journey.tap(find.text(_english.create));
      await settle(tester);
      await journey.tap(inForm(find.text(_english.sell)));
      await tester.enterText(inForm(find.byType(TextField)).at(0), '100');
      await settle(tester);
      await settle(tester);
      expect(
        find.textContaining(
          'your bond would be larger than it should be, and you would lock more sats for your amount when the order is taken',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    },
  );

  testWidgets(
    'the form\'s price check: a coordinator\'s price too high is no warning for a seller, a warning for a buyer',
    (tester) async {
      final journey = await _Journey.start(tester, _english);
      // The coordinator's 50,000 against the Bull wallet's 40,000: 25 % above.
      journey.wallet.rate = P2pWalletRateRead(40000);
      Finder inForm(Finder finder) =>
          find.descendant(of: find.byType(CreateOrderScreen), matching: finder);
      await journey.tap(find.text(_english.create));
      await settle(tester);
      await journey.tap(inForm(find.text(_english.sell)));
      await tester.enterText(inForm(find.byType(TextField)).at(0), '100');
      await settle(tester);
      await settle(tester);
      const compare =
          'For comparison, the Bull wallet\'s indicative price: 40,000 USD/BTC';
      expect(find.textContaining(compare), findsOneWidget);
      expect(find.textContaining('above the Bull wallet\'s'), findsNothing);
      final colors = Theme.of(
        tester.element(find.textContaining(compare)),
      ).extension<BullTheme>();
      expect(
        tester.widget<Text>(find.textContaining(compare)).style?.color,
        isNot(colors?.error),
      );
      await journey.tap(inForm(find.text('Buy')));
      await settle(tester);
      expect(
        find.textContaining(
          'above the Bull wallet\'s: you would receive fewer sats when the order is taken',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    },
  );

  testWidgets(
    'two calls of « Confirm … received » to the screen\'s cubit at once: the second does nothing, the first sends once (functional review of #188, C3)',
    (tester) async {
      final journey = await _Journey.start(tester, _english);
      await journey.toFirstTake();
      journey.coordinator
        ..lockEscrow(journey.order.id)
        ..buyerGivesInvoice(journey.order.id)
        ..buyerSentFiat(journey.order.id);
      final received = find.widgetWithText(TradeButton, _english.received);
      for (var i = 0; i < 40 * 4; i++) {
        if (received.evaluate().isNotEmpty &&
            tester.widget<TradeButton>(received).onPressed != null) {
          break;
        }
        await journey.pass(1);
      }
      final cubit = BlocProvider.of<TradeCubit>(
        find.byType(TradeScreen).evaluate().single,
      );
      final seen = switch (cubit.state.watch) {
        TradeWatchStatus(:final seen) => seen,
        final other => fail('$other'),
      };
      final ended = <String>[];
      unawaited(
        cubit.confirmFiatReceived(seen).then((_) {
          ended.add('first');
        }),
      );
      unawaited(
        cubit.confirmFiatReceived(seen).then((_) {
          ended.add('second');
        }),
      );
      for (var i = 0; i < 40 && ended.length < 2; i++) {
        await settle(tester);
      }
      // The second returned at once, the first action running (`TradeCubit._chatStep`, `actionRunning`).
      expect(ended, ['second', 'first']);
      expect(journey.coordinator.sellerConfirmations, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  testWidgets(
    'the order taken again while the previous take\'s payment is being sent: once it ends, the page left open offers the new take\'s collateral (functional review of #188, R4)',
    (tester) async {
      final journey = await _Journey.start(tester, _english);
      await journey.toFirstTake();
      final walletQuote = await journey.openConfirmation();
      final escrow0 = journey.order.escrow ?? fail('no escrow invoice');
      final hold = Completer<void>();
      journey.wallet
        ..holdPayments = hold.future
        ..scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-e0',
              paymentHash: escrow0.facts.paymentHash,
            ),
          ),
        );
      journey.paidAt(escrow0, 'swap-e0', const P2pWalletPaymentPending());
      await journey.tap(journey.payOf(walletQuote));
      await settle(tester);
      expect(journey.wallet.paid, hasLength(1));
      journey.takenAgain();
      await journey.pass(20);
      hold.complete();
      journey.wallet.holdPayments = null;
      await journey.waitFor(find.text(_english.earlierTitle), seconds: 30);
      // « Pay with this wallet » offered for the new take, not the earlier payment's « Sending… » left on the page.
      final pay = find.widgetWithText(TradeButton, _english.payWithThisWallet);
      for (var i = 0; i < 30 * 4; i++) {
        if (pay.evaluate().isNotEmpty &&
            tester.widget<TradeButton>(pay).onPressed != null &&
            !tester.widget<TradeButton>(pay).busy) {
          break;
        }
        await journey.pass(1);
      }
      expect(tester.widget<TradeButton>(pay).onPressed, isNotNull);
      expect(tester.widget<TradeButton>(pay).busy, isFalse);
      expect(find.text('Sending the payment…'), findsNothing);
      expect(await journey.rows(journey.record), [(InvoiceStep.escrow, 0)]);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  for (final (name, rate, line) in [
    (
      'a currency the Bull wallet does not price',
      const P2pWalletRateNotPriced() as P2pWalletBitcoinRate,
      'not quoted',
    ),
    (
      'the Bull wallet\'s price not read',
      const P2pWalletRateUnavailable() as P2pWalletBitcoinRate,
      'Amount not checked',
    ),
  ]) {
    testWidgets(
      '$name, a coordinator\'s price ten times too low: the confirmation\'s line alone, above the buttons, no gap and no price of the creation; « Pay » offered (security review of #188, C1, R11)',
      (tester) async {
        final journey = await _Journey.start(tester, _english);
        // 5,000 USD/BTC announced before the make and fixed at the take: a collateral ten times too large.
        journey.coordinator.prices[1] = 5000;
        journey.wallet.rate = rate;
        await journey.toFirstTake();
        final walletQuote = await journey.openConfirmation();
        expect(walletQuote.amount, Sats.fromInt(1961274));
        final alert = find.text(line);
        expect(alert, findsOneWidget);
        expect(
          tester.getTopLeft(alert).dy,
          lessThan(tester.getTopLeft(find.text('Go back')).dy),
        );
        // « Amount not checked » in orange; a currency the Bull wallet does not price, the grey « not quoted » line alone (the owner's decision of 2026-11-24, #250).
        final palette = Theme.of(tester.element(alert)).extension<BullTheme>();
        expect(
          tester.widget<Text>(alert).style?.color,
          rate is P2pWalletRateUnavailable
              ? palette?.warning
              : palette?.textMuted,
        );
        expect(
          tester.widget<TradeButton>(journey.payOf(walletQuote)).onPressed,
          isNotNull,
        );
        expect(
          find.widgetWithText(TextButton, 'Retry'),
          rate is P2pWalletRateUnavailable ? findsOneWidget : findsNothing,
        );
        // Nothing of the creation's price nor any gap, on arrival nor in the detail.
        await journey.tap(find.text('Show details'));
        await settle(tester);
        expect(find.text('Gap to the Bull price (indicative)'), findsNothing);
        expect(find.text('Gap against you'), findsNothing);
        expect(
          find.textContaining('from the rate when you made it'),
          findsNothing,
        );
        expect(find.textContaining('5,100'), findsNothing);
        expect(find.textContaining('5,000 USD'), findsNothing);
        expect(find.textContaining('are worth'), findsNothing);
        expect(find.textContaining('come to'), findsNothing);
        expect(find.textContaining('A small gap is normal'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
        await tester.pump(const Duration(seconds: 61));
      },
    );
  }

  testWidgets(
    'the earlier takes\' collaterals stay listed while the screen waits for its first read (security review of #188, R3)',
    (tester) async {
      final journey = await _Journey.start(tester, _english);
      await journey.toFirstTake();
      final walletQuote = await journey.openConfirmation();
      final escrow0 = journey.order.escrow ?? fail('no escrow invoice');
      journey.wallet.scriptPayment(
        Ok(
          P2pWalletPayment(
            id: 'swap-e0',
            paymentHash: escrow0.facts.paymentHash,
          ),
        ),
      );
      journey.paidAt(escrow0, 'swap-e0', const P2pWalletPaymentPending());
      await journey.tap(journey.payOf(walletQuote));
      await settle(tester);
      journey.takenAgain();
      await journey.waitFor(find.text(_english.earlierTitle), seconds: 60);
      final record = journey.record;
      await tester.binding.handlePopRoute();
      await settle(tester);
      // The coordinator now reads the fixed amount otherwise: the page opened again refuses its first read as a whole and waits with the terms' alert (#211).
      journey.coordinator.orderChanges[journey.order.id] = {
        'amount': '1000.00000000',
      };
      unawaited(
        journey.router.pushNamed(
          P2pRouter.tradeName,
          extra: P2pTradeRouteArgs(record),
        ),
      );
      await journey.waitFor(
        find.text('The terms of the order are not those of the order taken.'),
        seconds: 30,
      );
      expect(find.byType(TradeScreen), findsOneWidget);
      expect(find.textContaining('as collateral'), findsNothing);
      expect(find.text(_english.earlierTitle), findsOneWidget);
      expect(
        find.text(
          'Take 1: not back yet, paid by the swap service and held by ${journey.coordinatorNameOf(record)}',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  testWidgets(
    'the order taken again while the earlier take\'s payment is being sent, and that payment refused: the refusal stays said, « Pay with this wallet » offered under it (functional verification of #188, R10)',
    (tester) async {
      final journey = await _Journey.start(tester, _english);
      await journey.toFirstTake();
      final walletQuote = await journey.openConfirmation();
      final hold = Completer<void>();
      journey.wallet
        ..holdPayments = hold.future
        ..scriptPayment(const Err(P2pWalletServiceUnreachable()));
      await journey.tap(journey.payOf(walletQuote));
      await settle(tester);
      journey.takenAgain();
      await journey.pass(20);
      hold.complete();
      journey.wallet.holdPayments = null;
      const refusal = 'Swap server is unavailable. Please try again later.';
      await journey.waitFor(find.text(refusal), seconds: 20);
      final pay = find.widgetWithText(TradeButton, _english.payWithThisWallet);
      for (var i = 0; i < 20 * 4; i++) {
        if (pay.evaluate().isNotEmpty &&
            tester.widget<TradeButton>(pay).onPressed != null) {
          break;
        }
        await journey.pass(1);
      }
      expect(tester.widget<TradeButton>(pay).onPressed, isNotNull);
      await journey.pass(20);
      expect(find.text(refusal), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );

  for (final (name, rate, line) in [
    (
      'a currency the Bull wallet does not price',
      const P2pWalletRateNotPriced() as P2pWalletBitcoinRate,
      'The Bull wallet has no price for USD: rate not checked.',
    ),
    (
      'the Bull wallet\'s price not read',
      const P2pWalletRateUnavailable() as P2pWalletBitcoinRate,
      'could not be read: rate not checked.',
    ),
  ]) {
    testWidgets(
      'a maker buyer, $name, a coordinator\'s price ten times too low: before « Submit », before the chat and in « Confirm … sent », the warning line alone, no gap and no price of the creation, each gesture still possible (#234)',
      (tester) async {
        final journey = await _Journey.start(tester, _english);
        // 5,000 USD/BTC announced before the make and fixed at the take: the buyer told 1,960,784 sats for 100 USD at +2 %.
        journey.coordinator.prices[1] = 5000;
        journey.wallet.rate = rate;
        await journey.makeSellOrder(buy: true);
        final order = journey.order;
        expect(order.type, 0);
        journey.coordinator.lockMakerBond(order.id);
        await journey.waitFor(
          find.textContaining(_english.public),
          seconds: 20,
        );
        journey.coordinator.take(order.id, TradeHarness.robotsOf(_net)[5]);
        final generate = find.text('Generate Invoice');
        await journey.waitFor(generate, seconds: 60);

        void unchecked({bool breakdown = false}) {
          // At 6 the payout panel's breakdown says it (#250): « Amount not checked » or the grey « not quoted » line, no banner above it; at 9 the rule's line.
          if (breakdown) {
            expect(find.textContaining(line), findsNothing);
            expect(
              find.text(
                rate is P2pWalletRateUnavailable
                    ? 'Amount not checked'
                    : 'not quoted',
              ),
              findsOneWidget,
            );
          } else {
            expect(find.textContaining(line), findsWidgets);
          }
          expect(
            find.textContaining('from the rate when you made it'),
            findsNothing,
          );
          expect(find.textContaining('5,100'), findsNothing);
          expect(find.textContaining('are worth'), findsNothing);
        }

        // Before « Submit » (6): the alert alone.
        await journey.pass(2);
        unchecked(breakdown: true);
        expect(
          find.text('Retry'),
          rate is P2pWalletRateUnavailable ? findsOneWidget : findsNothing,
        );
        // « Submit » still possible: the wallet's invoice of the sats asked, less the reference's routing budget.
        final payout = _halfEven(
          order.lastSatoshis -
              order.lastSatoshis * journey.coordinator.makerFee,
        );
        final asked = (payout - payout * 1000 / 1000000).truncate();
        final now = journey.coordinator.clock();
        final invoice = Bolt11TestInvoice(
          network: Bolt11Network.testnet,
          sats: asked,
          seed: 77,
          createdAt: now,
          expiry: const Duration(hours: 24),
          description: 'Bull wallet payout',
        );
        journey.coordinator.decoder.add(invoice);
        journey.wallet.scriptInvoice(
          Ok(
            P2pWalletInvoice(
              bolt11: invoice.text,
              amount: Sats.fromInt(asked),
              expiresAt: now.add(const Duration(hours: 24)),
              received: Sats.fromInt(asked),
            ),
          ),
        );
        await journey.tap(generate);
        await settle(tester);
        final before = journey.coordinator.requests.length;
        await journey.tap(find.widgetWithText(TradeButton, 'Submit'));
        await journey.pass(5);
        // « Submit » sent the invoice to the coordinator. The tests' coordinator checks its clear signature against the key it kept for the robot, which the fake robot keys of this composition do not sign for (« The PGP signed cleartext message is not valid »): the invoice is then taken as the coordinator takes one given from another app, 6 → 7 (`api/logics.py:907-933`).
        expect(
          [
            for (final request in journey.coordinator.requests.skip(before))
              utf8.decode(request.body ?? const []),
          ].where((body) => body.contains('update_invoice')),
          hasLength(1),
        );
        // The invoice sent is the wallet's own, clear-signed in the request's body (security review of #234, R5).
        expect(
          [
            for (final request in journey.coordinator.requests.skip(before))
              utf8.decode(request.body ?? const []),
          ].where(
            (body) =>
                body.contains('update_invoice') && body.contains(invoice.text),
          ),
          hasLength(1),
        );
        order
          ..payoutHash = invoice.facts.paymentHash
          ..status = 7;
        await journey.waitFor(
          find.textContaining('Your info looks good!'),
          seconds: 30,
        );
        // The seller locks the escrow: 9, before the chat, the alert alone.
        journey.coordinator.lockEscrow(order.id);
        final sent = find.widgetWithText(TradeButton, 'Confirm 100 USD sent');
        await journey.waitFor(sent, seconds: 30);
        await journey.pass(2);
        unchecked();
        expect(
          find.text('Retry'),
          rate is P2pWalletRateUnavailable ? findsOneWidget : findsNothing,
        );
        // « Confirm … sent » and its dialog: the alert alone; « Confirm » sends.
        for (var i = 0; i < 20 * 4; i++) {
          if (tester.widget<TradeButton>(sent).onPressed != null) break;
          await journey.pass(1);
        }
        await journey.tap(sent);
        await settle(tester);
        await settle(tester);
        final dialog = find.byType(Dialog);
        expect(dialog, findsOneWidget);
        expect(
          find.descendant(of: dialog, matching: find.textContaining(line)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.textContaining('from the rate when you made it'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: dialog, matching: find.textContaining('5,100')),
          findsNothing,
        );
        await tester.tap(
          find.descendant(of: dialog, matching: find.text('Confirm')),
        );
        await journey.waitFor(
          find.textContaining('Wait for the seller to confirm'),
          seconds: 30,
        );
        expect(journey.order.status, 10);
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
        await tester.pump(const Duration(seconds: 61));
      },
    );
  }

  for (final (name, rate) in [
    (
      'a currency the Bull wallet does not price',
      const P2pWalletRateNotPriced() as P2pWalletBitcoinRate,
    ),
    (
      'the Bull wallet\'s price not read',
      const P2pWalletRateUnavailable() as P2pWalletBitcoinRate,
    ),
  ]) {
    testWidgets(
      'a maker seller at 9, $name, a coordinator\'s price ten times too low: no gap from the creation\'s rate nor its price in the chat (functional review of #234, C1)',
      (tester) async {
        final journey = await _Journey.start(tester, _english);
        journey.coordinator.prices[1] = 5000;
        journey.wallet.rate = rate;
        await journey.toFirstTake();
        // The collateral locked from another wallet, the buyer's invoice given: 9.
        journey.coordinator
          ..lockEscrow(journey.order.id)
          ..buyerGivesInvoice(journey.order.id);
        await journey.waitFor(find.textContaining(_english.chat), seconds: 30);
        await journey.pass(12);
        expect(find.textContaining(_english.chat), findsWidgets);
        expect(
          find.textContaining('from the rate when you made it'),
          findsNothing,
        );
        expect(find.textContaining('5,100'), findsNothing);
        expect(find.textContaining('fixed 1,960,784 sats'), findsNothing);
        // « Confirm … received » shown, off at 9 as the reference's.
        expect(
          find.widgetWithText(TradeButton, _english.received),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
        await tester.pump(const Duration(seconds: 61));
      },
    );
  }

  // The lean breakdown of the buyer's payout (#228, #250), on the real route and composition by the user's gestures, a maker buyer, in English and in French: the Bull wallet's price as the coordinator's (within the margin), 20 % below it (the red alert), not read (« Amount not checked », then « Retry »), and a currency it does not price (the « not quoted » line).
  for (final words in [_english, _french]) {
    final l10n = lookupP2pLocalizations(words.locale);
    for (final (name, rate) in [
      (
        'the Bull wallet\'s price as the coordinator\'s',
        P2pWalletRateRead(50000),
      ),
      (
        'the Bull wallet\'s price 20 % below the coordinator\'s',
        P2pWalletRateRead(40000),
      ),
      (
        'the Bull wallet\'s price not read',
        const P2pWalletRateUnavailable() as P2pWalletBitcoinRate,
      ),
      (
        'a currency the Bull wallet does not price',
        const P2pWalletRateNotPriced() as P2pWalletBitcoinRate,
      ),
    ]) {
      testWidgets(
        'a maker buyer at 6, ${words.locale.languageCode}, $name: the lean breakdown on arrival, adding up to the sat, the rule\'s check in it and no banner above; « Show details » opens the detail under the buttons, which do not move; « Generate Invoice » adds the swap fee; « Submit » still offered (#228, #250)',
        (tester) async {
          final journey = await _Journey.start(tester, words);
          journey.wallet.rate = rate;
          await journey.makeSellOrder(buy: true);
          final order = journey.order;
          journey.coordinator.lockMakerBond(order.id);
          await journey.waitFor(find.textContaining(words.public), seconds: 20);
          journey.coordinator.take(order.id, TradeHarness.robotsOf(_net)[5]);
          final generate = find.text(l10n.p2pPayoutWalletGenerateInvoice);
          await journey.waitFor(generate, seconds: 60);
          await journey.pass(2);
          String row(Key key) => [
            for (final text in tester.widgetList<Text>(
              find.descendant(of: find.byKey(key), matching: find.byType(Text)),
            ))
              text.data ?? '',
          ].last;
          Color? colourOf(Key key) => tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byKey(key),
                  matching: find.byType(Text),
                ),
              )
              .last
              .style
              ?.color;
          final theme = Theme.of(
            tester.element(find.byKey(PayoutBreakdownView.givenRow)),
          ).extension<BullTheme>();
          final last = order.lastSatoshis;
          final payout = _halfEven(last - last * journey.coordinator.makerFee);
          final asked = (payout - payout * 1000 / 1000000).truncate();
          // On arrival: the sats paid, the routing fees (no invoice of this wallet yet) and what will be received, their difference to the sat.
          expect(find.text(l10n.p2pPayoutBreakdownTitle), findsOneWidget);
          expect(row(PayoutBreakdownView.givenRow), words.sats(payout));
          expect(find.text(l10n.p2pPayoutBreakdownRoutingFees), findsOneWidget);
          expect(
            row(PayoutBreakdownView.feesRow),
            words.sats(-(payout - asked)),
          );
          expect(row(PayoutBreakdownView.receivedRow), words.sats(asked));
          // The detail is closed: neither what Bull Wallet expected nor « Your invoice ».
          expect(find.byKey(PayoutPanel.detail), findsNothing);
          expect(find.text(l10n.p2pPayoutBreakdownValue), findsNothing);
          expect(find.text(l10n.p2pPayoutBreakdownInvoice), findsNothing);
          // One figure of the invoice at most, never « You receive » beside « Submit invoice for … » (#249's functional review), nor the rule's sentence or banner above the breakdown.
          for (final gone in [
            'You receive',
            'Vous recevez',
            'Submit invoice for',
            'Soumettre la facture pour',
            'At the Bull wallet\'s price',
            'Au prix du portefeuille Bull',
            'rate not checked',
            'taux non vérifié',
          ]) {
            expect(find.textContaining(gone), findsNothing, reason: gone);
          }
          final worth = switch (rate) {
            // 100 USD at the Bull wallet's price with the order's premium of 2 %, rounded down.
            P2pWalletRateRead(:final price) =>
              (100 * 100000000 / (price * 1.02)).floor(),
            _ => null,
          };
          final warns = rate is P2pWalletRateRead && rate.price < 50000;
          switch (rate) {
            case P2pWalletRateRead() when !warns:
              expect(find.text(l10n.p2pPayoutBreakdownGap), findsOneWidget);
              final gap = row(PayoutCheckLines.gapRow);
              expect(gap.startsWith('−'), isTrue, reason: gap);
              expect(colourOf(PayoutCheckLines.gapRow), theme?.text);
              expect(colourOf(PayoutBreakdownView.givenRow), theme?.text);
              expect(find.text(l10n.p2pPayoutBreakdownAgainst), findsNothing);
            case P2pWalletRateRead():
              // The red alert in the breakdown: its bold line in the gap's place, without « (indicative) », the two figures under it, the figure paid in red; no banner above.
              expect(find.text(l10n.p2pPayoutBreakdownGap), findsNothing);
              expect(find.text(l10n.p2pPayoutBreakdownAgainst), findsOneWidget);
              final gap = row(PayoutCheckLines.alertRow);
              expect(gap.startsWith('−'), isTrue, reason: gap);
              expect(colourOf(PayoutCheckLines.alertRow), theme?.error);
              expect(colourOf(PayoutBreakdownView.givenRow), theme?.error);
              expect(colourOf(PayoutBreakdownView.receivedRow), theme?.text);
              expect(
                find.text(
                  l10n.p2pPayoutBreakdownAgainstFigures(
                    words.sats(worth ?? 0),
                    words.sats(payout),
                  ),
                ),
                findsOneWidget,
              );
              expect(find.byKey(PayoutPanel.looseCheck), findsNothing);
            case P2pWalletRateUnavailable():
              expect(
                find.text(l10n.p2pPayoutBreakdownUnverified),
                findsOneWidget,
              );
              expect(
                tester
                    .widget<Text>(find.text(l10n.p2pPayoutBreakdownUnverified))
                    .style
                    ?.color,
                theme?.warning,
              );
              expect(
                find.text(l10n.p2pPayoutBreakdownUnverifiedLine),
                findsOneWidget,
              );
              expect(find.text(l10n.p2pPayoutBreakdownGap), findsNothing);
            case _:
              expect(
                find.text(l10n.p2pPayoutBreakdownGapNotPriced),
                findsOneWidget,
              );
              expect(
                find.text(l10n.p2pPayoutBreakdownNotPriced),
                findsOneWidget,
              );
              expect(colourOf(PayoutCheckLines.notPricedRow), theme?.textMuted);
              expect(find.text(l10n.p2pCommonRetry), findsNothing);
              expect(find.text(l10n.p2pPayoutBreakdownGap), findsNothing);
          }
          // « Show details » in the breakdown's card, under the gap's line, seen on arrival on a phone of 720 × 1280 pixels (the owner's decision of 2026-11-24: the validated mock-up); the detail opens in the card, the buttons moving down; « Hide details » puts everything back.
          final submit = find.widgetWithText(TradeButton, l10n.p2pPayoutSubmit);
          final toggle = find.byKey(PayoutPanel.detailToggle);
          await _expectToggleInCard(tester);
          final before = [
            for (final button in [generate, submit]) tester.getTopLeft(button),
          ];
          await tester.tap(find.text(l10n.p2pDetailShow));
          await tester.pump();
          expect(find.byKey(PayoutPanel.detail), findsOneWidget);
          expect(find.text(l10n.p2pDetailHide), findsOneWidget);
          _expectDetailInCard(tester);
          expect(tester.getTopLeft(generate).dy, greaterThan(before.first.dy));
          expect(toggle, findsOneWidget);
          expect(row(PayoutBreakdownDetail.feeRow), words.sats(last - payout));
          expect(
            row(PayoutBreakdownDetail.budgetRow),
            words.sats(-(payout - asked)),
          );
          expect(row(PayoutBreakdownDetail.invoiceRow), words.sats(asked));
          final small = find.text(l10n.p2pPayoutBreakdownSmallGap);
          switch (rate) {
            case P2pWalletRateRead():
              expect(
                row(PayoutBreakdownDetail.valueRow),
                words.sats(worth ?? 0),
              );
              expect(
                find.text(
                  l10n.p2pPayoutBreakdownPrice(
                    '100',
                    'USD',
                    NumberFormat.decimalPattern(
                      words.locale.languageCode,
                    ).format(rate.price),
                  ),
                ),
                findsOneWidget,
              );
              // « A small gap is normal » beside a comparison within the threshold only, never beside the alert, whose explanation is there instead.
              expect(small, warns ? findsNothing : findsOneWidget);
              expect(
                find.text(
                  l10n.p2pPayoutBreakdownAgainstDetail(
                    words.locale.languageCode == 'en' ? '10%' : '10 %',
                  ),
                ),
                warns ? findsOneWidget : findsNothing,
              );
            case P2pWalletRateUnavailable():
              expect(find.byKey(PayoutBreakdownDetail.valueRow), findsNothing);
              expect(small, findsNothing);
              expect(
                find.text(l10n.p2pPayoutBreakdownUnverifiedDetail),
                findsOneWidget,
              );
            case _:
              expect(find.byKey(PayoutBreakdownDetail.valueRow), findsNothing);
              expect(small, findsNothing);
              expect(
                find.byKey(PayoutBreakdownDetail.explanation),
                findsNothing,
              );
          }
          await tester.tap(find.text(l10n.p2pDetailHide));
          await tester.pump();
          expect(find.byKey(PayoutPanel.detail), findsNothing);
          expect([
            for (final button in [generate, submit]) tester.getTopLeft(button),
          ], before);
          // « Retry » of « Amount not checked »: the price read again, the gap line in its place.
          if (rate is P2pWalletRateUnavailable) {
            final asks = journey.wallet.ratesAsked.length;
            journey.wallet.rate = P2pWalletRateRead(50000);
            await journey.tap(find.text(l10n.p2pCommonRetry));
            await journey.pass(1);
            expect(journey.wallet.ratesAsked, hasLength(asks + 1));
            expect(find.text(l10n.p2pPayoutBreakdownUnverified), findsNothing);
            expect(find.text(l10n.p2pPayoutBreakdownGap), findsOneWidget);
          }
          // « Generate Invoice »: the swap service's fee joins the fees, what will be received is what reaches the wallet.
          final now = journey.coordinator.clock();
          final invoice = Bolt11TestInvoice(
            network: Bolt11Network.testnet,
            sats: asked,
            seed: 78,
            createdAt: now,
            expiry: const Duration(hours: 24),
            description: 'Bull wallet payout',
          );
          journey.coordinator.decoder.add(invoice);
          journey.wallet.scriptInvoice(
            Ok(
              P2pWalletInvoice(
                bolt11: invoice.text,
                amount: Sats.fromInt(asked),
                expiresAt: now.add(const Duration(hours: 24)),
                received: Sats.fromInt(asked - 187),
              ),
            ),
          );
          await journey.tap(generate);
          await settle(tester);
          expect(find.text(l10n.p2pPayoutBreakdownFees), findsOneWidget);
          expect(
            row(PayoutBreakdownView.feesRow),
            words.sats(-(payout - asked + 187)),
          );
          expect(row(PayoutBreakdownView.receivedRow), words.sats(asked - 187));
          await journey.tap(find.text(l10n.p2pDetailShow));
          await settle(tester);
          expect(row(PayoutBreakdownDetail.swapRow), words.sats(-187));
          expect(row(PayoutBreakdownDetail.invoiceRow), words.sats(asked));
          // Nothing is stopped: « Submit » offered for the wallet's invoice.
          await tester.ensureVisible(submit);
          expect(tester.widget<TradeButton>(submit).onPressed, isNotNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester);
          await tester.pump(const Duration(seconds: 61));
        },
      );
    }
  }

  testWidgets(
    'a maker buyer at 6, fr, a phone of 320 points with the text at three times its size: the lean breakdown, its red alert and its detail open overflow nothing (#250)',
    (tester) async {
      final journey = await _Journey.start(tester, _french);
      tester.view.physicalSize = const Size(320 * 3, 9000 * 3);
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final l10n = lookupP2pLocalizations(_french.locale);
      journey.wallet.rate = P2pWalletRateRead(40000);
      await journey.makeSellOrder(buy: true);
      final order = journey.order;
      journey.coordinator.lockMakerBond(order.id);
      await journey.waitFor(find.textContaining(_french.public), seconds: 20);
      journey.coordinator.take(order.id, TradeHarness.robotsOf(_net)[5]);
      await journey.waitFor(
        find.text(l10n.p2pPayoutWalletGenerateInvoice),
        seconds: 60,
      );
      await journey.pass(2);
      expect(find.text(l10n.p2pPayoutBreakdownAgainst), findsOneWidget);
      expect(tester.takeException(), isNull);
      await journey.tap(find.text(l10n.p2pDetailShow));
      await settle(tester);
      expect(find.byKey(PayoutPanel.detail), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await tester.pump(const Duration(seconds: 61));
    },
  );
  for (final words in const [_english, _french]) {
    final code = words.locale.languageCode;
    group('the lean confirmation of a maker seller\'s collateral (#250), $code', () {
      /// The first take's collateral paid with this wallet and held, the order taken again: the second take's page, before its confirmation.
      Future<(_Journey, P2pWalletQuote)> secondTake(WidgetTester tester) async {
        final journey = await _Journey.start(tester, words);
        await journey.toFirstTake();
        final first = await journey.openConfirmation();
        final escrow0 = journey.order.escrow ?? fail('no escrow invoice');
        journey.wallet.scriptPayment(
          Ok(
            P2pWalletPayment(
              id: 'swap-e0',
              paymentHash: escrow0.facts.paymentHash,
            ),
          ),
        );
        journey.paidAt(escrow0, 'swap-e0', const P2pWalletPaymentPending());
        await journey.tap(journey.payOf(first));
        await settle(tester);
        expect(journey.wallet.paid, isNotEmpty);
        journey.takenAgain();
        await journey.waitFor(find.text(words.earlierTitle), seconds: 60);
        await journey.waitFor(find.text(words.payWithThisWallet), seconds: 20);
        return (journey, first);
      }

      testWidgets(
        'two alerts at once: the earlier collateral not back and « Amount not checked », each in two lines above the buttons, with « New contract »; their explanations in the detail; the buttons still; « Pay » offered',
        (tester) async {
          final (journey, first) = await secondTake(tester);
          journey.wallet.rate = const P2pWalletRateUnavailable();
          final quote = await journey.openConfirmation();
          final lean = LeanConfirmation(tester, words.locale);
          final l10n = lean.l10n;
          lean.expectArrival(quote, escrow: true);
          final block = find.byKey(PayConfirmationCard.earlierBlock);
          expect(
            find.descendant(
              of: block,
              matching: find.text(words.earlierNotBack),
            ),
            findsOneWidget,
          );
          final total = Sats(first.total.value + quote.total.value);
          final out = find.descendant(
            of: block,
            matching: find.text(
              words.earlierOut.replaceAll(
                '{b}',
                words.sats(total.value.toInt()),
              ),
            ),
          );
          expect(out, findsOneWidget);
          lean.expectAboveButtons(out);
          final palette = Theme.of(tester.element(out)).extension<BullTheme>();
          expect(tester.widget<Text>(out).style?.color, palette?.error);
          final unverified = lean.inCard(
            find.text(l10n.p2pPayoutBreakdownUnverifiedLine),
          );
          lean.expectAboveButtons(unverified);
          expect(lean.inCard(find.text(l10n.p2pCommonRetry)), findsOneWidget);
          // « New contract », neutral, beside them.
          final contract = find.descendant(
            of: find.byKey(PayConfirmationCard.newContractBlock),
            matching: find.text(words.newContractLine),
          );
          expect(contract, findsOneWidget);
          expect(tester.widget<Text>(contract).style?.color, palette?.text);
          await lean.toggleDetail(
            quote,
            whileOpen: () {
              expect(find.text(l10n.p2pPayUnverifiedDetail), findsOneWidget);
              expect(
                find.text(
                  l10n.p2pPayEarlierNotBackDetail(
                    words.sats(first.total.value.toInt()),
                  ),
                ),
                findsOneWidget,
              );
              expect(find.byKey(PayConfirmationCard.smallGap), findsNothing);
            },
          );
          expect(
            tester.widget<TradeButton>(lean.payOf(quote)).onPressed,
            isNotNull,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester);
          await tester.pump(const Duration(seconds: 61));
        },
      );

      testWidgets(
        'the « Pay » of a confirmation the screen replaced with « The amounts have changed » pays nothing; the new one\'s « Pay » pays once (functional review of #268, R4)',
        (tester) async {
          final journey = await _Journey.start(tester, words);
          await journey.toFirstTake();
          final first = await journey.openConfirmation();
          final escrow0 = journey.order.escrow ?? fail('no escrow invoice');
          journey.wallet.scriptPayment(
            Ok(
              P2pWalletPayment(
                id: 'swap-e0',
                paymentHash: escrow0.facts.paymentHash,
              ),
            ),
          );
          final payment0 = journey.paidAt(
            escrow0,
            'swap-e0',
            const P2pWalletPaymentPending(),
          );
          await journey.tap(journey.payOf(first));
          await settle(tester);
          journey.takenAgain();
          await journey.waitFor(find.text(words.earlierTitle), seconds: 60);
          await journey.waitFor(
            find.text(words.payWithThisWallet),
            seconds: 20,
          );
          final quote = await journey.openConfirmation();
          final lean = LeanConfirmation(tester, words.locale);
          final escrow1 = journey.order.escrow ?? fail('no second escrow');
          // Before « Pay », the coordinator keeps the first collateral: under the payment's lock, more is out than confirmed.
          journey.wallet
            ..setFound(
              payment0.paymentHash,
              P2pWalletPaymentFound(
                payment: payment0,
                progress: const P2pWalletPaymentPaid(),
              ),
            )
            ..setProgress(payment0, const Ok(P2pWalletPaymentPaid()));
          journey.wallet.scriptPayment(
            Ok(
              P2pWalletPayment(
                id: 'swap-e1',
                paymentHash: escrow1.facts.paymentHash,
              ),
            ),
          );
          final paid = journey.wallet.paid.length;
          // The « Pay » of this confirmation, as drawn: its tap is the one a second, late tap would make.
          final press =
              tester.widget<TradeButton>(lean.payOf(quote)).onPressed ??
              fail('« Pay » off');
          press();
          await settle(tester);
          await settle(tester);
          expect(find.text(lean.l10n.p2pPayConfirmAgainTitle), findsOneWidget);
          expect(journey.wallet.paid, hasLength(paid));
          // The replaced confirmation's « Pay » again: it was drawn for the confirmation before, and pays nothing.
          press();
          await settle(tester);
          await settle(tester);
          expect(journey.wallet.paid, hasLength(paid));
          expect(find.text(lean.l10n.p2pPayConfirmAgainTitle), findsOneWidget);
          // The new confirmation's own « Pay »: it pays once.
          journey.paidAt(escrow1, 'swap-e1', const P2pWalletPaymentPending());
          await journey.tap(lean.payOf(quote));
          await settle(tester);
          expect(journey.wallet.paid, hasLength(paid + 1));
          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester);
          await tester.pump(const Duration(seconds: 61));
        },
      );

      testWidgets(
        'a confirmation left open while the order is taken again: « The order was taken again meanwhile » in red above the buttons, « Pay » not offered and paying nothing, never « The amounts have changed »',
        (tester) async {
          final journey = await _Journey.start(tester, words);
          await journey.toFirstTake();
          final quote = await journey.openConfirmation();
          final lean = LeanConfirmation(tester, words.locale);
          final l10n = lean.l10n;
          journey.takenAgain();
          final title = find.text(l10n.p2pPayConfirmStaleTitle);
          await journey.waitFor(title, seconds: 30);
          final line = find.text(l10n.p2pPayConfirmStaleLine);
          expect(line, findsOneWidget);
          lean.expectAboveButtons(line);
          final palette = Theme.of(tester.element(line)).extension<BullTheme>();
          expect(tester.widget<Text>(line).style?.color, palette?.error);
          expect(find.text(l10n.p2pPayConfirmAgainTitle), findsNothing);
          expect(
            tester.widget<TradeButton>(lean.payOf(quote)).onPressed,
            isNull,
          );
          await tester.tap(lean.payOf(quote), warnIfMissed: false);
          await settle(tester);
          expect(journey.wallet.paid, isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester);
          await tester.pump(const Duration(seconds: 61));
        },
      );
    });
  }
}

/// « Show details » in the breakdown's card, under the rule's lines, and within a phone of 720 × 1280 pixels (360 × 640 points) on arrival, without scrolling (#250, the owner's decision of 2026-11-24).
Future<void> _expectToggleInCard(WidgetTester tester) async {
  final toggle = find.byKey(PayoutPanel.detailToggle);
  expect(
    find.descendant(of: find.byType(PayoutBreakdownView), matching: toggle),
    findsOneWidget,
  );
  final checks = find.descendant(
    of: find.byType(PayoutBreakdownView),
    matching: find.byType(PayoutCheckLines),
  );
  if (checks.evaluate().isNotEmpty) {
    expect(
      tester.getTopLeft(toggle).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(checks).dy),
    );
  }
  // Seen without scrolling on a phone of 720 × 1280 pixels; with an alert's two lines, the tests' font (wider than the app's) wraps them further down, so the arrival with an alert is checked on the captures, drawn with the app's font.
  final alert =
      find.byKey(PayoutCheckLines.alertRow).evaluate().isNotEmpty ||
      find.byKey(PayoutCheckLines.unverifiedRow).evaluate().isNotEmpty;
  if (!alert) {
    final size = tester.view.physicalSize;
    final ratio = tester.view.devicePixelRatio;
    tester.view
      ..physicalSize = const Size(720, 1280)
      ..devicePixelRatio = 2;
    await tester.pump();
    expect(tester.getBottomLeft(toggle).dy, lessThanOrEqualTo(640));
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = ratio;
    await tester.pump();
  }
}

/// The detail open in the breakdown's card, under « Hide details ».
void _expectDetailInCard(WidgetTester tester) {
  final detail = find.byKey(PayoutPanel.detail);
  expect(
    find.descendant(of: find.byType(PayoutBreakdownView), matching: detail),
    findsOneWidget,
  );
  expect(
    tester.getTopLeft(detail).dy,
    greaterThanOrEqualTo(
      tester.getBottomLeft(find.byKey(PayoutPanel.detailToggle)).dy,
    ),
  );
}

/// [value] rounded to the nearest whole number, a half to the even one, as Python's `round` (`Logics.payout_amount`, `api/logics.py:650-669`).
int _halfEven(double value) {
  final floor = value.floorToDouble();
  final rest = value - floor;
  final whole = floor.toInt();
  if (rest > 0.5) return whole + 1;
  if (rest < 0.5) return whole;
  return whole.isEven ? whole : whole + 1;
}
