import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
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

  /// Reads one element of the book, rejecting it with the first invalid field.
  ///
  /// Every field the user needs to understand or take the order is required and checked.
  /// `maker_status` is the only lenient one: an unknown label is read as `null`.
  /// `maker` (the maker's database id) is not read.
  @internal
  static Result<PublicOrder, CoordinatorResponseMalformed> parse(
    Object? element,
    Coordinator coordinator,
  ) {
    if (element is! Map<String, Object?>) {
      return const Err(CoordinatorResponseMalformed('order'));
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
    final paymentMethod = fields.requiredString('payment_method', maxLength: 70);
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
      return Err(CoordinatorResponseMalformed(field));
    }

    Err<PublicOrder, CoordinatorResponseMalformed> reject(String field) =>
        Err(CoordinatorResponseMalformed(field));

    final type = OrderType.fromWire(typeWire);
    if (type == null) return reject('type');
    final currency = RobosatsCurrency.fromId(currencyId);
    if (currency == null) return reject('currency');
    if (createdAt == null || expiresAt == null) return reject('created_at');
    if (!expiresAt.isAfter(createdAt)) return reject('expires_at');

    final OrderAmount amount;
    if (hasRange) {
      final min = rangeMin == null ? null : FiatAmount.tryCreate(rangeMin);
      final max = rangeMax == null ? null : FiatAmount.tryCreate(rangeMax);
      if (min == null || max == null) return reject('min_amount');
      final range = RangeOrderAmount.tryCreate(min, max);
      if (range == null) return reject('max_amount');
      amount = range;
    } else {
      final value = fixed == null ? null : FiatAmount.tryCreate(fixed);
      if (value == null) return reject('amount');
      amount = FixedOrderAmount(value);
    }

    if (isExplicit && satoshis == null) return reject('satoshis');

    final OrderLocation? location;
    switch ((latitude, longitude)) {
      case (null, null):
        location = null;
      case (final double lat, final double lon):
        location = OrderLocation.tryCreate(lat, lon);
        if (location == null) return reject('latitude');
      default:
        return reject('longitude');
    }

    final maker = RobotHashId.parse(makerHashId);
    if (maker is! Ok<RobotHashId, RobosatsFailure>) {
      return reject('maker_hash_id');
    }
    if (makerNick != null && makerNick != maker.value.nickname) {
      return reject('maker_nick');
    }

    final premiumValue = Premium.tryCreate(premium);
    final bondValue = BondSize.tryCreate(bond);
    if (premiumValue == null) return reject('premium');
    if (bondValue == null) return reject('bond_size');

    return Ok(
      PublicOrder._(
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

  /// An ISO 8601 date with a time zone, which the coordinator always sends in UTC; a date without a zone would be read in local time, so it is rejected.
  static DateTime? _date(JsonFields fields, String key) {
    final text = fields.requiredString(key, maxLength: 40);
    if (fields.rejected != null) return null;
    final date = DateTime.tryParse(text);
    if (date == null || !date.isUtc) {
      fields.rejected ??= key;
      return null;
    }
    return date;
  }

  /// Orders are identified by their coordinator and their number.
  @override
  bool operator ==(Object other) =>
      other is PublicOrder && other.coordinator == coordinator && other.id == id;

  @override
  int get hashCode => Object.hash(coordinator, id);

  /// Public order data without the maker's free text.
  @override
  String toString() =>
      'PublicOrder(${coordinator.shortAlias}#$id, ${type.name}, ${currency.code}, $amount, $premium)';
}
