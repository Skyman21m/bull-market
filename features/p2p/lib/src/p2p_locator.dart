import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;

import 'package:bull_tor/tor.dart';
import 'package:get_it/get_it.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeys;

import 'data/garage_key_repository_impl.dart';
import 'data/isolate_robot_key_compute.dart';
import 'data/p2p_database.dart';
import 'data/robot_binding_repository_impl.dart';
import 'data/tor_coordinator_transport.dart';
import 'domain/coordinator_sessions_port.dart';
import 'domain/p2p_clock.dart';
import 'domain/p2p_shuffle.dart';
import 'domain/p2p_waits.dart';
import 'domain/repositories/garage_key_repository.dart';
import 'domain/repositories/robot_binding_repository.dart';
import 'domain/robot_key_compute_port.dart';
import 'domain/usecases/acknowledge_garage_key_history_usecase.dart';
import 'domain/usecases/close_coordinator_sessions_usecase.dart';
import 'domain/usecases/close_robot_sessions_usecase.dart';
import 'domain/usecases/delete_garage_key_usecase.dart';
import 'domain/usecases/derive_first_robot_usecase.dart';
import 'domain/usecases/fetch_coordinator_info_usecase.dart';
import 'domain/usecases/fetch_robot_usecase.dart';
import 'domain/usecases/generate_garage_key_usecase.dart';
import 'domain/usecases/has_garage_key_usecase.dart';
import 'domain/usecases/import_garage_key_usecase.dart';
import 'domain/usecases/load_federation_books_usecase.dart';
import 'domain/usecases/needs_pin_to_delete_garage_key_usecase.dart';
import 'domain/usecases/read_garage_key_usecase.dart';
import 'domain/usecases/read_robot_standing_usecase.dart';
import 'domain/usecases/request_federation_books_usecase.dart';
import 'domain/usecases/retry_p2p_tor_usecase.dart';
import 'domain/usecases/start_p2p_tor_usecase.dart';
import 'domain/usecases/watch_p2p_tor_state_usecase.dart';
import 'presentation/book_cubit.dart';
import 'presentation/coordinator_details_cubit.dart';
import 'presentation/garage_cubit.dart';
import 'presentation/order_details_cubit.dart';
import 'ui/widgets/garage_key_clipboard.dart';

/// Registers the internals of the feature: one Tor transport, shared by every request to the coordinators, the use-cases and the cubits of the screens.
final class P2pLocator {
  /// [garageKeys] is the vault's handle on the Garage Keys and [databaseDirectory] gives the directory of the feature's database: without them, nothing that reads or writes a Garage Key, a binding or the database is registered.
  static void setup(
    GetIt locator, {
    required GarageKeys? garageKeys,
    required Future<Directory> Function()? databaseDirectory,
  }) {
    // `Tor` and its HTTP client factory are read lazily, so this runs whether or not the Tor package is registered yet.
    locator.registerLazySingleton<TorCoordinatorTransport>(
      () => TorCoordinatorTransport(
        () => locator<Tor>(),
        locator<TorHttpClientFactory>(),
      ),
      dispose: (transport) => transport.closeSessions(),
    );
    registerOver(
      locator,
      transport: () => locator<TorCoordinatorTransport>(),
      sessions: () => locator<TorCoordinatorTransport>(),
      tor: () => locator<Tor>(),
      clock: DateTime.now,
      // The book's waits before it asks a coordinator again: real timers, spread by a random draw that nothing secret depends on.
      waits: P2pWaits(start: Timer.new, random: Random().nextDouble),
    );
    if (garageKeys != null && databaseDirectory != null) {
      registerGarageKeys(
        locator,
        garageKeys,
        database: () => P2pDatabase.open(databaseDirectory),
        transport: () => locator<TorCoordinatorTransport>(),
        clock: DateTime.now,
      );
    }
  }

