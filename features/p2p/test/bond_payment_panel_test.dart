import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/bond_payment.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/domain/usecases/fetch_coordinator_info_usecase.dart';
import 'package:p2p/src/domain/usecases/find_public_order_usecase.dart';
import 'package:p2p/src/presentation/bond_payment_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/src/presentation/trade_order_page_cubit.dart';
import 'package:p2p/src/ui/trade/bond_payment_panel.dart';
import 'package:p2p/src/ui/trade/trade_screen.dart';
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
    (record, seen, {bondLoss}) => throw StateError('no cancel'),
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
            now: () => tradeNow,
            coordinatorDetails: (_) => throw StateError('not opened'),
            walletPayment: BondPaymentPanel.slotFor,
            walletBondLine: (_) => const BondPaymentLine(),
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
    };
    final offer = walletPaymentFor(
      accepted: Sats.fromInt(1000000),
      status: _bondSeen().status,
      step: InvoiceStep.bond,
      now: tradeNow,
    );
    _offered = offer as WalletPaymentOffered;
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
      expect(
        find.text('Asking the swap service for its fees…'),
        findsOneWidget,
      );
      expect(payments.quotes, hasLength(1));
      payments.quotes.single.complete(Ok(walletQuote()));
      await tester.pump();
      await tester.pump();
      expect(find.text('Pay 3,207 sats to lock your bond?'), findsOneWidget);
      expect(find.text('Swap service fee: 123 sats'), findsOneWidget);
      expect(find.text('Network fee: about 27 sats'), findsOneWidget);
      expect(
        find.text('Total: 3,357 sats. Left in Instant payments: 46,643 sats.'),
        findsOneWidget,
      );
      expect(find.textContaining('through a swap service'), findsOneWidget);
      expect(payments.pays, isEmpty);
    },
  );

  testWidgets(
    '« Cancel » in the confirmation pays nothing; « Pay {total} sats » pays once and shows the payment sent',
    (tester) async {
      final (_, payments) = await _show(tester, state: 'bond');
      await _confirming(tester, payments);
      await _reveal(tester, find.descendant(
        of: find.byType(BondPaymentPanel),
        matching: find.text('Cancel'),
      ));
      await tester.tap(find.descendant(
        of: find.byType(BondPaymentPanel),
        matching: find.text('Cancel'),
      ));
      await tester.pump();
      expect(payments.pays, isEmpty);
      expect(find.text('Pay with this wallet'), findsOneWidget);

      await tester.tap(find.text('Pay with this wallet'));
      await tester.pump();
      payments.quotes.last.complete(Ok(walletQuote()));
      await tester.pump();
      await tester.pump();
      await _reveal(tester, find.text('Pay 3,357 sats'));
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
        find.text(
          'This bond is under the swap service’s minimum of 25,000 sats.',
        ),
        findsOneWidget,
      );
      expect(find.byType(QrImageView), findsOneWidget);
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
    'not offered (the invoice is not one the wallet pays): the screen as without the wallet',
    (tester) async {
      await _show(tester, state: 'bond', offered: false);
      await tester.pump();
      expect(find.text('Pay with this wallet'), findsNothing);
      expect(find.byType(QrImageView), findsOneWidget);
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
      'held',
      'six',
      const P2pWalletPaymentPending(),
      'Your bond is locked. Its sats are held by the swap service until the trade ends.',
    ),
    (
      'refund pending',
      'expired',
      const P2pWalletPaymentRefundPending(),
      'Your bond was returned. The swap service is refunding it to Instant payments, without its fees.',
    ),
    (
      'refunded',
      'expired',
      const P2pWalletPaymentRefunded(),
      'Refunded: the bond is back in Instant payments, without the swap service’s fees.',
    ),
    (
      'kept',
      'expired',
      const P2pWalletPaymentPaid(),
      'Your bond was kept by Temple of Sats.',
    ),
    (
      'under review',
      'six',
      const P2pWalletPaymentUnderReview(),
      'The swap service is reviewing this payment. Your sats are with it; contact Bull Bitcoin support if it lasts.',
    ),
    (
      'maybe sent',
      'six',
      const P2pWalletPaymentBroadcastUnknown(),
      'The payment may have been sent. The wallet is checking with the swap service.',
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

  testWidgets('after status 3, a bond not paid by this wallet: no line', (
    tester,
  ) async {
    await _show(tester, state: 'six');
    expect(find.textContaining('swap service'), findsNothing);
  });

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

  testWidgets(
    'a screen reader hears the confirmation\'s title as it opens, and the payment\'s line as it changes',
    (tester) async {
      final handle = tester.ensureSemantics();
      final (_, payments) = await _show(tester, state: 'bond');
      await _confirming(tester, payments);
      expect(
        tester.getSemantics(find.text('Pay 3,207 sats to lock your bond?')),
        isSemantics(isHeader: true, isLiveRegion: true),
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
