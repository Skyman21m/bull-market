import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../trade_record.dart' show TradeRole;
import 'exact_ratio.dart';
import 'sats_at_price.dart';
import 'trade_storable.dart';
import 'trade_tolerances.dart';

/// The role of the robot that makes an order of [type]: making a buy order makes a buyer, making a sell order a seller, the opposite of a take (`Logics.is_buyer`, `api/logics.py:236-254`).
TradeRole tradeRoleMaking(OrderType type) => switch (type) {
  OrderType.buy => TradeRole.buyer,
  OrderType.sell => TradeRole.seller,
};

/// Why the terms of a make cannot be built, so the make is not sent: a type, never a text of the coordinator.
sealed class MakerTermsRefusal extends Failure {
  const MakerTermsRefusal();

  @override
  String toString() => runtimeType.toString();
}

/// The coordinator announces a maker fee above [TradeTolerances.makerFeeCeiling].
final class MakerFeeTooHigh extends MakerTermsRefusal {
  const MakerFeeTooHigh();
}

/// The terms cannot be checked so: a maker fee that is no fraction, a price outside [MakerTerms.minCreatedPrice] to [MakerTerms.maxCreatedPrice], or a coordinator that is not on the network.
final class MakerTermsUnusable extends MakerTermsRefusal {
  const MakerTermsUnusable();
}

/// What a gap from the rate of the creation means for the maker's side ([TradeRateGap.effectFor]).
enum RateGapEffect {
  /// More for the maker: more sats to receive as a buyer, fewer to lock as a seller.
  favourable,

  /// Less for the maker: fewer sats to receive as a buyer, more to lock as a seller.
  unfavourable,

  /// The very rate of the creation.
  none,
}

/// The rate the coordinator fixed for a contract of a maker's order, against the rate of the order when it was made (design note `docs/design/phase-3-making-an-order.md` § 3.3): information shown before the steps that commit money, never a warning and never a ceiling.
///
/// Doubles, since nothing compares them nor pays on them: the screen rounds them to show them.
@immutable
final class TradeRateGap {
  /// The rate the coordinator fixed at the take, in the order's currency per bitcoin: the contract's amount over its sats (`last_satoshis`, `api/logics.py:1332-1335`).
  final double fixedRate;

  /// The rate of the order when it was made: the coordinator's price read just before the make, with the order's premium ([MakerTerms.createdRate]).
  final double createdRate;

  /// How far [fixedRate] is from [createdRate], in percent of [createdRate]: positive when the coordinator fixed a higher rate, so fewer sats for the same amount (less for a buyer to receive, less for a seller to lock).
  final double percent;

  /// The contract's sats fixed at the take (`last_satoshis`) and the contract's amount in sats at the rate of the creation, exactly ([MakerTerms.createdSatoshis]): what [againstFor] compares.
  final Sats _tradeSatoshis;
  final ExactRatio _createdSatoshis;

  const TradeRateGap._({
    required this.fixedRate,
    required this.createdRate,
    required this.percent,
    required this._tradeSatoshis,
    required this._createdSatoshis,
  });

  /// For a currency the Bull wallet does not price, an order made here (#237, the owner's decision of 2026-11-20; design note `docs/design/phase-3-making-an-order.md` § 3.3 bis): how far the contract's sats fixed at the take are from its amount's sats at the rate of the creation, in hundredths of a percent of the latter without their sign, rounded away from zero, **only when** they are more than [TradeTolerances.walletRateGap] against a maker of [role] (fewer sats for a buyer to receive, more for a seller to lock), compared exactly; `null` otherwise, within the threshold or in the maker's favour, so that no figure is ever said there.
  ///
  /// The sats, as the owner's threshold is on the sats that cost the user (§ 3.3), not the rate: a buyer is warned when its rate is more than 11.11 % higher, a seller when it is more than 9.09 % lower. Rounded away from zero, a figure said is always above 10.00 %.
  BigInt? againstFor(TradeRole role) {
    final trade = ExactRatio.bigInt(_tradeSatoshis.value);
    final created = _createdSatoshis;
    final against = switch (role) {
      TradeRole.buyer => trade < created * (_one - _gap),
      TradeRole.seller => trade > created * (_one + _gap),
    };
    if (!against) return null;
    final gap = (trade - created).abs() * ExactRatio.integer(10000) / created;
    // Away from zero, for a size: its ceiling.
    return -(ExactRatio.integer(0) - gap).floor();
  }

