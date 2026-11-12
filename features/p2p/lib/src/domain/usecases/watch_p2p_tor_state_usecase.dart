import 'package:bull_tor/tor.dart';

import '../p2p_tor_state.dart';

/// Follows the embedded Tor that carries every request to the coordinators.
final class WatchP2pTorStateUsecase {
  final Tor Function() _tor;

  const WatchP2pTorStateUsecase(this._tor);

  /// The current report at once, then each change, the share of the start included; it does not start Tor, the first request does.
  ///
  /// It is the embedded Tor's, whatever proxy the wallet is set to: the P2P tab always goes through the embedded Tor.
  Stream<P2pTorReport> execute() =>
      _tor().embedded.states.map(P2pTorReport.of).distinct();
}
