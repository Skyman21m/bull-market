import 'package:bb_mobile/core/utils/payment_request.dart';
import 'package:bb_mobile/features/p2p_wallet/data/wallet_invoice_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/issued_quotes.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/wallet_invoice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';

import 'support/fakes.dart';
import 'support/payment_fakes.dart';

/// The wallet's decoder as the payment reads it, over a stand-in for `PaymentRequest.parse` (whose decoder is native code): what it maps, and that anything else is unreadable. And the record of the quotes given.
void main() {
  group('the wallet\'s reading of an invoice', () {
    WalletInvoiceRepositoryImpl over(Object answer) =>
        WalletInvoiceRepositoryImpl((text) async {
          if (answer is PaymentRequest) return answer;
          throw answer;
        });

    test(
      'maps a BOLT11 request: amount, hash in lower case, expiry, network',
      () async {
        final read = await over(
          PaymentRequest.bolt11(
            invoice: payBolt11(),
            amountSat: 600,
            paymentHash: payHash().toUpperCase(),
            description: 'not carried',
            expiresAt: testNow.millisecondsSinceEpoch ~/ 1000 + 180,
            isTestnet: true,
          ),
        ).read(payBolt11());
        final invoice = switch (read) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(invoice.amount, Sats.fromInt(600));
        expect(invoice.paymentHash, payHash());
        expect(invoice.expiresAt, testNow.add(const Duration(seconds: 180)));
        expect(invoice.expiresAt.isUtc, isTrue);
        expect(invoice.isTestnet, isTrue);
        expect('$invoice', 'WalletInvoice');
      },
    );

    test(
      'anything else, an error, no amount or no expiry is unreadable',
      () async {
        for (final answer in <Object>[
          const PaymentRequest.liquid(address: 'lq1x', isTestnet: false),
          const PaymentRequest.lnAddress(address: 'a@b.c'),
          PaymentRequest.bolt11(
            invoice: payBolt11(),
            amountSat: 0,
            paymentHash: payHash(),
            expiresAt: 1,
            isTestnet: false,
          ),
          PaymentRequest.bolt11(
            invoice: payBolt11(),
            amountSat: 600,
            paymentHash: payHash(),
            expiresAt: 0,
            isTestnet: false,
          ),
          'Invalid payment request',
          StateError('rust panic'),
        ]) {
          expect(
            await over(answer).read(payBolt11()),
            isA<Err<WalletInvoice, P2pWalletRefusal>>().having(
              (e) => e.failure,
              'failure',
              isA<P2pWalletInvoiceUnreadable>(),
            ),
            reason: '$answer',
          );
        }
      },
    );
  });

  group('the quotes given', () {
    P2pWalletQuote quote() => P2pWalletQuote(
      invoice: payInvoice(),
      payin: Sats.fromInt(603),
      networkFee: Sats.fromInt(26),
      balance: Sats.fromInt(1000),
      quotedAt: testNow,
    );

    test('a quote given is let through once', () {
      final issued = IssuedQuotes();
      final one = quote();
      issued.issue(one);
      expect(issued.consume(one), isTrue);
      expect(issued.consume(one), isFalse);
      // Given again after it was used, it stays used.
      issued.issue(one);
      expect(issued.consume(one), isFalse);
    });

    test(
      'an equal quote that was not given is refused: identity, not equality',
      () {
        final issued = IssuedQuotes();
        final given = quote();
        issued.issue(given);
        expect(issued.consume(quote()), isFalse);
        expect(issued.consume(given), isTrue);
        expect(IssuedQuotes().consume(given), isFalse);
      },
    );
  });
}
