/// Answers of `OrderView` about one order, built as the reference coordinator builds them (commit ff1998c): derived from its code, never recorded, since no trade was ever made to record them.
library;

import 'package:robosats/robosats.dart';

import 'coordinator.dart';
import 'pgp.dart';

const _testnet = RobosatsNetwork.testnet;

/// The order of every answer built here.
const testOrderId = 42;

/// This device's robot, the taker of the tests: index 0 of the example Garage Key of the RoboSats repository, a token published there and never a secret.
final _us = interopIdentity;

/// The peer, the maker of the tests: index 1 of the same example key.
final _peer = interopPeerIdentity;

/// Fake hold invoices, built by the test: a coordinator's are about 400 characters of bech32.
final testBondInvoice = 'lntb30u1pfakebondinvoice${'q' * 360}';
final testEscrowInvoice = 'lntb1m1pfakeescrowinvoice${'p' * 360}';

/// Who this device's robot is to the order of an answer.
enum OrderRole { maker, taker, preTaker, outsider }

/// The answer of `OrderView.get` (`api/views.py:226-528`, commit ff1998c) about order [testOrderId] to this device's robot, built step by step as the view builds it, for an order in [status] (the stored one: a pre-take is asked with status 1).
///
/// [buyer] says whether this device's robot buys bitcoin, so the order's type follows from it and [role]; [range] makes a range order of 100-300 EUR taken for 150.5.
/// [bondsLocked] and [escrowLocked] are what the hold invoices of the coordinator say; [place] gives the order coordinates; [changes] is applied last, a `null` value removing its key.
///
/// Every value has the JSON type the reference writes (checked against `api/views.py`, `api/logics.py` and `docs/assets/schemas/api-latest.yaml`): the serializer's decimals as strings, the raw `Decimal`s a view adds as numbers (the coordinates of a participant, `premium_now`, the summary's fiat amounts and percentages, `routing_budget_sats`), Python floats as numbers with a fraction, integers as integers.
Map<String, Object?> orderAnswer(
  int status, {
  OrderRole role = OrderRole.taker,
  bool buyer = true,
  bool range = false,
  bool password = false,
  bool place = true,
  bool bondsLocked = true,
  bool escrowLocked = true,
  Map<String, Object?> changes = const {},
}) {
  final isMaker = role == OrderRole.maker;
  final isTaker = role == OrderRole.taker || role == OrderRole.preTaker;
  final makerIdentity = isMaker ? _us : _peer;
  final takerIdentity = switch (role) {
    OrderRole.maker => status >= 6 ? _peer : null,
    OrderRole.taker => _us,
    _ => null,
  };
  // The maker buys when this robot buys as maker, or sells to this robot as taker.
  final makerBuys = isMaker == buyer;
  final taken = takerIdentity != null;
  final data = <String, Object?>{
    'id': testOrderId,
    'status': status,
    'created_at': '2026-11-13T08:00:00.123456Z',
    'expires_at': '2026-11-13T11:00:00Z',
    'type': makerBuys ? 0 : 1,
    'currency': 2,
    'amount': range ? (taken ? '150.50000000' : null) : '150.00000000',
    'has_range': range,
    'min_amount': range ? '100.00000000' : null,
    'max_amount': range ? '300.00000000' : null,
    'payment_method': 'SEPA Revolut',
    'is_explicit': false,
    'premium': '1.50',
    'satoshis': null,
    'maker': 7,
    'taker': taken ? 8 : null,
    'escrow_duration': 10799,
    'bond_size': '3.00',
    // The serializer's `DecimalField`s, strings (`api/serializers.py:83-107`).
    'latitude': place ? '48.85660000' : null,
    'longitude': place ? '2.35220000' : null,
    'is_maker': isMaker,
    'is_taker': isTaker,
    'is_participant': isMaker || isTaker,
    'has_password': password,
    'total_secs_exp': _stepSeconds(status),
    'maker_nick': makerIdentity.nickname,
    'maker_hash_id': makerIdentity.hashId.hex,
    'maker_nostr_pubkey': makerIdentity.nostrKeyPair().publicKeyHex,
    'description': 'Revolut only, € please.',
    'maker_status': 'Active',
    if (taken) 'taker_status': 'Seen recently',
  };
  if (role == OrderRole.outsider) {
    data
      ..['price_now'] = 91234.5
      ..['premium_now'] = 1.5
      ..['satoshis_now'] = 164414;
    if (password) {
      data
        ..['latitude'] = null
        ..['longitude'] = null
        ..['description'] = null;
    }
    return _apply(data, changes);
  }
  if (status >= 1 && status < 6) {
    data
      ..['price_now'] = 91234.5
      ..['premium_now'] = 1.5;
  }
  data
    ..['is_buyer'] = buyer
    ..['is_seller'] = !buyer
    ..['taker_nick'] = takerIdentity?.nickname ?? 'None';
  if (takerIdentity != null) {
    data
      ..['taker_hash_id'] = takerIdentity.hashId.hex
      ..['taker_nostr_pubkey'] = takerIdentity.nostrKeyPair().publicKeyHex;
  }
  data
    ..['status_message'] = 'Some label'
    ..['is_fiat_sent'] = status == 10
    ..['is_disputed'] = status == 11 || status >= 16
    ..['ur_nick'] = _us.nickname
    // The raw `Decimal`s of the order, which the encoder writes as numbers (`api/views.py:320-321`).
    ..['latitude'] = place ? 48.8566 : null
    ..['longitude'] = place ? 2.3522 : null
    ..['satoshis_now'] = 164414
    ..['maker_locked'] = status >= 1 && status != 5
    ..['taker_locked'] = status >= 6 && bondsLocked
    ..['escrow_locked'] = (status == 8 || status >= 9) && escrowLocked;
  if ([6, 7, 8, 12, 10, 11, 13, 14, 15].contains(status) && bondsLocked) {
    data['trade_satoshis'] = buyer ? 164126 : 164702;
  }
  if (status == 0 && isMaker) {
    data
      ..['bond_invoice'] = testBondInvoice
      ..['bond_satoshis'] = 4932
      ..['expires_at'] = '2026-11-13T08:05:00.654321Z';
  } else if (status == 1 && role == OrderRole.preTaker) {
    data
      ..['status'] = 3
      ..['total_secs_exp'] = 150
      ..['amount'] = range ? '150.50000000' : '150.00000000'
      ..['bond_invoice'] = testBondInvoice
      ..['bond_satoshis'] = 4932
      ..['expires_at'] = '2026-11-13T08:02:30.000001Z';
  } else if (!buyer && (status == 6 || status == 7)) {
    if (bondsLocked) {
      data
        ..['escrow_invoice'] = testEscrowInvoice
        ..['escrow_satoshis'] = 164702;
    }
  } else if (buyer && (status == 6 || status == 8)) {
    if (bondsLocked) {
      data
        ..['invoice_amount'] = 164126
        ..['swap_allowed'] = false
        ..['swap_failure_reason'] = 'On-the-fly submarine swaps are disabled';
    }
  } else if ([8, 9, 10].contains(status)) {
    if (bondsLocked && escrowLocked) data['asked_for_cancel'] = false;
    data['chat_last_index'] = 3;
  } else if (status == 11) {
    data['statement_submitted'] = false;
  } else if (status == 15 && buyer) {
    data
      ..['retries'] = 2
      ..['next_retry_time'] = '2026-11-13T09:10:00.5Z'
      ..['failure_reason'] =
          'All possible routes were tried and failed permanently. Or there were no routes to the destination at all.'
      ..['invoice_expired'] = true
      ..['trade_satoshis'] = 164126;
  } else if ([5, 14, 13, 15].contains(status)) {
    data
      ..['public_duration'] = 86399
      ..['bond_size'] = '3.00';
    if (status != 5) data.addAll(_summaries(buyer: buyer, isMaker: isMaker));
    if (status == 5) {
      data
        ..['expiry_reason'] = 2
        ..['expiry_message'] = 'Escrow not locked';
    }
  }
  return _apply(data, changes);
}

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

