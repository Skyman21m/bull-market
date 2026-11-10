import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/dropped_order_reason.dart';
import 'package:robosats/src/coordinator/json_fields.dart';
import 'package:robosats/src/coordinator/order_values.dart';
import 'package:robosats/src/coordinator/payment_methods.dart';
import 'package:robosats/src/coordinator/read_bounds.dart';
import 'package:robosats/src/coordinator/robosats_currency.dart';
import 'package:robosats/src/robosats_failure.dart';
import 'package:robosats/src/robot_hash_id.dart';

/// An order of the public book of a coordinator, as `GET /api/book/` lists it (`BookView`, `api/views.py:776-826`).
///
/// Every field has been checked: an order that fails any check is left out of its book, never shown half-read.
@immutable
final class PublicOrder {
  /// The coordinator that hosts the order.
  final Coordinator coordinator;

  /// The number of the order on its coordinator: two coordinators can use the same number.
  final int id;
  final DateTime createdAt;

  /// When the order leaves the book if nobody takes it.
  final DateTime expiresAt;
  final OrderType type;
  final RobosatsCurrency currency;
  final OrderAmount amount;
  final PaymentMethods paymentMethods;

  /// The premium over the coordinator's market price: chosen by the maker, or computed by the coordinator for an order priced in sats.
  final Premium premium;

  /// The amount in sats the maker fixed, for an order priced in sats (`is_explicit`), else `null`.
  final Sats? explicitSatoshis;

  /// The sats the order trades at the current price, for the largest amount of a range, without fees.
  final Sats? satoshisNow;

  /// The price per bitcoin, in [currency], at the current market price and [premium].
  final double? price;

  /// How long the maker and the taker have to lock the escrow and submit the invoice once the order is taken.
  final Duration escrowDuration;
  final BondSize bondSize;

  /// The meeting area of a face-to-face cash order, if the maker set one.
  final OrderLocation? location;

  /// The maker, whose nickname this package derives from the hash id rather than trusting the coordinator's `maker_nick`.
  final RobotHashId maker;
  final MakerActivity? makerActivity;

  const PublicOrder._({
    required this.coordinator,
    required this.id,
    required this.createdAt,
    required this.expiresAt,
    required this.type,
    required this.currency,
    required this.amount,
    required this.paymentMethods,
    required this.premium,
    required this.explicitSatoshis,
    required this.satoshisNow,
    required this.price,
    required this.escrowDuration,
    required this.bondSize,
    required this.location,
    required this.maker,
    required this.makerActivity,
  });

