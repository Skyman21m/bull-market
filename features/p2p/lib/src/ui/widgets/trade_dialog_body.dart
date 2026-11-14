import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import 'trade_button.dart';

/// The body of a dialog of the official client in the wallet's look: its title, its text, then its two buttons, the one that goes back first and the one that goes on second, as the reference lays them out from left to right (`DialogActions`).
///
/// The button that goes on is the filled one, unless [backFirst]: then the one that goes back is filled and the other outlined, as a dialog whose going on loses something (« Go back » / « Confirm Cancel » at 6 and 7, `TradeBox/Dialogs/ConfirmCancel.tsx`, where « Go back » has the focus).
///
/// The buttons are stacked, each the dialog's width, so that a long French label at three times the text size wraps instead of overflowing on a phone of 320 points; the whole body scrolls.
class TradeDialogBody extends StatelessWidget {
  final String title;
  final String text;
  final String backLabel;
  final VoidCallback onBack;
  final String goLabel;
  final VoidCallback onGo;

  /// Whether the button that goes back is the emphasized, filled one.
  final bool backFirst;

  const TradeDialogBody({
    super.key,
    required this.title,
    required this.text,
    required this.backLabel,
    required this.onBack,
    required this.goLabel,
    required this.onGo,
    this.backFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final styles = Theme.of(context).textTheme;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            header: true,
            child: Text(
              title,
              style: styles.headlineLarge?.copyWith(color: colors.text),
            ),
          ),
          const Gap(BullSpacing.md),
          Text(
            text,
            style: styles.bodyMedium?.copyWith(color: colors.textMuted),
          ),
          const Gap(BullSpacing.lg),
          TradeButton(
            label: backLabel,
            onPressed: onBack,
            outlined: !backFirst,
          ),
          const Gap(BullSpacing.sm),
          TradeButton(label: goLabel, onPressed: onGo, outlined: backFirst),
        ],
      ),
    );
  }
}
