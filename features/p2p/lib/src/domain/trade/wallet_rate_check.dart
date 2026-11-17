import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsCurrency;

import '../../../public/p2p_wallet_port.dart';
import 'exact_ratio.dart';
import 'maker_terms.dart';
import 'trade_tolerances.dart';

/// What the sats a payment is compared with were computed from (the owner's payment rule of 2026-11-17, design note `docs/design/phase-3-making-an-order.md` § 3.3).
enum WalletRateReference {
  /// The wallet's own price of a bitcoin, read at the moment of paying: a price that does not come from the coordinator.
  wallet,

  /// The coordinator's price read just before the make (`MakerTerms.createdPrice`), because the wallet has no price for the order's currency: a weaker reference, said as such.
  createdNotPriced,

  /// The coordinator's price read just before the make, because the wallet's price could not be read now (no connection, the service down, an answer that is no price): a weaker reference, said as such. Not decided by the owner: the default of #180, to put to him.
  createdUnreadable,
}

/// How an amount this wallet is asked to pay for an order made here compares with the sats the order's amount is worth at a reference price (the owner's payment rule of 2026-11-17, design note `docs/design/phase-3-making-an-order.md` § 3.3): information for the confirmation, and a warning beyond [TradeTolerances.walletRateGap] on the side that costs the user. **It never stops a payment**: the user may confirm whatever it says.
///
/// The sats expected are the order's amount (a range's maximum, for the maker bond) at the reference's price with the order's premium, times the bond size for the bond, computed exactly (`ExactRatio`, `MakerTerms.bondAtPrice`); the one rounding is the display's: [expected] rounded down, [gapHundredths] away from zero.
/// The reference is the wallet's own price whenever the wallet gave one ([WalletRateReference.wallet]), and **never the coordinator's price of the creation then**: a coordinator that announced a price ten times too low before the make has a bond ten times too large agree with its own estimate (`MakerTerms.bondAgrees`), not with the wallet's price (security review of #179). Only for a currency the wallet does not price, or when its price could not be read, is the creation's price the reference, said as weaker.
/// Doubles only for display ([price]); every comparison is exact.
@immutable
final class WalletRateCheck {
  /// What the invoice asks: the amount the wallet pays (the quote's invoice).
  final Sats asked;

  /// The sats expected at the reference's price, rounded down.
  final Sats expected;

  /// The reference's price of one bitcoin in [currency], without the premium: the wallet's, or the coordinator's of the creation.
  final double price;

  /// The order's currency, which [price] is in.
  final RobosatsCurrency currency;

  final WalletRateReference reference;

  /// How far [asked] is from the exact sats expected, in hundredths of a percent of them, rounded away from zero: positive when more is asked than expected. Rounded so, a gap shown as more than 10.00 % is always one that warns ([warns]), and one shown as 10.00 % or less never is.
  final BigInt gapHundredths;

  /// Whether [asked] is more than [TradeTolerances.walletRateGap] above the exact sats expected: the confirmation then shows a red warning with both amounts, the user free to confirm.
  final bool warns;

  const WalletRateCheck._({
    required this.asked,
    required this.expected,
    required this.price,
    required this.currency,
    required this.reference,
    required this.gapHundredths,
    required this.warns,
  });

  /// The check of a maker bond of [asked] sats for the order of [terms], at the wallet's price [wallet] when it gave one, else at the price of the creation (`MakerTerms.createdPrice`).
  ///
  /// A price of the wallet that `MakerTerms.bondAtPrice` does not take (outside the bounds of a price of the creation) counts as one that could not be read.
  static WalletRateCheck ofMakerBond(
    MakerTerms terms, {
    required Sats asked,
    required P2pWalletBitcoinRate wallet,
  }) {
    if (wallet case P2pWalletRateRead(:final price)) {
      if (terms.bondAtPrice(price) case final bond?) {
        return _of(
          asked,
          bond,
          price,
          terms.currency,
          WalletRateReference.wallet,
        );
      }
    }
    return _of(
      asked,
      _created(terms),
      terms.createdPrice,
      terms.currency,
      wallet is P2pWalletRateNotPriced
          ? WalletRateReference.createdNotPriced
          : WalletRateReference.createdUnreadable,
    );
  }

  /// The maker bond at the price of the creation, which `MakerTerms.create` bounded as `bondAtPrice` asks.
  static ExactRatio _created(MakerTerms terms) =>
      terms.bondAtPrice(terms.createdPrice) ??
      (throw StateError('a price of the creation out of its bounds'));

  static WalletRateCheck _of(
    Sats asked,
    ExactRatio expected,
    double price,
    RobosatsCurrency currency,
    WalletRateReference reference,
  ) {
    final askedExactly = ExactRatio.bigInt(asked.value);
    final gap =
        (askedExactly - expected) * ExactRatio.integer(10000) / expected;
    final limit =
        expected *
        (ExactRatio.integer(1) +
            (ExactRatio.ofDouble(TradeTolerances.walletRateGap) ??
                (throw StateError('not finite'))));
    return WalletRateCheck._(
      asked: asked,
      expected: Sats(expected.floor()),
      price: price,
      currency: currency,
      reference: reference,
      // Away from zero: the ceiling of a gain, the floor of a saving.
      gapHundredths: gap >= ExactRatio.integer(0)
          ? -(ExactRatio.integer(0) - gap).floor()
          : gap.floor(),
      warns: askedExactly > limit,
    );
  }

  /// Whether the wallet's own price was the reference: otherwise the amount is not checked by the wallet, and the screen says so.
  bool get checkedByWallet => reference == WalletRateReference.wallet;

  /// Never an amount nor a price.
  @override
  String toString() =>
      'WalletRateCheck(${reference.name}${warns ? ', warns' : ''})';
}
