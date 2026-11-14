import 'bolt11.dart';
import 'trade_tolerances.dart';

/// What a failed check does to the invoice of the step, beyond forbidding « Pay with this wallet », which every failed check does (design note § 3.2, § 4.4).
enum TradeWarningEffect {
  /// The warning is shown; the QR code and the copy stay.
  shown,

  /// The QR code and the copy are hidden behind the warning and « Show anyway » (design note § 3.2: the amount checks).
  hidesInvoiceUntilShownAnyway,

  /// The QR code and the copy are not shown at all: no « Show anyway ».
  hidesInvoice,
}

/// A check of the state machine that failed on an answer of the coordinator: a type, never a text of the coordinator, never an action (design note § 3.2).
///
/// Every warning forbids paying from this wallet: « Pay with this wallet » is offered only for an invoice of a status with no warning at all (§ 4.4, as amended by #86).
/// [effect] says what it does to the QR code and the copy, which pay from another wallet; the screens give each warning its text (#88).
sealed class TradeWarning {
  const TradeWarning();

  TradeWarningEffect get effect;

  /// Whether the coordinator said something it never says to an honest taker, which every later status of the trade remembers (see [CoordinatorInconsistent]).
  bool get isBreachOfTrust => false;

  @override
  String toString() => runtimeType.toString();
}

/// The coordinator says this robot is the maker, or the buyer when it took as seller (or the reverse): « Do not pay anything. » (`TradeRoleMismatch` in the design note).
final class TradeRoleMismatch extends TradeWarning {
  const TradeRoleMismatch();

  @override
  TradeWarningEffect get effect => TradeWarningEffect.hidesInvoice;

  @override
  bool get isBreachOfTrust => true;
}

/// The answer is about another coordinator, network or order than the trade: a mix-up of the caller, refused as an answer.
final class TradeOrderMismatch extends TradeWarning {
  const TradeOrderMismatch();

  @override
  TradeWarningEffect get effect => TradeWarningEffect.hidesInvoice;

  @override
  bool get isBreachOfTrust => true;
}

/// The order's terms differ from those of the public order taken: currency, amount, premium, sats of an order priced in sats, bond size or escrow duration.
final class TradeTermsChanged extends TradeWarning {
  const TradeTermsChanged();

  @override
  TradeWarningEffect get effect =>
      TradeWarningEffect.hidesInvoiceUntilShownAnyway;
}

/// The status moved along an edge that the reference never takes for a taker, even through steps between two reads: « Unexpected change on the coordinator's side. », and the polling goes on.
final class TradeStatusUnexpected extends TradeWarning {
  const TradeStatusUnexpected();

  @override
  TradeWarningEffect get effect => TradeWarningEffect.hidesInvoice;

  @override
  bool get isBreachOfTrust => true;
}

/// The answer goes back to the bond step after the bond step ended, or shows a status a taker is never shown (0, 2, 4 or 12 in an order, or public with this robot as its taker): refused as an answer, the status stays the last one.
final class TradeStatusRegressed extends TradeWarning {
  const TradeStatusRegressed();

  @override
  TradeWarningEffect get effect => TradeWarningEffect.hidesInvoice;

  @override
  bool get isBreachOfTrust => true;
}

/// An earlier answer of this trade was refused as a breach of trust (role, order, an unexpected or refused status): every later status carries this, so that the wallet never pays on this trade, while another wallet still can.
final class CoordinatorInconsistent extends TradeWarning {
  const CoordinatorInconsistent();

  @override
  TradeWarningEffect get effect => TradeWarningEffect.shown;
}

/// The trade was found by recovery, without its history: its invoices cannot be checked against the first ones of their step, so the wallet never pays on it, while another wallet still can (`TradeTrail.recovered`).
final class TradeHistoryUnknown extends TradeWarning {
  const TradeHistoryUnknown();

  @override
  TradeWarningEffect get effect => TradeWarningEffect.shown;
}

/// The bond the coordinator asks for (`bond_satoshis`) is not the bond the public order implies at the book's price, within [TradeTolerances.price].
final class BondAmountOutsideOrder extends TradeWarning {
  const BondAmountOutsideOrder();

  @override
  TradeWarningEffect get effect =>
      TradeWarningEffect.hidesInvoiceUntilShownAnyway;
}