  static final _one = ExactRatio.integer(1);

  /// [TradeTolerances.walletRateGap], exactly: the owner's one threshold, reused (#237).
  static final ExactRatio _gap =
      ExactRatio.ofDouble(TradeTolerances.walletRateGap) ??
      // A constant of the code, finite: never here.
      ExactRatio.integer(0);

  /// What the gap means for a maker of [role] (#178): a positive gap is fewer sats for the same amount, so less for a buyer to receive and less for a seller to lock; a negative one the reverse; none at exactly 0. A screen never shows a gap as neutral when it is not.
  RateGapEffect effectFor(TradeRole role) => switch ((percent, role)) {
    (0, _) => RateGapEffect.none,
    (> 0, TradeRole.buyer) ||
    (< 0, TradeRole.seller) => RateGapEffect.unfavourable,
    _ => RateGapEffect.favourable,
  };

  @override
  bool operator ==(Object other) =>
      other is TradeRateGap &&
      other.fixedRate == fixedRate &&
      other.createdRate == createdRate &&
      other.percent == percent;

  @override
  int get hashCode => Object.hash(fixedRate, createdRate, percent);

  /// Never an amount nor a rate.
  @override
  String toString() => 'TradeRateGap';
}

/// What a maker asked, fixed once before the make's request leaves and never read again from the coordinator (design note `docs/design/phase-3-making-an-order.md` § 3.2): every answer about the order it makes is checked against it, and the wallet pays within it.
///
/// It is the request itself ([request], a `MakeOrderRequest` checked by its own `tryCreate`, so that the terms and what is sent have the very same bounds), the network and coordinator it is sent to, the coordinator's price of a bitcoin in the order's currency read from `/api/limits/` just before the make ([createdPrice]), and the maker fee of `/api/info/` ([makerFee]).
/// It names no order, which does not exist when it is written; `TradeTerms.made` joins it to the order once a read of it shows this robot as its maker.
/// Since #189 the request may carry a meeting point, kept and stored as it is, and a password, of which only whether there is one is kept and stored ([MakeOrderRequest.kept]): never the password nor its hash, which the make sends once and forgets, so that a renewal asks for the password again.
///
/// Its money rules are computed exactly ([ExactRatio]): each figure the coordinator gives is a whole number of sats, each rule a bound on it rounded down once, at its end, so that a sat is let through only when the rule's exact bound reaches it.
/// Its ceiling is [Sats], a `BigInt`, and nothing in the feature turns one into an `int`: `BigInt.toInt` stops at 2^63 − 1 on the Dart VM, so a screen that showed a ceiling through it could show a false figure; the wallet compares `BigInt`s (`walletPaymentFor`). Within the bounds of [create], every figure for display ([expectedBond], [createdRate], [rateGap]) is finite.
///
/// Every protection here rests on [createdPrice], which the coordinator gives: a price k times too low makes the expected bond, its ceiling and the expected sats k times too large, and the gap of a contract whose sats agree with that price reads 0 % (100 USD at 3 %, a price of 5,000 announced for 50,000: a bond ceiling of 61,201 sats instead of 6,121). As the taker trusts the book's price and the reference its own `/api/limits/`; design note `docs/design/phase-3-making-an-order.md` § 3.3 and § 4.1. What this wallet pays for an order made here is also compared with the wallet's own price at the moment of paying (`WalletRateCheck`, the owner's rule of 2026-11-17), which such a lie does not move; the escrow's ceiling at a factor of the creation's price (`escrowCeilingFor`) was removed by #187, that rule replacing it.
@immutable
final class MakerTerms {
  /// The highest [createdPrice]: the bound `maker_terms` keeps (`CHECK (created_price < 1000000000000000)`, schema 8), far above any price the coordinator can store (`exchange_rate`, 18 digits with 4 decimals, `api/models/currency.py:17-23`).
  static const double maxCreatedPrice = TradePriceBounds.highest;

