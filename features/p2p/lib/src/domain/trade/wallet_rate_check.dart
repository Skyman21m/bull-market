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
/// - [WalletRateNotPriced]: the wallet does not price the order's currency: **nothing is compared and no figure is shown**, one line in the warning colour says that the rate is not checked and that the user trusts the coordinator's price (the owner's decision of 2026-11-17 in the evening, which replaces the comparison with the coordinator's price of the creation: at status 0 that comparison could never warn, the bond payable being already within 2 % of the coordinator's own estimate at that price, and it read « −0.01 % » for a bond ten times too large when the coordinator lied about its price, security review of #180); there is nothing to read again;
/// - [WalletRateUnverified]: the wallet prices the currency but its price could not be read now (or is no price a coordinator could give): **nothing is compared, and the creation's price is never cited**, since a coordinator that announced a price ten times too low would have a bond ten times too large look right against it (functional review of #180, C1; decided by the owner on 2026-11-17). The screen says « rate not checked » (the owner's words: the rate is not checked, not the amount) and offers to read the price again.
///
/// The comparison computes the sats expected exactly (`MakerTerms.bondAtPrice`); the one rounding is the display's. No case cites the coordinator's price of the creation (`MakerTerms.createdPrice`) as the reference of a payment.
@immutable
sealed class WalletRateCheck {
  /// What the invoice asks: the amount the wallet pays (the quote's invoice).
  final Sats asked;

  /// The order's currency.
  final RobosatsCurrency currency;

  const WalletRateCheck._(this.asked, this.currency);

  /// The check of a maker bond of [asked] sats for the order of [terms], as the wallet's price [wallet] allows: at that price when it gave one within the bounds of a price (`MakerTerms.bondAtPrice`), and nothing compared otherwise ([WalletRateNotPriced] for a currency the wallet does not price, [WalletRateUnverified] for a price that could not be read).
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
        return WalletRateNotPriced._(asked, currency);
      case P2pWalletRateUnavailable():
        return WalletRateUnverified._(asked, currency);
    }
  }

  /// Whether the confirmation shows the red warning: only a comparison beyond the threshold.
  bool get warns => false;
}

/// The amount compared with the sats expected at the wallet's own price ([WalletRateAtWallet], the only comparison since the owner's decision of 2026-11-17 in the evening).
sealed class WalletRateCompared extends WalletRateCheck {
  /// The sats expected at [price], rounded down.
  final Sats expected;

  /// The wallet's price of one bitcoin in [currency], without the premium.
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

/// Not compared: the wallet has no price for the order's currency (the owner's decision of 2026-11-17 in the evening, design note § 3.3). The screen shows no figure and no « Retry »: one line in the warning colour says that the rate is not checked, that the user trusts the coordinator's price and should check it before paying; « Pay » stays offered.
final class WalletRateNotPriced extends WalletRateCheck {
  const WalletRateNotPriced._(super.asked, super.currency) : super._();

  @override
  String toString() => 'WalletRateNotPriced';
}

/// Not compared: the wallet prices the currency but its price could not be read now; the screen says « rate not checked » and offers to read the price again (the owner's decision of 2026-11-17).
final class WalletRateUnverified extends WalletRateCheck {
  const WalletRateUnverified._(super.asked, super.currency) : super._();

  @override
  String toString() => 'WalletRateUnverified';
}
