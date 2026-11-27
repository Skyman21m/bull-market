import 'dart:io';

import 'package:bull_tor/tor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/p2p.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/recovery_note_sync.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/garage_recovery_note_repository.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/robot_key_compute_port.dart';
import 'package:p2p/src/domain/robot_request_limiter.dart';
import 'package:p2p/src/domain/usecases/acknowledge_garage_key_history_usecase.dart';
import 'package:p2p/src/domain/usecases/derive_first_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/has_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/new_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/list_robot_hosts_usecase.dart';
import 'package:p2p/src/domain/usecases/put_robot_on_coordinator_usecase.dart';
import 'package:p2p/src/domain/usecases/read_robot_on_coordinator_usecase.dart';
import 'package:p2p/src/domain/usecases/read_robot_standing_usecase.dart';
import 'package:p2p/src/domain/usecases/release_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/make_order_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/trade_make_locks.dart';
import 'package:p2p/src/domain/usecases/trade/trade_read_order.dart';
import 'package:p2p/src/presentation/robot_coordinator_cubit.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/testing.dart'
    show hasGarageKeysForTesting, hasP2pDatabaseForTesting;
import 'package:robosats/robosats.dart' show Federation;
import 'package:secrets/secrets.dart' show Secrets;
import 'package:secrets/testing.dart';