  /// The lowest [createdPrice]: the smallest positive price the coordinator can give, its `exchange_rate` being a decimal of 4 places (`DecimalField(max_digits=18, decimal_places=4)`, `api/models/currency.py:17-23`), stored so by `update_or_create` (`api/tasks.py:415-423`) and read back from the database by `/api/limits/` (`LimitView`, `api/views.py:1186-1189`).
  ///
  /// Below it no coordinator of the reference answers; above it every figure of these terms for display is finite, where a price such as `5e-324` would make the expected bond infinite and the rate of the creation 0. The database keeps only `created_price > 0` (schema 8): it is wider here, and [restore] goes through [create].
  static const double minCreatedPrice = TradePriceBounds.lowest;

  final RobosatsNetwork network;

  /// The coordinator of the federation list the make is sent to.
  final Coordinator coordinator;

  /// What is asked: the order's type, currency, amount or range, payment methods, premium, durations, bond size, description, meeting point, and whether it has a password; never the password's hash ([MakeOrderRequest.kept]), so never a request to send as it is when the order has a password: the make sends the request it was given, equal to this one.
  final MakeOrderRequest request;

  /// The coordinator's price of a bitcoin in the order's currency, from `/api/limits/` just before the make: the `exchange_rate` the coordinator computes the order's sats with (`LimitView`, `api/views.py:1177-1197`; `Logics.calc_sats`, `api/logics.py:256-259`).
  final double createdPrice;

  /// The maker's fee as a fraction of the trade, as `/api/info/` of [coordinator] announced it (`maker_fee`, `FEE` × `MAKER_FEE_SPLIT`, `api/views.py:1042`): 0.00025 with the reference's defaults.
  final double makerFee;

  const MakerTerms._({
    required this.network,
    required this.coordinator,
    required this.request,
    required this.createdPrice,
    required this.makerFee,
  });

  /// The terms of making [request] on [coordinator] and [network], at the [createdPrice] of `/api/limits/` and with the [makerFee] of `/api/info/`, both read just before the make.
  ///
  /// The terms keep [request] without its password's hash ([MakeOrderRequest.kept]).
  ///
  /// Refused with [MakerFeeTooHigh] above [TradeTolerances.makerFeeCeiling], and with [MakerTermsUnusable] for a fee that is not finite or is negative, a price that is not finite, below [minCreatedPrice] or not below [maxCreatedPrice], or a coordinator that is not on [network]. A fee of minus zero is kept as zero.
  static Result<MakerTerms, MakerTermsRefusal> create({
    required RobosatsNetwork network,
    required Coordinator coordinator,
    required MakeOrderRequest request,
    required double createdPrice,
    required double makerFee,
  }) {
    if (!makerFee.isFinite || makerFee < 0) {
      return const Err(MakerTermsUnusable());
    }
    if (makerFee > TradeTolerances.makerFeeCeiling) {
      return const Err(MakerFeeTooHigh());
    }
    if (!createdPrice.isFinite ||
        createdPrice < minCreatedPrice ||
        createdPrice >= maxCreatedPrice ||
        !coordinator.isOn(network)) {
      return const Err(MakerTermsUnusable());
    }
    return Ok(
      MakerTerms._(
        network: network,
        coordinator: coordinator,
        request: request.kept,
        createdPrice: createdPrice,
        makerFee: makerFee == 0 ? 0.0 : makerFee,
      ),
    );
  }

