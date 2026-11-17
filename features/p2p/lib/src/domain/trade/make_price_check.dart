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

/// What the user saw of the price check under « Create order » when pressing it (#181, security review C1, C2): the verdict of the line shown, the coordinator's price it was drawn from, and the Bull wallet's price when one was compared.
enum MakePriceVerdict {
  /// No line: the Bull wallet's price was not read (no amount typed yet, a read still running, or no wallet).
  notRead,

  /// Compared, within the threshold.
  within,

  /// Compared, the coordinator's price more than the threshold below the Bull wallet's.
  below,

  /// Compared, the coordinator's price more than the threshold above the Bull wallet's.
  above,

  /// The Bull wallet does not price the currency.
  notPriced,

  /// The Bull wallet's price could not be read.
  unverified,
}

/// The price check as the user saw it at the press, handed to the make so that an order is never made on a coordinator's price whose comparison the user did not see (security review of #181, C1).
///
/// The make reads `/api/limits/` again just before it reserves a robot, and keeps that price as the terms' `createdPrice`; [holdsAt] tells whether the user would see the same thing at that price: a price within [TradeTolerances.walletRateGap] of the one shown, whatever the line (the estimated bond shown is then still the order's), and, when a Bull wallet's price was compared, the same verdict against it. It never refuses for a price itself: a red verdict seen is kept, but only for a price close to the one it was seen at (a red line seen at 12 % below never covers a price 90 % below; second security review of #181, C3).
@immutable
final class MakePriceSeen {
  final RobosatsCurrency currency;

  /// The coordinator's price the line was drawn from, without the premium (`/api/limits/`).
  final double coordinatorPrice;

  final MakePriceVerdict verdict;

  /// The Bull wallet's price compared, for [MakePriceVerdict.within], [MakePriceVerdict.below] and [MakePriceVerdict.above].
  final double? walletPrice;

  const MakePriceSeen._(
    this.currency,
    this.coordinatorPrice,
    this.verdict,
    this.walletPrice,
  );

  /// What a line of [check] says for [coordinatorPrice] of [currency], or no line when [check] is `null`.
  factory MakePriceSeen.of({
    required RobosatsCurrency currency,
    required double coordinatorPrice,
    MakePriceCheck? check,
  }) => switch (check) {
    null => MakePriceSeen._(
      currency,
      coordinatorPrice,
      MakePriceVerdict.notRead,
      null,
    ),
    MakePriceCompared(:final walletPrice, :final side) => MakePriceSeen._(
      currency,
      coordinatorPrice,
      switch (side) {
        MakePriceSide.within => MakePriceVerdict.within,
        MakePriceSide.below => MakePriceVerdict.below,
        MakePriceSide.above => MakePriceVerdict.above,
      },
      walletPrice,
    ),
    MakePriceNotPriced() => MakePriceSeen._(
      currency,
      coordinatorPrice,
      MakePriceVerdict.notPriced,
      null,
    ),
    MakePriceUnverified() => MakePriceSeen._(
      currency,
      coordinatorPrice,
      MakePriceVerdict.unverified,
      null,
    ),
  };

  /// The check the user would see at [price], a coordinator's price read again: compared again with the same Bull wallet's price when one was compared, nothing read anew; `null` when there was none.
  MakePriceCheck? checkAt(double price) {
    final wallet = walletPrice;
    return switch (verdict) {
      MakePriceVerdict.within ||
      MakePriceVerdict.below ||
      MakePriceVerdict.above when wallet != null => MakePriceCheck.of(
        currency: currency,
        coordinatorPrice: price,
        wallet: P2pWalletRateRead(wallet),
      ),
      MakePriceVerdict.notPriced => MakePriceCheck.of(
        currency: currency,
        coordinatorPrice: price,
        wallet: const P2pWalletRateNotPriced(),
      ),
      MakePriceVerdict.unverified => MakePriceCheck.of(
        currency: currency,
        coordinatorPrice: price,
        wallet: const P2pWalletRateUnavailable(),
      ),
      _ => null,
    };
  }

  /// Whether the user would see the same at [price], a coordinator's price of [currency] read again just before the make (see the class).
  bool holdsAt(double price) {
    final now = MakePriceCheck._price(price);
    final shown = MakePriceCheck._price(coordinatorPrice);
    if (now == null || shown == null) return false;
    if ((now - shown).abs() > shown * MakePriceCompared._gap) return false;
    switch (verdict) {
      case MakePriceVerdict.within ||
          MakePriceVerdict.below ||
          MakePriceVerdict.above:
        final check = checkAt(price);
        return check != null &&
            MakePriceSeen.of(
                  currency: currency,
                  coordinatorPrice: price,
                  check: check,
                ).verdict ==
                verdict;
      case MakePriceVerdict.notRead ||
          MakePriceVerdict.notPriced ||
          MakePriceVerdict.unverified:
        return true;
    }
  }

  /// Whether [other] shows the user the same line as this: the same verdict (the prices themselves may move within it).
  bool sameLineAs(MakePriceSeen other) =>
      other.currency == currency && other.verdict == verdict;

  /// Never a price.
  @override
  String toString() => 'MakePriceSeen(${verdict.name})';
}
