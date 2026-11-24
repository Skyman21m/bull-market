import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import 'amount_row.dart';
import 'word_fit_text.dart';

/// What the owner's payment rule says of an amount, drawn in a lean card of #250 (the payout breakdown, the confirmation of a bond or a collateral), in the words validated on 2026-11-24: the gap to the Bull price as information ([PriceCheckLines.gap]); beyond the threshold the red alert in two lines, its bold line in the gap's place and the two figures under it ([PriceCheckLines.against]); « Amount not checked » in orange with « Retry » and its second line ([PriceCheckLines.unverified]); the grey « not quoted » line ([PriceCheckLines.notPriced]). Always visible without a tap; an alert's explanation goes in the card's detail, or under its two lines when there is no detail to hold it ([explanation]).
///
/// The caller words the figures (« the coordinator asks » or « pays ») and the explanation; this widget only draws them, one node for a screen reader, announced when it changes.
class PriceCheckLines extends StatelessWidget {
  final _PriceCheckKind _kind;

  /// The gap written with its sign, for [PriceCheckLines.gap] and [PriceCheckLines.against].
  final String? gap;

  /// The red alert's two figures, worded by the caller (« the coordinator asks » or « pays »).
  final String? figures;

  /// The alert's explanation said under its two lines, where no detail holds it; `null` says none.
  final String? explanation;

  /// « Retry » of « Amount not checked »; `null` draws none.
  final VoidCallback? onRetry;

  /// Whether the price is being read again: « Retry » is then shown but not offered.
  final bool retrying;

  /// The gap to the Bull price within the threshold, written with its sign: « Gap to the Bull price (indicative) ».
  const PriceCheckLines.gap(String this.gap, {super.key})
    : _kind = _PriceCheckKind.gap,
      figures = null,
      explanation = null,
      onRetry = null,
      retrying = false;

  /// Beyond the threshold: « ⚠ Gap against you » and the gap, in red and bold, then [figures] in red; never « (indicative) ».
  const PriceCheckLines.against(
    String this.gap, {
    super.key,
    required String this.figures,
    this.explanation,
  }) : _kind = _PriceCheckKind.against,
       onRetry = null,
       retrying = false;

  /// The Bull wallet's price not read: « ⚠ Amount not checked » in orange and bold with « Retry », then « Bull Wallet could not get its bitcoin price. ».
  const PriceCheckLines.unverified({
    super.key,
    this.onRetry,
    this.retrying = false,
    this.explanation,
  }) : _kind = _PriceCheckKind.unverified,
       gap = null,
       figures = null;

  /// A currency the Bull wallet does not price: the grey line « Gap to the Bull price — not quoted », nothing else.
  const PriceCheckLines.notPriced({super.key})
    : _kind = _PriceCheckKind.notPriced,
      gap = null,
      figures = null,
      explanation = null,
      onRetry = null,
      retrying = false;

  static const explanationLine = ValueKey('price-check-explanation');
  static const gapRow = ValueKey('price-check-gap');
  static const alertRow = ValueKey('price-check-alert');
  static const alertFigures = ValueKey('price-check-alert-figures');
  static const unverifiedRow = ValueKey('price-check-unverified');
  static const unverifiedLine = ValueKey('price-check-unverified-line');
  static const notPricedRow = ValueKey('price-check-not-priced');
  static const retryButton = ValueKey('price-check-retry');

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final onRetry = this.onRetry;
    final explanation = this.explanation;
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
        children: switch (_kind) {
          _PriceCheckKind.gap => [
            AmountRow(
              key: gapRow,
              label: l10n.p2pPayoutBreakdownGap,
              amount: gap,
            ),
          ],
          _PriceCheckKind.against => [
            AmountRow(
              key: alertRow,
              label: l10n.p2pPayoutBreakdownAgainst,
              amount: gap,
              tone: AmountRowTone.alert,
              icon: Icons.warning_amber_rounded,
            ),
            if (figures case final shown?)
              second(alertFigures, shown, colors.error),
            if (explanation != null)
              second(explanationLine, explanation, colors.error),
          ],
          _PriceCheckKind.unverified => [
            AmountRow(
              key: unverifiedRow,
              label: l10n.p2pPayoutBreakdownUnverified,
              tone: AmountRowTone.warning,
              icon: Icons.warning_amber_rounded,
              trailing: onRetry == null
                  ? null
                  : TextButton.icon(
                      key: retryButton,
                      onPressed: retrying ? null : onRetry,
                      icon: Icon(
                        Icons.refresh,
                        size: 18,
                        color: retrying ? colors.textMuted : colors.primary,
                      ),
                      label: Text(
                        l10n.p2pCommonRetry,
                        style: text.labelLarge?.copyWith(
                          color: retrying ? colors.textMuted : colors.primary,
                        ),
                      ),
                    ),
            ),
            second(
              unverifiedLine,
              l10n.p2pPayoutBreakdownUnverifiedLine,
              colors.warning,
            ),
            if (explanation != null)
              second(explanationLine, explanation, colors.warning),
          ],
          _PriceCheckKind.notPriced => [
            AmountRow(
              key: notPricedRow,
              label: l10n.p2pPayoutBreakdownGapNotPriced,
              amount: l10n.p2pPayoutBreakdownNotPriced,
              tone: AmountRowTone.muted,
            ),
          ],
        },
      ),
    );
  }
}

enum _PriceCheckKind { gap, against, unverified, notPriced }
