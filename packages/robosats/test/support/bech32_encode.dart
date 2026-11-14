import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;

/// Writes bech32 and bech32m strings as BIP-173 and BIP-350 give the encoder in their reference code, independently of the package, with no length limit.
String encodeBech32(
  String humanReadablePart,
  List<int> words, {
  bool bech32m = false,
}) {
  const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  final values = [
    for (final unit in humanReadablePart.codeUnits) unit >> 5,
    0,
    for (final unit in humanReadablePart.codeUnits) unit & 31,
    ...words,
    0,
    0,
    0,
    0,
    0,
    0,
  ];
  final checksum = _polymod(values) ^ (bech32m ? 0x2bc830a3 : 1);
  return '${humanReadablePart}1${[...words, for (var i = 0; i < 6; i++) (checksum >> (5 * (5 - i))) & 31].map((word) => charset[word]).join()}';
}

int _polymod(List<int> values) {
  const generator = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  var checksum = 1;
  for (final value in values) {
    final top = checksum >> 25;
    checksum = ((checksum & 0x1ffffff) << 5) ^ value;
    for (var i = 0; i < 5; i++) {
      if (((top >> i) & 1) != 0) checksum ^= generator[i];
    }
  }
  return checksum;
}

/// A string with the shape of a BOLT11 invoice: the prefix [humanReadablePart] (`lntb1641u`, `lnbc`, …), [wordCount] data words drawn from [seed], and a bech32 checksum.
///
/// It is no invoice: no field of it means anything, so no node would pay it. The package only checks the shape before signing, and these strings exercise that check without any real invoice.
String invoiceShaped(
  String humanReadablePart, {
  String seed = 'payout invoice',
  int wordCount = 300,
  bool bech32m = false,
}) {
  final words = <int>[];
  for (var counter = 0; words.length < wordCount; counter++) {
    for (final byte in sha256.convert(utf8.encode('$seed/$counter')).bytes) {
      if (words.length < wordCount) words.add(byte & 31);
    }
  }
  return encodeBech32(humanReadablePart, words, bech32m: bech32m);
}