import 'support/trade_screens.dart';
import 'support/garage_words.dart';

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
    derivedGarageKeys: TestWordsPort(),
    databaseDirectory: databaseDirectory,
  );

  /// Whether each type of the Garage Key is registered in [locator].
  List<bool> garageKeyRegistrations() => [
    hasGarageKeysForTesting(locator),
    locator.isRegistered<GarageKeyRepository>(),
    locator.isRegistered<HasGarageKeyUsecase>(),
    locator.isRegistered<ImportGarageKeyUsecase>(),
    locator.isRegistered<DeriveFirstRobotUsecase>(),
    locator.isRegistered<NewGarageKeyUsecase>(),
    hasP2pDatabaseForTesting(locator),
    locator.isRegistered<P2pDatabase>(),
    locator.isRegistered<RobotBindingRepository>(),
    // A robot comes from a Garage Key only, so its request is registered with the Garage, over the bindings and the key work of its pair.
    locator.isRegistered<RobotKeyComputePort>(),
    locator.isRegistered<FetchRobotUsecase>(),
    // The local reads and records of a robot's standing, over the same database.
    locator.isRegistered<ReadRobotStandingUsecase>(),
    locator.isRegistered<AcknowledgeGarageKeyHistoryUsecase>(),
    // The robot requests, their places and their memory, over the same request of a robot.
    locator.isRegistered<RobotRequestLimiter>(),
    locator.isRegistered<PutRobotOnCoordinatorUsecase>(),
    locator.isRegistered<ReadRobotOnCoordinatorUsecase>(),
    locator.isRegistered<ReleaseRobotUsecase>(),
    // The robot panel of the Garage, and the coordinators it lists.
    locator.isRegistered<ListRobotHostsUsecase>(),
    locator.isRegistered<RobotCoordinatorCubit>(),
    // The recovery notes of the Garage Keys (#81): what this device read of them, and their reading and writing on the coordinators' relays of the app's transport (functional review of #302, R8: without them, no note is read nor written, and no other test would see it).
    locator.isRegistered<GarageRecoveryNoteRepository>(),
    locator.isRegistered<RecoveryNoteSync>(),
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

  test('the handle, the words and the directory go together, or it is a bug', () {
    expect(
      () => const P2pFeature().setup(
        locator,
        garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
        derivedGarageKeys: TestWordsPort(),
        databaseDirectory: null,
      ),
      throwsArgumentError,
    );
    // Without the words (#81), the Garage would have no key: a bug, never a key drawn instead.
    expect(
      () => const P2pFeature().setup(
        locator,
        garageKeys: Secrets(scratchDirectory: () async => '.').garageKeys(),
        databaseDirectory: databaseDirectory,
      ),
      throwsArgumentError,
    );
    expect(
      () => const P2pFeature().setup(
        locator,
        garageKeys: null,
        derivedGarageKeys: TestWordsPort(),
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
    'with both, the trade screen\'s cubit is given the run\'s memory of each trade (#152): the newest status stored, through `WatchTradeUsecase.lastStored`',
    () async {
      setUpWithGarage();
      final record = TradeScreenStatuses.record;
      final bond = await (await TradeScreenStatuses.make()).bondStep();
      final order = locator<TradeReadOrder>();
      final times = order.request();
      await order.send(times, DateTime.now(), () async {});
      expect(order.claim(record.robot, times), isNull);
      order.stored(record, bond);

      final cubit = locator<TradeCubit>(param1: record);
      addTearDown(cubit.close);
      expect(cubit.lastStoredNow, same(bond));
    },
  );

  test('with both, the database is one object, so one connection (#128)', () {
    setUpWithGarage();

    expect(
      identical(locator<P2pDatabase>(), locator<P2pDatabase>()),
      isTrue,
      reason: 'a second connection to p2p.sqlite needs its own review',
    );
  });

  test(
    'with both, setting up and resolving the use-cases touch no key and no file',
    () {
      setUpWithGarage();

      expect(garageKeyRegistrations(), everyElement(isTrue));
      locator
        ..get<HasGarageKeyUsecase>()
        ..get<ImportGarageKeyUsecase>()
        ..get<DeriveFirstRobotUsecase>()
        ..get<NewGarageKeyUsecase>()
        ..get<FetchRobotUsecase>()
        ..get<ReadRobotStandingUsecase>()
        ..get<AcknowledgeGarageKeyHistoryUsecase>()
        ..get<PutRobotOnCoordinatorUsecase>()
        ..get<ReadRobotOnCoordinatorUsecase>()
        ..get<ReleaseRobotUsecase>()
        ..get<ListRobotHostsUsecase>()
        // The make use case (#179): every one of its parameters registered, none of which touches a key or a file at its making.
        ..get<MakeOrderUsecase>();
      // One lock of the makes for the whole feature (#179).
      expect(locator<TradeMakeLocks>(), same(locator<TradeMakeLocks>()));
      // One limiter for the whole feature.
      expect(
        locator<RobotRequestLimiter>(),
        same(locator<RobotRequestLimiter>()),
      );
      expect(storage.reads, 0);
      expect(storage.entries, isEmpty);
      expect(directoryAsked, 0);
      expect(directory.listSync(), isEmpty);
    },
  );

  test(
    'the registered use-cases find a key of the words, use it, and activate the next one',
    () async {
      setUpWithGarage();
      const network = RobosatsNetwork.testnet;

      expect(
        await locator<HasGarageKeyUsecase>().execute(network),
        isA<Ok<bool, P2pFailure>>().having((ok) => ok.value, 'value', isTrue),
      );
      // Key 0, activated at the first reading and recorded as drawn here, so its robot 0 can be bound, in `p2p.sqlite` of the directory given.
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
        await locator<NewGarageKeyUsecase>().execute(network, after: 0),
        isOk(1),
      );
      // Nothing of a key in the vault: the words give the keys back.
      expect(
        storage.entries.keys.where((entry) => entry.contains('garage')),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // Restored from `main` (review of #292): the rule still holds for an external Garage Key imported on the other network.
  test(
    'a key of testnet imported into mainnet: its robots have one credential, so one binding, on both networks',
    () async {
      setUpWithGarage();
      const testnet = RobosatsNetwork.testnet;
      const mainnet = RobosatsNetwork.mainnet;
      T value<T>(Result<T, P2pFailure> result) => switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      CoordinatorIdentity identityOf(String alias, RobosatsNetwork network) =>
          CoordinatorIdentity.of(
            Federation.robosats.byAlias(alias) ?? fail('no $alias'),
            network,
          ) ??
          fail('$alias is not on $network');

      final keys = locator<GarageKeyRepository>();
      // Internal key 0 of testnet, recorded as drawn here there; its text, of the public test words, imported into the mainnet slot.
      final testnetKey = value(await keys.read(testnet));
      expect(value(await keys.keyring(mainnet)).highest, 0);
      expect(
        await locator<ImportGarageKeyUsecase>().execute(
          mainnet,
          text: testnetKey.key.revealBech32(),
        ),
        isA<Ok<void, P2pFailure>>(),
      );
      final mainnetKey = value(await keys.read(mainnet));
      expect(mainnetKey.index, isNull);
      expect(value(mainnetKey.fingerprint), value(testnetKey.fingerprint));

      final bindings = locator<RobotBindingRepository>();
      final testnet0 = value(testnetKey.firstUsableRobot(0));
      final mainnet0 = value(mainnetKey.firstUsableRobot(0));
      expect(
        mainnet0.identity.tokenSha256Base91,
        testnet0.identity.tokenSha256Base91,
      );
      expect(
        await bindings.bind(testnet0.slot, identityOf('temple', testnet)),
        isA<Ok<void, P2pFailure>>(),
      );
      // Robot 0's token hash went to temple on testnet: no mainnet coordinator gets it.
      expect(
        await bindings.bind(mainnet0.slot, identityOf('lake', mainnet)),
        isA<Err<void, P2pFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<RobotBoundToAnotherCoordinatorFailure>(),
        ),
      );
      // On mainnet the key was imported: a robot without a binding there may live anywhere, so « Select Host » asks first.
      expect(
        await bindings.bind(
          value(mainnetKey.firstUsableRobot(1)).slot,
          identityOf('lake', mainnet),
        ),
        isA<Err<void, P2pFailure>>().having(
          (err) => err.failure,
          'failure',
          isA<RobotHistoryUnknownFailure>(),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
