import 'package:primitives/primitives.dart';

import 'trade_status.dart';
import 'trade_tolerances.dart';

/// Whether « Pay with this wallet » may be offered for an invoice (design note § 3.2, § 4.4, as amended by #86): the only answer is this function's, and nothing overrides it.
sealed class WalletPaymentDecision {
  const WalletPaymentDecision();
}

/// The wallet may be asked to pay [invoice], its exact text, after the user's confirmation: at most [accepted] sats, before [invoice] stops being payable less [TradeTolerances.walletPaymentMargin].
///
/// The payment pull request builds the wallet port's `CheckedBolt11Invoice` from this decision only, with the invoice's exact text, amount, network, payment hash and `payableUntil` (`AGENTS.md`, the trade's state machine).
final class WalletPaymentOffered extends WalletPaymentDecision {
  final CheckedInvoice invoice;

  /// The amount the user accepted, which the payment never exceeds.
  final Sats accepted;

  const WalletPaymentOffered._(this.invoice, this.accepted);

  @override
  String toString() => 'WalletPaymentOffered';
}

/// Why « Pay with this wallet » is not offered; « Pay with another wallet » stays as the invoice's warnings allow.
enum WalletPaymentRefusal {
  /// The status holds no checked invoice of that step: nothing to pay at this status.
  noInvoice,

  /// A check of the read that carried the invoice failed: whatever its effect on the QR code, the wallet never pays it.
  checkFailed,

  /// The invoice asks for more than the user accepted.
  aboveAccepted,

  /// The invoice, or the coordinator's step, ends within [TradeTolerances.walletPaymentMargin].
  tooLate,
}

final class WalletPaymentRefused extends WalletPaymentDecision {
  final WalletPaymentRefusal reason;

  const WalletPaymentRefused._(this.reason);

  @override
  String toString() => 'WalletPaymentRefused(${reason.name})';
}

/// Whether the wallet may be offered, at [now], to pay the invoice of [step] that the trade's current [status] holds, when the user accepted [accepted] sats for that step (the bond stated in the take confirmation, or the escrow in the escrow panel's, exactly the amount shown on the confirmation the user tapped).
///
/// It takes the status, never an invoice kept by a screen: only the invoice of the latest status is ever offered, and the payment code asks again with the latest status at the moment it pays.
/// Offered only when [status] holds a [CheckedInvoice] of [step], neither [status] nor its invoice carries any warning (so never after « Show anyway », never on a trade whose coordinator once contradicted itself), the invoice's amount is at most [accepted], and the invoice and its step stay payable for [TradeTolerances.walletPaymentMargin] at least.
/// A payment is bound to [CheckedInvoice.paymentHash]: an invoice with another hash is another invoice and needs a new confirmation (#88).
WalletPaymentDecision walletPaymentFor({
  required Sats accepted,
  required TradeStatus status,
  required InvoiceStep step,
  required DateTime now,
}) {
  final invoice = status.invoice;
  if (invoice is! CheckedInvoice || invoice.step != step) {
    return const WalletPaymentRefused._(WalletPaymentRefusal.noInvoice);
  }
  if (status.warnings.isNotEmpty || !invoice.passedEveryCheck) {
    return const WalletPaymentRefused._(WalletPaymentRefusal.checkFailed);
  }
  if (invoice.amount.value > accepted.value) {
    return const WalletPaymentRefused._(WalletPaymentRefusal.aboveAccepted);
  }
  if (invoice.payableUntil.difference(now) <
      TradeTolerances.walletPaymentMargin) {
    return const WalletPaymentRefused._(WalletPaymentRefusal.tooLate);
  }
  return WalletPaymentOffered._(invoice, accepted);
}
