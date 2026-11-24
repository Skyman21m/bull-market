import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:primitives/primitives.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/payout_breakdown.dart';
import '../../presentation/p2p_formats.dart';
import '../widgets/amount_row.dart';
import '../widgets/detail_toggle.dart';
import '../widgets/price_check_lines.dart';
import '../widgets/word_fit_text.dart';

/// What the owner's payment rule said at the payout step (6 and 8) of the sats [given] by the coordinator (#182, #249), as the breakdown draws it (#228, #250): a comparison with the Bull wallet's price ([PayoutCheckCompared]), a price that could not be read ([PayoutCheckUnverified]) or a currency the Bull wallet does not price ([PayoutCheckNotPriced]).
///
/// The trade screen, which holds the rule, builds it from the rule's state (`PayoutRateLines.checkOf`); the payout panel only draws it. Never for a price being read, amounts that do not agree, a comparison within the threshold beside an alert of the screen (`PayoutRateAlertAlone`: the alert speaks alone), the chat step, nor a figure of the creation's price (#234).
@immutable
sealed class PayoutCheck {
  /// The sats the rule compared: the payout panel draws the check in the breakdown only for the very sats the breakdown shows as paid ([PayoutBreakdownView.drawnOf]).
  final Sats given;

  const PayoutCheck(this.given);

  /// Whether it is an alert (red beyond the threshold, orange for a price not read): drawn above the panel's form when no breakdown can draw it, never left out ([PayoutCheckLines]).
  bool get alert;
}

/// The comparison with the Bull wallet's price: [expected] the sats the contract's amount is worth at it with the order's premium, rounded down; [price] its line (the amount, the price and the premium, written by the trade screen); [gap] the gap of [given] from it, written with its sign; [warns] beyond the owner's threshold ([threshold], written), the red alert.
final class PayoutCheckCompared extends PayoutCheck {
  final Sats expected;
  final String price;
  final String gap;
  final bool warns;
  final String threshold;

  const PayoutCheckCompared({
    required Sats given,
    required this.expected,
    required this.price,
    required this.gap,
    required this.warns,
    required this.threshold,
  }) : super(given);

  @override
  bool get alert => warns;

  @override
  bool operator ==(Object other) =>
      other is PayoutCheckCompared &&
      other.given == given &&
      other.expected == expected &&
      other.price == price &&
      other.gap == gap &&
      other.warns == warns &&
      other.threshold == threshold;

  @override
  int get hashCode =>
      Object.hash(given, expected, price, gap, warns, threshold);
}

/// The Bull wallet's price could not be read: « Amount not checked », in orange, with « Retry ».
final class PayoutCheckUnverified extends PayoutCheck {
  const PayoutCheckUnverified(super.given);

  @override
  bool get alert => true;

  @override
  bool operator ==(Object other) =>
      other is PayoutCheckUnverified && other.given == given;

  @override
  int get hashCode => Object.hash(PayoutCheckUnverified, given);
}

/// The Bull wallet does not price the order's currency: the grey « not quoted » line, nothing else (the owner's decision of 2026-11-24, #250, #249).
final class PayoutCheckNotPriced extends PayoutCheck {
  const PayoutCheckNotPriced(super.given);

  @override
  bool get alert => false;

  @override
  bool operator ==(Object other) =>
      other is PayoutCheckNotPriced && other.given == given;

  @override
  int get hashCode => Object.hash(PayoutCheckNotPriced, given);
}

/// The lean breakdown of the payout's sats, on arrival (#228; layout and words validated by the owner on 2026-11-24, #250): « Breakdown, in sats », the sats paid by the coordinator, the fees taken from them and, in bold, what the user will receive, then the gap to the Bull price ([PayoutCheckLines]). Under them, « Show details » opens the detail ([PayoutBreakdownDetail]) in the card, as the validated mock-up draws it (the owner's decision of 2026-11-24); what is under the card moves down.
///
/// On the Lightning tab ([lightning]) with an invoice: « Routing and swap fees » once this wallet made the invoice ([PayoutBreakdown.swap]), « Routing fees » before or for an invoice pasted from another wallet; « You will receive » their difference with the sats paid ([PayoutBreakdown.received]), so the lines add up by construction. On the Onchain tab, the sats paid and the gap only: the reference's table under the tabs says the swap's fees and the final amount.
///
/// Amounts aligned to the right in tabular figures, the total in bold under a rule; a label wraps rather than being cut, and under a large text the amount goes under its label. The project's own: the reference shows no breakdown.
class PayoutBreakdownView extends StatelessWidget {
  final PayoutBreakdown breakdown;
  final PayoutCheck? check;
  final bool lightning;

  /// Whether nothing is compared at this step (15, a new invoice after a failed payout, where the owner's rule does not run): a discreet line under the title says so, so that the breakdown does not look checked (security review of #228, C2).
  final bool notCompared;

  /// « Retry » of « Amount not checked »; `null` draws none.
  final VoidCallback? onRetry;

  /// Whether the detail is open; [onToggleDetail] opens or closes it, `null` draws no « Show details » and no detail.
  final bool detailOpen;
  final VoidCallback? onToggleDetail;

