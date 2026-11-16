import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/json_fields.dart';
import 'package:robosats/src/coordinator/order_values.dart';
import 'package:robosats/src/coordinator/robosats_currency.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';
import 'package:robosats/src/robosats_failure.dart';

/// What a maker asks a coordinator to make, checked before anything is sent: the body of `POST /api/make/` (`CoordinatorClient.makeOrder`).
///
/// Every field is bounded as the coordinator bounds it (`MakeOrderSerializer`, `api/serializers.py:587-627`, with the validators of the order model, `api/models/order.py:77-184`, commit ff1998c), so that a request this package sends is not refused by the form check, whose empty `400` says nothing of why; where the reference client is stricter, its own bound is the caller's to apply.
/// Nothing is rounded or cleaned: a value the coordinator would store differently from what was sent (a number with more decimals than its field keeps, a text with spaces at its ends, which its serializer trims) is refused, so that the answer can be compared with the request field by field.
///
/// What this package does not send yet: a price in sats (`is_explicit`, `satoshis`, which the reference client no longer offers), an order in bitcoin (currency 1000, the reference's « Swap? »), a meeting point and a password, which the design note leaves to issue #189; the body then carries `null` for each, as the reference client writes it when they are not set.
@immutable
final class MakeOrderRequest {
  /// The bounds of a public duration: from 10 minutes, the reference client's shortest (`MakerForm.tsx:1115-1148`, the coordinator taking 597.6 s, `robosats/settings.py:300`, `api/models/order.py:109-122`), to 24 hours, the coordinator's longest.
  static const minPublicDuration = Duration(seconds: 600);
  static const maxPublicDuration = Duration(hours: 24);

  /// The bounds of an escrow duration, the time each side has for its step once the order is taken: 30 minutes to 10 hours (`api/models/order.py:124-133`); the reference client offers 1 to 10 hours.
  static const minEscrowDuration = Duration(minutes: 30);
  static const maxEscrowDuration = Duration(hours: 10);

  /// The most code points of the payment method text (`max_length=70`, `api/serializers.py:592-597`); the reference client warns from 50.
  static const maxPaymentMethodCodePoints = 70;

  /// The most code points of a description (`max_length=240`, `api/models/order.py:178-184`).
  static const maxDescriptionCodePoints = 240;

  /// The ratio a range's maximum must keep to its minimum: at least [minRangeRatio] (error 1006) and at most [maxRangeRatio] times (error 1009), as the coordinator compares them (`api/logics.py:159-175`); the reference client keeps 1.6 and 14.8 in its form (`AmountRange.tsx:54-55`).
  static const minRangeRatio = 1.5;
  static const maxRangeRatio = 15.0;

  /// The decimals each number keeps at the coordinator (`decimal_places` of its fields, `api/models/order.py:77-146`): more is refused there with an empty `400`.
  static const amountDecimals = 8;
  static const premiumDecimals = 2;
  static const bondSizeDecimals = 2;

  /// An amount is below 10^10: 18 digits, 8 of them decimals (`max_digits=18`, `api/models/order.py:77-84`).
  static const amountLimit = 1e10;

  /// The side of the order: the maker of a [OrderType.buy] order buys bitcoin.
  final OrderType type;

  final RobosatsCurrency currency;

  /// A fixed amount, or a range whose taker chooses the amount.
  final OrderAmount amount;

  /// The payment methods as one text, the reference client's names joined by spaces, or `not specified`.
  final String paymentMethod;

  /// Above -100 % and at most 999 %, with at most two decimals.
  final Premium premium;

  /// How long the order stays in the book, counted from its creation.
  final Duration publicDuration;

  /// How long each side has for its step once the order is taken.
  final Duration escrowDuration;

  /// With at most two decimals.
  final BondSize bondSize;

  /// The maker's free text, which the coordinator shows to every robot that reads the order and publishes on Nostr with it, or `null`.
  final String? description;

