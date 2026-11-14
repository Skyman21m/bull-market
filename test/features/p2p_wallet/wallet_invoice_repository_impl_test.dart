import 'dart:async';
import 'dart:io';

import 'package:bb_mobile/features/p2p_wallet/data/wallet_invoice_repository_impl.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/issued_quotes.dart';
import 'package:bb_mobile/features/p2p_wallet/domain/entities/wallet_invoice.dart';
import 'package:bull_logger/bull_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';

import 'support/fakes.dart';
import 'support/payment_fakes.dart';

/// The wallet's BOLT11 decoder as the payment reads it, over a stand-in for Boltz's `DecodedInvoice.fromString` (native code): what it maps, that anything else is unreadable, and that a failing decode logs and prints nothing. And the record of the quotes given.
void main() {
  group('the wallet\'s reading of an invoice', () {
    WalletInvoiceRepositoryImpl over(Object answer) =>
        WalletInvoiceRepositoryImpl((text) async {
          if (answer is WalletBolt11Read) return answer;
          throw answer;
        });

    WalletBolt11Read decoded({
      int msats = 600000,
      String? hash,
      int expiresAt = 0,
      String network = 'bitcoin',
    }) => (
      msats: BigInt.from(msats),
      paymentHash: hash ?? payHash().toUpperCase(),
      expiresAt: BigInt.from(
        expiresAt == 0
            ? testNow.millisecondsSinceEpoch ~/ 1000 + 180
            : expiresAt,
      ),
      network: network,
    );

    test(
      'maps what the decoder reads: amount, hash in lower case, expiry, network',
      () async {
        final read = await over(decoded()).read(payBolt11());
        final invoice = switch (read) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(invoice.amount, Sats.fromInt(600));
        expect(invoice.paymentHash, payHash());
        expect(invoice.expiresAt, testNow.add(const Duration(seconds: 180)));
        expect(invoice.expiresAt.isUtc, isTrue);
        expect(invoice.isTestnet, isFalse);
        expect('$invoice', 'WalletInvoice');
        for (final network in ['testnet', 'signet', 'regtest']) {
          final other = await over(decoded(network: network)).read(payBolt11());
          expect(
            other,
            isA<Ok<WalletInvoice, P2pWalletRefusal>>().having(
              (ok) => ok.value.isTestnet,
              'isTestnet',
              isTrue,
            ),
            reason: network,
          );
        }
      },
    );

    test(
      'an error, no amount, a fraction of a sat or no usable expiry is unreadable',
      () async {
        for (final answer in <Object>[
          decoded(msats: 0),
          decoded(msats: 600001),
          decoded(expiresAt: -1),
          decoded(expiresAt: 253402300800),
          'Invalid invoice',
          StateError('rust panic'),
          Exception('bad signature'),
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

    test(
      'a decode that fails (a bad signature, say) logs and prints nothing, and keeps no text',
      () async {
        final invoice = payBolt11();
        final seen = <Object>[];
        final output = await _capture(() async {
          final result = await over(
            Exception('signature does not match $invoice'),
          ).read(invoice);
          seen.add(result);
          if (result case Err(:final failure)) {
            seen
              ..add(failure)
              ..add(failure.logMessage ?? '');
          }
        });
        final lines = output
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();
        expect(lines, hasLength(2));
        expect(output, isNot(contains(invoice)));
        expect(seen.map((v) => '$v').join(), isNot(contains(invoice)));
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

    test(
      'a quote given is let through once, with the wallet it was given for',
      () {
        final issued = IssuedQuotes();
        final one = quote();
        issued.issue(one, walletId: 'instant');
        expect(issued.consume(one), 'instant');
        expect(issued.consume(one), isNull);
        // Given again after it was used, it stays used; given again for another wallet, it keeps its first.
        issued.issue(one, walletId: 'other');
        expect(issued.consume(one), isNull);
        final two = quote();
        issued
          ..issue(two, walletId: 'instant')
          ..issue(two, walletId: 'other');
        expect(issued.consume(two), 'instant');
      },
    );

    test(
      'an equal quote that was not given is refused: identity, not equality',
      () {
        final issued = IssuedQuotes();
        final given = quote();
        issued.issue(given, walletId: 'instant');
        expect(issued.consume(quote()), isNull);
        expect(issued.consume(given), 'instant');
        expect(IssuedQuotes().consume(given), isNull);
      },
    );
  });
}

/// Everything [body] prints and everything the project logger writes while it runs, as one text; a line printed and a line logged by the capture itself show that both are seen.
Future<String> _capture(Future<void> Function() body) async {
  final printed = <String>[];
  final directory = Directory.systemTemp.createTempSync('p2p_wallet_decode');
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
