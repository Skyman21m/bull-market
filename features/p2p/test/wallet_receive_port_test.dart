import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/testing.dart';

/// What the wallet's port gives for the buyer's payout (#90): its invoice and its address, their bounds, and the fake that the payout's tests use.
void main() {
  final expiry = DateTime.utc(2026, 11, 15, 12, 10);

  P2pWalletInvoice invoiceOf({int amount = 25000, int received = 24950}) =>
      P2pWalletInvoice(
        bolt11: 'lnbcfake1',
        amount: Sats.fromInt(amount),
        expiresAt: expiry,
        received: Sats.fromInt(received),
      );

  group('the wallet\'s invoice', () {
    test('says what it asks, what arrives, and the fee between them', () {
      final invoice = invoiceOf();
      expect(invoice.bolt11, 'lnbcfake1');
      expect(invoice.amount, Sats.fromInt(25000));
      expect(invoice.received, Sats.fromInt(24950));
      expect(invoice.fee, Sats.fromInt(50));
      expect(invoice.expiresAt, expiry);
    });

    test('keeps its expiry in UTC', () {
      final local = DateTime(2026, 11, 15, 13, 10);
      final invoice = P2pWalletInvoice(
        bolt11: 'lnbcfake1',
        amount: Sats.fromInt(25000),
        expiresAt: local,
        received: Sats.fromInt(24950),
      );
      expect(invoice.expiresAt.isUtc, isTrue);
      expect(invoice.expiresAt, local.toUtc());
    });

    test('pays out a part of its amount, no more and not nothing', () {
      expect(invoiceOf(received: 25000).fee, Sats.zero);
      expect(invoiceOf(received: 1).fee, Sats.fromInt(24999));
      expect(() => invoiceOf(received: 25001), throwsArgumentError);
      expect(() => invoiceOf(received: 0), throwsArgumentError);
    });

    test('prints none of it', () {
      expect('${invoiceOf()}', 'P2pWalletInvoice');
    });
  });

  test('the wallet\'s address prints none of it', () {
    expect('${const P2pWalletAddress('bc1qfake')}', 'P2pWalletAddress');
    expect(const P2pWalletAddress('bc1qfake').address, 'bc1qfake');
  });

  test('no Bitcoin wallet is a refusal without text', () {
    const refusal = P2pWalletNoBitcoinWallet();
    expect('$refusal', 'P2pWalletNoBitcoinWallet');
    expect(refusal.logMessage, isNull);
    expect(refusal.fundsMayHaveMoved, isFalse);
  });

  group('the fake port', () {
    test(
      'answers the invoices and addresses it was given, in order, and records them',
      () async {
        final port = FakeP2pWalletPort(Ok(Sats.zero));
        final invoice = invoiceOf();
        port
          ..scriptInvoice(const Err(P2pWalletServiceUnreachable()))
          ..scriptInvoice(Ok(invoice))
          ..scriptAddress(const Ok(P2pWalletAddress('bc1qfake')));
        expect(
          await port.newLightningInvoice(
            RobosatsNetwork.mainnet,
            Sats.fromInt(25000),
            payout: 'trade-1',
          ),
          isA<Err<P2pWalletInvoice, P2pWalletRefusal>>(),
        );
        expect(
          await port.newLightningInvoice(
            RobosatsNetwork.testnet,
            Sats.fromInt(26000),
            payout: 'trade-2',
          ),
          isA<Ok<P2pWalletInvoice, P2pWalletRefusal>>().having(
            (ok) => ok.value,
            'value',
            same(invoice),
          ),
        );
        expect(
          await port.newReceiveAddress(RobosatsNetwork.mainnet),
          isA<Ok<P2pWalletAddress, P2pWalletRefusal>>().having(
            (ok) => ok.value.address,
            'address',
            'bc1qfake',
          ),
        );
        expect(port.invoicesAsked, [
          (RobosatsNetwork.mainnet, Sats.fromInt(25000), 'trade-1'),
          (RobosatsNetwork.testnet, Sats.fromInt(26000), 'trade-2'),
        ]);
        expect(port.addressesAsked, [RobosatsNetwork.mainnet]);
        expect(
          () => port.newLightningInvoice(
            RobosatsNetwork.mainnet,
            Sats.zero,
            payout: 'trade-1',
          ),
          throwsStateError,
        );
        expect(
          () => port.newReceiveAddress(RobosatsNetwork.mainnet),
          throwsStateError,
        );
      },
    );
  });
}
