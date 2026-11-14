import 'dart:async';
import 'dart:io';

import 'package:bb_mobile/features/p2p_wallet/data/instant_wallet_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/data/lightning_swap_quote_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/data/wallet_payment_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/issued_quotes.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/find_wallet_payment_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/pay_checked_invoice_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/quote_invoice_payment_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/watch_instant_balance_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/watch_wallet_payment_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/public/p2p_wallet_facade.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart';
import 'package:bull_logger/bull_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';

import 'support/fakes.dart';
import 'support/payment_fakes.dart';

/// The port as the shell lends it, over fakes of the Swap feature's facade and of the wallet: no test reaches the swap service, nothing real is built, signed or broadcast.
void main() {
  late FakeGetWallets getWallets;
  late FakeWatchSyncs syncs;
  late FakeLiquidWallet liquid;
  late FakeSwapFacade swaps;
  late Journal journal;
  late FakeOrderSwaps orders;
  late FakeWalletInvoices invoices;
  late P2pWalletPort port;

  setUp(() {
    getWallets = FakeGetWallets(Ok([testWallet()]));
    syncs = FakeWatchSyncs();
    liquid = FakeLiquidWallet();
    swaps = FakeSwapFacade(FakeSwapFacade.quoteOf());
    journal = Journal();
    orders = FakeOrderSwaps(journal, () => testNow);
    invoices = FakeWalletInvoices();
    final wallets = InstantWalletRepositoryImpl(
      getWallets,
      syncs,
      FakeGetAddressAtIndex(),
      liquid,
    );
    final issued = IssuedQuotes();
    final payments = WalletPaymentRepositoryImpl(orders, invoices);
    port = P2pWalletFacade(
      WatchInstantBalanceUsecase(wallets),
      QuoteInvoicePaymentUsecase(
        wallets,
        LightningSwapQuoteRepositoryImpl(swaps),
        issued,
        () => testNow,
      ),
      PayCheckedInvoiceUsecase(
        issued,
        wallets,
        invoices,
        payments,
        orders,
        FakePayingLiquid(journal),
        FakeRefundAddress(journal),
        FakeBroadcast(journal),
        () => testNow,
      ),
      WatchWalletPaymentUsecase(payments),
      FindWalletPaymentUsecase(payments),
    );
  });

  tearDown(() async {
    await syncs.finished.close();
    await orders.close();
  });

  group('pays through the port', () {
    test(
      'with a quote the port gave, once; then follows and finds the payment',
      () async {
        final invoice = testInvoice();
        invoices.learn(invoice);
        final quote = switch (await port.quote(invoice)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        final payment = switch (await port.payInvoice(
          invoice,
          accepted: quote,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(payment.paymentHash, invoice.paymentHash);
        expect(journal.only({'broadcast'}), hasLength(1));
        // The quote is spent.
        expect(
          await port.payInvoice(invoice, accepted: quote),
          isA<Err<P2pWalletPayment, P2pWalletRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<P2pWalletQuoteStale>(),
          ),
        );
        expect(
          await port.watchPayment(payment).first,
          isA<Ok<P2pWalletPaymentProgress, P2pWalletRefusal>>().having(
            (ok) => ok.value,
            'value',
            isA<P2pWalletPaymentSent>(),
          ),
        );
        expect(
          await port.findPayment(invoice.paymentHash),
          isA<Ok<P2pWalletPaymentFound?, P2pWalletRefusal>>().having(
            (ok) => ok.value?.payment,
            'payment',
            payment,
          ),
        );
        expect(
          await port.findPayment(payHash(9)),
          isA<Ok<P2pWalletPaymentFound?, P2pWalletRefusal>>().having(
            (ok) => ok.value,
            'value',
            isNull,
          ),
        );
      },
    );

    test('never with a quote it did not give', () async {
      final invoice = testInvoice();
      invoices.learn(invoice);
      final forged = P2pWalletQuote(
        invoice: invoice,
        payin: Sats.fromInt(5000),
        networkFee: Sats.fromInt(26),
        balance: Sats.fromInt(10000),
        quotedAt: testNow,
      );
      expect(
        await port.payInvoice(invoice, accepted: forged),
        isA<Err<P2pWalletPayment, P2pWalletRefusal>>().having(
          (e) => e.failure,
          'failure',
          isA<P2pWalletQuoteStale>(),
        ),
      );
      expect(journal.events, isEmpty);
    });
  });

  test('quotes an invoice: fees, total and what stays', () async {
    final result = await port.quote(testInvoice());
    final quote = switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    expect(
      (
        quote.payin,
        quote.serviceFee,
        quote.networkFee,
        quote.total,
        quote.remaining,
      ),
      (
        Sats.fromInt(603),
        Sats.fromInt(3),
        Sats.fromInt(26),
        Sats.fromInt(629),
        Sats.fromInt(9371),
      ),
    );
    // One question to the service, one unsigned transaction, nothing else: the fakes fail on any other member, creating an order or signing included.
    expect(swaps.quotes, hasLength(1));
    expect(liquid.builds, hasLength(1));
  });

  test('quotes a testnet invoice only from a testnet wallet', () async {
    final invoice = testInvoice(network: RobosatsNetwork.testnet);
    expect(
      await port.quote(invoice),
      isA<Err<P2pWalletQuote, P2pWalletRefusal>>().having(
        (err) => err.failure,
        'failure',
        isA<P2pWalletWrongNetwork>(),
      ),
    );
    expect(swaps.quotes, isEmpty);
    getWallets.answer = Ok([testWallet(isTestnet: true)]);
    expect(
      await port.quote(invoice),
      isA<Ok<P2pWalletQuote, P2pWalletRefusal>>(),
    );
    expect(swaps.quotes.single.environment, OrderSwapEnvironment.testnet);
  });

  test('says when the service is out of reach', () async {
    swaps.answer = const Err(SwapNetworkFailure('Connection refused'));
    expect(
      await port.quote(testInvoice()),
      isA<Err<P2pWalletQuote, P2pWalletRefusal>>().having(
        (err) => err.failure,
        'failure',
        isA<P2pWalletServiceUnreachable>(),
      ),
    );
    expect(liquid.builds, isEmpty);
  });

  test('gives the balance, then each new one', () async {
    final seen = <Result<Sats, P2pWalletRefusal>>[];
    final subscription = port
        .instantBalance(RobosatsNetwork.mainnet)
        .listen(seen.add);
    await pumpEventQueue();
    syncs.finished.add(testWallet(balance: 9371));
    await pumpEventQueue();
    expect(
      seen.map(
        (result) => switch (result) {
          Ok(:final value) => value.value.toInt(),
          Err() => -1,
        },
      ),
      [10000, 9371],
    );
    await subscription.cancel();
  });

  test(
    'prints and logs nothing, so nothing of an invoice, an amount or an answer',
    () async {
      final output = await _capture(() async {
        await port.quote(testInvoice());
        swaps.answer = Err(
          SwapAmountOutOfBoundsFailure(
            limitAmountSat: BigInt.from(1000),
            isMinimum: true,
            logMessage: 'Amount below 0.00001',
          ),
        );
        await port.quote(testInvoice());
        liquid.buildError = Exception('InsufficientFunds { missing_sats: 21 }');
        swaps.answer = FakeSwapFacade.quoteOf();
        await port.quote(testInvoice());
        final balance = await port
            .instantBalance(RobosatsNetwork.mainnet)
            .first;
        expect(balance, isA<Ok<Sats, P2pWalletRefusal>>());
      });
      // Over these fakes, the port's own code prints and logs nothing at all: no invoice, amount, answer of the service or exception text can be in what it writes.
      final lines = output
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      expect(lines, hasLength(2));
      expect(lines.first, 'print capture works');
      expect(lines.last, contains('logger capture works'));
      expect(output.contains(fakeBolt11(RobosatsNetwork.mainnet)), isFalse);
    },
  );
}

/// Everything [body] prints and everything the project logger writes while it runs, as one text; a line printed and a line logged by the capture itself show that both are seen.
Future<String> _capture(Future<void> Function() body) async {
  final printed = <String>[];
  final directory = Directory.systemTemp.createTempSync('p2p_wallet_output');
  final previous = log;
  log = Logger.replace(directory: directory);
  try {
    await runZoned(
      () async {
        Zone.current.print('print capture works');
        log.fine('logger capture works');
        await body();
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );
    await log.flush();
  } finally {
    log = previous;
  }
  final written = [
    for (final file in directory.listSync().whereType<File>())
      file.readAsStringSync(),
  ].join('\n');
  directory.deleteSync(recursive: true);
  expect(printed, contains('print capture works'));
  expect(written, contains('logger capture works'));
  return '${printed.join('\n')}\n$written';
}
