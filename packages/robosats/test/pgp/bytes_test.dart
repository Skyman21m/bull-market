import 'dart:typed_data';

import 'package:robosats/src/pgp/bytes.dart';
import 'package:test/test.dart';

void main() {
  group('multiprecision integers', () {
    test('are written without leading zero bytes, with an exact bit count', () {
      expect(mpiEncode([0x01]), [0, 1, 0x01]);
      expect(mpiEncode([0x40, 0xff]), [0, 15, 0x40, 0xff]);
      expect(mpiEncode([0, 0, 0x80]), [0, 8, 0x80]);
      expect(mpiEncode([0, 0]), [0, 0]);
      expect(mpiEncode([]), [0, 0]);
    });

    test('are read back and padded to their fixed length', () {
      final reader = ByteReader(Uint8List.fromList([0, 9, 0x01, 0xff, 7]));
      final magnitude = reader.mpi();
      expect(magnitude, [0x01, 0xff]);
      expect(reader.u8(), 7);
      expect(reader.isDone, isTrue);
      expect(leftPad(magnitude, 4), [0, 0, 0x01, 0xff]);
      expect(() => leftPad(magnitude, 1), throwsFormatException);
    });

    test('fail on truncated data', () {
      expect(
        () => ByteReader(Uint8List.fromList([0, 16, 1])).mpi(),
        throwsFormatException,
      );
      expect(() => ByteReader(Uint8List(1)).u16(), throwsFormatException);
    });
  });

  group('packets', () {
    test('are framed with the shortest definite new-format length', () {
      expect(encodePacket(2, List.filled(191, 0)).sublist(0, 2), [0xc2, 191]);
      expect(encodePacket(2, List.filled(192, 0)).sublist(0, 3), [
        0xc2,
        192,
        0,
      ]);
      expect(encodePacket(2, List.filled(8383, 0)).sublist(0, 3), [
        0xc2,
        223,
        255,
      ]);
      expect(encodePacket(18, List.filled(8384, 0)).sublist(0, 6), [
        0xd2,
        255,
        0,
        0,
        0x20,
        0xc0,
      ]);
    });

    test('are read in both formats', () {
      for (final length in [0, 1, 191, 192, 8383, 8384]) {
        final body = List.generate(length, (i) => i & 0xff);
        final packet = decodePackets(encodePacket(13, body)).single;
        expect(packet.tag, 13);
        expect(packet.body, body);
      }
      // Old format, as GnuPG exports keys: tag 6 with a one-byte, a two-byte and a four-byte length.
      for (final bytes in [
        [0x98, 2, 7, 8],
        [0x99, 0, 2, 7, 8],
        [0x9a, 0, 0, 0, 2, 7, 8],
      ]) {
        final packet = decodePackets(Uint8List.fromList(bytes)).single;
        expect(packet.tag, 6);
        expect(packet.body, [7, 8]);
      }
      final two = decodePackets(Uint8List.fromList([0x98, 1, 7, 0xcd, 1, 8]));
      expect(two.map((packet) => packet.tag), [6, 13]);
    });

    test('fail on what keys and signatures never contain', () {
      for (final bytes in [
        [0x00],
        [0xc2],
        [0xc2, 5, 1],
        [0xc2, 224, 1],
        [0x9b, 1],
      ]) {
        expect(
          () => decodePackets(Uint8List.fromList(bytes)),
          throwsFormatException,
          reason: '$bytes',
        );
      }
    });
  });

  test('bytesEqual compares content', () {
    expect(bytesEqual([1, 2], [1, 2]), isTrue);
    expect(bytesEqual([1, 2], [1, 3]), isFalse);
    expect(bytesEqual([1, 2], [1, 2, 3]), isFalse);
  });
}
