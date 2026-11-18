import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_terms.dart';
import 'package:p2p/src/testing/bolt11_test_invoice.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import 'fakes.dart';
import 'trade_orders.dart';

/// The order of the maker tests: number [tradeOrderId] on temple, made by this device's robot ([us]) at [madeAt], taken by [peer] (contract 0) or [third] (a next contract).
///
/// The figures: 100 EUR (or a range of 50 to 200 EUR, taken for 120), a premium of 2 %, a bond of 3 %, an escrow of 3 h, a public duration of 23:59, the coordinator's price of the creation [makerPrice], so that 100 EUR are about [makerSats] sats at the rate of the creation, and the maker fee [makerFee].
final madeAt = tradeNow.subtract(const Duration(seconds: 30));

/// The coordinator's price of the creation: 100 EUR at it, premium included, are 106,900 sats and a fraction.
const makerPrice = 91711.15;

/// The maker fee `/api/info/` announces with the reference's defaults: 0.2 % × 0.125.
const makerFee = 0.00025;

/// The sats of 100 EUR at the rate of the creation, truncated as the coordinator does.
const makerSats = 106900;

/// The maker bond of the order made: 3 % of [makerSats], truncated.
const makerBond = makerSats * 3 ~/ 100;

/// A third robot, the taker of a next contract.
final RobotIdentity third = robotOfTests(2);

/// When contract 0 ends its steps (6 to 8), and a next contract's.
final deadline0 = tradeNow.add(const Duration(hours: 2, minutes: 59));
final deadline1 = deadline0.add(const Duration(hours: 1));

