import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/json_fields.dart';
import 'package:robosats/src/coordinator/read_bounds.dart';
import 'package:robosats/src/coordinator/robosats_currency.dart';
import 'package:robosats/src/robosats_failure.dart';

/// The market price of a coordinator in one currency, and the order sizes it accepts in that currency.
@immutable
final class CurrencyLimit {
  final RobosatsCurrency currency;

  /// The price of one bitcoin in [currency], greater than zero.
  final double price;

  /// The smallest order, in [currency]: the coordinator's minimum in sats at [price].
  final double minAmount;

  /// The largest order, in [currency], at least [minAmount].
  final double maxAmount;

  const CurrencyLimit._(
    this.currency,
    this.price,
    this.minAmount,
    this.maxAmount,
  );

  @override
  bool operator ==(Object other) =>
      other is CurrencyLimit &&
      other.currency == currency &&
      other.price == price &&
      other.minAmount == minAmount &&
      other.maxAmount == maxAmount;

  @override
  int get hashCode => Object.hash(currency, price, minAmount, maxAmount);

  @override
  String toString() =>
      'CurrencyLimit(${currency.code}, price: $price, $minAmount-$maxAmount)';
}

/// What `GET /api/limits/` returns: the market price and the order size bounds of a coordinator, per currency (`LimitView`, `api/views.py:1177-1197`).
@immutable
final class CurrencyLimits {
  final Map<RobosatsCurrency, CurrencyLimit> byCurrency;

  /// How many entries were left out because they were invalid, or for a currency this package does not know.
  final int droppedEntries;

  const CurrencyLimits._(this.byCurrency, this.droppedEntries);

  /// The limit in [currency], or `null` when the coordinator has no valid price for it.
  CurrencyLimit? operator [](RobosatsCurrency currency) => byCurrency[currency];

  /// Reads the decoded body: an object keyed by currency id.
  ///
  /// A body that is not an object, or that has more than `CoordinatorReadBounds.maxLimitEntries` entries, rejects the response.
  /// An invalid entry only drops that currency: a key that is not a known currency id, a `code` that does not match the id, a price that is not a finite number above zero, or bounds that are negative, not finite or reversed.
  @internal
  static Result<CurrencyLimits, CoordinatorFailure> parse(Object? body) {
    if (body is! Map<String, Object?>) {
      return const Err(CoordinatorResponseMalformed('limits'));
    }
    if (body.length > CoordinatorReadBounds.maxLimitEntries) {
      return const Err(CoordinatorResponseMalformed('limits'));
    }
    final limits = <RobosatsCurrency, CurrencyLimit>{};
    var dropped = 0;
    for (final MapEntry(:key, :value) in body.entries) {
      final limit = _entry(key, value);
      if (limit == null) {
        dropped++;
      } else {
        limits[limit.currency] = limit;
      }
    }
    return Ok(CurrencyLimits._(Map.unmodifiable(limits), dropped));
  }

  static CurrencyLimit? _entry(String key, Object? value) {
    final id = int.tryParse(key);
    final currency = id == null ? null : RobosatsCurrency.fromId(id);
    if (currency == null || '${currency.id}' != key) return null;
    if (value is! Map<String, Object?>) return null;
    final fields = JsonFields(value);
    final code = fields.requiredString('code', maxLength: 16);
    final price = fields.requiredDouble('price', min: 0, max: double.maxFinite);
    final min = fields.requiredDouble(
      'min_amount',
      min: 0,
      max: double.maxFinite,
    );
    final max = fields.requiredDouble(
      'max_amount',
      min: 0,
      max: double.maxFinite,
    );
    if (fields.rejected != null || code != currency.code) return null;
    if (price <= 0 || min > max) return null;
    return CurrencyLimit._(currency, price, min, max);
  }

  @override
  String toString() =>
      'CurrencyLimits(${byCurrency.length} currencies, $droppedEntries dropped)';
}
