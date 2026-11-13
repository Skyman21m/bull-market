import 'dart:async';

/// How the P2P book waits before it does something again, and how it spreads those waits: real timers and a random draw in the app, ones the test controls in tests and screenshots.
///
/// It is given to the book as `P2pClock` and `P2pShuffle` are, so that no use case starts a timer or draws at random by itself.
/// Its draws spread waits only, and are never used for anything secret: they need not come from a cryptographic generator.
final class P2pWaits {
  final Timer Function(Duration duration, void Function() callback) _start;
  final double Function() _random;

  /// [start] starts a timer that runs its callback once, after the duration, unless it is cancelled first (`Timer.new` in the app); [random] draws a number from 0 (included) to 1 (excluded).
  const P2pWaits({required this._start, required this._random});

  /// Runs [callback] once after [duration], unless the timer returned is cancelled first.
  Timer start(Duration duration, void Function() callback) =>
      _start(duration, callback);

  /// A number from 0 (included) to 1 (excluded).
  double random() => _random();
}
