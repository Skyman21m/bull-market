import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../trade_record.dart' show TradeRole;
import 'exact_ratio.dart';
import 'maker_terms.dart';
import 'sats_at_price.dart';
import 'trade_storable.dart';
import 'trade_tolerances.dart';

export '../trade_record.dart' show TradeRole;
export 'maker_terms.dart';

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

/// What depends on the side of a trade in its terms (design note `docs/design/phase-3-making-an-order.md` § 3.2): [TakenSide] for a trade taken here, [MadeSide] for an order made here.
@immutable
sealed class TradeSide {
  const TradeSide();
}

/// What a taker's terms hold beside the order's: the amount taken, the book's price and the taker fee, fixed at the take (phase 2).
@immutable
final class TakenSide extends TradeSide {
  /// The fiat amount traded: the order's fixed amount, or the amount chosen in its range.
  final FiatAmount amount;

  /// Whether the order has a range, so that [amount] was chosen at the take.
  final bool isRange;

  /// The sats the maker fixed, for an order priced in sats: then the trade is these sats whatever the price (`Logics.satoshis_now`, `api/logics.py:262-275`).
  final Sats? explicitSatoshis;

  /// The price the book gave, in the order's currency per bitcoin, premium included: the order's largest amount over the sats the book said it trades now, the rate the official client estimates with (`TakerEstimate`).
  final double bookPrice;

  /// The taker's fee as a fraction of the trade, as `/api/info/` of the coordinator announced it (`taker_fee`): 0.00175 with the reference's defaults.
  final double takerFee;

  const TakenSide._({
    required this.amount,
    required this.isRange,
    required this.explicitSatoshis,
    required this.bookPrice,
    required this.takerFee,
  });

  /// The sats the trade is worth at the book's price, before any fee: what the coordinator computes as `satoshis_now` for the amount taken, at the price of its own when it does (`Logics.satoshis_now`, `api/logics.py:262-275`).
  double get expectedSatoshis => switch (explicitSatoshis) {
    final sats? => sats.value.toDouble(),
    null => amount.value / bookPrice * TradeTerms.satsPerBitcoin,
  };

  /// The most an escrow invoice of this trade may ask (#97): the most the state machine lets the seller's escrow be without a warning, rounded down to the sat.
  ///
  /// The trade's sats fixed at the bond's lock (`last_satoshis`) are within [TradeTolerances.price] and [TradeTolerances.roundingSats] of [expectedSatoshis] (`TradePriceOutsideOrder`), and the escrow adds at most the announced [takerFee] of them and [TradeTolerances.feeSats] (`TakerFeeAboveAnnounced`, `Logics.escrow_amount`, `api/logics.py:733-749`). It is what the seller accepts by taking the order, as [TradeTerms.bondCeiling] for the bond: the wallet pays the invoice's own decoded amount, never more than this.
  Sats get escrowCeiling => Sats.fromInt(
    ((expectedSatoshis * (1 + TradeTolerances.price) +
                    TradeTolerances.roundingSats) *
                (1 + takerFee) +
            TradeTolerances.feeSats)
        .floor(),
  );

  /// What a taker buyer receives for a trade whose sats the coordinator fixed at [lastSatoshis] (`last_satoshis`, `satoshis_now` to a participant from 6 on, `api/views.py:324`): its `invoice_amount`, `round(last_satoshis − last_satoshis × taker fee)` (`Logics.payout_amount`, `api/logics.py:650-669`), with the taker fee of these terms, rounded half to even ([payoutLessFee]); at 9, where the coordinator gives no `trade_satoshis` (`api/views.py:345-371`), the sats the owner's payment rule compares (#249, design note `docs/design/phase-3-taken-order-price-check.md` § 3).
  Sats payoutAt(Sats lastSatoshis) => payoutLessFee(lastSatoshis, takerFee);

