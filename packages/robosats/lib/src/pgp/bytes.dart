import 'dart:typed_data';

/// Reads big-endian OpenPGP fields from a byte sequence.
///
/// Every read past the end throws a [FormatException], the signal this package uses internally for malformed OpenPGP data.
final class ByteReader {
  final Uint8List _bytes;
  int _offset = 0;

  ByteReader(this._bytes);

  /// Whether every byte has been read.
  bool get isDone => _offset >= _bytes.length;

  /// The number of bytes read so far.
  int get offset => _offset;

  int u8() => take(1)[0];

  int u16() {
    final bytes = take(2);
    return bytes[0] << 8 | bytes[1];
  }

  int u32() {
    final bytes = take(4);
    return bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3];
  }

  /// The next [length] bytes, as a view on the underlying buffer.
  Uint8List take(int length) {
    if (length < 0 || _offset + length > _bytes.length) {
      throw const FormatException('truncated OpenPGP data');
    }
    final view = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return view;
  }

  /// The [length] bytes read just before the current position.
  Uint8List lastRead(int length) =>
      Uint8List.sublistView(_bytes, _offset - length, _offset);

  /// Every remaining byte.
  Uint8List rest() => take(_bytes.length - _offset);

  /// The magnitude bytes of a multiprecision integer: a two-byte bit count, then the big-endian value.
  Uint8List mpi() => take((u16() + 7) >> 3);
}

/// Encodes [magnitude], a big-endian unsigned integer, as an OpenPGP multiprecision integer.
///
/// Leading zero bytes are dropped and the bit count is exact, as OpenPGP.js and GnuPG write it.
Uint8List mpiEncode(List<int> magnitude) {
  var start = 0;
  while (start < magnitude.length && magnitude[start] == 0) {
    start++;
  }
  if (start == magnitude.length) return Uint8List(2);
  final bits =
      (magnitude.length - start) * 8 - (8 - magnitude[start].bitLength);
  return Uint8List.fromList([bits >> 8, bits & 0xff, ...magnitude.skip(start)]);
}

/// Restores the leading zero bytes an OpenPGP multiprecision integer drops, up to [length] bytes.
///
/// Throws a [FormatException] when [magnitude] is longer than [length].
Uint8List leftPad(List<int> magnitude, int length) {
  if (magnitude.length > length) {
    throw const FormatException('OpenPGP integer out of range');
  }
  return Uint8List(length)
    ..setRange(length - magnitude.length, length, magnitude);
}

Uint8List u16Bytes(int value) => Uint8List.fromList([value >> 8, value & 0xff]);

Uint8List u32Bytes(int value) => Uint8List.fromList([
  value >> 24 & 0xff,
  value >> 16 & 0xff,
  value >> 8 & 0xff,
  value & 0xff,
]);

/// Overwrites a buffer that held a secret, as far as Dart allows: copies the runtime made are out of reach.
void wipe(Uint8List secret) => secret.fillRange(0, secret.length, 0);

/// Compares two byte sequences without stopping at the first difference.
bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

/// An OpenPGP packet: its tag and its body, without the header.
typedef RawPacket = ({int tag, Uint8List body});

/// OpenPGP packet tags used by RoboSats keys and messages.
abstract final class PacketTag {
  static const publicKeyEncryptedSessionKey = 1;
  static const signature = 2;
  static const onePassSignature = 4;
  static const secretKey = 5;
  static const publicKey = 6;
  static const secretSubkey = 7;
  static const compressedData = 8;
  static const literalData = 11;
  static const userId = 13;
  static const publicSubkey = 14;
  static const integrityProtectedData = 18;
}

/// Frames [body] as a new-format packet with a definite length, as OpenPGP.js does.
Uint8List encodePacket(int tag, List<int> body) {
  final length = body.length;
  final List<int> header;
  if (length < 192) {
    header = [length];
  } else if (length < 8384) {
    header = [((length - 192) >> 8) + 192, (length - 192) & 0xff];
  } else {
    header = [0xff, ...u32Bytes(length)];
  }
  return Uint8List.fromList([0xc0 | tag, ...header, ...body]);
}

/// Splits [bytes] into at most [maxPackets] packets, accepting the old format GnuPG exports and the new format OpenPGP.js writes.
///
/// Throws a [FormatException] on truncated data, on a stray byte and on too many packets.
/// Partial and indeterminate lengths, which only message contents use, are refused unless [streamLengths] is set.
List<RawPacket> decodePackets(
  Uint8List bytes, {
  required int maxPackets,
  bool streamLengths = false,
}) {
  final reader = ByteReader(bytes);
  final packets = <RawPacket>[];
  while (!reader.isDone) {
    if (packets.length == maxPackets) {
      throw const FormatException('too many OpenPGP packets');
    }
    final header = reader.u8();
    if (header & 0x80 == 0) {
      throw const FormatException('not an OpenPGP packet');
    }
    if (header & 0x40 != 0) {
      packets.add((
        tag: header & 0x3f,
        body: _newFormatBody(reader, streamLengths: streamLengths),
      ));
      continue;
    }
    final Uint8List body;
    switch (header & 0x03) {
      case 0:
        body = reader.take(reader.u8());
      case 1:
        body = reader.take(reader.u16());
      case 2:
        body = reader.take(reader.u32());
      default:
        // An indeterminate length runs to the end of the data: GnuPG frames compressed data so.
        if (!streamLengths) {
          throw const FormatException('indeterminate OpenPGP packet length');
        }
        body = reader.rest();
    }
    packets.add((tag: (header & 0x3f) >> 2, body: body));
  }
  return packets;
}

/// The body of a new-format packet, its partial chunks joined when [streamLengths] allows them.
Uint8List _newFormatBody(ByteReader reader, {required bool streamLengths}) {
  BytesBuilder? chunks;
  while (true) {
    final first = reader.u8();
    final int length;
    if (first < 192) {
      length = first;
    } else if (first < 224) {
      length = ((first - 192) << 8) + reader.u8() + 192;
    } else if (first == 255) {
      length = reader.u32();
    } else {
      if (!streamLengths) {
        throw const FormatException('partial OpenPGP packet length');
      }
      (chunks ??= BytesBuilder(
        copy: false,
      )).add(reader.take(1 << (first & 0x1f)));
      continue;
    }
    final last = reader.take(length);
    if (chunks == null) return last;
    chunks.add(last);
    return chunks.takeBytes();
  }
}