/// What the maker asked: a buy order (a buyer) or a sell order (a seller) on temple.
TradeTerms<MadeSide> madeTerms({
  TradeRole role = TradeRole.buyer,
  RobosatsNetwork network = RobosatsNetwork.mainnet,
  bool range = false,
  double price = makerPrice,
  double fee = makerFee,
  int orderId = tradeOrderId,
}) {
  FiatAmount fiat(double value) => _some(FiatAmount.tryCreate(value));
  final request = _some(
    MakeOrderRequest.tryCreate(
      type: role == TradeRole.buyer ? OrderType.buy : OrderType.sell,
      currency: _some(RobosatsCurrency.fromId(2)),
      amount: range
          ? _some(RangeOrderAmount.tryCreate(fiat(50), fiat(200)))
          : FixedOrderAmount(fiat(100)),
      paymentMethod: 'Revolut Instant SEPA',
      premium: _some(Premium.tryCreate(2)),
      publicDuration: const Duration(seconds: 86340),
      escrowDuration: const Duration(seconds: 10800),
      bondSize: _some(BondSize.tryCreate(3)),
    ),
  );
  final maker = switch (MakerTerms.create(
    network: network,
    coordinator: coordinator('temple'),
    request: request,
    createdPrice: price,
    makerFee: fee,
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  return _some(TradeTerms.made(maker, orderId: orderId));
}

/// The trade's figures fixed at the take for [last] sats, as `Logics.payout_amount` and `Logics.escrow_amount` compute them for the maker: Python's `round`, a half to the even one.
int makerFeeOf(int last) => _roundHalfEven(last * makerFee);
int makerPayoutOf(int last) => _roundHalfEven(last - last * makerFee);
int makerEscrowOf(int last) => _roundHalfEven(last + last * makerFee);

int _roundHalfEven(double value) {
  final floor = value.floorToDouble();
  final rest = value - floor;
  if (rest > 0.5) return floor.toInt() + 1;
  if (rest < 0.5) return floor.toInt();
  return floor.toInt().isEven ? floor.toInt() : floor.toInt() + 1;
}

/// The maker bond invoice of [sats], made at the first read, ten seconds before [tradeNow], for the coordinator's 300 s.
Bolt11TestInvoice makerBondInvoice({
  int sats = makerBond,
  int seed = 11,
  Bolt11Network network = Bolt11Network.mainnet,
  Duration expiry = const Duration(seconds: 300),
}) => Bolt11TestInvoice(
  network: network,
  sats: sats,
  seed: seed,
  createdAt: tradeNow.subtract(const Duration(seconds: 10)),
  expiry: expiry,
  description:
      "temple - Publishing 'Order 42: BUY BTC for 100 EUR' - Maker bond",
);

/// The escrow invoice of a maker seller's contract [take], of [sats] (by default the escrow of [makerSats]).
Bolt11TestInvoice makerEscrowInvoice({
  int take = 0,
  int? sats,
  Bolt11Network network = Bolt11Network.mainnet,
}) => Bolt11TestInvoice(
  network: network,
  sats: sats ?? makerEscrowOf(makerSats),
  seed: 20 + take,
  createdAt: tradeNow.subtract(const Duration(minutes: 1)),
  expiry: const Duration(seconds: 10800),
  description: "temple - Escrow amount for 'Order 42'",
);

/// The answer of `OrderView.get` (`api/views.py:226-528`, commit ff1998c) about order [tradeOrderId] to this device's robot, its maker as [role], with the JSON types the reference writes.
///
/// [status] is the order's; from 6 on, [taker] is the contract's taker and [deadline] its deadline at 6, 7 and 8 ([deadline0] by default); [last] is the order's `last_satoshis`; for a range, [taken] is the amount the contract took (none at 0, 1 and 2, nor at 5 without [taker]); [changes] is applied last, a `null` value removing its key.
Map<String, Object?> makerOrderJson(
  int status, {
  TradeRole role = TradeRole.buyer,
  bool range = false,
  int last = makerSats,
  RobotIdentity? taker,
  DateTime? deadline,
  double taken = 120,
  Bolt11TestInvoice? bond,
  Bolt11TestInvoice? escrow,
  Map<String, Object?> changes = const {},
}) {
  final buyer = role == TradeRole.buyer;
  final contractTaker = taker ?? (status >= 6 ? peer : null);
  final hasTaker = contractTaker != null;
  final data = <String, Object?>{
    'id': tradeOrderId,
    'status': status,
    'created_at': madeAt.toIso8601String(),
    'expires_at': (switch (status) {
      0 => madeAt.add(const Duration(seconds: 300)),
      1 || 2 || 5 => madeAt.add(const Duration(seconds: 86340)),
      6 || 7 || 8 => deadline ?? deadline0,
      9 || 10 => tradeNow.add(const Duration(hours: 24)),
      11 => tradeNow.add(const Duration(days: 1)),
      _ => tradeNow.add(const Duration(days: 100)),
    }).toIso8601String(),
    'type': buyer ? 0 : 1,
    'currency': 2,
    'amount': range
        ? (hasTaker ? taken.toStringAsFixed(8) : null)
        : '100.00000000',
    'has_range': range,
    'min_amount': range ? '50.00000000' : null,
    'max_amount': range ? '200.00000000' : null,
    'payment_method': 'Revolut Instant SEPA',
    'is_explicit': false,
    'premium': '2.00',
    'satoshis': null,
    'maker': 7,
    'taker': hasTaker ? 8 : null,
    'escrow_duration': 10800,
    'bond_size': '3.00',
    'latitude': null,
    'longitude': null,
    'is_maker': true,
    'is_taker': false,
    'is_participant': true,
    'has_password': false,
    'total_secs_exp': switch (status) {
      0 => 300,
      1 => 86340,
      6 || 7 || 8 => 10800,
      9 || 10 => 86400,
      11 => 86400,
      2 || 5 => 0,
      _ => 8640000,
    },
    'maker_nick': us.nickname,
    'maker_hash_id': us.hashId.hex,
    'description': null,
    'maker_status': 'Active',
    if (hasTaker) 'taker_status': 'Active',
  };
  if (status >= 1 && status < 6) {
    data
      ..['price_now'] = 93545.0
      ..['premium_now'] = 2.0;
  }
  data
    ..['is_buyer'] = buyer
    ..['is_seller'] = !buyer
    ..['taker_nick'] = hasTaker ? contractTaker.nickname : 'None'
    ..['status_message'] = 'Some label'
    // `order.is_fiat_sent`: set by the buyer's « confirm » (`api/logics.py:1696`), cleared by « undo » only (`:1748`): set at 10, and at 13 to 15, reached only through 10 here; 11 (a dispute opened at 9 or 10) is the test's (`changes`).
    ..['is_fiat_sent'] = const [10, 13, 14, 15].contains(status)
    ..['is_disputed'] = status == 11 || status >= 16
    ..['ur_nick'] = us.nickname
    ..['satoshis_now'] = last
    // Whether each hold invoice is LOCKED now (`api/views.py:326-343`): the maker bond from the publication to the trade's end, returned or settled at 4, 5 and 11 to 18 (`Logics.return_bond`, `settle_bond`, `api/logics.py:1561-1600`; a dispute settles the escrow and both bonds, `:503-506`; the seller's « confirm » returns both bonds before paying the buyer, `:1724-1727`); the taker bond from the contract (6) to 10; the escrow from its lock (8, or 9 after 7) to 10.
    ..['maker_locked'] = const [1, 2, 3, 6, 7, 8, 9, 10].contains(status)
    ..['taker_locked'] = status >= 6 && status <= 10
    ..['escrow_locked'] = status >= 8 && status <= 10;
  if (hasTaker) {
    data
      ..['taker_hash_id'] = contractTaker.hashId.hex
      ..['taker_nostr_pubkey'] = 'None';
  }
  final trade = buyer ? makerPayoutOf(last) : makerEscrowOf(last);
  // `trade_satoshis` only while both bonds are LOCKED, at the statuses `api/views.py:346-361` lists (6, 7, 8, 10, 11, 12, 13, 14, 15, not 9): with the bonds locked only at 6, 7, 8 and 10 (above), never at 9, 11 to 15, but for the buyer's expired invoice at 15 (below).
  if ([6, 7, 8, 10].contains(status)) {
    data['trade_satoshis'] = trade;
  }
  switch (status) {
    case 0:
      final invoice = bond ?? makerBondInvoice();
      data
        ..['bond_invoice'] = invoice.text
        ..['bond_satoshis'] = invoice.facts.amount.value.toInt();
    case 6 || 7 when !buyer:
      final invoice = escrow ?? makerEscrowInvoice(sats: makerEscrowOf(last));
      data
        ..['escrow_invoice'] = invoice.text
        ..['escrow_satoshis'] = invoice.facts.amount.value.toInt();
    case 6 || 8 when buyer:
      data
        ..['invoice_amount'] = makerPayoutOf(last)
        ..['swap_allowed'] = false
        ..['swap_failure_reason'] = 'On-the-fly submarine swaps are disabled';
    // The chat's fields at 8 for the seller (the buyer's 8 is the payout's branch, above), 9 and 10 (`api/views.py:438-460`).
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
        ..['expiry_reason'] = hasTaker ? 3 : 0
        ..['expiry_message'] = hasTaker
            ? 'Invoice not submitted'
            : 'Expired not taken';
  }
  // The renewal's fields (`api/views.py:489-498`), not for the buyer at 15, whose branch is the routing's (`:466-487`); the trade summary of 13 to 15 (`Logics.summarize_trade`) is not played.
  if (const [5, 13, 14].contains(status) || (status == 15 && !buyer)) {
    data
      ..['public_duration'] = 86340
      ..['bond_size'] = '3.00';
  }
  for (final MapEntry(:key, :value) in changes.entries) {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
  return data;
}

T _some<T>(T? value) => value ?? (throw StateError('missing'));