  /// The terms [record] holds, or why not: [TradeCoordinatorGone] when its coordinator is no longer in the federation list on its network, [TradeRecordMalformed] when it is not one [record] wrote (an unknown version or network, a role that does not follow from the order's type, any value `MakeOrderRequest.tryCreate` or [create] refuses, a latitude without its longitude or the reverse).
  ///
  /// The request restored says whether the order has a password (`has_password`), never with the password's hash, which was never stored: it is not sent as it is (`MakeOrderRequest.isSendable`), a renewal giving the password again.
  ///
  /// The terms are set once, before the make: their record is never written again.
  static Result<MakerTerms, TradeRecordRefusal> restore(
    MakerTermsRecord record,
  ) {
    const refused = Err<MakerTerms, TradeRecordRefusal>(TradeRecordMalformed());
    if (record.version != MakerTermsRecord.currentVersion) return refused;
    final network = RobosatsNetwork.values
        .where((value) => value.name == record.network)
        .firstOrNull;
    if (network == null) return refused;
    final coordinator = Federation.robosats.byAlias(record.coordinatorAlias);
    if (coordinator == null || !coordinator.isOn(network)) {
      return const Err(TradeCoordinatorGone());
    }
    final type = OrderType.fromWire(record.type);
    final role = TradeRole.values
        .where((value) => value.name == record.role)
        .firstOrNull;
    final currency = RobosatsCurrency.fromId(record.currencyId);
    final premium = Premium.tryCreate(record.premiumPercent);
    final bondSize = BondSize.tryCreate(record.bondSizePercent);
    final OrderAmount? amount = switch ((
      record.amount,
      record.minAmount,
      record.maxAmount,
    )) {
      (final fixed?, null, null) => switch (FiatAmount.tryCreate(fixed)) {
        final value? => FixedOrderAmount(value),
        null => null,
      },
      (null, final min?, final max?) => switch ((
        FiatAmount.tryCreate(min),
        FiatAmount.tryCreate(max),
      )) {
        (final low?, final high?) => RangeOrderAmount.tryCreate(low, high),
        _ => null,
      },
      _ => null,
    };
    final (OrderLocation?, bool) location = switch ((
      record.latitude,
      record.longitude,
    )) {
      (null, null) => (null, true),
      (final latitude?, final longitude?) => switch (OrderLocation.tryCreate(
        latitude,
        longitude,
      )) {
        final value? => (value, true),
        null => (null, false),
      },
      _ => (null, false),
    };
    if (type == null ||
        role == null ||
        role != tradeRoleMaking(type) ||
        currency == null ||
        premium == null ||
        bondSize == null ||
        amount == null ||
        !location.$2) {
      return refused;
    }
    final request = MakeOrderRequest.tryCreate(
      type: type,
      currency: currency,
      amount: amount,
      paymentMethod: record.paymentMethod,
      premium: premium,
      publicDuration: Duration(seconds: record.publicSeconds),
      escrowDuration: Duration(seconds: record.escrowSeconds),
      bondSize: bondSize,
      description: record.description,
      location: location.$1,
      keptWithPassword: record.hasPassword,
    );
    if (request == null) return refused;
    return switch (create(
      network: network,
      coordinator: coordinator,
      request: request,
      createdPrice: record.createdPrice,
      makerFee: record.makerFee,
    )) {
      Ok(:final value) => Ok(value),
      Err() => refused,
    };
  }

  /// The exact, storable form of these terms: store it with the pending make, before its request leaves (`TradeTrailRepository.recordMakerTerms`).
  MakerTermsRecord get record {
    final amount = request.amount;
    final range = amount is RangeOrderAmount;
    return MakerTermsRecord(
      version: MakerTermsRecord.currentVersion,
      network: network.name,
      coordinatorAlias: coordinator.shortAlias,
      role: role.name,
      type: request.type.wire,
      currencyId: request.currency.id,
      amount: range ? null : amount.max.value,
      minAmount: range ? amount.min.value : null,
      maxAmount: range ? amount.max.value : null,
      premiumPercent: request.premium.percent,
      paymentMethod: request.paymentMethod,
      bondSizePercent: request.bondSize.percent,
      publicSeconds: request.publicDuration.inSeconds,
      escrowSeconds: request.escrowDuration.inSeconds,
      description: request.description,
      hasPassword: request.hasPassword,
      latitude: request.location?.latitude,
      longitude: request.location?.longitude,
      createdPrice: createdPrice,
      makerFee: makerFee,
    );
  }

