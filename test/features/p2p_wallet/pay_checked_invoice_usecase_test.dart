import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:bb_mobile/core/entities/signer_device_entity.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/wallet/domain/consolidation_required_exception.dart';
import 'package:bb_mobile/core/wallet/domain/insufficient_funds_exception.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/no_spendable_utxo_exception.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_failure.dart';
import 'package:bb_mobile/features/p2p_wallet/data/instant_wallet_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/data/wallet_payment_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/issued_quotes.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/wallet_invoice.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/usecases/pay_checked_invoice_usecase.dart';
import 'package:bb_mobile/features/swap/public/swap_facade.dart';
import 'package:bull_logger/bull_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/testing.dart' show checkedBolt11InvoiceForTesting;

import 'support/fakes.dart';
import 'support/payment_fakes.dart';

/// The payment of a checked invoice (#100, W3), over fakes of the Swap feature's facade and of the wallet: every exit of the sequence, what moved and what was recorded at each, and the order of the side effects. Nothing is real: no order reaches a swap service, nothing is signed or broadcast.
void main() {
  late Journal journal;
  late DateTime now;
  late FakeGetWallets getWallets;
  late FakePayingLiquid liquid;
  late FakeOrderSwaps swaps;
  late FakeWalletInvoices invoices;
  late FakeRefundAddress refund;
  late FakeBroadcast broadcast;
  late IssuedQuotes issued;
  late List<Duration> waits;
  late PayCheckedInvoiceUsecase pay;

  PayCheckedInvoiceUsecase build() => PayCheckedInvoiceUsecase(
    issued,
    InstantWalletRepositoryImpl(
      getWallets,
      FakeWatchSyncs(),
      FakeGetAddressAtIndex(),
      liquid,
    ),
    invoices,
    WalletPaymentRepositoryImpl(swaps, invoices),
    swaps,
    liquid,
    refund,
    broadcast,
    () => now,
    delay: (wait) async {
      waits.add(wait);
      now = now.add(wait);
    },
  );

  void reset() {
    journal = Journal();
    now = testNow;
    getWallets = FakeGetWallets(Ok([testWallet()]));
    liquid = FakePayingLiquid(journal);
    swaps = FakeOrderSwaps(journal, () => now);
    invoices = FakeWalletInvoices();
    refund = FakeRefundAddress(journal);
    broadcast = FakeBroadcast(journal);
    issued = IssuedQuotes();
    waits = [];
    pay = build();
  }

  setUp(reset);

  tearDown(() => swaps.close());

  /// A quote of [invoice] the wallet gave (unless [issue] is false), accepted by the user.
  P2pWalletQuote quoteOf(
    CheckedBolt11Invoice invoice, {
    int payin = 603,
    int fee = 26,
    int balance = 10000,
    DateTime? at,
    bool issue = true,
  }) {
    final quote = P2pWalletQuote(
      invoice: invoice,
      payin: Sats.fromInt(payin),
      networkFee: Sats.fromInt(fee),
      balance: Sats.fromInt(balance),
      quotedAt: at ?? now,
    );
    if (issue) issued.issue(quote);
    return quote;
  }

  /// Pays [invoice] (readable by the wallet's decoder) with [quote], or a fresh quote of it.
  Future<Result<P2pWalletPayment, P2pWalletRefusal>> payOf(
    CheckedBolt11Invoice invoice, {
    P2pWalletQuote? quote,
    bool learn = true,
  }) {
    if (learn && !invoices.known.containsKey(invoice.bolt11)) {
      invoices.learn(invoice);
    }
    return pay.execute(invoice, accepted: quote ?? quoteOf(invoice));
  }

  P2pWalletRefusal refusalOf(Result<P2pWalletPayment, P2pWalletRefusal> r) =>
      switch (r) {
        Err(:final failure) => failure,
        Ok() => fail('paid'),
      };

  P2pWalletPayment paymentOf(Result<P2pWalletPayment, P2pWalletRefusal> r) =>
      switch (r) {
        Ok(:final value) => value,
        Err(:final failure) => fail('refused: $failure'),
      };

  /// Nothing was signed, saved, marked or broadcast.
  void expectNothingMoved() => expect(
    journal.only({'sign', 'save', 'markUnknown', 'broadcast', 'markBroadcast'}),
    isEmpty,
  );

  /// No order was asked for, so nothing at all.
  void expectNoOrder() {
    expect(journal.only({'create', 'refund-address'}), isEmpty);
    expect(swaps.records, isEmpty);
    expectNothingMoved();
  }

  group('a payment that goes through', () {
    test(
      'creates the order, builds, checks, signs, saves, marks, broadcasts the saved transaction, marks it broadcast, in that order',
      () async {
        final invoice = payInvoice();
        final payment = paymentOf(await payOf(invoice));
        expect(payment.id, 'local-1');
        expect(payment.paymentHash, invoice.paymentHash);
        expect(journal.events, [
          'refund-address',
          'create',
          'build:lq1payin1:603:25',
          'sign:pset1',
          'save:signed-pset1',
          'markUnknown',
          'broadcast:signed-pset1',
          'markBroadcast:txid-of-signed-pset1',
        ]);
        final record = swaps.records['local-1'];
        expect(record?.localStatus, OrderSwapLocalStatus.payinBroadcast);
        expect(record?.signedPayinTransaction, 'signed-pset1');
        expect(record?.localPayinTransactionId, 'txid-of-signed-pset1');
        // What the order was asked: the invoice, an address of the wallet for a refund, the payin accepted as the quote.
        expect(swaps.created.single, {
          'amount': BigInt.from(600),
          'fixedIn': false,
          'in': OrderSwapNetwork.liquid,
          'out': OrderSwapNetwork.lightning,
          'destination': invoice.bolt11,
          'refund': 'lq1refund',
          'purpose': OrderSwapPurpose.sendLightning,
          'environment': OrderSwapEnvironment.mainnet,
          'wallet': 'instant',
          'note': 'RoboSats',
          'quoted': BigInt.from(603),
        });
        // The refund address is the wallet's last revealed one, as the Send feature takes it; no new address is revealed.
        expect(refund.calls.single, (walletId: 'instant', generateNew: false));
        expect(broadcast.networks, [false]);
        // The invoice's text went to the wallet's decoder (and to the order above) only.
        expect(invoices.reads, everyElement(invoice.bolt11));
      },
    );

    test('on testnet, with the testnet service and network', () async {
      getWallets.answer = Ok([testWallet(isTestnet: true)]);
      final invoice = payInvoice(network: RobosatsNetwork.testnet);
      paymentOf(await payOf(invoice));
      expect(swaps.created.single['environment'], OrderSwapEnvironment.testnet);
      expect(broadcast.networks, [true]);
    });

    test('at the accepted payin and fee exactly, or below them', () async {
      final exact = payInvoice();
      paymentOf(await payOf(exact, quote: quoteOf(exact, payin: 603, fee: 26)));
      swaps.payinFor = (quoted) => quoted - BigInt.from(2);
      liquid.fee = 20;
      final cheaper = payInvoice(tag: 'p', hash: payHash(2));
      paymentOf(await payOf(cheaper));
      expect(journal.only({'build'}), [
        'build:lq1payin1:603:25',
        'build:lq1payin2:601:25',
      ]);
    });

    test(
      'the transaction broadcast is the one saved on the order, after it was saved and marked',
      () async {
        paymentOf(await payOf(payInvoice()));
        final saved = swaps.records['local-1']?.signedPayinTransaction;
        final events = journal.events;
        final save = events.indexOf('save:$saved');
        final mark = events.indexOf('markUnknown');
        final sent = events.indexOf('broadcast:$saved');
        expect(save, greaterThan(events.indexOf('sign:pset1')));
        expect(mark, greaterThan(save));
        expect(sent, greaterThan(mark));
        expect(
          events.indexOf('markBroadcast:txid-of-$saved'),
          greaterThan(sent),
        );
        expect(journal.only({'broadcast'}), ['broadcast:$saved']);
      },
    );

    test(
      'returns although the order cannot be marked broadcast: the broadcast is done',
      () async {
        swaps.markBroadcastError = StateError('store closed');
        final payment = paymentOf(await payOf(payInvoice()));
        expect(payment.id, 'local-1');
        expect(
          swaps.records['local-1']?.localStatus,
          OrderSwapLocalStatus.broadcastUnknown,
        );
      },
    );
  });

  group('the quote:', () {
    test('one the wallet did not give is refused, nothing asked', () async {
      final invoice = payInvoice();
      invoices.learn(invoice);
      expect(
        refusalOf(
          await pay.execute(invoice, accepted: quoteOf(invoice, issue: false)),
        ),
        isA<P2pWalletQuoteStale>(),
      );
      expectNoOrder();
      expect(invoices.reads, isEmpty);
    });

    test('is used once, whatever the first payment became', () async {
      final invoice = payInvoice(payableIn: const Duration(seconds: 30));
      final quote = quoteOf(invoice);
      // Refused for its time: the quote is used all the same.
      expect(
        refusalOf(await payOf(invoice, quote: quote)),
        isA<P2pWalletInvoiceExpiresTooSoon>(),
      );
      expect(
        refusalOf(await payOf(invoice, quote: quote)),
        isA<P2pWalletQuoteStale>(),
      );
      final paid = payInvoice(tag: 'p', hash: payHash(2));
      final once = quoteOf(paid);
      paymentOf(await payOf(paid, quote: once));
      expect(
        refusalOf(await payOf(paid, quote: once)),
        isA<P2pWalletQuoteStale>(),
      );
    });

    test('of another invoice is refused', () async {
      final invoice = payInvoice();
      for (final other in [
        payInvoice(tag: 'p'),
        payInvoice(hash: payHash(2)),
        payInvoice(amount: 601),
      ]) {
        expect(
          refusalOf(await payOf(invoice, quote: quoteOf(other))),
          isA<P2pWalletQuoteStale>(),
          reason: '$other',
        );
      }
      expectNoOrder();
      // The same invoice read again later, with another deadline, is the same invoice.
      final later = payInvoice(payableIn: const Duration(minutes: 2));
      paymentOf(await payOf(invoice, quote: quoteOf(later)));
    });

    test(
      'is refused when older than two minutes, or from ahead of the clock',
      () async {
        final invoice = payInvoice();
        expect(
          PayCheckedInvoiceUsecase.quoteMaxAge,
          const Duration(minutes: 2),
        );
        for (final at in [
          now.subtract(const Duration(minutes: 2, milliseconds: 1)),
          now.add(const Duration(milliseconds: 1)),
        ]) {
          expect(
            refusalOf(await payOf(invoice, quote: quoteOf(invoice, at: at))),
            isA<P2pWalletQuoteStale>(),
            reason: '$at',
          );
        }
        expectNoOrder();
        paymentOf(
          await payOf(
            invoice,
            quote: quoteOf(
              invoice,
              at: now.subtract(const Duration(minutes: 2)),
            ),
          ),
        );
      },
    );
  });

  group('the invoice and the wallet, before any order:', () {
    test('an invoice no longer payable, or within the margin', () async {
      expect(
        PayCheckedInvoiceUsecase.invoiceMargin,
        const Duration(seconds: 60),
      );
      for (final (payableIn, refusal) in [
        (Duration.zero, isA<P2pWalletInvoiceExpired>()),
        (const Duration(seconds: -1), isA<P2pWalletInvoiceExpired>()),
        (const Duration(seconds: 1), isA<P2pWalletInvoiceExpiresTooSoon>()),
        (
          const Duration(seconds: 59, milliseconds: 999),
          isA<P2pWalletInvoiceExpiresTooSoon>(),
        ),
      ]) {
        expect(
          refusalOf(await payOf(payInvoice(payableIn: payableIn))),
          refusal,
          reason: '$payableIn',
        );
      }
      expectNoOrder();
      // At the margin exactly, it pays.
      paymentOf(
        await payOf(
          payInvoice(tag: 'p', payableIn: const Duration(seconds: 60)),
        ),
      );
    });

    test('the wallet\'s decoder reads an earlier expiry', () async {
      final invoice = payInvoice();
      invoices.learn(
        invoice,
        read: WalletInvoice(
          amount: invoice.amount,
          paymentHash: invoice.paymentHash,
          expiresAt: now.add(const Duration(seconds: 59)),
          isTestnet: false,
        ),
      );
      expect(
        refusalOf(await payOf(invoice)),
        isA<P2pWalletInvoiceExpiresTooSoon>(),
      );
      expectNoOrder();
    });

    test(
      'the wallet\'s decoder reads another hash, amount or network, or nothing',
      () async {
        final invoice = payInvoice();
        for (final (read, refusal) in [
          (
            WalletInvoice(
              amount: invoice.amount,
              paymentHash: payHash(9),
              expiresAt: invoice.expiresAt,
              isTestnet: false,
            ),
            isA<P2pWalletInvoiceUnreadable>(),
          ),
          (
            WalletInvoice(
              amount: Sats.fromInt(601),
              paymentHash: invoice.paymentHash,
              expiresAt: invoice.expiresAt,
              isTestnet: false,
            ),
            isA<P2pWalletInvoiceUnreadable>(),
          ),
          (
            WalletInvoice(
              amount: invoice.amount,
              paymentHash: invoice.paymentHash,
              expiresAt: invoice.expiresAt,
              isTestnet: true,
            ),
            isA<P2pWalletWrongNetwork>(),
          ),
        ]) {
          invoices.learn(invoice, read: read);
          expect(refusalOf(await payOf(invoice)), refusal, reason: '$read');
        }
        invoices.known.clear();
        expect(
          refusalOf(await payOf(invoice, learn: false)),
          isA<P2pWalletInvoiceUnreadable>(),
        );
        expectNoOrder();
      },
    );

    test('an invoice of the other network than the wallet', () async {
      expect(
        refusalOf(await payOf(payInvoice(network: RobosatsNetwork.testnet))),
        isA<P2pWalletWrongNetwork>(),
      );
      expectNoOrder();
    });

    test(
      'no default Liquid wallet, one that does not sign here, or no read',
      () async {
        for (final (wallets, refusal) in [
          (
            const Err<List<Wallet>, WalletFailure>(NoWalletsFoundFailure()),
            isA<P2pWalletNoInstantWallet>(),
          ),
          (
            Ok<List<Wallet>, WalletFailure>([testWallet(isDefault: false)]),
            isA<P2pWalletNoInstantWallet>(),
          ),
          (
            Ok<List<Wallet>, WalletFailure>([testWallet(isLiquid: false)]),
            isA<P2pWalletNoInstantWallet>(),
          ),
          (
            Ok<List<Wallet>, WalletFailure>([
              testWallet(signer: SignerEntity.remote),
            ]),
            isA<P2pWalletUnavailable>(),
          ),
          (
            Ok<List<Wallet>, WalletFailure>([
              testWallet(signer: SignerEntity.none),
            ]),
            isA<P2pWalletUnavailable>(),
          ),
          (
            Ok<List<Wallet>, WalletFailure>([
              testWallet(signerDevice: SignerDeviceEntity.jade),
            ]),
            isA<P2pWalletUnavailable>(),
          ),
        ]) {
          getWallets.answer = wallets;
          expect(
            refusalOf(await payOf(payInvoice())),
            refusal,
            reason: '$wallets',
          );
        }
        getWallets.error = StateError('database locked');
        expect(
          refusalOf(await payOf(payInvoice())),
          isA<P2pWalletUnavailable>(),
        );
        expectNoOrder();
      },
    );
  });

  group('never twice:', () {
    test(
      "an invoice the wallet's records hold in any status, a refunded one included",
      () async {
        for (final status in OrderSwapLocalStatus.values) {
          reset();
          final invoice = payInvoice();
          final signed = switch (status) {
            OrderSwapLocalStatus.readyToBroadcast ||
            OrderSwapLocalStatus.broadcastUnknown => 'signed-earlier',
            _ => null,
          };
          swaps.hold(
            paymentRecord(
              destination: invoice.bolt11,
              status: status,
              signed: signed,
              transactionId: status == OrderSwapLocalStatus.payinBroadcast
                  ? 'txid-earlier'
                  : null,
              withOrder:
                  status != OrderSwapLocalStatus.creating &&
                  status != OrderSwapLocalStatus.creationUnknown,
            ),
          );
          expect(
            refusalOf(await payOf(invoice)),
            isA<P2pWalletAlreadyPaid>(),
            reason: status.name,
          );
          expect(journal.events, isEmpty, reason: status.name);
        }
      },
    );

    test(
      'whatever the record: another case, another purpose, another wallet, another note',
      () async {
        final invoice = payInvoice();
        for (final record in [
          paymentRecord(destination: invoice.bolt11.toUpperCase()),
          paymentRecord(
            destination: invoice.bolt11,
            purpose: OrderSwapPurpose.transfer,
          ),
          paymentRecord(destination: invoice.bolt11, walletId: 'another'),
          paymentRecord(
            destination: invoice.bolt11,
            walletId: null,
            note: null,
          ),
        ]) {
          swaps.records
            ..clear()
            ..[record.localId] = record;
          expect(refusalOf(await payOf(invoice)), isA<P2pWalletAlreadyPaid>());
        }
        expect(journal.events, isEmpty);
      },
    );

    test(
      'another invoice of the same payment hash that this feature paid',
      () async {
        final earlier = payInvoice(tag: 'p');
        invoices.learn(earlier);
        swaps.hold(
          paymentRecord(
            destination: earlier.bolt11,
            status: OrderSwapLocalStatus.refunded,
          ),
        );
        expect(
          refusalOf(await payOf(payInvoice())),
          isA<P2pWalletAlreadyPaid>(),
        );
        expect(journal.events, isEmpty);
        // An order of the wallet's own Send with the same hash is not this feature's: only its text would match.
        swaps.records.clear();
        swaps.hold(paymentRecord(destination: earlier.bolt11, note: 'my note'));
        paymentOf(await payOf(payInvoice()));
      },
    );

    test('records that cannot be read refuse the payment', () async {
      swaps.ordersFailure = const SwapStorageFailure('disk');
      expect(refusalOf(await payOf(payInvoice())), isA<P2pWalletUnavailable>());
      expectNoOrder();
    });

    test(
      'a second payment of an invoice is refused, whatever became of the first once it had an order',
      () async {
        final firsts = <String, void Function()>{
          'paid': () {},
          'broadcast unknown': () => broadcast.error = StateError('electrum'),
          'refused at the cap': () =>
              swaps.payinFor = (quoted) => quoted + BigInt.one,
          'refused for the fee': () => liquid.fee = 27,
          'signature failed': () => liquid.signError = StateError('secrets'),
          'save failed': () =>
              swaps.saveFailure = const SwapStorageFailure('disk'),
          'mark failed': () =>
              swaps.markUnknownFailure = const SwapStorageFailure('disk'),
          'consolidation needed': () =>
              liquid.buildError = ConsolidationRequiredException('many'),
        };
        for (final MapEntry(key: label, value: arrange) in firsts.entries) {
          reset();
          arrange();
          final invoice = payInvoice();
          await payOf(invoice);
          expect(swaps.records, hasLength(1), reason: label);
          broadcast.error = null;
          liquid
            ..signError = null
            ..buildError = null
            ..fee = 26;
          swaps
            ..payinFor = ((quoted) => quoted)
            ..saveFailure = null
            ..markUnknownFailure = null;
          journal.events.clear();
          expect(
            refusalOf(await payOf(invoice)),
            isA<P2pWalletAlreadyPaid>(),
            reason: label,
          );
          expect(journal.events, isEmpty, reason: label);
        }
      },
    );

    test(
      'a first attempt refused before any order leaves nothing to refuse a second on',
      () async {
        swaps.createFailures.add(const SwapNetworkFailure('down'));
        final invoice = payInvoice();
        expect(
          refusalOf(await payOf(invoice)),
          isA<P2pWalletServiceUnreachable>(),
        );
        // The wallet's store deletes an order whose creation was refused: nothing was created, so a new confirmation may pay.
        expect(swaps.records, isEmpty);
        paymentOf(await payOf(invoice));
      },
    );

    test(
      'two payments of one invoice at once: the second waits for the first, then sees its order',
      () async {
        final invoice = payInvoice();
        invoices.learn(invoice);
        final results = await Future.wait([
          pay.execute(invoice, accepted: quoteOf(invoice)),
          pay.execute(invoice, accepted: quoteOf(invoice)),
        ]);
        expect(
          results.whereType<Ok<P2pWalletPayment, P2pWalletRefusal>>(),
          hasLength(1),
        );
        expect(refusalOf(results.last), isA<P2pWalletAlreadyPaid>());
        expect(journal.only({'create'}), ['create']);
        expect(journal.only({'broadcast'}), hasLength(1));
      },
    );

    test(
      'the same quote presented twice at once pays once: the second is refused at its start',
      () async {
        final invoice = payInvoice();
        invoices.learn(invoice);
        final quote = quoteOf(invoice);
        final first = pay.execute(invoice, accepted: quote);
        final again = pay.execute(invoice, accepted: quote);
        final third = pay.execute(invoice, accepted: quoteOf(invoice));
        expect(refusalOf(await again), isA<P2pWalletQuoteStale>());
        paymentOf(await first);
        expect(refusalOf(await third), isA<P2pWalletAlreadyPaid>());
        expect(journal.only({'create'}), ['create']);
      },
    );

    test(
      'two payments of two invoices at once run one after the other',
      () async {
        final one = payInvoice();
        final two = payInvoice(tag: 'p', hash: payHash(2));
        invoices
          ..learn(one)
          ..learn(two);
        final results = await Future.wait([
          pay.execute(one, accepted: quoteOf(one)),
          pay.execute(two, accepted: quoteOf(two)),
        ]);
        expect(results.map(paymentOf).map((p) => p.id).toList(), [
          'local-1',
          'local-2',
        ]);
        final events = journal.events;
        expect(
          events.indexOf('markBroadcast:txid-of-signed-pset1'),
          lessThan(events.lastIndexOf('refund-address')),
        );
      },
    );
  });

  group('the order:', () {
    test('« app update required » stops before any order', () async {
      swaps.appUpdateRequired = true;
      expect(
        refusalOf(await payOf(payInvoice())),
        isA<P2pWalletServiceRefused>(),
      );
      expectNoOrder();
    });

    test('no refund address, no order', () async {
      refund.error = StateError('lwk');
      expect(refusalOf(await payOf(payInvoice())), isA<P2pWalletUnavailable>());
      expect(journal.only({'create'}), isEmpty);
      expectNothingMoved();
    });

    test(
      'each failure of the creation is a refusal, with nothing moved',
      () async {
        for (final (failure, refusal) in [
          (
            SwapAmountOutOfBoundsFailure(
              limitAmountSat: BigInt.from(1000),
              isMinimum: true,
            ),
            isA<P2pWalletUnderMinimum>().having(
              (r) => r.minimum,
              'minimum',
              Sats.fromInt(1000),
            ),
          ),
          (
            SwapAmountOutOfBoundsFailure(
              limitAmountSat: BigInt.from(100),
              isMinimum: false,
            ),
            isA<P2pWalletOverMaximum>(),
          ),
          (
            SwapAmountOutOfBoundsFailure(
              limitAmountSat: BigInt.parse('99999999999999999999'),
              isMinimum: true,
            ),
            isA<P2pWalletUnderMinimum>().having(
              (r) => r.minimum,
              'minimum',
              isNull,
            ),
          ),
          (
            const SwapAmountOutOfBoundsFailure(),
            isA<P2pWalletOutsideServiceLimits>(),
          ),
          (const SwapNetworkFailure('x'), isA<P2pWalletServiceUnreachable>()),
          (const SwapTimeoutFailure('x'), isA<P2pWalletServiceUnreachable>()),
          (
            const SwapCreationUnknownFailure('x'),
            isA<P2pWalletServiceUnreachable>(),
          ),
          (const SwapStorageFailure('x'), isA<P2pWalletUnavailable>()),
          (
            const SwapProviderFailure('App update required'),
            isA<P2pWalletServiceRefused>(),
          ),
          (const SwapNoPaymentOptionFailure(), isA<P2pWalletServiceRefused>()),
          (const SwapValidationFailure(), isA<P2pWalletServiceRefused>()),
          (const SwapUnexpectedFailure('x'), isA<P2pWalletServiceRefused>()),
          (const SwapOrderMismatchFailure('x'), isA<P2pWalletServiceRefused>()),
          (const SwapOrderNotFoundFailure('x'), isA<P2pWalletServiceRefused>()),
          (const SwapOrderExpiredFailure('x'), isA<P2pWalletServiceRefused>()),
          (const SwapInvalidStateFailure('x'), isA<P2pWalletServiceRefused>()),
          (
            const SwapPriceUnavailableFailure('x'),
            isA<P2pWalletServiceRefused>(),
          ),
        ]) {
          reset();
          swaps.createFailures.add(failure);
          expect(
            refusalOf(await payOf(payInvoice())),
            refusal,
            reason: '$failure',
          );
          expect(journal.only({'create'}), ['create'], reason: '$failure');
          expectNothingMoved();
        }
      },
    );

    test('asked to wait, it tries once more after a short wait', () async {
      swaps.createFailures.add(
        const SwapRateLimitedFailure(retryAfter: Duration(seconds: 3)),
      );
      paymentOf(await payOf(payInvoice()));
      expect(waits, [const Duration(seconds: 3)]);
      expect(journal.only({'create'}), ['create', 'create']);
      // Without a wait stated, 5 s.
      reset();
      swaps.createFailures.add(const SwapRateLimitedFailure());
      paymentOf(await payOf(payInvoice()));
      expect(waits, [const Duration(seconds: 5)]);
    });

    test(
      'asked to wait too long, again, or past the margin, it stops busy',
      () async {
        for (final (failures, payableIn, retryAfter) in [
          // More than 30 s.
          (
            [const SwapRateLimitedFailure(retryAfter: Duration(seconds: 31))],
            const Duration(minutes: 3),
            const Duration(seconds: 31),
          ),
          // Twice.
          (
            [
              const SwapRateLimitedFailure(retryAfter: Duration(seconds: 2)),
              const SwapRateLimitedFailure(retryAfter: Duration(seconds: 4)),
            ],
            const Duration(minutes: 3),
            const Duration(seconds: 4),
          ),
          // A wait that would leave less than the margin.
          (
            [const SwapRateLimitedFailure(retryAfter: Duration(seconds: 3))],
            const Duration(seconds: 62),
            const Duration(seconds: 3),
          ),
          // An hour, passed on as ten minutes.
          (
            [const SwapRateLimitedFailure(retryAfter: Duration(hours: 1))],
            const Duration(minutes: 3),
            const Duration(minutes: 10),
          ),
          // A negative wait.
          (
            [const SwapRateLimitedFailure(retryAfter: Duration(seconds: -5))],
            const Duration(minutes: 3),
            null,
          ),
        ]) {
          reset();
          swaps.createFailures.addAll(failures);
          expect(
            refusalOf(await payOf(payInvoice(payableIn: payableIn))),
            isA<P2pWalletServiceBusy>().having(
              (r) => r.retryAfter,
              'retryAfter',
              retryAfter,
            ),
            reason: '$failures',
          );
          expect(swaps.records, isEmpty);
          expectNothingMoved();
        }
      },
    );

    test('an answer that is not the order asked for is not built on', () async {
      final invoice = payInvoice();
      for (final answer in [
        paymentRecord(destination: payBolt11(tag: 'p')),
        paymentRecord(
          destination: invoice.bolt11,
          status: OrderSwapLocalStatus.readyToBroadcast,
          signed: 'signed-earlier',
        ),
        paymentRecord(destination: invoice.bolt11, walletId: 'another'),
        paymentRecord(
          destination: invoice.bolt11,
          purpose: OrderSwapPurpose.transfer,
        ),
        paymentRecord(destination: invoice.bolt11, payinAddress: ''),
      ]) {
        reset();
        swaps.createAnswer = answer;
        expect(
          refusalOf(await payOf(invoice)),
          isA<P2pWalletServiceRefused>(),
          reason: '${answer.localStatus} ${answer.destination}',
        );
        expect(journal.only({'build'}), isEmpty);
        expectNothingMoved();
      }
    });
  });

  group('the cap and the transaction:', () {
    test(
      'a payin one sat above the one accepted stops, the order left to expire',
      () async {
        swaps.payinFor = (quoted) => quoted + BigInt.one;
        expect(
          refusalOf(await payOf(payInvoice())),
          isA<P2pWalletQuoteChanged>(),
        );
        expect(
          swaps.records['local-1']?.localStatus,
          OrderSwapLocalStatus.awaitingUserConfirmation,
        );
        expect(journal.only({'build'}), isEmpty);
        expectNothingMoved();
      },
    );

    test(
      'the cap, as a property: paid only when the service\'s payin is at most the one accepted',
      () async {
        final random = Random(100);
        var paid = 0;
        var refused = 0;
        for (var i = 0; i < 200; i++) {
          final accepted = 600 + random.nextInt(2000);
          final asked = 600 + random.nextInt(2000);
          final tag = String.fromCharCodes(
            List.generate(
              8,
              (_) => 'qpzry9x8gf2tvdw0'.codeUnitAt(random.nextInt(16)),
            ),
          );
          final invoice = checkedBolt11InvoiceForTesting(
            bolt11:
                payBolt11(tag: tag) +
                i.toRadixString(2).replaceAll('0', 'q').replaceAll('1', 'p'),
            amount: Sats.fromInt(600),
            network: RobosatsNetwork.mainnet,
            paymentHash: i.toRadixString(16).padLeft(64, '0'),
            expiresAt: testNow.add(const Duration(minutes: 3)),
            now: testNow,
          );
          if (invoice == null) fail('fake invoice refused');
          swaps.payinFor = (_) => BigInt.from(asked);
          journal.events.clear();
          final result = await payOf(
            invoice,
            quote: quoteOf(invoice, payin: accepted, balance: 100000),
          );
          if (asked <= accepted) {
            paymentOf(result);
            expect(journal.only({'broadcast'}), hasLength(1));
            paid++;
          } else {
            expect(refusalOf(result), isA<P2pWalletQuoteChanged>());
            expectNothingMoved();
            refused++;
          }
        }
        // Both sides were drawn.
        expect(paid, greaterThan(50));
        expect(refused, greaterThan(50));
      },
    );

    test(
      'a transaction that does not send exactly the payin to the order is not signed',
      () async {
        for (final sent in [
          (int asked) => asked - 1,
          (int asked) => asked + 1,
          (int _) => 0,
        ]) {
          reset();
          liquid.sentInstead = sent;
          expect(
            refusalOf(await payOf(payInvoice())),
            isA<P2pWalletUnavailable>(),
          );
          expect(journal.only({'build'}), hasLength(1));
          expectNothingMoved();
        }
      },
    );

    test('a fee above the one accepted is not signed', () async {
      liquid.fee = 27;
      expect(
        refusalOf(await payOf(payInvoice())),
        isA<P2pWalletQuoteChanged>(),
      );
      expectNothingMoved();
      reset();
      liquid.fee = -1;
      expect(refusalOf(await payOf(payInvoice())), isA<P2pWalletUnavailable>());
      expectNothingMoved();
    });

    test(
      'the payin below the one accepted does not lift the fee above the one accepted',
      () async {
        swaps.payinFor = (quoted) => quoted - BigInt.from(10);
        liquid.fee = 27;
        expect(
          refusalOf(await payOf(payInvoice())),
          isA<P2pWalletQuoteChanged>(),
        );
        expectNothingMoved();
      },
    );

    test('consolidation needed, and not enough funds', () async {
      for (final (error, refusal) in [
        (
          ConsolidationRequiredException('many'),
          isA<P2pWalletNeedsConsolidation>(),
        ),
        (
          InsufficientFundsException('short'),
          isA<P2pWalletNotEnoughBalance>()
              .having((r) => r.available, 'available', Sats.fromInt(10000))
              .having((r) => r.needed, 'needed', Sats.fromInt(10001)),
        ),
        (NoSpendableUtxoException('none'), isA<P2pWalletNotEnoughBalance>()),
        (StateError('lwk'), isA<P2pWalletUnavailable>()),
      ]) {
        reset();
        liquid.buildError = error;
        expect(refusalOf(await payOf(payInvoice())), refusal, reason: '$error');
        expectNothingMoved();
      }
      // The total accepted, when it is above the balance read now.
      reset();
      getWallets.answer = Ok([testWallet(balance: 500)]);
      liquid.buildError = InsufficientFundsException('short');
      expect(
        refusalOf(await payOf(payInvoice())),
        isA<P2pWalletNotEnoughBalance>().having(
          (r) => r.needed,
          'needed',
          Sats.fromInt(629),
        ),
      );
    });

    test(
      'the margin is checked again just before the signature: a slow order stops there',
      () async {
        swaps.onCreate = () => now = now.add(const Duration(seconds: 6));
        expect(
          refusalOf(
            await payOf(payInvoice(payableIn: const Duration(seconds: 65))),
          ),
          isA<P2pWalletInvoiceExpiresTooSoon>(),
        );
        expect(journal.only({'build'}), hasLength(1));
        expectNothingMoved();
        // With the margin left after the order, it pays.
        reset();
        swaps.onCreate = () => now = now.add(const Duration(seconds: 5));
        paymentOf(
          await payOf(payInvoice(payableIn: const Duration(seconds: 65))),
        );
      },
    );
  });

  group('after the signature:', () {
    test('a failed signature leaves the order unprepared', () async {
      liquid.signError = StateError('secrets');
      expect(refusalOf(await payOf(payInvoice())), isA<P2pWalletUnavailable>());
      expect(journal.only({'sign', 'save'}), ['sign:pset1']);
      expect(
        swaps.records['local-1']?.localStatus,
        OrderSwapLocalStatus.awaitingUserConfirmation,
      );
    });

    test('a failed save stops before any mark or broadcast', () async {
      swaps.saveFailure = const SwapStorageFailure('disk');
      expect(refusalOf(await payOf(payInvoice())), isA<P2pWalletUnavailable>());
      expect(journal.only({'markUnknown', 'broadcast'}), isEmpty);
    });

    test('a failed mark stops before the broadcast, nothing sent', () async {
      for (final (failure, refusal) in [
        (const SwapStorageFailure('disk'), isA<P2pWalletUnavailable>()),
        (const SwapOrderExpiredFailure('late'), isA<P2pWalletServiceRefused>()),
      ]) {
        reset();
        swaps.markUnknownFailure = failure;
        expect(refusalOf(await payOf(payInvoice())), refusal);
        expect(journal.only({'broadcast'}), isEmpty);
        expect(
          swaps.records['local-1']?.localStatus,
          OrderSwapLocalStatus.readyToBroadcast,
        );
      }
    });

    test(
      'a saved transaction other than the one signed is never broadcast',
      () async {
        swaps.savedInstead = 'signed-by-someone-else';
        expect(
          refusalOf(await payOf(payInvoice())),
          isA<P2pWalletUnavailable>(),
        );
        expect(journal.only({'broadcast'}), isEmpty);
      },
    );

    test(
      'a broadcast that fails says the funds may have moved, and the payment is found as such',
      () async {
        broadcast.error = StateError('electrum: connection reset');
        final invoice = payInvoice();
        final refusal = refusalOf(await payOf(invoice));
        expect(refusal, isA<P2pWalletBroadcastUnknown>());
        expect(refusal.fundsMayHaveMoved, isTrue);
        expect(
          (refusal as P2pWalletBroadcastUnknown).payment,
          P2pWalletPayment(id: 'local-1', paymentHash: invoice.paymentHash),
        );
        expect(
          swaps.records['local-1']?.localStatus,
          OrderSwapLocalStatus.broadcastUnknown,
        );
        expect(journal.only({'broadcast', 'markBroadcast'}), [
          'broadcast:signed-pset1',
        ]);
        final found = await WalletPaymentRepositoryImpl(
          swaps,
          invoices,
        ).find(invoice.paymentHash);
        expect(
          found,
          isA<Ok<P2pWalletPaymentFound?, P2pWalletRefusal>>().having(
            (ok) => ok.value?.progress,
            'progress',
            isA<P2pWalletPaymentBroadcastUnknown>(),
          ),
        );
        // Nothing tries the broadcast again.
        broadcast.error = null;
        expect(refusalOf(await payOf(invoice)), isA<P2pWalletAlreadyPaid>());
        expect(journal.only({'broadcast'}), hasLength(1));
      },
    );

    test('every refusal but an unknown broadcast says nothing moved', () async {
      final refusals = <P2pWalletRefusal>[];
      for (final arrange in <void Function()>[
        () => swaps.payinFor = (quoted) => quoted + BigInt.one,
        () => liquid.fee = 27,
        () => liquid.signError = StateError('x'),
        () => swaps.saveFailure = const SwapStorageFailure('x'),
        () => swaps.markUnknownFailure = const SwapStorageFailure('x'),
        () => swaps.createFailures.add(const SwapNetworkFailure('x')),
        () => broadcast.error = StateError('x'),
      ]) {
        reset();
        arrange();
        refusals.add(refusalOf(await payOf(payInvoice())));
      }
      expect(refusals.map((r) => r.fundsMayHaveMoved), [
        false,
        false,
        false,
        false,
        false,
        false,
        true,
      ]);
    });
  });

  group('no text:', () {
    test(
      'no refusal or handle carries a text of the service, an exception or the invoice, and nothing is printed or logged',
      () async {
        final invoice = payInvoice();
        const secret = 'server-secret-text';
        final seen = <Object>[];
        final output = await _capture(() async {
          seen.add(await payOf(invoice));
          for (final arrange in <void Function()>[
            () => swaps.createFailures.add(
              const SwapProviderFailure('$secret ERR_PROV_400'),
            ),
            () => swaps.createFailures.add(
              SwapAmountOutOfBoundsFailure(
                limitAmountSat: BigInt.from(1000),
                isMinimum: true,
                logMessage: '$secret limit',
              ),
            ),
            () => liquid.buildError = Exception('$secret ${invoice.bolt11}'),
            () => liquid.signError = Exception('$secret ${invoice.bolt11}'),
            () => broadcast.error = Exception('$secret ${invoice.bolt11}'),
          ]) {
            reset();
            arrange();
            final result = await payOf(invoice);
            seen.add(result);
            if (result case Err(:final failure)) seen.add(failure);
          }
        });
        final lines = output
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();
        expect(lines, hasLength(2));
        expect(output, isNot(contains(invoice.bolt11)));
        expect(output, isNot(contains(secret)));
        for (final value in seen) {
          final text = switch (value) {
            Ok(:final value) => '$value',
            Err(:final failure) => '$failure ${failure.logMessage}',
            final other => '$other',
          };
          expect(text, isNot(contains(secret)));
          expect(text, isNot(contains(invoice.bolt11)));
          expect(text, isNot(contains(invoice.paymentHash)));
          expect(text, isNot(contains('local-')));
          if (value is P2pWalletRefusal) expect(value.logMessage, isNull);
        }
      },
    );
  });
}

/// Everything [body] prints and everything the project logger writes while it runs, as one text; a line printed and a line logged by the capture itself show that both are seen.
Future<String> _capture(Future<void> Function() body) async {
  final printed = <String>[];
  final directory = Directory.systemTemp.createTempSync('p2p_wallet_pay');
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
