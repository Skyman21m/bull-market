import 'dart:convert';

import 'package:convert/convert.dart' show hex;
import 'package:crypto/crypto.dart' show sha256;
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/json_fields.dart';
import 'package:robosats/src/coordinator/order_values.dart';
import 'package:robosats/src/coordinator/robosats_currency.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';
import 'package:robosats/src/coordinator/visible_text.dart';
import 'package:robosats/src/robosats_failure.dart';

/// What a maker asks a coordinator to make, checked before anything is sent: the body of `POST /api/make/` (`CoordinatorClient.makeOrder`).
///
/// Every field is bounded as the coordinator bounds it (`MakeOrderSerializer`, `api/serializers.py:587-627`, with the validators of the order model, `api/models/order.py:77-184`, commit ff1998c), so that a request this package sends is not refused by the form check, whose empty `400` says nothing of why; where the reference client is stricter, its own bound is the caller's to apply.
/// Nothing is rounded or cleaned: a value the coordinator would store differently from what was sent (a number with more decimals than its field keeps, a text with spaces at its ends, which its serializer trims) is refused, so that the answer can be compared with the request field by field.
///
/// What this package does not send: a price in sats (`is_explicit`, `satoshis`, which the reference client no longer offers) and an order in bitcoin (currency 1000, the reference's « Swap? »); the body carries `null` for each, as the reference client writes it when they are not set.
///
/// Since #189 it sends a meeting point ([location]) and a password, as the reference client does (`MakerForm.tsx:270-273`): the password only as its SHA-256 ([OrderPasswordHash]), never the text. Two requests are equal when they ask the same order: whether there is a password is compared, never its hash, which a device does not keep ([kept]).
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

  /// The decimals of a meeting point's latitude and longitude at the coordinator (`decimal_places=6`, `api/models/order.py:148-167`): more is refused there with an empty `400`.
  static const locationDecimals = 6;

  /// The coordinator's nominal ratios of a range's maximum to its minimum: at least [minRangeRatio] (error 1006) and at most [maxRangeRatio] times (error 1009, `api/logics.py:164-175`).
  ///
  /// The package refuses a range that the coordinator would refuse whatever its price; it does not promise that the coordinator takes a range at these exact bounds: the coordinator compares sats it computes in floating point at its price of the moment (`Logics.calc_sats`, `api/logics.py:256-259`), so a range at a bound may still get 1006 or 1009, a refusal known to come before the order is made ([OrderSizeRefused]).
  /// The reference client keeps a margin in its form, 1.6 and 14.8 (`components/MakerForm/AmountRange.tsx:54-55`): that margin is the form's to apply (design note § 2.2, #183), not this package's.
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

  /// The meeting point of a face-to-face trade, which the coordinator shows with the order and publishes on Nostr as a geohash (`api/nostr.py:151-153`), or `null`.
  final OrderLocation? location;

  /// Whether the order is protected by a password: the coordinator then leaves it out of its book (`api/views.py:788-795`) and a take must send the same password's hash (`:554-560`).
  final bool hasPassword;

  /// The SHA-256 of the password, what the body sends; `null` without a password, and for a request a device kept of an order that had one ([kept]), which is never sent ([isSendable]).
  final OrderPasswordHash? passwordHash;

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
    required this.location,
    required this.hasPassword,
    required this.passwordHash,
  });

  /// The request, or `null` when a field is outside what the coordinator stores as sent.
  ///
  /// - [currency]: any currency of RoboSats but bitcoin (1000).
  /// - [amount]: each amount above 0 and below [amountLimit], with at most [amountDecimals] decimals; a range's maximum from [minRangeRatio] to [maxRangeRatio] times its minimum, the coordinator's nominal bounds (see there).
  /// - [paymentMethod]: 1 to [maxPaymentMethodCodePoints] code points of clean text (see below).
  /// - [premium]: above -100 (excluded: a price of zero, which the coordinator cannot divide by) and at most 999, with at most [premiumDecimals] decimals.
  /// - [publicDuration] and [escrowDuration]: whole seconds within their bounds.
  /// - [bondSize]: at most [bondSizeDecimals] decimals.
  /// - [description]: `null`, or 1 to [maxDescriptionCodePoints] code points of clean text.
  /// - [location]: `null`, or a latitude and a longitude with at most [locationDecimals] decimals each.
  /// - [password]: `null`, or the hash of the password sent with the order.
  /// - [keptWithPassword]: the request of an order a device made with a password, read back from its records, which keep that there was one and never the password nor its hash: such a request says it has a password and is never sent ([isSendable]); give [password] again for a request to send.
  ///
  /// A clean text is what `displayText` leaves as it is, with no space at either end: no control character, no line break, no bidirectional control, no unpaired surrogate; and, since #181, a text every character of which is seen as it is written ([isShownAsWritten]): never one that shows as empty, nor one with an invisible character, a space other than U+0020, a private use character or a joiner, a variation selector or a combining mark out of its place, which the coordinator would store and show to every robot that reads the order.
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
    OrderLocation? location,
    OrderPasswordHash? password,
    bool keptWithPassword = false,
  }) {
    final amountValid = switch (amount) {
      FixedOrderAmount(:final amount) => _isAmount(amount),
      RangeOrderAmount(:final min, :final max) =>
        _isAmount(min) &&
            _isAmount(max) &&
            // The coordinator's comparisons, `min_sats > max_sats / 1.5` and `min_sats < max_sats / 15`, written on the amounts: the nominal bounds, which its own floating-point sats can still miss by a rounding (see [minRangeRatio]).
            !(min.value > max.value / minRangeRatio) &&
            !(min.value < max.value / maxRangeRatio),
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
            _isCleanText(description, maxDescriptionCodePoints)) &&
        (location == null ||
            (_decimalsOf(location.latitude) <= locationDecimals &&
                _decimalsOf(location.longitude) <= locationDecimals));
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
      location: location,
      hasPassword: password != null || keptWithPassword,
      passwordHash: password,
    );
  }

  /// What a device keeps of this request: the same order, whether it has a password included, never the password's hash, so never sent when it has a password; this very request when it holds no hash.
  MakeOrderRequest get kept => passwordHash == null
      ? this
      : MakeOrderRequest._(
          type: type,
          currency: currency,
          amount: amount,
          paymentMethod: paymentMethod,
          premium: premium,
          publicDuration: publicDuration,
          escrowDuration: escrowDuration,
          bondSize: bondSize,
          description: description,
          location: location,
          hasPassword: hasPassword,
          passwordHash: null,
        );

  /// Whether this request can be sent: with its password's hash when it has a password. A request a device kept ([kept]) of a protected order cannot: `CoordinatorClient.makeOrder` refuses it before sending.
  bool get isSendable => !hasPassword || passwordHash != null;

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
      isShownAsWritten(text);

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
      'latitude': switch (location) {
        final location? => jsonNumber(location.latitude),
        null => null,
      },
      'longitude': switch (location) {
        final location? => jsonNumber(location.longitude),
        null => null,
      },
      'password': passwordHash?.hex,
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
      other.description == description &&
      other.location == location &&
      other.hasPassword == hasPassword;

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
    location,
    hasPassword,
  );

  /// Names the side and the currency only: the amounts, the premium, the payment methods, the description, the meeting point and the password's hash are never printed.
  @override
  String toString() => 'MakeOrderRequest(${type.name}, ${currency.code})';
}