  /// Copies the invoice's amount, in the detail; `null` draws no copy.
  final VoidCallback? onCopy;

  /// Whether the amount was just copied: the icon then shows it.
  final bool copied;

  const PayoutBreakdownView({
    super.key,
    required this.breakdown,
    this.check,
    this.lightning = true,
    this.notCompared = false,
    this.onRetry,
    this.detailOpen = false,
    this.onToggleDetail,
    this.onCopy,
    this.copied = false,
  });

  /// The keys of « Show details » and of the detail, for the tests.
  static const detailToggle = ValueKey('payout-detail-toggle');
  static const detail = ValueKey('payout-detail');

  /// The keys of the rows, for the tests.
  static const notComparedLine = ValueKey('payout-breakdown-not-compared');
  static const givenRow = ValueKey('payout-breakdown-given');
  static const feesRow = ValueKey('payout-breakdown-fees');
  static const receivedRow = ValueKey('payout-breakdown-received');

  /// [check] when it is for the very sats [breakdown] shows as paid; `null` otherwise: a figure that changed since the rule compared is compared again by the rule, never drawn against an older comparison.
  static PayoutCheck? drawnOf(PayoutBreakdown? breakdown, PayoutCheck? check) =>
      breakdown != null && check != null && check.given == breakdown.given
      ? check
      : null;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final formats = P2pFormats.of(context);
    String sats(Sats sats) => formats.bigSats(sats.value);
    String less(Sats sats) => formats.bigSats(-sats.value);
    final drawn = drawnOf(breakdown, check);
    final warns = drawn is PayoutCheckCompared && drawn.warns;
    final fees = breakdown.fees;
    final received = breakdown.received;
    return AmountCard(
      children: [
        WordFitText(
          l10n.p2pPayoutBreakdownTitle,
          style: text.labelMedium?.copyWith(color: colors.textMuted),
        ),
        if (notCompared && drawn == null)
          WordFitText(
            l10n.p2pPayoutBreakdownNotCompared,
            key: notComparedLine,
            style: text.bodySmall?.copyWith(color: colors.textMuted),
          ),
        const Gap(BullSpacing.xxs),
        // Beyond the rule's threshold the figure at fault in the alert colour, beside the gap's alert (the owner's choice of 2026-11-20, #250).
        AmountRow(
          key: givenRow,
          label: l10n.p2pPayoutBreakdownGiven,
          amount: sats(breakdown.given),
          tone: warns ? AmountRowTone.alert : AmountRowTone.plain,
        ),
        if (lightning && fees != null && received != null) ...[
          AmountRow(
            key: feesRow,
            label: breakdown.swap == null
                ? l10n.p2pPayoutBreakdownRoutingFees
                : l10n.p2pPayoutBreakdownFees,
            amount: less(fees),
          ),
          Divider(
            height: BullSpacing.xs,
            thickness: 1,
            color: colors.outlineVariant,
          ),
          AmountRow(
            key: receivedRow,
            label: l10n.p2pPayoutBreakdownReceived,
            amount: sats(received),
            tone: AmountRowTone.total,
          ),
        ],
        if (drawn != null) PayoutCheckLines(check: drawn, onRetry: onRetry),
        // In the card, under the gap's line (or the alert's two lines, or « not quoted »), as the validated mock-up draws it (the owner's decision of 2026-11-24).
        if (onToggleDetail case final toggle?) ...[
          DetailToggle(key: detailToggle, open: detailOpen, onPressed: toggle),
          if (detailOpen)
            PayoutBreakdownDetail(
              key: detail,
              breakdown: breakdown,
              check: drawn,
              lightning: lightning,
              onCopy: onCopy,
              copied: copied,
            ),
        ],
      ],
    );
  }
}

/// What the rule said of the sats paid, in the breakdown or, when no breakdown can draw it, alone above the payout panel's form (an alert is never left out), drawn by [PriceCheckLines]: the gap to the Bull price as information; beyond the threshold the red alert in two lines, its bold line in the gap's place and the two figures under it (« the coordinator pays »); « Amount not checked » in orange with « Retry » and its second line; the grey « not quoted » line. Always visible without a tap; the explanations are in the detail ([PayoutBreakdownDetail]).
class PayoutCheckLines extends StatelessWidget {
  final PayoutCheck check;
  final VoidCallback? onRetry;

  /// Whether the alert's explanation is said under its two lines: where the check is drawn alone above the form, with no breakdown and so no detail to hold it (#250).
  final bool explained;

  const PayoutCheckLines({
    super.key,
    required this.check,
    this.onRetry,
    this.explained = false,
  });

  static const explanation = PriceCheckLines.explanationLine;

