import 'dart:convert';

import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/testing/bolt11_test_invoice.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'fakes.dart';

/// The order of the trade tests: number 42 on temple.
const tradeOrderId = 42;

/// The clock of the trade tests.
final tradeNow = DateTime.utc(2026, 11, 13, 8, 0, 30);

/// The book's figures of the order taken: 100 EUR for 106,900 sats, a bond of 3 %, a premium of 2 %, an escrow of 3 h.
const bookSats = 106900;
const bookAmount = 100.0;

/// The taker fee `/api/info/` announces with the reference's defaults: 0.2 % × (1 − 0.125).
const takerFee = 0.00175;

/// A Garage Key made for these tests only.
final GarageKey _garageKey = switch (GarageKey.fromBytes(
  utf8.encode('a Garage Key of the trade tests.'),
)) {
  Ok(:final value) => value,
  Err(:final failure) => throw StateError('$failure'),
};

RobotIdentity _identityAt(int index) => switch (NetworkGarageKey(
  RobosatsNetwork.mainnet,
  _garageKey,
).firstUsableRobot(index)) {
  Ok(:final value) => value.identity,
  Err(:final failure) => throw StateError('$failure'),
};

/// This device's robot, the taker of every trade of the tests, and the maker.
final RobotIdentity us = _identityAt(0);
final RobotIdentity peer = _identityAt(1);

