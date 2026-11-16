/// Answers of a coordinator to a maker, built as the reference coordinator builds them (commit ff1998c): derived from its code, never recorded, since no order was ever made to record them.
library;

import 'package:robosats/robosats.dart';

import 'order_answers.dart';

/// The maker's request of the tests: a buy order of 150 EUR at a premium of 1.5 %, the reference client's default durations (23:59 public, 3 hours of escrow step, `frontend/src/models/Maker.model.ts:42-46`) and bond (3 %).
MakeOrderRequest testMakeRequest({
  OrderType type = OrderType.buy,
  int currencyId = 2,
  OrderAmount? amount,
  String paymentMethod = 'SEPA Revolut',
  double premium = 1.5,
  Duration publicDuration = const Duration(seconds: 86340),
  Duration escrowDuration = const Duration(seconds: 10800),
  double bondSize = 3,
  String? description,
}) {
  final request = MakeOrderRequest.tryCreate(
    type: type,
    currency: RobosatsCurrency.fromId(currencyId) ?? _missing('currency'),
    amount: amount ?? FixedOrderAmount(fiat(150)),
    paymentMethod: paymentMethod,
    premium: Premium.tryCreate(premium) ?? _missing('premium'),
    publicDuration: publicDuration,
    escrowDuration: escrowDuration,
    bondSize: BondSize.tryCreate(bondSize) ?? _missing('bond size'),
    description: description,
  );
  return request ?? _missing('request');
}

/// A range of the tests, 100 to 300.
RangeOrderAmount testRange([double min = 100, double max = 300]) =>
    RangeOrderAmount.tryCreate(fiat(min), fiat(max)) ?? _missing('range');

FiatAmount fiat(double value) =>
    FiatAmount.tryCreate(value) ?? _missing('$value');

Never _missing(String what) => throw StateError('invalid test $what');

/// The `201` answer of `MakerView.post` to [request] (`api/views.py:179-216`): the order as `ListOrderSerializer` writes it (`api/serializers.py:83-107`), with [changes] applied last, a `null` value removing its key.
///
/// The serializer writes the order's `DecimalField`s as strings with the field's decimal places (`amount` 8, `premium` and `bond_size` 2, `api/models/order.py:77-146`), the integers as numbers, the dates in ISO 8601 with `Z` (`TIME_ZONE = "UTC"`, `robosats/settings.py:248`); `maker` is the coordinator's internal user id and `taker` is `null`.
/// `created_at` is the model's default, taken when the order is built, and `expires_at` the view's `timezone.now()` plus `EXP_MAKER_BOND_INVOICE`, 300 seconds, taken just before (`api/views.py:190`): a few microseconds less than 300 seconds apart.
Map<String, Object?> madeAnswer(
  MakeOrderRequest request, {
  Map<String, Object?> changes = const {},
}) {
  final amount = request.amount;
  String decimal(double value, int places) => value.toStringAsFixed(places);
  return applyChanges({
    'id': testOrderId,
    'status': 0,
    'created_at': '2026-11-16T10:00:00.000012Z',
    'expires_at': '2026-11-16T10:05:00.000003Z',
    'type': request.type.wire,
    'currency': request.currency.id,
    'amount': amount is FixedOrderAmount
        ? decimal(amount.amount.value, 8)
        : null,
    'has_range': amount is RangeOrderAmount,
    'min_amount': amount is RangeOrderAmount
        ? decimal(amount.min.value, 8)
        : null,
    'max_amount': amount is RangeOrderAmount
        ? decimal(amount.max.value, 8)
        : null,
    'payment_method': request.paymentMethod,
    'is_explicit': false,
    'premium': decimal(request.premium.percent, 2),
    'satoshis': null,
    'maker': 7,
    'taker': null,
    'escrow_duration': request.escrowDuration.inSeconds,
    'bond_size': decimal(request.bondSize.percent, 2),
    'latitude': null,
    'longitude': null,
  }, changes);
}
