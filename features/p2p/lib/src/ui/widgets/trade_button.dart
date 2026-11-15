import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import 'word_fit_text.dart';

/// A button of the trade screens drawn as `BullButton.big`, filled or outlined, whose label wraps onto several lines instead of being cut.
///
/// `BullButton` keeps its label on one line with an ellipsis and a fixed height, which cuts the longer French labels of the official client (« Confirmer l'annulation », « Payer avec un autre portefeuille ») at three times the text size on a phone of 320 points; this one grows with its label. It lives in the feature, as `FilterSheet` does, until `bull_ui` gains such a variant (a follow-up).
/// [onPressed] `null` draws it disabled; [busy] draws a small spinner beside the label and ignores taps, as the official client's loading buttons do.
class TradeButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool busy;
  final IconData? icon;
  final Color? color;

  /// What a screen reader reads of the button, when it differs from its label (« Wait 42 seconds » for « Wait (42) »); `null` for the label.
  final String? semanticLabel;

  const TradeButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.outlined = false,
    this.busy = false,
    this.icon,
    this.color,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final accent = color ?? colors.primary;
    final foreground = outlined ? accent : colors.onPrimary;
    final enabled = onPressed != null && !busy;
    final radius = BorderRadius.circular(BullRadius.xxs);
    final icon = this.icon;
    final style = Theme.of(
      context,
    ).textTheme.headlineLarge?.copyWith(color: foreground);
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      onTap: semanticLabel != null && enabled ? onPressed : null,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(
              horizontal: BullSpacing.md,
              vertical: BullSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: outlined ? colors.transparent : accent,
              border: outlined ? Border.all(color: accent) : null,
              borderRadius: radius,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy) ...[
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  ),
                  const Gap(BullSpacing.sm),
                ] else if (icon != null) ...[
                  Icon(icon, size: 20, color: foreground),
                  const Gap(BullSpacing.sm),
                ],
                // Wrapped at word boundaries only, never letter by letter at the larger text sizes.
                Flexible(child: WordFitText(label, style: style)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
