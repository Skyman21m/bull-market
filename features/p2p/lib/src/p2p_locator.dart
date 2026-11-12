import 'package:bull_tor/tor.dart';
import 'package:get_it/get_it.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeys;

import 'data/garage_key_repository_impl.dart';
import 'data/tor_coordinator_transport.dart';
import 'domain/coordinator_sessions_port.dart';
import 'domain/p2p_clock.dart';
import 'domain/repositories/garage_key_repository.dart';
import 'domain/usecases/close_coordinator_sessions_usecase.dart';
import 'domain/usecases/close_robot_sessions_usecase.dart';
import 'domain/usecases/delete_garage_key_usecase.dart';
import 'domain/usecases/derive_first_robot_usecase.dart';
import 'domain/usecases/fetch_coordinator_info_usecase.dart';
import 'domain/usecases/fetch_robot_usecase.dart';
import 'domain/usecases/generate_garage_key_usecase.dart';
import 'domain/usecases/has_garage_key_usecase.dart';
import 'domain/usecases/import_garage_key_usecase.dart';
import 'domain/usecases/read_garage_key_usecase.dart';
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
  /// [garageKeys] is the vault's handle on the Garage Keys: without it, nothing that reads or writes a Garage Key is registered.
  static void setup(GetIt locator, {required GarageKeys? garageKeys}) {
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
    );
    if (garageKeys != null) registerGarageKeys(locator, garageKeys);
  }

  /// Registers the Garage Key of each network, kept by the vault behind [garageKeys], the use-cases that create, import, read and delete it, and the Garage that shows it.
  ///
  /// Registering touches no key: the keystore is read or written only when a use-case runs, and the Garage runs them only once the user opens it.
  static void registerGarageKeys(GetIt locator, GarageKeys garageKeys) {
    locator.registerLazySingleton<GarageKeyRepository>(
      () => GarageKeyRepositoryImpl(garageKeys),
    );
    locator.registerFactory<HasGarageKeyUsecase>(
      () => HasGarageKeyUsecase(locator()),
    );
    locator.registerFactory<GenerateGarageKeyUsecase>(
      () => GenerateGarageKeyUsecase(locator()),
    );
    locator.registerFactory<ImportGarageKeyUsecase>(
      () => ImportGarageKeyUsecase(locator()),
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
      ),
    );
    // One for the feature, so that a copied key is cleared even after the screen that copied it is gone.
    locator.registerLazySingleton<GarageKeyClipboard>(
      GarageKeyClipboard.new,
      dispose: (clipboard) => clipboard.dispose(),
    );
  }

  /// Registers the use-cases and the cubits over [transport], [tor] and [clock], which tests replace.
  static void registerOver(
    GetIt locator, {
    required CoordinatorTransport Function() transport,
    required CoordinatorSessionsPort Function() sessions,
    required Tor Function() tor,
    required DateTime Function() clock,
  }) {
    locator.registerSingleton<P2pClock>(P2pClock(clock));
    locator.registerFactory<RequestFederationBooksUsecase>(
      () => RequestFederationBooksUsecase(
        FederationBookReader(transport(), clock: clock),
        Federation.robosats,
      ),
    );
    locator.registerFactory<FetchCoordinatorInfoUsecase>(
      () => FetchCoordinatorInfoUsecase(
        CoordinatorClient(transport(), clock: clock),
      ),
    );
    // The robot use-cases have no caller yet: the Garage cubits of this feature will be the first, and nothing outside the feature reaches them.
    locator.registerFactory<FetchRobotUsecase>(
      () => FetchRobotUsecase(CoordinatorClient(transport(), clock: clock)),
    );
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
