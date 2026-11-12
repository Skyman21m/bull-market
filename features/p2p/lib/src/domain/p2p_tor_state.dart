import 'package:bull_tor/tor.dart';
import 'package:meta/meta.dart';

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

/// What the embedded Tor reports, as the P2P screens read it: its [state], and while it connects the share of its start done so far.
@immutable
final class P2pTorReport {
  final P2pTorState state;

  /// The share of its start Tor has done, from 0 to 1, as Arti reports it while Tor connects (`TorConnecting.progress` of `bull_tor`).
  ///
  /// It is `null` in every other state, and while Tor connects but has reported no share yet: `bull_tor` begins each attempt with a connecting state without one.
  final double? progress;

  const P2pTorReport._(this.state, this.progress);

  /// A report of [state]; [progress] is kept only while Tor connects, within 0 and 1.
  ///
  /// A share that is not a number reads as 0, never as none: none means a new attempt, and the percentage shown would start over and go back.
  factory P2pTorReport(P2pTorState state, {double? progress}) => P2pTorReport._(
    state,
    state == P2pTorState.connecting ? _share(progress) : null,
  );

  /// The report of the embedded Tor in [state].
  factory P2pTorReport.of(TorConnectionState state) => switch (state) {
    TorConnecting(:final progress) => P2pTorReport(
      P2pTorState.connecting,
      progress: progress,
    ),
    _ => P2pTorReport(P2pTorState.of(state)),
  };

  static double? _share(double? progress) => switch (progress) {
    null => null,
    final share when share.isNaN => 0.0,
    final share => share.clamp(0.0, 1.0),
  };

  @override
  bool operator ==(Object other) =>
      other is P2pTorReport &&
      other.state == state &&
      other.progress == progress;

  @override
  int get hashCode => Object.hash(state, progress);

  @override
  String toString() => 'P2pTorReport(${state.name}, $progress)';
}
