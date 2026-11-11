import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeys;

import '../src/domain/p2p_tor_state.dart';
import '../src/domain/usecases/close_coordinator_sessions_usecase.dart';
import '../src/domain/usecases/fetch_coordinator_info_usecase.dart';
import '../src/domain/usecases/request_federation_books_usecase.dart';
import '../src/domain/usecases/watch_p2p_tor_state_usecase.dart';
import '../src/p2p_locator.dart';
import '../src/p2p_router.dart';

/// Public application-shell composition for the P2P feature.
final class P2pFeature {
  const P2pFeature();

  /// Where the P2P tab lives.
  static const String path = P2pRouter.path;

  /// Registers the services of the feature; nothing starts until the first request, which starts Tor if needed.
  ///
  /// [garageKeys] is the vault's handle on the RoboSats Garage Keys, which only the foreground composition of the shell asks `Secrets` for and passes here.
  /// With `null`, as in the WorkManager isolate, whose keystore lock does not reach the foreground's, the feature has no Garage Key ability at all: nothing that reads or writes one is registered.
  /// Registering reads and writes no key either way.
  void setup(GetIt locator, {required GarageKeys? garageKeys}) {
    P2pLocator.setup(locator, garageKeys: garageKeys);
    locator.registerLazySingleton<P2pFacade>(
      () => P2pFacade._(locator(), locator(), locator(), locator()),
    );
  }

  /// The P2P tab, with the page of an order inside it, to mount in the bottom bar of the shell.
  ///
  /// The route is always registered: the shell hides the tab and sends every location of it elsewhere with [redirect] while the gate is closed, so that no widget, cubit or Tor start of P2P is ever built then.
  /// [network] is read from the context of the tab each time it builds, so a change of network reloads the book.
  ///
  /// How the tab uses Tor:
  /// - each entry in the tab builds a new book: it calls `ensureReady` on the embedded Tor, waits for it, then asks every coordinator again;
  /// - P2P always goes through the embedded Tor of the wallet, even when the wallet is set to use an external Tor proxy;
  /// - Tor and the sessions to the coordinators stay up after leaving the tab;
  /// - « Retry » is offered only when Tor failed to start, and it restarts the embedded Tor that the whole wallet shares.
  GoRoute route(
    GetIt locator, {
    required RobosatsNetwork Function(BuildContext context) network,
  }) => P2pRouter.route(locator, network);

  /// Whether [location] is a page of the P2P tab.
  static bool isP2pPath(String location) => P2pRouter.isP2pPath(location);

  /// Whether the user may see P2P: superusers in developer mode only, the gate of Silent Payments.
  static bool isVisibleTo({
    required bool isSuperuser,
    required bool isDevModeEnabled,
  }) => isSuperuser && isDevModeEnabled;

  /// Where a navigation to [location] goes instead, or `null` to let it through.
  ///
  /// With the gate closed every page of the P2P tab sends to [gateClosedRedirectPath]; any other location is left alone.
  /// Pure, so the gate the router ships is the gate the tests check.
  static String? redirect(
    String location, {
    required bool isSuperuser,
    required bool isDevModeEnabled,
    required String gateClosedRedirectPath,
  }) {
    if (!isP2pPath(location)) return null;
    return isVisibleTo(
          isSuperuser: isSuperuser,
          isDevModeEnabled: isDevModeEnabled,
        )
        ? null
        : gateClosedRedirectPath;
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

  /// Closes every Tor session to the coordinators, those of the robots included; the next request opens new ones.
  Future<void> closeSessions() => _closeSessions.execute();
}