  /// The maker's role: a buy order's maker buys ([tradeRoleMaking]).
  TradeRole get role => tradeRoleMaking(request.type);

  OrderType get type => request.type;
  RobosatsCurrency get currency => request.currency;
  OrderAmount get amount => request.amount;
  Premium get premium => request.premium;
  BondSize get bondSize => request.bondSize;
  Duration get publicDuration => request.publicDuration;
  Duration get escrowDuration => request.escrowDuration;

  /// The rate of the order when it was made, in its currency per bitcoin: [createdPrice] with the premium, as the coordinator prices it (`premium_rate`, `Logics.calc_sats`, `api/logics.py:256-259`); for display.
  double get createdRate => _createdRate.toDouble();

  ExactRatio get _createdRate =>
      _exact(createdPrice) *
      (_hundred + _exact(request.premium.percent)) /
      _hundred;

  /// The sats of [amount] at the rate of the creation, exactly and before any rounding: `amount / (price × (1 + premium / 100)) × 10^8`, the coordinator's own formula (`Logics.calc_sats`, `api/logics.py:256-259`), which it truncates to the sat (`Logics.satoshis_now`, `:262-275`).
  ExactRatio createdSatoshis(FiatAmount amount) =>
      _exact(amount.value) * _satsPerBitcoin / _createdRate;

  /// The maker bond the order implies at the rate of the creation, exactly: its bond size of the sats of its largest amount, the maximum of a range (`Logics.gen_maker_hold_invoice`, `api/logics.py:1266-1268`: `int(last_satoshis × bond_size / 100)`, `last_satoshis` being the sats of the largest amount at the coordinator's price when the maker's first read makes the invoice).
  ExactRatio get _expectedBond =>
      createdSatoshis(request.amount.max) *
      _exact(request.bondSize.percent) /
      _hundred;

  /// The maker bond the order implies, in sats at the rate of the creation, for display: an estimate, the bond invoice states the amount to lock.
  double get expectedBond => _expectedBond.toDouble();

  /// What a maker buyer receives for a contract whose sats the coordinator fixed at [lastSatoshis] (`last_satoshis`, `satoshis_now` to a participant, `api/views.py:324`): its `invoice_amount`, `round(last_satoshis − last_satoshis × maker fee)` (`Logics.payout_amount`, `api/logics.py:650-669`), with the maker fee of these terms, rounded half to even as Python's `round`; computed exactly, where the coordinator computes in floating point, so a figure on a half could differ by one sat (#182: the sats of the owner's rule at 9, where the coordinator gives no `trade_satoshis`, `api/views.py:346-356`).
  Sats payoutAt(Sats lastSatoshis) => payoutLessFee(lastSatoshis, makerFee);

  /// The sats [amount] of this order's currency is worth at [price] with the order's premium, exactly (the contract's sats at the wallet's price, #182): `null` for a price outside the bounds of a price of the creation, as [bondAtPrice].
  ExactRatio? satsAtPrice(double price, FiatAmount amount) =>
      amountSatsAtPrice(amount: amount, premium: request.premium, price: price);

