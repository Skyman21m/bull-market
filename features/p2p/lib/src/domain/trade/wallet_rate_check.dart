import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show FiatAmount, RobosatsCurrency;

import '../../../public/p2p_wallet_port.dart';
import 'exact_ratio.dart';
import 'trade_terms.dart';
import 'trade_tolerances.dart';

/// What the confirmation says of an amount this wallet is asked to pay for an order made here, against the sats the order's amount is worth (the owner's payment rule of 2026-11-17, design note `docs/design/phase-3-making-an-order.md` § 3.3): information, and a warning beyond [TradeTolerances.walletRateGap] on the side that costs the user. **It never stops a payment**: the user may confirm whatever it says.
///
/// Three cases:
/// - [WalletRateAtWallet]: the wallet gave its own price of a bitcoin at the moment of paying, the reference, a price that does not come from the coordinator;
/// - [WalletRateNotPriced]: the wallet does not price the order's currency: **nothing is compared and no figure is shown**, one line in the warning colour says that the rate is not checked and that the user trusts the coordinator's price (the owner's decision of 2026-11-17 in the evening, which replaces the comparison with the coordinator's price of the creation: at status 0 that comparison could never warn, the bond payable being already within 2 % of the coordinator's own estimate at that price, and it read « −0.01 % » for a bond ten times too large when the coordinator lied about its price, security review of #180); there is nothing to read again;
/// - [WalletRateUnverified]: the wallet prices the currency but its price could not be read now (or is no price a coordinator could give): **nothing is compared, and the creation's price is never cited**, since a coordinator that announced a price ten times too low would have a bond ten times too large look right against it (functional review of #180, C1; decided by the owner on 2026-11-17). The screen says « rate not checked » (the owner's words: the rate is not checked, not the amount) and offers to read the price again.
///
/// The comparison computes the sats expected exactly (`MakerTerms.bondAtPrice`); the one rounding is the display's. No case cites the coordinator's price of the creation (`MakerTerms.createdPrice`) as the reference of a payment.
///
/// The same rule holds on the buyer's side (#182, the owner's decision of 2026-11-17: « the same alert before « Submit » of the payout invoice and before « fiat sent » »): [ofMakerPayout] compares the sats a maker buyer is to receive with the sats the contract's amount is worth at the wallet's price, and the side that costs is then fewer sats ([WalletRateSide.receives]).
///
/// And for an order taken here (#249, the owner's decision of 2026-11-20, design note `docs/design/phase-3-taken-order-price-check.md` § 3): [ofTakerBond], [ofTakerEscrow] and [ofTakerPayout] compare the bond, a taker seller's escrow and a taker buyer's payout with the amount taken at the wallet's price with the premium kept in the taker's terms ([TakenTradeTerms.satsAtPrice]), never with a figure the coordinator gives (its price, `TakenSide.bookPrice`, is the coordinator's word).
@immutable
sealed class WalletRateCheck {
  /// The amount compared: what the invoice asks, the amount the wallet pays (the quote's invoice); for a maker buyer ([side] [WalletRateSide.receives]), the sats the coordinator gives the buyer for the contract (`trade_satoshis`, the payout's `invoice_amount`).
  final Sats asked;

  /// The order's currency.
  final RobosatsCurrency currency;

  /// Whether this wallet pays [asked] (more is the side that costs) or receives it (fewer is the side that costs).
  final WalletRateSide side;

  /// The fiat amount whose sats are expected, for a line that names it: the contract's amount of a maker seller's escrow or a maker buyer's payout, the amount taken of a take (#249); `null` for the maker bond, which is the bond of the order's largest amount.
  final FiatAmount? amount;

  const WalletRateCheck._(
    this.asked,
    this.currency, {
    this.side = WalletRateSide.pays,
    this.amount,
  });

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

