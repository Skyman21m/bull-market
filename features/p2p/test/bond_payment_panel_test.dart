import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/presentation/bond_payment_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/trade/bond_payment_panel.dart';
import 'package:p2p/src/ui/trade/pay_confirmation_card.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
import 'package:p2p/src/ui/trade/wallet_payment_section.dart';
import 'package:p2p/src/ui/widgets/moved_tap_guard.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:robosats/robosats.dart';

import 'bond_payment_cubit_test.dart' show Payments, walletQuote;
import 'support/fakes.dart' show FakeTransport, coordinator, testNow;
import 'support/harness.dart';
import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

late Map<String, TradeSeen> _seen;
final _record = TradeScreenStatuses.record;
final _payment = P2pWalletPayment(id: 'swap', paymentHash: testPaymentHash);

/// Shows the trade screen at [state] with the wallet's panel over [payments]; [offered] says whether `walletPaymentFor` offers the wallet.
Future<(BondPaymentCubit, Payments)> _show(
  WidgetTester tester, {
  required String state,
  bool offered = true,
  Result<Sats, P2pWalletRefusal>? balance,
  Locale locale = const Locale('en'),
  Size size = const Size(390, 844),
  DateTime Function()? now,
  Future<Result<CancelOutcome, CancelRefusal>>? cancel,
  BondPayRefusal? notOffered,
  double textScale = 1,
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
      // The signals are listened to, as the watch does, so that the cubit's close completes.
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
  final payments = Payments();
  if (offered) payments.offer = Ok(_offer());
  if (notOffered != null) payments.offer = Err(notOffered);
  final cubit = payments.cubit()..start();
  addTearDown(cubit.close);
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
            BlocProvider.value(value: cubit),
          ],
          child: TradeScreen(
            now: now ?? () => tradeNow,
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
  watch.add(
    TradeScreenStatuses.watched(_seen[state] ?? (throw StateError(state))),
  );
  payments.balances.add(balance ?? Ok(Sats.fromInt(50000)));
  payments.follows.single.add(const BondPaymentNone());
  await tester.pump();
  await tester.pump();
  await tester.pump();
  return (cubit, payments);
}

late WalletPaymentOffered _offered;
TradeSeen _bondSeen() => _seen['bond'] ?? (throw StateError('bond'));
WalletPaymentOffered _offer() => _offered;

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _confirming(WidgetTester tester, Payments payments) async {
  await _reveal(tester, find.text('Pay with this wallet'));
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

void main() {
  setUpAll(() async {
    final statuses = await TradeScreenStatuses.make();
    _seen = {
      'bond': await statuses.bondStep(),
      'six': await statuses.waitingForBoth(),
      'expired': await statuses.expired(),
      'seven': await statuses.waitingForEscrow(),
    };
    final offer = walletPaymentFor(
      accepted: Sats.fromInt(1000000),
      status: _bondSeen().status,
      step: InvoiceStep.bond,
      now: tradeNow,
    );
    _offered = offer as WalletPaymentOffered;
  });

  group('how the bond was paid, for the line of the swap service (#207)', () {
    test('each step of the payment', () {
      for (final (step, paid) in <(BondPayStep, WalletPaidHere)>[
        (const BondPayLooking(), WalletPaidHere.no),
        (const BondPayIdle(), WalletPaidHere.no),
        (const BondPayQuoting(), WalletPaidHere.no),
        (
          const BondPayFollowing(P2pWalletPaymentPreparing()),
          WalletPaidHere.no,
        ),
        (const BondPayFollowing(P2pWalletPaymentSigned()), WalletPaidHere.no),
        (
          const BondPayFollowing(
            P2pWalletPaymentExpired(P2pWalletFunds.notSent),
          ),
          WalletPaidHere.no,
        ),
        // Sent, not yet received by the swap service: the bond may have been locked by another wallet meanwhile (security review of #208, R1).
        (
          const BondPayFollowing(P2pWalletPaymentSent()),
          WalletPaidHere.cannotTell,
        ),
        (const BondPayFollowing(P2pWalletPaymentPending()), WalletPaidHere.yes),
        (
          const BondPayFollowing(P2pWalletPaymentUnderReview()),
          WalletPaidHere.cannotTell,
        ),
        (const BondPayFollowing(P2pWalletPaymentPaid()), WalletPaidHere.yes),
        // A refund does not tell a hold invoice cancelled after its lock from the swap service failing to pay it (review of #208, C1).
        (
          const BondPayFollowing(P2pWalletPaymentRefundPending()),
          WalletPaidHere.cannotTell,
        ),
        (
          const BondPayFollowing(P2pWalletPaymentRefunded()),
          WalletPaidHere.cannotTell,
        ),
        // The wallet's own screens paid it: this wallet still.
        (
          const BondPayPaidElsewhere(P2pWalletPaymentPending()),
          WalletPaidHere.yes,
        ),
        (
          const BondPayPaidElsewhere(P2pWalletPaymentSent()),
          WalletPaidHere.cannotTell,
        ),
        (
          const BondPayPaidElsewhere(P2pWalletPaymentSigned()),
          WalletPaidHere.no,
        ),
        (
          const BondPayFollowing(P2pWalletPaymentBroadcastUnknown()),
          WalletPaidHere.cannotTell,
        ),
        (
          const BondPayFollowing(P2pWalletPaymentFailed(P2pWalletFunds.sent)),
          WalletPaidHere.cannotTell,
        ),
        (const BondPayUnreadable(), WalletPaidHere.cannotTell),
        (const BondPaySending(), WalletPaidHere.cannotTell),
      ]) {
        expect(BondPaymentPanel.paidHereOf(step), paid, reason: '$step');
      }
    });

    testWidgets(
      'at 7, the trade screen\'s line from the payment followed: named once a payment of this wallet is held, said as a condition when the records cannot be read, nothing without one',
      (tester) async {
        const named =
            'Your bond was paid with this wallet: once returned, it comes back through the swap service, less its fees, after a delay.';
        const maybe =
            'A bond paid with this wallet comes back through the swap service, less its fees, after a delay.';
        final (_, payments) = await _show(
          tester,
          state: 'seven',
          offered: false,
        );
        expect(find.textContaining('swap service'), findsNothing);
        // Sent, not yet received by the swap service: a condition only (security review of #208, R1).
        _follow(payments, const P2pWalletPaymentSent());
        await tester.pump();
        await tester.pump();
        expect(find.text(maybe), findsOneWidget);
        expect(find.text(named), findsNothing);
        _follow(payments, const P2pWalletPaymentPending());
        await tester.pump();
        await tester.pump();
        expect(find.text(named), findsOneWidget);
        payments.follows.last.add(
          const BondPaymentUnreadable(P2pStorageFailure()),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text(maybe), findsOneWidget);
        expect(find.text(named), findsNothing);
      },
    );

    testWidgets(
      'at 7, a payment of this wallet being refunded, then refunded: said as a condition, never « Your bond was paid with this wallet », since the bond may have been paid with another wallet after the swap failed (review of #208, C1)',
      (tester) async {
        const named =
            'Your bond was paid with this wallet: once returned, it comes back through the swap service, less its fees, after a delay.';
        const maybe =
            'A bond paid with this wallet comes back through the swap service, less its fees, after a delay.';
        final (_, payments) = await _show(
          tester,
          state: 'seven',
          offered: false,
        );
        for (final progress in const [
          P2pWalletPaymentRefundPending(),
          P2pWalletPaymentRefunded(),
        ]) {
          _follow(payments, progress);
          await tester.pump();
          await tester.pump();
          expect(find.text(maybe), findsOneWidget, reason: '$progress');
          expect(find.text(named), findsNothing, reason: '$progress');
        }
      },
    );
  });

  testWidgets(
    'ready: the balance and « Pay with this wallet » above the other wallet; nothing quoted on opening',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
      expect(
        find.text('Instant payments: 50,000 sats available'),
        findsOneWidget,
      );
      expect(find.text('Pay with this wallet'), findsOneWidget);
      expect(payments.quotes, isEmpty);
      expect(
        tester.getTopLeft(find.text('Pay with this wallet')).dy,
        lessThan(tester.getTopLeft(find.text('Pay with another wallet')).dy),
      );
    },
  );

  testWidgets(
    'the tap asks the quote, then the confirmation states the fees, the total and what stays',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
      await _reveal(tester, find.text('Pay with this wallet'));
      await tester.tap(find.text('Pay with this wallet'));
      await tester.pump();
      expect(find.text('Getting the swap fees…'), findsOneWidget);
      expect(payments.quotes, hasLength(1));
      payments.quotes.single.complete(Ok(walletQuote()));
      await tester.pump();
      await tester.pump();
      // The lean card on arrival (#250): the bond, the fees together, the total in bold; no title of its own.
      String row(Key key) => [
        for (final text in tester.widgetList<Text>(
          find.descendant(of: find.byKey(key), matching: find.byType(Text)),
        ))
          text.data ?? '',
      ].join(' | ');
      expect(row(PayConfirmationCard.amountRow), 'Bond | 3,207 sats');
      expect(
        row(PayConfirmationCard.feesRow),
        'Swap and network fees | 150 sats',
      );
      expect(row(PayConfirmationCard.totalRow), 'Total to pay | 3,357 sats');
      expect(find.textContaining('to lock your bond?'), findsNothing);
      expect(find.text('Pay 3,357 sats'), findsOneWidget);
      const sentence =
          'This is a hold invoice, it will freeze in your wallet. It will be charged only if you cancel or lose a dispute.';
      // The fees one by one, what stays and the reference's sentence on a hold invoice, word for word, in the detail.
      expect(find.text(sentence), findsNothing);
      await _reveal(tester, find.text('Show details'));
      await tester.tap(find.text('Show details'));
      await tester.pump();
      expect(row(PayConfirmationCard.swapFeeRow), 'Swap fees | 123 sats');
      expect(
        row(PayConfirmationCard.networkFeeRow),
        'Network fee (estimate) | 27 sats',
      );
      expect(
        row(PayConfirmationCard.balanceRow),
        'Balance after payment | 46,643 sats',
      );
      expect(find.text(sentence), findsOneWidget);
      // A bond's detail has no word of the swap service holding the sats: that is a collateral's.
      expect(find.textContaining('swap service'), findsNothing);
      expect(payments.pays, isEmpty);
      // The other wallet's section opened meanwhile does not show the sentence again.
      await tester.ensureVisible(find.text('Pay with another wallet'));
      await tester.pump();
      await tester.tap(find.text('Pay with another wallet'));
      await tester.pump();
      expect(find.text(sentence), findsOneWidget);
    },
  );

  testWidgets(
    '« Go back » in the confirmation pays nothing and cancels nothing; « Pay {total} sats » pays once and shows the payment sent',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
      await _confirming(tester, payments);
      await _reveal(
        tester,
        find.descendant(
          of: find.byType(BondPaymentPanel),
          matching: find.text('Go back'),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(BondPaymentPanel),
          matching: find.text('Go back'),
        ),
      );
      await tester.pump();
      expect(payments.pays, isEmpty);
      expect(find.text('Pay with this wallet'), findsOneWidget);
      // Only the confirmation closed: the order's cancel dialog never opened.
      expect(find.text('Cancel the order?'), findsNothing);

      await tester.tap(find.text('Pay with this wallet'));
      await tester.pump();
      payments.quotes.last.complete(Ok(walletQuote()));
      await tester.pump();
      await tester.pump();
      await _reveal(tester, find.text('Pay 3,357 sats'));
      await tester.pump(MovedTapGuard.afterMove);
      await tester.tap(find.text('Pay 3,357 sats'));
      await tester.tap(find.text('Pay 3,357 sats'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Sending the payment…'), findsOneWidget);
      expect(payments.pays, hasLength(1));
      payments.pays.single.complete(Ok(_payment));
      await tester.pump();
      _follow(payments, const P2pWalletPaymentSent());
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Payment sent. Waiting for Temple of Sats to see your bond locked.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pay with this wallet'), findsNothing);
    },
  );

  testWidgets(
    'a refusal: its reason, « Pay with another wallet » open with its QR code, the wallet still offered',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
      await _reveal(tester, find.text('Pay with this wallet'));
      await tester.tap(find.text('Pay with this wallet'));
      await tester.pump();
      payments.quotes.single.complete(
        Err(
          BondPayWalletRefused(
            P2pWalletUnderMinimum(minimum: Sats.fromInt(25000)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Amount below minimum swap limit: 25,000 sats'),
        findsOneWidget,
      );
      expect(find.byType(QrImageView), findsOneWidget);
      expect(
        find.text(
          'This is a hold invoice, it will freeze in your wallet. It will be charged only if you cancel or lose a dispute.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pay with this wallet'), findsOneWidget);
    },
  );

  testWidgets(
    'a payment interrupted before it was sent: said, and only the other wallet',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
      _follow(payments, const P2pWalletPaymentSigned());
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'The payment was interrupted before it was sent. Nothing left this wallet yet.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pay with this wallet'), findsNothing);
      expect(find.byType(QrImageView), findsOneWidget);
    },
  );

  testWidgets(
    'not offered (the invoice is not one the wallet pays): why, no balance, no button, the other wallet open',
    (tester) async {
      await _show(tester, state: 'bond', offered: false);
      await tester.pump();
      expect(find.text('Pay with this wallet'), findsNothing);
      expect(
        find.text('The order moved on before the payment. Nothing was paid.'),
        findsOneWidget,
      );
      expect(find.textContaining('sats available'), findsNothing);
      expect(find.byType(QrImageView), findsOneWidget);
    },
  );

  testWidgets(
    'while the payment is sent, and once sent: the other wallet closed, no QR code nor copy of the same invoice, the line in view',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
      await _confirming(tester, payments);
      await tester.tap(find.text('Pay 3,357 sats'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Sending the payment…'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Copy to clipboard'), findsNothing);
      final line = tester.getRect(find.text('Sending the payment…'));
      expect(line.top, greaterThanOrEqualTo(0));
      expect(line.bottom, lessThanOrEqualTo(844));
      payments.pays.single.complete(Ok(_payment));
      await tester.pump();
      _follow(payments, const P2pWalletPaymentSent());
      await tester.pump();
      await tester.pump();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Copy to clipboard'), findsNothing);
      // Opened again by the user: still neither the QR code nor the copy of the invoice this wallet paid.
      await tester.ensureVisible(find.text('Pay with another wallet'));
      await tester.pump();
      await tester.tap(find.text('Pay with another wallet'));
      await tester.pump();
      expect(find.text('See Compatible Wallets'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Copy to clipboard'), findsNothing);
    },
  );

  testWidgets(
    'at 6, the cancel\'s dialog adds nothing: the bond is locked and the reference says it is lost',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'six');
      _follow(payments, const P2pWalletPaymentPending());
      await tester.pump();
      await tester.pump();
      final cancel = find.widgetWithText(TradeButton, 'Cancel');
      await tester.ensureVisible(cancel.last);
      await tester.pump();
      await tester.tap(cancel.last);
      await tester.pump();
      await tester.pump();
      expect(find.text('Confirm Cancel'), findsOneWidget);
      expect(find.textContaining('on its way from this wallet'), findsNothing);
    },
  );

  testWidgets(
    'at 3, a payment being refunded is not on its way: the cancel\'s dialog adds nothing',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
      _follow(payments, const P2pWalletPaymentRefundPending());
      await tester.pump();
      await tester.pump();
      final cancel = find.widgetWithText(TradeButton, 'Cancel');
      await tester.ensureVisible(cancel.last);
      await tester.pump();
      await tester.tap(cancel.last);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('on its way from this wallet'), findsNothing);
    },
  );

  testWidgets(
    'records that cannot be read when the panel opens: said as such, never as the coordinator not reached',
    (tester) async {
      await _show(
        tester,
        state: 'bond',
        notOffered: const BondPayRecordsUnreadable(P2pStorageFailure()),
      );
      await tester.pump();
      expect(
        find.text('Bull Market could not read its records on this device.'),
        findsOneWidget,
      );
      expect(find.textContaining('Could not reach'), findsNothing);
    },
  );

  testWidgets(
    'while a cancel of the order runs, « Pay with this wallet » waits',
    (tester) async {
      final answer = Completer<Result<CancelOutcome, CancelRefusal>>();
      await _show(tester, state: 'bond', cancel: answer.future);
      final trade = tester
          .element(find.byType(BondPaymentPanel))
          .read<TradeCubit>();
      unawaited(trade.cancel(_bondSeen()));
      await tester.pump();
      await tester.pump();
      final pay = find.widgetWithText(TradeButton, 'Pay with this wallet');
      expect(tester.widget<TradeButton>(pay).onPressed, isNull);
      answer.complete(Ok(CancelDone(_record, _bondSeen())));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<TradeButton>(pay).onPressed, isNotNull);
    },
  );

  testWidgets(
    '« Cancel » waits while the payment is sent; once sent, its dialog says a payment is on its way',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
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
          'A payment of this bond is on its way from this wallet.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a payment followed stays said when the balance can no longer be read; unreadable records keep the panel, the other wallet not opened',
    (tester) async {
      final (cubit, payments) = await _show(tester, state: 'bond');
      _follow(payments, const P2pWalletPaymentSent());
      await tester.pump();
      payments.balances.add(const Err(P2pWalletUnavailable()));
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Payment sent. Waiting for Temple of Sats to see your bond locked.',
        ),
        findsOneWidget,
      );
      payments.follows.last.add(
        const BondPaymentUnreadable(P2pWalletUnavailable()),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Bull Market cannot read where this payment stands.'),
        findsOneWidget,
      );
      expect(find.byType(QrImageView), findsNothing);
      expect(cubit.state.step, isA<BondPayUnreadable>());
    },
  );

  testWidgets(
    'at 3, the swap service could not pay: said so, the other wallet open',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
      _follow(payments, const P2pWalletPaymentRefundPending());
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Swap failed. Swap will be refunded shortly. The swap fees are not refunded.',
        ),
        findsOneWidget,
      );
      expect(find.byType(QrImageView), findsOneWidget);
    },
  );

  for (final (name, progress, text) in [
    (
      'expired with its funding sent',
      const P2pWalletPaymentExpired(P2pWalletFunds.sent),
      'Swap expired. The sats of this bond left this wallet. Contact Bull Bitcoin support.',
    ),
    (
      'expired with its funding possibly sent',
      const P2pWalletPaymentExpired(P2pWalletFunds.maybeSent),
      'Swap expired. The sats of this bond may have left this wallet. Contact Bull Bitcoin support.',
    ),
    (
      'failed with its funding sent',
      const P2pWalletPaymentFailed(P2pWalletFunds.sent),
      'Swap failed. The sats of this bond left this wallet. Contact Bull Bitcoin support.',
    ),
    (
      'failed with its funding possibly sent',
      const P2pWalletPaymentFailed(P2pWalletFunds.maybeSent),
      'Swap failed. The sats of this bond may have left this wallet. Contact Bull Bitcoin support.',
    ),
  ]) {
    testWidgets('at 3, a bond paid by this wallet: $name', (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
      _follow(payments, progress);
      await tester.pump();
      await tester.pump();
      expect(find.text(text), findsOneWidget);
    });
  }

  testWidgets(
    'a payment of the invoice made by the wallet\'s own screens: already paid, nothing more offered',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
      await _confirming(tester, payments);
      await tester.tap(find.text('Pay 3,357 sats'));
      await tester.pump();
      payments.pays.single.complete(
        const Err(
          BondPayWalletRefused(
            P2pWalletPaymentExists(progress: P2pWalletPaymentSent()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text('This wallet already paid this invoice.'),
        findsOneWidget,
      );
      expect(find.text('Pay with this wallet'), findsNothing);
      expect(find.byType(QrImageView), findsNothing);
    },
  );

  testWidgets(
    'the order could not be read just before the payment: the coordinator not reached, nothing paid, the wallet still offered',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
      await _confirming(tester, payments);
      await tester.tap(find.text('Pay 3,357 sats'));
      await tester.pump();
      payments.pays.single.complete(
        const Err(BondPayTradeUnavailable(CoordinatorTimedOut())),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Could not reach Temple of Sats. Nothing was paid.'),
        findsOneWidget,
      );
      expect(find.text('Pay with this wallet'), findsOneWidget);
    },
  );

  testWidgets(
    'past the invoice\'s end, a payment sent is still said; nothing more is offered',
    (tester) async {
      var clock = tradeNow;
      final (_, payments) = await _show(
        tester,
        state: 'bond',
        now: () => clock,
      );
      _follow(payments, const P2pWalletPaymentSent());
      await tester.pump();
      clock = tradeNow.add(const Duration(hours: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text(
          'Payment sent. Waiting for Temple of Sats to see your bond locked.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pay with this wallet'), findsNothing);
    },
  );

  testWidgets('no Instant payments wallet: nothing in the slot', (
    tester,
  ) async {
    await _show(
      tester,
      state: 'bond',
      balance: const Err(P2pWalletNoInstantWallet()),
    );
    expect(find.text('Pay with this wallet'), findsNothing);
    expect(find.textContaining('Instant payments'), findsNothing);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  for (final (name, state, progress, text) in [
    (
      'refund pending',
      'expired',
      const P2pWalletPaymentRefundPending(),
      'Swap will be refunded shortly. The swap fees are not refunded.',
    ),
    (
      'refunded',
      'expired',
      const P2pWalletPaymentRefunded(),
      'Swap has been refunded. The swap fees are not refunded.',
    ),
    (
      'kept',
      'expired',
      const P2pWalletPaymentPaid(),
      'Your bond was kept by Temple of Sats.',
    ),
    (
      'sent, the order no longer going on: neutral',
      'expired',
      const P2pWalletPaymentPending(),
      'Your swap is in progress.',
    ),
    (
      'expired with its funding sent',
      'expired',
      const P2pWalletPaymentExpired(P2pWalletFunds.sent),
      'Swap expired. The sats of this bond left this wallet. Contact Bull Bitcoin support.',
    ),
    (
      'expired with its funding possibly sent',
      'expired',
      const P2pWalletPaymentExpired(P2pWalletFunds.maybeSent),
      'Swap expired. The sats of this bond may have left this wallet. Contact Bull Bitcoin support.',
    ),
    (
      'failed with its funding sent',
      'expired',
      const P2pWalletPaymentFailed(P2pWalletFunds.sent),
      'Swap failed. The sats of this bond left this wallet. Contact Bull Bitcoin support.',
    ),
    (
      'failed with its funding possibly sent',
      'expired',
      const P2pWalletPaymentFailed(P2pWalletFunds.maybeSent),
      'Swap failed. The sats of this bond may have left this wallet. Contact Bull Bitcoin support.',
    ),
    (
      'under review',
      'six',
      const P2pWalletPaymentUnderReview(),
      'Swap is under review. Contact Bull Bitcoin support if it lasts.',
    ),
    (
      'maybe sent',
      'six',
      const P2pWalletPaymentBroadcastUnknown(),
      'The payment may have been sent. Its status will update shortly.',
    ),
  ]) {
    testWidgets('after status 3, a bond paid by this wallet: $name', (
      tester,
    ) async {
      final (_, payments) = await _show(tester, state: state);
      _follow(payments, progress);
      await tester.pump();
      await tester.pump();
      expect(find.text(text), findsOneWidget);
    });
  }

  testWidgets(
    'the bond locked and paid by this wallet: the reference\'s bond line alone, nothing of ours',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'six');
      _follow(payments, const P2pWalletPaymentPending());
      await tester.pump();
      await tester.pump();
      expect(find.text('Your taker bond is locked'), findsOneWidget);
      // The line of ours renders no text at all.
      expect(
        find.descendant(
          of: find.byType(BondPaymentLine),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('after status 3, a bond not paid by this wallet: no line', (
    tester,
  ) async {
    await _show(tester, state: 'six');
    expect(
      find.descendant(
        of: find.byType(BondPaymentLine),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'the wallet offered and idle, « Pay with another wallet » opened: the reference\'s sentence once, with the QR code',
    (tester) async {
      await _show(tester, state: 'bond');
      await tester.ensureVisible(find.text('Pay with another wallet'));
      await tester.pump();
      if (find.byType(QrImageView).evaluate().isEmpty) {
        await tester.tap(find.text('Pay with another wallet'));
        await tester.pump();
      }
      expect(find.byType(QrImageView), findsOneWidget);
      expect(
        find.text(
          'This is a hold invoice, it will freeze in your wallet. It will be charged only if you cancel or lose a dispute.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'at 3, the swap refunded already: said so, the other wallet open',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
      _follow(payments, const P2pWalletPaymentRefunded());
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Swap failed. Swap has been refunded. The swap fees are not refunded.',
        ),
        findsOneWidget,
      );
      expect(find.byType(QrImageView), findsOneWidget);
    },
  );

  testWidgets(
    'after status 3, a swap expired with its funding sent: « Swap expired. », support',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'expired');
      _follow(payments, const P2pWalletPaymentExpired(P2pWalletFunds.sent));
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Swap expired. The sats of this bond left this wallet. Contact Bull Bitcoin support.',
        ),
        findsOneWidget,
      );
    },
  );

  group('on a phone of 320 points, the text larger', () {
    for (final locale in const [Locale('en'), Locale('fr')]) {
      for (final scale in const [2.0, 3.0]) {
        testWidgets(
          '${locale.languageCode} at ×$scale: the confirmation and a refusal are not cut',
          (tester) async {
            final (_, payments) = await _show(
              tester,
              state: 'bond',
              locale: locale,
              size: const Size(320, 640),
              textScale: scale,
            );
            final pay = find.byWidgetPredicate(
              (widget) => widget is BondPaymentPanel,
            );
            expect(pay, findsOneWidget);
            final cubit = tester.element(pay).read<BondPaymentCubit>();
            unawaited(cubit.ask(_bondSeen()));
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
            unawaited(cubit.ask(_bondSeen()));
            await tester.pump();
            payments.quotes.last.complete(
              const Err(BondPayWalletRefused(P2pWalletServiceUnreachable())),
            );
            await tester.pump();
            await tester.pump();
            _expectNothingCut(tester, 'refusal');
          },
        );
      }
    }
  });

  group(
    'on a phone of 320 points, the text larger, the lines of the payment',
    () {
      for (final locale in const [Locale('en'), Locale('fr')]) {
        for (final scale in const [2.0, 3.0]) {
          testWidgets(
            '${locale.languageCode} at ×$scale: sending, sent, and after 3',
            (tester) async {
              final (cubit, payments) = await _show(
                tester,
                state: 'bond',
                locale: locale,
                size: const Size(320, 640),
                textScale: scale,
              );
              unawaited(cubit.ask(_bondSeen()));
              await tester.pump();
              payments.quotes.single.complete(Ok(walletQuote()));
              await tester.pump();
              unawaited(cubit.confirm());
              await tester.pump();
              _expectNothingCut(tester, 'sending');
              payments.pays.single.complete(Ok(_payment));
              await tester.pump();
              for (final progress in const <P2pWalletPaymentProgress>[
                P2pWalletPaymentSent(),
                P2pWalletPaymentRefundPending(),
                P2pWalletPaymentUnderReview(),
                P2pWalletPaymentExpired(P2pWalletFunds.maybeSent),
              ]) {
                _follow(payments, progress);
                await tester.pump();
                await tester.pump();
                _expectNothingCut(tester, '$progress');
              }
            },
          );
        }
      }
    },
  );
  testWidgets(
    'a screen reader hears the confirmation\'s total as it opens, and the payment\'s line as it changes',
    (tester) async {
      final handle = tester.ensureSemantics();
      final (_, payments) = await _show(tester, state: 'bond');
      await _confirming(tester, payments);
      // The lean card has no title (#250): its total is read out as it opens, with its amount.
      expect(
        tester.getSemantics(find.byKey(PayConfirmationCard.totalRow)),
        isSemantics(isLiveRegion: true, label: 'Total to pay\n3,357 sats'),
      );
      handle.dispose();
    },
  );
}

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
