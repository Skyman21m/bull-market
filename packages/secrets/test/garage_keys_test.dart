import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart' as convert;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:primitives/primitives.dart';
import 'package:secrets/secrets.dart';

import 'fake_secure_storage_platform.dart';
import 'result_helpers.dart';

/// The Garage Keys of the P2P feature: random, one per network, never replaced, never mixed with a seed.
///
/// Through the public handle, on the real package over the in-memory keystore. Creating into an empty slot settles the absence with the full read budget under the lock, so each such test waits ~4.5 s of real time.
void main() {
  const mainnetKey = 'com.bullbitcoin.secrets/garage/p2p/mainnet';
  const testnetKey = 'com.bullbitcoin.secrets/garage/p2p/testnet';
  const seedKey = 'seed_73c5da0a';

  // Fixed test bytes, 0x01 to 0x20: not a key anyone uses.
  final testBytes = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
  final testHex = convert.hex.encode(testBytes);

  // The published BIP39 test mnemonic, filed under its known fingerprint.
  final seedEntry = jsonEncode({
    'mnemonicWords': [...List.filled(11, 'abandon'), 'about'],
    'passphrase': null,
    'runtimeType': 'mnemonic',
  });

  String envelope({
    Object v = 1,
    String kind = 'garage',
    String name = mainnetKey,
    String? bytes,
    String createdAt = '2026-11-11T00:00:00.000Z',
  }) => jsonEncode({
    'v': v,
    'kind': kind,
    'name': name,
    'bytes': bytes ?? testHex,
    'createdAt': createdAt,
  });

  GarageKeys keysWith(FakeSecureStoragePlatform storage) {
    storage.install();
    return Secrets(scratchDirectory: () async => '.').garageKeys();
  }

  Map<String, dynamic> stored(FakeSecureStoragePlatform storage, String key) =>
      jsonDecode(storage.entries[key]!) as Map<String, dynamic>;

  const slow = Timeout(Duration(seconds: 60));

  group('creating a Garage Key', () {
    test(
      'create draws 32 bytes into an empty slot, and read gives them back',
      () async {
        final storage = FakeSecureStoragePlatform();
        final keys = keysWith(storage);

        final created = ok(await keys.create(slot: GarageKeySlot.mainnet));

        expect(created.bytes, hasLength(GarageKeyMaterial.lengthInBytes));
        expect(storage.entries.keys, [mainnetKey]);
        final envelope = stored(storage, mainnetKey);
        expect(envelope['v'], 1);
        expect(envelope['kind'], 'garage');
        expect(envelope['name'], mainnetKey);
        expect(envelope['bytes'], convert.hex.encode(created.bytes));
        expect(
          ok(await keys.read(slot: GarageKeySlot.mainnet)).bytes,
          created.bytes,
        );
      },
      timeout: slow,
    );

    test('each network has its own slot, under its own name', () async {
      final storage = FakeSecureStoragePlatform();
      final keys = keysWith(storage);

      final testnet = ok(await keys.create(slot: GarageKeySlot.testnet));
      expect(storage.entries.keys, [testnetKey]);
      expect(stored(storage, testnetKey)['name'], testnetKey);

      final mainnet = ok(await keys.create(slot: GarageKeySlot.mainnet));
      expect(storage.entries.keys, unorderedEquals([testnetKey, mainnetKey]));
      expect(mainnet.bytes, isNot(testnet.bytes));
      expect(
        ok(await keys.read(slot: GarageKeySlot.testnet)).bytes,
        testnet.bytes,
      );
    }, timeout: slow);

    for (final (label, handles) in [
      ('one handle', 1),
      ('two handles, the lock being static', 2),
    ]) {
      test('two simultaneous creates store one key, from $label', () async {
        // Unserialised, both would settle a miss, draw, and write; the second
        // write would win, and the first caller would derive robots from a key
        // that no longer exists. The store's writes take time, as a real
        // keystore's do: an in-memory write lands within the first caller's
        // microtasks, before the second caller's last read, so without the
        // delay this test passes with no lock at all.
        final storage = _SlowWrites()..install();
        final first = Secrets(scratchDirectory: () async => '.').garageKeys();
        final second = handles == 1
            ? first
            : Secrets(scratchDirectory: () async => '.').garageKeys();

        final (a, b) = await (
          first.create(slot: GarageKeySlot.mainnet),
          second.create(slot: GarageKeySlot.mainnet),
        ).wait;

        final results = [a, b];
        final created = results
            .whereType<Ok<GarageKeyMaterial, SecretFailure>>();
        final refused = results
            .whereType<Err<GarageKeyMaterial, SecretFailure>>();
        expect(created, hasLength(1));
        expect(refused.single.failure, isA<GarageKeyAlreadyExistsFailure>());
        expect(storage.entries.keys, [mainnetKey]);
        expect(
          stored(storage, mainnetKey)['bytes'],
          convert.hex.encode(created.single.value.bytes),
        );
      }, timeout: slow);
    }
  });

  group('a stored entry is never replaced', () {
    final occupants = <String, String>{
      'a valid key': envelope(),
      'an empty value': '',
      'a value that is not JSON': 'not json at all',
      'a key of another kind': envelope(kind: 'dek'),
      'a key filed under another slot': envelope(name: testnetKey),
      'a truncated key': envelope(bytes: testHex.substring(0, 62)),
      'a newer envelope version': envelope(v: 2),
    };
    for (final MapEntry(key: label, value: occupant) in occupants.entries) {
      test('$label refuses create and import, and stays', () async {
        final storage = FakeSecureStoragePlatform(
          entries: {mainnetKey: occupant},
        );
        final keys = keysWith(storage);

        expect(
          err(await keys.create(slot: GarageKeySlot.mainnet)),
          isA<GarageKeyAlreadyExistsFailure>(),
        );
        expect(
          err(
            await keys.import(
              slot: GarageKeySlot.mainnet,
              bytes: Uint8List(32),
            ),
          ),
          isA<GarageKeyAlreadyExistsFailure>(),
        );
        expect(storage.entries, {mainnetKey: occupant});
      }, timeout: slow);
    }

    test('a single false miss does not let a create replace a key', () async {
      final storage = FakeSecureStoragePlatform(
        entries: {mainnetKey: envelope()},
        scripted: [null],
      );

      expect(
        err(await keysWith(storage).create(slot: GarageKeySlot.mainnet)),
        isA<GarageKeyAlreadyExistsFailure>(),
      );
      expect(storage.entries, {mainnetKey: envelope()});
    });

    test(
      'absence is believed only after the full read budget, under the lock',
      () async {
        // Four false misses: the two reads of the under-lock budget would
        // have believed the slot empty and written over the key.
        final storage = FakeSecureStoragePlatform(
          entries: {mainnetKey: envelope()},
          scripted: [null, null, null, null],
        );

        expect(
          err(await keysWith(storage).create(slot: GarageKeySlot.mainnet)),
          isA<GarageKeyAlreadyExistsFailure>(),
        );
        expect(storage.reads, 5);
        expect(storage.entries, {mainnetKey: envelope()});
      },
      timeout: slow,
    );

    test('a read that keeps failing writes nothing', () async {
      PlatformException failing() => PlatformException(code: 'read failed');
      for (final attempt in [
        (GarageKeys keys) => keys.create(slot: GarageKeySlot.mainnet),
        (GarageKeys keys) =>
            keys.import(slot: GarageKeySlot.mainnet, bytes: testBytes),
      ]) {
        final storage = FakeSecureStoragePlatform(
          scripted: List.generate(5, (_) => failing()),
        );

        final failure = err(await attempt(keysWith(storage)));

        expect(failure, isA<StoreSecretFailure>());
        expect(storage.entries, isEmpty);
      }
    }, timeout: slow);

    test('a locked keystore writes nothing and burns no retry', () async {
      final storage = FakeSecureStoragePlatform(locked: true);
      final keys = keysWith(storage);

      expect(
        err(await keys.create(slot: GarageKeySlot.mainnet)),
        isA<KeystoreLockedFailure>(),
      );
      expect(
        err(await keys.import(slot: GarageKeySlot.mainnet, bytes: testBytes)),
        isA<KeystoreLockedFailure>(),
      );
      expect(
        err(await keys.read(slot: GarageKeySlot.mainnet)),
        isA<KeystoreLockedFailure>(),
      );
      expect(storage.reads, 3);
      expect(storage.entries, isEmpty);
    });

    test('a refused write is a failure, never a key', () async {
      final storage = FakeSecureStoragePlatform(
        scriptedWrites: [PlatformException(code: 'write failed')],
      );

      expect(
        err(await keysWith(storage).create(slot: GarageKeySlot.mainnet)),
        isA<StoreSecretFailure>(),
      );
      expect(storage.entries, isEmpty);
    }, timeout: slow);
  });

  group('importing a Garage Key', () {
    test('known bytes are stored and read back byte for byte', () async {
      final storage = FakeSecureStoragePlatform();
      final keys = keysWith(storage);

      final imported = ok(
        await keys.import(slot: GarageKeySlot.mainnet, bytes: testBytes),
      );

      expect(imported.bytes, testBytes);
      expect(stored(storage, mainnetKey)['bytes'], testHex);
      expect(ok(await keys.read(slot: GarageKeySlot.mainnet)).bytes, testBytes);
    }, timeout: slow);

    test('the caller buffer is copied before anything awaits', () async {
      final storage = FakeSecureStoragePlatform();
      final buffer = Uint8List.fromList(testBytes);

      final pending = keysWith(
        storage,
      ).import(slot: GarageKeySlot.mainnet, bytes: buffer);
      buffer.fillRange(0, buffer.length, 0);
      final imported = ok(await pending);

      expect(imported.bytes, testBytes);
      expect(stored(storage, mainnetKey)['bytes'], testHex);
      expect(() => imported.bytes[0] = 0, throwsUnsupportedError);
    }, timeout: slow);

    test(
      'any other length is a programmer error, before the keystore',
      () async {
        final storage = FakeSecureStoragePlatform();
        final keys = keysWith(storage);

        for (final length in [0, 16, 31, 33, 64]) {
          await expectLater(
            keys.import(slot: GarageKeySlot.mainnet, bytes: Uint8List(length)),
            throwsArgumentError,
          );
        }
        expect(storage.reads, 0);
        expect(storage.entries, isEmpty);
      },
    );
  });

  group('reading a Garage Key', () {
    test(
      'read never creates, and concludes absence after the full budget',
      () async {
        final storage = FakeSecureStoragePlatform();

        expect(
          err(await keysWith(storage).read(slot: GarageKeySlot.mainnet)),
          isA<SecretNotFoundFailure>(),
        );
        expect(storage.reads, 5);
        expect(storage.entries, isEmpty, reason: 'nothing was generated');
      },
      timeout: slow,
    );

    test('a single false miss does not hide a stored key', () async {
      final storage = FakeSecureStoragePlatform(
        entries: {mainnetKey: envelope()},
        scripted: [null],
      );

      expect(
        ok(await keysWith(storage).read(slot: GarageKeySlot.mainnet)).bytes,
        testBytes,
      );
    });

    final unusable = <String, String>{
      'an empty value': '',
      'a value that is not JSON': 'not json at all',
      'a JSON value that is not an envelope': '{"v":1,"kind":"garage"}',
      'a key of another kind': envelope(kind: 'dek'),
      'a key filed under another slot': envelope(name: testnetKey),
      'a truncated key': envelope(bytes: testHex.substring(0, 62)),
      'a key that is not hexadecimal': envelope(bytes: 'zz' * 32),
      'a newer envelope version': envelope(v: 2),
    };
    for (final MapEntry(key: label, value: entry) in unusable.entries) {
      test('$label is a corrupt Garage Key, refused and kept', () async {
        final storage = FakeSecureStoragePlatform(entries: {mainnetKey: entry});

        final failure = err(
          await keysWith(storage).read(slot: GarageKeySlot.mainnet),
        );

        expect(failure, isA<GarageKeyCorruptFailure>());
        expect(storage.entries, {mainnetKey: entry});
      }, timeout: slow);
    }

    test(
      'a read that keeps failing is a read failure, not an absence',
      () async {
        final storage = FakeSecureStoragePlatform(
          entries: {mainnetKey: envelope()},
          scripted: List.generate(5, (_) => PlatformException(code: 'boom')),
        );

        expect(
          err(await keysWith(storage).read(slot: GarageKeySlot.mainnet)),
          isA<FetchSecretFailure>(),
        );
      },
      timeout: slow,
    );
  });

  group('deleting a Garage Key', () {
    test(
      'delete empties the slot, and a new key can then be created',
      () async {
        final storage = FakeSecureStoragePlatform(
          entries: {mainnetKey: envelope()},
        );
        final keys = keysWith(storage);

        ok(await keys.delete(slot: GarageKeySlot.mainnet));
        expect(storage.entries, isEmpty);
        ok(await keys.delete(slot: GarageKeySlot.mainnet));

        final fresh = ok(await keys.create(slot: GarageKeySlot.mainnet));
        expect(fresh.bytes, isNot(testBytes));
      },
      timeout: slow,
    );

    test(
      'delete removes a corrupt entry: the way out of a corrupt key',
      () async {
        final storage = FakeSecureStoragePlatform(
          entries: {mainnetKey: 'not json at all'},
        );
        final keys = keysWith(storage);
        expect(
          err(await keys.read(slot: GarageKeySlot.mainnet)),
          isA<GarageKeyCorruptFailure>(),
        );

        ok(await keys.delete(slot: GarageKeySlot.mainnet));
        expect(storage.entries, isEmpty);

        ok(await keys.import(slot: GarageKeySlot.mainnet, bytes: testBytes));
        expect(
          ok(await keys.read(slot: GarageKeySlot.mainnet)).bytes,
          testBytes,
        );
      },
      timeout: slow,
    );

    test('a refused delete keeps the key and says so', () async {
      for (final (refusal, expected) in [
        (FakeSecureStoragePlatform.lockedError, isA<KeystoreLockedFailure>()),
        (PlatformException(code: 'delete failed'), isA<TrashSecretFailure>()),
      ]) {
        final storage = FakeSecureStoragePlatform(
          entries: {mainnetKey: envelope()},
          scriptedWrites: [refusal],
        );

        expect(
          err(await keysWith(storage).delete(slot: GarageKeySlot.mainnet)),
          expected,
        );
        expect(storage.entries, {mainnetKey: envelope()});
      }
    });

    test('delete touches only its own slot', () async {
      final storage = FakeSecureStoragePlatform(
        entries: {
          mainnetKey: envelope(),
          testnetKey: envelope(name: testnetKey),
        },
      );

      ok(await keysWith(storage).delete(slot: GarageKeySlot.testnet));

      expect(storage.entries, {mainnetKey: envelope()});
    });
  });

  group('isolation from the wallet seeds', () {
    test('no Garage Key operation reads a seed entry', () async {
      final storage = FakeSecureStoragePlatform(entries: {seedKey: seedEntry});
      final keys = keysWith(storage);

      Future<void> readsOnly(
        String slotKey,
        Future<Object?> Function() operation,
      ) async {
        storage.readKeys.clear();
        await operation();
        expect(storage.readKeys, isNotEmpty);
        expect(storage.readKeys.toSet(), {slotKey});
      }

      await readsOnly(
        mainnetKey,
        () => keys.create(slot: GarageKeySlot.mainnet),
      );
      await readsOnly(mainnetKey, () => keys.read(slot: GarageKeySlot.mainnet));
      await readsOnly(
        mainnetKey,
        () => keys.create(slot: GarageKeySlot.mainnet),
      );
      await readsOnly(
        testnetKey,
        () => keys.import(slot: GarageKeySlot.testnet, bytes: testBytes),
      );
      storage.entries[testnetKey] = 'not json at all';
      await readsOnly(testnetKey, () => keys.read(slot: GarageKeySlot.testnet));

      storage.readKeys.clear();
      ok(await keys.delete(slot: GarageKeySlot.testnet));
      ok(await keys.delete(slot: GarageKeySlot.mainnet));
      expect(storage.readKeys, isEmpty, reason: 'a delete reads nothing');
      expect(storage.entries, {seedKey: seedEntry});
    }, timeout: slow);

    test('listing the wallets ignores the Garage Keys', () async {
      // An unreadable Garage Key must not appear as an unreadable wallet.
      final storage = FakeSecureStoragePlatform(
        entries: {
          seedKey: seedEntry,
          mainnetKey: envelope(),
          testnetKey: 'not json at all',
        },
      )..install();

      final listing = ok(
        await Secrets(scratchDirectory: () async => '.').list(),
      );

      expect(storage.entries, hasLength(3), reason: 'listed past, not removed');
      expect(listing.single, isA<Secret>());
      expect(listing.single.id, Fingerprint('73c5da0a'));
    });

    test(
      'trashing a seed leaves the Garage Key, and deleting it leaves the seed',
      () async {
        final storage = FakeSecureStoragePlatform(
          entries: {seedKey: seedEntry, mainnetKey: envelope()},
        )..install();
        final secrets = Secrets(scratchDirectory: () async => '.');

        ok(await secrets.trash(Fingerprint('73c5da0a')));
        expect(storage.entries, {mainnetKey: envelope()});
        expect(
          ok(
            await secrets.garageKeys().read(slot: GarageKeySlot.mainnet),
          ).bytes,
          testBytes,
        );

        storage.entries[seedKey] = seedEntry;
        ok(await secrets.garageKeys().delete(slot: GarageKeySlot.mainnet));
        expect(storage.entries, {seedKey: seedEntry});
        expect(
          ok(await secrets.fetch(Fingerprint('73c5da0a'))).id,
          Fingerprint('73c5da0a'),
        );
      },
    );

    test('a Garage Key moved to a database key location is refused', () async {
      // Kinds do not mix: a database key handle never serves a Garage Key,
      // and does not replace it either.
      const moved = 'com.bullbitcoin.secrets/dek/p2p/mainnet';
      final value = envelope(name: moved);
      final storage = FakeSecureStoragePlatform(entries: {moved: value})
        ..install();
      final databaseKeys = Secrets(
        scratchDirectory: () async => '.',
      ).databaseKeys(module: 'p2p');

      expect(
        err(await databaseKeys.get(name: 'mainnet')),
        isA<DatabaseKeyCorruptFailure>(),
      );
      expect(
        err(await databaseKeys.getOrCreate(name: 'mainnet')),
        isA<DatabaseKeyCorruptFailure>(),
      );
      expect(storage.entries, {moved: value});
    });

    test('the Garage Keys live under a prefix the app store refuses', () {
      expect(Secrets.reservedKeyPrefixes.any(mainnetKey.startsWith), isTrue);
      expect(Secrets.reservedKeyPrefixes.any(testnetKey.startsWith), isTrue);
    });
  });

  group('redaction', () {
    test('the material never prints itself', () async {
      final storage = FakeSecureStoragePlatform(
        entries: {mainnetKey: envelope()},
      );
      final result = await keysWith(storage).read(slot: GarageKeySlot.mainnet);
      final material = ok(result);

      expect(material.toString(), 'GarageKeyMaterial(•••)');
      for (final printed in [
        '$material',
        '$result',
        '${[material]}',
      ]) {
        expect(printed, isNot(contains(testHex)));
        expect(printed, isNot(contains(testHex.toUpperCase())));
        expect(printed, isNot(contains(base64.encode(testBytes))));
        expect(printed, isNot(contains(testBytes.join(', '))));
      }
    });

    for (final field in ['v', 'kind', 'name', 'bytes', 'createdAt']) {
      test(
        'a sentinel stored in "$field" does not reach the failure',
        () async {
          const sentinel = 'SYNTHETIC_STORED_SENTINEL';
          final value = (jsonDecode(envelope()) as Map<String, dynamic>)
            ..[field] = sentinel;
          final storage = FakeSecureStoragePlatform(
            entries: {mainnetKey: jsonEncode(value)},
          );

          final failure = err(
            await keysWith(storage).read(slot: GarageKeySlot.mainnet),
          );

          expect(failure, isA<GarageKeyCorruptFailure>());
          expect(failure.logMessage, isNot(contains(sentinel)));
          expect(failure.toString(), isNot(contains(sentinel)));
        },
      );
    }
  });
}

/// A keystore whose writes take time, as a real one does: the in-memory store answers within microtasks, so a racing caller never reads between another caller's last read and its write.
class _SlowWrites extends FakeSecureStoragePlatform {
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return super.write(key: key, value: value, options: options);
  }
}