  /// The maker bond the order implies at [price], a price of one bitcoin in the order's currency that is not the creation's, exactly: the bond size of the sats of the order's largest amount (the maximum of a range) at [price] with the order's premium, the formula of [_expectedBond] (`Logics.calc_sats`, `api/logics.py:256-259`; `api/logics.py:1266-1268`), before any rounding.
  ///
  /// For the owner's payment rule of 2026-11-17 (design note § 3.3, `WalletRateCheck`), at the wallet's own price at the moment of paying. `null` when [price] is not a price [create] would take for [createdPrice] (not finite, below [minCreatedPrice], not below [maxCreatedPrice]), so that every figure computed from it is finite.
  ExactRatio? bondAtPrice(double price) =>
      switch (satsAtPrice(price, request.amount.max)) {
        final sats? => sats * _exact(request.bondSize.percent) / _hundred,
        null => null,
      };

  /// The most a maker bond invoice of this order may ask: the expected bond with the tolerance of a taker's bond on it, [TradeTolerances.price] and [TradeTolerances.roundingSats], rounded down to the sat (design note § 3.2: `TradeTerms.bondCeiling`'s formula on these sats).
  ///
  /// The coordinator makes the invoice at the maker's first read, seconds after the creation, at its price then (`api/logics.py:1266-1268`), and truncates it twice (the sats, then the bond), so at the price of the creation the bond is at most the expected bond, but for the error of its floating-point sats, a fraction of a sat that the 1 sat covers: the tolerance covers a price that rose by up to 2 % or fell by up to 1.96 % in between. Rounded down: the ceiling is the largest whole sat within the rule, never one more.
  Sats get bondCeiling =>
      Sats(_upperBound(_expectedBond, TradeTolerances.price).floor());

  /// Whether a maker bond of [bond] sats agrees with these terms: within [TradeTolerances.price] of the expected bond, both ways, plus [TradeTolerances.roundingSats] (the check a taker's bond has, `BondAmountOutsideOrder`), so that every bond it accepts is at most [bondCeiling].
  ///
  /// Both ways, since a bond far from the order's, even below it, says the coordinator computed with other terms.
  /// A known limit, the taker's too, set by the size of the order rather than of the bond: below it, the coordinator's two truncations (up to 1 sat and a bond size's hundredth) can take a legitimate bond under the lower mark. With S the order's sats at the rate of the creation and x the rise of the price before the bond, a refusal is possible only when S × (0.02 − x / (1 + x)) < 1: below 50 sats of order at the same price, about 738 sats for a price 1.9 % higher, 1,146 sats for 1.95 %, 2,550 sats for 2 %. The smallest order a recorded coordinator allows is 1,000 sats (`packages/robosats/test/fixtures/coordinator/ammanaya-mainnet-limits.json`), so such a refusal needs a price that rose by more than about 1.9 % in the seconds between the make and its first read.
  bool bondAgrees(Sats bond) {
    final expected = _expectedBond;
    final slack =
        expected * _exact(TradeTolerances.price) +
        ExactRatio.integer(TradeTolerances.roundingSats);
    return (ExactRatio.bigInt(bond.value) - expected).abs() <= slack;
  }

  /// [value] times 1 plus [tolerance], plus [TradeTolerances.roundingSats].
  static ExactRatio _upperBound(ExactRatio value, double tolerance) =>
      value * (ExactRatio.integer(1) + _exact(tolerance)) +
      ExactRatio.integer(TradeTolerances.roundingSats);

  /// The fiat amount of a contract of this order: the fixed amount when [rangeAmount] is `null`, or for a range [rangeAmount] when it is within the range's bounds; `null` otherwise (a range without the amount its take chose, an amount outside the range, or an amount for a fixed order).
  ///
  /// What a take of a range chooses belongs to its contract, not to these terms: the coordinator clears it when the order goes back to the book, and the next take sets another (`api/logics.py:1210-1213`, `:1329-1330`), so the trail keeps it with the contract (design note § 3.2) and passes it here.
  FiatAmount? contractAmount(FiatAmount? rangeAmount) =>
      switch ((request.amount, rangeAmount)) {
        (FixedOrderAmount(:final amount), null) => amount,
        (RangeOrderAmount(:final min, :final max), final taken?)
            when taken.value >= min.value && taken.value <= max.value =>
          taken,
        _ => null,
      };

