import 'package:bull_tor/tor.dart';
import 'package:get_it/get_it.dart';
import 'package:robosats/robosats.dart';

import 'data/tor_coordinator_transport.dart';
import 'domain/usecases/close_coordinator_sessions_usecase.dart';
import 'domain/usecases/fetch_coordinator_info_usecase.dart';
import 'domain/usecases/request_federation_books_usecase.dart';
import 'domain/usecases/watch_p2p_tor_state_usecase.dart';

/// Registers the internals of the feature: one Tor transport, shared by every request to the coordinators, and the use-cases.
final class P2pLocator {
  static void setup(GetIt locator) {
    // `Tor` and its HTTP client factory are read lazily, so this runs whether or not the Tor package is registered yet.
    locator.registerLazySingleton<TorCoordinatorTransport>(
      () => TorCoordinatorTransport(
        () => locator<Tor>(),
        locator<TorHttpClientFactory>(),
      ),
      dispose: (transport) => transport.closeSessions(),
    );
    locator.registerFactory<RequestFederationBooksUsecase>(
      () => RequestFederationBooksUsecase(
        FederationBookReader(locator<TorCoordinatorTransport>()),
        Federation.robosats,
      ),
    );
    locator.registerFactory<FetchCoordinatorInfoUsecase>(
      () => FetchCoordinatorInfoUsecase(
        CoordinatorClient(locator<TorCoordinatorTransport>()),
      ),
    );
    locator.registerFactory<WatchP2pTorStateUsecase>(
      () => WatchP2pTorStateUsecase(() => locator<Tor>()),
    );
    locator.registerFactory<CloseCoordinatorSessionsUsecase>(
      () => CloseCoordinatorSessionsUsecase(locator<TorCoordinatorTransport>()),
    );
  }
}
