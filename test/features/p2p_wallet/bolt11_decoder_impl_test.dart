import 'dart:math';

import 'package:bb_mobile/features/p2p_wallet/data/bolt11_decoder_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/testing.dart';

/// temple's mainnet node key, as the federation list gives it: public data.
final String _coordinatorNode = switch (Federation.robosats.byAlias('temple')) {
  final temple? => temple.nodesPubkeys(RobosatsNetwork.mainnet).first,
  null => throw StateError('no temple'),
};

void main() {
  const decoder = Bolt11DecoderImpl();
  final createdAt = DateTime.utc(2026, 11, 13, 8);

  Bolt11Refusal? refusalOf(String text) => switch (decoder.decode(text)) {
    Err(:final failure) => failure,
    Ok() => null,
  };

  void expectSameFacts(Bolt11Invoice decoded, Bolt11Invoice made) {
    expect(decoded.network, made.network);
    expect(decoded.amount, made.amount);
    // Booleans, so that a failure prints no hash.
    expect(decoded.paymentHash == made.paymentHash, isTrue);
    expect(decoded.createdAt, made.createdAt);
    expect(decoded.expiry, made.expiry);
    expect(decoded.description, made.description);
    expect(decoded.payeeNodeKey == made.payeeNodeKey, isTrue);
  }

  test(
    'reads the invoices the tests make as the trade tests\' decoder does, on every network',
    () {
      final random = Random(86);
      for (var seed = 0; seed < 300; seed++) {
        final network =
            Bolt11Network.values[random.nextInt(Bolt11Network.values.length)];
        final made = Bolt11TestInvoice(
          network: network,
          sats: 1 + random.nextInt(2000000),
          seed: seed,
          createdAt: createdAt.add(Duration(seconds: random.nextInt(100000))),
          expiry: Duration(seconds: random.nextInt(100000)),
          writeExpiry: random.nextInt(5) != 0,
          description: random.nextBool()
              ? "temple - Taking 'Order $seed' Buying BTC – é"
              : null,
          payeeNodeKey: random.nextInt(3) == 0 ? _coordinatorNode : null,
        );
        final decoded = switch (decoder.decode(made.text)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('seed $seed: $failure'),
        };
        expectSameFacts(decoded, made.facts);
        final same = switch (Bolt11TestDecoder([made]).decode(made.text)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expectSameFacts(decoded, same);
        // Upper case is the same invoice (bech32 allows one case).
        expect(decoder.decode(made.text.toUpperCase()), isA<Ok<Bolt11Invoice, Bolt11Refusal>>());
      }
    },
  );

  test('refuses what is not a usable invoice, with a type', () {
    Bolt11TestInvoice made({
      String? prefix,
      String? amountText,
      int paymentHashes = 1,
      Bolt11Network network = Bolt11Network.mainnet,
    }) => Bolt11TestInvoice(
      network: network,
      sats: 3207,
      seed: 1,
      createdAt: createdAt,
      prefix: prefix,
      amountText: amountText,
      paymentHashes: paymentHashes,
    );

    // No amount, a fraction of a sat, zero.
    expect(refusalOf(made(amountText: '').text), isA<Bolt11AmountUnusable>());
    expect(refusalOf(made(amountText: '1p').text), isA<Bolt11AmountUnusable>());
    expect(refusalOf(made(amountText: '15n').text), isA<Bolt11AmountUnusable>());
    expect(refusalOf(made(amountText: '0n').text), isA<Bolt11AmountUnusable>());
    // An unknown prefix or amount.
    expect(refusalOf(made(prefix: 'lnxx').text), isA<Bolt11Malformed>());
    expect(refusalOf(made(amountText: '10x').text), isA<Bolt11Malformed>());
    // No payment hash, or two.
    expect(refusalOf(made(paymentHashes: 0).text), isA<Bolt11Malformed>());
    expect(refusalOf(made(paymentHashes: 2).text), isA<Bolt11Malformed>());
    // A wrong checksum, a truncated text, garbage, mixed case.
    final valid = made().text;
    final flipped =
        '${valid.substring(0, valid.length - 1)}${valid.endsWith('q') ? 'p' : 'q'}';
    expect(refusalOf(flipped), isA<Bolt11Malformed>());
    expect(refusalOf(valid.substring(0, 60)), isA<Bolt11Malformed>());
    expect(refusalOf('not an invoice'), isA<Bolt11Malformed>());
    expect(refusalOf('lnbc1'), isA<Bolt11Malformed>());
    expect(
      refusalOf('${valid.substring(0, 20).toUpperCase()}${valid.substring(20)}'),
      isA<Bolt11Malformed>(),
    );
  });

  test('never throws, whatever the text', () {
    final random = Random(1186);
    final valid = Bolt11TestInvoice(
      network: Bolt11Network.mainnet,
      sats: 3207,
      seed: 3,
      createdAt: createdAt,
      description: 'a description',
      payeeNodeKey: _coordinatorNode,
    ).text;
    const alphabet = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l1bio-';
    for (var round = 0; round < 3000; round++) {
      final chars = valid.split('');
      for (var change = 1 + random.nextInt(4); change > 0; change--) {
        final at = random.nextInt(chars.length);
        switch (random.nextInt(3)) {
          case 0:
            chars[at] = alphabet[random.nextInt(alphabet.length)];
          case 1:
            chars.removeAt(at);
          default:
            chars.insert(at, alphabet[random.nextInt(alphabet.length)]);
        }
      }
      final text = chars.join();
      expect(
        () => decoder.decode(text),
        returnsNormally,
        reason: 'round $round',
      );
    }
  });
}