  /// The check of a maker seller's escrow of [asked] sats (the quote's invoice, the amount the wallet pays) for [amount] of the contract of the order of [terms] (the fixed amount, or a range's amount kept with the contract), at the wallet's price [wallet] with the order's premium (`MakerTerms.satsAtPrice`): the warning when [asked] is more than the sats expected by more than [TradeTolerances.walletRateGap] (#187, the owner's rule of 2026-11-17: « the escrow's sats expected are the contract's amount at the Bull wallet's rate at the moment of paying with the order's premium, one threshold of 10 % above them »); nothing compared for a currency the wallet does not price or a price that could not be read, as [ofMakerBond].
  ///
  /// The maker fee the coordinator adds to the escrow (`Logics.escrow_amount`, `api/logics.py:733-749`, at most 1 % by `MakerTerms`) is not added to the sats expected: the rule compares with the contract's amount alone, so the fee shows in the gap (+0.025 % with the reference's default), well inside the threshold.
  static WalletRateCheck ofMakerEscrow(
    MakerTerms terms, {
    required FiatAmount amount,
    required Sats asked,
    required P2pWalletBitcoinRate wallet,
  }) {
    final currency = terms.currency;
    switch (wallet) {
      case P2pWalletRateRead(:final price):
        return switch (terms.satsAtPrice(price, amount)) {
          final expected? => WalletRateAtWallet._of(
            asked,
            expected,
            price,
            currency,
            amount: amount,
          ),
          null => WalletRateUnverified._(asked, currency, amount: amount),
        };
      case P2pWalletRateNotPriced():
        return WalletRateNotPriced._(asked, currency, amount: amount);
      case P2pWalletRateUnavailable():
        return WalletRateUnverified._(asked, currency, amount: amount);
    }
  }

  /// The check of the sats a maker buyer is to receive, [received] (the payout's `trade_satoshis`), for [amount] of the contract of the order of [terms], at the wallet's price [wallet] with the order's premium (`MakerTerms.satsAtPrice`): the warning when [received] is less than the sats expected by more than [TradeTolerances.walletRateGap] (fewer sats is the side that costs a buyer); nothing compared for a currency the wallet does not price or a price that could not be read, as [ofMakerBond]. The maker fee (at most 1 %, `MakerTerms`) comes off the payout and is not added back: the threshold is the rule's, on what the buyer receives.
  static WalletRateCheck ofMakerPayout(
    MakerTerms terms, {
    required FiatAmount amount,
    required Sats received,
    required P2pWalletBitcoinRate wallet,
  }) {
    final currency = terms.currency;
    const side = WalletRateSide.receives;
    switch (wallet) {
      case P2pWalletRateRead(:final price):
        return switch (terms.satsAtPrice(price, amount)) {
          final expected? => WalletRateAtWallet._of(
            received,
            expected,
            price,
            currency,
            side: side,
            amount: amount,
          ),
          null => WalletRateUnverified._(
            received,
            currency,
            side: side,
            amount: amount,
          ),
        };
      case P2pWalletRateNotPriced():
        return WalletRateNotPriced._(
          received,
          currency,
          side: side,
          amount: amount,
        );
      case P2pWalletRateUnavailable():
        return WalletRateUnverified._(
          received,
          currency,
          side: side,
          amount: amount,
        );
    }
  }

  /// The check of a taker bond of [asked] sats (the quote's invoice, the amount the wallet pays) for the take of [terms]: the bond size of the amount taken at the wallet's price [wallet] with the premium kept in the terms ([TakenTradeTerms.satsAtPrice]), the bond the reference makes on the amount taken (`Logics.gen_taker_hold_invoice`, `api/logics.py:1402-1404`); the warning when [asked] is above it by more than [TradeTolerances.walletRateGap] (more costs, as for the maker bond); nothing compared for a currency the wallet does not price ([TakenRateRules.notPriced]) or a price that could not be read.
  ///
  /// For a taker buyer a bond too *small* (a coordinator's price too high, so fewer sats received) does not warn here: the payout's line says it ([ofTakerPayout]), and the order page's line of slice 4 before the bond (design note § 3).
  static WalletRateCheck ofTakerBond(
    TradeTerms<TakenSide> terms, {
    required Sats asked,
    required P2pWalletBitcoinRate wallet,
  }) => _ofTaker(
    terms,
    asked: asked,
    wallet: wallet,
    side: WalletRateSide.pays,
    bond: true,
  );

