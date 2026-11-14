import 'package:primitives/primitives.dart';

import '../checked_bolt11_invoice.dart';
import 'trade_status.dart';
import 'trade_tolerances.dart';

/// Whether « Pay with this wallet » may be offered for an invoice (design note § 3.2, § 4.4, as amended by #86): the only answer is this function's, and nothing overrides it.
sealed class WalletPaymentDecision {
  const WalletPaymentDecision();
}

/// The wallet may be asked to pay [invoice], its exact text, after the user's confirmation: at most [accepted] sats, before [invoice] stops being payable less [TradeTolerances.walletPaymentMargin].
///
/// [walletInvoice] is what the wallet's port takes: the only source of a [CheckedBolt11Invoice] in the feature (`wallet_port_architecture_test.dart`), built here with the invoice's exact text, amount, network, payment hash, expiry and `payableUntil`, and read again by its own strict check of the human-readable part.
final class WalletPaymentOffered extends WalletPaymentDecision {
  final CheckedInvoice invoice;

  /// The amount the user accepted, which the payment never exceeds.
  final Sats accepted;

  /// The invoice as the wallet's port takes it: [invoice], for the current status and step, within [accepted].
  final CheckedBolt11Invoice walletInvoice;

  const WalletPaymentOffered._(this.invoice, this.accepted, this.walletInvoice);

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

  /// The wallet port's own reading of the invoice refused it ([CheckedBolt11Invoice.of]: its human-readable part, network, amount and payment hash, a second check independent of the decoder): the wallet never pays it.
  walletRefused,
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
/// Offered only when [status] holds a [CheckedInvoice] of [step], neither [status] nor its invoice carries any warning (so never after « Show anyway », never on a trade whose coordinator once contradicted itself), the invoice's amount is at most [accepted], the invoice and its step stay payable for [TradeTolerances.walletPaymentMargin] at least, and the wallet port's own check of the invoice accepts it.
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
  final walletInvoice = CheckedBolt11Invoice.of(
    bolt11: invoice.bolt11,
    amount: invoice.amount,
    network: invoice.network,
    paymentHash: invoice.paymentHash,
    expiresAt: invoice.expiresAt,
    payableUntil: invoice.payableUntil,
    now: now,
  );
  if (walletInvoice == null) {
    return const WalletPaymentRefused._(WalletPaymentRefusal.walletRefused);
  }
  return WalletPaymentOffered._(invoice, accepted, walletInvoice);
}