  @override
  bool operator ==(Object other) =>
      other is TakenSide &&
      other.amount == amount &&
      other.isRange == isRange &&
      other.explicitSatoshis == explicitSatoshis &&
      other.bookPrice == bookPrice &&
      other.takerFee == takerFee;

  @override
  int get hashCode =>
      Object.hash(amount, isRange, explicitSatoshis, bookPrice, takerFee);

  /// Never an amount.
  @override
  String toString() => 'TakenSide';
}

/// What a maker's terms hold beside the order's: what the maker asked ([maker]), only; what a take of a range chooses belongs to its contract, kept in the trail, since it changes at each contract (`api/logics.py:1210-1213`, `:1329-1330`).
@immutable
final class MadeSide extends TradeSide {
  final MakerTerms maker;

  const MadeSide._(this.maker);

  @override
  bool operator ==(Object other) => other is MadeSide && other.maker == maker;

  @override
  int get hashCode => maker.hashCode;

  /// Never an amount.
  @override
  String toString() => 'MadeSide';
}

/// What a trade was taken or made with, fixed before its request left and never read again from the coordinator: every answer about the trade is checked against it (the phase 2 design note § 3.2; for a maker, `docs/design/phase-3-making-an-order.md` § 3.2).
///
/// It holds what both sides share (the network, the coordinator, the order, the role, the order's type, currency, premium, bond size and escrow duration) and, in [side], what depends on the side: a taker's ([TakenSide], from the public order as the book showed it when the user took it, the amount taken, and the taker fee `/api/info/` announced) or a maker's ([MadeSide], the [MakerTerms] it asked). The coordinator, the network and the order are the ones the request was sent to, never the answer's.
/// [S] is the side when it is known where the terms are made: the take's own terms are `TradeTerms<TakenSide>` (read with [TakenTradeTerms]), a maker's `TradeTerms<MadeSide>`; every factory instantiates the type of its side, so `terms is TradeTerms<TakenSide>` holds exactly when [side] is a [TakenSide].
@immutable
final class TradeTerms<S extends TradeSide> {
  static const satsPerBitcoin = 100000000;

  final RobosatsNetwork network;

  /// The coordinator of the federation list the request was sent to.
  final Coordinator coordinator;
  final int orderId;
  final TradeRole role;
  final OrderType type;
  final RobosatsCurrency currency;

  /// The premium of the order: the maker's, or for an order priced in sats the one the coordinator computed at the price now (the book's `premium`, a robot's `premium_now`).
  final Premium premium;
  final BondSize bondSize;
  final Duration escrowDuration;

  /// What depends on the side of the trade.
  final S side;

  const TradeTerms._({
    required this.network,
    required this.coordinator,
    required this.orderId,
    required this.role,
    required this.type,
    required this.currency,
    required this.premium,
    required this.bondSize,
    required this.escrowDuration,
    required this.side,
  });

