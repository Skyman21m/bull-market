import 'dart:io';
import 'dart:math';

import 'package:bb_mobile/features/p2p_bolt11/bolt11_decoder_impl.dart';
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
        expect(
          decoder.decode(made.text.toUpperCase()),
          isA<Ok<Bolt11Invoice, Bolt11Refusal>>(),
        );
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
    expect(
      refusalOf(made(amountText: '15n').text),
      isA<Bolt11AmountUnusable>(),
    );
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
      refusalOf(
        '${valid.substring(0, 20).toUpperCase()}${valid.substring(20)}',
      ),
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

  test('reads the amount only in the strict form of BOLT 11', () {
    String withAmount(String amount) => _invoice('lnbc$amount');
    final accepted = {
      '1m': 100000,
      '1u': 100,
      '10n': 1,
      '10000p': 1,
      '2500u': 250000,
      '25m': 2500000,
      '1': 100000000,
    };
    for (final MapEntry(key: amount, value: sats) in accepted.entries) {
      expect(
        switch (decoder.decode(withAmount(amount))) {
          Ok(:final value) => value.amount.value.toInt(),
          Err(:final failure) => failure,
        },
        sats,
        reason: amount,
      );
    }
    for (final amount in [
      '1n',
      '1p',
      '10p',
      '1230p',
      '15n',
      '0u',
      '01u',
      '001m',
      '1.5u',
      '1e3u',
      '1uu',
      '',
      '1000000000000000000000m',
    ]) {
      expect(
        decoder.decode(withAmount(amount)),
        isA<Err<Bolt11Invoice, Bolt11Refusal>>(),
        reason: amount,
      );
    }
  });

  test('refuses a field the decoder would read twice or wrap', () {
    Bolt11TestInvoice made({int descriptions = 1, int payees = 1}) =>
        Bolt11TestInvoice(
          network: Bolt11Network.mainnet,
          sats: 3207,
          seed: 1,
          createdAt: createdAt,
          description: 'one',
          payeeNodeKey: _coordinatorNode,
          descriptionFields: descriptions,
          payeeFields: payees,
        );
    expect(
      decoder.decode(made().text),
      isA<Ok<Bolt11Invoice, Bolt11Refusal>>(),
    );
    expect(refusalOf(made(descriptions: 2).text), isA<Bolt11Malformed>());
    expect(refusalOf(made(payees: 2).text), isA<Bolt11Malformed>());
    String withExpiry(List<int> data) =>
        _invoice('lnbc1u', tags: [..._tag(1, _hash52()), ..._tag(6, data)]);
    expect(switch (decoder.decode(withExpiry(_words(3600, 7)))) {
      Ok(:final value) => value.expiry.inSeconds,
      Err(:final failure) => failure,
    }, 3600);
    // Empty, longer than 7 words (the decoder wraps from 13), or given twice.
    expect(refusalOf(withExpiry([])), isA<Bolt11Malformed>());
    expect(refusalOf(withExpiry(_words(3600, 8))), isA<Bolt11Malformed>());
    expect(
      refusalOf(withExpiry([16, ...List.filled(12, 0), ..._words(3600, 13)])),
      isA<Bolt11Malformed>(),
    );
    expect(
      refusalOf(
        _invoice(
          'lnbc1u',
          tags: [
            ..._tag(1, _hash52()),
            ..._tag(6, _words(60, 2)),
            ..._tag(6, _words(3600, 3)),
          ],
        ),
      ),
      isA<Bolt11Malformed>(),
    );
  });

  test(
    'never throws on random text, and any invoice it reads has whole positive sats and a hash',
    () {
      final random = Random(106);
      for (var i = 0; i < 5000; i++) {
        final text = String.fromCharCodes(
          List.generate(random.nextInt(2001), (_) => 33 + random.nextInt(94)),
        );
        expect(() => decoder.decode(text), returnsNormally);
      }
      const hrps = [
        'lnbc',
        'lntb',
        'lntbs',
        'lnbcrt',
        'lnbc2500u',
        'lnbc1p',
        'lnbc10p',
        'lnbc1m',
        'lnbc20n',
        'lnbc0',
        'lnbc-1u',
        'lnbc1.5u',
        'lnbcu',
        'lnbc99999999999999999999999m',
        'lnsb1u',
      ];
      var read = 0;
      for (var i = 0; i < 5000; i++) {
        final hrp = hrps[random.nextInt(hrps.length)];
        final tags = <int>[];
        for (var k = random.nextInt(6); k > 0; k--) {
          final length = const [
            0,
            1,
            7,
            13,
            51,
            52,
            53,
            100,
          ][random.nextInt(8)];
          tags.addAll(
            _tag(
              random.nextInt(32),
              List.generate(length, (_) => random.nextInt(32)),
            ),
          );
        }
        if (random.nextInt(3) > 0) {
          tags.addAll(_tag(1, List.generate(52, (_) => random.nextInt(32))));
        }
        final text = _bech32(hrp, [
          ..._words(random.nextInt(1 << 30), 7),
          ...tags,
          ...List.filled(104, 7),
        ]);
        late Result<Bolt11Invoice, Bolt11Refusal> result;
        expect(() => result = decoder.decode(text), returnsNormally);
        if (result case Ok(:final value)) {
          read++;
          expect(value.amount.value > BigInt.zero, isTrue);
          expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(value.paymentHash), isTrue);
          expect(value.expiry.isNegative, isFalse);
        }
      }
      expect(read, greaterThan(0));
    },
  );

  test(
    'the adapter imports the decoder and the feature\'s port, nothing of the wallet',
    () {
      final source = File(
        'lib/features/p2p_bolt11/bolt11_decoder_impl.dart',
      ).readAsStringSync();
      final imports = RegExp(
        r"^import '([^']+)';",
        multiLine: true,
      ).allMatches(source).map((match) => match.group(1)).toSet();
      expect(imports, {
        'package:bolt11_decoder/bolt11_decoder.dart',
        'package:decimal/decimal.dart',
        'package:p2p/p2p.dart',
      });
    },
  );
}

