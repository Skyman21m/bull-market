import 'dart:async';
import 'dart:io';

import 'package:bb_mobile/core/wallet/domain/entities/wallet_address.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_receive_address_usecase.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/instant_wallet.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/wallet_invoice.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/instant_wallet_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_invoice_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/repositories/wallet_payment_repository.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/receive_wallet_invoice_usecase.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart';
import 'package:bull_logger/bull_logger.dart';
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
    String payout = 'trade-1',
  }) => usecase.execute(network, Sats.fromInt(amount), payout: payout);

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

    test(
      'on testnet asks the testnet service, from a testnet wallet',
      () async {
        wallets.wallet = _wallet(isTestnet: true);
        decoder.testnet = true;
        expect(await make(network: RobosatsNetwork.testnet), isA<Ok>());
        expect(swaps.quotes.single.environment, OrderSwapEnvironment.testnet);
        expect(
          swaps.created.single['environment'],
          OrderSwapEnvironment.testnet,
        );
      },
    );

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

    test(
      'the wallet\'s orders unreadable: what the store could answer is not known',
      () async {
        swaps.ordersFailure = const SwapStorageFailure();
        expect(refusalOf(await make()), isA<P2pWalletUnavailable>());
        expect(swaps.quotes, isEmpty);
        expect(swaps.created, isEmpty);
      },
    );
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
        // A fresh store each time: an earlier order of the loop could be given again.
        swaps
          ..reset()
          ..changeCreated = change;
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
        // An order of another amount than asked cannot be recorded: the wallet's record refuses it (`OrderSwapRecord`, « Server order does not preserve the fixed amount »).
        (
          'expires before the deadline',
          () =>
              decoder.expiresAt = deadline.subtract(const Duration(seconds: 1)),
        ),
        // The money rule: an invoice that outlives the order could be paid after the service stopped waiting for it.
        (
          'expires after the deadline and its tolerance',
          () => decoder.expiresAt = deadline.add(const Duration(seconds: 2)),
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

    test(
      'an invoice expiring with the order, to the tolerance, is given',
      () async {
        final deadline = testNow.add(const Duration(minutes: 10));
        for (final (orderDeadline, expiresAt) in [
          (deadline, deadline),
          (deadline, deadline.add(const Duration(seconds: 1))),
          // The deadline may carry a fraction of a second, the invoice's expiry does not.
          (deadline.add(const Duration(milliseconds: 500)), deadline),
        ]) {
          swaps.deadline = orderDeadline;
          decoder.expiresAt = expiresAt;
          expect(await make(), isA<Ok>(), reason: '$orderDeadline $expiresAt');
          swaps.reset();
          decoder.reset();
        }
      },
    );
  });

  test(
    'prints and logs nothing, so nothing of an invoice, an address or an answer',
    () async {
      final output = await _capture(() async {
        final invoice = invoiceOf(await make());
        expect('$invoice', 'P2pWalletInvoice');
        await make();
        swaps.quoteFailure = SwapAmountOutOfBoundsFailure(
          limitAmountSat: BigInt.from(30000),
          isMinimum: true,
          logMessage: 'Amount below 0.0003',
        );
        await make(payout: 'trade-2');
        swaps.quoteFailure = null;
        decoder.readable = false;
        await make(payout: 'trade-3');
      });
      final lines = output
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      expect(lines, hasLength(2));
      expect(lines.first, 'print capture works');
      expect(lines.last, contains('logger capture works'));
      expect(output.contains('lnbcreceive'), isFalse);
      expect(output.contains('lq1new'), isFalse);
    },
  );

  group('an earlier invoice still waiting', () {
    String? bolt11Of(Result<P2pWalletInvoice, P2pWalletRefusal> result) =>
        switch (result) {
          Ok(:final value) => value.bolt11,
          Err() => null,
        };

    test(
      'is given again for the same payout rather than a new order',
      () async {
        final first = invoiceOf(await make());
        final second = invoiceOf(await make());
        expect(second.bolt11, first.bolt11);
        expect(swaps.created, hasLength(1));
        expect(swaps.quotes, hasLength(1));
        expect(addresses.calls, hasLength(1));
      },
    );

    test(
      'is never given to another payout of the same amount: the store would answer it, and it is refused (review of #150, P1)',
      () async {
        final a = invoiceOf(await make(payout: 'trade-A'));
        // Liquid's next unused address is the same until paid, and the store answers the waiting order of the same request.
        final b = await make(payout: 'trade-B');
        expect(refusalOf(b), isA<P2pWalletAnotherInvoiceWaiting>());
        expect(swaps.answered, ['receive-1']);
        expect(swaps.created, hasLength(1));
        // Payout A still gets its own.
        expect(bolt11Of(await make(payout: 'trade-A')), a.bolt11);
        // And B, asked again while A's order waits, is refused again, never remembered.
        expect(
          refusalOf(await make(payout: 'trade-B')),
          isA<P2pWalletAnotherInvoiceWaiting>(),
        );
      },
    );

    test(
      'is never given to another payout after a restart either (review of #150, P2)',
      () async {
        final a = invoiceOf(await make(payout: 'trade-A'));
        ReceiveWalletInvoiceUsecase restarted() => ReceiveWalletInvoiceUsecase(
          wallets,
          decoder,
          swaps,
          addresses,
          () => testNow,
        );
        final b = await restarted().execute(
          RobosatsNetwork.mainnet,
          Sats.fromInt(25000),
          payout: 'trade-B',
        );
        expect(refusalOf(b), isA<P2pWalletAnotherInvoiceWaiting>());
        // The keys are forgotten: payout A too is refused while its order of before waits.
        final again = await restarted().execute(
          RobosatsNetwork.mainnet,
          Sats.fromInt(25000),
          payout: 'trade-A',
        );
        expect(refusalOf(again), isA<P2pWalletAnotherInvoiceWaiting>());
        expect(bolt11Of(b), isNot(a.bolt11));
        // Once that order ended, a new one is made.
        swaps.records.updateAll(
          (_, record) => _with(record, status: OrderSwapLocalStatus.expired),
        );
        final after = await restarted().execute(
          RobosatsNetwork.mainnet,
          Sats.fromInt(25000),
          payout: 'trade-B',
        );
        expect(after, isA<Ok>());
        expect(swaps.created, hasLength(2));
      },
    );

    test(
      'is never an order of the wallet\'s Receive screen: listed elsewhere, or answered by the store (review of #150, I1)',
      () async {
        // An order of the wallet's Receive screen, waiting, same amount, same wallet: to another address it is only listed.
        swaps.records['screen-1'] = _record(
          localId: 'screen-1',
          amount: BigInt.from(25000),
          destination: 'lq1screen',
          walletId: 'instant',
          environment: OrderSwapEnvironment.mainnet,
          note: null,
          purpose: OrderSwapPurpose.receiveLightning,
          invoice: 'lnbcscreen1',
          payin: BigInt.from(25000),
          payout: BigInt.from(24950),
        );
        final made = invoiceOf(await make());
        expect(made.bolt11, 'lnbcreceive1');
        // Asked again for the same payout, the use case gives its own order's invoice, not the other waiting order listed before it.
        expect(invoiceOf(await make()).bolt11, 'lnbcreceive1');
        expect(swaps.created, hasLength(1));
      },
    );

    test(
      'a Receive screen\'s order to the same address, which the store answers, blocks the payouts of that amount until it ends',
      () async {
        swaps.records['screen-1'] = _record(
          localId: 'screen-1',
          amount: BigInt.from(25000),
          destination: 'lq1new1',
          walletId: 'instant',
          environment: OrderSwapEnvironment.mainnet,
          note: null,
          purpose: OrderSwapPurpose.receiveLightning,
          invoice: 'lnbcscreen1',
          payin: BigInt.from(25000),
          payout: BigInt.from(24950),
        );
        expect(refusalOf(await make()), isA<P2pWalletAnotherInvoiceWaiting>());
        expect(swaps.answered, ['screen-1']);
        expect(swaps.created, isEmpty);
        // Another amount is another request.
        decoder.amount = 26000;
        expect(await make(amount: 26000), isA<Ok>());
      },
    );

    test(
      'an invoice whose payment hash was given for another payout is refused',
      () async {
        // A service answering one invoice for two orders: different orders, the same text and hash.
        addresses.repeat = false;
        swaps.sameInvoice = true;
        expect(await make(payout: 'trade-A'), isA<Ok>());
        expect(
          refusalOf(await make(payout: 'trade-B')),
          isA<P2pWalletAnotherInvoiceWaiting>(),
        );
        expect(swaps.created, hasLength(2));
        // The payout it was given for still gets it.
        expect(await make(payout: 'trade-A'), isA<Ok>());
      },
    );

    test('is not given again for another amount', () async {
      await make();
      await make(amount: 26000);
      expect(swaps.created, hasLength(2));
    });

    test(
      'is not given again once paid, expired or near its end, nor once it is no longer this feature\'s receive order',
      () async {
        for (final (label, change)
            in <(String, OrderSwapRecord Function(OrderSwapRecord))>[
              (
                'paid',
                (r) => _with(r, status: OrderSwapLocalStatus.payoutInProgress),
              ),
              (
                'completed',
                (r) => _with(r, status: OrderSwapLocalStatus.completed),
              ),
              (
                'expired',
                (r) => _with(r, status: OrderSwapLocalStatus.expired),
              ),
              ('another wallet', (r) => _with(r, destinationWalletId: 'other')),
              ('another note', (r) => _with(r, note: 'Auto-Transfer')),
              (
                'a send',
                (r) => _with(r, purpose: OrderSwapPurpose.sendLightning),
              ),
              (
                'another network',
                (r) => _with(r, environment: OrderSwapEnvironment.testnet),
              ),
              (
                'near its end',
                (r) => _with(
                  r,
                  deadline: testNow.add(const Duration(seconds: 59)),
                ),
              ),
            ]) {
          swaps.reset();
          final first = invoiceOf(await make()).bolt11;
          swaps.records.updateAll((_, record) => change(record));
          // Either refused, or a new order: never the first invoice again.
          expect(bolt11Of(await make()), isNot(first), reason: label);
        }
      },
    );

    test(
      'two calls at once for one payout make one order, the second given the first one\'s invoice',
      () async {
        final both = await Future.wait([make(), make()]);
        expect(invoiceOf(both[0]).bolt11, invoiceOf(both[1]).bolt11);
        expect(swaps.created, hasLength(1));
      },
    );

    test(
      'two calls at once for two payouts of the same amount: one order, the second payout refused',
      () async {
        final both = await Future.wait([
          make(payout: 'trade-1'),
          make(payout: 'trade-2'),
        ]);
        expect(both[0], isA<Ok>());
        expect(refusalOf(both[1]), isA<P2pWalletAnotherInvoiceWaiting>());
        expect(swaps.created, hasLength(1));
      },
    );

    test(
      'an order whose invoice was refused is never given; while it waits, the store answers it and the amount is refused',
      () async {
        decoder.readable = false;
        expect(refusalOf(await make()), isA<P2pWalletServiceRefused>());
        decoder.readable = true;
        // The refused order waits at the service until its deadline, and the store answers it for the same request.
        expect(refusalOf(await make()), isA<P2pWalletAnotherInvoiceWaiting>());
        expect(swaps.created, hasLength(1));
        // Once it ended, a new order.
        swaps.records.updateAll(
          (_, record) => _with(record, status: OrderSwapLocalStatus.expired),
        );
        expect(invoiceOf(await make()).bolt11, 'lnbcreceive2');
      },
    );

    test(
      'a call that throws lets the next one run (review of #150, M1)',
      () async {
        wallets.throwing = StateError('wallet read failed');
        await expectLater(make(), throwsStateError);
        wallets.throwing = null;
        final both = await Future.wait([
          make(),
          make(),
        ]).timeout(const Duration(seconds: 5));
        expect(invoiceOf(both[0]).bolt11, invoiceOf(both[1]).bolt11);
      },
    );
  });

  group('boundaries (review of #150, M2)', () {
    test('a wait of exactly 30 s is taken once', () async {
      swaps.createFailures.add(
        const SwapRateLimitedFailure(retryAfter: Duration(seconds: 30)),
      );
      expect(await make(), isA<Ok>());
      expect(waits, [const Duration(seconds: 30)]);
    });

    test(
      'a quote paying out the whole amount, and an order with no fee, are taken: the fee is the service\'s to set',
      () async {
        swaps
          ..quoteOut = 25000
          ..payout = 25000;
        final invoice = invoiceOf(await make());
        expect(invoice.received, Sats.fromInt(25000));
        expect(invoice.fee, Sats.zero);
      },
    );

    test('the tolerance after the deadline is one second', () async {
      expect(
        ReceiveWalletInvoiceUsecase.deadlineTolerance,
        const Duration(seconds: 1),
      );
      final deadline = testNow.add(const Duration(minutes: 10));
      swaps.deadline = deadline;
      decoder.expiresAt = deadline.add(const Duration(seconds: 1));
      expect(await make(payout: 'a'), isA<Ok>());
      swaps.reset();
      decoder.reset();
      swaps.deadline = deadline;
      decoder.expiresAt = deadline.add(const Duration(seconds: 2));
      expect(
        refusalOf(await make(payout: 'b')),
        isA<P2pWalletServiceRefused>(),
      );
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
  Object? throwing;

  @override
  Future<Result<InstantWallet, P2pWalletRefusal>> read() async {
    if (throwing case final error?) throw error;
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
        // One hash per invoice text, as a real decoder reads it.
        paymentHash: bolt11.hashCode.toRadixString(16).padLeft(64, '0'),
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
/// The wallet's receive address use case. As on Liquid (`WalletAddressRepository.generateNewReceiveAddress`: the last unused index plus one, recorded nowhere), it gives the same address at each call until something pays it, unless [repeat] is turned off.
final class _Addresses implements GetReceiveAddressUsecase {
  Object? error;
  bool repeat = true;
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
      index: repeat ? 1 : calls.length,
      address: repeat ? 'lq1new1' : 'lq1new${calls.length}',
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

  /// The local ids of the earlier orders the store answered instead of a new one.
  final List<String> answered = [];
  final List<SwapFailure> createFailures = [];
  var createAttempts = 0;

  /// As the wallet's store (`OrderSwapRepositoryImpl._createOrderLocked`): an active order of the same request (purpose, network, fixed side, amount, destination) is answered instead of a new one.
  bool dedup = true;

  /// Each new order's invoice the same text (and so the same payment hash), as a service that answered one invoice for two orders would.
  bool sameInvoice = false;
  bool appUpdateRequired = false;
  SwapFailure? quoteFailure;
  SwapFailure? ordersFailure;
  int? quoteIn;
  int? quoteOut;

  /// The stem of each order's invoice text, numbered by order (`lnbcreceive1`, `lnbcreceive2`…); `null` for an order without one.
  String? invoiceText = 'lnbcreceive';
  int? payin;
  int? payout;
  DateTime? deadline;
  OrderSwapRecord Function(OrderSwapRecord)? changeCreated;

  _ReceiveSwaps(this.decoder);

  void reset() {
    records.clear();
    quoteIn = null;
    quoteOut = null;
    invoiceText = 'lnbcreceive';
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
    if (dedup) {
      for (final record in records.values) {
        if (record.purpose == purpose &&
            record.environment == environment &&
            record.inNetwork == inNetwork &&
            record.outNetwork == outNetwork &&
            record.isInAmountFixed == isInAmountFixed &&
            record.requestedAmountSat == amountSat &&
            record.destination == destinationAddress &&
            record.sourceWalletId == sourceWalletId &&
            !record.localStatus.isTerminal) {
          answered.add(record.localId);
          return Ok(record);
        }
      }
    }
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
      invoice: invoiceText == null
          ? null
          : sameInvoice
          ? invoiceText
          : '$invoiceText${created.length}',
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
  // As the wallet's store records a receive order: its destination as the fallback (`OrderSwapRepositoryImpl.createOrder`).
  fallback: destination,
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

/// Everything [body] prints and everything the project logger writes while it runs, as one text; a line printed and a line logged by the capture itself show that both are seen.
Future<String> _capture(Future<void> Function() body) async {
  final printed = <String>[];
  final directory = Directory.systemTemp.createTempSync('p2p_wallet_receive');
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
