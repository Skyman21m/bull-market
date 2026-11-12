import 'dart:math' as math;

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

  /// The highest percentage the wait shows: a full start reads as done, and Tor is not ready until it says so.
  static const maxPercent = 99;

  /// The step after Tor reports [state].
  TorWait after(P2pTorState state) => switch ((this, state)) {
    (ready, _) => ready,
    (_, P2pTorState.ready) => ready,
    (_, P2pTorState.failed) => failed,
    (_, P2pTorState.connecting) => connecting,
    (connecting, P2pTorState.notStarted) => connecting,
    (_, P2pTorState.notStarted) => initializing,
  };

  /// The percentage of its start Tor has done, as this step shows it once Tor reports [report], [shown] being the percentage shown before; `null` shows none.
  ///
  /// It reads the share of [P2pTorReport.progress] with these rules:
  /// - only while Tor connects, and only once it has reported a share: none before, and none once Tor is ready or has failed;
  /// - in whole percent rounded down, and at most [maxPercent]: `bull_tor` reports a full share for a few seconds before Tor is ready (it holds readiness once Arti can carry traffic), and 100 % would read as done while the wait goes on;
  /// - never lower than [shown] during one attempt: Arti's share can dip while it fetches the directory, and the bar would read as work lost;
  /// - from scratch at each attempt: `bull_tor` reports Tor stopped, or connecting with no share, before it starts Arti again (the Snowflake fallback, « Retry »), and then none is shown until the new attempt reports a share.
  int? percentAfter(P2pTorReport report, {required int? shown}) {
    final share = report.progress;
    if (this != connecting || share == null) return null;
    // Rounded to a hundredth of a percent first, so that the error of a binary fraction does not take a point off: 0.29 is 29 %, not 28 %.
    final percent = math.min((share * 10000).round() ~/ 100, maxPercent);
    return shown == null ? percent : math.max(percent, shown);
  }
}
