import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart' as convert;
import 'package:flutter_test/flutter_test.dart';
import 'package:primitives/primitives.dart';
import 'package:recoverbull/recoverbull.dart';
import 'package:secrets/secrets.dart';

import 'fake_secure_storage_platform.dart';
import 'result_helpers.dart';

/// The wallet backup never carries the Garage Key (decision of the owner, option A).
///
/// The encrypted vault is opened here, inside the package's own tests, and its whole plaintext is checked: exactly the words and the caller's metadata, and no form of the Garage Key stored next to the seed. Restoring that vault on an empty device brings the wallet back and no Garage Key.
void main() {
  // The example key of the RoboSats frontend tests, recorded with its bytes
  // in `packages/robosats/test/fixtures/robot-identity-vectors.json` and
  // checked there against the reference implementation. Public test data.
  const exampleHex =
      '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d';
  const exampleBech32 =
      'robo180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsg9czpj';
  final exampleBytes = Uint8List.fromList(convert.hex.decode(exampleHex));

  // The published BIP39 test mnemonic, under its known fingerprint.
  const fingerprint = '73c5da0a';
  final seedEntry = jsonEncode({
    'mnemonicWords': [...List.filled(11, 'abandon'), 'about'],
    'passphrase': null,
    'runtimeType': 'mnemonic',
  });

  // The metadata `CreateEncryptedVaultUsecase` passes, with its keys and types.
  const metadata = <String, dynamic>{
    'masterFingerprint': fingerprint,
    'isEncryptedVaultTested': false,
    'isPhysicalBackupTested': true,
    'latestEncryptedBackup': null,
    'latestPhysicalBackup': '2026-11-01T00:00:00.000',
  };

  /// Every spelling of the key a careless encoder could produce.
  final forms = <String, String>{
    'hex': exampleHex,
    'upper-case hex': exampleHex.toUpperCase(),
    'base64': base64.encode(exampleBytes),
    'unpadded base64': base64.encode(exampleBytes).replaceAll('=', ''),
    'base64url': base64Url.encode(exampleBytes),
    'robo1 form': exampleBech32,
    'upper-case robo1 form': exampleBech32.toUpperCase(),
    'byte list': jsonEncode(exampleBytes),
  };

  test(
    'the vault holds the words and the metadata, and no Garage Key',
    () async {
      final storage = FakeSecureStoragePlatform(
        entries: {'seed_$fingerprint': seedEntry},
      )..install();
      final secrets = Secrets(scratchDirectory: () async => '.');
      ok(
        await secrets.garageKeys().import(
          slot: GarageKeySlot.mainnet,
          bytes: exampleBytes,
        ),
      );
      expect(
        storage.entries.keys,
        unorderedEquals([
          'seed_$fingerprint',
          'com.bullbitcoin.secrets/garage/p2p/mainnet',
        ]),
      );

      final secret = ok(await secrets.fetch(Fingerprint(fingerprint)));
      final backup = ok(await secret.backup.recoverbull(metadata: metadata));

      // Opened with the library, as the recovery side does, but without the
      // package's own `open`, which takes the words out of the plaintext.
      final plaintext = utf8.decode(
        RecoverBull.restoreBackup(
          backup: BullBackup.fromJson(backup.vault.json),
          backupKey: convert.hex.decode(backup.key.hex),
        ),
      );
      final opened = jsonDecode(plaintext) as Map<String, dynamic>;

      expect(opened.keys.toSet(), {'mnemonic', ...metadata.keys});
      expect(opened['mnemonic'], [...List.filled(11, 'abandon'), 'about']);
      for (final MapEntry(key: name, value: value) in metadata.entries) {
        expect(opened[name], value, reason: name);
      }
      for (final MapEntry(key: label, value: form) in forms.entries) {
        expect(plaintext, isNot(contains(form)), reason: label);
        expect(backup.vault.json, isNot(contains(form)), reason: label);
        expect(backup.key.hex, isNot(contains(form)), reason: label);
      }
      expect(plaintext, isNot(contains('garage')));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'restoring the vault on an empty device brings no Garage Key back',
    () async {
      final source = FakeSecureStoragePlatform(
        entries: {'seed_$fingerprint': seedEntry},
      )..install();
      final secrets = Secrets(scratchDirectory: () async => '.');
      ok(
        await secrets.garageKeys().import(
          slot: GarageKeySlot.testnet,
          bytes: exampleBytes,
        ),
      );
      final secret = ok(await secrets.fetch(Fingerprint(fingerprint)));
      final backup = ok(await secret.backup.recoverbull(metadata: metadata));
      expect(source.entries, hasLength(2));

      final target = FakeSecureStoragePlatform()..install();
      final restored = ok(
        await Secrets(
          scratchDirectory: () async => '.',
        ).recoverbull.restore(vault: backup.vault, key: backup.key),
      );

      expect(restored.secret.id, Fingerprint(fingerprint));
      expect(restored.metadata, metadata);
      expect(target.entries.keys, ['seed_$fingerprint']);
      expect(
        target.entries.keys.where((key) => key.contains('/garage/')),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
