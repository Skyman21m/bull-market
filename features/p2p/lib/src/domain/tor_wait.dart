import 'p2p_tor_state.dart';

/// The wait for Tor before the book, in the three steps the official Android client shows, plus the error.
///
/// It reads the states of [P2pTorState] with two rules, so the screen neither flashes nor goes back:
/// - once a connection has started, a brief `notStarted` is ignored: at start-up the Tor of the wallet passes through « stopped » between two « connecting » (measured on 10/11/2026);
/// - once Tor has been ready, the wait is over for good: Arti reports « connecting » again during a directory refresh over a live route, and a request that fails then is a failure of its coordinator, not of the screen.
enum TorWait {
  /// Tor is not started yet.
  initializing,

  /// Tor is starting.
  connecting,

  /// Tor has been ready: the book can be requested.
  ready,

  /// Tor could not start.
  failed;

  /// The step after Tor reports [state].
  TorWait after(P2pTorState state) => switch ((this, state)) {
    (ready, _) => ready,
    (_, P2pTorState.ready) => ready,
    (_, P2pTorState.failed) => failed,
    (_, P2pTorState.connecting) => connecting,
    (connecting, P2pTorState.notStarted) => connecting,
    (_, P2pTorState.notStarted) => initializing,
  };
}
