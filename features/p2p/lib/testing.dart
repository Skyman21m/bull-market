/// Test seam of the P2P feature: its real screens and cubits over a fake coordinator transport, fake Tor states and a fixed clock, without network, and its real transport for the live integration tests.
///
/// For tests and screenshots only: the app registers the feature with `P2pFeature.setup`.
library;

import 'package:bull_tor/tor.dart';
import 'package:drift/native.dart';
import 'package:get_it/get_it.dart';
import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeys;

import 'src/data/p2p_database.dart';
import 'src/data/tor_coordinator_transport.dart';
import 'src/domain/coordinator_sessions_port.dart';
import 'src/domain/p2p_tor_state.dart';
import 'src/domain/repositories/garage_key_repository.dart';
import 'src/domain/repositories/robot_binding_repository.dart';
import 'src/p2p_locator.dart';

// What a fake transport needs, so that a test of the app builds one without depending on `robosats` itself.
// And what a live integration test needs to make a throwaway robot and drive the coordinator client itself over [liveCoordinatorTransportForTesting].
// The app-facing library exports none of the robot types: they are here for tests only, and `test/features/p2p/p2p_testing_seam_test.dart` checks that no library of the app imports this file.
export 'package:robosats/robosats.dart'
    show
        CoordinatorClient,
        CoordinatorHttpMethod,
        CoordinatorRequest,
        CoordinatorResponse,
        CoordinatorRobot,
        CoordinatorTransport,
        Federation,
        GarageKey,
        NostrKeyDerivation,
        RobotIdentity,
        RobotKeysRefused,
        RobotPgpKey,
        RobotPgpKeyMismatch,
        RobotUnknown;

export 'src/domain/p2p_tor_state.dart' show P2pTorReport, P2pTorState;
// The coordinator images and their pinned sources, which the app's tests load through the app's own asset bundle.
export 'src/ui/widgets/coordinator_images.dart'
    show CoordinatorImage, coordinatorImages;

/// Registers what [P2pFeature.route] needs in [locator]: every coordinator request goes to [transport], Tor reports [torStates] to each new listener, and the screens read [clock].
///
/// Tor reports either [torStates], or [torReports] when a test needs the share of its start too.
///
/// With [garageKeys], a handle on a vault the test made over its own keystore, the Garage is registered as the app registers it, over a database in memory; without it, the Garage is disabled, as in a feature set up without the vault's handle.
@visibleForTesting
void setUpP2pForTesting(
  GetIt locator, {
  required CoordinatorTransport transport,
  Stream<P2pTorState> Function()? torStates,
  Stream<P2pTorReport> Function()? torReports,
  required DateTime Function() clock,
  GarageKeys? garageKeys,
}) {
  final Stream<P2pTorReport> Function() reports = switch ((
    torStates,
    torReports,
  )) {
    (final states?, null) => () => states().map(P2pTorReport.new),
    (null, final reports?) => reports,
    _ => throw ArgumentError('Tor reports either states or reports'),
  };
  final tor = _StatesOnlyTor(reports);
  P2pLocator.registerOver(
    locator,
    transport: () => transport,
    sessions: () => const _NoSessions(),
    tor: () => tor,
    clock: clock,
  );
  if (garageKeys != null) {
    P2pLocator.registerGarageKeys(
      locator,
      garageKeys,
      database: () => P2pDatabase.forTesting(NativeDatabase.memory()),
      transport: () => transport,
      clock: clock,
    );
  }
}

/// Whether the feature registered in [locator] was given the vault's Garage Key handle, which `P2pFeature.setup` receives from the foreground composition of the shell only.
@visibleForTesting
bool hasGarageKeysForTesting(GetIt locator) =>
    locator.isRegistered<GarageKeyRepository>();

/// Whether the feature registered in [locator] has its database and the bindings of the robots, which it gets with the directory `P2pFeature.setup` receives from the foreground composition of the shell only.
@visibleForTesting
bool hasP2pDatabaseForTesting(GetIt locator) =>
    locator.isRegistered<P2pDatabase>() &&
    locator.isRegistered<RobotBindingRepository>();

/// The transport of the app, over the embedded Tor, once the feature is registered with `P2pFeature.setup`.
///
/// For live integration tests only, which use it for what the facade leaves out on purpose: every request made for a robot, the raw answer of a coordinator, and a first contact that sends the Nostr key of the formula Troc does not use.
@visibleForTesting
CoordinatorTransport liveCoordinatorTransportForTesting(GetIt locator) =>
    locator<TorCoordinatorTransport>();

final class _NoSessions implements CoordinatorSessionsPort {
  const _NoSessions();

  @override
  Future<void> closeSessions() async {}

  @override
  Future<void> closeRobotSessions(RobotSessionKey robot) async {}
}

/// A Tor that only reports states: starting it or retrying it does nothing.
final class _StatesOnlyTor implements Tor {
  @override
  final EmbeddedTor embedded;

  _StatesOnlyTor(Stream<P2pTorReport> Function() reports)
    : embedded = _StatesOnlyEmbeddedTor(reports);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _StatesOnlyEmbeddedTor implements EmbeddedTor {
  final Stream<P2pTorReport> Function() _reports;

  _StatesOnlyEmbeddedTor(this._reports);

  static final _route = TorRoute(
    source: TorSource.embedded,
    endpoint: TorProxyEndpoint(host: '127.0.0.1', port: 9050),
    evidence: TorReadinessEvidence.embeddedBootstrap,
  );

  @override
  Stream<TorConnectionState> get states => _reports().map(
    (report) => switch (report.state) {
      P2pTorState.notStarted => const TorUninitialized(),
      P2pTorState.connecting => TorConnecting(
        source: TorSource.embedded,
        progress: report.progress,
      ),
      P2pTorState.ready => TorReady(_route),
      P2pTorState.failed => const TorUnavailable(
        source: TorSource.embedded,
        failure: TorBootstrapTimeoutFailure(),
      ),
    },
  );

  @override
  Future<TorConnectionState> ensureReady() async => const TorUninitialized();

  @override
  Future<TorConnectionState> retry() async => const TorUninitialized();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
