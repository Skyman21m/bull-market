import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import 'word_fit_text.dart';

/// « Show details » / « Hide details » with its chevron, in a lean card of #250: in the payout breakdown under the gap's line, the detail opening under it and what is under the card moving down; in the confirmation of a bond or a collateral under its buttons, the detail opening under it and the buttons never moving.
class DetailToggle extends StatelessWidget {
  final bool open;
  final VoidCallback onPressed;

  const DetailToggle({super.key, required this.open, required this.onPressed});

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
