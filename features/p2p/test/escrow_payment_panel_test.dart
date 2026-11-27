import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/p2p_clock.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/src/p2p_router.dart';
import 'package:p2p/src/presentation/bond_payment_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/trade/bond_payment_panel.dart';
import 'package:p2p/src/ui/trade/pay_confirmation_card.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:robosats/robosats.dart';

import 'bond_payment_cubit_test.dart' show Payments, walletQuote;
import 'support/fakes.dart' show FakeTransport, coordinator, testNow;
import 'support/harness.dart';
import 'support/trade_orders.dart' show tradeNow;
import 'support/trade_screens.dart';

/// « Pay with this wallet » for the seller's escrow at 6 and 7 (#97): the bond's panel in the escrow panel, over the escrow's cubit, with fakes only (never a coordinator, never a swap service, never money).
late Map<String, TradeSeen> _seen;
final _record = TradeScreenStatuses.recordFor(TradeRole.seller);
final _payment = P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash);
late WalletPaymentOffered _offered;

/// The bond's payments of the last screen shown, which a test may follow too.
late Payments _bondPayments;

const _holdLine =
    'This is a hold invoice, it will freeze in your wallet. It will be released to the buyer once you confirm to have received the EUR.';
const _heldLine =
    'Until the trade ends, these sats are with the swap service, not in this wallet. If the trade is cancelled, they come back to Instant payments, less the swap and network fees, sometimes with a delay.';

/// Shows the trade screen at [state] with the escrow's panel over [escrow]'s payments (the bond's cubit idle beside it).
Future<(EscrowPaymentCubit, Payments)> _show(
  WidgetTester tester, {
  required String state,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  double textScale = 1,
  Future<Result<CancelOutcome, CancelRefusal>>? cancel,
  BondPaymentWatch? escrowFound = const BondPaymentNone(),
  InvoiceStep escrowStep = InvoiceStep.escrow,
}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final watch = StreamController<TradeWatchState>.broadcast();
  addTearDown(watch.close);
  final trade = TradeCubit(
    _record,
    (record, {signals = const Stream.empty(), onScreen = true}) {
      signals.listen((_) {});
      return watch.stream;
    },
    (record, seen, {bondLoss}) => cancel ?? (throw StateError('no cancel')),
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
  final bondPayments = Payments();
  final bond = bondPayments.cubit()..start();
  addTearDown(bond.close);
  final payments = Payments()..offer = Ok(_offered);
  final escrow = EscrowPaymentCubit(
    _record,
    payments.balance,
    payments.check,
    payments.quote,
    payments.pay,
    payments.follow,
    (record) => payments.running,
    step: escrowStep,
  )..start();
  addTearDown(escrow.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: testTheme,
      locale: locale,
      localizationsDelegates: P2pLocalizations.localizationsDelegates,
      supportedLocales: P2pLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: trade),
            BlocProvider.value(value: page),
            BlocProvider<BondPaymentCubit>.value(value: bond),
            BlocProvider<EscrowPaymentCubit>.value(value: escrow),
          ],
          child: TradeScreen(
            now: () => tradeNow,
            coordinatorDetails: (_) => throw StateError('not opened'),
            walletPayment: BondPaymentPanel.slotFor,
            walletBond: BondPaymentPanel.bondOf,
            walletBondLine: (_, bondHeld) =>
                BondPaymentLine(bondHeld: bondHeld),
            walletEscrowLine: (_, escrowHeld) =>
                BondPaymentLine(bondHeld: escrowHeld, escrow: true),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  watch.add(
    TradeScreenStatuses.watched(_seen[state] ?? (throw StateError(state))),
  );
  bondPayments.balances.add(Ok(Sats.fromInt(50000)));
  payments.balances.add(Ok(Sats.fromInt(500000)));
  if (bondPayments.follows.isNotEmpty) {
    bondPayments.follows.single.add(const BondPaymentNone());
  }
  // `null`: the escrow's records not answered yet, the panel still looking.
  if (escrowFound != null && payments.follows.isNotEmpty) {
    payments.follows.single.add(escrowFound);
  }
  _bondPayments = bondPayments;
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return (escrow, payments);
}

Future<void> _confirming(WidgetTester tester, Payments payments) async {
  await tester.ensureVisible(find.text('Pay with this wallet'));
  await tester.pump();
  await tester.tap(find.text('Pay with this wallet'));
  await tester.pump();
  payments.quotes.single.complete(Ok(walletQuote()));
  await tester.pump();
  await tester.pump();
  // « Pay » just shown ignores taps for a moment (security review of #291, B1): a user's tap comes later.
  await tester.pump(MovedTapGuard.afterMove);
}

void _follow(Payments payments, P2pWalletPaymentProgress progress) =>
    payments.follows.last.add(BondPaymentFollowed(_payment, progress));

void _expectNothingCut(WidgetTester tester, String reason) {
  expect(tester.takeException(), isNull, reason: reason);
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.descendant(
      of: find.byType(BondPaymentPanel),
      matching: find.byType(RichText),
    ),
  )) {
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '$reason: ${paragraph.text.toPlainText()}',
    );
  }
}