const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

int _polymod(List<int> values) {
  const generator = [
    0x3b6a57b2,
    0x26508e6d,
    0x1ea119fa,
    0x3d4233dd,
    0x2a1462b3,
  ];
  var checksum = 1;
  for (final value in values) {
    final top = checksum >> 25;
    checksum = ((checksum & 0x1ffffff) << 5) ^ value;
    for (var i = 0; i < 5; i++) {
      if ((top >> i) & 1 == 1) checksum ^= generator[i];
    }
  }
  return checksum;
}

/// A bech32 text of [hrp] and [data] with its checksum: for invoices a test makes word by word.
String _bech32(String hrp, List<int> data) {
  final expanded = [
    for (final unit in hrp.codeUnits) unit >> 5,
    0,
    for (final unit in hrp.codeUnits) unit & 31,
  ];
  final polymod = _polymod([...expanded, ...data, 0, 0, 0, 0, 0, 0]) ^ 1;
  final checksum = [
    for (var i = 0; i < 6; i++) (polymod >> (5 * (5 - i))) & 31,
  ];
  return '${hrp}1${[...data, ...checksum].map((word) => _charset[word]).join()}';
}

List<int> _tag(int type, List<int> data) => [
  type,
  data.length >> 5,
  data.length & 31,
  ...data,
];

List<int> _words(int value, int count) => [
  for (var i = count - 1; i >= 0; i--) (value >> (5 * i)) & 31,
];

List<int> _hash52() => List.filled(52, 3);

/// An invoice of [hrp] made word by word: a timestamp, [tags] (one payment hash by default) and 104 words of fixed bytes as its signature.
String _invoice(String hrp, {List<int>? tags}) => _bech32(hrp, [
  ..._words(1794556800, 7),
  ...(tags ?? _tag(1, _hash52())),
  ...List.filled(104, 7),
]);
