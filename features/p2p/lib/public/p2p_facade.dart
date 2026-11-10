import 'package:get_it/get_it.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../src/domain/p2p_tor_state.dart';
import '../src/domain/usecases/close_coordinator_sessions_usecase.dart';
import '../src/domain/usecases/fetch_coordinator_info_usecase.dart';
import '../src/domain/usecases/request_federation_books_usecase.dart';
import '../src/domain/usecases/watch_p2p_tor_state_usecase.dart';
import '../src/p2p_locator.dart';

/// Public application-shell composition for the P2P feature.
final class P2pFeature {
  const P2pFeature();

  /// Registers the services of the feature; nothing starts until the first request, which starts Tor if needed.
  void setup(GetIt locator) {
    P2pLocator.setup(locator);
    locator.registerLazySingleton<P2pFacade>(
      () => P2pFacade._(locator(), locator(), locator(), locator()),
    );
  }
}

/// Public composition boundary for the P2P feature: the RoboSats federation, read over the embedded Tor.
final class P2pFacade {
  final RequestFederationBooksUsecase _requestBooks;
  final FetchCoordinatorInfoUsecase _fetchInfo;
  final WatchP2pTorStateUsecase _watchTorState;
  final CloseCoordinatorSessionsUsecase _closeSessions;

  const P2pFacade._(
    this._requestBooks,
    this._fetchInfo,
    this._watchTorState,
    this._closeSessions,
  );

  /// Asks every coordinator on [network] for its book at once: one pending outcome per coordinator, in the order of the federation.
  ///
  /// Each future completes, within the deadline of the transport, with the book or the failure of its coordinator, and never with an error.
  Map<Coordinator, Future<CoordinatorBookOutcome>> requestBooks(
    RobosatsNetwork network,
  ) => _requestBooks.execute(network);

  /// `/api/info/` of [coordinator], checked against the federation list: an identity mismatch is a [CoordinatorIdentityFailure].
  Future<Result<CoordinatorInfo, CoordinatorFailure>> fetchInfo(
    Coordinator coordinator,
    RobosatsNetwork network,
  ) => _fetchInfo.execute(coordinator, network);

  /// The state of the embedded Tor, at once and then at each change.
  Stream<P2pTorState> watchTorState() => _watchTorState.execute();

  /// Closes every Tor session to the coordinators; the next request opens new ones.
  Future<void> closeSessions() => _closeSessions.execute();
}