/// The SHA-256 of an order's password, what a make sends in place of the password (`password: maker.password ? sha256(maker.password) : null`, `MakerForm.tsx:273`, commit ff1998c): the hash of the password's UTF-8 bytes in lowercase hexadecimal, as `js-sha256` writes it and as a taker of the official client sends it for the same password (`OrderDetails/TakeButton.tsx:333`), so that the order can be taken with it (`api/views.py:554-560` compares the two texts as they are).
///
/// The password is any text but the empty one, which the reference sends as no password: neither trimmed nor bounded, as the reference's field takes it (the coordinator bounds what it stores, the hash, to 2,000 characters, `api/models/order.py:169-175`). The text is never kept here; the hash is never printed.
@immutable
final class OrderPasswordHash {
  /// 64 lowercase hexadecimal characters.
  final String hex;

  const OrderPasswordHash._(this.hex);

  /// The hash of [password], or `null` for an empty text, which the reference sends as no password.
  static OrderPasswordHash? of(String password) => password.isEmpty
      ? null
      : OrderPasswordHash._(
          _hexOf(sha256.convert(utf8.encode(password)).bytes),
        );

  @override
  bool operator ==(Object other) =>
      other is OrderPasswordHash && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;

  @override
  String toString() => 'OrderPasswordHash(<redacted>)';
}

