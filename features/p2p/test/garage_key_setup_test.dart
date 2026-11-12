import 'dart:io';

import 'package:bull_tor/tor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/usecases/delete_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/derive_first_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/generate_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/has_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:p2p/testing.dart'
    show hasGarageKeysForTesting, hasP2pDatabaseForTesting;
import 'package:robosats/robosats.dart' show Federation;
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

/// What `P2pFeature.setup` registers with and without the vault's Garage Key handle and the directory of the feature's database, and the use-cases it registers, run over the real vault on its in-memory keystore and a real database in a temporary directory.
void main() {
  late GetIt locator;
  late FakeSecureStoragePlatform storage;
  late Directory directory;
  late int directoryAsked;

  setUp(() async {
    storage = FakeSecureStoragePlatform()..install();
    locator = GetIt.asNewInstance()
      // Read lazily by the transport: no test here reaches a coordinator.
      ..registerSingleton<TorHttpClientFactory>(const TorHttpClientFactory());
    directory = await Directory.systemTemp.createTemp('p2p-setup-');
    directoryAsked = 0;
  });

  tearDown(() async {
    // Closes the database, if a test opened it.
    await locator.reset();
    await directory.delete(recursive: true);
  });

  Future<Directory> databaseDirectory() async {
    directoryAsked++;
    return directory;
  }

  void setUpWithGarage() => const P2pFeature().setup(
    locator,
    garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
    databaseDirectory: databaseDirectory,
  );

  /// Whether each type of the Garage Key is registered in [locator].
  List<bool> garageKeyRegistrations() => [
    hasGarageKeysForTesting(locator),
    locator.isRegistered<GarageKeyRepository>(),
    locator.isRegistered<HasGarageKeyUsecase>(),
    locator.isRegistered<GenerateGarageKeyUsecase>(),
    locator.isRegistered<ImportGarageKeyUsecase>(),
    locator.isRegistered<DeriveFirstRobotUsecase>(),
    locator.isRegistered<DeleteGarageKeyUsecase>(),
    hasP2pDatabaseForTesting(locator),
    locator.isRegistered<P2pDatabase>(),
    locator.isRegistered<RobotBindingRepository>(),
    // A robot comes from a Garage Key only, so its request is registered with the Garage, over the bindings.
    locator.isRegistered<FetchRobotUsecase>(),
  ];

  test(
    'without the handle and the directory, nothing of a Garage Key, a binding or the database is registered',
    () {
      const P2pFeature().setup(
        locator,
        garageKeys: null,
        databaseDirectory: null,
      );

      expect(garageKeyRegistrations(), everyElement(isFalse));
      expect(locator.isRegistered<P2pFacade>(), isTrue);
      expect(storage.reads, 0);
      expect(directoryAsked, 0);
    },
  );

  test('the handle without the directory, or the reverse, is a bug', () {
    expect(
      () => const P2pFeature().setup(
        locator,
        garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
        databaseDirectory: null,
      ),
      throwsArgumentError,
    );
    expect(
      () => const P2pFeature().setup(
        locator,
        garageKeys: null,
        databaseDirectory: databaseDirectory,
      ),
      throwsArgumentError,
    );
    expect(locator.isRegistered<P2pFacade>(), isFalse);
    expect(directoryAsked, 0);
  });

  test(
    'with both, setting up and resolving the use-cases touch no key and no file',
    () {
      setUpWithGarage();

      expect(garageKeyRegistrations(), everyElement(isTrue));
      locator
        ..get<HasGarageKeyUsecase>()
        ..get<GenerateGarageKeyUsecase>()
        ..get<ImportGarageKeyUsecase>()
        ..get<DeriveFirstRobotUsecase>()
        ..get<DeleteGarageKeyUsecase>()
        ..get<FetchRobotUsecase>();
      expect(storage.reads, 0);
      expect(storage.entries, isEmpty);
      expect(directoryAsked, 0);
      expect(directory.listSync(), isEmpty);
    },
  );

  test(
    'the registered use-cases generate, find, use and delete a key',
    () async {
      setUpWithGarage();
      const network = RobosatsNetwork.testnet;

      expect(
        await locator<HasGarageKeyUsecase>().execute(network),
        isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'value', isFalse),
      );
      expect(
        await locator<GenerateGarageKeyUsecase>().execute(network),
        isA<Ok<GarageKeyHistory, P2pFailure>>().having(
          (ok) => ok.value,
          'history',
          GarageKeyHistory.drawnHere,
        ),
      );
      expect(
        await locator<HasGarageKeyUsecase>().execute(network),
        isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'value', isTrue),
      );
      // Drawn here, so its robot 0 can be bound, in `p2p.sqlite` of the directory given.
      final robot = switch (await locator<DeriveFirstRobotUsecase>().execute(
        network,
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('no robot: $failure'),
      };
      final temple =
          CoordinatorIdentity.of(
            Federation.robosats.byAlias('temple') ?? fail('no temple'),
            network,
          ) ??
          fail('temple is not on testnet');
      expect(
        await locator<RobotBindingRepository>().bind(robot.slot, temple),
        isA<Ok<void, P2pFailure>>(),
      );
      expect(directoryAsked, 1);
      expect(File('${directory.path}/p2p.sqlite').existsSync(), isTrue);
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
      // The binding outlives the key: if the key comes back, its robot 0 is still bound to temple.
      expect(
        await locator<RobotBindingRepository>().bind(robot.slot, temple),
        isA<Ok<void, P2pFailure>>(),
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
