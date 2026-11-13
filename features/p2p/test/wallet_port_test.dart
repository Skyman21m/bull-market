import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/testing.dart';

/// The wallet's port as the feature declares it (#100): the invoice it takes, the arithmetic of a quote, its refusals, and the fake that the tests of the feature and of the app use.
void main() {
  final expiry = DateTime.utc(2026, 11, 13, 12);

  // Obviously fake strings: the type checks their shape, never a signature.
  String fake(String prefix, [int length = 40]) =>
      prefix + 'q' * (length - prefix.length);

  CheckedBolt11Invoice? invoiceOf(
    String bolt11, {
    int amount = 600,
    RobosatsNetwork network = RobosatsNetwork.mainnet,
  }) => checkedBolt11InvoiceForTesting(
    bolt11: bolt11,
    amount: Sats.fromInt(amount),
    network: network,
    expiresAt: expiry,
  );

  CheckedBolt11Invoice invoice({int amount = 600}) {
    final value = invoiceOf(fake('lnbc6u1'), amount: amount);
    if (value == null) throw StateError('the fake invoice is refused');
    return value;
  }

  group('a checked invoice', () {
    test('takes the string, amount, network and expiry it was given', () {
      final value = invoiceOf(
        fake('lntb6u1'),
        network: RobosatsNetwork.testnet,
      );
      expect(value?.bolt11, fake('lntb6u1'));
      expect(value?.amount, Sats.fromInt(600));
      expect(value?.network, RobosatsNetwork.testnet);
      expect(value?.expiresAt, expiry);
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
        ('empty', ''),
      ]) {
        expect(invoiceOf(text), isNull, reason: label);
      }
      expect(invoiceOf('lnbc6u1!~qq'), isNotNull);
    });

    test('is in one case, as bech32 is', () {
      expect(invoiceOf(fake('LNBC6U1').toUpperCase()), isNotNull);
      expect(invoiceOf('lnbc6u1qqQq'), isNull);
      expect(invoiceOf('LNBC6U1QQqQ'), isNull);
    });

    test('has the prefix of its network, with an amount', () {
      for (final (prefix, network, accepted) in [
        ('lnbc6u1', RobosatsNetwork.mainnet, true),
        ('lntb6u1', RobosatsNetwork.testnet, true),
        ('lntbs6u1', RobosatsNetwork.testnet, true),
        ('lntb6u1', RobosatsNetwork.mainnet, false),
        ('lnbc6u1', RobosatsNetwork.testnet, false),
        ('lnbcrt6u1', RobosatsNetwork.mainnet, false),
        ('lnbc1', RobosatsNetwork.mainnet, false),
        ('lntb1', RobosatsNetwork.testnet, false),
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

    test('has an amount', () {
      expect(invoiceOf(fake('lnbc6u1'), amount: 0), isNull);
      expect(invoiceOf(fake('lnbc6u1'), amount: 1), isNotNull);
    });

    test('keeps its expiry in UTC and has expired from that instant', () {
      final local = DateTime(2026, 11, 13, 12);
      final value = checkedBolt11InvoiceForTesting(
        bolt11: fake('lnbc6u1'),
        amount: Sats.fromInt(600),
        network: RobosatsNetwork.mainnet,
        expiresAt: local,
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

    test('equals another of the same string, amount, network and expiry', () {
      expect(invoice(), invoice());
      expect(invoice().hashCode, invoice().hashCode);
      expect(invoice(), isNot(invoice(amount: 601)));
      expect(invoiceOf(fake('lnbc6u1', 41)), isNot(invoice()));
    });

    test('prints nothing of itself', () {
      expect('${invoice()}', 'CheckedBolt11Invoice');
    });
  });

  group('a quote', () {
    P2pWalletQuote quoteOf({
      int payin = 603,
      int basisPoints = 50,
      int networkFee = 26,
      int balance = 10000,
    }) => P2pWalletQuote(
      invoice: invoice(),
      payin: Sats.fromInt(payin),
      serviceFeeBasisPoints: basisPoints,
      networkFee: Sats.fromInt(networkFee),
      balance: Sats.fromInt(balance),
      quotedAt: expiry,
    );

    test('itemises the fees, the total and what stays', () {
      final quote = quoteOf();
      expect(quote.amount, Sats.fromInt(600));
      expect(quote.payin, Sats.fromInt(603));
      expect(quote.serviceFee, Sats.fromInt(3));
      expect(quote.serviceFeeBasisPoints, 50);
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

    test('has no negative fee rate', () {
      expect(quoteOf(basisPoints: 0).serviceFeeBasisPoints, 0);
      expect(() => quoteOf(basisPoints: -1), throwsArgumentError);
    });

    test('prints none of its amounts', () {
      expect('${quoteOf()}', 'P2pWalletQuote');
    });
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
    ];
    for (final refusal in refusals) {
      expect('$refusal', '${refusal.runtimeType}');
      expect(refusal.logMessage, isNull);
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
    };
    expect(refusals.map(name).toSet(), hasLength(13));
  });

  group('the fake port', () {
    test('gives the balance at once, then each change, to each subscription', () async {
      final port = FakeP2pWalletPort(balance: Ok(Sats.fromInt(1000)));
      final first = <Result<Sats, P2pWalletRefusal>>[];
      final second = <Result<Sats, P2pWalletRefusal>>[];
      final a = port.instantBalance(RobosatsNetwork.mainnet).listen(first.add);
      await pumpEventQueue();
      port.setBalance(Ok(Sats.fromInt(400)));
      final b = port.instantBalance(RobosatsNetwork.testnet).listen(second.add);
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
    });

    test('ends a subscription on a refusal', () async {
      final port = FakeP2pWalletPort(balance: Ok(Sats.fromInt(1000)));
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

    test('answers the quotes it was given, in order, and records them', () async {
      final port = FakeP2pWalletPort(balance: Ok(Sats.fromInt(1000)));
      final quote = P2pWalletQuote(
        invoice: invoice(),
        payin: Sats.fromInt(603),
        serviceFeeBasisPoints: 50,
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
    });
  });
}

int _sats(Result<Sats, P2pWalletRefusal> result) => switch (result) {
  Ok(:final value) => value.value.toInt(),
  Err() => -1,
};