  /// Whether the fee a contract implies agrees with the announced [makerFee]: between 0 and [tradeSatoshis] × [makerFee] plus [TradeTolerances.feeSats], the fee being what a seller locks above the trade's sats ([paid], its escrow) or what a buyer receives below them ([paid], its payout), [tradeSatoshis] being the trade's sats fixed at the take (`last_satoshis`).
  ///
  /// The coordinator takes the maker's fee from the buyer's payout, `round(last_satoshis − last_satoshis × maker_fee)`, and adds it to the seller's escrow, `round(last_satoshis + last_satoshis × maker_fee)` (`Logics.payout_amount`, `api/logics.py:650-668`; `Logics.escrow_amount`, `:733-749`): rounded to the sat, so the fee is at most half a sat away from its exact value, which [TradeTolerances.feeSats] covers; a fee below 0 is never one of these.
  bool feeAgrees({required Sats tradeSatoshis, required Sats paid}) {
    final fee = switch (role) {
      TradeRole.seller => paid.value - tradeSatoshis.value,
      TradeRole.buyer => tradeSatoshis.value - paid.value,
    };
    final most =
        ExactRatio.bigInt(tradeSatoshis.value) * _exact(makerFee) +
        ExactRatio.integer(TradeTolerances.feeSats);
    return !fee.isNegative && ExactRatio.bigInt(fee) <= most;
  }

  /// How far the rate the coordinator fixed for the contract of [rangeAmount] ([contractAmount]) is from [createdRate], when the take fixed [tradeSatoshis] sats (`last_satoshis`): `null` when the contract's amount is not one of these terms or [tradeSatoshis] is 0.
  ///
  /// Shown before the escrow of a maker seller and before the payout and « Confirm … sent » of a maker buyer (design note § 3.3), where the owner's payment rule is not on the page; information only. For a currency the Bull wallet does not price, its [TradeRateGap.againstFor] is the alert of #237 (§ 3.3 bis).
  /// Call it only with sats `package:robosats` has already bounded (an order's `satoshis_now`, at most `CoordinatorReadBounds.maxSats`): its exact arithmetic grows with the size of the figures, and a huge number makes it very slow (security review of #177). The state machine calls it so, from the order it reads (`TradeStatus`, #178), and so does the owner's payment rule on a buyer's side, from the order of the status it compares (`CheckPayoutRateUsecase.againstOf`, #237); nothing else in the feature calls it.
  TradeRateGap? rateGap({
    required FiatAmount? rangeAmount,
    required Sats tradeSatoshis,
  }) {
    final amount = contractAmount(rangeAmount);
    if (amount == null || tradeSatoshis.value <= BigInt.zero) return null;
    final fixed =
        _exact(amount.value) *
        _satsPerBitcoin /
        ExactRatio.bigInt(tradeSatoshis.value);
    final created = _createdRate;
    return TradeRateGap._(
      fixedRate: fixed.toDouble(),
      createdRate: created.toDouble(),
      percent: ((fixed - created) / created * _hundred).toDouble(),
      tradeSatoshis: tradeSatoshis,
      createdSatoshis: createdSatoshis(amount),
    );
  }

  static final _hundred = ExactRatio.integer(100);
  static final _satsPerBitcoin = ExactRatio.integer(100000000);

  /// A finite double of these terms or of [TradeTolerances], as the decimal it writes: every one is finite by construction.
  static ExactRatio _exact(double value) =>
      ExactRatio.ofDouble(value) ?? (throw StateError('not finite'));

  @override
  bool operator ==(Object other) =>
      other is MakerTerms && other.record == record;

  @override
  int get hashCode => record.hashCode;

  /// The coordinator, the network and the side, never an amount, a payment method or a description.
  @override
  String toString() =>
      'MakerTerms(${coordinator.shortAlias}, ${network.name}, ${role.name})';
}
