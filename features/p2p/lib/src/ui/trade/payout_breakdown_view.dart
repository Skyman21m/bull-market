import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:primitives/primitives.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/payout_breakdown.dart';
import '../../presentation/p2p_formats.dart';

/// What the owner's payment rule compared at the payout step of a maker buyer (#182), as the breakdown writes it (#228): the sats [given] by the coordinator that it compared, the sats [value] the contract's amount is worth at the Bull wallet's price with the order's premium, the price's line ([price]: the amount, the price and the premium, written by the trade screen), the [gap], and whether the rule warns ([warns]: the rows then in the alert colour, beside the rule's own red warning, which stays as it is).
///
/// Only a comparison with the Bull wallet's price gives one: never for « rate not checked », a currency the Bull wallet does not price, a price being read or amounts that do not agree (no first line, no gap, and never a figure of the creation's price, #234). The trade screen, which holds the rule, builds it; the payout panel only draws it, and only for the very sats it shows as given ([PayoutBreakdownView]).
@immutable
final class PayoutValuation {
  final Sats given;
  final Sats value;
  final String price;
  final String gap;
  final bool warns;

  const PayoutValuation({
    required this.given,
    required this.value,
    required this.price,
    required this.gap,
    required this.warns,
  });

  @override
  bool operator ==(Object other) =>
      other is PayoutValuation &&
      other.given == given &&
      other.value == value &&
      other.price == price &&
      other.gap == gap &&
      other.warns == warns;

  @override
  int get hashCode => Object.hash(given, value, price, gap, warns);
}

/// The sats of the payout from top to bottom (#228): the value at the Bull wallet's price and the gap (from [valuation], when it compared the very sats given), what the coordinator gives and its fee already taken out, then on the Lightning tab ([lightning]) the routing budget, « Your invoice » with the copy of its amount (the reference's copy beside « Submit invoice for … Sats », `Forms/LightningPayout.tsx:556-577`), the swap service's fee and what reaches the wallet, once this wallet made the invoice.
///
/// Amounts aligned to the right in tabular figures, the two totals in bold under a rule, the details smaller and muted, one idea a line; a label wraps rather than being cut. The project's own: the reference shows no breakdown.
class PayoutBreakdownView extends StatelessWidget {
  final PayoutBreakdown breakdown;
  final PayoutValuation? valuation;
  final bool lightning;

  /// Copies the invoice's amount; `null` draws no copy.
  final VoidCallback? onCopy;

  /// Whether the amount was just copied: the icon then shows it.
  final bool copied;

  /// Whether nothing is compared at this step (15, a new invoice after a failed payout, where the owner's rule does not run): a discreet line under the title says so, so that the breakdown does not look checked (security review of #228, C2).
  final bool notCompared;

  const PayoutBreakdownView({
    super.key,
    required this.breakdown,
    this.valuation,
    this.lightning = true,
    this.onCopy,
    this.copied = false,
    this.notCompared = false,
  });

