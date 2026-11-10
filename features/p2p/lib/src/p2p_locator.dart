import 'package:bull_tor/tor.dart';
import 'package:get_it/get_it.dart';
import 'package:robosats/robosats.dart';

import 'data/tor_coordinator_transport.dart';
import 'domain/coordinator_sessions_port.dart';
import 'domain/p2p_clock.dart';
import 'domain/usecases/close_coordinator_sessions_usecase.dart';
import 'domain/usecases/fetch_coordinator_info_usecase.dart';
import 'domain/usecases/request_federation_books_usecase.dart';
import 'domain/usecases/retry_p2p_tor_usecase.dart';
import 'domain/usecases/start_p2p_tor_usecase.dart';
import 'domain/usecases/watch_p2p_tor_state_usecase.dart';
import 'presentation/book_cubit.dart';
import 'presentation/order_details_cubit.dart';

/// Registers the internals of the feature: one Tor transport, shared by every request to the coordinators, the use-cases and the cubits of the screens.
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
    registerOver(
      locator,
      transport: () => locator<TorCoordinatorTransport>(),
      sessions: () => locator<TorCoordinatorTransport>(),
      tor: () => locator<Tor>(),
      clock: DateTime.now,
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
  }
}
