import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import 'word_fit_text.dart';

/// How an [AmountRow] is drawn.
enum AmountRowTone {
  /// The text's colour and size.
  plain,

  /// Smaller, muted and indented: the price's line under « Expected by Bull Wallet ».
  detail,

  /// Bold: « You will receive », « Total to pay ».
  total,

  /// The alert colour, bold: the red alert and the figure at fault.
  alert,

  /// The warning colour, bold: « Amount not checked ».
  warning,

  /// Muted: the « not quoted » line.
  muted,
}

/// One line of the lean cards of #250 (the payout breakdown, the confirmation of a bond or a collateral): an optional icon, its label, which wraps, and its amount on the right in tabular figures, or [trailing] beside the label.
class AmountRow extends StatelessWidget {
  final String label;
  final String? amount;
  final AmountRowTone tone;
  final IconData? icon;
  final Widget? trailing;

  const AmountRow({
    super.key,
    required this.label,
    this.amount,
    this.tone = AmountRowTone.plain,
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
      AmountRowTone.detail => text.bodySmall?.copyWith(color: colors.textMuted),
      AmountRowTone.total => text.bodyMedium?.copyWith(
        color: colors.text,
        fontWeight: FontWeight.bold,
      ),
      AmountRowTone.alert => text.bodyMedium?.copyWith(
        color: colors.error,
        fontWeight: FontWeight.bold,
      ),
      AmountRowTone.warning => text.bodyMedium?.copyWith(
        color: colors.warning,
        fontWeight: FontWeight.bold,
      ),
      AmountRowTone.muted => text.bodyMedium?.copyWith(color: colors.textMuted),
      AmountRowTone.plain => text.bodyMedium?.copyWith(color: colors.text),
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
          left: tone == AmountRowTone.detail ? BullSpacing.sm : 0,
          top: BullSpacing.xxs / 2,
          bottom: BullSpacing.xxs / 2,
        ),
        child: line,
      ),
    );
  }
}

/// The frame of a lean card of #250 and of its detail: the payout breakdown, the confirmation of a bond or a collateral.
class AmountCard extends StatelessWidget {
  final List<Widget> children;

  const AmountCard({super.key, required this.children});

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
