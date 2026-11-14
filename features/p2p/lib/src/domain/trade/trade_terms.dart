import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../trade_record.dart' show TradeRole;
import 'trade_storable.dart';
import 'trade_tolerances.dart';

export '../trade_record.dart' show TradeRole;

/// The role of the robot that takes an order of [type]: taking a sell order makes a buyer, taking a buy order a seller (`Logics.is_buyer`, `api/logics.py`, commit ff1998c).
TradeRole tradeRoleTaking(OrderType type) => switch (type) {
  OrderType.sell => TradeRole.buyer,
  OrderType.buy => TradeRole.seller,
};

/// Why a take cannot be checked, so is not made: a type, the take use case gives the user its text (#87, #88).
sealed class TradeTermsRefusal extends Failure {
  const TradeTermsRefusal();
}

/// The coordinator announces a taker fee above [TradeTolerances.takerFeeCeiling].
final class TakerFeeTooHigh extends TradeTermsRefusal {
  const TakerFeeTooHigh();
}

/// The order gives nothing to check a take against: no sats at the current price, or no valid amount.
final class TradeTermsUnusable extends TradeTermsRefusal {
  const TradeTermsUnusable();
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

  /// The terms of taking [order], as the book listed it on [network], for [rangeAmount] when the order has a range, with the [takerFee] of the coordinator's `/api/info/`.
  ///
  /// Build them from a fresh read of the order just before the take (the book reloaded, or [takeRead]), never from a book left open: the bond and the trade's sats are checked against this price within [TradeTolerances.price].
  /// Refused with [TakerFeeTooHigh] above [TradeTolerances.takerFeeCeiling], and with [TradeTermsUnusable] when the order cannot be checked so: no sats at the current price, an amount for a fixed order or none for a range, an amount out of the range.
  static Result<TradeTerms, TradeTermsRefusal> take(
    PublicOrder order, {
    required RobosatsNetwork network,
    FiatAmount? rangeAmount,
    required double takerFee,
  }) => _of(
    network: network,
    coordinator: order.coordinator,
    orderId: order.id,
    type: order.type,
    currency: order.currency,
    orderAmount: order.amount,
    rangeAmount: rangeAmount,
    premium: order.premium,
    explicitSatoshis: order.explicitSatoshis,
    bondSize: order.bondSize,
    escrowDuration: order.escrowDuration,
    satoshisNow: order.satoshisNow,
    takerFee: takerFee,
  );

  /// The terms of taking [order], read just before the take by the robot that takes it, which is not one of its participants yet (`GET /api/order/` of a public order, `api/views.py:287-299`).
  ///
  /// Refused as [take] refuses, and with [TradeTermsUnusable] for a read that is not of a public order this robot does not take part in.
  static Result<TradeTerms, TradeTermsRefusal> takeRead(
    CoordinatorOrder order, {
    FiatAmount? rangeAmount,
    required double takerFee,
  }) {
    final premium = order.premium;
    if (order.status != CoordinatorOrderStatus.public ||
        order.isParticipant ||
        premium == null) {
      return const Err(TradeTermsUnusable());
    }
    return _of(
      network: order.network,
      coordinator: order.coordinator,
      orderId: order.id,
      type: order.type,
      currency: order.currency,
      orderAmount: order.amount,
      rangeAmount: rangeAmount,
      premium: premium,
      explicitSatoshis: order.explicitSatoshis,
      bondSize: order.bondSize,
      escrowDuration: order.escrowDuration,
      satoshisNow: order.satoshisNow,
      takerFee: takerFee,
    );
  }