/// The trade's sats fixed when the bond locked (`satoshis_now`, the order's `last_satoshis`) are not those of the amount at the book's price, within [TradeTolerances.price]: the price implied is not the order's.
final class TradePriceOutsideOrder extends TradeWarning {
  const TradePriceOutsideOrder();

  @override
  TradeWarningEffect get effect =>
      TradeWarningEffect.hidesInvoiceUntilShownAnyway;
}

/// The seller's escrow (`escrow_satoshis`) is not the trade's sats the coordinator gives the seller (`trade_satoshis`): both are `Logics.escrow_amount` of the same robot.
final class EscrowAmountMismatch extends TradeWarning {
  const EscrowAmountMismatch();

  @override
  TradeWarningEffect get effect =>
      TradeWarningEffect.hidesInvoiceUntilShownAnyway;
}

/// The buyer's payout (`invoice_amount`) is not the trade's sats the coordinator gives the buyer (`trade_satoshis`): both are `Logics.payout_amount` of the same robot.
final class PayoutAmountMismatch extends TradeWarning {
  const PayoutAmountMismatch();

  @override
  TradeWarningEffect get effect =>
      TradeWarningEffect.hidesInvoiceUntilShownAnyway;
}

/// The fee the amounts imply (the escrow over the trade's sats, or the trade's sats over the payout) is negative or above the taker fee `/api/info/` announced, by more than [TradeTolerances.feeSats].
final class TakerFeeAboveAnnounced extends TradeWarning {
  const TakerFeeAboveAnnounced();

  @override
  TradeWarningEffect get effect =>
      TradeWarningEffect.hidesInvoiceUntilShownAnyway;
}

/// The coordinator moved the deadline of the current status earlier than it said before: shown as it is, since the coordinator decides (design note § 3.2).
final class DeadlineMovedBack extends TradeWarning {
  const DeadlineMovedBack();

  @override
  TradeWarningEffect get effect => TradeWarningEffect.shown;
}

/// The invoice could not be read as a BOLT11 invoice ([reason]): nothing of it is shown.
final class InvoiceUnreadable extends TradeWarning {
  final Bolt11Refusal reason;

  const InvoiceUnreadable(this.reason);

  @override
  TradeWarningEffect get effect => TradeWarningEffect.hidesInvoice;

  @override
  String toString() => 'InvoiceUnreadable($reason)';
}

/// The invoice is for another network than the trade's: never shown, no « Show anyway » (design note § 4.4).
final class InvoiceWrongNetwork extends TradeWarning {
  const InvoiceWrongNetwork();

  @override
  TradeWarningEffect get effect => TradeWarningEffect.hidesInvoice;
}

/// The invoice's own amount is not the amount the order says for its step (`bond_satoshis` or `escrow_satoshis`).
final class InvoiceAmountMismatch extends TradeWarning {
  const InvoiceAmountMismatch();

  @override
  TradeWarningEffect get effect =>
      TradeWarningEffect.hidesInvoiceUntilShownAnyway;
}

/// The invoice has expired: paying it cannot work.
final class InvoiceExpired extends TradeWarning {
  const InvoiceExpired();

  @override
  TradeWarningEffect get effect => TradeWarningEffect.hidesInvoice;
}

/// The invoice expires within [TradeTolerances.walletPaymentMargin]: another wallet may still pay it in time, this one is not asked to.
final class InvoiceExpiringSoon extends TradeWarning {
  const InvoiceExpiringSoon();

  @override
  TradeWarningEffect get effect => TradeWarningEffect.shown;
}

/// The invoice's payment hash is not the one of the first invoice of the same step: a new invoice, which the coordinator never sends within a step (`api/logics.py:1393-1399`, `:1490-1495`). A breach of trust: the trade is never paid from this wallet again, even when the first invoice comes back. Any confirmation given for the first one does not hold for it.
final class InvoiceHashChanged extends TradeWarning {
  const InvoiceHashChanged();

  @override
  TradeWarningEffect get effect => TradeWarningEffect.hidesInvoice;

  @override
  bool get isBreachOfTrust => true;
}

/// The node the invoice pays is not one of the coordinator's Lightning nodes in the federation list: « This invoice is not from {coordinator}'s known Lightning node. Do not pay it. » (design note § 4.4).
final class InvoicePayeeNotCoordinator extends TradeWarning {
  const InvoicePayeeNotCoordinator();

  @override
  TradeWarningEffect get effect => TradeWarningEffect.shown;
}
