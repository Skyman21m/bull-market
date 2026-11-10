import 'package:bull_tor/tor.dart';

import '../p2p_tor_state.dart';

/// Follows the embedded Tor that carries every request to the coordinators.
final class WatchP2pTorStateUsecase {
  final Tor Function() _tor;

  const WatchP2pTorStateUsecase(this._tor);

  /// The current state at once, then each change; it does not start Tor, the first request does.
  Stream<P2pTorState> execute() =>
      _tor().embedded.states.map(P2pTorState.of).distinct();
}
