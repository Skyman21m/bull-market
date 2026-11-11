import 'package:bb_mobile/locator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart' show P2pFacade;
import 'package:p2p/testing.dart' show hasGarageKeysForTesting;
import 'package:secrets/secrets.dart';
import 'package:secrets/testing.dart';

/// Where the shell hands the P2P feature the vault's Garage Key handle, which creates and imports keys under a write lock that is per isolate.
///
/// `Secrets` is registered whatever the flag, as it always is in the app, so that the flag alone decides.
/// `AppLocator.setup` itself cannot run here; `test/core_test/background_tasks/background_tasks_keystore_test.dart` checks what each composition passes to it.
void main() {
  late GetIt locator;
  late FakeSecureStoragePlatform storage;

  setUp(() {
    storage = FakeSecureStoragePlatform()..install();
    locator = GetIt.asNewInstance()
      ..registerSingleton<Secrets>(Secrets(scratchDirectory: () async => '.'));
  });

  tearDown(() => locator.reset());

  for (final withGarageKeys in [true, false]) {
    test(
      'withGarageKeys: $withGarageKeys alone decides whether P2P gets the handle, and no key is touched',
      () {
        AppLocator.setupP2p(locator, withGarageKeys: withGarageKeys);

        expect(hasGarageKeysForTesting(locator), withGarageKeys);
        expect(locator.isRegistered<P2pFacade>(), isTrue);
        expect(storage.reads, 0);
        expect(storage.entries, isEmpty);
      },
    );
  }
}