void main() {
  setUpAll(() async {
    final statuses = await TradeScreenStatuses.make(role: TradeRole.seller);
    _seen = {
      'six': await statuses.waitingForBoth(),
      'seven': await statuses.waitingForEscrow(),
      'eight': await statuses.waitingForPayout(),
      'cancelled': await statuses.cancelled(),
      'forfeited': await statuses.bondForfeited(),
      'expired': await statuses.expired(),
    };
    final six = _seen['six'] ?? (throw StateError('six'));
    final offer = walletPaymentFor(
      accepted: Sats.fromInt(10000000),
      status: six.status,
      step: InvoiceStep.escrow,
      now: tradeNow,
    );
    _offered = offer as WalletPaymentOffered;
  });

  for (final state in ['six', 'seven']) {
    testWidgets(
      'at $state: the balance and « Pay with this wallet » above the escrow\'s QR code; nothing quoted on opening',
      (tester) async {
        final (_, payments) = await _show(tester, state: state);
        expect(
          find.text('Instant payments: 500,000 sats available'),
          findsOneWidget,
        );
        expect(find.text('Pay with this wallet'), findsOneWidget);
        expect(payments.quotes, isEmpty);
        expect(find.byType(QrImageView), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Pay with this wallet')).dy,
          lessThan(tester.getTopLeft(find.byType(QrImageView)).dy),
        );
        expect(find.text(_holdLine), findsOneWidget);
      },
    );
  }

  testWidgets(
    'at 8, the line of the swap service from the payments followed: the collateral when its payment of this wallet is held, the bond and the collateral once the bond\'s is too, nothing without either (#207)',
    (tester) async {
      await _show(tester, state: 'eight', size: const Size(390, 1600));
      expect(find.textContaining('swap service'), findsNothing);
      await _show(
        tester,
        state: 'eight',
        size: const Size(390, 1600),
        escrowFound: BondPaymentFollowed(
          _payment,
          const P2pWalletPaymentPending(),
        ),
      );
      expect(
        find.text(
          'Your collateral was paid with this wallet: once returned, it comes back through the swap service, less its fees, after a delay.',
        ),
        findsOneWidget,
      );
      _follow(_bondPayments, const P2pWalletPaymentPending());
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Your bond and collateral were paid with this wallet: once returned, they come back through the swap service, less its fees, after a delay.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'at 8, a payment of the collateral by this wallet being refunded, then refunded: said as a condition, never « Your collateral was paid with this wallet » (review of #208, C1)',
    (tester) async {
      for (final progress in const [
        P2pWalletPaymentRefundPending(),
        P2pWalletPaymentRefunded(),
      ]) {
        await _show(
          tester,
          state: 'eight',
          size: const Size(390, 1600),
          escrowFound: BondPaymentFollowed(_payment, progress),
        );
        expect(
          find.text(
            'A bond or collateral paid with this wallet comes back through the swap service, less its fees, after a delay.',
          ),
          findsOneWidget,
          reason: '$progress',
        );
        expect(
          find.textContaining('collateral was paid with this wallet'),
          findsNothing,
          reason: '$progress',
        );
      }
    },
  );

  testWidgets(
    'the confirmation states the collateral, the fees, the escrow\'s facts and the reference\'s line once; the QR code hidden; nothing paid before its tap',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'six');
      await _confirming(tester, payments);
      // The lean card on arrival (#250): « Collateral », never « Bond », the fees together, the total; the escrow's facts and the reference's line in the detail, once.
      String row(Key key) => [
        for (final text in tester.widgetList<Text>(
          find.descendant(of: find.byKey(key), matching: find.byType(Text)),
        ))
          text.data ?? '',
      ].join(' | ');
      expect(row(PayConfirmationCard.amountRow), 'Collateral | 3,207 sats');
      expect(
        row(PayConfirmationCard.feesRow),
        'Swap and network fees | 150 sats',
      );
      expect(row(PayConfirmationCard.totalRow), 'Total to pay | 3,357 sats');
      expect(find.text('Bond'), findsNothing);
      expect(find.text(_heldLine), findsNothing);
      expect(find.text(_holdLine), findsNothing);
      await tester.ensureVisible(find.text('Show details'));
      await tester.pump();
      await tester.tap(find.text('Show details'));
      await tester.pump();
      expect(row(PayConfirmationCard.swapFeeRow), 'Swap fees | 123 sats');
      expect(
        row(PayConfirmationCard.networkFeeRow),
        'Network fee (estimate) | 27 sats',
      );
      expect(find.text(_heldLine), findsOneWidget);
      expect(find.text(_holdLine), findsOneWidget);
      expect(find.textContaining('lock your bond'), findsNothing);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Copy to clipboard'), findsNothing);
      expect(payments.accepted, isEmpty);
      final pay = find.widgetWithText(TradeButton, 'Pay 3,357 sats');
      await tester.ensureVisible(pay);
      await tester.pump();
      await tester.tap(pay);
      await tester.pump();
      expect(payments.accepted, hasLength(1));
      expect(find.text('Sending the payment…'), findsOneWidget);
      expect(payments.accepted.single.total.value.toInt(), 3357);
      payments.pays.single.complete(
        const Err(BondPayWalletRefused(P2pWalletServiceUnreachable())),
      );
      await tester.pump();
      await tester.pump();
    },
  );

  testWidgets(
    '« Go back » leaves the confirmation, nothing paid, the QR code back',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'six');
      await _confirming(tester, payments);
      await tester.ensureVisible(find.text('Go back'));
      await tester.pump();
      await tester.tap(find.text('Go back'));
      await tester.pump();
      expect(payments.accepted, isEmpty);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text(_holdLine), findsOneWidget);
    },
  );

  testWidgets(
    'sent: the escrow\'s line, the QR code and the copy not offered again',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'six');
      await _confirming(tester, payments);
      await tester.tap(find.text('Pay 3,357 sats'));
      await tester.pump();
      payments.pays.single.complete(Ok(_payment));
      await tester.pump();
      await tester.pump();
      _follow(payments, const P2pWalletPaymentPending());
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Payment sent. Waiting for Temple of Sats to see the collateral locked.',
        ),
        findsOneWidget,
      );
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Copy to clipboard'), findsNothing);
      expect(find.text('Pay with this wallet'), findsNothing);
    },
  );

  testWidgets(
    'a refusal of the swap service\'s maximum: said with its figure, the QR code offered, the wallet still offered',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'six');
      await tester.ensureVisible(find.text('Pay with this wallet'));
      await tester.pump();
      await tester.tap(find.text('Pay with this wallet'));
      await tester.pump();
      payments.quotes.single.complete(
        Err(
          BondPayWalletRefused(
            P2pWalletOverMaximum(maximum: Sats.fromInt(100000)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Amount above maximum swap limit: 100,000 sats'),
        findsOneWidget,
      );
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Pay with this wallet'), findsOneWidget);
      expect(payments.accepted, isEmpty);
    },
  );

  testWidgets(
    'a broadcast whose outcome is unknown is never said sent: « may have been sent », the QR code not offered',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'six');
      _follow(payments, const P2pWalletPaymentBroadcastUnknown());
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'The payment may have been sent. Its status will update shortly.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Payment sent.'), findsNothing);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Pay with this wallet'), findsNothing);
    },
  );

  testWidgets(
    'a swap failed after its funds left: the escrow\'s words, support named',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'six');
      _follow(payments, const P2pWalletPaymentFailed(P2pWalletFunds.sent));
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Swap failed. The sats of this collateral left this wallet. Contact Bull Bitcoin support.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '« Cancel » waits while the escrow\'s payment is sent; once sent, its dialog adds that it is on its way',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'six');
      await _confirming(tester, payments);
      await tester.tap(find.text('Pay 3,357 sats'));
      await tester.pump();
      final cancel = find.widgetWithText(TradeButton, 'Cancel');
      expect(tester.widget<TradeButton>(cancel.last).onPressed, isNull);
      payments.pays.single.complete(Ok(_payment));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<TradeButton>(cancel.last).onPressed, isNotNull);
      await tester.ensureVisible(cancel.last);
      await tester.pump();
      await tester.tap(cancel.last);
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining(
          'A payment of this collateral is on its way from this wallet.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('A payment of this bond is on its way'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'after the escrow\'s step: a refund of the escrow\'s swap is said above the contract, a held one is not',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'eight');
      expect(find.byType(BondPaymentPanel), findsNothing);
      _follow(payments, const P2pWalletPaymentPending());
      await tester.pump();
      await tester.pump();
      expect(find.text('Your swap is in progress.'), findsNothing);
      _follow(payments, const P2pWalletPaymentRefundPending());
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Collateral: Swap will be refunded shortly. The swap fees are not refunded.',
        ),
        findsOneWidget,
      );
    },
  );

  for (final state in ['cancelled', 'forfeited', 'expired']) {
    testWidgets(
      'the trade over ($state): where the escrow\'s swap stands is still said, the escrow returned to the swap service',
      (tester) async {
        final (_, payments) = await _show(tester, state: state);
        expect(find.byType(BondPaymentPanel), findsNothing);
        _follow(payments, const P2pWalletPaymentRefundPending());
        await tester.pump();
        await tester.pump();
        expect(
          find.text(
            'Collateral: Swap will be refunded shortly. The swap fees are not refunded.',
          ),
          findsOneWidget,
        );
        _follow(payments, const P2pWalletPaymentRefunded());
        await tester.pump();
        await tester.pump();
        expect(
          find.text(
            'Collateral: Swap has been refunded. The swap fees are not refunded.',
          ),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'the bond and the escrow both paid from this wallet: each line says whose payment it is, in English and in French',
    (tester) async {
      for (final (locale, bond, escrow) in const [
        (
          Locale('en'),
          'Bond: Swap will be refunded shortly. The swap fees are not refunded.',
          'Collateral: Swap will be refunded shortly. The swap fees are not refunded.',
        ),
        (
          Locale('fr'),
          'Caution : Le swap sera remboursé sous peu. Les frais de swap ne sont pas remboursés.',
          'Garantie : Le swap sera remboursé sous peu. Les frais de swap ne sont pas remboursés.',
        ),
      ]) {
        final (_, payments) = await _show(
          tester,
          state: 'cancelled',
          locale: locale,
        );
        _bondPayments.follows.last.add(
          BondPaymentFollowed(_payment, const P2pWalletPaymentRefundPending()),
        );
        await tester.pump();
        await tester.pump();
        _follow(payments, const P2pWalletPaymentRefundPending());
        await tester.pump();
        await tester.pump();
        expect(find.text(bond), findsOneWidget, reason: '$locale');
        expect(find.text(escrow), findsOneWidget, reason: '$locale');
      }
    },
  );

  testWidgets(
    'the bond alone paid from this wallet: its line as before, not named',
    (tester) async {
      await _show(tester, state: 'cancelled');
      _bondPayments.follows.last.add(
        BondPaymentFollowed(_payment, const P2pWalletPaymentRefundPending()),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Swap will be refunded shortly. The swap fees are not refunded.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Bond: '), findsNothing);
    },
  );

  testWidgets(
    'while the panel looks for an earlier payment of the escrow: no QR code nor copy without a tap on « Pay with another wallet »',
    (tester) async {
      await _show(tester, state: 'six', escrowFound: null);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Copy to clipboard'), findsNothing);
      final other = find.widgetWithText(TradeButton, 'Pay with another wallet');
      expect(other, findsOneWidget);
      await tester.ensureVisible(other);
      await tester.pump();
      await tester.tap(other);
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Copy to clipboard'), findsOneWidget);
    },
  );

  testWidgets(
    'the escrow\'s records unreadable: no QR code without a tap, the reason said',
    (tester) async {
      await _show(
        tester,
        state: 'six',
        escrowFound: const BondPaymentUnreadable(P2pStorageFailure()),
      );
      expect(
        find.text('Bull Market cannot read where this payment stands.'),
        findsOneWidget,
      );
      expect(find.byType(QrImageView), findsNothing);
      expect(
        find.widgetWithText(TradeButton, 'Pay with another wallet'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'an escrow cubit wired to the bond\'s use case offers nothing in the escrow panel',
    (tester) async {
      await _show(tester, state: 'six', escrowStep: InvoiceStep.bond);
      expect(find.byType(BondPaymentPanel), findsNothing);
      expect(find.text('Pay with this wallet'), findsNothing);
      expect(find.byType(QrImageView), findsOneWidget);
    },
  );

  testWidgets(
    'the trade page provides the escrow\'s cubit and its line: a seller\'s escrow returned is said by the escrow\'s line',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 1800) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final watch = StreamController<TradeWatchState>.broadcast();
      addTearDown(watch.close);
      final bondPayments = Payments();
      final escrowPayments = Payments();
      final reads = FakeTransport();
      final locator = GetIt.asNewInstance();
      addTearDown(locator.reset);
      locator
        ..registerSingleton<P2pClock>(P2pClock(() => tradeNow))
        ..registerSingleton<P2pWalletPort>(
          FakeP2pWalletPort(Ok(Sats.fromInt(500000))),
        )
        ..registerFactory<TradeReader>(
          () => throw StateError('the page reads no trade itself'),
        )
        ..registerFactoryParam<TradeCubit, TradeRecord, void>(
          (record, _) => TradeCubit(record, (
            record, {
            signals = const Stream.empty(),
            onScreen = true,
          }) {
            signals.listen((_) {});
            return watch.stream;
          }, (record, seen, {bondLoss}) => throw StateError('no cancel')),
        )
        ..registerFactoryParam<TradeOrderPageCubit, TradeRecord, void>(
          (record, _) => TradeOrderPageCubit(
            coordinator('temple'),
            RobosatsNetwork.mainnet,
            FetchCoordinatorInfoUsecase(CoordinatorClient(reads)).execute,
            FindPublicOrderUsecase(
              CoordinatorClient(reads, clock: () => testNow),
            ).execute,
          ),
        )
        ..registerFactoryParam<BondPaymentCubit, TradeRecord, void>(
          (record, _) => bondPayments.cubit(),
        )
        ..registerFactoryParam<EscrowPaymentCubit, TradeRecord, void>(
          (record, _) => EscrowPaymentCubit(
            record,
            escrowPayments.balance,
            escrowPayments.check,
            escrowPayments.quote,
            escrowPayments.pay,
            escrowPayments.follow,
            (record) => escrowPayments.running,
            step: InvoiceStep.escrow,
          ),
        );
      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          localizationsDelegates: P2pLocalizations.localizationsDelegates,
          supportedLocales: P2pLocalizations.supportedLocales,
          home: Scaffold(
            body: P2pRouter.tradePage(locator, P2pTradeRouteArgs(_record)),
          ),
        ),
      );
      await tester.pump();
      watch.add(
        TradeScreenStatuses.watched(
          _seen['cancelled'] ?? (throw StateError('cancelled')),
        ),
      );
      await tester.pump();
      bondPayments.follows.single.add(const BondPaymentNone());
      escrowPayments.follows.single.add(
        BondPaymentFollowed(_payment, const P2pWalletPaymentRefundPending()),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Collateral: Swap will be refunded shortly. The swap fees are not refunded.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Swap will be refunded shortly. The swap fees are not refunded.',
        ),
        findsNothing,
      );
    },
  );

  group('on a phone of 320 points, the text larger', () {
    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets(
          '${locale.languageCode} at ×$scale: the confirmation, sent, and a refusal are not cut',
          (tester) async {
            final (cubit, payments) = await _show(
              tester,
              state: 'six',
              locale: locale,
              size: const Size(320, 640),
              textScale: scale,
            );
            final six = _seen['six'] ?? (throw StateError('six'));
            unawaited(cubit.ask(six));
            await tester.pump();
            payments.quotes.single.complete(Ok(walletQuote()));
            await tester.pump();
            await tester.pump();
            _expectNothingCut(tester, 'confirmation');
            // The detail open too (#250).
            final show = find.byKey(PayConfirmationCard.detailToggle);
            await tester.ensureVisible(show);
            await tester.pump();
            await tester.tap(show);
            await tester.pump();
            expect(find.byKey(PayConfirmationCard.detail), findsOneWidget);
            _expectNothingCut(tester, 'confirmation, the detail open');
            cubit.dismiss();
            unawaited(cubit.ask(six));
            await tester.pump();
            payments.quotes.last.complete(
              Err(
                BondPayWalletRefused(
                  P2pWalletOverMaximum(maximum: Sats.fromInt(100000)),
                ),
              ),
            );
            await tester.pump();
            await tester.pump();
            _expectNothingCut(tester, 'refusal');
            _follow(payments, const P2pWalletPaymentPending());
            await tester.pump();
            await tester.pump();
            _expectNothingCut(tester, 'sent');
          },
        );
      }
    }
  });
}
