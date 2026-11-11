import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart';

/// The largest trade the official client lets a coordinator host, which grows with its age in the federation (`calculateSizeLimit`, `frontend/src/models/Coordinator.model.ts:110` at commit ff1998c).
///
/// A founder is trusted with 21 BTC at once.
/// Another coordinator starts at 250,000 sats and gains 30 % at each difficulty adjustment, counted as 14 days since its date in the federation list, up to 21 BTC after the twelfth.
/// The limit is a number of sats that need not be whole, as in the official client.
@immutable
final class CoordinatorSizeLimit {
  /// The limit, in sats.
  final double sats;

  const CoordinatorSizeLimit._(this.sats);

  /// 21 BTC, the limit of a mature coordinator.
  static const double mature = 21 * 100000000;

  /// What the official client calls large limits, the threshold of the badge.
  static const double large = 3000000;

  static const double _start = 250000;
  static const double _growth = 1.3;
  static const int _adjustmentsToMature = 12;
  static const Duration _adjustment = Duration(days: 14);

  /// The limit of [coordinator] at [now].
  factory CoordinatorSizeLimit.of(Coordinator coordinator, DateTime now) {
    if (coordinator.badges.isFounder) {
      return const CoordinatorSizeLimit._(mature);
    }
    final age = now.difference(coordinator.establishedOn);
    final adjustments = (age.inMilliseconds / _adjustment.inMilliseconds)
        .ceil();
    var value = _start;
    for (var i = 1; i < adjustments; i++) {
      value *= _growth;
      if (i >= _adjustmentsToMature) {
        return const CoordinatorSizeLimit._(mature);
      }
    }
    return CoordinatorSizeLimit._(value);
  }

  /// Whether the badge of large limits is lit.
  bool get isLarge => sats > large;

  /// The « Maximum order size » of the coordinator dialog: the smaller of this limit and the largest order [info] announces.
  double maxOrderSize(CoordinatorInfo info) =>
      _min(sats, info.maxOrderSize.value.toDouble());

  /// The « Maximum onchain swap size »: the smaller of [maxOrderSize] and the largest swap [info] announces.
  double maxSwapSize(CoordinatorInfo info) =>
      _min(maxOrderSize(info), info.maxSwap.value.toDouble());

  static double _min(double a, double b) => a < b ? a : b;

  @override
  bool operator ==(Object other) =>
      other is CoordinatorSizeLimit && other.sats == sats;

  @override
  int get hashCode => sats.hashCode;

  @override
  String toString() => 'CoordinatorSizeLimit($sats)';
}
