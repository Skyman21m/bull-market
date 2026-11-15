import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_payout_outcome.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/payout_from_wallet_usecase.dart';
import 'package:p2p/src/presentation/payout_cubit.dart';
import 'package:p2p/src/presentation/payout_wallet_cubit.dart';
import 'package:p2p/src/ui/trade/payout_panel.dart';
import 'package:p2p/src/ui/trade/payout_wallet_section.dart';
import 'package:p2p/src/ui/widgets/trade_button.dart';
import 'package:p2p/testing.dart'
    show Bolt11TestDecoder, Bolt11TestInvoice, FakeP2pWalletPort;

import 'support/harness.dart';
import 'support/trade_orders.dart';
import 'support/trade_screens.dart';

/// The wallet's invoice and address in the payout panel (#90): « Generate Invoice » and « Generate New Address », over the panel and its checks run for real, and a fake wallet's port that records what it was asked: never the wallet, never the swap service, never a coordinator.
void main() {
  final record = TradeScreenStatuses.record;
  // The invoice asked with the default budget of 1,000 ppm, as the panel's own tests compute it.
  const asked = 106606;
  final readAt = tradeNow.add(const Duration(seconds: 30));
  const coordinatorName = 'Temple of Sats';
  // An obviously fake address of BIP-173's test vectors, which no wallet of the project holds.
  const walletAddress = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';

  Bolt11TestInvoice invoiceOf({
    int sats = asked,
    int seed = 90,
  }) => Bolt11TestInvoice(
    network: Bolt11Network.mainnet,
    sats: sats,
    seed: seed,
    createdAt: tradeNow,
    // A wallet invoice lives a short time: it may expire before the coordinator pays, which the panel says.
    expiry: const Duration(minutes: 10),
  );

  final walletInvoice = invoiceOf();
  final secondInvoice = invoiceOf(seed: 91);
  final reader = Bolt11Reader(
    Bolt11TestDecoder([walletInvoice, secondInvoice]),
  );

  P2pWalletInvoice made(Bolt11TestInvoice invoice, {int received = 106400}) =>
      P2pWalletInvoice(
        bolt11: invoice.text,
        amount: Sats.fromInt(asked),
        expiresAt: tradeNow.add(const Duration(minutes: 10)),
        received: Sats.fromInt(received),
      );

  late TradeScreenStatuses statuses;
  late TradeSeen six;
  late TradeSeen sixSwap;
  late TradeSeen fifteenExpired;

  setUpAll(() async {
    statuses = await TradeScreenStatuses.make();
    six = await statuses.waitingForBoth();
    sixSwap = await statuses.read(
      await statuses.bondStep(),
      orderJson(
        6,
        changes: {
          'swap_allowed': true,
          'swap_failure_reason': null,
          'suggested_mining_fee_rate': 3.5,
          'swap_fee_rate': 0.75,
        },
      ),
    );
    fifteenExpired = await statuses.read(
      await statuses.waitingForPayout(),
      orderJson(15),
    );
  });

  PayoutAsk askOf(TradeSeen seen) => switch (PayoutAsk.of(record, seen)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  group('the use case', () {
    test(
      'asks the wallet for exactly the amount, on the trade\'s network, for this trade',
      () async {
        final port = FakeP2pWalletPort(Ok(Sats.zero))
          ..scriptInvoice(Ok(made(walletInvoice)));
        final usecase = PayoutFromWalletUsecase(port);
        final ask = askOf(six);
        final result = await usecase.invoice(ask, Sats.fromInt(asked));
        expect(result, isA<Ok<P2pWalletInvoice, P2pWalletRefusal>>());
        expect(port.invoicesAsked, [
          (
            record.network,
            Sats.fromInt(asked),
            PayoutFromWalletUsecase.payoutKey(ask),
          ),
        ]);
      },
    );

    test('refuses an invoice of another amount than asked', () async {
      final port = FakeP2pWalletPort(Ok(Sats.zero))
        ..scriptInvoice(Ok(made(walletInvoice)));
      expect(
        await PayoutFromWalletUsecase(
          port,
        ).invoice(askOf(six), Sats.fromInt(asked + 1)),
        isA<Err<P2pWalletInvoice, P2pWalletRefusal>>().having(
          (err) => err.failure,
          'failure',
          isA<P2pWalletServiceRefused>(),
        ),
      );
    });

    test(
      'the payout key: one per trade, and a new one for each failed payout',
      () {
        final first = PayoutFromWalletUsecase.payoutKey(askOf(six));
        expect(
          first,
          '${record.network.name}:${record.coordinatorAlias}:${record.orderId}',
        );
        expect(PayoutFromWalletUsecase.payoutKey(askOf(sixSwap)), first);
        final again = PayoutFromWalletUsecase.payoutKey(askOf(fifteenExpired));
        expect(again, startsWith('$first:again:'));
        expect(again, isNot(first));
      },
    );

    test('asks an address of the trade\'s network', () async {
      final port = FakeP2pWalletPort(Ok(Sats.zero))
        ..scriptAddress(const Ok(P2pWalletAddress(walletAddress)));
      expect(
        await PayoutFromWalletUsecase(port).address(record),
        isA<Ok<P2pWalletAddress, P2pWalletRefusal>>(),
      );
      expect(port.addressesAsked, [record.network]);
    });
  });

  group('the cubit', () {
    test(
      'asks one thing at a time, says a long wait, then what the wallet gave',
      () async {
        final gate = Completer<void>();
        final port = _GatedPort(gate.future)
          ..scriptInvoice(Ok(made(walletInvoice)));
        final cubit = PayoutWalletCubit(
          PayoutFromWalletUsecase(port),
          stillWaitingAfter: const Duration(milliseconds: 10),
        );
        addTearDown(cubit.close);
        final first = cubit.makeInvoice(askOf(six), Sats.fromInt(asked));
        expect(cubit.state, isA<PayoutWalletMaking>());
        // A second request meanwhile does nothing.
        expect(await cubit.makeAddress(askOf(sixSwap)), isNull);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          cubit.state,
          isA<PayoutWalletMaking>().having(
            (s) => s.waitedLong,
            'waitedLong',
            isTrue,
          ),
        );
        gate.complete();
        expect(await first, walletInvoice.text);
        expect(cubit.state, isA<PayoutWalletMadeInvoice>());
        expect(port.addressesAsked, isEmpty);
      },
    );

    test('says a refusal and gives no text', () async {
      final port = FakeP2pWalletPort(Ok(Sats.zero))
        ..scriptAddress(const Err(P2pWalletNoBitcoinWallet()));
      final cubit = PayoutWalletCubit(PayoutFromWalletUsecase(port));
      addTearDown(cubit.close);
      expect(await cubit.makeAddress(askOf(sixSwap)), isNull);
      expect(
        cubit.state,
        isA<PayoutWalletRefused>()
            .having((s) => s.kind, 'kind', PayoutKind.onchain)
            .having(
              (s) => s.refusal,
              'refusal',
              isA<P2pWalletNoBitcoinWallet>(),
            ),
      );
    });
  });

  group('in the payout panel', () {
    late _Sender sender;

    Future<(PayoutCubit, FakeP2pWalletPort)> show(
      WidgetTester tester,
      TradeSeen seen, {
      Locale locale = const Locale('en'),
    }) async {
      sender = _Sender();
      final payout = PayoutCubit(
        record,
        PayoutAsk.of,
        (record, seen, destination) => switch (PayoutAsk.of(record, seen)) {
          Err(:final failure) => Err(failure),
          Ok(:final value) => value.check(
            destination,
            now: readAt,
            reader: reader,
          ),
        },
        sender.call,
        (record) => () {},
        now: () => readAt.add(const Duration(seconds: 1)),
      );
      addTearDown(payout.close);
      final port = FakeP2pWalletPort(Ok(Sats.zero));
      final wallet = PayoutWalletCubit(PayoutFromWalletUsecase(port));
      addTearDown(wallet.close);
      tester.view
        ..physicalSize = const Size(390, 844) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness(
          MultiBlocProvider(
            providers: [
              BlocProvider.value(value: payout),
              BlocProvider.value(value: wallet),
            ],
            child: SingleChildScrollView(
              child: PayoutPanel(
                request: PayoutPanelRequest(
                  record: record,
                  seen: seen,
                  coordinator: coordinatorName,
                  now: readAt,
                ),
                wallet: PayoutWalletSection.slotFor,
              ),
            ),
          ),
          locale: locale,
        ),
      );
      payout.show(seen);
      await tester.pump();
      return (payout, port);
    }

    Finder generateInvoice() =>
        find.widgetWithText(TradeButton, 'Generate Invoice');
    Finder submit() => find.widgetWithText(TradeButton, 'Submit');

    testWidgets(
      '« Generate Invoice » puts the wallet\'s invoice in the field, says what arrives, and submits nothing',
      (tester) async {
        final (payout, port) = await show(tester, six);
        port.scriptInvoice(Ok(made(walletInvoice)));
        await tester.ensureVisible(generateInvoice());
        await tester.tap(generateInvoice());
        await tester.pump();
        await tester.pump();
        // The amount the panel shows, for this trade.
        expect(port.invoicesAsked.single.$2, Sats.fromInt(asked));
        expect(
          port.invoicesAsked.single.$3,
          PayoutFromWalletUsecase.payoutKey(askOf(six)),
        );
        // In the field, as if pasted: the panel's own check reads it.
        expect(payout.state.form.invoice, walletInvoice.text);
        expect(
          payout.state.invoice,
          isA<Ok<CheckedPayout, PayoutCheckRefusal>>(),
        );
        expect(find.text('Receive Amount: 106,400 sats'), findsOneWidget);
        expect(find.text('Swap fees: 206 sats'), findsOneWidget);
        expect(
          find.text('This fee will be deducted from the amount sent'),
          findsOneWidget,
        );
        // Nothing submitted: « Submit » is the user's tap.
        expect(sender.sent, isEmpty);
        expect(tester.widget<TradeButton>(submit()).onPressed, isNotNull);
      },
    );

    testWidgets('the lines go once the field holds something else', (
      tester,
    ) async {
      final (payout, port) = await show(tester, six);
      port.scriptInvoice(Ok(made(walletInvoice)));
      await tester.ensureVisible(generateInvoice());
      await tester.tap(generateInvoice());
      await tester.pump();
      await tester.pump();
      expect(find.text('Receive Amount: 106,400 sats'), findsOneWidget);
      payout.editInvoice(secondInvoice.text);
      await tester.pump();
      expect(find.text('Receive Amount: 106,400 sats'), findsNothing);
    });

    testWidgets(
      'a refusal is said in the wallet\'s words, and the field is left as it was',
      (tester) async {
        final (payout, port) = await show(tester, six);
        port.scriptInvoice(
          Err(P2pWalletUnderMinimum(minimum: Sats.fromInt(200000))),
        );
        await tester.ensureVisible(generateInvoice());
        await tester.tap(generateInvoice());
        await tester.pump();
        await tester.pump();
        expect(
          find.text('Amount below minimum swap limit: 200,000 sats'),
          findsOneWidget,
        );
        expect(payout.state.form.invoice, isEmpty);
      },
    );

    testWidgets(
      '« Generate New Address » on the Onchain tab puts a new address in its field',
      (tester) async {
        final (payout, port) = await show(tester, sixSwap);
        await tester.tap(find.text('Onchain'));
        await tester.pump();
        expect(payout.state.form.kind, PayoutKind.onchain);
        port.scriptAddress(const Ok(P2pWalletAddress(walletAddress)));
        final button = find.widgetWithText(TradeButton, 'Generate New Address');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        await tester.pump();
        expect(port.addressesAsked, [record.network]);
        expect(payout.state.form.address, walletAddress);
        expect(sender.sent, isEmpty);
      },
    );

    testWidgets(
      'at 15, once the invoice expired, the same button makes a new invoice, for a new key',
      (tester) async {
        final (payout, port) = await show(tester, fifteenExpired);
        expect(generateInvoice(), findsOneWidget);
        port.scriptInvoice(Ok(made(walletInvoice)));
        await tester.ensureVisible(generateInvoice());
        await tester.tap(generateInvoice());
        await tester.pump();
        await tester.pump();
        expect(port.invoicesAsked.single.$3, contains(':again:'));
        expect(payout.state.form.invoice, walletInvoice.text);
      },
    );

    testWidgets('in French, the wallet\'s words', (tester) async {
      final (_, port) = await show(tester, six, locale: const Locale('fr'));
      port.scriptInvoice(Ok(made(walletInvoice)));
      final button = find.widgetWithText(TradeButton, 'Générer une facture');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Montant à recevoir :'), findsOneWidget);
      expect(
        find.text('Ces frais seront déduits du montant envoyé'),
        findsOneWidget,
      );
    });
  });
}