  /// Reads one element of the book: the order, or the reason it is left out, the first invalid field.
  ///
  /// Every field the user needs to understand or take the order is required and checked.
  /// `maker_status` is the only lenient one: an unknown label is read as `null`.
  /// `maker` (the maker's database id) is not read.
  /// [now] only rules out absurd dates: an order created more than 7 days after it, or that expired more than 7 days before it, is dropped, never one that is merely expired.
  @internal
  static ({PublicOrder? order, DroppedOrderReason? dropped}) parse(
    Object? element,
    Coordinator coordinator,
    DateTime now,
  ) {
    if (element is! Map<String, Object?>) {
      return const (order: null, dropped: DroppedOrderReason.notAnObject);
    }
    final fields = JsonFields(element);
    final id = fields.requiredInt('id', min: 1, max: 1 << 53);
    final createdAt = _date(fields, 'created_at');
    final expiresAt = _date(fields, 'expires_at');
    final typeWire = fields.requiredInt('type', min: 0, max: 1);
    final currencyId = fields.requiredInt('currency', min: 1, max: 65535);
    final hasRange = fields.requiredBool('has_range');
    final fixed = fields.optionalDecimal('amount', min: 0, max: 1e10);
    final rangeMin = fields.optionalDecimal('min_amount', min: 0, max: 1e10);
    final rangeMax = fields.optionalDecimal('max_amount', min: 0, max: 1e10);
    // At most 70 code points, the `max_length` of the order model (`api/models/order.py:85`).
    final paymentMethod = fields.requiredText(
      'payment_method',
      maxCodePoints: 70,
    );
    final isExplicit = fields.requiredBool('is_explicit');
    final premium = fields.requiredDecimal(
      'premium',
      min: Premium.minPercent,
      max: Premium.maxPercent,
    );
    final satoshis = fields.optionalInt(
      'satoshis',
      min: 1,
      max: CoordinatorReadBounds.maxSats,
    );
    final satoshisNow = fields.optionalInt(
      'satoshis_now',
      min: 0,
      max: CoordinatorReadBounds.maxSats,
    );
    final price = fields.optionalDouble('price', min: 0, max: double.maxFinite);
    final escrowSeconds = fields.requiredInt(
      'escrow_duration',
      min: _minEscrowSeconds,
      max: _maxEscrowSeconds,
    );
    final bond = fields.requiredDecimal(
      'bond_size',
      min: BondSize.minPercent,
      max: BondSize.maxPercent,
    );
    final latitude = fields.optionalDecimal('latitude', min: -90, max: 90);
    final longitude = fields.optionalDecimal('longitude', min: -180, max: 180);
    final makerHashId = fields.requiredString('maker_hash_id', maxLength: 64);
    final makerNick = fields.optionalString('maker_nick', maxLength: 64);
    final makerStatus = fields.optionalString('maker_status', maxLength: 64);
    if (fields.rejected case final field?) {
      return (order: null, dropped: DroppedOrderReason.forField(field));
    }

    ({PublicOrder? order, DroppedOrderReason? dropped}) reject(
      DroppedOrderReason reason,
    ) => (order: null, dropped: reason);

    final type = OrderType.fromWire(typeWire);
    if (type == null) return reject(DroppedOrderReason.type);
    final currency = RobosatsCurrency.fromId(currencyId);
    if (currency == null) return reject(DroppedOrderReason.currency);
    if (createdAt == null || expiresAt == null) {
      return reject(DroppedOrderReason.createdAt);
    }
    if (!expiresAt.isAfter(createdAt) ||
        expiresAt.difference(createdAt) > _maxPublicDuration ||
        expiresAt.isBefore(now.subtract(_clockTolerance))) {
      return reject(DroppedOrderReason.expiresAt);
    }
    if (createdAt.isAfter(now.add(_clockTolerance))) {
      return reject(DroppedOrderReason.createdAt);
    }

    final OrderAmount amount;
    if (hasRange) {
      final min = rangeMin == null ? null : FiatAmount.tryCreate(rangeMin);
      final max = rangeMax == null ? null : FiatAmount.tryCreate(rangeMax);
      if (min == null) return reject(DroppedOrderReason.minAmount);
      if (max == null) return reject(DroppedOrderReason.maxAmount);
      final range = RangeOrderAmount.tryCreate(min, max);
      if (range == null) return reject(DroppedOrderReason.maxAmount);
      amount = range;
    } else {
      final value = fixed == null ? null : FiatAmount.tryCreate(fixed);
      if (value == null) return reject(DroppedOrderReason.amount);
      amount = FixedOrderAmount(value);
    }

    if (isExplicit && satoshis == null) {
      return reject(DroppedOrderReason.satoshis);
    }

    final OrderLocation? location;
    switch ((latitude, longitude)) {
      case (null, null):
        location = null;
      case (final double lat, final double lon):
        location = OrderLocation.tryCreate(lat, lon);
        if (location == null) return reject(DroppedOrderReason.latitude);
      default:
        return reject(DroppedOrderReason.longitude);
    }

    final maker = RobotHashId.parse(makerHashId);
    if (maker is! Ok<RobotHashId, RobosatsFailure>) {
      return reject(DroppedOrderReason.makerHashId);
    }
    if (makerNick != null && makerNick != maker.value.nickname) {
      return reject(DroppedOrderReason.makerNick);
    }

    final premiumValue = Premium.tryCreate(premium);
    final bondValue = BondSize.tryCreate(bond);
    if (premiumValue == null) return reject(DroppedOrderReason.premium);
    if (bondValue == null) return reject(DroppedOrderReason.bondSize);

    return (
      dropped: null,
      order: PublicOrder._(
        coordinator: coordinator,
        id: id,
        createdAt: createdAt,
        expiresAt: expiresAt,
        type: type,
        currency: currency,
        amount: amount,
        paymentMethods: PaymentMethods.parse(paymentMethod),
        premium: premiumValue,
        explicitSatoshis: isExplicit && satoshis != null
            ? Sats.fromInt(satoshis)
            : null,
        satoshisNow: satoshisNow == null ? null : Sats.fromInt(satoshisNow),
        price: price == null || price == 0 ? null : price,
        escrowDuration: Duration(seconds: escrowSeconds),
        bondSize: bondValue,
        location: location,
        maker: maker.value,
        makerActivity: makerStatus == null
            ? null
            : MakerActivity.fromWire(makerStatus),
      ),
    );
  }

  /// The bounds of `escrow_duration` in the order model, in seconds (`api/models/order.py`: 30 minutes to 10 hours).
  static const _minEscrowSeconds = 1800;
  static const _maxEscrowSeconds = 36000;

  /// The longest an order can stay public: `MAX_PUBLIC_ORDER_DURATION` is 24 hours (`robosats/settings.py:298`), doubled for margin.
  static const _maxPublicDuration = Duration(hours: 48);

  /// How far the dates of an order may be from the local clock: Tor itself does not work with a clock this wrong, so only absurd dates fall outside.
  static const _clockTolerance = Duration(days: 7);

  static final RegExp _isoDate = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-](\d{2}):(\d{2}))$',
  );

  /// An ISO 8601 date and time with a time zone, as the coordinator serializes it, between 2020 and 2100.
  ///
  /// Every part must be in range, so the text means the date it is read as: `DateTime.tryParse` alone would turn `25:61` into the next day.
  /// A date without a zone would be read in local time, so it is rejected.
  static DateTime? _date(JsonFields fields, String key) {
    final text = fields.requiredString(key, maxLength: 40);
    if (fields.rejected != null) return null;
    final match = _isoDate.firstMatch(text);
    final date = match == null ? null : DateTime.tryParse(text);
    if (match == null || date == null || !_inRange(match)) {
      fields.rejected ??= key;
      return null;
    }
    return date;
  }

  static bool _inRange(RegExpMatch match) {
    int part(int group) => int.parse(match[group] ?? '0');
    final year = part(1);
    final month = part(2);
    final day = part(3);
    return year >= 2020 &&
        year <= 2100 &&
        month >= 1 &&
        month <= 12 &&
        day >= 1 &&
        day <= DateTime.utc(year, month + 1, 0).day &&
        part(4) <= 23 &&
        part(5) <= 59 &&
        part(6) <= 59 &&
        part(7) <= 14 &&
        part(8) <= 59;
  }

  /// Orders are identified by their coordinator and their number.
  @override
  bool operator ==(Object other) =>
      other is PublicOrder &&
      other.coordinator == coordinator &&
      other.id == id;

  @override
  int get hashCode => Object.hash(coordinator, id);

  /// Public order data without the maker's free text.
  @override
  String toString() =>
      'PublicOrder(${coordinator.shortAlias}#$id, ${type.name}, ${currency.code}, $amount, $premium)';
}
