import 'package:meta/meta.dart';

/// The side of an order, from its maker's point of view: `type` 0 and 1 in the API.
///
/// A taker who wants to buy bitcoin takes a [sell] order.
enum OrderType {
  /// The maker buys bitcoin and pays fiat.
  buy(0),

  /// The maker sells bitcoin and receives fiat.
  sell(1);

  /// The value of the `type` field and query parameter.
  final int wire;

  const OrderType(this.wire);

  /// The type with this wire value, or `null`.
  static OrderType? fromWire(int value) => switch (value) {
    0 => buy,
    1 => sell,
    _ => null,
  };
}

/// How recently the maker of an order was seen by its coordinator (`api/logics.py:196-202`).
enum MakerActivity {
  /// Seen in the last 2 minutes.
  active('Active'),

  /// Seen in the last 10 minutes.
  seenRecently('Seen recently'),

  /// Not seen for 10 minutes or more.
  inactive('Inactive');

  final String wire;

  const MakerActivity(this.wire);

  /// The activity with this exact label, or `null`.
  static MakerActivity? fromWire(String value) {
    for (final activity in values) {
      if (activity.wire == value) return activity;
    }
    return null;
  }
}

/// A positive amount in the currency of an order: fiat, gold, or bitcoin for a swap.
@immutable
final class FiatAmount implements Comparable<FiatAmount> {
  /// Finite and greater than zero.
  final double value;

  const FiatAmount._(this.value);

  /// The amount, or `null` unless [value] is finite and greater than zero.
  static FiatAmount? tryCreate(double value) =>
      value.isFinite && value > 0 ? FiatAmount._(value) : null;

  @override
  int compareTo(FiatAmount other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is FiatAmount && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'FiatAmount($value)';
}

/// The amount an order trades: a fixed amount, or a range within which the taker chooses.
@immutable
sealed class OrderAmount {
  const OrderAmount();

  /// The largest amount the order can trade.
  FiatAmount get max;

  /// The smallest amount the order can trade.
  FiatAmount get min;
}

/// An order for exactly [amount].
final class FixedOrderAmount extends OrderAmount {
  final FiatAmount amount;

  const FixedOrderAmount(this.amount);

  @override
  FiatAmount get max => amount;

  @override
  FiatAmount get min => amount;

  @override
  bool operator ==(Object other) =>
      other is FixedOrderAmount && other.amount == amount;

  @override
  int get hashCode => amount.hashCode;

  @override
  String toString() => 'FixedOrderAmount(${amount.value})';
}

/// An order for any amount from [min] to [max], which the taker chooses.
final class RangeOrderAmount extends OrderAmount {
  @override
  final FiatAmount min;

  @override
  final FiatAmount max;

  const RangeOrderAmount._(this.min, this.max);

  /// The range, or `null` when [min] is above [max].
  static RangeOrderAmount? tryCreate(FiatAmount min, FiatAmount max) =>
      min.compareTo(max) <= 0 ? RangeOrderAmount._(min, max) : null;

  @override
  bool operator ==(Object other) =>
      other is RangeOrderAmount && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'RangeOrderAmount(${min.value}-${max.value})';
}

/// The premium of an order over the market price of its coordinator, in percent: negative for a discount.
@immutable
final class Premium implements Comparable<Premium> {
  /// The bounds a coordinator accepts for an order priced relative to the market (`api/models/order.py`, `premium`).
  static const double minPercent = -100;
  static const double maxPercent = 999;

  /// Finite, between [minPercent] and [maxPercent].
  final double percent;

  const Premium._(this.percent);

  /// The premium, or `null` outside [minPercent] to [maxPercent].
  static Premium? tryCreate(double percent) =>
      percent.isFinite && percent >= minPercent && percent <= maxPercent
      ? Premium._(percent)
      : null;

  @override
  int compareTo(Premium other) => percent.compareTo(other.percent);

  @override
  bool operator ==(Object other) => other is Premium && other.percent == percent;

  @override
  int get hashCode => percent.hashCode;

  @override
  String toString() => 'Premium($percent%)';
}

/// The fidelity bond of an order, in percent of the trade amount, locked by both maker and taker.
@immutable
final class BondSize implements Comparable<BondSize> {
  /// The bounds a coordinator accepts (`MIN_BOND_SIZE` and `MAX_BOND_SIZE`, `robosats/settings.py:304-305`).
  static const double minPercent = 2;
  static const double maxPercent = 15;

  final double percent;

  const BondSize._(this.percent);

  /// The bond, or `null` outside [minPercent] to [maxPercent].
  static BondSize? tryCreate(double percent) =>
      percent.isFinite && percent >= minPercent && percent <= maxPercent
      ? BondSize._(percent)
      : null;

  @override
  int compareTo(BondSize other) => percent.compareTo(other.percent);

  @override
  bool operator ==(Object other) => other is BondSize && other.percent == percent;

  @override
  int get hashCode => percent.hashCode;

  @override
  String toString() => 'BondSize($percent%)';
}

/// The approximate place a maker chose for a face-to-face cash trade.
@immutable
final class OrderLocation {
  /// From -90 to 90.
  final double latitude;

  /// From -180 to 180.
  final double longitude;

  const OrderLocation._(this.latitude, this.longitude);

  /// The location, or `null` outside the bounds of [latitude] and [longitude].
  static OrderLocation? tryCreate(double latitude, double longitude) =>
      latitude.abs() <= 90 && longitude.abs() <= 180
      ? OrderLocation._(latitude, longitude)
      : null;

  @override
  bool operator ==(Object other) =>
      other is OrderLocation &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'OrderLocation($latitude, $longitude)';
}