  /// The terms of taking [order], as the book listed it on [network], for [rangeAmount] when the order has a range, with the [takerFee] of the coordinator's `/api/info/`.
  ///
  /// Build them from a fresh read of the order just before the take (the book reloaded, or [takeRead]), never from a book left open: the bond and the trade's sats are checked against this price within [TradeTolerances.price].
  /// Refused with [TakerFeeTooHigh] above [TradeTolerances.takerFeeCeiling], and with [TradeTermsUnusable] when the order cannot be checked so: no sats at the current price, an amount for a fixed order or none for a range, an amount out of the range.
  static Result<TradeTerms<TakenSide>, TradeTermsRefusal> take(
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
  /// The premium of an order priced in sats is the one the coordinator computes at the price now, `premium_now` (`Logics.price_and_premium_now`, `api/views.py:289`), the very one the book gives as its `premium` (`api/views.py:809-812`): the order's own `premium` is `null` when the official client made it (`frontend/src/models/Order.model.ts:206`), and the state machine never checks the premium of such an order (`TradeStatus`).
  static Result<TradeTerms<TakenSide>, TradeTermsRefusal> takeRead(
    CoordinatorOrder order, {
    FiatAmount? rangeAmount,
    required double takerFee,
  }) {
    final premium = order.isExplicit ? order.premiumNow : order.premium;
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

  static Result<TradeTerms<TakenSide>, TradeTermsRefusal> _of({
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
      TradeTerms<TakenSide>._(
        network: network,
        coordinator: coordinator,
        orderId: orderId,
        role: tradeRoleTaking(type),
        type: type,
        currency: currency,
        premium: premium,
        bondSize: bondSize,
        escrowDuration: escrowDuration,
        side: TakenSide._(
          amount: amount,
          isRange: orderAmount is RangeOrderAmount,
          explicitSatoshis: explicitSatoshis,
          bookPrice: orderAmount.max.value / (sats / satsPerBitcoin),
          takerFee: takerFee,
        ),
      ),
    );
  }

  /// The terms of the order [orderId] that [maker] made, once a read of it shows this robot as its maker (design note § 3.4): `null` unless [orderId] is a positive order number.
  ///
  /// Everything but the order's number is the maker's: the network, the coordinator, the role ([tradeRoleMaking]), the type, currency, premium, bond size and escrow duration of [MakerTerms.request].
  static TradeTerms<MadeSide>? made(MakerTerms maker, {required int orderId}) {
    if (orderId < 1) return null;
    final request = maker.request;
    return TradeTerms<MadeSide>._(
      network: maker.network,
      coordinator: maker.coordinator,
      orderId: orderId,
      role: maker.role,
      type: request.type,
      currency: request.currency,
      premium: request.premium,
      bondSize: request.bondSize,
      escrowDuration: request.escrowDuration,
      side: MadeSide._(maker),
    );
  }

  /// The terms of the order [orderId] made with the terms [record] holds: refused as [MakerTerms.restore] refuses, and as [TradeRecordMalformed] for an order number that is not positive.
  static Result<TradeTerms<MadeSide>, TradeRecordRefusal> restoreMade(
    MakerTermsRecord record, {
    required int orderId,
  }) => switch (MakerTerms.restore(record)) {
    Ok(:final value) => switch (made(value, orderId: orderId)) {
      final terms? => Ok(terms),
      null => const Err(TradeRecordMalformed()),
    },
    Err(:final failure) => Err(failure),
  };

  /// The exact, storable form of a taker's terms, of which [taken] is the side ([TakenTradeTerms.record]).
  TradeTermsRecord _takenRecord(TakenSide taken) => TradeTermsRecord(
    version: TradeTermsRecord.currentVersion,
    network: network.name,
    coordinatorAlias: coordinator.shortAlias,
    orderId: orderId,
    role: role.name,
    type: type.wire,
    currencyId: currency.id,
    amount: taken.amount.value,
    isRange: taken.isRange,
    premiumPercent: premium.percent,
    explicitSatoshis: taken.explicitSatoshis?.value.toInt(),
    bondSizePercent: bondSize.percent,
    escrowSeconds: escrowDuration.inSeconds,
    bookPrice: taken.bookPrice,
    takerFee: taken.takerFee,
  );

  /// The terms [record] holds, or why not: [TradeCoordinatorGone] when its coordinator is no longer in the federation list on its network (the trade is shown, never resumed), [TradeRecordMalformed] when it is not one [record] wrote (an unknown version or network, a role that does not follow from the order's type, any value out of the bounds the take checks).
  ///
  /// The terms are set once, at the take: their record is never written again (#87).
  static Result<TradeTerms<TakenSide>, TradeRecordRefusal> restore(
    TradeTermsRecord record,
  ) {
    const refused = Err<TradeTerms<TakenSide>, TradeRecordRefusal>(
      TradeRecordMalformed(),
    );
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
      TradeTerms<TakenSide>._(
        network: network,
        coordinator: coordinator,
        orderId: record.orderId,
        role: role,
        type: type,
        currency: currency,
        premium: premium,
        bondSize: bondSize,
        escrowDuration: Duration(seconds: record.escrowSeconds),
        side: TakenSide._(
          amount: amount,
          isRange: record.isRange,
          explicitSatoshis: explicit == null ? null : Sats.fromInt(explicit),
          bookPrice: record.bookPrice,
          takerFee: record.takerFee,
        ),
      ),
    );
  }

  /// What these terms are equal by: a taker's record, or a maker's order with the record of what it asked.
  Object get _identity => switch (side) {
    final TakenSide taken => _takenRecord(taken),
    MadeSide(:final maker) => (orderId, maker.record),
  };

  @override
  bool operator ==(Object other) =>
      other is TradeTerms && other._identity == _identity;

  @override
  int get hashCode => _identity.hashCode;

  /// The bond this robot locks, as the order implies it: for a taker, its bond size of [TakenSide.expectedSatoshis] at the book's price (`Logics.gen_taker_hold_invoice`, `api/logics.py:1402-1404`); for a maker, the maker bond at the rate of the creation ([MakerTerms.expectedBond]).
  double get expectedBond => switch (side) {
    final TakenSide taken => taken.expectedSatoshis * bondSize.percent / 100,
    MadeSide(:final maker) => maker.expectedBond,
  };

  /// The most a bond invoice of this trade may ask: for a taker, [expectedBond] with the state machine's tolerance on it ([TradeTolerances.price] and [TradeTolerances.roundingSats], as `BondAmountOutsideOrder` checks the order's bond), rounded down to the sat; for a maker, [MakerTerms.bondCeiling], the same rule on the maker bond, computed exactly.
  ///
  /// It is what the user accepts by taking or making the order (#100): the wallet pays the invoice's own decoded amount, never more than this, and never the coordinator's `bond_satoshis`.
  Sats get bondCeiling => switch (side) {
    TakenSide() => Sats.fromInt(
      (expectedBond * (1 + TradeTolerances.price) +
              TradeTolerances.roundingSats)
          .floor(),
    ),
    MadeSide(:final maker) => maker.bondCeiling,
  };

  /// The Lightning node keys the federation list gives [coordinator] on [network]: an invoice of the trade must be one of theirs.
  List<String> get nodeKeys => coordinator.nodesPubkeys(network);

  /// The coordinator, the network and the order, never an amount.
  @override
  String toString() =>
      'TradeTerms(${coordinator.shortAlias}#$orderId, ${network.name}, ${role.name})';
}

/// What only a taker's terms have, read on terms whose side is known to be [TakenSide], as the take's own terms are: the fields of [TakenSide], and the record of [TradeTermsRecord].
extension TakenTradeTerms on TradeTerms<TakenSide> {
  FiatAmount get amount => side.amount;
  bool get isRange => side.isRange;
  Sats? get explicitSatoshis => side.explicitSatoshis;
  double get bookPrice => side.bookPrice;
  double get takerFee => side.takerFee;
  double get expectedSatoshis => side.expectedSatoshis;
  Sats get escrowCeiling => side.escrowCeiling;

  Sats payoutAt(Sats lastSatoshis) => side.payoutAt(lastSatoshis);

  /// The sats the amount taken ([amount]) is worth at [price], a price of one bitcoin in the order's currency without the premium, with the order's premium kept in these terms ([premium], read from the robot's read at the take and never read again), exactly ([amountSatsAtPrice]): the figure the owner's payment rule expects at each payment of a taker, at the Bull wallet's price of the moment (#249, design note `docs/design/phase-3-taken-order-price-check.md` § 3); `null` for a price outside [TradePriceBounds] or a premium of −100 %.
  ///
  /// The amount is the one this take chose (a range's amount, or the fixed amount), never a range's maximum; the taker fee is not added, so that it shows in the gap.
  ExactRatio? satsAtPrice(double price) =>
      amountSatsAtPrice(amount: amount, premium: premium, price: price);

  /// The exact, storable form of these terms: store it at the take, with the trade (#87).
  TradeTermsRecord get record => _takenRecord(side);
}