/// `Order.t_to_expire` with the defaults of the code (`api/models/order.py:310-339`).
int _stepSeconds(int status) => switch (status) {
  0 => 300,
  1 => 86399,
  3 => 150,
  6 || 7 || 8 => 10799,
  9 || 10 => 86400,
  11 => 86400,
  >= 13 => 8640000,
  _ => 0,
};

/// The summaries of `Logics.summarize_trade` (`api/logics.py:2047-2139`) for a Lightning payout.
Map<String, Object?> _summaries({required bool buyer, required bool isMaker}) {
  Map<String, Object?> side({required bool isBuyer, required bool ofMaker}) => {
    'trade_fee_percent': ofMaker ? 0.00025 : 0.00175,
    'bond_size_sats': 4932,
    'bond_size_percent': 3.0,
    'is_buyer': isBuyer,
    if (isBuyer) ...{
      'sent_fiat': 150.0,
      'received_sats': 164126,
      'payment_hash': 'f' * 64,
      'preimage': 'processing',
      'trade_fee_sats': 288,
    } else ...{
      'sent_sats': 164702,
      'received_fiat': 150.0,
      'trade_fee_sats': 288,
    },
  };
  final makerBuys = isMaker == buyer;
  return {
    'maker_summary': side(isBuyer: makerBuys, ofMaker: true),
    'taker_summary': side(isBuyer: !makerBuys, ofMaker: false),
    'platform_summary': {
      'contract_exchange_rate': 91234.56,
      'contract_timestamp': '2026-11-13T08:03:00Z',
      'contract_total_time': 1234.5,
      // A `DecimalField` of 3 places, raw (`api/logics.py:2128`).
      'routing_budget_sats': 0.0,
      'trade_revenue_sats': 576,
    },
  };
}

/// The error body of `new_error` (`api/errors.py:120-138`).
Map<String, Object?> orderError(int code, [String message = 'Some text.']) => {
  'error_code': code,
  'bad_request': message,
};

/// The order a read of [answer] gives this device's robot on temple's testnet instance, the last read a cancel is guarded with.
CoordinatorOrder readOrder(
  Map<String, Object?> answer, {
  String alias = 'temple',
  RobosatsNetwork network = _testnet,
  RobotIdentity? identity,
}) => expectOk(
  CoordinatorOrder.parse(
    answer,
    coordinatorNamed(alias),
    network,
    orderId: answer['id'] is int ? answer['id'] as int : testOrderId,
    identity: identity ?? _us,
  ),
);

/// The order read at [status], as [orderAnswer] builds it.
CoordinatorOrder readOrderAt(int status, {OrderRole role = OrderRole.taker}) =>
    readOrder(orderAnswer(status, role: role));
