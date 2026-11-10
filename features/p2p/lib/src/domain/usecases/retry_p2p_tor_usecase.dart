import 'package:bull_tor/tor.dart';

/// Starts the embedded Tor again after it could not start, when the user asks for it on the P2P screen.
final class RetryP2pTorUsecase {
  final Tor Function() _tor;

  const RetryP2pTorUsecase(this._tor);

  /// Stops and restarts Tor; how it goes arrives through [WatchP2pTorStateUsecase], so the outcome is not returned.
  Future<void> execute() async {
    try {
      await _tor().embedded.retry();
    } on Exception {
      // A start that fails again is reported as the `failed` state of Tor.
    }
  }
}
