import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:primitives/primitives.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/payout_breakdown.dart';
import '../../presentation/p2p_formats.dart';
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

/// The lean breakdown of the payout's sats, on arrival (#228; layout and words validated by the owner on 2026-11-24, #250): « Breakdown, in sats », the sats paid by the coordinator, the fees taken from them and, in bold, what the user will receive, then the gap to the Bull price ([PayoutCheckLines]). The detail ([PayoutBreakdownDetail]) opens under the panel's buttons, never here: the buttons never move.
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

  const PayoutBreakdownView({
    super.key,
    required this.breakdown,
    this.check,
    this.lightning = true,
    this.notCompared = false,
    this.onRetry,
  });

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
    return _Card(
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
        PayoutRow(
          key: givenRow,
          label: l10n.p2pPayoutBreakdownGiven,
          amount: sats(breakdown.given),
          tone: warns ? PayoutRowTone.alert : PayoutRowTone.plain,
        ),
        if (lightning && fees != null && received != null) ...[
          PayoutRow(
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
          PayoutRow(
            key: receivedRow,
            label: l10n.p2pPayoutBreakdownReceived,
            amount: sats(received),
            tone: PayoutRowTone.total,
          ),
        ],
        if (drawn != null) PayoutCheckLines(check: drawn, onRetry: onRetry),
      ],
    );
  }
}

/// What the rule said of the sats paid, in the breakdown or, when no breakdown can draw it, alone above the payout panel's form (an alert is never left out): the gap to the Bull price as information; beyond the threshold the red alert in two lines, its bold line in the gap's place and the two figures under it; « Amount not checked » in orange with « Retry » and its second line; the grey « not quoted » line. Always visible without a tap; the explanations are in the detail ([PayoutBreakdownDetail]).
class PayoutCheckLines extends StatelessWidget {
  final PayoutCheck check;
  final VoidCallback? onRetry;

  const PayoutCheckLines({super.key, required this.check, this.onRetry});

  static const gapRow = ValueKey('payout-breakdown-gap');
  static const alertRow = ValueKey('payout-breakdown-alert');
  static const alertFigures = ValueKey('payout-breakdown-alert-figures');
  static const unverifiedRow = ValueKey('payout-breakdown-unverified');
  static const unverifiedLine = ValueKey('payout-breakdown-unverified-line');
  static const notPricedRow = ValueKey('payout-breakdown-not-priced');

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final formats = P2pFormats.of(context);
    final onRetry = this.onRetry;
    Widget second(Key key, String line, Color color) => Padding(
      padding: const EdgeInsets.only(bottom: BullSpacing.xxs / 2),
      child: WordFitText(
        line,
        key: key,
        style: text.bodyMedium?.copyWith(color: color),
      ),
    );
    // One node for a screen reader, announced when it changes: an alert is read with its figures.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: switch (check) {
          PayoutCheckCompared(:final warns, :final gap) when !warns => [
            PayoutRow(
              key: gapRow,
              label: l10n.p2pPayoutBreakdownGap,
              amount: gap,
            ),
          ],
          PayoutCheckCompared(:final gap, :final expected, :final given) => [
            PayoutRow(
              key: alertRow,
              label: l10n.p2pPayoutBreakdownAgainst,
              amount: gap,
              tone: PayoutRowTone.alert,
              icon: Icons.warning_amber_rounded,
            ),
            second(
              alertFigures,
              l10n.p2pPayoutBreakdownAgainstFigures(
                formats.bigSats(expected.value),
                formats.bigSats(given.value),
              ),
              colors.error,
            ),
          ],
          PayoutCheckUnverified() => [
            PayoutRow(
              key: unverifiedRow,
              label: l10n.p2pPayoutBreakdownUnverified,
              tone: PayoutRowTone.warning,
              icon: Icons.warning_amber_rounded,
              trailing: onRetry == null
                  ? null
                  : TextButton.icon(
                      onPressed: onRetry,
                      icon: Icon(
                        Icons.refresh,
                        size: 18,
                        color: colors.primary,
                      ),
                      label: Text(
                        l10n.p2pCommonRetry,
                        style: text.labelLarge?.copyWith(color: colors.primary),
                      ),
                    ),
            ),
            second(
              unverifiedLine,
              l10n.p2pPayoutBreakdownUnverifiedLine,
              colors.warning,
            ),
          ],
          PayoutCheckNotPriced() => [
            PayoutRow(
              key: notPricedRow,
              label: l10n.p2pPayoutBreakdownGapNotPriced,
              amount: l10n.p2pPayoutBreakdownNotPriced,
              tone: PayoutRowTone.muted,
            ),
          ],
        },
      ),
    );
  }
}

