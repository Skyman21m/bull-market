import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// What this robot is to the trade it took: taking a sell order makes a buyer, taking a buy order a seller (`Logics.is_buyer`, `api/logics.py`, commit ff1998c).
enum TradeRole {
  buyer,
  seller;

  /// The role of the robot that takes an order of [type].
  static TradeRole takingOrderOf(OrderType type) => switch (type) {
    OrderType.sell => buyer,
    OrderType.buy => seller,
  };
}

/// What a trade was taken with, fixed at the take and never read again from the coordinator: every answer about the trade is checked against it (design note § 3.2).
///
/// It comes from the public order as the book showed it when the user took it, the amount taken, and the taker fee `/api/info/` announced; the coordinator, the network and the order are the ones the take was sent to, never the answer's.
@immutable
final class TradeTerms {
  static const satsPerBitcoin = 100000000;

  final RobosatsNetwork network;

  /// The coordinator of the federation list the take was sent to.
  final Coordinator coordinator;
  final int orderId;
  final TradeRole role;
  final OrderType type;
  final RobosatsCurrency currency;

  /// The fiat amount traded: the order's fixed amount, or the amount chosen in its range.
  final FiatAmount amount;

  /// Whether the order has a range, so that [amount] was chosen at the take.
  final bool isRange;

  /// The premium of the order: the maker's, or for an order priced in sats the one the coordinator computed for the book.
  final Premium premium;

  /// The sats the maker fixed, for an order priced in sats: then the trade is these sats whatever the price (`Logics.satoshis_now`, `api/logics.py:262-275`).
  final Sats? explicitSatoshis;
  final BondSize bondSize;
  final Duration escrowDuration;

  /// The price the book gave, in [currency] per bitcoin, premium included: the order's largest amount over the sats the book said it trades now, the rate the official client estimates with (`TakerEstimate`).
  final double bookPrice;

  /// The taker's fee as a fraction of the trade, as `/api/info/` of [coordinator] announced it (`taker_fee`): 0.00175 with the reference's defaults.
  final double takerFee;

  const TradeTerms._({
    required this.network,
    required this.coordinator,
    required this.orderId,
    required this.role,
    required this.type,
    required this.currency,
    required this.amount,
    required this.isRange,
    required this.premium,
    required this.explicitSatoshis,
    required this.bondSize,
    required this.escrowDuration,
    required this.bookPrice,
    required this.takerFee,
  });

  /// The terms of taking [order] of the book of [network], for [rangeAmount] when the order has a range, with the [takerFee] of the coordinator's `/api/info/`.
  ///
  /// `null` when the order cannot be checked or taken so: no sats at the current price in the book, an amount for a fixed order or none for a range, an amount out of the range, or a fee that is not a fraction.
  static TradeTerms? take(
    PublicOrder order, {
    required RobosatsNetwork network,
    FiatAmount? rangeAmount,
    required double takerFee,
  }) {
    if (!takerFee.isFinite || takerFee < 0 || takerFee >= 1) return null;
    final satoshisNow = order.satoshisNow?.value.toInt();
    if (satoshisNow == null || satoshisNow <= 0) return null;
    final FiatAmount amount;
    switch ((order.amount, rangeAmount)) {
      case (FixedOrderAmount(amount: final fixed), null):
        amount = fixed;
      case (RangeOrderAmount(:final min, :final max), final chosen?)
          when chosen.value >= min.value && chosen.value <= max.value:
        amount = chosen;
      default:
        return null;
    }
    return TradeTerms._(
      network: network,
      coordinator: order.coordinator,
      orderId: order.id,
      role: TradeRole.takingOrderOf(order.type),
      type: order.type,
      currency: order.currency,
      amount: amount,
      isRange: order.amount is RangeOrderAmount,
      premium: order.premium,
      explicitSatoshis: order.explicitSatoshis,
      bondSize: order.bondSize,
      escrowDuration: order.escrowDuration,
      bookPrice: order.amount.max.value / (satoshisNow / satsPerBitcoin),
      takerFee: takerFee,
    );
  }

  /// The sats the trade is worth at the book's price, before any fee: what the coordinator computes as `satoshis_now` for the amount taken, at the price of its own when it does (`Logics.satoshis_now`, `api/logics.py:262-275`).
  double get expectedSatoshis => switch (explicitSatoshis) {
    final sats? => sats.value.toDouble(),
    null => amount.value / bookPrice * satsPerBitcoin,
  };

  /// The bond the order implies at the book's price: its bond size of [expectedSatoshis] (`Logics.gen_taker_hold_invoice`, `api/logics.py:1402-1404`).
  double get expectedBond => expectedSatoshis * bondSize.percent / 100;

  /// The Lightning node keys the federation list gives [coordinator] on [network]: an invoice of the trade must be one of theirs.
  List<String> get nodeKeys => coordinator.nodesPubkeys(network);

  /// The coordinator, the network and the order, never an amount.
  @override
  String toString() =>
      'TradeTerms(${coordinator.shortAlias}#$orderId, ${network.name}, ${role.name})';
}