  /// The check of a taker seller's escrow of [asked] sats (the quote's invoice, the amount the wallet pays) for the take of [terms]: the amount taken at the wallet's price [wallet] with the premium kept in the terms ([TakenTradeTerms.satsAtPrice]); the warning when [asked] is above it by more than [TradeTolerances.walletRateGap]; nothing compared for a currency the wallet does not price or a price that could not be read, as [ofTakerBond].
  ///
  /// The taker fee the coordinator adds to the escrow (`Logics.escrow_amount`, `api/logics.py:733-749`, at most 1 % by the terms) is not added to the sats expected, so that it shows in the gap (+0.18 % with the reference's default of 0.175 %), as the maker fee does for a maker seller.
  static WalletRateCheck ofTakerEscrow(
    TradeTerms<TakenSide> terms, {
    required Sats asked,
    required P2pWalletBitcoinRate wallet,
  }) => _ofTaker(
    terms,
    asked: asked,
    wallet: wallet,
    side: WalletRateSide.pays,
    bond: false,
  );

  /// The check of the sats a taker buyer is to receive, [received] (the payout invoice's `trade_satoshis`, or at 9 the trade's sats less the taker fee, [TakenTradeTerms.payoutAt]), for the take of [terms], at the wallet's price [wallet] with the premium kept in the terms: the warning when [received] is below the sats expected by more than [TradeTolerances.walletRateGap] (fewer sats is the side that costs a buyer); nothing compared for a currency the wallet does not price or a price that could not be read, as [ofTakerBond]. The taker fee comes off the payout and is not added back.
  static WalletRateCheck ofTakerPayout(
    TradeTerms<TakenSide> terms, {
    required Sats received,
    required P2pWalletBitcoinRate wallet,
  }) => _ofTaker(
    terms,
    asked: received,
    wallet: wallet,
    side: WalletRateSide.receives,
    bond: false,
  );

  static WalletRateCheck _ofTaker(
    TradeTerms<TakenSide> terms, {
    required Sats asked,
    required P2pWalletBitcoinRate wallet,
    required WalletRateSide side,
    required bool bond,
  }) {
    final currency = terms.currency;
    final amount = terms.amount;
    switch (wallet) {
      case P2pWalletRateRead(:final price):
        final sats = terms.satsAtPrice(price);
        // The bond: its bond size of those sats, exactly (a bond size is a finite percentage, `BondSize.tryCreate`).
        final size = ExactRatio.ofDouble(terms.bondSize.percent);
        final ExactRatio? expected = !bond
            ? sats
            : sats == null || size == null
            ? null
            : sats * size / ExactRatio.integer(100);
        return switch (expected) {
          final expected? => WalletRateAtWallet._of(
            asked,
            expected,
            price,
            currency,
            side: side,
            amount: amount,
          ),
          null => WalletRateUnverified._(
            asked,
            currency,
            side: side,
            amount: amount,
          ),
        };
      case P2pWalletRateNotPriced():
        return TakenRateRules.notPriced(
          asked,
          currency,
          side: side,
          amount: amount,
        );
      case P2pWalletRateUnavailable():
        return WalletRateUnverified._(
          asked,
          currency,
          side: side,
          amount: amount,
        );
    }
  }

  /// Whether the confirmation shows the red warning: only a comparison beyond the threshold.
  bool get warns => false;
}

/// The two points of the owner's payment rule for an order taken here that his rules of 2026-11-17 and 2026-11-20 did not settle (design note `docs/design/phase-3-taken-order-price-check.md` § 7, questions 2 and 3), decided by the owner on 2026-11-24 as the note recommended: each here and nowhere else, pinned by `taken_price_check_test.dart`, group « the two points the owner decided on 2026-11-24 ».
abstract final class TakenRateRules {
  /// Question 3, an order priced in sats (its sats chosen by the maker, `TakenSide.explicitSatoshis`): `true`, compared at the payments as the other orders, with the premium the coordinator computed for it at its own price (`premium_now`, kept in the terms), decided by the owner on 2026-11-24 (question 3). `false` would compare nothing at the payments for such an order ([compares]).
  static const bool comparesOrdersPricedInSats = true;

