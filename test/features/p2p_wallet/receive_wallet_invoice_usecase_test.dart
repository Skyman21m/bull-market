import 'dart:async';

import 'package:bb_mobile/core/wallet/domain/entities/wallet_address.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/instant_wallet.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/wallet_invoice.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/instant_wallet_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_invoice_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_payment_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/receive_wallet_invoice_usecase.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';

import 'support/fakes.dart';

/// The wallet's invoice for the buyer's payout (#90), over fakes of the Swap feature's facade and of the wallet's readers: no test reaches the swap service.
void main() {
  late _Wallets wallets;
  late _Decoder decoder;
  late _ReceiveSwaps swaps;
  late _Addresses addresses;
  late List<Duration> waits;
  late ReceiveWalletInvoiceUsecase usecase;

  setUp(() {
    wallets = _Wallets();
    decoder = _Decoder();
    swaps = _ReceiveSwaps(decoder);
    addresses = _Addresses();
    waits = [];
    usecase = ReceiveWalletInvoiceUsecase(
      wallets,
      decoder,
      swaps,
      addresses,
      () => testNow,
      delay: (wait) async => waits.add(wait),
    );
  });

  P2pWalletInvoice invoiceOf(Result<P2pWalletInvoice, P2pWalletRefusal> r) =>
      switch (r) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  P2pWalletRefusal refusalOf(Result<P2pWalletInvoice, P2pWalletRefusal> r) =>
      switch (r) {
        Ok() => throw StateError('made'),
        Err(:final failure) => failure,
      };

  Future<Result<P2pWalletInvoice, P2pWalletRefusal>> make({
    RobosatsNetwork network = RobosatsNetwork.mainnet,
    int amount = 25000,
  }) => usecase.execute(network, Sats.fromInt(amount));

  group('a new invoice', () {
    test(
      'asks the quote with the amount fixed on the Lightning side, a new address, and the order to that address',
      () async {
        final invoice = invoiceOf(await make());
        expect(invoice.bolt11, 'lnbcreceive1');
        expect(invoice.amount, Sats.fromInt(25000));
        expect(invoice.received, Sats.fromInt(24950));
        expect(invoice.fee, Sats.fromInt(50));
        expect(invoice.expiresAt, testNow.add(const Duration(minutes: 10)));
        expect(swaps.quotes, [
          (
            environment: OrderSwapEnvironment.mainnet,
            amountSat: BigInt.from(25000),
            isInAmountFixed: true,
            inNetwork: OrderSwapNetwork.lightning,
            outNetwork: OrderSwapNetwork.liquid,
          ),
        ]);
        expect(addresses.calls, [(walletId: 'instant', generateNew: true)]);
        expect(swaps.created, hasLength(1));
        final created = swaps.created.single;
        expect(created['amountSat'], BigInt.from(25000));
        expect(created['isInAmountFixed'], isTrue);
        expect(created['inNetwork'], OrderSwapNetwork.lightning);
        expect(created['outNetwork'], OrderSwapNetwork.liquid);
        expect(created['destinationAddress'], 'lq1new1');
        expect(created['fallbackAddress'], isNull);
        expect(created['purpose'], OrderSwapPurpose.receiveLightning);
        expect(created['destinationWalletId'], 'instant');
        expect(created['sourceWalletId'], isNull);
        expect(created['note'], WalletPaymentRepository.note);
        expect(created['quotedCounterpartAmountSat'], BigInt.from(24950));
      },
    );

    test('on testnet asks the testnet service, from a testnet wallet', () async {
      wallets.wallet = _wallet(isTestnet: true);
      decoder.testnet = true;
      expect(await make(network: RobosatsNetwork.testnet), isA<Ok>());
      expect(swaps.quotes.single.environment, OrderSwapEnvironment.testnet);
      expect(swaps.created.single['environment'], OrderSwapEnvironment.testnet);
    });

    test('takes a short wait of the service once, then the order', () async {
      swaps.createFailures.add(
        const SwapRateLimitedFailure(retryAfter: Duration(seconds: 5)),
      );
      expect(await make(), isA<Ok>());
      expect(waits, [const Duration(seconds: 5)]);
      expect(swaps.createAttempts, 2);
    });

    test('gives a long wait, or a second one, as busy', () async {
      swaps.createFailures.add(
        const SwapRateLimitedFailure(retryAfter: Duration(minutes: 2)),
      );
      expect(refusalOf(await make()), isA<P2pWalletServiceBusy>());
      expect(waits, isEmpty);
      swaps.createFailures
        ..add(const SwapRateLimitedFailure(retryAfter: Duration(seconds: 1)))
        ..add(const SwapRateLimitedFailure(retryAfter: Duration(seconds: 1)));
      expect(refusalOf(await make()), isA<P2pWalletServiceBusy>());
      expect(waits, [const Duration(seconds: 1)]);
    });
  });

  group('refused before anything is asked', () {
    test('a wallet that cannot be read, or none', () async {
      for (final refusal in const [
        P2pWalletNoInstantWallet(),
        P2pWalletUnavailable(),
      ]) {
        wallets.readError = refusal;
        expect(refusalOf(await make()), same(refusal));
      }
      expect(swaps.quotes, isEmpty);
    });

    test('a wallet of the other network', () async {
      expect(
        refusalOf(await make(network: RobosatsNetwork.testnet)),
        isA<P2pWalletWrongNetwork>(),
      );
      expect(swaps.quotes, isEmpty);
    });

    test('no amount, or the wallet waiting for its update', () async {
      expect(refusalOf(await make(amount: 0)), isA<P2pWalletServiceRefused>());
      swaps.appUpdateRequired = true;
      expect(refusalOf(await make()), isA<P2pWalletServiceRefused>());
      expect(swaps.quotes, isEmpty);
    });

    test('the wallet\'s orders unreadable', () async {
      swaps.ordersFailure = const SwapStorageFailure();
      expect(refusalOf(await make()), isA<P2pWalletUnavailable>());
      expect(swaps.quotes, isEmpty);
    });
  });

  group('the service\'s answers', () {
    test('each failure of the quote as the port\'s refusal', () async {
      for (final (failure, matcher) in [
        (
          SwapAmountOutOfBoundsFailure(
            limitAmountSat: BigInt.from(30000),
            isMinimum: true,
          ),
          isA<P2pWalletUnderMinimum>().having(
            (r) => r.minimum,
            'minimum',
            Sats.fromInt(30000),
          ),
        ),
        (
          SwapAmountOutOfBoundsFailure(
            limitAmountSat: BigInt.from(1000000),
            isMinimum: false,
          ),
          isA<P2pWalletOverMaximum>(),
        ),
        (
          const SwapAmountOutOfBoundsFailure(),
          isA<P2pWalletOutsideServiceLimits>(),
        ),
        (const SwapNetworkFailure(), isA<P2pWalletServiceUnreachable>()),
        (const SwapTimeoutFailure(), isA<P2pWalletServiceUnreachable>()),
        (
          const SwapRateLimitedFailure(retryAfter: Duration(days: 3)),
          isA<P2pWalletServiceBusy>().having(
            (r) => r.retryAfter,
            'retryAfter',
            const Duration(minutes: 10),
          ),
        ),
        (const SwapProviderFailure(), isA<P2pWalletServiceRefused>()),
      ]) {
        swaps.quoteFailure = failure;
        final refusal = refusalOf(await make());
        expect(refusal, matcher, reason: '$failure');
        expect(refusal.logMessage, isNull);
      }
      expect(swaps.created, isEmpty);
    });

    test('a quote that does not fix the amount', () async {
      for (final (inAmount, outAmount) in [(25001, 24950), (25000, 25001)]) {
        swaps.quoteIn = inAmount;
        swaps.quoteOut = outAmount;
        expect(
          refusalOf(await make()),
          isA<P2pWalletServiceRefused>(),
          reason: '$inAmount $outAmount',
        );
      }
      expect(swaps.created, isEmpty);
    });

    test('an address the wallet cannot give', () async {
      addresses.error = StateError('no metadata');
      expect(refusalOf(await make()), isA<P2pWalletUnavailable>());
      expect(swaps.created, isEmpty);
    });

    test('an order that is not the one asked', () async {
      for (final change in <OrderSwapRecord Function(OrderSwapRecord)>[
        (r) => _with(r, purpose: OrderSwapPurpose.sendLightning),
        (r) => _with(r, destinationWalletId: 'other'),
        (r) => _with(r, destination: 'lq1other'),
        (r) => _with(r, environment: OrderSwapEnvironment.testnet),
        (r) => _with(r, note: 'Auto-Transfer'),
      ]) {
        swaps.changeCreated = change;
        expect(refusalOf(await make()), isA<P2pWalletServiceRefused>());
      }
    });

    test('an order\'s invoice that is not what the port promises', () async {
      final deadline = testNow.add(const Duration(minutes: 10));
      for (final (label, setUp) in <(String, void Function())>[
        ('no invoice', () => swaps.invoiceText = null),
        ('unreadable', () => decoder.readable = false),
        ('another amount', () => decoder.amount = 24999),
        ('another network', () => decoder.testnet = true),
        ('order of another amount', () => swaps.payin = 24999),
        (
          'expires before the deadline',
          () => decoder.expiresAt = deadline.subtract(
            const Duration(seconds: 1),
          ),
        ),
        // The money rule: an invoice that outlives the order could be paid after the service stopped waiting for it.
        (
          'expires after the deadline and its tolerance',
          () => decoder.expiresAt = deadline.add(const Duration(seconds: 11)),
        ),
        (
          'too little left',
          () {
            swaps.deadline = testNow.add(const Duration(seconds: 59));
            decoder.expiresAt = testNow.add(const Duration(seconds: 59));
          },
        ),
        ('more received than asked', () => swaps.payout = 25001),
      ]) {
        setUp();
        expect(
          refusalOf(await make()),
          isA<P2pWalletServiceRefused>(),
          reason: label,
        );
        swaps.reset();
        decoder.reset();
      }
    });

    test('an invoice expiring with the order, to the tolerance, is given', () async {
      final deadline = testNow.add(const Duration(minutes: 10));
      for (final (orderDeadline, expiresAt) in [
        (deadline, deadline),
        (deadline, deadline.add(const Duration(seconds: 10))),
        // The deadline may carry a fraction of a second, the invoice's expiry does not.
        (deadline.add(const Duration(milliseconds: 500)), deadline),
      ]) {
        swaps.deadline = orderDeadline;
        decoder.expiresAt = expiresAt;
        expect(await make(), isA<Ok>(), reason: '$orderDeadline $expiresAt');
        swaps.reset();
        decoder.reset();
      }
    });
  });

  group('an earlier invoice still waiting', () {
    test('is given again rather than a new order', () async {
      final first = invoiceOf(await make());
      final second = invoiceOf(await make());
      expect(second.bolt11, first.bolt11);
      expect(swaps.created, hasLength(1));
      expect(swaps.quotes, hasLength(1));
      expect(addresses.calls, hasLength(1));
    });

    test('is not given again for another amount', () async {
      await make();
      await make(amount: 26000);
      expect(swaps.created, hasLength(2));
    });

    test('is not given again once paid, expired or near its end, nor if it is not this feature\'s for this wallet', () async {
      for (final (label, change) in <(String, OrderSwapRecord Function(OrderSwapRecord))>[
        ('paid', (r) => _with(r, status: OrderSwapLocalStatus.payoutInProgress)),
        ('completed', (r) => _with(r, status: OrderSwapLocalStatus.completed)),
        ('expired', (r) => _with(r, status: OrderSwapLocalStatus.expired)),
        ('another wallet', (r) => _with(r, destinationWalletId: 'other')),
        ('another note', (r) => _with(r, note: 'Auto-Transfer')),
        ('a send', (r) => _with(r, purpose: OrderSwapPurpose.sendLightning)),
        (
          'near its end',
          (r) => _with(r, deadline: testNow.add(const Duration(seconds: 59))),
        ),
      ]) {
        swaps.reset();
        await make();
        final made = swaps.created.length;
        swaps.records.updateAll((_, record) => change(record));
        await make();
        expect(swaps.created, hasLength(made + 1), reason: label);
      }
    });

    test('two calls at once make one order, the second given the first one\'s invoice', () async {
      final both = await Future.wait([make(), make()]);
      expect(invoiceOf(both[0]).bolt11, invoiceOf(both[1]).bolt11);
      expect(swaps.created, hasLength(1));
    });
  });
}