  static Result<TradeTerms, TradeTermsRefusal> _of({
    required RobosatsNetwork network,
    required Coordinator coordinator,
    required int orderId,
    required OrderType type,
    required RobosatsCurrency currency,
    required OrderAmount orderAmount,
    required FiatAmount? rangeAmount,
    required Premium premium,
    required Sats? explicitSatoshis,
    required BondSize bondSize,
    required Duration escrowDuration,
    required Sats? satoshisNow,
    required double takerFee,
  }) {
    if (!takerFee.isFinite || takerFee < 0) {
      return const Err(TradeTermsUnusable());
    }
    if (takerFee > TradeTolerances.takerFeeCeiling) {
      return const Err(TakerFeeTooHigh());
    }
    final sats = satoshisNow?.value.toInt();
    if (sats == null || sats <= 0) return const Err(TradeTermsUnusable());
    final FiatAmount amount;
    switch ((orderAmount, rangeAmount)) {
      case (FixedOrderAmount(amount: final fixed), null):
        amount = fixed;
      case (RangeOrderAmount(:final min, :final max), final chosen?)
          when chosen.value >= min.value && chosen.value <= max.value:
        amount = chosen;
      default:
        return const Err(TradeTermsUnusable());
    }
    return Ok(
      TradeTerms._(
        network: network,
        coordinator: coordinator,
        orderId: orderId,
        role: tradeRoleTaking(type),
        type: type,
        currency: currency,
        amount: amount,
        isRange: orderAmount is RangeOrderAmount,
        premium: premium,
        explicitSatoshis: explicitSatoshis,
        bondSize: bondSize,
        escrowDuration: escrowDuration,
        bookPrice: orderAmount.max.value / (sats / satsPerBitcoin),
        takerFee: takerFee,
      ),
    );
  }

  /// The exact, storable form of these terms: store it at the take, with the trade (#87).
  TradeTermsRecord get record => TradeTermsRecord(
    version: TradeTermsRecord.currentVersion,
    network: network.name,
    coordinatorAlias: coordinator.shortAlias,
    orderId: orderId,
    role: role.name,
    type: type.wire,
    currencyId: currency.id,
    amount: amount.value,
    isRange: isRange,
    premiumPercent: premium.percent,
    explicitSatoshis: explicitSatoshis?.value.toInt(),
    bondSizePercent: bondSize.percent,
    escrowSeconds: escrowDuration.inSeconds,
    bookPrice: bookPrice,
    takerFee: takerFee,
  );

  /// The terms [record] holds, or why not: [TradeCoordinatorGone] when its coordinator is no longer in the federation list on its network (the trade is shown, never resumed), [TradeRecordMalformed] when it is not one [record] wrote (an unknown version or network, a role that does not follow from the order's type, any value out of the bounds the take checks).
  ///
  /// The terms are set once, at the take: their record is never written again (#87).
  static Result<TradeTerms, TradeRecordRefusal> restore(
    TradeTermsRecord record,
  ) {
    const refused = Err<TradeTerms, TradeRecordRefusal>(TradeRecordMalformed());
    if (record.version != TradeTermsRecord.currentVersion) return refused;
    final network = RobosatsNetwork.values
        .where((value) => value.name == record.network)
        .firstOrNull;
    final coordinator = Federation.robosats.byAlias(record.coordinatorAlias);
    final type = OrderType.fromWire(record.type);
    final role = TradeRole.values
        .where((value) => value.name == record.role)
        .firstOrNull;
    final currency = RobosatsCurrency.fromId(record.currencyId);
    final amount = FiatAmount.tryCreate(record.amount);
    final premium = Premium.tryCreate(record.premiumPercent);
    final bondSize = BondSize.tryCreate(record.bondSizePercent);
    final explicit = record.explicitSatoshis;
    if (network == null) return refused;
    if (coordinator == null || !coordinator.isOn(network)) {
      return const Err(TradeCoordinatorGone());
    }
    if (type == null ||
        role == null ||
        role != tradeRoleTaking(type) ||
        currency == null ||
        amount == null ||
        premium == null ||
        bondSize == null ||
        record.orderId < 1 ||
        (explicit != null && explicit < 1) ||
        record.escrowSeconds < 1800 ||
        record.escrowSeconds > 36000 ||
        !record.bookPrice.isFinite ||
        record.bookPrice <= 0 ||
        !record.takerFee.isFinite ||
        record.takerFee < 0 ||
        record.takerFee > TradeTolerances.takerFeeCeiling) {
      return refused;
    }
    return Ok(
      TradeTerms._(
        network: network,
        coordinator: coordinator,
        orderId: record.orderId,
        role: role,
        type: type,
        currency: currency,
        amount: amount,
        isRange: record.isRange,
        premium: premium,
        explicitSatoshis: explicit == null ? null : Sats.fromInt(explicit),
        bondSize: bondSize,
        escrowDuration: Duration(seconds: record.escrowSeconds),
        bookPrice: record.bookPrice,
        takerFee: record.takerFee,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TradeTerms && other.record == record;

  @override
  int get hashCode => record.hashCode;

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
