import 'package:flutter_test/flutter_test.dart';
import 'package:secrets/secrets.dart';

import 'fake_secure_storage_platform.dart';
import 'result_helpers.dart';

/// What the module-key write path stores, byte for byte.
///
/// Database keys and Garage Keys share the envelope and the datasource that writes it. A change to that path must leave a database key's stored value exactly as it was: same fields, same order, same values.
void main() {
  test(
    'a new database key is stored in exactly this envelope',
    () async {
      const storageKey = 'com.bullbitcoin.secrets/dek/swaps/main';
      final storage = FakeSecureStoragePlatform()..install();

      final before = DateTime.now().toUtc();
      final key = ok(
        await Secrets(
          scratchDirectory: () async => '.',
        ).databaseKeys(module: 'swaps').getOrCreate(name: 'main'),
      );
      final after = DateTime.now().toUtc();

      expect(storage.entries.keys, [storageKey]);
      final stored = storage.entries[storageKey] ?? fail('nothing stored');
      // The creation time is the clock's: checked here, then pinned with the rest.
      final createdAt =
          RegExp(r'"createdAt":"([^"]*)"}$').firstMatch(stored)?.group(1) ??
          fail('no createdAt at the end of the envelope');
      final time = DateTime.parse(createdAt);
      expect(time.isUtc, isTrue);
      expect(time.toIso8601String(), createdAt);
      expect(time.isBefore(before), isFalse);
      expect(time.isAfter(after), isFalse);

      expect(
        stored,
        '{"v":1,"kind":"dek","name":"$storageKey",'
        '"bytes":"${key.hex}","createdAt":"$createdAt"}',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
