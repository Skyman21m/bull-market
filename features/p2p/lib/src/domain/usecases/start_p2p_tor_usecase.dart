import 'package:bull_tor/tor.dart';

/// Starts the embedded Tor for the P2P screens, which wait for it before they ask the coordinators for anything.
final class StartP2pTorUsecase {
  final Tor Function() _tor;

  const StartP2pTorUsecase(this._tor);

  /// Starts Tor if it is not running, or checks the running one; how it goes arrives through [WatchP2pTorStateUsecase], so the outcome is not returned.
  Future<void> execute() async {
    try {
      await _tor().embedded.ensureReady();
    } on Exception {
      // A start that fails is reported as the `failed` state of Tor.
    }
  }
}
