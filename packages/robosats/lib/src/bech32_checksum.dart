import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The two checksums of bech32 strings: bech32 (BIP-173), and bech32m (BIP-350), which differ only by the constant the checksum is compared with.
///
/// The `bech32` dependency (0.2.2) knows bech32 only, caps strings at 90 characters and does not report which constant matched, so this file does the checksum by hand, as BIP-350 gives it in its reference code.
@internal
enum Bech32Variant {
  bech32(1),
  bech32m(0x2bc830a3);

  final int constant;

  const Bech32Variant(this.constant);
}

/// A bech32 string read once: its human-readable part in lowercase, its data words before the checksum, and the checksum it carries.
@internal
final class Bech32Parts {
  final String humanReadablePart;
  final Uint8List words;
  final Bech32Variant variant;

  const Bech32Parts._(this.humanReadablePart, this.words, this.variant);
}

/// Why a string is not a bech32 string.
@internal
enum Bech32Refusal {
  /// Too long, mixed case, a character outside the printable ASCII range or the charset, no separator, an empty human-readable part, or fewer than 6 data characters.
  malformed,

  /// The checksum matches neither constant: most likely a typo.
  badChecksum,
}

const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

/// The value of each character of [_charset], or -1, indexed by its code unit (0 to 127).
final Int8List _values = () {
  final values = Int8List(128)..fillRange(0, 128, -1);
  for (var i = 0; i < _charset.length; i++) {
    values[_charset.codeUnitAt(i)] = i;
  }
  return values;
}();

int _polymod(Iterable<int> values) {
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
    checksum = (checksum & 0x1ffffff) << 5 ^ value;
    for (var i = 0; i < 5; i++) {
      if ((top >> i) & 1 == 1) checksum ^= generator[i];
    }
  }
  return checksum;
}

/// Reads [text] as a bech32 or bech32m string of at most [maxLength] characters, which is checked before anything else is read.
///
/// BIP-173: an all-lowercase or all-uppercase string of printable ASCII, a human-readable part of at least one character, the last `1` as separator, then at least 6 characters of the charset, the last 6 the checksum.
/// Which constant the checksum matches is reported: whether that variant is the right one for the string is the caller's rule (BIP-350 for segwit addresses, bech32 for BOLT11 invoices).
@internal
({Bech32Parts? parts, Bech32Refusal? refusal}) readBech32(
  String text, {
  required int maxLength,
}) {
  const malformed = (parts: null, refusal: Bech32Refusal.malformed);
  if (text.length > maxLength || text.length < 8) return malformed;
  var hasLower = false;
  var hasUpper = false;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit < 33 || unit > 126) return malformed;
    if (unit >= 0x61 && unit <= 0x7a) hasLower = true;
    if (unit >= 0x41 && unit <= 0x5a) hasUpper = true;
  }
  if (hasLower && hasUpper) return malformed;
  final lower = text.toLowerCase();
  final separator = lower.lastIndexOf('1');
  if (separator < 1 || lower.length - separator - 1 < 6) return malformed;
  final humanReadablePart = lower.substring(0, separator);
  final data = Uint8List(lower.length - separator - 1);
  for (var i = 0; i < data.length; i++) {
    final value = _values[lower.codeUnitAt(separator + 1 + i)];
    if (value < 0) return malformed;
    data[i] = value;
  }
  final checksum = _polymod([
    for (var i = 0; i < humanReadablePart.length; i++)
      humanReadablePart.codeUnitAt(i) >> 5,
    0,
    for (var i = 0; i < humanReadablePart.length; i++)
      humanReadablePart.codeUnitAt(i) & 31,
    ...data,
  ]);
  for (final variant in Bech32Variant.values) {
    if (checksum == variant.constant) {
      return (
        parts: Bech32Parts._(
          humanReadablePart,
          Uint8List.sublistView(data, 0, data.length - 6),
          variant,
        ),
        refusal: null,
      );
    }
  }
  return (parts: null, refusal: Bech32Refusal.badChecksum);
}

/// Regroups 5-bit words into bytes, or returns `null` when the padding left over is 5 bits or more or is not all zero bits (BIP-173, `convertbits` with `pad=False`).
@internal
Uint8List? bytesFromWords(List<int> words) {
  final bytes = BytesBuilder(copy: false);
  var accumulator = 0;
  var bits = 0;
  for (final word in words) {
    accumulator = (accumulator << 5 | word) & 0xfff;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.addByte(accumulator >> bits & 0xff);
    }
  }
  if (bits >= 5 || accumulator & ((1 << bits) - 1) != 0) return null;
  return bytes.takeBytes();
}