  static const gapRow = PriceCheckLines.gapRow;
  static const alertRow = PriceCheckLines.alertRow;
  static const alertFigures = PriceCheckLines.alertFigures;
  static const unverifiedRow = PriceCheckLines.unverifiedRow;
  static const unverifiedLine = PriceCheckLines.unverifiedLine;
  static const notPricedRow = PriceCheckLines.notPricedRow;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    return switch (check) {
      PayoutCheckCompared(:final warns, :final gap) when !warns =>
        PriceCheckLines.gap(gap),
      PayoutCheckCompared(
        :final gap,
        :final expected,
        :final given,
        :final threshold,
      ) =>
        PriceCheckLines.against(
          gap,
          figures: l10n.p2pPayoutBreakdownAgainstFigures(
            formats.bigSats(expected.value),
            formats.bigSats(given.value),
          ),
          explanation: explained
              ? l10n.p2pPayoutBreakdownAgainstDetail(threshold)
              : null,
        ),
      PayoutCheckUnverified() => PriceCheckLines.unverified(
        onRetry: onRetry,
        explanation: explained ? l10n.p2pPayoutBreakdownUnverifiedDetail : null,
      ),
      PayoutCheckNotPriced() => const PriceCheckLines.notPriced(),
    };
  }
}

/// The breakdown's detail, opened by « Show details » inside the breakdown's card, under the gap's line (the validated mock-up of the payout screen, the owner's decision of 2026-11-24, #250), in this order: what Bull Wallet expected and its price's line, the coordinator's fee already deducted, on the Lightning tab the routing fees, « Your invoice » with the copy of its amount (the reference's copy beside « Submit invoice for … sats », `Forms/LightningPayout.tsx:556-577`) and the swap service's fee, then one paragraph: « A small gap is normal… » beside a comparison within the threshold only, never beside an alert; the red alert's explanation; « Amount not checked »'s.
class PayoutBreakdownDetail extends StatelessWidget {
  final PayoutBreakdown breakdown;

  /// The rule's check as the summary draws it ([PayoutBreakdownView.drawnOf]).
  final PayoutCheck? check;
  final bool lightning;

  /// Copies the invoice's amount; `null` draws no copy.
  final VoidCallback? onCopy;

  /// Whether the amount was just copied: the icon then shows it.
  final bool copied;

  const PayoutBreakdownDetail({
    super.key,
    required this.breakdown,
    this.check,
    this.lightning = true,
    this.onCopy,
    this.copied = false,
  });

  static const valueRow = ValueKey('payout-breakdown-value');
  static const priceLine = ValueKey('payout-breakdown-price');
  static const feeRow = ValueKey('payout-breakdown-coordinator-fee');
  static const budgetRow = ValueKey('payout-breakdown-routing-budget');
  static const invoiceRow = ValueKey('payout-breakdown-invoice');
  static const swapRow = ValueKey('payout-breakdown-swap-fee');
  static const explanation = ValueKey('payout-breakdown-explanation');

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final formats = P2pFormats.of(context);
    String sats(Sats sats) => formats.bigSats(sats.value);
    String less(Sats sats) => formats.bigSats(-sats.value);
    final check = this.check;
    final fee = breakdown.coordinatorFee;
    final budget = breakdown.routingBudget;
    final invoice = breakdown.invoice;
    final swap = breakdown.swap;
    final paragraph = switch (check) {
      PayoutCheckCompared(warns: false) => (
        l10n.p2pPayoutBreakdownSmallGap,
        colors.text,
      ),
      PayoutCheckCompared(:final threshold) => (
        l10n.p2pPayoutBreakdownAgainstDetail(threshold),
        colors.error,
      ),
      PayoutCheckUnverified() => (
        l10n.p2pPayoutBreakdownUnverifiedDetail,
        colors.warning,
      ),
      PayoutCheckNotPriced() || null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (check case PayoutCheckCompared(:final expected, :final price)) ...[
          AmountRow(
            key: valueRow,
            label: l10n.p2pPayoutBreakdownValue,
            amount: sats(expected),
          ),
          AmountRow(key: priceLine, label: price, tone: AmountRowTone.detail),
        ],
        if (fee != null)
          AmountRow(
            key: feeRow,
            label: l10n.p2pPayoutBreakdownCoordinatorFee,
            amount: sats(fee),
          ),
        if (lightning && budget != null && invoice != null) ...[
          AmountRow(
            key: budgetRow,
            label: l10n.p2pPayoutBreakdownRoutingBudget,
            amount: less(budget),
          ),
          AmountRow(
            key: invoiceRow,
            label: l10n.p2pPayoutBreakdownInvoice,
            amount: sats(invoice),
            trailing: switch (onCopy) {
              final onCopy? => IconButton(
                tooltip: copied
                    ? l10n.p2pCommonCopied
                    : l10n.p2pPayoutCopyAmount,
                onPressed: onCopy,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  copied ? Icons.check : Icons.content_copy,
                  size: 18,
                  color: colors.primary,
                ),
              ),
              null => null,
            },
          ),
          if (swap != null)
            AmountRow(
              key: swapRow,
              label: l10n.p2pPayoutBreakdownSwapFee,
              amount: less(swap.fee),
            ),
        ],
        if (paragraph case (final line, final color)) ...[
          const Gap(BullSpacing.xs),
          WordFitText(
            line,
            key: explanation,
            style: text.bodyMedium?.copyWith(color: color),
          ),
        ],
      ],
    );
  }
}
