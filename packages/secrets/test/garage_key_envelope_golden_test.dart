import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secrets/secrets.dart';
import 'package:secrets/src/data/models/key_model.dart';

import 'fake_secure_storage_platform.dart';
import 'result_helpers.dart';

/// The on-disk shape of a Garage Key is a **frozen contract** from its first release.
///
/// Once written on a device, an envelope that no longer opens is a lost key, and with it every robot derived from it. So these tests pin the literal strings, as `secret_model_golden_test.dart` does for the seeds: a round trip through the model alone stays green even if both directions drift together.
void main() {
  // Fixed test bytes, 0x01 to 0x20.
  final testBytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

  const mainnetGolden =
      '{"v":1,"kind":"garage",'
      '"name":"com.bullbitcoin.secrets/garage/p2p/mainnet",'
      '"bytes":"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",'
      '"createdAt":"2026-11-11T00:00:00.000Z"}';
  const testnetGolden =
      '{"v":1,"kind":"garage",'
      '"name":"com.bullbitcoin.secrets/garage/p2p/testnet",'
      '"bytes":"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",'
      '"createdAt":"2026-11-11T00:00:00.000Z"}';

  final slots = {
    GarageKeySlot.mainnet: (
      key: 'com.bullbitcoin.secrets/garage/p2p/mainnet',
      golden: mainnetGolden,
    ),
    GarageKeySlot.testnet: (
      key: 'com.bullbitcoin.secrets/garage/p2p/testnet',
      golden: testnetGolden,
    ),
  };

  GarageKeys keysWith(FakeSecureStoragePlatform storage) {
    storage.install();
    return Secrets(scratchDirectory: () async => '.').garageKeys();
  }

  /// The stored value with its creation time pinned, so the rest compares byte for byte.
  String pinCreatedAt(String stored) =>
      stored.replaceFirstMapped(RegExp(r'"createdAt":"([^"]*)"'), (match) {
        final written = match.group(1) ?? fail('no createdAt');
        expect(DateTime.parse(written).isUtc, isTrue, reason: 'written in UTC');
        expect(written, endsWith('Z'));
        return '"createdAt":"2026-11-11T00:00:00.000Z"';
      });

  for (final MapEntry(key: slot, value: (:key, :golden)) in slots.entries) {
    group('the ${slot.name} slot', () {
      test('the stored shape opens to the same bytes', () async {
        final storage = FakeSecureStoragePlatform(entries: {key: golden});

        expect(ok(await keysWith(storage).read(slot: slot)).bytes, testBytes);
      });

      test(
        'a written key has exactly this shape, under exactly this key',
        () async {
          final storage = FakeSecureStoragePlatform();

          ok(await keysWith(storage).import(slot: slot, bytes: testBytes));

          expect(storage.entries.keys, [key]);
          expect(
            pinCreatedAt(storage.entries[key] ?? fail('nothing stored')),
            golden,
          );
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );

      test('the model encodes to exactly these bytes', () {
        final decoded = KeyModel.fromJson(
          jsonDecode(golden) as Map<String, dynamic>,
          expectedName: key,
          expectedKind: KeyKind.garage,
        );

        expect(jsonEncode(decoded.toJson()), golden);
      });
    });
  }

  test('one slot never opens the envelope of the other', () async {
    final storage = FakeSecureStoragePlatform(
      entries: {'com.bullbitcoin.secrets/garage/p2p/testnet': mainnetGolden},
    );

    expect(
      err(await keysWith(storage).read(slot: GarageKeySlot.testnet)),
      isA<GarageKeyCorruptFailure>(),
    );
  });

  test('the kind names on disk are frozen', () {
    expect(
      {for (final kind in KeyKind.values) kind: kind.wire},
      {KeyKind.dek: 'dek', KeyKind.garage: 'garage'},
    );
  });
}
