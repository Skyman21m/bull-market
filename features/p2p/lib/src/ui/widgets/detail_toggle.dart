import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import 'word_fit_text.dart';

/// « Show details » / « Hide details » with its chevron, in a lean card of #250: in the payout breakdown under the gap's line, the detail opening under it and what is under the card moving down; in the confirmation of a bond or a collateral under its buttons, the detail opening under it and the buttons never moving.
/// With other words ([showLabel], [hideLabel]), « See history » / « Hide history » under the « Last order #N » lines of the Garage (#253).
/// With a text larger than normal, or when either of its two words takes more than one line, the label holds the room of the larger of the two, in height and in width, so that the link stays under the finger as it opens or folds (at three times the text size on a phone of 320 points, « Show details » took two lines and « Hide details » one); at the normal text size, both on one line, it is drawn exactly as the word shown alone, as before (follow-ups of #270, #273 and #283).
class DetailToggle extends StatelessWidget {
  final bool open;
  final VoidCallback onPressed;

  /// The words while closed and while open, « Show details » and « Hide details » when not given.
  final String? showLabel;
  final String? hideLabel;

  /// A font size to tell an enlarged text by: the scale of the text, not of this size, is what counts.
  static const double _normal = 14;

  const DetailToggle({
    super.key,
    required this.open,
    required this.onPressed,
    this.showLabel,
    this.hideLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final shown = open
        ? hideLabel ?? l10n.p2pDetailHide
        : showLabel ?? l10n.p2pDetailShow;
    final other = open
        ? showLabel ?? l10n.p2pDetailShow
        : hideLabel ?? l10n.p2pDetailHide;
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: colors.primary);
    return Center(
      child: TextButton(
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final label = WordFitText(
                    shown,
                    textAlign: TextAlign.center,
                    style: style,
                  );
                  if (!constraints.maxWidth.isFinite) return label;
                  final room = constraints.maxWidth;
                  final drawn = WordFitText.measure(
                    context,
                    shown,
                    style: style,
                    textAlign: TextAlign.center,
                    maxWidth: room,
                  );
                  final held = WordFitText.measure(
                    context,
                    other,
                    style: style,
                    textAlign: TextAlign.center,
                    maxWidth: room,
                  );
                  // At the normal text size, both on one line: drawn as before, the two words of nearly the same width.
                  final enlarged =
                      MediaQuery.textScalerOf(context).scale(_normal) > _normal;
                  if (!enlarged && drawn.lines <= 1 && held.lines <= 1) {
                    return label;
                  }
                  // With a larger text: the label holds the room of the larger of the two, so that the link keeps its height and its width when it opens or folds, and a second tap at the same place falls on it again (review of #276, R3).
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: drawn.size.width > held.size.width
                          ? drawn.size.width
                          : held.size.width,
                      minHeight: drawn.size.height > held.size.height
                          ? drawn.size.height
                          : held.size.height,
                    ),
                    child: Align(widthFactor: 1, heightFactor: 1, child: label),
                  );
                },
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
