import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/domain/trade/wallet_rate_check.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/presentation/bond_payment_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/presentation/trade_panel.dart';
import 'package:p2p/src/ui/trade/bond_payment_panel.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:robosats/robosats.dart';

import 'bond_payment_cubit_test.dart' show Payments, walletQuote;
import 'support/fakes.dart' show FakeTransport, coordinator, testNow;
import 'support/harness.dart';
import 'support/maker_orders.dart';
import 'support/trade_harness.dart' show tradeKey;
import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

/// The panel of status 0 of an order made here (#180): the reference's `TradeBox` at 0 for a maker (`TradeBox/index.tsx:379-389`, `Prompts/LockInvoice.tsx`, `CancelButton.tsx`, `Dialogs/CancelOrder.tsx`) in the wallet's look, and the confirmation of « Pay with this wallet » under the owner's payment rule of 2026-11-17, with and without its warning.
///
/// Every status comes from the state machine, from the reference's maker answer (`support/maker_orders.dart`); the wallet's use case is played by [Payments], with the comparison the test gives.

T _some<T>(T? value) => value ?? (throw StateError('missing'));

/// The order made here, as the repository gives it once confirmed.
final _record = TradeRecord(
  robot: RobotSlot(RobosatsNetwork.mainnet, switch (GarageKeyFingerprint.of(
    tradeKey,
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  }, 0),
  coordinatorAlias: 'temple',
  coordinatorOnion: _some(Federation.robosats.byAlias('temple')?.mainnet.onion),
  orderId: tradeOrderId,
  role: TradeRole.buyer,
  origin: TradeOrigin.madeHere,
  takenAt: madeAt,
  confirmedAt: madeAt,
  closedAt: null,
);

late TradeSeen _bondStep;
late WalletPaymentOffered _offered;

/// The maker bond at 0, as the state machine computes it from the reference's first read of the order.
Future<TradeSeen> _makerBondStep() async {
  final invoice = makerBondInvoice();
  final order = await readOrder(makerOrderJson(0, bond: invoice));
  final status = TradeStatus.afterMake(
    TradeOrderRead(order),
    terms: madeTerms(),
    now: tradeNow,
    reader: Bolt11Reader(Bolt11TestDecoder([invoice])),
  );
  return TradeSeen(status, order: order, stored: true);
}

/// The comparison of the quote of the tests ([walletQuote], 3,207 sats) at the wallet's [rate].
WalletRateCheck _rateAt(P2pWalletBitcoinRate rate) =>
    WalletRateCheck.ofMakerBond(
      switch (madeTerms().side) {
        MadeSide(:final maker) => maker,
      },
      asked: Sats.fromInt(3207),
      wallet: rate,
    );

/// Shows the trade screen at the maker bond with the wallet's panel; the comparison [rate] answers each quote.
Future<(BondPaymentCubit, Payments, List<TradeSeen>)> _show(
  WidgetTester tester, {
  Result<WalletRateCheck?, BondPayRefusal>? rate,

  /// When given, the answers of the comparison in order, each read of the price taking the next one (« Retry »).
  List<Completer<Result<WalletRateCheck?, BondPayRefusal>>>? rateReads,
  Locale locale = const Locale('en'),
  Future<Result<CancelOutcome, CancelRefusal>> Function(TradeSeen seen)? cancel,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final watch = StreamController<TradeWatchState>.broadcast();
  addTearDown(watch.close);
  final cancelled = <TradeSeen>[];
  final trade = TradeCubit(
    _record,
    (record, {signals = const Stream.empty(), onScreen = true}) {
      signals.listen((_) {});
      return watch.stream;
    },
    (record, seen, {bondLoss}) {
      cancelled.add(seen);
      return cancel?.call(seen) ?? (throw StateError('no cancel'));
    },
  )..start();
  addTearDown(trade.close);
  final reads = FakeTransport();
  final page = TradeOrderPageCubit(
    coordinator('temple'),
    RobosatsNetwork.mainnet,
    FetchCoordinatorInfoUsecase(CoordinatorClient(reads)).execute,
    FindPublicOrderUsecase(
      CoordinatorClient(reads, clock: () => testNow),
    ).execute,
  );
  addTearDown(page.close);
  final payments = Payments()..offer = Ok(_offered);
  final cubit = BondPaymentCubit(
    _record,
    payments.balance,
    payments.check,
    payments.quote,
    payments.pay,
    payments.follow,
    (record) => payments.running,
    rate: (record, quote) {
      if (rateReads != null) {
        final answer = Completer<Result<WalletRateCheck?, BondPayRefusal>>();
        rateReads.add(answer);
        return answer.future;
      }
      return Future.value(rate ?? const Ok(null));
    },
  )..start();
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: testTheme,
      locale: locale,
      localizationsDelegates: P2pLocalizations.localizationsDelegates,
      supportedLocales: P2pLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: trade),
            BlocProvider.value(value: page),
            BlocProvider.value(value: cubit),
          ],
          child: TradeScreen(
            now: () => tradeNow,
            coordinatorDetails: (_) => throw StateError('not opened'),
            walletPayment: BondPaymentPanel.slotFor,
            walletBond: BondPaymentPanel.bondOf,
            walletBondLine: (_, bondHeld) =>
                BondPaymentLine(bondHeld: bondHeld),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  watch.add(TradeScreenStatuses.watched(_bondStep, of: _record));
  payments.balances.add(Ok(Sats.fromInt(50000)));
  payments.follows.single.add(const BondPaymentNone());
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return (cubit, payments, cancelled);
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// Taps « Pay with this wallet » and gives the quote of the tests: the confirmation then shows.
Future<void> _confirming(WidgetTester tester, Payments payments) async {
  await _reveal(tester, find.text('Pay with this wallet'));
  await tester.tap(find.text('Pay with this wallet'));
  await tester.pump();
  payments.quotes.single.complete(Ok(walletQuote()));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// Opens the confirmation's detail (« Show details », #250).
Future<void> _detail(WidgetTester tester) async {
  await _reveal(tester, find.text('Show details'));
  await tester.tap(find.text('Show details'));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    _bondStep = await _makerBondStep();
    final offer = walletPaymentFor(
      accepted: Sats.fromInt(1000000),
      status: _bondStep.status,
      step: InvoiceStep.bond,
      now: tradeNow,
    );
    if (offer is! WalletPaymentOffered) throw StateError('$offer');
    _offered = offer;
  });

  test(
    'the maker bond at 0 is the bond panel\'s, its reference\'s title and step, a free cancel',
    () {
      expect(_bondStep.status, isA<WaitingForMakerBond>());
      final contract = TradeContract(_bondStep, order: _bondStep.order);
      expect(contract.title, TradeTitle.lockBondToPublish);
      expect(contract.prompt, TradePrompt.lockInvoice);
      expect(contract.titleSats, Sats.fromInt(makerBond));
      expect(contract.step, (1, 5));
      expect(contract.cancel, TradeCancelOffer.free);
      expect(contract.bondLine, TradeBondLine.hide);
    },
  );

  testWidgets(
    'status 0: « Lock 3,207 Sats to PUBLISH order (1/5) », « You are BUYING BTC », the wallet\'s slot over the other wallet, « Copy URL » and « Cancel »',
    (tester) async {
      final (_, payments, _) = await _show(tester);
      expect(
        find.text('Lock 3,207 Sats to PUBLISH order (1/5)'),
        findsOneWidget,
      );
      expect(find.text('You are BUYING BTC'), findsOneWidget);
      expect(find.text('Pay with this wallet'), findsOneWidget);
      expect(find.text('Pay with another wallet'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Pay with this wallet')).dy,
        lessThan(tester.getTopLeft(find.text('Pay with another wallet')).dy),
      );
      await _reveal(tester, find.text('Copy URL'));
      expect(find.text('Copy URL'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // Nothing asked of the swap service nor of the wallet's price on opening.
      expect(payments.quotes, isEmpty);
      // No text names the project's internal name or the swap engine.
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.data ?? '', isNot(contains('Troc')));
        expect(text.data ?? '', isNot(contains('Boltz')));
      }
    },
  );

  testWidgets(
    'the other wallet: the QR code of the maker bond, its copy and the reference\'s hold-invoice sentence, word for word',
    (tester) async {
      await _show(tester);
      await _reveal(tester, find.text('Pay with another wallet'));
      await tester.tap(find.text('Pay with another wallet'));
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Copy to clipboard'), findsOneWidget);
      expect(
        find.text(
          'This is a hold invoice, it will freeze in your wallet. It will be charged only if you cancel or lose a dispute.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '« Cancel » at 0 opens the reference\'s « Cancel the order? »; « Back » sends nothing, « Confirm cancellation » sends the status shown',
    (tester) async {
      final (_, _, cancelled) = await _show(
        tester,
        cancel: (seen) async => Ok(CancelDone(_record, seen)),
      );
      await _reveal(tester, find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel the order?'), findsOneWidget);
      expect(
        find.text(
          'If the order is cancelled now but you already tried to pay the invoice, you might lose your bond.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(cancelled, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm cancellation'));
      await tester.pumpAndSettle();
      expect(cancelled.single.status, isA<WaitingForMakerBond>());
    },
  );

  testWidgets(
    'a cancel answered with the order unchanged: the screen judges by the status it carries, still the bond to lock, never « cancelled » nor « bond returned »',
    (tester) async {
      await _show(
        tester,
        cancel: (seen) async => Ok(CancelDone(_record, seen)),
      );
      await _reveal(tester, find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm cancellation'));
      await tester.pumpAndSettle();
      expect(
        find.text('Lock 3,207 Sats to PUBLISH order (1/5)'),
        findsOneWidget,
      );
      expect(find.text('This order has been cancelled'), findsNothing);
      expect(find.textContaining('returned'), findsNothing);
    },
  );

  testWidgets(
    'a payment of the maker bond sent: the panel says it, and the line of after the bond\'s step is not added at 0',
    (tester) async {
      final (_, payments, _) = await _show(tester);
      payments.follows.last.add(
        const BondPaymentFollowed(
          P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash),
          P2pWalletPaymentSent(),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Payment sent. Waiting for Temple of Sats to see your bond locked.',
        ),
        findsOneWidget,
      );
      expect(find.text('Your swap is in progress.'), findsNothing);
    },
  );

  testWidgets('the « Order » tab at 0: the bond\'s countdown, 300 s', (
    tester,
  ) async {
    await _show(tester);
    await tester.tap(find.text('Order').last);
    await tester.pump();
    expect(find.text('Expires in'), findsOneWidget);
    // Made 30 s before the screen's time, the bond's 300 s: 4 minutes 30 seconds left.
    expect(find.text('0h 04m 30s'), findsOneWidget);
  });

  group('the confirmation under the owner\'s payment rule', () {
    testWidgets(
      'within 10 %: the wallet\'s price, the bond it gives and the gap, no warning; « Pay » pays',
      (tester) async {
        final (_, payments, _) = await _show(
          tester,
          rate: Ok(_rateAt(P2pWalletRateRead(91711.15))),
        );
        await _confirming(tester, payments);
        // On arrival the bond and the gap « (indicative) » (#250); the sentence in the detail, with « A small gap is normal ».
        expect(find.text('Bond'), findsOneWidget);
        expect(find.text('3,207 sats'), findsOneWidget);
        expect(find.text('Gap to the Bull price (indicative)'), findsOneWidget);
        expect(find.text('+0.01%'), findsOneWidget);
        expect(find.text('Gap against you'), findsNothing);
        await _detail(tester);
        expect(
          find.text(
            'At the Bull wallet\'s price, 91,711 EUR/BTC, with the order\'s premium, this bond is worth 3,206 sats. Gap of the invoice: +0.01%.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'A small gap is normal: the coordinator has its own price source.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('beyond a 10% gap'), findsNothing);
        await _reveal(tester, find.text('Pay 3,357 sats'));
        // « Pay » just shown ignores taps for a moment (security review of #291, B1).
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Pay 3,357 sats'));
        await tester.pump();
        expect(payments.pays, hasLength(1));
        payments.pays.single.complete(
          const Ok(P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash)),
        );
        await tester.pump();
        await tester.pump();
      },
    );

    testWidgets(
      'beyond 10 %: the red warning with both amounts, and the user may still pay',
      (tester) async {
        // The wallet's price 110,000: 2,673 sats expected for 3,207 asked, +19.95 %.
        final (_, payments, _) = await _show(
          tester,
          rate: Ok(_rateAt(P2pWalletRateRead(110000))),
        );
        await _confirming(tester, payments);
        // The red alert in two lines, visible on arrival above the buttons (#250): the gap against the user, then both amounts; never « (indicative) ».
        expect(find.text('Gap against you'), findsOneWidget);
        expect(find.text('+19.95%'), findsOneWidget);
        expect(find.text('Gap to the Bull price (indicative)'), findsNothing);
        final warning = find.text(
          'Bull Wallet expected 2,673 sats, the coordinator asks 3,207.',
        );
        expect(warning, findsOneWidget);
        expect(
          tester.widget<Text>(warning).style?.color,
          tester.element(warning).bull.error,
        );
        expect(
          tester.getTopLeft(warning).dy,
          lessThan(tester.getTopLeft(find.text('Go back')).dy),
        );
        // Its explanation in the detail, in red, in place of the comparison's sentence; never « A small gap is normal ».
        await _detail(tester);
        final explanation = find.text(
          'Bull Wallet redoes the calculation with its own price (110,000 EUR/BTC, premium included) and warns you beyond a 10% gap. Check the order before paying.',
        );
        expect(explanation, findsOneWidget);
        expect(
          tester.widget<Text>(explanation).style?.color,
          tester.element(explanation).bull.error,
        );
        expect(find.textContaining('Gap of the invoice'), findsNothing);
        expect(find.textContaining('A small gap is normal'), findsNothing);
        await _reveal(tester, find.text('Pay 3,357 sats'));
        // « Pay » just shown ignores taps for a moment (security review of #291, B1).
        await tester.pump(MovedTapGuard.afterMove);
        final pay = tester.widget<TradeButton>(
          find.ancestor(
            of: find.text('Pay 3,357 sats'),
            matching: find.byType(TradeButton),
          ),
        );
        expect(pay.onPressed, isNotNull);
        await tester.tap(find.text('Pay 3,357 sats'));
        await tester.pump();
        expect(payments.pays, hasLength(1));
        payments.pays.single.complete(
          const Ok(P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash)),
        );
        await tester.pump();
        await tester.pump();
      },
    );

    testWidgets('a favourable gap: shown, no warning', (tester) async {
      final (_, payments, _) = await _show(
        tester,
        rate: Ok(_rateAt(P2pWalletRateRead(80000))),
      );
      await _confirming(tester, payments);
      expect(find.text('−12.77%'), findsOneWidget);
      expect(find.text('Gap to the Bull price (indicative)'), findsOneWidget);
      expect(find.text('Gap against you'), findsNothing);
      await _detail(tester);
      expect(
        find.textContaining('Gap of the invoice: −12.77%'),
        findsOneWidget,
      );
      expect(find.textContaining('beyond a 10% gap'), findsNothing);
      // Beyond 10 % on the side that does not warn: no « small gap » either (functional review of #268, C1).
      expect(find.textContaining('A small gap is normal'), findsNothing);
    });

    testWidgets(
      'a currency the wallet does not price, the price of the creation ten times too low: one line in the warning colour, no figure, no « Retry », and « Pay » still pays',
      (tester) async {
        final lied = switch (madeTerms(price: makerPrice / 10).side) {
          MadeSide(:final maker) => maker,
        };
        final (_, payments, _) = await _show(
          tester,
          rate: Ok(
            WalletRateCheck.ofMakerBond(
              lied,
              asked: Sats.fromInt(3207),
              wallet: const P2pWalletRateNotPriced(),
            ),
          ),
        );
        await _confirming(tester, payments);
        // The grey « not quoted » line alone (the owner's decision of 2026-11-24, #250): no figure, no line naming the coordinator.
        final line = find.text('not quoted');
        expect(line, findsOneWidget);
        expect(find.text('Gap to the Bull price'), findsOneWidget);
        expect(
          tester.widget<Text>(line).style?.color,
          tester.element(line).bull.textMuted,
        );
        await _detail(tester);
        // Nothing reassuring: no price, no expected bond, no gap, not even in the detail.
        expect(find.textContaining('Gap of the invoice'), findsNothing);
        expect(find.textContaining('A small gap is normal'), findsNothing);
        expect(find.textContaining('9,171'), findsNothing);
        expect(find.textContaining('EUR/BTC'), findsNothing);
        expect(find.textContaining('Temple of Sats'), findsNothing);
        expect(find.text('Retry'), findsNothing);
        await _reveal(tester, find.text('Pay 3,357 sats'));
        // « Pay » just shown ignores taps for a moment (security review of #291, B1).
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Pay 3,357 sats'));
        await tester.pump();
        expect(payments.pays, hasLength(1));
        payments.pays.single.complete(
          const Ok(P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash)),
        );
        await tester.pump();
        await tester.pump();
      },
    );

    testWidgets(
      'the reviewer\'s scenario (review of #180, C1): the wallet\'s price unread, a bond ten times too large: no comparison, no price of the creation cited, the line in the warning colour, « Retry », and « Pay » still pays',
      (tester) async {
        final lied = switch (madeTerms(price: makerPrice / 10).side) {
          MadeSide(:final maker) => maker,
        };
        final (_, payments, _) = await _show(
          tester,
          rate: Ok(
            WalletRateCheck.ofMakerBond(
              lied,
              asked: Sats.fromInt(3207),
              wallet: const P2pWalletRateUnavailable(),
            ),
          ),
        );
        await _confirming(tester, payments);
        // « Amount not checked » in orange and its second line, visible on arrival (#250).
        final line = find.text('Amount not checked');
        expect(line, findsOneWidget);
        expect(
          tester.widget<Text>(line).style?.color,
          tester.element(line).bull.warning,
        );
        expect(
          find.text('Bull Wallet could not get its bitcoin price.'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        await _detail(tester);
        expect(
          find.text(
            'Without this price, it cannot compare the coordinator\'s amount. You can try again, or pay without this check.',
          ),
          findsOneWidget,
        );
        // Nothing reassuring: no expected bond, no gap, no price of the creation, not even in the detail.
        expect(find.textContaining('Gap of the invoice'), findsNothing);
        expect(find.textContaining('A small gap is normal'), findsNothing);
        expect(find.textContaining('9,171'), findsNothing);
        expect(find.textContaining('beyond a 10% gap'), findsNothing);
        await _reveal(tester, find.text('Pay 3,357 sats'));
        // « Pay » just shown ignores taps for a moment (security review of #291, B1).
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Pay 3,357 sats'));
        await tester.pump();
        expect(payments.pays, hasLength(1));
        payments.pays.single.complete(
          const Ok(P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash)),
        );
        await tester.pump();
        await tester.pump();
      },
    );

    testWidgets(
      '« Retry » reads the price again for the same quote: the comparison comes, here with its red warning',
      (tester) async {
        final reads = <Completer<Result<WalletRateCheck?, BondPayRefusal>>>[];
        final (_, payments, _) = await _show(tester, rateReads: reads);
        await _confirming(tester, payments);
        reads.single.complete(Ok(_rateAt(const P2pWalletRateUnavailable())));
        await tester.pump();
        await tester.pump();
        await _reveal(tester, find.text('Retry'));
        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(reads, hasLength(2));
        // While it reads: « Retry » waits, « Pay » stays.
        expect(
          tester
              .widget<TextButton>(
                find.ancestor(
                  of: find.text('Retry'),
                  matching: find.byType(TextButton),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(find.text('Pay 3,357 sats'), findsOneWidget);
        reads.last.complete(Ok(_rateAt(P2pWalletRateRead(110000))));
        await tester.pump();
        await tester.pump();
        expect(find.text('Retry'), findsNothing);
        expect(find.text('Gap against you'), findsOneWidget);
        expect(find.text('+19.95%'), findsOneWidget);
        expect(
          find.text(
            'Bull Wallet expected 2,673 sats, the coordinator asks 3,207.',
          ),
          findsOneWidget,
        );
        // The same quote: no second quote asked of the swap service.
        expect(payments.quotes, hasLength(1));
      },
    );

    testWidgets(
      '« Pay » while « Retry » reads: enabled, it pays once, and the late answer of the read is ignored (review of #180, C2)',
      (tester) async {
        final reads = <Completer<Result<WalletRateCheck?, BondPayRefusal>>>[];
        final (cubit, payments, _) = await _show(tester, rateReads: reads);
        await _confirming(tester, payments);
        reads.single.complete(Ok(_rateAt(const P2pWalletRateUnavailable())));
        await tester.pump();
        await tester.pump();
        await _reveal(tester, find.text('Retry'));
        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(reads, hasLength(2));
        final pay = find.ancestor(
          of: find.text('Pay 3,357 sats'),
          matching: find.byType(TradeButton),
        );
        expect(tester.widget<TradeButton>(pay).onPressed, isNotNull);
        await _reveal(tester, find.text('Pay 3,357 sats'));
        // « Pay » just shown ignores taps for a moment (security review of #291, B1).
        await tester.pump(MovedTapGuard.afterMove);
        await tester.tap(find.text('Pay 3,357 sats'));
        await tester.pump();
        expect(payments.pays, hasLength(1));
        expect(cubit.state.step, isA<BondPaySending>());
        // The read answers once the payment left: nothing of it is shown, and nothing more is paid.
        reads.last.complete(Ok(_rateAt(P2pWalletRateRead(110000))));
        await tester.pump();
        await tester.pump();
        expect(cubit.state.step, isA<BondPaySending>());
        expect(find.textContaining('Gap of the invoice'), findsNothing);
        expect(find.text('Gap against you'), findsNothing);
        expect(payments.pays, hasLength(1));
        payments.pays.single.complete(
          const Ok(P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash)),
        );
        await tester.pump();
        await tester.pump();
        expect(payments.pays, hasLength(1));
      },
    );

    testWidgets(
      '« Retry » that fails again: still « rate not checked », « Retry » offered again, « Pay » still offered',
      (tester) async {
        final reads = <Completer<Result<WalletRateCheck?, BondPayRefusal>>>[];
        final (_, payments, _) = await _show(tester, rateReads: reads);
        await _confirming(tester, payments);
        reads.single.complete(Ok(_rateAt(const P2pWalletRateUnavailable())));
        await tester.pump();
        await tester.pump();
        await _reveal(tester, find.text('Retry'));
        await tester.tap(find.text('Retry'));
        await tester.pump();
        reads.last.complete(Ok(_rateAt(const P2pWalletRateUnavailable())));
        await tester.pump();
        await tester.pump();
        expect(find.text('Amount not checked'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(
          tester
              .widget<TextButton>(
                find.ancestor(
                  of: find.text('Retry'),
                  matching: find.byType(TextButton),
                ),
              )
              .onPressed,
          isNotNull,
        );
        expect(find.text('Pay 3,357 sats'), findsOneWidget);
        expect(payments.quotes, hasLength(1));
      },
    );

    testWidgets(
      'a price of the wallet outside the bounds of a price: « rate not checked » as well, never a comparison',
      (tester) async {
        final (_, payments, _) = await _show(
          tester,
          rate: Ok(_rateAt(P2pWalletRateRead(1e15))),
        );
        await _confirming(tester, payments);
        expect(find.text('Amount not checked'), findsOneWidget);
        expect(find.text('Gap to the Bull price (indicative)'), findsNothing);
        await _detail(tester);
        expect(find.textContaining('Gap of the invoice'), findsNothing);
      },
    );

    testWidgets(
      'a price of few units for a bitcoin is shown with its decimals, as the reference\'s « Order current rate »',
      (tester) async {
        final (_, payments, _) = await _show(
          tester,
          rate: Ok(_rateAt(P2pWalletRateRead(33.4567))),
        );
        await _confirming(tester, payments);
        await _detail(tester);
        expect(find.textContaining('33.457 EUR/BTC'), findsOneWidget);
      },
    );

    testWidgets('in French: the warning in the project\'s words', (
      tester,
    ) async {
      final (_, payments, _) = await _show(
        tester,
        rate: Ok(_rateAt(P2pWalletRateRead(110000))),
        locale: const Locale('fr'),
      );
      await _reveal(tester, find.text('Payer avec ce portefeuille'));
      await tester.tap(find.text('Payer avec ce portefeuille'));
      await tester.pump();
      payments.quotes.single.complete(Ok(walletQuote()));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      // The numbers in the French conventions of the locale (its own spaces), the validated words (#250).
      expect(find.text('Écart en votre défaveur'), findsOneWidget);
      expect(find.text('Caution'), findsOneWidget);
      expect(find.textContaining('Bull Wallet attendait 2'), findsOneWidget);
      expect(
        find.textContaining('sats, le coordinateur en demande 3'),
        findsOneWidget,
      );
      await _reveal(tester, find.text('Voir le détail'));
      await tester.tap(find.text('Voir le détail'));
      await tester.pump();
      expect(
        find.textContaining(
          'EUR/BTC, prime comprise) et vous prévient au-delà de 10',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('d’écart. Vérifiez l’ordre avant de payer.'),
        findsOneWidget,
      );
    });
  });

  group('the cubit', () {
    BondPaymentCubit cubitOf(
      Payments payments,
      Future<Result<WalletRateCheck?, BondPayRefusal>> Function() rate,
    ) => BondPaymentCubit(
      _record,
      payments.balance,
      payments.check,
      payments.quote,
      payments.pay,
      payments.follow,
      (record) => null,
      rate: (record, quote) => rate(),
    );

    test(
      'closed while the wallet\'s price is read: nothing emitted after, no error (review of #180, R3)',
      () async {
        final payments = Payments()..offer = Ok(_offered);
        final reading = Completer<Result<WalletRateCheck?, BondPayRefusal>>();
        final cubit = cubitOf(payments, () => reading.future)..start();
        payments.follows.single.add(const BondPaymentNone());
        await pumpEventQueue();
        final steps = <BondPayStep>[];
        final listening = cubit.stream.listen((state) => steps.add(state.step));
        final asking = cubit.ask(_bondStep);
        payments.quotes.single.complete(Ok(walletQuote()));
        await pumpEventQueue();
        expect(cubit.state.step, isA<BondPayQuoting>());
        await cubit.close();
        final before = steps.length;
        reading.complete(Ok(_rateAt(P2pWalletRateRead(110000))));
        await asking;
        await pumpEventQueue();
        expect(steps, hasLength(before));
        expect(steps.whereType<BondPayConfirming>(), isEmpty);
        await listening.cancel();
      },
    );

    test(
      '« Retry »: only for a comparison not made, once at a time, the same quote; a confirmation left meanwhile is not touched',
      () async {
        final payments = Payments()..offer = Ok(_offered);
        final answers = <Completer<Result<WalletRateCheck?, BondPayRefusal>>>[];
        final cubit = cubitOf(payments, () {
          final answer = Completer<Result<WalletRateCheck?, BondPayRefusal>>();
          answers.add(answer);
          return answer.future;
        })..start();
        payments.follows.single.add(const BondPaymentNone());
        await pumpEventQueue();
        final asking = cubit.ask(_bondStep);
        payments.quotes.single.complete(Ok(walletQuote()));
        await pumpEventQueue();
        answers.single.complete(Ok(_rateAt(const P2pWalletRateUnavailable())));
        await asking;
        final retrying = cubit.retryRate();
        unawaited(cubit.retryRate());
        expect(answers, hasLength(2));
        expect(
          cubit.state.step,
          isA<BondPayConfirming>().having(
            (c) => c.retrying,
            'retrying',
            isTrue,
          ),
        );
        // « Go back » while it reads: what the read gives is dropped.
        cubit.dismiss();
        answers.last.complete(Ok(_rateAt(P2pWalletRateRead(110000))));
        await retrying;
        expect(cubit.state.step, isA<BondPayIdle>());
        expect(payments.quotes, hasLength(1));
        await cubit.close();
      },
    );

    test(
      'a « Retry » answered after a new quote and its own comparison: dropped, the new confirmation kept',
      () async {
        final payments = Payments()..offer = Ok(_offered);
        final answers = <Completer<Result<WalletRateCheck?, BondPayRefusal>>>[];
        final cubit = cubitOf(payments, () {
          final answer = Completer<Result<WalletRateCheck?, BondPayRefusal>>();
          answers.add(answer);
          return answer.future;
        })..start();
        payments.follows.single.add(const BondPaymentNone());
        await pumpEventQueue();
        final first = cubit.ask(_bondStep);
        payments.quotes.single.complete(Ok(walletQuote()));
        await pumpEventQueue();
        answers.single.complete(Ok(_rateAt(const P2pWalletRateUnavailable())));
        await first;
        final retrying = cubit.retryRate();
        cubit.dismiss();
        final second = cubit.ask(_bondStep);
        final newQuote = walletQuote();
        payments.quotes.last.complete(Ok(newQuote));
        await pumpEventQueue();
        final fresh = _rateAt(P2pWalletRateRead(91711.15));
        answers.last.complete(Ok(fresh));
        await second;
        // The old « Retry » answers last, with a comparison the new confirmation must not take.
        answers[1].complete(Ok(_rateAt(P2pWalletRateRead(110000))));
        await retrying;
        final step = cubit.state.step;
        expect(step, isA<BondPayConfirming>());
        if (step is BondPayConfirming) {
          expect(step.walletQuote, same(newQuote));
          expect(step.rate, same(fresh));
        }
        await cubit.close();
      },
    );

    test(
      '« Retry » refused by the records: back to the start, the refusal said, nothing paid (review of #180, R10)',
      () async {
        final payments = Payments()..offer = Ok(_offered);
        var reads = 0;
        final cubit = cubitOf(payments, () async {
          reads++;
          return reads == 1
              ? Ok(_rateAt(const P2pWalletRateUnavailable()))
              : const Err(BondPayNotAtBondStep());
        })..start();
        payments.follows.single.add(const BondPaymentNone());
        await pumpEventQueue();
        final asking = cubit.ask(_bondStep);
        payments.quotes.single.complete(Ok(walletQuote()));
        await asking;
        expect(cubit.state.step, isA<BondPayConfirming>());
        await cubit.retryRate();
        expect(reads, 2);
        expect(
          cubit.state.step,
          isA<BondPayIdle>().having(
            (i) => i.refused,
            'refused',
            isA<BondPayNotAtBondStep>(),
          ),
        );
        expect(payments.pays, isEmpty);
        await cubit.close();
      },
    );

    test('« Retry » does nothing on a comparison made', () async {
      final payments = Payments()..offer = Ok(_offered);
      var reads = 0;
      final cubit = cubitOf(payments, () async {
        reads++;
        return Ok(_rateAt(P2pWalletRateRead(91711.15)));
      })..start();
      payments.follows.single.add(const BondPaymentNone());
      await pumpEventQueue();
      final asking = cubit.ask(_bondStep);
      payments.quotes.single.complete(Ok(walletQuote()));
      await asking;
      await cubit.retryRate();
      expect(reads, 1);
      await cubit.close();
    });

    test(
      'the comparison is asked with the quote, and the confirmation carries it',
      () async {
        final payments = Payments()..offer = Ok(_offered);
        final asked = <P2pWalletQuote>[];
        final rate = _rateAt(P2pWalletRateRead(110000));
        final cubit = BondPaymentCubit(
          _record,
          payments.balance,
          payments.check,
          payments.quote,
          payments.pay,
          payments.follow,
          (record) => null,
          rate: (record, quote) async {
            asked.add(quote);
            return Ok(rate);
          },
        )..start();
        payments.follows.single.add(const BondPaymentNone());
        await pumpEventQueue();
        final quote = walletQuote();
        final asking = cubit.ask(_bondStep);
        payments.quotes.single.complete(Ok(quote));
        await asking;
        expect(asked.single, same(quote));
        final step = cubit.state.step;
        expect(step, isA<BondPayConfirming>());
        if (step is BondPayConfirming) {
          expect(step.walletQuote, same(quote));
          expect(step.rate, same(rate));
        }
        await cubit.close();
      },
    );

    test(
      'a comparison refused (the records unreadable): no confirmation, the refusal said, nothing paid',
      () async {
        final payments = Payments()..offer = Ok(_offered);
        final cubit = BondPaymentCubit(
          _record,
          payments.balance,
          payments.check,
          payments.quote,
          payments.pay,
          payments.follow,
          (record) => null,
          rate: (record, quote) async => const Err(BondPayNotAtBondStep()),
        )..start();
        payments.follows.single.add(const BondPaymentNone());
        await pumpEventQueue();
        final asking = cubit.ask(_bondStep);
        payments.quotes.single.complete(Ok(walletQuote()));
        await asking;
        expect(
          cubit.state.step,
          isA<BondPayIdle>().having(
            (i) => i.refused,
            'refused',
            isA<BondPayNotAtBondStep>(),
          ),
        );
        expect(payments.pays, isEmpty);
        await cubit.close();
      },
    );

    test(
      'no comparison for a take: the confirmation as before, with none',
      () async {
        final payments = Payments()..offer = Ok(_offered);
        final cubit = payments.cubit()..start();
        payments.follows.single.add(const BondPaymentNone());
        await pumpEventQueue();
        final asking = cubit.ask(_bondStep);
        payments.quotes.single.complete(Ok(walletQuote()));
        await asking;
        final step = cubit.state.step;
        expect(step, isA<BondPayConfirming>());
        if (step is BondPayConfirming) expect(step.rate, isNull);
        await cubit.close();
      },
    );
  });
}