  const MakeOrderRequest._({
    required this.type,
    required this.currency,
    required this.amount,
    required this.paymentMethod,
    required this.premium,
    required this.publicDuration,
    required this.escrowDuration,
    required this.bondSize,
    required this.description,
  });

  /// The request, or `null` when a field is outside what the coordinator stores as sent.
  ///
  /// - [currency]: any currency of RoboSats but bitcoin (1000).
  /// - [amount]: each amount above 0 and below [amountLimit], with at most [amountDecimals] decimals; a range's maximum from [minRangeRatio] to [maxRangeRatio] times its minimum.
  /// - [paymentMethod]: 1 to [maxPaymentMethodCodePoints] code points of clean text (see below).
  /// - [premium]: above -100 (excluded: a price of zero, which the coordinator cannot divide by) and at most 999, with at most [premiumDecimals] decimals.
  /// - [publicDuration] and [escrowDuration]: whole seconds within their bounds.
  /// - [bondSize]: at most [bondSizeDecimals] decimals.
  /// - [description]: `null`, or 1 to [maxDescriptionCodePoints] code points of clean text.
  ///
  /// A clean text is what `displayText` leaves as it is, with no space at either end: no control character, no line break, no bidirectional control, no unpaired surrogate.
  static MakeOrderRequest? tryCreate({
    required OrderType type,
    required RobosatsCurrency currency,
    required OrderAmount amount,
    required String paymentMethod,
    required Premium premium,
    required Duration publicDuration,
    required Duration escrowDuration,
    required BondSize bondSize,
    String? description,
  }) {
    final amountValid = switch (amount) {
      FixedOrderAmount(:final amount) => _isAmount(amount),
      RangeOrderAmount(:final min, :final max) =>
        _isAmount(min) &&
            _isAmount(max) &&
            max.value >= min.value * minRangeRatio &&
            max.value <= min.value * maxRangeRatio,
    };
    final valid =
        !currency.isBitcoin &&
        amountValid &&
        _isCleanText(paymentMethod, maxPaymentMethodCodePoints) &&
        premium.percent > Premium.minPercent &&
        premium.percent <= Premium.maxMarketPercent &&
        _decimalsOf(premium.percent) <= premiumDecimals &&
        _isWholeSecondsWithin(
          publicDuration,
          minPublicDuration,
          maxPublicDuration,
        ) &&
        _isWholeSecondsWithin(
          escrowDuration,
          minEscrowDuration,
          maxEscrowDuration,
        ) &&
        _decimalsOf(bondSize.percent) <= bondSizeDecimals &&
        (description == null ||
            _isCleanText(description, maxDescriptionCodePoints));
    if (!valid) return null;
    return MakeOrderRequest._(
      type: type,
      currency: currency,
      amount: amount,
      paymentMethod: paymentMethod,
      premium: premium,
      publicDuration: publicDuration,
      escrowDuration: escrowDuration,
      bondSize: bondSize,
      description: description,
    );
  }

  static bool _isAmount(FiatAmount amount) =>
      amount.value < amountLimit && _decimalsOf(amount.value) <= amountDecimals;

  static bool _isWholeSecondsWithin(
    Duration duration,
    Duration min,
    Duration max,
  ) =>
      duration.inMicroseconds % Duration.microsecondsPerSecond == 0 &&
      duration >= min &&
      duration <= max;

  static bool _isCleanText(String text, int maxCodePoints) =>
      text.isNotEmpty &&
      text.length <= 2 * maxCodePoints &&
      text.runes.length <= maxCodePoints &&
      text.trim() == text &&
      displayText(text) == text;

  /// The decimals of [value] as it is written in JSON, the shortest text that reads back as [value], which is also how the coordinator reads the number (`str` of a Python `float`, then `Decimal`).
  static int _decimalsOf(double value) {
    final text = value.abs().toString();
    final exponentAt = text.indexOf('e');
    final mantissa = exponentAt < 0 ? text : text.substring(0, exponentAt);
    final exponent = exponentAt < 0
        ? 0
        : int.parse(text.substring(exponentAt + 1));
    final pointAt = mantissa.indexOf('.');
    final fraction = pointAt < 0
        ? ''
        : mantissa.substring(pointAt + 1).replaceFirst(RegExp(r'0+$'), '');
    final decimals = fraction.length - exponent;
    return decimals < 0 ? 0 : decimals;
  }