  /// The keys of the rows, for the tests.
  static const valueRow = ValueKey('payout-breakdown-value');
  static const notComparedLine = ValueKey('payout-breakdown-not-compared');
  static const gapRow = ValueKey('payout-breakdown-gap');
  static const givenRow = ValueKey('payout-breakdown-given');
  static const feeRow = ValueKey('payout-breakdown-coordinator-fee');
  static const budgetRow = ValueKey('payout-breakdown-routing-budget');
  static const invoiceRow = ValueKey('payout-breakdown-invoice');
  static const swapRow = ValueKey('payout-breakdown-swap-fee');
  static const receivedRow = ValueKey('payout-breakdown-received');

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final formats = P2pFormats.of(context);
    String sats(Sats sats) => formats.bigSats(sats.value);
    String less(Sats sats) => formats.bigSats(-sats.value);
    // The comparison only for the very sats this breakdown shows as given: a figure that changed meanwhile is compared again by the rule, never drawn against an older one.
    final valued = switch (valuation) {
      final valuation? when valuation.given == breakdown.given => valuation,
      _ => null,
    };
    final fee = breakdown.coordinatorFee;
    final budget = breakdown.routingBudget;
    final invoice = breakdown.invoice;
    final swap = breakdown.swap;
    final alert = valued?.warns ?? false;
    final rule = Divider(
      height: BullSpacing.xs,
      thickness: 1,
      color: colors.outlineVariant,
    );
    return Container(
      padding: const EdgeInsets.all(BullSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(BullRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.p2pPayoutBreakdownTitle,
            style: text.labelMedium?.copyWith(color: colors.textMuted),
          ),
          if (notCompared && valued == null)
            Text(
              l10n.p2pPayoutBreakdownNotCompared,
              key: notComparedLine,
              style: text.bodySmall?.copyWith(color: colors.textMuted),
            ),
          const Gap(BullSpacing.xxs),
          if (valued != null) ...[
            _Row(
              key: valueRow,
              label: l10n.p2pPayoutBreakdownValue,
              amount: sats(valued.value),
            ),
            _Row(label: valued.price, tone: _Tone.detail),
          ],
          // Beyond the rule's threshold the figure at fault and its gap in the alert colour, the value at the Bull wallet's price, the reference, plain (security review of #228, R3); under it the gap in the text's size and colour, as the comparison's sentence said it before (R1).
          _Row(
            key: givenRow,
            label: l10n.p2pPayoutBreakdownGiven,
            amount: sats(breakdown.given),
            tone: alert ? _Tone.alert : _Tone.plain,
          ),
          if (valued != null)
            _Row(
              key: gapRow,
              label: l10n.p2pPayoutBreakdownGap,
              amount: valued.gap,
              tone: alert ? _Tone.alert : _Tone.plain,
            ),
          if (fee != null)
            _Row(
              key: feeRow,
              label: l10n.p2pPayoutBreakdownCoordinatorFee,
              amount: sats(fee),
              tone: _Tone.detail,
            ),
          if (lightning && budget != null && invoice != null) ...[
            _Row(
              key: budgetRow,
              label: l10n.p2pPayoutBreakdownRoutingBudget,
              amount: less(budget),
            ),
            rule,
            _Row(
              key: invoiceRow,
              label: l10n.p2pPayoutBreakdownInvoice,
              amount: sats(invoice),
              tone: _Tone.total,
              trailing: onCopy == null
                  ? null
                  : IconButton(
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
            ),
            if (swap != null) ...[
              _Row(
                key: swapRow,
                label: l10n.p2pPayoutBreakdownSwapFee,
                amount: less(swap.fee),
              ),
              rule,
              _Row(
                key: receivedRow,
                label: l10n.p2pPayoutBreakdownReceived,
                amount: sats(swap.received),
                tone: _Tone.total,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

enum _Tone { plain, detail, total, alert }

/// One line: its label, which wraps, and its amount on the right in tabular figures; a detail indented, smaller and muted; a total in bold; the figure at fault and its gap in the alert colour and bold when the rule warns.
class _Row extends StatelessWidget {
  final String label;
  final String? amount;
  final _Tone tone;
  final Widget? trailing;

  const _Row({
    super.key,
    required this.label,
    this.amount,
    this.tone = _Tone.plain,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final base = switch (tone) {
      _Tone.detail => text.bodySmall?.copyWith(color: colors.textMuted),
      _Tone.total => text.bodyMedium?.copyWith(
        color: colors.text,
        fontWeight: FontWeight.bold,
      ),
      _Tone.alert => text.bodyMedium?.copyWith(
        color: colors.error,
        fontWeight: FontWeight.bold,
      ),
      _Tone.plain => text.bodyMedium?.copyWith(color: colors.text),
    };
    final amount = this.amount;
    final trailing = this.trailing;
    // One node for a screen reader: the label, its amount and the copy, read together.
    return MergeSemantics(
      child: Padding(
        padding: EdgeInsets.only(
          left: tone == _Tone.detail ? BullSpacing.sm : 0,
          top: BullSpacing.xxs / 2,
          bottom: BullSpacing.xxs / 2,
        ),
        child: _line(context, base, amount, trailing),
      ),
    );
  }

  /// The label and its amount on one line; under a large text size (more than [stackedFrom] times the base), the amount on its own line under the label, still on the right, so that neither is cut on a narrow phone.
  Widget _line(
    BuildContext context,
    TextStyle? base,
    String? amount,
    Widget? trailing,
  ) {
    final label = Row(
      children: [
        Flexible(child: Text(this.label, style: base)),
        ?trailing,
      ],
    );
    if (amount == null) return label;
    final figure = Text(
      amount,
      textAlign: TextAlign.right,
      style: base?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
    if (MediaQuery.textScalerOf(context).scale(1) > stackedFrom) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label,
          Align(alignment: AlignmentDirectional.centerEnd, child: figure),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: label),
        const Gap(BullSpacing.xs),
        figure,
      ],
    );
  }

  /// The text size past which an amount goes under its label.
  static const double stackedFrom = 1.3;
}
