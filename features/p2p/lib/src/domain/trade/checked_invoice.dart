part of 'trade_status.dart';

/// The step of a trade an invoice pays: the taker's bond, or the seller's escrow.
enum InvoiceStep { bond, escrow }

/// A hold invoice of the coordinator as the trade's status holds it: decoded and checked ([CheckedInvoice]), or unusable ([UnusableInvoice]).
sealed class StepInvoice {
  const StepInvoice();

  InvoiceStep get step;

  /// The amount the order says for the step: `bond_satoshis` or `escrow_satoshis`.
  Sats get orderAmount;
}

/// An invoice that cannot be shown at all: not a BOLT11 invoice, or one for another network than the trade's (design note § 4.4: no « Show anyway »).
final class UnusableInvoice extends StepInvoice {
  @override
  final InvoiceStep step;

  @override
  final Sats orderAmount;

  /// [InvoiceUnreadable] or [InvoiceWrongNetwork].
  final TradeWarning reason;

  const UnusableInvoice._(this.step, this.orderAmount, this.reason);

  @override
  String toString() => 'UnusableInvoice(${step.name}, $reason)';
}

/// A hold invoice of the coordinator, decoded here, on the trade's network, with every check of its read: the only kind of invoice a screen may show as a QR code and the wallet may be asked to pay (design note § 4.4).
///
/// Only the state machine builds one (`_checkStepInvoice`, private to the library of `TradeStatus`, which this file is part of): a string read from a coordinator becomes one only through every check of [TradeStatus.from], the order's, the trade's history and its own.
/// [warnings] holds every check that failed on the read that carried it, the invoice's own and the order's: « Pay with this wallet » needs none at all (`walletPaymentFor`), and each warning's effect says whether the QR code is shown.
/// Its [toString] names no part of the invoice.
@immutable
final class CheckedInvoice extends StepInvoice {
  /// The exact text that was decoded: what the QR code encodes, what « Copy » copies and what the wallet is given, never a text read again from the coordinator.
  final String bolt11;

  /// What the invoice says.
  final Bolt11Invoice facts;

  /// The trade's network, which the invoice's is.
  final RobosatsNetwork network;

  @override
  final InvoiceStep step;

  @override
  final Sats orderAmount;

  /// When the coordinator ends the step: the pre-take for the bond, the escrow's deadline for the escrow (`expires_at`).
  final DateTime stepDeadline;

  /// Every check that failed on the read that carried this invoice.
  final List<TradeWarning> warnings;

  const CheckedInvoice._({
    required this.bolt11,
    required this.facts,
    required this.network,
    required this.step,
    required this.orderAmount,
    required this.stepDeadline,
    required this.warnings,
  });

  /// The invoice's own amount.
  Sats get amount => facts.amount;

  /// The invoice's payment hash: a payment is bound to it.
  String get paymentHash => facts.paymentHash;

  /// When the invoice expires.
  DateTime get expiresAt => facts.expiresAt;

  /// The earlier of [expiresAt] and [stepDeadline]: past it, paying is pointless.
  DateTime get payableUntil =>
      expiresAt.isBefore(stepDeadline) ? expiresAt : stepDeadline;

  /// Whether every check of its read passed.
  bool get passedEveryCheck => warnings.isEmpty;

  /// Whether the QR code and the copy may be shown without « Show anyway ».
  bool get mayShow =>
      warnings.every((warning) => warning.effect == TradeWarningEffect.shown);

  /// Whether the QR code and the copy may be shown after « Show anyway »: only the amount checks hide it so (design note § 3.2).
  bool get mayShowAnyway => warnings.every(
    (warning) => warning.effect != TradeWarningEffect.hidesInvoice,
  );

  /// The same invoice with [more] warnings: the checks of a later read of the trade can only add to what forbids it.
  CheckedInvoice withMoreWarnings(Iterable<TradeWarning> more) =>
      CheckedInvoice._(
        bolt11: bolt11,
        facts: facts,
        network: network,
        step: step,
        orderAmount: orderAmount,
        stepDeadline: stepDeadline,
        warnings: List.unmodifiable([...warnings, ...more]),
      );

  @override
  String toString() =>
      'CheckedInvoice(${step.name}, ${warnings.isEmpty ? 'clean' : warnings.join(', ')})';
}

/// Decodes and checks the hold invoice [hold] of [step] that a read of the trade [terms] carried at [now], whose step ends at [stepDeadline] (design note § 4.4).
///
/// - Not a BOLT11 invoice, or one for another network than the trade's: an [UnusableInvoice], never shown.
/// - Its amount not the order's for the step ([HoldInvoice.satoshis]): [InvoiceAmountMismatch].
/// - Expired at [now]: [InvoiceExpired]; expiring within [TradeTolerances.walletPaymentMargin]: [InvoiceExpiringSoon].
/// - A payment hash other than [pinnedHash], the hash of the first invoice of this step in the trade: [InvoiceHashChanged].
/// - A payee it states (`n`) that is not one of the coordinator's node keys in the federation list: [InvoicePayeeNotCoordinator]. The app's decoder does not recover the payee from the signature, so an invoice that states none is not compared (design note § 7, decision 6).
///
/// [readWarnings] are the checks of the same read that failed on the order: the invoice carries them too, so that nothing pays it from the wallet.
StepInvoice _checkStepInvoice({
  required HoldInvoice hold,
  required InvoiceStep step,
  required TradeTerms terms,
  required Bolt11Reader reader,
  required String? pinnedHash,
  required DateTime stepDeadline,
  required DateTime now,
  required List<TradeWarning> readWarnings,
}) {
  final decoded = reader.read(hold.invoice);
  final Bolt11Invoice facts;
  switch (decoded) {
    case Err(:final failure):
      return UnusableInvoice._(step, hold.satoshis, InvoiceUnreadable(failure));
    case Ok(:final value):
      facts = value;
  }
  if (!facts.network.belongsTo(terms.network)) {
    return UnusableInvoice._(step, hold.satoshis, const InvoiceWrongNetwork());
  }
  final own = <TradeWarning>[
    if (facts.amount != hold.satoshis) const InvoiceAmountMismatch(),
    if (!now.isBefore(facts.expiresAt))
      const InvoiceExpired()
    else if (facts.expiresAt.difference(now) <
        TradeTolerances.walletPaymentMargin)
      const InvoiceExpiringSoon(),
    if (pinnedHash != null && facts.paymentHash != pinnedHash)
      const InvoiceHashChanged(),
    if (facts.payeeNodeKey case final payee?
        when !terms.nodeKeys.contains(payee))
      const InvoicePayeeNotCoordinator(),
  ];
  return CheckedInvoice._(
    bolt11: hold.invoice,
    facts: facts,
    network: terms.network,
    step: step,
    orderAmount: hold.satoshis,
    stepDeadline: stepDeadline,
    warnings: List.unmodifiable([...readWarnings, ...own]),
  );
}
