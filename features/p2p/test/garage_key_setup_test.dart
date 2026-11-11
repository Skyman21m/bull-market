import 'package:bull_tor/tor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/usecases/delete_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/derive_first_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/generate_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/has_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:p2p/testing.dart' show hasGarageKeysForTesting;
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

/// What `P2pFeature.setup` registers with and without the vault's Garage Key handle, and the use-cases it registers, run over the real vault on its in-memory keystore.
void main() {
  late GetIt locator;
  late FakeSecureStoragePlatform storage;

  setUp(() {
    storage = FakeSecureStoragePlatform()..install();
    locator = GetIt.asNewInstance()
      // Read lazily by the transport: no test here reaches a coordinator.
      ..registerSingleton<TorHttpClientFactory>(const TorHttpClientFactory());
  });

  tearDown(() => locator.reset());

  /// Whether each type of the Garage Key is registered in [locator].
  List<bool> garageKeyRegistrations() => [
    hasGarageKeysForTesting(locator),
    locator.isRegistered<GarageKeyRepository>(),
    locator.isRegistered<HasGarageKeyUsecase>(),
    locator.isRegistered<GenerateGarageKeyUsecase>(),
    locator.isRegistered<ImportGarageKeyUsecase>(),
    locator.isRegistered<DeriveFirstRobotUsecase>(),
    locator.isRegistered<DeleteGarageKeyUsecase>(),
  ];

  test('without the handle, nothing of a Garage Key is registered', () {
    const P2pFeature().setup(locator, garageKeys: null);

    expect(garageKeyRegistrations(), everyElement(isFalse));
    expect(locator.isRegistered<P2pFacade>(), isTrue);
    expect(storage.reads, 0);
  });

  test(
    'with the handle, setting up and resolving the use-cases touch no key',
    () {
      const P2pFeature().setup(
        locator,
        garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      );

      expect(garageKeyRegistrations(), everyElement(isTrue));
      locator
        ..get<HasGarageKeyUsecase>()
        ..get<GenerateGarageKeyUsecase>()
        ..get<ImportGarageKeyUsecase>()
        ..get<DeriveFirstRobotUsecase>()
        ..get<DeleteGarageKeyUsecase>();
      expect(storage.reads, 0);
      expect(storage.entries, isEmpty);
    },
  );

  test(
    'the registered use-cases generate, find, use and delete a key',
    () async {
      const P2pFeature().setup(
        locator,
        garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
      );
      const network = RobosatsNetwork.testnet;

      expect(
        await locator<HasGarageKeyUsecase>().execute(network),
        isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'value', isFalse),
      );
      expect(
        await locator<GenerateGarageKeyUsecase>().execute(network),
        isA<Ok<void, P2pFailure>>(),
      );
      expect(
        await locator<HasGarageKeyUsecase>().execute(network),
        isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'value', isTrue),
      );
      expect(
        await locator<DeriveFirstRobotUsecase>().execute(network),
        isA<Ok<Object, P2pFailure>>(),
      );
      expect(
        await locator<GenerateGarageKeyUsecase>().execute(network),
        isA<Err<void, P2pFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<GarageKeyAlreadyStoredFailure>(),
        ),
      );
      expect(storage.entries, hasLength(1));
      expect(
        await locator<DeleteGarageKeyUsecase>().execute(network),
        isA<Ok<void, P2pFailure>>(),
      );
      expect(storage.entries, isEmpty);
      expect(
        await locator<HasGarageKeyUsecase>().execute(network),
        isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'value', isFalse),
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