/// The breakdown's detail, opened by « Show details » under the payout panel's buttons (variant C of the owner's screen session of 2026-11-20, validated on 2026-11-24, #250), in this order: what Bull Wallet expected and its price's line, the coordinator's fee already deducted, on the Lightning tab the routing fees, « Your invoice » with the copy of its amount (the reference's copy beside « Submit invoice for … sats », `Forms/LightningPayout.tsx:556-577`) and the swap service's fee, then one paragraph: « A small gap is normal… » beside a comparison within the threshold only, never beside an alert; the red alert's explanation; « Amount not checked »'s.
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
    return _Card(
      children: [
        if (check case PayoutCheckCompared(:final expected, :final price)) ...[
          PayoutRow(
            key: valueRow,
            label: l10n.p2pPayoutBreakdownValue,
            amount: sats(expected),
          ),
          PayoutRow(key: priceLine, label: price, tone: PayoutRowTone.detail),
        ],
        if (fee != null)
          PayoutRow(
            key: feeRow,
            label: l10n.p2pPayoutBreakdownCoordinatorFee,
            amount: sats(fee),
          ),
        if (lightning && budget != null && invoice != null) ...[
          PayoutRow(
            key: budgetRow,
            label: l10n.p2pPayoutBreakdownRoutingBudget,
            amount: less(budget),
          ),
          PayoutRow(
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
            PayoutRow(
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

/// « Show details » / « Hide details » with its chevron, under the payout panel's buttons: the detail opens under it, so that nothing above moves.
class PayoutDetailToggle extends StatelessWidget {
  final bool open;
  final VoidCallback onPressed;

  const PayoutDetailToggle({
    super.key,
    required this.open,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    return Center(
      child: TextButton(
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: WordFitText(
                open ? l10n.p2pDetailHide : l10n.p2pDetailShow,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: colors.primary),
              ),
            ),
            const Gap(BullSpacing.xxs),
            ExcludeSemantics(
              child: Icon(
                open ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frame of the breakdown and of its detail.
class _Card extends StatelessWidget {
  final List<Widget> children;

  const _Card({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(BullSpacing.sm),
    decoration: BoxDecoration(
      border: Border.all(color: context.bull.outlineVariant),
      borderRadius: BorderRadius.circular(BullRadius.sm),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// How a [PayoutRow] is drawn.
enum PayoutRowTone {
  /// The text's colour and size.
  plain,

  /// Smaller, muted and indented: the price's line under « Expected by Bull Wallet ».
  detail,

  /// Bold: « You will receive ».
  total,

  /// The alert colour, bold: the red alert and the figure at fault.
  alert,

  /// The warning colour, bold: « Amount not checked ».
  warning,

  /// Muted: the « not quoted » line.
  muted,
}

/// One line: an optional icon, its label, which wraps, and its amount on the right in tabular figures, or [trailing] beside the label.
class PayoutRow extends StatelessWidget {
  final String label;
  final String? amount;
  final PayoutRowTone tone;
  final IconData? icon;
  final Widget? trailing;

  const PayoutRow({
    super.key,
    required this.label,
    this.amount,
    this.tone = PayoutRowTone.plain,
    this.icon,
    this.trailing,
  });

  /// The text size past which an amount goes under its label.
  static const double stackedFrom = 1.3;

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final base = switch (tone) {
      PayoutRowTone.detail => text.bodySmall?.copyWith(color: colors.textMuted),
      PayoutRowTone.total => text.bodyMedium?.copyWith(
        color: colors.text,
        fontWeight: FontWeight.bold,
      ),
      PayoutRowTone.alert => text.bodyMedium?.copyWith(
        color: colors.error,
        fontWeight: FontWeight.bold,
      ),
      PayoutRowTone.warning => text.bodyMedium?.copyWith(
        color: colors.warning,
        fontWeight: FontWeight.bold,
      ),
      PayoutRowTone.muted => text.bodyMedium?.copyWith(color: colors.textMuted),
      PayoutRowTone.plain => text.bodyMedium?.copyWith(color: colors.text),
    };
    final icon = this.icon;
    final trailing = this.trailing;
    final amount = this.amount;
    final stacked = MediaQuery.textScalerOf(context).scale(1) > stackedFrom;
    final words = Row(
      children: [
        if (icon != null) ...[
          ExcludeSemantics(child: Icon(icon, size: 18, color: base?.color)),
          const Gap(BullSpacing.xxs),
        ],
        Flexible(child: WordFitText(this.label, style: base)),
        if (!stacked) ?trailing,
      ],
    );
    // Under a large text the button goes under its label, on the right, so that neither is cut on a narrow phone.
    final label = stacked && trailing != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              words,
              Align(alignment: AlignmentDirectional.centerEnd, child: trailing),
            ],
          )
        : words;
    final Widget line;
    if (amount == null) {
      line = label;
    } else {
      final figure = Text(
        amount,
        textAlign: TextAlign.right,
        style: base?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      line = stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label,
                Align(alignment: AlignmentDirectional.centerEnd, child: figure),
              ],
            )
          : Row(
              children: [
                Expanded(child: label),
                const Gap(BullSpacing.xs),
                figure,
              ],
            );
    }
    // One node for a screen reader: the label, its amount and its button, read together.
    return MergeSemantics(
      child: Padding(
        padding: EdgeInsets.only(
          left: tone == PayoutRowTone.detail ? BullSpacing.sm : 0,
          top: BullSpacing.xxs / 2,
          bottom: BullSpacing.xxs / 2,
        ),
        child: line,
      ),
    );
  }
}
