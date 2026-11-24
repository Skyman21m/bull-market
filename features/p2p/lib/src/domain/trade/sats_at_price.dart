import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show FiatAmount, Premium;

import 'exact_ratio.dart';

/// The bounds of a price of one bitcoin that the trade's rules compute with: the coordinator's price of a maker's creation (`MakerTerms.createdPrice`, checked against them at the make and in `maker_terms`), and the Bull wallet's price that the owner's payment rule of 2026-11-17 compares with (`WalletRateCheck`, for a maker and, since #249, for a taker).
abstract final class TradePriceBounds {
  /// The lowest price: the smallest positive price a coordinator can give, its `exchange_rate` being a decimal of 4 places (`DecimalField(max_digits=18, decimal_places=4)`, `api/models/currency.py:17-23`). Above it every figure computed from a price is finite, where a price such as `5e-324` would make one infinite.
  static const double lowest = 0.0001;

  /// The highest price, excluded: far above any price a coordinator can store (`exchange_rate`, 18 digits with 4 decimals, `api/models/currency.py:17-23`), the bound `maker_terms` keeps (`CHECK (created_price < 1000000000000000)`, schema 8).
  static const double highest = 1e15;

  /// Whether [price] is within these bounds: finite, at least [lowest], below [highest].
  static bool holds(double price) =>
      price.isFinite && price >= lowest && price < highest;
}

/// The sats [amount] is worth at [price], a price of one bitcoin in the amount's currency without the premium, with [premium] (a percentage), exactly and before any rounding: `amount / (price × (1 + premium / 100)) × 10^8`, the coordinator's own formula (`Logics.calc_sats`, `api/logics.py:256-259`), which it truncates to the sat (`Logics.satoshis_now`, `:262-275`).
///
/// Shared by both sides of a trade (design note `docs/design/phase-3-taken-order-price-check.md` § 3, § 8 slice 1): a maker's contract at the Bull wallet's price (`MakerTerms.satsAtPrice`, #182) and a taker's amount taken at it (`WalletRateCheck.ofTakerBond`, `.ofTakerEscrow`, `.ofTakerPayout`, #249).
/// `null` when [price] is outside [TradePriceBounds], and for a premium of −100 % or less, whose price with the premium is zero or below (`Premium.tryCreate` accepts −100 %): no figure, never a division by zero.
ExactRatio? amountSatsAtPrice({
  required FiatAmount amount,
  required Premium premium,
  required double price,
}) {
  if (!TradePriceBounds.holds(price)) return null;
  final value = ExactRatio.ofDouble(amount.value);
  final percent = ExactRatio.ofDouble(premium.percent);
  final exactPrice = ExactRatio.ofDouble(price);
  if (value == null || percent == null || exactPrice == null) return null;
  final rate = exactPrice * (_hundred + percent) / _hundred;
  if (rate <= ExactRatio.integer(0)) return null;
  return value * _satsPerBitcoin / rate;
}

/// What a buyer receives for a contract whose sats the coordinator fixed at [lastSatoshis] (`last_satoshis`), [fee] being the buyer's fee as a fraction of the trade (the maker fee for a maker buyer, the taker fee for a taker buyer): its `invoice_amount`, `round(last_satoshis − last_satoshis × fee)` (`Logics.payout_amount`, `api/logics.py:650-669`), rounded half to even as Python's `round`; computed exactly, where the coordinator computes in floating point, so a figure on a half could differ by one sat.
///
/// [fee] is a finite fraction the terms checked (at most `TradeTolerances.makerFeeCeiling` or `takerFeeCeiling`).
Sats payoutLessFee(Sats lastSatoshis, double fee) {
  final exactFee = ExactRatio.ofDouble(fee) ?? (throw StateError('not finite'));
  final exact =
      ExactRatio.bigInt(lastSatoshis.value) *
      (ExactRatio.integer(1) - exactFee);
  final floor = exact.floor();
  final rest = exact - ExactRatio.bigInt(floor);
  final half = ExactRatio.integer(1) / ExactRatio.integer(2);
  final up = rest > half || (rest == half && floor.isOdd);
  return Sats(up ? floor + BigInt.one : floor);
}

final _hundred = ExactRatio.integer(100);
final _satsPerBitcoin = ExactRatio.integer(100000000);
