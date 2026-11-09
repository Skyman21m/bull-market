import 'dart:math';
import 'dart:typed_data';

import 'package:bip32_keys/bip32_keys.dart';
import 'package:convert/convert.dart';
import 'package:robosats/src/bip32.dart';
import 'package:test/test.dart';

import 'support/vectors.dart';

Uint8List _bytes(String hexString) => Uint8List.fromList(hex.decode(hexString));

void main() {
  group('deriveBip32PrivateKey', () {
    test('reproduces test vector 1 of the BIP32 specification', () {
      final seed = _bytes('000102030405060708090a0b0c0d0e0f');
      expect(
        hex.encode(deriveBip32PrivateKey(seed, const [])),
        'e8f32e723decf4051aefac8e2c93c9c5b214313817cdb01a1494b917c8436b35',
      );
      expect(
        hex.encode(deriveBip32PrivateKey(seed, const [bip32Hardened])),
        'edb2e14f9ee77d26dd93b4ecede8d16ed408ce149b6cd80b0715a2d911a0afea',
      );
      expect(
        hex.encode(deriveBip32PrivateKey(seed, const [bip32Hardened, 1])),
        '3c6cb8d0f6a264c91ea8b5030fadaa8e538b020f0a387421a12de9319dc93368',
      );
    });

    final seed = _bytes(garageKeyVector['bip32_seed_sha512_hex'] as String);
    final derived = [...garageKeyRobots, base91ShortRobot];
    for (final robot in derived) {
      final index = robot['account_index'] as int;
      test('derives the RoboSats key at ${robot['derivation_path']}', () {
        final key = deriveBip32PrivateKey(seed, [
          44 | bip32Hardened,
          88 | bip32Hardened,
          index | bip32Hardened,
          0,
        ]);
        expect(hex.encode(key), robot['derived_private_key_hex']);
      });
    }

    test('agrees with the wallet BIP32 library on random seeds and paths', () {
      final random = Random(32);
      for (var i = 0; i < 25; i++) {
        final seed = Uint8List.fromList(
          List.generate(64, (_) => random.nextInt(256)),
        );
        final path = List.generate(
          1 + random.nextInt(5),
          (_) =>
              random.nextInt(1 << 31) | (random.nextBool() ? bip32Hardened : 0),
        );
        var node = Bip32Keys.fromSeed(seed);
        for (final index in path) {
          node = node.derive(index);
        }
        expect(deriveBip32PrivateKey(seed, path), node.private, reason: '$i');
      }
    });
  });
}
