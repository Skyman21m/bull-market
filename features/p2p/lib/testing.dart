/// Test seam of the P2P feature: its real screens and cubits over a fake coordinator transport, fake Tor states and a fixed clock, without network, and its real transport for the live integration tests.
///
/// For tests and screenshots only: the app registers the feature with `P2pFeature.setup`.
library;

import 'package:bull_tor/tor.dart';
import 'package:get_it/get_it.dart';
import 'package:robosats/robosats.dart';

import 'src/data/tor_coordinator_transport.dart';
import 'src/domain/coordinator_sessions_port.dart';
import 'src/domain/p2p_tor_state.dart';
import 'src/p2p_locator.dart';

// What a fake transport needs, so that a test of the app builds one without depending on `robosats` itself.
// And what a live integration test needs to drive the coordinator client itself over [liveCoordinatorTransportForTesting].
export 'package:robosats/robosats.dart'
    show
        CoordinatorClient,
        CoordinatorHttpMethod,
        CoordinatorRequest,
        CoordinatorResponse,
        CoordinatorTransport,
        Federation;

export 'src/domain/p2p_tor_state.dart' show P2pTorState;

/// Registers what [P2pFeature.route] needs in [locator]: every coordinator request goes to [transport], Tor reports [torStates] to each new listener, and the screens read [clock].
void setUpP2pForTesting(
  GetIt locator, {
  required CoordinatorTransport transport,
  required Stream<P2pTorState> Function() torStates,
  required DateTime Function() clock,
}) {
  final tor = _StatesOnlyTor(torStates);
  P2pLocator.registerOver(
    locator,
    transport: () => transport,
    sessions: () => const _NoSessions(),
    tor: () => tor,
    clock: clock,
  );
}

/// The transport of the app, over the embedded Tor, once the feature is registered with `P2pFeature.setup`.
///
/// For live integration tests only, which use it for what the facade leaves out on purpose: the raw answer of a coordinator, and a first contact that sends the Nostr key of the formula Troc does not use.
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

  _StatesOnlyTor(Stream<P2pTorState> Function() states)
    : embedded = _StatesOnlyEmbeddedTor(states);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _StatesOnlyEmbeddedTor implements EmbeddedTor {
  final Stream<P2pTorState> Function() _states;

  _StatesOnlyEmbeddedTor(this._states);

  static final _route = TorRoute(
    source: TorSource.embedded,
    endpoint: TorProxyEndpoint(host: '127.0.0.1', port: 9050),
    evidence: TorReadinessEvidence.embeddedBootstrap,
  );

  @override
  Stream<TorConnectionState> get states => _states().map(
    (state) => switch (state) {
      P2pTorState.notStarted => const TorUninitialized(),
      P2pTorState.connecting => const TorConnecting(source: TorSource.embedded),
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