/// The terms of taking the book's order [tradeOrderId] on temple, as a buyer (a sell order) or a seller (a buy order).
Future<TradeTerms> tradeTerms({
  TradeRole role = TradeRole.buyer,
  RobosatsNetwork network = RobosatsNetwork.mainnet,
  bool range = false,
  double rangeAmount = 120,
}) async {
  final [order] = await parseOrders([
    bookOrder(
      id: tradeOrderId,
      type: role == TradeRole.buyer ? 1 : 0,
      amount: range ? null : bookAmount,
      minAmount: range ? 50 : null,
      maxAmount: range ? 200 : null,
      satoshisNow: range ? bookSats * 2 : bookSats,
      makerSeed: 1,
    ),
  ]);
  return switch (TradeTerms.take(
    order,
    network: network,
    rangeAmount: range ? FiatAmount.tryCreate(rangeAmount) : null,
    takerFee: takerFee,
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('no terms: $failure'),
  };
}

/// The figures of the trade fixed at the bond's lock, for [last] sats, as `Logics.payout_amount` and `Logics.escrow_amount` compute them.
int feeOf(int last) => (last * takerFee).round();
int payoutOf(int last) => last - feeOf(last);
int escrowOf(int last) => last + feeOf(last);

/// The bond of the book's order: 3 % of [bookSats], truncated as the coordinator does.
const bookBond = bookSats * 3 ~/ 100;

/// A bond invoice of [sats] made at [tradeNow] less 10 s for 200 s, as a coordinator's (`EXP_TAKER_BOND_INVOICE` of `.env-sample`).
Bolt11TestInvoice bondInvoice({
  int sats = bookBond,
  int seed = 1,
  Bolt11Network network = Bolt11Network.mainnet,
  Duration age = const Duration(seconds: 10),
  Duration expiry = const Duration(seconds: 200),
  String? payee,
}) => Bolt11TestInvoice(
  network: network,
  sats: sats,
  seed: seed,
  createdAt: tradeNow.subtract(age),
  expiry: expiry,
  description:
      "temple - Taking 'Order 42' Buying BTC for 100.0EUR - Taker bond",
  payeeNodeKey: payee,
);

/// An escrow invoice of [sats], made at [tradeNow] less a minute for the escrow duration.
Bolt11TestInvoice escrowInvoice({
  int sats = 0,
  int seed = 2,
  Bolt11Network network = Bolt11Network.mainnet,
}) => Bolt11TestInvoice(
  network: network,
  sats: sats == 0 ? escrowOf(bookSats) : sats,
  seed: seed,
  createdAt: tradeNow.subtract(const Duration(minutes: 1)),
  expiry: const Duration(seconds: 10800),
  description: "temple - Escrow amount for 'Order 42'",
);

/// The answer of `OrderView.get` (`api/views.py:226-528`, commit ff1998c) about order [tradeOrderId] to this device's robot, the taker as [role], with the JSON types the reference writes (as `packages/robosats/test/coordinator/order_test.dart` builds it).
///
/// [status] is the status shown: 3 for the pre-take with [bond], 1 for the order public again with this robot no participant. [last] is the order's `last_satoshis` from the bond's lock on; [changes] is applied last, a `null` value removing its key.
Map<String, Object?> orderJson(
  int status, {
  TradeRole role = TradeRole.buyer,
  bool range = false,
  int last = bookSats,
  Bolt11TestInvoice? bond,
  Bolt11TestInvoice? escrow,
  DateTime? expiresAt,
  Map<String, Object?> changes = const {},
}) {
  final buyer = role == TradeRole.buyer;
  final participant = status != 1;
  final taken = status >= 5;
  final data = <String, Object?>{
    'id': tradeOrderId,
    'status': status,
    'created_at': '2026-11-13T07:00:00Z',
    'expires_at': (expiresAt ?? tradeNow.add(_stepOf(status)))
        .toIso8601String(),
    'type': buyer ? 1 : 0,
    'currency': 2,
    'amount': range ? (participant ? '120.00000000' : null) : '100.00000000',
    'has_range': range,
    'min_amount': range ? '50.00000000' : null,
    'max_amount': range ? '200.00000000' : null,
    'payment_method': 'Revolut Instant SEPA',
    'is_explicit': false,
    'premium': '2.00',
    'satoshis': null,
    'maker': 7,
    'taker': taken ? 8 : null,
    'escrow_duration': 10800,
    'bond_size': '3.00',
    'latitude': null,
    'longitude': null,
    'is_maker': false,
    'is_taker': participant,
    'is_participant': participant,
    'has_password': false,
    'total_secs_exp': _stepOf(status).inSeconds,
    'maker_nick': peer.nickname,
    'maker_hash_id': peer.hashId.hex,
    'description': null,
    'maker_status': 'Active',
  };
  if (!participant) {
    data
      ..['price_now'] = 93545.0
      ..['premium_now'] = 2.0
      ..['satoshis_now'] = bookSats;
    return _apply(data, changes);
  }
  data
    ..['is_buyer'] = buyer
    ..['is_seller'] = !buyer
    ..['taker_nick'] = taken ? us.nickname : 'None'
    ..['status_message'] = 'Some label'
    ..['is_fiat_sent'] = status == 10
    ..['is_disputed'] = status == 11 || status >= 16
    ..['ur_nick'] = us.nickname
    // At the pre-take the participant's `satoshis_now` is the order's stale `last_satoshis`, of its largest amount at publication.
    ..['satoshis_now'] = taken ? last : bookSats + 4321
    ..['maker_locked'] = true
    ..['taker_locked'] = taken
    ..['escrow_locked'] = status == 8 || status >= 9;
  if (taken) data['taker_hash_id'] = us.hashId.hex;
  final trade = buyer ? payoutOf(last) : escrowOf(last);
  if ([6, 7, 8, 10, 11, 13, 14, 15].contains(status)) {
    data['trade_satoshis'] = trade;
  }
  switch (status) {
    case 3:
      final invoice = bond ?? bondInvoice();
      data
        ..['bond_invoice'] = invoice.text
        ..['bond_satoshis'] = invoice.facts.amount.value.toInt()
        ..['price_now'] = 93545.0
        ..['premium_now'] = 2.0;
    case 6 || 7 when !buyer:
      final invoice = escrow ?? escrowInvoice(sats: escrowOf(last));
      data
        ..['escrow_invoice'] = invoice.text
        ..['escrow_satoshis'] = invoice.facts.amount.value.toInt();
    case 6 || 8 when buyer:
      data
        ..['invoice_amount'] = payoutOf(last)
        ..['swap_allowed'] = false
        ..['swap_failure_reason'] = 'On-the-fly submarine swaps are disabled';
    case 8 || 9 || 10:
      data
        ..['asked_for_cancel'] = false
        ..['chat_last_index'] = 3;
    case 11:
      data['statement_submitted'] = false;
    case 15 when buyer:
      data
        ..['retries'] = 2
        ..['next_retry_time'] = '2026-11-13T09:10:00Z'
        ..['failure_reason'] = 'A non-recoverable error has occurred.'
        ..['invoice_expired'] = true
        ..['trade_satoshis'] = trade;
    case 5:
      data
        ..['public_duration'] = 86399
        ..['expiry_reason'] = 3
        ..['expiry_message'] = 'Invoice not submitted';
  }
  return _apply(data, changes);
}

Duration _stepOf(int status) => switch (status) {
  1 => const Duration(hours: 20),
  3 => const Duration(seconds: 190),
  6 || 7 || 8 => const Duration(hours: 2, minutes: 59),
  9 || 10 || 11 => const Duration(hours: 24),
  _ => const Duration(days: 100),
};

Map<String, Object?> _apply(
  Map<String, Object?> data,
  Map<String, Object?> changes,
) {
  for (final MapEntry(:key, :value) in changes.entries) {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
  return data;
}

/// A transport that answers every request with [body].
final class _OneAnswer implements CoordinatorTransport {
  final Object body;

  _OneAnswer(this.body);

  @override
  Future<Result<CoordinatorResponse, CoordinatorTransportFailure>> send(
    CoordinatorRequest request,
  ) async => Ok(
    CoordinatorResponse(
      statusCode: 200,
      headers: const {'content-type': 'application/json'},
      body: utf8.encode(jsonEncode(body)),
    ),
  );
}

/// [json] read as the package reads it for this device's robot, through `CoordinatorClient.fetchOrder`: only answers its parser accepts reach the state machine.
Future<CoordinatorOrder> readOrder(
  Map<String, Object?> json, {
  RobosatsNetwork network = RobosatsNetwork.mainnet,
  String alias = 'temple',
  int orderId = tradeOrderId,
}) async {
  final read = await CoordinatorClient(
    _OneAnswer(json),
  ).fetchOrder(coordinator(alias), network, identity: us, orderId: orderId);
  return switch (read) {
    Ok(:final value) => value,
    Err(failure: CoordinatorResponseMalformed(:final field)) =>
      throw StateError('refused: $field, status ${json['status']}'),
    Err(:final failure) => throw StateError('refused: $failure'),
  };
}

/// [readOrder] as a [TradeAnswer].
Future<TradeAnswer> readAnswer(
  Map<String, Object?> json, {
  RobosatsNetwork network = RobosatsNetwork.mainnet,
}) async => TradeOrderRead(await readOrder(json, network: network));
