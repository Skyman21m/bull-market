import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsCurrency;

import '../../../public/p2p_wallet_port.dart';
import 'exact_ratio.dart';
import 'maker_terms.dart';
import 'trade_tolerances.dart';

/// What the confirmation says of an amount this wallet is asked to pay for an order made here, against the sats the order's amount is worth (the owner's payment rule of 2026-11-17, design note `docs/design/phase-3-making-an-order.md` § 3.3): information, and a warning beyond [TradeTolerances.walletRateGap] on the side that costs the user. **It never stops a payment**: the user may confirm whatever it says.
///
/// Three cases:
/// - [WalletRateAtWallet]: the wallet gave its own price of a bitcoin at the moment of paying, the reference, a price that does not come from the coordinator;
/// - [WalletRateAtCreation]: the wallet does not price the order's currency, so the coordinator's price read just before the make (`MakerTerms.createdPrice`) is the reference, a weaker one, said as such (the owner's rule);
/// - [WalletRateUnverified]: the wallet prices the currency but its price could not be read now (or is no price a coordinator could give): **nothing is compared, and the creation's price is never cited**, since a coordinator that announced a price ten times too low would have a bond ten times too large look right against it (functional review of #180, C1; decided by the owner on 2026-11-17). The screen says « rate not checked » (the owner's words: the rate is not checked, not the amount) and offers to read the price again.
///
/// The two comparisons compute the sats expected exactly (`MakerTerms.bondAtPrice`); the one rounding is the display's.
@immutable
sealed class WalletRateCheck {
  /// What the invoice asks: the amount the wallet pays (the quote's invoice).
  final Sats asked;

  /// The order's currency.
  final RobosatsCurrency currency;

  const WalletRateCheck._(this.asked, this.currency);

  /// The check of a maker bond of [asked] sats for the order of [terms], as the wallet's price [wallet] allows: at that price when it gave one within the bounds of a price (`MakerTerms.bondAtPrice`), at the price of the creation for a currency the wallet does not price, and nothing compared otherwise.
  static WalletRateCheck ofMakerBond(
    MakerTerms terms, {
    required Sats asked,
    required P2pWalletBitcoinRate wallet,
  }) {
    final currency = terms.currency;
    switch (wallet) {
      case P2pWalletRateRead(:final price):
        return switch (terms.bondAtPrice(price)) {
          final bond? => WalletRateAtWallet._of(asked, bond, price, currency),
          null => WalletRateUnverified._(asked, currency),
        };
      case P2pWalletRateNotPriced():
        return switch (terms.bondAtPrice(terms.createdPrice)) {
          final bond? => WalletRateAtCreation._of(
            asked,
            bond,
            terms.createdPrice,
            currency,
          ),
          // `MakerTerms.create` bounds the price of the creation as `bondAtPrice` asks: never here, and nothing compared if it were.
          null => WalletRateUnverified._(asked, currency),
        };
      case P2pWalletRateUnavailable():
        return WalletRateUnverified._(asked, currency);
    }
  }

  /// Whether the confirmation shows the red warning: only a comparison beyond the threshold.
  bool get warns => false;
}

/// The amount compared with the sats expected at a reference price: the wallet's ([WalletRateAtWallet]) or the creation's ([WalletRateAtCreation]).
sealed class WalletRateCompared extends WalletRateCheck {
  /// The sats expected at [price], rounded down.
  final Sats expected;

  /// The reference's price of one bitcoin in [currency], without the premium.
  final double price;

  /// How far [asked] is from the exact sats expected, in hundredths of a percent of them, rounded away from zero: positive when more is asked than expected. Rounded so, a gap shown as more than 10.00 % is always one that warns ([warns]), and one shown as 10.00 % or less never is.
  final BigInt gapHundredths;

  final bool _warns;

  WalletRateCompared._(
    Sats asked,
    ExactRatio exact,
    this.price,
    RobosatsCurrency currency,
  ) : expected = Sats(exact.floor()),
      gapHundredths = _gapOf(asked, exact),
      _warns = ExactRatio.bigInt(asked.value) > exact * _limit,
      super._(asked, currency);

  /// 1 plus [TradeTolerances.walletRateGap], exactly: one tenth more for 0.10.
  static final ExactRatio _limit =
      ExactRatio.integer(1) +
      (ExactRatio.ofDouble(TradeTolerances.walletRateGap) ??
          // A constant of the code, finite: never here.
          ExactRatio.integer(0));

  /// Whether [asked] is more than [TradeTolerances.walletRateGap] above the exact sats expected: the confirmation then shows a red warning with both amounts, the user free to confirm.
  @override
  bool get warns => _warns;

  static BigInt _gapOf(Sats asked, ExactRatio expected) {
    final gap =
        (ExactRatio.bigInt(asked.value) - expected) *
        ExactRatio.integer(10000) /
        expected;
    // Away from zero: the ceiling of a gain, the floor of a saving.
    return gap >= ExactRatio.integer(0)
        ? -(ExactRatio.integer(0) - gap).floor()
        : gap.floor();
  }
}

/// Compared at the wallet's own price of a bitcoin, read at the moment of paying.
final class WalletRateAtWallet extends WalletRateCompared {
  WalletRateAtWallet._of(super.asked, super.exact, super.price, super.currency)
    : super._();

  /// Never an amount nor a price.
  @override
  String toString() => 'WalletRateAtWallet${warns ? '(warns)' : ''}';
}

/// Compared at the coordinator's price of the creation, the wallet having no price for the order's currency: a weaker reference, said as such.
final class WalletRateAtCreation extends WalletRateCompared {
  WalletRateAtCreation._of(
    super.asked,
    super.exact,
    super.price,
    super.currency,
  ) : super._();

  /// Never an amount nor a price.
  @override
  String toString() => 'WalletRateAtCreation${warns ? '(warns)' : ''}';
}

/// Not compared: the wallet prices the currency but its price could not be read now; the screen says « rate not checked » and offers to read the price again (the owner's decision of 2026-11-17).
final class WalletRateUnverified extends WalletRateCheck {
  const WalletRateUnverified._(super.asked, super.currency) : super._();

  @override
  String toString() => 'WalletRateUnverified';
}
