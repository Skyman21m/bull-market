/// The time the P2P screens read: the wall clock in the app, a fixed one in tests and screenshots.
final class P2pClock {
  final DateTime Function() now;

  const P2pClock(this.now);
}
