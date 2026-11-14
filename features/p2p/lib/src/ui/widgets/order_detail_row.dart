import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../presentation/coordinator_text.dart';
import 'coordinator_avatar.dart';

/// The coordinator that hosts an order, and the number of the order on it, as the official client's order details open (`components/OrderDetails/index.tsx:300-328`); a tap does [onTap].
class OrderHostRow extends StatelessWidget {
  final Coordinator coordinator;
  final int orderId;
  final VoidCallback? onTap;

  const OrderHostRow({
    super.key,
    required this.coordinator,
    required this.orderId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final row = Row(
      children: [
        CoordinatorAvatar(coordinator: coordinator, size: 44),
        const Gap(BullSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                CoordinatorText.of(
                  coordinator.longAlias,
                  maxCodePoints: CoordinatorText.name,
                ),
                style: text.headlineLarge?.copyWith(color: colors.text),
              ),
              Text(
                l10n.p2pOrderHost,
                style: text.labelMedium?.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
        Semantics(
          label: l10n.p2pOrderId,
          child: Text(
            '# $orderId',
            style: text.headlineMedium?.copyWith(
              color: colors.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
    final onTap = this.onTap;
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// One row of the order details: label and value share the width equally, so that a long label wraps on two lines at most.
///
/// With [warning], the row shows the orange warning of the official client and opens it when tapped.
class OrderDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool bold;
  final VoidCallback? warning;

  const OrderDetailRow(
    this.label,
    this.value, {
    super.key,
    this.color,
    this.bold = false,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final warning = this.warning;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: BullSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: colors.textMuted),
            ),
          ),
          const Gap(BullSpacing.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.bodyLarge?.copyWith(
                color: color ?? colors.text,
                fontWeight: bold ? FontWeight.w700 : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (warning != null) ...[
            const Gap(BullSpacing.xs),
            Tooltip(
              message: P2pLocalizations.of(context).p2pReversibleTitle,
              child: Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: colors.warning,
              ),
            ),
          ],
        ],
      ),
    );
    if (warning == null) return row;
    return InkWell(onTap: warning, child: row);
  }
}

/// A sentence of the official client cut where its value starts, so that « You send via Revolut 100 EUR » reads as a label and a value.
final class OrderSentence {
  final String label;
  final String value;

  const OrderSentence(this.label, this.value);

  /// Stands for the value in the translated sentence: a control character, which no coordinator text can contain.
  static const mark = '\u0001';

  /// [sentence] translated with [mark] in place of [value]: the text before it is the label, the rest is the value.
  static OrderSentence split(String sentence, String value) {
    final at = sentence.indexOf(mark);
    if (at <= 0) return OrderSentence(sentence.replaceAll(mark, value), '');
    return OrderSentence(
      sentence.substring(0, at).trim(),
      sentence.substring(at).replaceAll(mark, value).trim(),
    );
  }
}
