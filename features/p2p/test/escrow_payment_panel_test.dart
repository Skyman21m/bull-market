import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/presentation/bond_payment_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/trade/bond_payment_panel.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
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

const _holdLine =
    'This is a hold invoice, it will freeze in your wallet. It will be released to the buyer once you confirm to have received the EUR.';
const _heldLine =
    'Until the trade ends, these sats are with the swap service, not in this wallet. If the trade is cancelled, the swap is refunded to Instant payments without the swap fees, and the refund may take time.';

/// Shows the trade screen at [state] with the escrow's panel over [escrow]'s payments (the bond's cubit idle beside it).
Future<(EscrowPaymentCubit, Payments)> _show(
  WidgetTester tester, {
  required String state,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  double textScale = 1,
  Future<Result<CancelOutcome, CancelRefusal>>? cancel,
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
  for (final follows in [bondPayments.follows, payments.follows]) {
    if (follows.isNotEmpty) follows.single.add(const BondPaymentNone());
  }
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
    'the confirmation states the collateral, the fees, the escrow\'s facts and the reference\'s line once; the QR code hidden; nothing paid before its tap',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'six');
      await _confirming(tester, payments);
      expect(
        find.text('Pay 3,207 sats to lock the collateral?'),
        findsOneWidget,
      );
      expect(find.text('Swap fees: 123 sats'), findsOneWidget);
      expect(find.text('Network fee: about 27 sats'), findsOneWidget);
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
          'Swap will be refunded shortly. The swap fees are not refunded.',
        ),
        findsOneWidget,
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
