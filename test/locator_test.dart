import 'package:bb_mobile/locator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart' show P2pFacade;
import 'package:p2p/testing.dart' show hasGarageKeysForTesting;
import 'package:secrets/secrets.dart';
import 'package:secrets/testing.dart';

/// Where the shell hands the P2P feature the vault's Garage Key handle, which creates and imports keys under a write lock that is per isolate.
///
/// `AppLocator.setup` itself cannot run here; `test/core_test/background_tasks/background_tasks_keystore_test.dart` checks what each composition passes to it.
void main() {
  late GetIt locator;
  late FakeSecureStoragePlatform storage;

  setUp(() {
    storage = FakeSecureStoragePlatform()..install();
    locator = GetIt.asNewInstance();
  });

  tearDown(() => locator.reset());

  test('with the Garage Keys, P2P gets the handle, and no key is touched', () {
    locator.registerSingleton<Secrets>(
      Secrets(scratchDirectory: () async => '.'),
    );

    AppLocator.setupP2p(locator, withGarageKeys: true);

    expect(hasGarageKeysForTesting(locator), isTrue);
    expect(storage.reads, 0);
    expect(storage.entries, isEmpty);
  });

  test('without them, P2P is set up with no Garage Key ability', () {
    // No `Secrets` is registered: asking it for the handle would throw.
    AppLocator.setupP2p(locator, withGarageKeys: false);

    expect(hasGarageKeysForTesting(locator), isFalse);
    expect(locator.isRegistered<P2pFacade>(), isTrue);
    expect(storage.reads, 0);
  });
}
