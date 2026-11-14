import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import 'trade_button.dart';

/// The body of a dialog of the official client in the wallet's look: its title, its text, then its two buttons, the one that goes back first and the one that goes on second, as the reference lays them out from left to right (`DialogActions`).
///
/// The buttons are stacked, each the dialog's width, so that a long French label at three times the text size wraps instead of overflowing on a phone of 320 points; the whole body scrolls.
class TradeDialogBody extends StatelessWidget {
  final String title;
  final String text;
  final String backLabel;
  final VoidCallback onBack;
  final String goLabel;
  final VoidCallback onGo;

  const TradeDialogBody({
    super.key,
    required this.title,
    required this.text,
    required this.backLabel,
    required this.onBack,
    required this.goLabel,
    required this.onGo,
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
          TradeButton(label: backLabel, onPressed: onBack, outlined: true),
          const Gap(BullSpacing.sm),
          TradeButton(label: goLabel, onPressed: onGo),
        ],
      ),
    );
  }
}
