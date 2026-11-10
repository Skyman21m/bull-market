import 'dart:typed_data';

/// The basE91 alphabet of Joachim Henke, as RoboSats uses it.
///
/// It is the alphabet of the `base-ex` 0.8.1 `Base91` class used by the frontend (`frontend/src/utils/hexToBase91.ts`) and of the Python `base91` 1.0.1 package used by the coordinator, and it is spelled out in `api/utils.py:668` (RoboSats commit ff1998c).
const String base91Alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#\$%&()*+,./:;<=>?@[]^_`{|}~"';

final List<int> _decodeTable = () {
  final table = List<int>.filled(128, -1);
  for (var i = 0; i < base91Alphabet.length; i++) {
    table[base91Alphabet.codeUnitAt(i)] = i;
  }
  return table;
}();

/// Encodes [bytes] with basE91.
///
/// Bits are consumed least-significant first, in groups of 13 bits, or 14 bits when the 13-bit value is below 89, and each group yields two characters: the remainder then the quotient of the division by 91.
String base91Encode(List<int> bytes) {
  final output = StringBuffer();
  var queue = 0;
  var queuedBits = 0;
  for (final byte in bytes) {
    queue |= (byte & 0xff) << queuedBits;
    queuedBits += 8;
    if (queuedBits > 13) {
      var value = queue & 8191;
      if (value > 88) {
        queue >>= 13;
        queuedBits -= 13;
      } else {
        value = queue & 16383;
        queue >>= 14;
        queuedBits -= 14;
      }
      output
        ..write(base91Alphabet[value % 91])
        ..write(base91Alphabet[value ~/ 91]);
    }
  }
  if (queuedBits > 0) {
    output.write(base91Alphabet[queue % 91]);
    if (queuedBits > 7 || queue > 90) {
      output.write(base91Alphabet[queue ~/ 91]);
    }
  }
  return output.toString();
}

/// Decodes a basE91 string, or returns `null` when [encoded] holds a character outside [base91Alphabet].
///
/// The client never needs to decode: this mirrors what the coordinator does with the token hash it receives, and backs the round-trip tests.
Uint8List? base91Decode(String encoded) {
  final output = BytesBuilder(copy: false);
  var queue = 0;
  var queuedBits = 0;
  var pending = -1;
  for (final unit in encoded.codeUnits) {
    final digit = unit < _decodeTable.length ? _decodeTable[unit] : -1;
    if (digit < 0) return null;
    if (pending < 0) {
      pending = digit;
      continue;
    }
    final value = pending + digit * 91;
    queue |= value << queuedBits;
    queuedBits += (value & 8191) > 88 ? 13 : 14;
    do {
      output.addByte(queue & 0xff);
      queue >>= 8;
      queuedBits -= 8;
    } while (queuedBits > 7);
    pending = -1;
  }
  if (pending >= 0) {
    output.addByte((queue | pending << queuedBits) & 0xff);
  }
  return output.takeBytes();
}
