import 'dart:convert';

import 'package:primitives/primitives.dart';

import '../domain/trade/bolt11.dart';

/// A BOLT11 invoice made by a test, never a real one: its text and what it says, for the tests of the trade's checks and of the app's decoder (#86).
///
/// The text is a well-formed BOLT11 invoice (bech32 with its checksum, a timestamp, tagged fields), but its signature is 65 fixed bytes made from [seed], not a signature: the app's decoder does not check signatures (`bolt11_decoder` at f5deec21), and no node made it. Its payee, when it states one, is a key the test chooses.
final class Bolt11TestInvoice {
  /// The invoice text.
  final String text;

  /// What the text says, as a decoder must read it.
  final Bolt11Invoice facts;

  const Bolt11TestInvoice._(this.text, this.facts);

  /// An invoice of [sats] on [network], whose payment hash is 32 bytes made from [seed], made at [createdAt] (whole seconds) for [expiry], with [description] and the payee [payeeNodeKey] when given.
  ///
  /// [prefix] replaces the network's human-readable prefix (`lnbc`, `lntb`, `lntbs`, `lnbcrt`), and [amountText] the amount's text (by default the sats in nano-bitcoin, `{sats×10}n`), to make invoices a decoder must refuse; [paymentHashes] repeats the payment hash field.
  factory Bolt11TestInvoice({
    required Bolt11Network network,
    required int sats,
    required int seed,
    required DateTime createdAt,
    Duration expiry = const Duration(seconds: 3600),
    bool writeExpiry = true,
    String? description,
    String? payeeNodeKey,
    String? prefix,
    String? amountText,
    int paymentHashes = 1,
  }) {
    final hrp =
        '${prefix ?? _prefixes[network]}${amountText ?? '${sats * 10}n'}';
    final hash = List<int>.generate(32, (i) => (seed * 31 + i * 7 + 1) & 0xff);
    final seconds = createdAt.millisecondsSinceEpoch ~/ 1000;
    final words = <int>[
      ..._intWords(seconds, 7),
      for (var i = 0; i < paymentHashes; i++) ..._tag(1, _toWords(hash)),
      if (description != null) ..._tag(13, _toWords(utf8.encode(description))),
      if (writeExpiry) ..._tag(6, _minimalWords(expiry.inSeconds)),
      if (payeeNodeKey != null) ..._tag(19, _toWords(_hexBytes(payeeNodeKey))),
      ..._toWords(List<int>.generate(65, (i) => (seed * 13 + i * 5) & 0xff)),
    ];
    final text = _bech32(hrp, words);
    return Bolt11TestInvoice._(
      text,
      Bolt11Invoice(
        network: network,
        amount: Sats.fromInt(sats),
        paymentHash: _hex(hash),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        ),
        expiry: writeExpiry ? expiry : const Duration(seconds: 3600),
        description: description,
        payeeNodeKey: payeeNodeKey,
      ),
    );
  }

  static const _prefixes = {
    Bolt11Network.mainnet: 'lnbc',
    Bolt11Network.testnet: 'lntb',
    Bolt11Network.signet: 'lntbs',
    Bolt11Network.regtest: 'lnbcrt',
  };

  static const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  @override
  String toString() => 'Bolt11TestInvoice';
}

/// A decoder for the tests of the trade's checks: it reads back the invoices [Bolt11TestInvoice] made, as the app's decoder does (`test/features/p2p_wallet/bolt11_decoder_impl_test.dart` checks that both agree), and refuses any other text.
final class Bolt11TestDecoder implements Bolt11Decoder {
  final Map<String, Bolt11Invoice> _known = {};

  /// Every text it was given, in order.
  final List<String> decoded = [];

  Bolt11TestDecoder([Iterable<Bolt11TestInvoice> invoices = const []]) {
    invoices.forEach(add);
  }

  /// Makes [invoice] readable.
  void add(Bolt11TestInvoice invoice) => _known[invoice.text] = invoice.facts;

  @override
  Result<Bolt11Invoice, Bolt11Refusal> decode(String invoice) {
    decoded.add(invoice);
    return switch (_known[invoice]) {
      final facts? => Ok(facts),
      null => const Err(Bolt11Malformed()),
    };
  }
}

List<int> _tag(int type, List<int> data) => [
  type,
  data.length >> 5,
  data.length & 31,
  ...data,
];

List<int> _intWords(int value, int count) => [
  for (var i = count - 1; i >= 0; i--) (value >> (5 * i)) & 31,
];

List<int> _minimalWords(int value) {
  var count = 1;
  while (value >= 1 << (5 * count)) {
    count++;
  }
  return _intWords(value, count);
}

List<int> _toWords(List<int> bytes) {
  final words = <int>[];
  var accumulator = 0;
  var bits = 0;
  for (final byte in bytes) {
    accumulator = (accumulator << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      words.add((accumulator >> bits) & 31);
    }
    accumulator &= (1 << bits) - 1;
  }
  if (bits > 0) words.add((accumulator << (5 - bits)) & 31);
  return words;
}

List<int> _hexBytes(String hex) => [
  for (var i = 0; i + 1 < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

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

String _bech32(String hrp, List<int> data) {
  final expanded = [
    for (final unit in hrp.codeUnits) unit >> 5,
    0,
    for (final unit in hrp.codeUnits) unit & 31,
  ];
  final polymod = _polymod([...expanded, ...data, 0, 0, 0, 0, 0, 0]) ^ 1;
  final checksum = [for (var i = 0; i < 6; i++) (polymod >> (5 * (5 - i))) & 31];
  return '${hrp}1${[...data, ...checksum].map((word) => Bolt11TestInvoice._charset[word]).join()}';
}
