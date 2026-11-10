import 'package:bull_tor/tor.dart';

/// Where the embedded Tor stands, as the P2P screens show it before any coordinator answers.
enum P2pTorState {
  /// Tor has not been started, or it was stopped.
  notStarted,

  /// Tor is starting: the coordinators cannot be reached yet.
  connecting,

  /// Tor is running: requests to the coordinators can go out.
  ready,

  /// Tor could not start: no coordinator can be reached until it does.
  failed;

  /// The state of the embedded Tor as these four steps.
  static P2pTorState of(TorConnectionState state) => switch (state) {
    TorUninitialized() || TorStopped() => notStarted,
    TorConnecting() => connecting,
    TorReady() => ready,
    TorUnavailable() => failed,
  };
}
