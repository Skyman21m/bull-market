import 'package:robosats/robosats.dart' show OrderType;

import 'exact_ratio.dart';
import 'make_price_check.dart';
import 'sats_at_price.dart';
import 'trade_terms.dart';

/// The owner's payment rule on the order page, before a take is sent (#249, slice 4; design note `docs/design/phase-3-taken-order-price-check.md` § 3, first row, and § 8, point 4; option B of § 7, question 1, decided by the owner on 2026-11-24: the alert only).
///
/// Once « Take Order » has shown the robot's read, the coordinator's price of a bitcoin, without the premium, from the very terms the take is sent on ([coordinatorPrice]), is compared with the Bull wallet's as the create form compares it (`CheckMakePriceUsecase`, [MakePriceCheck]), on the taker's own side ([sideOf]): a taker of a buy order is a seller. Information only, never a lock.
abstract final class TakenPriceCheck {
  /// The coordinator's price of one bitcoin in the order's currency, without the premium, from [terms]: the read's price kept in the terms, premium included ([TakenSide.bookPrice]), over 1 plus the premium kept, computed exactly and then given as the nearest double, far within a hundredth of a percent.
  ///
  /// Never the book's price (`PublicOrder.price`, `CoordinatorOrder.priceNow`): the terms are what the take is sent on and what every later line compares with. For an order priced in sats, the premium kept is the coordinator's `premium_now`, so this is the coordinator's own rate (§ 3).
  /// `null` for a premium of −100 % or below, whose price with the premium is zero (`Premium.tryCreate` accepts −100 %: never a division by zero), and for a price outside [TradePriceBounds].
  static double? coordinatorPrice(TradeTerms<TakenSide> terms) {
    final book = terms.side.bookPrice;
    if (!TradePriceBounds.holds(book)) return null;
    final exactBook = ExactRatio.ofDouble(book);
    final percent = ExactRatio.ofDouble(terms.premium.percent);
    if (exactBook == null || percent == null) return null;
    final hundred = ExactRatio.integer(100);
    final factor = (hundred + percent) / hundred;
    if (factor <= ExactRatio.integer(0)) return null;
    final price = (exactBook / factor).toDouble();
    return TradePriceBounds.holds(price) ? price : null;
  }

  /// The side [MakePriceCheck.warnsFor] is given for a taker of [role]: the order type whose maker stands where the taker stands, a buyer as `OrderType.buy`, a seller as `OrderType.sell`. Never the order's own type, which is the other side (`tradeRoleTaking`).
  static OrderType sideOf(TradeRole role) => switch (role) {
    TradeRole.buyer => OrderType.buy,
    TradeRole.seller => OrderType.sell,
  };

  /// What the order page shows for [check] and a taker of [role]; `null`, nothing read yet, shows nothing.
  static TakenPriceShown shownOf(
    MakePriceCheck? check,
    TradeRole role,
  ) => switch (check) {
    null => TakenPriceShown.nothing,
    final MakePriceCompared compared when !compared.warnsFor(sideOf(role)) =>
      TakenPriceShown.nothing,
    // A buyer is warned of a price far below the Bull wallet's too, as the create form warns it (a larger bond): « against you » would be false there.
    MakePriceCompared(side: MakePriceSide.below) when role == TradeRole.buyer =>
      TakenPriceShown.farBelow,
    MakePriceCompared() => TakenPriceShown.against,
    MakePriceUnverified() => TakenPriceShown.unverified,
    MakePriceNotPriced() => TakenPriceShown.notPriced,
  };
}

/// What the order page shows of the comparison under « Price and premium » (option B): nothing within the threshold, never a reassuring line.
enum TakenPriceShown {
  /// Nothing: not read yet, read and within the threshold, or beyond it on the side that does not cost the taker (a seller and a price above the Bull wallet's).
  nothing,

  /// The red alert: the coordinator's price beyond the threshold against the taker, above the Bull wallet's for a buyer (fewer sats received), below it for a seller (a larger bond, more sats locked).
  against,

  /// The red alert of a buyer whose coordinator's price is beyond the threshold below the Bull wallet's (a larger bond).
  farBelow,

  /// The Bull wallet's price could not be read, or the coordinator's price gives no figure: « Price not checked » in orange with « Retry ».
  unverified,

  /// The Bull wallet does not price the currency: the grey « not quoted » line, nothing else (the owner's decision of 2026-11-24, § 7, question 2).
  notPriced,
}
