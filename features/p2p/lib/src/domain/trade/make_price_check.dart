import 'package:meta/meta.dart';
import 'package:robosats/robosats.dart' show RobosatsCurrency;

import '../../../public/p2p_wallet_port.dart';
import 'exact_ratio.dart';
import 'maker_terms.dart';
import 'trade_tolerances.dart';

/// What the create form says of the chosen coordinator's price of a bitcoin (`/api/limits/`, the price the order's terms will keep as `MakerTerms.createdPrice`) against the wallet's own price ([P2pWalletPort.bitcoinRate]), before the order is made (#181; the owner's decision of 2026-11-17: « bonne idée », on the proposal of the security review of #180).
///
/// Information, and a red warning beyond [TradeTolerances.walletRateGap] **either way**: a price too low makes the bond and the trade's sats too large, a price too high makes a buyer receive fewer sats at the take (that it warns both ways is the coordinator of the work's choice, not the owner's). **It never stops the make**: « Create order » stays offered whatever it says.
///
/// Three cases, in the spirit of the payment rule (`WalletRateCheck`):
/// - [MakePriceCompared]: both prices and how far the coordinator's is from the wallet's;
/// - [MakePriceNotPriced]: the wallet does not price the currency, so nothing is compared and no figure is shown: the user trusts the coordinator's price (the owner's decision of 2026-11-17 in the evening);
/// - [MakePriceUnverified]: the wallet prices the currency but its price could not be read (or is no price a coordinator could give): nothing is compared, the screen offers « Retry ».
@immutable
sealed class MakePriceCheck {
  final RobosatsCurrency currency;

  const MakePriceCheck._(this.currency);

  /// The check of the coordinator's [coordinatorPrice] for [currency] against the wallet's [wallet]; [coordinatorPrice] must be a price `MakerTerms.create` takes (the form shows no figure otherwise and asks nothing).
  static MakePriceCheck of({
    required RobosatsCurrency currency,
    required double coordinatorPrice,
    required P2pWalletBitcoinRate wallet,
  }) {
    switch (wallet) {
      case P2pWalletRateRead(:final price):
        final walletExact = _price(price);
        final coordinatorExact = _price(coordinatorPrice);
        if (walletExact == null || coordinatorExact == null) {
          return MakePriceUnverified._(currency);
        }
        return MakePriceCompared._(
          currency,
          walletPrice: price,
          coordinatorPrice: coordinatorPrice,
          wallet: walletExact,
          coordinator: coordinatorExact,
        );
      case P2pWalletRateNotPriced():
        return MakePriceNotPriced._(currency);
      case P2pWalletRateUnavailable():
        return MakePriceUnverified._(currency);
    }
  }

  /// [value] exactly, when it is a price `MakerTerms.create` would take.
  static ExactRatio? _price(double value) =>
      value.isFinite &&
          value >= MakerTerms.minCreatedPrice &&
          value < MakerTerms.maxCreatedPrice
      ? ExactRatio.ofDouble(value)
      : null;

  /// Whether the form shows the red warning: only a comparison beyond the threshold, either way.
  bool get warns => false;
}

/// Which way the coordinator's price is beyond the threshold, if it is.
enum MakePriceSide {
  /// Within [TradeTolerances.walletRateGap] of the wallet's price.
  within,

  /// More than the threshold below the wallet's price: the bond and the trade's sats too large.
  below,

  /// More than the threshold above the wallet's price: fewer sats for the same amount.
  above,
}

/// Both prices compared: how far the coordinator's is from the wallet's, in percent of the wallet's.
final class MakePriceCompared extends MakePriceCheck {
  /// The wallet's price of one bitcoin in [currency].
  final double walletPrice;

  /// The coordinator's price of one bitcoin in [currency], without the premium.
  final double coordinatorPrice;

  /// How far [coordinatorPrice] is from [walletPrice], in hundredths of a percent of [walletPrice], rounded away from zero: positive when the coordinator's is higher. Rounded so, a gap shown as more than 10.00 % either way is always one that warns, and one shown as 10.00 % or less never is.
  final BigInt gapHundredths;

  final MakePriceSide side;

  MakePriceCompared._(
    super.currency, {
    required this.walletPrice,
    required this.coordinatorPrice,
    required ExactRatio wallet,
    required ExactRatio coordinator,
  }) : gapHundredths = _gapOf(wallet, coordinator),
       side = _sideOf(wallet, coordinator),
       super._();

  @override
  bool get warns => side != MakePriceSide.within;

  /// 1 plus or minus [TradeTolerances.walletRateGap], exactly.
  static final ExactRatio _gap =
      ExactRatio.ofDouble(TradeTolerances.walletRateGap) ??
      // A constant of the code, finite: never here.
      ExactRatio.integer(0);

  static MakePriceSide _sideOf(ExactRatio wallet, ExactRatio coordinator) {
    final one = ExactRatio.integer(1);
    if (coordinator < wallet * (one - _gap)) return MakePriceSide.below;
    if (coordinator > wallet * (one + _gap)) return MakePriceSide.above;
    return MakePriceSide.within;
  }

  static BigInt _gapOf(ExactRatio wallet, ExactRatio coordinator) {
    final gap = (coordinator - wallet) * ExactRatio.integer(10000) / wallet;
    // Away from zero: the ceiling of a rise, the floor of a fall.
    return gap >= ExactRatio.integer(0)
        ? -(ExactRatio.integer(0) - gap).floor()
        : gap.floor();
  }

  /// Never a price.
  @override
  String toString() => 'MakePriceCompared(${side.name})';
}

/// Not compared: the wallet has no price for [currency]; the form shows one line in the warning colour, no figure and no « Retry ».
final class MakePriceNotPriced extends MakePriceCheck {
  const MakePriceNotPriced._(super.currency) : super._();

  @override
  String toString() => 'MakePriceNotPriced';
}

/// Not compared: the wallet's price could not be read; the form shows « rate not checked » in the warning colour with « Retry ».
final class MakePriceUnverified extends MakePriceCheck {
  const MakePriceUnverified._(super.currency) : super._();

  @override
  String toString() => 'MakePriceUnverified';
}