/// A wallet's port whose invoice waits for [gate], then is the one scripted; any other member fails the test.
final class _GatedPort implements P2pWalletPort {
  final Future<void> gate;
  final _inner = FakeP2pWalletPort(Ok(Sats.zero));

  _GatedPort(this.gate);

  List<RobosatsNetwork> get addressesAsked => _inner.addressesAsked;

  void scriptInvoice(Result<P2pWalletInvoice, P2pWalletRefusal> answer) =>
      _inner.scriptInvoice(answer);

  @override
  Future<Result<P2pWalletInvoice, P2pWalletRefusal>> newLightningInvoice(
    RobosatsNetwork network,
    Sats amount, {
    required String payout,
  }) async {
    await gate;
    return _inner.newLightningInvoice(network, amount, payout: payout);
  }

  @override
  Future<Result<P2pWalletAddress, P2pWalletRefusal>> newReceiveAddress(
    RobosatsNetwork network,
  ) => _inner.newReceiveAddress(network);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('P2pWalletPort.${invocation.memberName} used');
}

/// A payout « sent »: recorded, never sent.
final class _Sender {
  final List<CheckedPayout> sent = [];

  Future<Result<PayoutSubmission, PayoutNotSent>> call(
    TradeRecord record,
    CheckedPayout shown, {
    void Function(PayoutProgress step)? onProgress,
  }) async {
    sent.add(shown);
    throw StateError('nothing is submitted in these tests');
  }
}