  /// Whether the payments of the take of [terms] are compared with the Bull wallet's price at all: every take, but an order priced in sats only as [comparesOrdersPricedInSats] says.
  static bool compares(TradeTerms<TakenSide> terms) =>
      terms.explicitSatoshis == null || comparesOrdersPricedInSats;

  /// Question 2, a currency the Bull wallet does not price, for a taken order: the « not priced » line alone ([WalletRateNotPriced]: no figure, no « Retry »), decided by the owner on 2026-11-24 (question 2). For an order made here the owner decided on 2026-11-20 a grey « not priced » line and an orange alert when the rate at the take is more than 10 % worse than at the creation (#250, not applied yet); for a taker the line alone, the state machine already warning from 2 % when the bond or the trade's sats move from the read the take was made on (`BondAmountOutsideOrder`, `TradePriceOutsideOrder`), beside which nothing is compared.
  static WalletRateCheck notPriced(
    Sats asked,
    RobosatsCurrency currency, {
    required WalletRateSide side,
    required FiatAmount amount,
  }) => WalletRateNotPriced._(asked, currency, side: side, amount: amount);
}

/// Which way the money goes for the amount a [WalletRateCheck] compares.
enum WalletRateSide {
  /// This wallet pays it (the maker bond, an escrow): more than expected costs the user.
  pays,

  /// This wallet receives it (a maker buyer's payout): fewer than expected costs the user.
  receives,
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
    RobosatsCurrency currency, {
    required WalletRateSide side,
    FiatAmount? amount,
  }) : expected = Sats(exact.floor()),
       gapHundredths = _gapOf(asked, exact),
       _warns = switch (side) {
         WalletRateSide.pays => ExactRatio.bigInt(asked.value) > exact * _limit,
         WalletRateSide.receives =>
           ExactRatio.bigInt(asked.value) < exact * _floor,
       },
       super._(asked, currency, side: side, amount: amount);

  /// [TradeTolerances.walletRateGap], exactly.
  static final ExactRatio _gap =
      ExactRatio.ofDouble(TradeTolerances.walletRateGap) ??
      // A constant of the code, finite: never here.
      ExactRatio.integer(0);

  /// 1 plus [TradeTolerances.walletRateGap], exactly: one tenth more for 0.10.
  static final ExactRatio _limit = ExactRatio.integer(1) + _gap;

  /// 1 less [TradeTolerances.walletRateGap], exactly: nine tenths for 0.10.
  static final ExactRatio _floor = ExactRatio.integer(1) - _gap;

  /// Whether [asked] is more than [TradeTolerances.walletRateGap] above the exact sats expected (below them, for sats this wallet receives): the screen then shows a red warning with both amounts, the user free to go on.
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
  WalletRateAtWallet._of(
    super.asked,
    super.exact,
    super.price,
    super.currency, {
    super.side = WalletRateSide.pays,
    super.amount,
  }) : super._();

  /// Never an amount nor a price.
  @override
  String toString() => 'WalletRateAtWallet${warns ? '(warns)' : ''}';
}

/// Not compared: the wallet has no price for the order's currency (the owner's decision of 2026-11-17 in the evening, design note § 3.3). The screen shows no figure and no « Retry »: one line in the warning colour says that the rate is not checked, that the user trusts the coordinator's price and should check it before paying; « Pay » stays offered.
final class WalletRateNotPriced extends WalletRateCheck {
  const WalletRateNotPriced._(
    super.asked,
    super.currency, {
    super.side = WalletRateSide.pays,
    super.amount,
  }) : super._();

  @override
  String toString() => 'WalletRateNotPriced';
}

/// Not compared: the wallet prices the currency but its price could not be read now; the screen says « rate not checked » and offers to read the price again (the owner's decision of 2026-11-17).
final class WalletRateUnverified extends WalletRateCheck {
  const WalletRateUnverified._(
    super.asked,
    super.currency, {
    super.side = WalletRateSide.pays,
    super.amount,
  }) : super._();

  @override
  String toString() => 'WalletRateUnverified';
}