/// [bytes] in lowercase hexadecimal.
String _hexOf(List<int> bytes) => hex.encode(bytes);

/// What a coordinator answered to a make: an order numbered [id], at status 0, waiting for its maker bond.
///
/// It is the coordinator's word, checked for consistency with [request] on the fields the answer carries, and nothing more.
/// Compared with [request] and found equal: the type, the currency, the fixed amount or the range (`amount`, `has_range`, `min_amount`, `max_amount`), the payment method, the premium, the escrow duration, the bond size and the meeting point (`latitude`, `longitude`, the serializer's texts of 6 decimals, `null` without one); and found as this package sends them: `is_explicit` false, `satoshis` `null`.
/// Not in the answer (`ListOrderSerializer`, `api/serializers.py:83-107`), so not checked here: the public duration, the description and the password; fields the answer adds beyond the serializer's are ignored.
/// The first read of the order by the robot (`CoordinatorClient.fetchOrder`) gives them: `expires_at` at status 1 is the creation plus the public duration, with `description` and `has_password`; the make use case (#179) compares them with what it asked.
/// The answer names no robot either (its `maker` and `taker` are the coordinator's internal user ids, read as nothing), so it does not prove that this robot is the order's maker: that first read, which checks `is_maker` against the robot's hash id, does; the bond invoice comes with it too (`api/views.py:373-379`), never with this answer.
@immutable
final class MadeOrder {
  final Coordinator coordinator;
  final RobosatsNetwork network;

  /// The order's number on [coordinator].
  final int id;

  final DateTime createdAt;

  /// When the time to lock the maker bond ends, as the coordinator says (`EXP_MAKER_BOND_INVOICE`, 300 seconds by default, `api/views.py:190`): only after [createdAt] and within 2020 to 2100, not bounded further, so not a deadline to rely on; the bond invoice's own expiry is.
  final DateTime expiresAt;

  /// What was sent: every term the answer carries equals it (see the class).
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
/// The answer is malformed ([CoordinatorResponseMalformed], with the field) unless it has every field of the serializer but `maker` and `taker`, an `id` from 1 to 2^53, `status` 0, `expires_at` after `created_at`, and each term equal to [request]'s: the serializer's decimals are strings, compared as the numbers they write; `is_explicit` false, `satoshis` `null`; `latitude` and `longitude` the meeting point sent, both `null` without one (the coordinator stores what it is sent with 6 decimals, `api/models/order.py:148-167`, so the text it writes back reads as the very number sent); and for a fixed amount no range, for a range no amount.
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
  final latitude = fields.optionalDecimal('latitude', min: -90, max: 90);
  final longitude = fields.optionalDecimal('longitude', min: -180, max: 180);
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
  if (latitude != request.location?.latitude) return reject('latitude');
  if (longitude != request.location?.longitude) return reject('longitude');
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
