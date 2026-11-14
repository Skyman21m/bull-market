import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/testing.dart';

/// The wallet's port as the feature declares it (#100): the invoice it takes, the arithmetic of a quote, its refusals, and the fake that the tests of the feature and of the app use.
void main() {
  final expiry = DateTime.utc(2026, 11, 13, 12);
  final before = expiry.subtract(const Duration(minutes: 3));

  // Obviously fake strings: the type checks their shape, never a signature or a checksum.
  String fake(String prefix, [int length = 40]) =>
      prefix + 'q' * (length - prefix.length);

  CheckedBolt11Invoice? invoiceOf(
    String bolt11, {
    int amount = 600,
    RobosatsNetwork network = RobosatsNetwork.mainnet,
    String paymentHash = testPaymentHash,
    DateTime? payableUntil,
    DateTime? now,
  }) => checkedBolt11InvoiceForTesting(
    bolt11: bolt11,
    amount: Sats.fromInt(amount),
    network: network,
    paymentHash: paymentHash,
    expiresAt: expiry,
    payableUntil: payableUntil,
    now: now ?? before,
  );

  // `n` is a tenth of a satoshi: `lnbc6000n` is 600 sats.
  CheckedBolt11Invoice invoice({int amount = 600}) {
    final value = invoiceOf(fake('lnbc${amount * 10}n1'), amount: amount);
    if (value == null) throw StateError('the fake invoice is refused');
    return value;
  }

  group('a checked invoice', () {
    test(
      'takes the string, amount, network, payment hash, expiry and deadline it was given',
      () {
        final until = expiry.subtract(const Duration(seconds: 30));
        final value = invoiceOf(
          fake('lntb6u1'),
          network: RobosatsNetwork.testnet,
          paymentHash: 'cd' * 32,
          payableUntil: until,
        );
        expect(value?.bolt11, fake('lntb6u1'));
        expect(value?.amount, Sats.fromInt(600));
        expect(value?.network, RobosatsNetwork.testnet);
        expect(value?.paymentHash, 'cd' * 32);
        expect(value?.expiresAt, expiry);
        expect(value?.payableUntil, until);
        // Without a deadline of its own, the helper takes the expiry.
        expect(invoiceOf(fake('lnbc6u1'))?.payableUntil, expiry);
      },
    );

    test('has a payment hash of 64 lowercase hexadecimal characters', () {
      expect(invoiceOf(fake('lnbc6u1'), paymentHash: '0' * 64), isNotNull);
      expect(invoiceOf(fake('lnbc6u1'), paymentHash: 'f' * 64), isNotNull);
      for (final hash in [
        '',
        '0' * 63,
        '0' * 65,
        'A' * 64,
        'g' * 64,
        '${'0' * 63} ',
        ' ${'0' * 63}',
      ]) {
        expect(
          invoiceOf(fake('lnbc6u1'), paymentHash: hash),
          isNull,
          reason: hash,
        );
      }
    });

    test('is payable until a deadline no later than its expiry', () {
      expect(invoiceOf(fake('lnbc6u1'), payableUntil: expiry), isNotNull);
      expect(
        invoiceOf(
          fake('lnbc6u1'),
          payableUntil: expiry.add(const Duration(milliseconds: 1)),
        ),
        isNull,
      );
      final until = before.add(const Duration(minutes: 1));
      final value = invoiceOf(fake('lnbc6u1'), payableUntil: until);
      expect(
        value?.isExpiredAt(until.subtract(const Duration(milliseconds: 1))),
        isFalse,
      );
      expect(value?.isExpiredAt(until), isTrue);
      // Built at its deadline or after, it is refused.
      expect(
        invoiceOf(fake('lnbc6u1'), payableUntil: until, now: until),
        isNull,
      );
    });

    test('is bounded to 2,000 characters', () {
      expect(CheckedBolt11Invoice.maxLength, 2000);
      expect(invoiceOf(fake('lnbc6u1', 2000)), isNotNull);
      expect(invoiceOf(fake('lnbc6u1', 2001)), isNull);
    });

    test('is visible ASCII only', () {
      for (final (label, text) in [
        ('space', 'lnbc6u1 qqqq'),
        ('newline', 'lnbc6u1qq\nqq'),
        ('tab', 'lnbc6u1\tqqqq'),
        ('nul', 'lnbc6u1\u0000qqq'),
        ('delete', 'lnbc6u1\u007fqqq'),
        ('non-ASCII', 'lnbc6u1qqéqq'),
        ('non-ASCII before the separator', 'lnbc6éu1qqqq'),
        ('empty', ''),
      ]) {
        expect(invoiceOf(text), isNull, reason: label);
      }
    });

    test('has only bech32 characters after its separator', () {
      expect(invoiceOf('lnbc6u1qpzry9x8gf2tvdw0s3jn54khce6mua7l'), isNotNull);
      // The reviewer's probe P3: visible ASCII outside the alphabet.
      for (final data in [
        'bio!~qq',
        'qqbqq',
        'qqiqq',
        'qqoqq',
        'qq-qq',
        'qq_q',
      ]) {
        expect(invoiceOf('lnbc6u1$data'), isNull, reason: data);
      }
    });

    test('is in one case, as bech32 is', () {
      expect(invoiceOf(fake('LNBC6U1').toUpperCase()), isNotNull);
      expect(invoiceOf('lnbc6u1qqQq'), isNull);
      expect(invoiceOf('LNBC6U1QQqQ'), isNull);
      expect(invoiceOf('LNBC6u1QQQQ'), isNull);
    });

    test('has the prefix of its network, with an amount', () {
      for (final (prefix, network, accepted) in [
        ('lnbc6u1', RobosatsNetwork.mainnet, true),
        ('lntb6u1', RobosatsNetwork.testnet, true),
        // Signet is another network than testnet (#113).
        ('lntbs6u1', RobosatsNetwork.testnet, false),
        ('lntb6u1', RobosatsNetwork.mainnet, false),
        ('lntbs6u1', RobosatsNetwork.mainnet, false),
        ('lnbc6u1', RobosatsNetwork.testnet, false),
        ('lnbcrt6u1', RobosatsNetwork.mainnet, false),
        ('lnbcrt6u1', RobosatsNetwork.testnet, false),
        ('lntbrt6u1', RobosatsNetwork.testnet, false),
        ('lntx6u1', RobosatsNetwork.testnet, false),
        ('lnt6u1', RobosatsNetwork.testnet, false),
        ('lnsb6u1', RobosatsNetwork.testnet, false),
        ('lnbc1', RobosatsNetwork.mainnet, false),
        ('lntb1', RobosatsNetwork.testnet, false),
        ('lnbc6x1', RobosatsNetwork.mainnet, false),
        ('lnbc6u', RobosatsNetwork.mainnet, false),
        ('lnbcu1', RobosatsNetwork.mainnet, false),
        ('lightning:lnbc6u1', RobosatsNetwork.mainnet, false),
        ('xlnbc6u1', RobosatsNetwork.mainnet, false),
      ]) {
        expect(
          invoiceOf(fake(prefix), network: network) != null,
          accepted,
          reason: '$prefix on ${network.name}',
        );
      }
    });

    test('says in its string the amount it is given', () {
      for (final (prefix, sats) in [
        ('lnbc6u1', 600),
        ('lnbc6000n1', 600),
        ('lnbc6000000p1', 600),
        ('lnbc1500n1', 150),
        ('lnbc10m1', 1000000),
        ('lnbc2m1', 200000),
        ('lnbc21', 200000000),
        ('lnbc1u1', 100),
        ('lnbc10n1', 1),
        ('lnbc10000p1', 1),
        ('lntb4u1', 400),
      ]) {
        final network = prefix.startsWith('lntb')
            ? RobosatsNetwork.testnet
            : RobosatsNetwork.mainnet;
        expect(
          invoiceOf(fake(prefix), amount: sats, network: network),
          isNotNull,
          reason: '$prefix is $sats sats',
        );
        expect(
          invoiceOf(fake(prefix), amount: sats + 1, network: network),
          isNull,
          reason: '$prefix is not ${sats + 1} sats',
        );
        if (sats > 1) {
          expect(
            invoiceOf(fake(prefix), amount: sats - 1, network: network),
            isNull,
            reason: '$prefix is not ${sats - 1} sats',
          );
        }
      }
      // The reviewer's probe P1: a string of 1,000,000 sats, or of 2,100,000 BTC, given as 400 sats.
      expect(invoiceOf(fake('lnbc10m1'), amount: 400), isNull);
      expect(invoiceOf(fake('lnbc21000001'), amount: 400), isNull);
    });

    test('asks for at most 21 million bitcoin, as the payout check (#113)', () {
      final most = CheckedBolt11Invoice.maxSats;
      expect(most, BigInt.from(2100000000000000));
      CheckedBolt11Invoice? of(String prefix, BigInt sats) =>
          checkedBolt11InvoiceForTesting(
            bolt11: fake(prefix),
            amount: Sats(sats),
            network: RobosatsNetwork.mainnet,
            expiresAt: expiry,
            now: before,
          );
      expect(of('lnbc210000001', most), isNotNull);
      expect(of('lnbc21000000000m1', most), isNotNull);
      expect(of('lnbc210000011', most + BigInt.from(100000000)), isNull);
      expect(of('lnbc21000000001m1', most + BigInt.from(100000)), isNull);
      // The value of #113's report: 60,708,632 BTC.
      expect(of('lnbc607086321', BigInt.from(6070863200000000)), isNull);
    });

    test('refuses an amount below a satoshi, with a leading zero, or zero', () {
      // The reviewer's probe P2, and the BOLT11 rule on `p` amounts.
      for (final (prefix, sats) in [
        ('lnbc1p1', 1),
        ('lnbc9n1', 1),
        ('lnbc15n1', 1),
        ('lnbc15n1', 2),
        ('lnbc10001p1', 1),
        ('lnbc0001n1', 1),
        ('lnbc06u1', 600),
        ('lnbc0n1', 400),
        ('lnbc0n1', 0),
        ('lnbc01', 0),
      ]) {
        expect(
          invoiceOf(fake(prefix), amount: sats),
          isNull,
          reason: '$prefix as $sats sats',
        );
      }
      expect(invoiceOf(fake('lnbc6u1'), amount: 0), isNull);
    });

    test('has data after its separator', () {
      expect(invoiceOf('lnbc6u1'), isNull);
      expect(invoiceOf('lnbc6u1q'), isNotNull);
      expect(invoiceOf('lnbc6uqqqq'), isNull);
    });

    test('has not expired when it is built', () {
      // The reviewer's probe P4: an invoice expired long ago.
      expect(invoiceOf(fake('lnbc6u1'), now: DateTime.utc(2030)), isNull);
      expect(invoiceOf(fake('lnbc6u1'), now: expiry), isNull);
      expect(
        invoiceOf(
          fake('lnbc6u1'),
          now: expiry.subtract(const Duration(milliseconds: 1)),
        ),
        isNotNull,
      );
      // Without a clock, the helper reads the device's.
      expect(
        checkedBolt11InvoiceForTesting(
          bolt11: fake('lnbc6u1'),
          amount: Sats.fromInt(600),
          network: RobosatsNetwork.mainnet,
          expiresAt: DateTime.utc(2000),
        ),
        isNull,
      );
    });

    test('is fast on hostile strings', () {
      final watch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        expect(invoiceOf('1' * 2000), isNull);
        expect(invoiceOf('lnbc${'9' * 1990}m1q', amount: 1), isNull);
        expect(invoiceOf('lnbc${'0' * 1990}x1qq'), isNull);
        expect(invoiceOf('l' * 2000), isNull);
      }
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('keeps its expiry in UTC and has expired from that instant', () {
      final local = DateTime(2026, 11, 13, 12);
      final value = checkedBolt11InvoiceForTesting(
        bolt11: fake('lnbc6u1'),
        amount: Sats.fromInt(600),
        network: RobosatsNetwork.mainnet,
        expiresAt: local,
        now: local.subtract(const Duration(minutes: 1)),
      );
      expect(value?.expiresAt.isUtc, isTrue);
      expect(value?.expiresAt, local.toUtc());
      final one = invoice();
      expect(
        one.isExpiredAt(expiry.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(one.isExpiredAt(expiry), isTrue);
      expect(one.isExpiredAt(expiry.add(const Duration(seconds: 1))), isTrue);
    });

    test(
      'equals another of the same string, amount, network, hash, expiry and deadline',
      () {
        expect(invoice(), invoice());
        expect(invoice().hashCode, invoice().hashCode);
        expect(invoice(), isNot(invoice(amount: 601)));
        expect(invoiceOf(fake('lnbc6000n1', 41)), isNot(invoice()));
        final otherHash = invoiceOf(fake('lnbc6000n1'), paymentHash: 'cd' * 32);
        expect(otherHash, isNot(invoice()));
        final earlier = invoiceOf(
          fake('lnbc6000n1'),
          payableUntil: expiry.subtract(const Duration(seconds: 1)),
        );
        expect(earlier, isNot(invoice()));
        // The same invoice read again with another deadline is the same invoice, for a payment.
        expect(earlier?.isSameInvoiceAs(invoice()), isTrue);
        expect(otherHash?.isSameInvoiceAs(invoice()), isFalse);
        expect(invoice(amount: 601).isSameInvoiceAs(invoice()), isFalse);
      },
    );

    test('prints nothing of itself', () {
      expect('${invoice()}', 'CheckedBolt11Invoice');
    });
  });

  group('a quote', () {
    P2pWalletQuote quoteOf({
      int payin = 603,
      int networkFee = 26,
      int balance = 10000,
    }) => P2pWalletQuote(
      invoice: invoice(),
      payin: Sats.fromInt(payin),
      networkFee: Sats.fromInt(networkFee),
      balance: Sats.fromInt(balance),
      quotedAt: expiry,
    );

    test('itemises the fees, the total and what stays', () {
      final quote = quoteOf();
      expect(quote.amount, Sats.fromInt(600));
      expect(quote.payin, Sats.fromInt(603));
      expect(quote.serviceFee, Sats.fromInt(3));
      expect(quote.networkFee, Sats.fromInt(26));
      expect(quote.total, Sats.fromInt(629));
      expect(quote.balance, Sats.fromInt(10000));
      expect(quote.remaining, Sats.fromInt(9371));
      expect(quote.quotedAt, expiry);
      expect(quote.invoice, invoice());
    });

    test('may take the whole balance, and no more', () {
      expect(quoteOf(balance: 629).remaining, Sats.zero);
      expect(() => quoteOf(balance: 628), throwsArgumentError);
    });

    test('never pays out more than its payin', () {
      expect(quoteOf(payin: 600).serviceFee, Sats.zero);
      expect(() => quoteOf(payin: 599), throwsArgumentError);
    });

    test('prints none of its amounts', () {
      expect('${quoteOf()}', 'P2pWalletQuote');
    });
  });

  test('not enough balance always needs more than there is', () {
    expect(
      P2pWalletNotEnoughBalance(
        available: Sats.fromInt(628),
        needed: Sats.fromInt(629),
      ).needed,
      Sats.fromInt(629),
    );
    for (final needed in [628, 0]) {
      expect(
        () => P2pWalletNotEnoughBalance(
          available: Sats.fromInt(628),
          needed: Sats.fromInt(needed),
        ),
        throwsArgumentError,
        reason: '$needed',
      );
    }
  });

  test('a refusal prints its type and carries no text', () {
    final refusals = <P2pWalletRefusal>[
      P2pWalletUnderMinimum(minimum: Sats.fromInt(1000)),
      P2pWalletOverMaximum(maximum: Sats.fromInt(5000000)),
      const P2pWalletOutsideServiceLimits(),
      P2pWalletNotEnoughBalance(
        available: Sats.fromInt(10),
        needed: Sats.fromInt(629),
      ),
      const P2pWalletNeedsConsolidation(),
      const P2pWalletNoInstantWallet(),
      const P2pWalletUnavailable(),
      const P2pWalletWrongNetwork(),
      const P2pWalletInvoiceUnreadable(),
      const P2pWalletInvoiceExpired(),
      const P2pWalletServiceUnreachable(),
      const P2pWalletServiceBusy(retryAfter: Duration(seconds: 30)),
      const P2pWalletServiceRefused(),
      const P2pWalletInvoiceExpiresTooSoon(),
      const P2pWalletQuoteStale(),
      const P2pWalletQuoteChanged(),
      const P2pWalletAlreadyPaid(),
      const P2pWalletBroadcastUnknown(
        P2pWalletPayment(id: 'local-1', paymentHash: testPaymentHash),
      ),
    ];
    for (final refusal in refusals) {
      expect('$refusal', '${refusal.runtimeType}');
      expect(refusal.logMessage, isNull);
      // Only an unknown broadcast may have moved funds.
      expect(
        refusal.fundsMayHaveMoved,
        refusal is P2pWalletBroadcastUnknown,
        reason: '$refusal',
      );
    }
    // Every variant is listed: a new one fails to compile here until it is.
    String name(P2pWalletRefusal refusal) => switch (refusal) {
      P2pWalletUnderMinimum() => 'under minimum',
      P2pWalletOverMaximum() => 'over maximum',
      P2pWalletOutsideServiceLimits() => 'outside limits',
      P2pWalletNotEnoughBalance() => 'not enough',
      P2pWalletNeedsConsolidation() => 'consolidation',
      P2pWalletNoInstantWallet() => 'no wallet',
      P2pWalletUnavailable() => 'unavailable',
      P2pWalletWrongNetwork() => 'wrong network',
      P2pWalletInvoiceUnreadable() => 'unreadable',
      P2pWalletInvoiceExpired() => 'expired',
      P2pWalletServiceUnreachable() => 'unreachable',
      P2pWalletServiceBusy() => 'busy',
      P2pWalletServiceRefused() => 'refused',
      P2pWalletInvoiceExpiresTooSoon() => 'too soon',
      P2pWalletQuoteStale() => 'stale',
      P2pWalletQuoteChanged() => 'changed',
      P2pWalletAlreadyPaid() => 'already paid',
      P2pWalletBroadcastUnknown() => 'broadcast unknown',
    };
    expect(refusals.map(name).toSet(), hasLength(18));
  });

  test('a payment and its progress print no id, hash or text', () {
    const payment = P2pWalletPayment(
      id: 'local-1',
      paymentHash: testPaymentHash,
    );
    expect('$payment', 'P2pWalletPayment');
    expect(
      payment,
      const P2pWalletPayment(id: 'local-1', paymentHash: testPaymentHash),
    );
    expect(
      payment,
      isNot(
        const P2pWalletPayment(id: 'local-2', paymentHash: testPaymentHash),
      ),
    );
    final progress = <P2pWalletPaymentProgress, (bool, bool)>{
      const P2pWalletPaymentPreparing(): (false, false),
      const P2pWalletPaymentSigned(): (false, false),
      const P2pWalletPaymentBroadcastUnknown(): (true, false),
      const P2pWalletPaymentSent(): (true, false),
      const P2pWalletPaymentPending(): (true, false),
      const P2pWalletPaymentUnderReview(): (true, false),
      const P2pWalletPaymentPaid(): (true, true),
      const P2pWalletPaymentRefundPending(): (true, false),
      const P2pWalletPaymentRefunded(): (true, true),
      const P2pWalletPaymentExpired(P2pWalletFunds.notSent): (false, true),
      const P2pWalletPaymentExpired(P2pWalletFunds.maybeSent): (true, true),
      const P2pWalletPaymentExpired(P2pWalletFunds.sent): (true, true),
      const P2pWalletPaymentFailed(P2pWalletFunds.notSent): (false, true),
      const P2pWalletPaymentFailed(P2pWalletFunds.maybeSent): (true, true),
      const P2pWalletPaymentFailed(P2pWalletFunds.sent): (true, true),
    };
    for (final MapEntry(key: value, value: (mayHaveLeft, isFinal))
        in progress.entries) {
      expect(value.fundsMayHaveLeft, mayHaveLeft, reason: '$value');
      expect(value.isFinal, isFinal, reason: '$value');
      expect('$value', startsWith('${value.runtimeType}'));
      expect('$value', isNot(contains('local')));
    }
    expect(
      '${const P2pWalletPaymentFound(payment: payment, progress: P2pWalletPaymentSent())}',
      'P2pWalletPaymentFound(P2pWalletPaymentSent)',
    );
    // Every variant is listed: a new one fails to compile here until it is.
    String name(P2pWalletPaymentProgress value) => switch (value) {
      P2pWalletPaymentPreparing() => 'preparing',
      P2pWalletPaymentSigned() => 'signed',
      P2pWalletPaymentBroadcastUnknown() => 'broadcast unknown',
      P2pWalletPaymentSent() => 'sent',
      P2pWalletPaymentPending() => 'pending',
      P2pWalletPaymentUnderReview() => 'under review',
      P2pWalletPaymentPaid() => 'paid',
      P2pWalletPaymentRefundPending() => 'refund pending',
      P2pWalletPaymentRefunded() => 'refunded',
      P2pWalletPaymentExpired() => 'expired',
      P2pWalletPaymentFailed() => 'failed',
    };
    expect(progress.keys.map(name).toSet(), hasLength(11));
  });

  group('setup', () {
    test('lends no port when none is given', () {
      final locator = GetIt.asNewInstance();
      addTearDown(locator.reset);
      // As a composition written before the port, the WorkManager isolate's among them, calls it.
      const P2pFeature().setup(
        locator,
        garageKeys: null,
        databaseDirectory: null,
      );
      expect(hasWalletPortForTesting(locator), isFalse);
      final explicit = GetIt.asNewInstance();
      addTearDown(explicit.reset);
      const P2pFeature().setup(
        explicit,
        garageKeys: null,
        databaseDirectory: null,
        wallet: null,
      );
      expect(hasWalletPortForTesting(explicit), isFalse);
    });

    test('registers the port given, and asks for it at its first use only', () {
      final locator = GetIt.asNewInstance();
      addTearDown(locator.reset);
      final port = FakeP2pWalletPort(Ok(Sats.zero));
      var asked = 0;
      const P2pFeature().setup(
        locator,
        garageKeys: null,
        databaseDirectory: null,
        wallet: () {
          asked++;
          return port;
        },
      );
      expect(hasWalletPortForTesting(locator), isTrue);
      expect(asked, 0);
      expect(locator<P2pWalletPort>(), same(port));
      expect(locator<P2pWalletPort>(), same(port));
      expect(asked, 1);
    });
  });

  group('the fake port', () {
    test(
      'gives the balance at once, then each change, to each subscription',
      () async {
        final port = FakeP2pWalletPort(Ok(Sats.fromInt(1000)));
        final first = <Result<Sats, P2pWalletRefusal>>[];
        final second = <Result<Sats, P2pWalletRefusal>>[];
        final a = port
            .instantBalance(RobosatsNetwork.mainnet)
            .listen(first.add);
        await pumpEventQueue();
        port.setBalance(Ok(Sats.fromInt(400)));
        final b = port
            .instantBalance(RobosatsNetwork.testnet)
            .listen(second.add);
        await pumpEventQueue();
        port.setBalance(Ok(Sats.fromInt(5000)));
        await pumpEventQueue();
        expect(first.map(_sats), [1000, 400, 5000]);
        expect(second.map(_sats), [400, 5000]);
        expect(port.balanceRequests, [
          RobosatsNetwork.mainnet,
          RobosatsNetwork.testnet,
        ]);
        await a.cancel();
        await b.cancel();
      },
    );

    test('ends a subscription on a refusal', () async {
      final port = FakeP2pWalletPort(Ok(Sats.fromInt(1000)));
      final seen = <Result<Sats, P2pWalletRefusal>>[];
      final done = Completer<void>();
      port
          .instantBalance(RobosatsNetwork.mainnet)
          .listen(seen.add, onDone: done.complete);
      await pumpEventQueue();
      port.setBalance(const Err(P2pWalletUnavailable()));
      await done.future;
      expect(seen, hasLength(2));
      expect(seen.last, isA<Err<Sats, P2pWalletRefusal>>());
      expect(
        await port.instantBalance(RobosatsNetwork.mainnet).toList(),
        hasLength(1),
      );
    });

    test(
      'answers the quotes it was given, in order, and records them',
      () async {
        final port = FakeP2pWalletPort(Ok(Sats.fromInt(1000)));
        final quote = P2pWalletQuote(
          invoice: invoice(),
          payin: Sats.fromInt(603),
          networkFee: Sats.fromInt(26),
          balance: Sats.fromInt(1000),
          quotedAt: expiry,
        );
        port
          ..scriptQuote(Err(P2pWalletUnderMinimum(minimum: Sats.fromInt(1000))))
          ..scriptQuote(Ok(quote));
        expect(
          await port.quote(invoice()),
          isA<Err<P2pWalletQuote, P2pWalletRefusal>>().having(
            (err) => err.failure,
            'failure',
            isA<P2pWalletUnderMinimum>().having(
              (refusal) => refusal.minimum,
              'minimum',
              Sats.fromInt(1000),
            ),
          ),
        );
        expect(
          await port.quote(invoice()),
          isA<Ok<P2pWalletQuote, P2pWalletRefusal>>().having(
            (ok) => ok.value,
            'value',
            same(quote),
          ),
        );
        expect(port.quoted, [invoice(), invoice()]);
        expect(() => port.quote(invoice()), throwsStateError);
      },
    );

    test('answers the payments it was given, and records them', () async {
      final port = FakeP2pWalletPort(Ok(Sats.fromInt(1000)));
      final quote = P2pWalletQuote(
        invoice: invoice(),
        payin: Sats.fromInt(603),
        networkFee: Sats.fromInt(26),
        balance: Sats.fromInt(1000),
        quotedAt: expiry,
      );
      const payment = P2pWalletPayment(
        id: 'local-1',
        paymentHash: testPaymentHash,
      );
      port
        ..scriptPayment(const Err(P2pWalletAlreadyPaid()))
        ..scriptPayment(const Ok(payment));
      expect(
        await port.payInvoice(invoice(), accepted: quote),
        isA<Err<P2pWalletPayment, P2pWalletRefusal>>(),
      );
      expect(
        await port.payInvoice(invoice(), accepted: quote),
        isA<Ok<P2pWalletPayment, P2pWalletRefusal>>(),
      );
      expect(port.paid, hasLength(2));
      expect(port.paid.first.$2, same(quote));
      expect(
        () => port.payInvoice(invoice(), accepted: quote),
        throwsStateError,
      );
    });

    test(
      'gives a payment\'s progress, then each change, until a refusal',
      () async {
        final port = FakeP2pWalletPort(Ok(Sats.fromInt(1000)));
        const payment = P2pWalletPayment(
          id: 'local-1',
          paymentHash: testPaymentHash,
        );
        port.setProgress(payment, const Ok(P2pWalletPaymentSent()));
        final seen = <Result<P2pWalletPaymentProgress, P2pWalletRefusal>>[];
        final done = Completer<void>();
        port.watchPayment(payment).listen(seen.add, onDone: done.complete);
        await pumpEventQueue();
        port
          ..setProgress(payment, const Ok(P2pWalletPaymentPending()))
          ..setProgress(
            const P2pWalletPayment(id: 'other', paymentHash: testPaymentHash),
            const Ok(P2pWalletPaymentPaid()),
          )
          ..setProgress(payment, const Err(P2pWalletUnavailable()));
        await done.future;
        expect(seen, hasLength(3));
        expect(
          seen.last,
          isA<Err<P2pWalletPaymentProgress, P2pWalletRefusal>>(),
        );
        port.setFound(
          testPaymentHash,
          const P2pWalletPaymentFound(
            payment: payment,
            progress: P2pWalletPaymentRefunded(),
          ),
        );
        expect(
          await port.findPayment(testPaymentHash),
          isA<Ok<P2pWalletPaymentFound?, P2pWalletRefusal>>().having(
            (ok) => ok.value?.payment,
            'payment',
            payment,
          ),
        );
        expect(
          await port.findPayment('cd' * 32),
          isA<Ok<P2pWalletPaymentFound?, P2pWalletRefusal>>().having(
            (ok) => ok.value,
            'value',
            isNull,
          ),
        );
        expect(port.found, [testPaymentHash, 'cd' * 32]);
      },
    );
  });
}

int _sats(Result<Sats, P2pWalletRefusal> result) => switch (result) {
  Ok(:final value) => value.value.toInt(),
  Err() => -1,
};
