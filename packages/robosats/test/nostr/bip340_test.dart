import 'dart:io';

import 'package:convert/convert.dart';
import 'package:robosats/src/nostr/schnorr.dart';
import 'package:test/test.dart';

/// The official BIP-340 vectors (`test/fixtures/nostr/README.md`), played through [Bip340], the one entry point of this package to the `bip340` package.
void main() {
  final rows = File('test/fixtures/nostr/bip340-test-vectors.csv')
      .readAsLinesSync()
      .skip(1)
      .where((line) => line.isNotEmpty)
      .map((line) => line.split(','))
      .toList();

  test(
    'the file has the 19 official vectors, 4 of them on messages that are not 32 bytes',
    () {
      expect(rows, hasLength(19));
      expect(
        [
          for (final row in rows)
            if (row[4].length != 64) row[0],
        ],
        ['15', '16', '17', '18'],
      );
    },
  );

  final digestRows = rows.where((row) => row[4].length == 64).toList();

  for (final row in digestRows) {
    final index = row[0];
    final secretKey = row[1];
    final publicKey = hex.decode(row[2].toLowerCase());
    final aux = row[3];
    final message = hex.decode(row[4].toLowerCase());
    final signature = hex.decode(row[5].toLowerCase());
    final expected = row[6] == 'TRUE';

    if (secretKey.isNotEmpty) {
      test('vector $index: signs as expected', () {
        expect(
          hex.encode(
            Bip340.sign(
              hex.decode(secretKey.toLowerCase()),
              message,
              hex.decode(aux.toLowerCase()),
            ),
          ),
          row[5].toLowerCase(),
        );
      });
    }

    test('vector $index: verifies to $expected', () {
      expect(Bip340.verify(publicKey, message, signature), expected);
    });
  }

  test('fifteen vectors are played, four of them signatures', () {
    expect(digestRows, hasLength(15));
    expect(digestRows.where((row) => row[1].isNotEmpty), hasLength(4));
  });

  test('a secret key out of range is an argument error, not a signature', () {
    final digest = List<int>.filled(32, 7);
    final aux = List<int>.filled(32, 9);
    expect(
      () => Bip340.sign(List<int>.filled(32, 0), digest, aux),
      throwsArgumentError,
    );
    expect(
      () => Bip340.sign(List<int>.filled(32, 0xff), digest, aux),
      throwsArgumentError,
    );
    expect(
      () => Bip340.sign(List<int>.filled(31, 1), digest, aux),
      throwsArgumentError,
    );
  });
}