  /// The JSON body of `POST /api/make/`, the keys in the reference client's order (`Order.make`, `frontend/src/models/Order.model.ts:196-215`, commit ff1998c).
  @internal
  Map<String, Object?> get body {
    final range = amount is RangeOrderAmount;
    return {
      'type': type.wire,
      'currency': currency.id,
      'amount': range ? null : jsonNumber(amount.max.value),
      'has_range': range,
      'min_amount': range ? jsonNumber(amount.min.value) : null,
      'max_amount': range ? jsonNumber(amount.max.value) : null,
      'payment_method': paymentMethod,
      'is_explicit': false,
      'premium': jsonNumber(premium.percent),
      'satoshis': null,
      'public_duration': publicDuration.inSeconds,
      'escrow_duration': escrowDuration.inSeconds,
      'bond_size': jsonNumber(bondSize.percent),
      'latitude': null,
      'longitude': null,
      'password': null,
      'description': description,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is MakeOrderRequest &&
      other.type == type &&
      other.currency == currency &&
      other.amount == amount &&
      other.paymentMethod == paymentMethod &&
      other.premium == premium &&
      other.publicDuration == publicDuration &&
      other.escrowDuration == escrowDuration &&
      other.bondSize == bondSize &&
      other.description == description;

  @override
  int get hashCode => Object.hash(
    type,
    currency,
    amount,
    paymentMethod,
    premium,
    publicDuration,
    escrowDuration,
    bondSize,
    description,
  );

  /// Names the side and the currency only: the amounts, the premium, the payment methods and the description are never printed.
  @override
  String toString() => 'MakeOrderRequest(${type.name}, ${currency.code})';
}

/// What a coordinator answered to a make: an order numbered [id], waiting for its maker bond, with the terms of [request].
///
/// It proves only that [coordinator] made an order with these terms: the answer names no robot (its `maker` and `taker` are the coordinator's internal user ids, read as nothing), so it does not prove that this robot is the order's maker.
/// The first read of the order by the robot (`CoordinatorClient.fetchOrder`), which checks `is_maker` against the robot's hash id, is what proves it; the bond invoice comes with that read too (`api/views.py:373-379`), never with this answer.
@immutable
final class MadeOrder {
  final Coordinator coordinator;
  final RobosatsNetwork network;

  /// The order's number on [coordinator].
  final int id;

  final DateTime createdAt;

  /// When the time to lock the maker bond ends (`EXP_MAKER_BOND_INVOICE`, 300 seconds by default, `api/views.py:190`).
  final DateTime expiresAt;

  /// What was sent, which every term of the answer equals.
  final MakeOrderRequest request;

  const MadeOrder._({
    required this.coordinator,
    required this.network,
    required this.id,
    required this.createdAt,
    required this.expiresAt,
    required this.request,
  });

  @override
  String toString() => 'MadeOrder(#$id)';
}

/// The fields of `ListOrderSerializer` (`api/serializers.py:83-107`) that a `201` answer to [request] must have, with the values it must have.
const _answerKeys = [
  'id',
  'status',
  'created_at',
  'expires_at',
  'type',
  'currency',
  'amount',
  'has_range',
  'min_amount',
  'max_amount',
  'payment_method',
  'is_explicit',
  'premium',
  'satoshis',
  'escrow_duration',
  'bond_size',
  'latitude',
  'longitude',
];

/// Reads the decoded body of a `201` answer of [coordinator] on [network] to a make of [request]: the order as `ListOrderSerializer` writes it (`MakerView.post`, `api/views.py:216`, commit ff1998c).
///
/// The answer is malformed ([CoordinatorResponseMalformed], with the field) unless it has every field of the serializer but `maker` and `taker`, an `id` from 1 to 2^53, `status` 0, `expires_at` after `created_at`, and each term equal to [request]'s: the serializer's decimals are strings, compared as the numbers they write; `is_explicit` false, `satoshis`, `latitude` and `longitude` `null`; and for a fixed amount no range, for a range no amount.
@internal
Result<MadeOrder, CoordinatorFailure> parseMakeAnswer(
  Object? body,
  Coordinator coordinator,
  RobosatsNetwork network, {
  required MakeOrderRequest request,
}) {
  if (body is! Map<String, Object?>) {
    return const Err(CoordinatorResponseMalformed('order'));
  }
  for (final key in _answerKeys) {
    if (!body.containsKey(key)) return Err(CoordinatorResponseMalformed(key));
  }
  final fields = JsonFields(body);
  final id = fields.requiredInt('id', min: 1, max: 1 << 53);
  final status = fields.requiredInt('status', min: 0, max: 18);
  final createdAt = fields.requiredDate('created_at');
  final expiresAt = fields.requiredDate('expires_at');
  final type = fields.requiredInt('type', min: 0, max: 1);
  final currency = fields.requiredInt('currency', min: 1, max: 65535);
  final hasRange = fields.requiredBool('has_range');
  final fixed = fields.optionalDecimal('amount', min: 0, max: 1e10);
  final rangeMin = fields.optionalDecimal('min_amount', min: 0, max: 1e10);
  final rangeMax = fields.optionalDecimal('max_amount', min: 0, max: 1e10);
  final paymentMethod = fields.requiredString(
    'payment_method',
    maxLength: 2 * MakeOrderRequest.maxPaymentMethodCodePoints,
  );
  final isExplicit = fields.requiredBool('is_explicit');
  final premium = fields.optionalDecimal('premium', min: -100, max: 999);
  final escrowSeconds = fields.requiredInt(
    'escrow_duration',
    min: 0,
    max: 1 << 31,
  );
  final bondSize = fields.optionalDecimal('bond_size', min: 0, max: 100);
  if (fields.rejected case final field?) {
    return Err(CoordinatorResponseMalformed(field));
  }
  // Each check names the field it rejects, as [JsonFields] does.
  Result<MadeOrder, CoordinatorFailure> reject(String field) =>
      Err(CoordinatorResponseMalformed(field));
  if (status != 0) return reject('status');
  if (createdAt == null) return reject('created_at');
  if (expiresAt == null || !expiresAt.isAfter(createdAt)) {
    return reject('expires_at');
  }
  if (type != request.type.wire) return reject('type');
  if (currency != request.currency.id) return reject('currency');
  final range = request.amount is RangeOrderAmount;
  if (hasRange != range) return reject('has_range');
  if (range) {
    if (body['amount'] != null) return reject('amount');
    if (rangeMin != request.amount.min.value) return reject('min_amount');
    if (rangeMax != request.amount.max.value) return reject('max_amount');
  } else {
    if (fixed != request.amount.max.value) return reject('amount');
    if (body['min_amount'] != null) return reject('min_amount');
    if (body['max_amount'] != null) return reject('max_amount');
  }
  if (paymentMethod != request.paymentMethod) return reject('payment_method');
  if (isExplicit) return reject('is_explicit');
  if (premium != request.premium.percent) return reject('premium');
  if (body['satoshis'] != null) return reject('satoshis');
  if (escrowSeconds != request.escrowDuration.inSeconds) {
    return reject('escrow_duration');
  }
  if (bondSize != request.bondSize.percent) return reject('bond_size');
  if (body['latitude'] != null) return reject('latitude');
  if (body['longitude'] != null) return reject('longitude');
  return Ok(
    MadeOrder._(
      coordinator: coordinator,
      network: network,
      id: id,
      createdAt: createdAt,
      expiresAt: expiresAt,
      request: request,
    ),
  );
}