  /// Registers the Garage Key of each network, kept by the vault behind [garageKeys], the use-cases that create, import, read and delete it, the Garage that shows it, and the bindings of its robots in the database [database] makes, with the request of a robot that checks them over [transport].
  ///
  /// Registering touches no key and no file: the keystore and the database are read or written only when a use-case runs, and the Garage runs them only once the user opens it.
  static void registerGarageKeys(
    GetIt locator,
    GarageKeys garageKeys, {
    required P2pDatabase Function() database,
    required CoordinatorTransport Function() transport,
    required DateTime Function() clock,
  }) {
    locator.registerLazySingleton<GarageKeyRepository>(
      () => GarageKeyRepositoryImpl(garageKeys),
    );
    locator.registerLazySingleton<P2pDatabase>(
      database,
      dispose: (database) => database.close(),
    );
    locator.registerLazySingleton<RobotBindingRepository>(
      () => RobotBindingRepositoryImpl(locator(), clock: clock),
    );
    // The hashing of a robot's key pair, away from the UI isolate.
    locator.registerLazySingleton<RobotKeyComputePort>(
      () => const IsolateRobotKeyCompute(),
    );
    // The request of a robot: its only caller will be the Garage of this feature, and nothing outside the feature reaches it.
    locator.registerFactory<FetchRobotUsecase>(
      () => FetchRobotUsecase(
        CoordinatorClient(transport(), clock: clock),
        locator(),
        locator(),
      ),
    );
    locator.registerFactory<HasGarageKeyUsecase>(
      () => HasGarageKeyUsecase(locator()),
    );
    locator.registerFactory<GenerateGarageKeyUsecase>(
      () => GenerateGarageKeyUsecase(locator(), locator()),
    );
    locator.registerFactory<ImportGarageKeyUsecase>(
      () => ImportGarageKeyUsecase(locator(), locator()),
    );
    locator.registerFactory<ReadGarageKeyUsecase>(
      () => ReadGarageKeyUsecase(locator()),
    );
    locator.registerFactory<DeriveFirstRobotUsecase>(
      () => DeriveFirstRobotUsecase(locator()),
    );
    locator.registerFactory<DeleteGarageKeyUsecase>(
      () => DeleteGarageKeyUsecase(locator()),
    );
    locator.registerFactory<NeedsPinToDeleteGarageKeyUsecase>(
      () => NeedsPinToDeleteGarageKeyUsecase(locator()),
    );
    // The local reads and records of the Garage's robot panel: nothing outside the feature reaches them.
    locator.registerFactory<ReadRobotStandingUsecase>(
      () => ReadRobotStandingUsecase(locator()),
    );
    locator.registerFactory<AcknowledgeGarageKeyHistoryUsecase>(
      () => AcknowledgeGarageKeyHistoryUsecase(locator()),
    );
    // The Garage of a network, created when the user opens it.
    // The keys drawn and not acknowledged yet, in memory, for the whole run of the app.
    locator.registerLazySingleton<UnacknowledgedGarageKeys>(
      UnacknowledgedGarageKeys.new,
    );
    locator.registerFactoryParam<GarageCubit, RobosatsNetwork, void>(
      (network, _) => GarageCubit(
        network,
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
      ),
    );
    // One for the feature, so that a copied key is cleared even after the screen that copied it is gone.
    locator.registerLazySingleton<GarageKeyClipboard>(
      GarageKeyClipboard.new,
      dispose: (clipboard) => clipboard.dispose(),
    );
  }

  /// Registers the use-cases and the cubits over [transport], [tor], [clock], [waits] and [shuffle], which tests replace.
  static void registerOver(
    GetIt locator, {
    required CoordinatorTransport Function() transport,
    required CoordinatorSessionsPort Function() sessions,
    required Tor Function() tor,
    required DateTime Function() clock,
    required P2pWaits waits,
    P2pShuffle shuffle = P2pShuffle.random,
  }) {
    locator.registerSingleton<P2pClock>(P2pClock(clock));
    locator.registerSingleton<P2pShuffle>(shuffle);
    locator.registerSingleton<P2pWaits>(waits);
    locator.registerFactory<RequestFederationBooksUsecase>(
      () => RequestFederationBooksUsecase(
        FederationBookReader(transport(), clock: clock),
        Federation.robosats,
      ),
    );
    // A factory: each book gets its own, which remembers the coordinators it reached and its requests in flight.
    locator.registerFactory<LoadFederationBooksUsecase>(
      () => LoadFederationBooksUsecase(locator(), locator()),
    );
    locator.registerFactory<FetchCoordinatorInfoUsecase>(
      () => FetchCoordinatorInfoUsecase(
        CoordinatorClient(transport(), clock: clock),
      ),
    );
    // It has no caller yet: the Garage cubits of this feature will be the first, and nothing outside the feature reaches it.
    locator.registerFactory<CloseRobotSessionsUsecase>(
      () => CloseRobotSessionsUsecase(sessions()),
    );
    locator.registerFactory<WatchP2pTorStateUsecase>(
      () => WatchP2pTorStateUsecase(tor),
    );
    locator.registerFactory<StartP2pTorUsecase>(() => StartP2pTorUsecase(tor));
    locator.registerFactory<RetryP2pTorUsecase>(() => RetryP2pTorUsecase(tor));
    locator.registerFactory<CloseCoordinatorSessionsUsecase>(
      () => CloseCoordinatorSessionsUsecase(sessions()),
    );
    locator.registerFactoryParam<BookCubit, RobosatsNetwork, void>(
      (network, _) =>
          BookCubit(network, locator(), locator(), locator(), locator()),
    );
    locator
        .registerFactoryParam<OrderDetailsCubit, PublicOrder, RobosatsNetwork>(
          (order, network) => OrderDetailsCubit(order, network, locator()),
        );
    locator.registerFactoryParam<
      CoordinatorDetailsCubit,
      CoordinatorDetailsRequest,
      void
    >(
      (request, _) => CoordinatorDetailsCubit(request, locator(), now: clock()),
    );
  }
}