InstantWallet _wallet({bool isTestnet = false}) => InstantWallet(
  id: 'instant',
  balance: Sats.zero,
  isTestnet: isTestnet,
  signsHere: true,
);

final class _Wallets implements InstantWalletRepository {
  InstantWallet wallet = _wallet();
  P2pWalletRefusal? readError;

  @override
  Future<Result<InstantWallet, P2pWalletRefusal>> read() async {
    if (readError case final refusal?) return Err(refusal);
    return Ok(wallet);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('InstantWalletRepository.${invocation.memberName} used');
}

/// The wallet's decoder: it reads the order's invoice text as the test says.
final class _Decoder implements WalletInvoiceRepository {
  bool readable = true;
  int amount = 25000;
  bool testnet = false;
  DateTime? expiresAt;

  void reset() {
    readable = true;
    amount = 25000;
    testnet = false;
    expiresAt = null;
  }

  @override
  Future<Result<WalletInvoice, P2pWalletRefusal>> read(String bolt11) async {
    if (!readable) return const Err(P2pWalletInvoiceUnreadable());
    return Ok(
      WalletInvoice(
        amount: Sats.fromInt(amount),
        paymentHash: 'ab' * 32,
        expiresAt: expiresAt ?? testNow.add(const Duration(minutes: 10)),
        isTestnet: testnet,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('WalletInvoiceRepository.${invocation.memberName} used');
}

/// The wallet's receive address use case: a new address each call.
final class _Addresses implements GetReceiveAddressUsecase {
  Object? error;
  final List<({String walletId, bool generateNew})> calls = [];

  @override
  Future<WalletAddress> execute({
    required String walletId,
    bool generateNew = false,
  }) async {
    calls.add((walletId: walletId, generateNew: generateNew));
    if (error case final error?) throw error;
    return WalletAddress(
      walletId: walletId,
      index: calls.length,
      address: 'lq1new${calls.length}',
      createdAt: testNow,
      updatedAt: testNow,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The Swap feature's facade for receive orders, in memory: the quote, the orders of a wallet and the creation. Any other member fails the test; no test reaches the service.
final class _ReceiveSwaps implements SwapFacade {
  final _Decoder decoder;
  final Map<String, OrderSwapRecord> records = {};
  final List<
    ({
      OrderSwapEnvironment environment,
      BigInt amountSat,
      bool isInAmountFixed,
      OrderSwapNetwork inNetwork,
      OrderSwapNetwork outNetwork,
    })
  >
  quotes = [];
  final List<Map<String, Object?>> created = [];
  final List<SwapFailure> createFailures = [];
  var createAttempts = 0;
  bool appUpdateRequired = false;
  SwapFailure? quoteFailure;
  SwapFailure? ordersFailure;
  int? quoteIn;
  int? quoteOut;
  String? invoiceText = 'lnbcreceive1';
  int? payin;
  int? payout;
  DateTime? deadline;
  OrderSwapRecord Function(OrderSwapRecord)? changeCreated;

  _ReceiveSwaps(this.decoder);

  void reset() {
    records.clear();
    quoteIn = null;
    quoteOut = null;
    invoiceText = 'lnbcreceive1';
    payin = null;
    payout = null;
    deadline = null;
    changeCreated = null;
  }

  @override
  bool get isAppUpdateRequired => appUpdateRequired;

  @override
  Future<Result<OrderSwapQuote, SwapFailure>> getQuote({
    required OrderSwapEnvironment environment,
    required BigInt amountSat,
    required bool isInAmountFixed,
    required OrderSwapNetwork inNetwork,
    required OrderSwapNetwork outNetwork,
  }) async {
    quotes.add((
      environment: environment,
      amountSat: amountSat,
      isInAmountFixed: isInAmountFixed,
      inNetwork: inNetwork,
      outNetwork: outNetwork,
    ));
    if (quoteFailure case final failure?) return Err(failure);
    return Ok(
      OrderSwapQuote(
        inAmountSat: BigInt.from(quoteIn ?? amountSat.toInt()),
        outAmountSat: BigInt.from(quoteOut ?? amountSat.toInt() - 50),
        inNetwork: inNetwork,
        outNetwork: outNetwork,
        inCurrency: 'BTC',
        outCurrency: 'LBTC',
        feeBasisPoints: 20,
        warnings: const [],
      ),
    );
  }

  @override
  Future<Result<List<OrderSwapRecord>, SwapFailure>> getOrders({
    String? walletId,
  }) async {
    if (ordersFailure case final failure?) return Err(failure);
    return Ok([
      for (final record in records.values)
        if (walletId == null ||
            record.destinationWalletId == walletId ||
            record.sourceWalletId == walletId)
          record,
    ]);
  }

  @override
  Future<Result<OrderSwapRecord, SwapFailure>> createOrder({
    required BigInt amountSat,
    required bool isInAmountFixed,
    required OrderSwapNetwork inNetwork,
    required OrderSwapNetwork outNetwork,
    required String destinationAddress,
    required String? fallbackAddress,
    required OrderSwapPurpose purpose,
    required OrderSwapEnvironment environment,
    String? sourceWalletId,
    String? destinationWalletId,
    String? note,
    BigInt? quotedCounterpartAmountSat,
  }) async {
    createAttempts++;
    if (createFailures.isNotEmpty) return Err(createFailures.removeAt(0));
    created.add({
      'amountSat': amountSat,
      'isInAmountFixed': isInAmountFixed,
      'inNetwork': inNetwork,
      'outNetwork': outNetwork,
      'destinationAddress': destinationAddress,
      'fallbackAddress': fallbackAddress,
      'purpose': purpose,
      'environment': environment,
      'sourceWalletId': sourceWalletId,
      'destinationWalletId': destinationWalletId,
      'note': note,
      'quotedCounterpartAmountSat': quotedCounterpartAmountSat,
    });
    final localId = 'receive-${created.length}';
    var record = _record(
      localId: localId,
      amount: amountSat,
      destination: destinationAddress,
      walletId: destinationWalletId,
      environment: environment,
      note: note,
      purpose: purpose,
      invoice: invoiceText,
      payin: payin == null ? amountSat : BigInt.from(payin ?? 0),
      payout: BigInt.from(payout ?? amountSat.toInt() - 50),
      deadline: deadline,
    );
    if (changeCreated case final change?) record = change(record);
    records[localId] = record;
    return Ok(record);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('SwapFacade.${invocation.memberName} used');
}

OrderSwapRecord _record({
  required String localId,
  required BigInt amount,
  required String destination,
  required String? walletId,
  required OrderSwapEnvironment environment,
  required String? note,
  required OrderSwapPurpose purpose,
  required String? invoice,
  required BigInt payin,
  required BigInt payout,
  DateTime? deadline,
  OrderSwapLocalStatus status = OrderSwapLocalStatus.awaitingUserConfirmation,
}) => OrderSwapRecord(
  localId: localId,
  purpose: purpose,
  environment: environment,
  inNetwork: OrderSwapNetwork.lightning,
  outNetwork: OrderSwapNetwork.liquid,
  isInAmountFixed: true,
  requestedAmountSat: amount,
  quotedCounterpartAmountSat: payout,
  destination: destination,
  fallback: '',
  createdAt: testNow,
  localStatus: status,
  destinationWalletId: walletId,
  note: note,
  order: OrderSwap(
    orderId: 'order-$localId',
    orderNumber: 1,
    inNetwork: OrderSwapNetwork.lightning,
    outNetwork: OrderSwapNetwork.liquid,
    payinAmountSat: payin <= BigInt.zero ? BigInt.one : payin,
    payoutAmountSat: payout <= BigInt.zero ? BigInt.one : payout,
    payinCurrency: 'BTC',
    payoutCurrency: 'LBTC',
    payinMethod: 'lightning',
    payoutMethod: 'liquid',
    orderType: 'funding',
    orderStatus: 'pending',
    payinStatus: 'pending',
    payoutStatus: 'pending',
    messageCode: 'ok',
    createdAt: testNow,
    confirmationDeadline: deadline ?? testNow.add(const Duration(minutes: 10)),
    lightningInvoice: invoice,
  ),
);

/// [record] with the fields given changed.
OrderSwapRecord _with(
  OrderSwapRecord record, {
  OrderSwapPurpose? purpose,
  String? destinationWalletId,
  String? destination,
  OrderSwapEnvironment? environment,
  String? note,
  OrderSwapLocalStatus? status,
  DateTime? deadline,
}) {
  final order = record.order;
  return _record(
    localId: record.localId,
    amount: record.requestedAmountSat,
    destination: destination ?? record.destination,
    walletId: destinationWalletId ?? record.destinationWalletId,
    environment: environment ?? record.environment,
    note: note ?? record.note,
    purpose: purpose ?? record.purpose,
    invoice: order?.lightningInvoice,
    payin: order?.payinAmountSat ?? record.requestedAmountSat,
    payout: order?.payoutAmountSat ?? BigInt.one,
    deadline: deadline ?? order?.confirmationDeadline,
    status: status ?? record.localStatus,
  );
}
