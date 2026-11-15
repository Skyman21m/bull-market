import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../presentation/coordinator_text.dart';
import '../../presentation/p2p_formats.dart';
import 'coordinator_avatar.dart';
import 'robot_avatar.dart';

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
///
/// With [changed], its value differs from the read the user saw before (#119): the label and the value take the warning colour, the value bold, and a screen reader hears « New value: … ». The label marks a changed row apart from an expiry near its end, whose value only is coloured, as in the official client.
class OrderDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool bold;
  final VoidCallback? warning;
  final bool changed;

  const OrderDetailRow(
    this.label,
    this.value, {
    super.key,
    this.color,
    this.bold = false,
    this.warning,
    this.changed = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final warning = this.warning;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: BullSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(
                color: changed ? colors.warning : colors.textMuted,
              ),
            ),
          ),
          const Gap(BullSpacing.sm),
          Expanded(
            child: Text(
              value,
              semanticsLabel: changed ? l10n.p2pOrderNewValue(value) : null,
              textAlign: TextAlign.end,
              style: text.bodyLarge?.copyWith(
                color: color ?? (changed ? colors.warning : colors.text),
                fontWeight: bold || changed ? FontWeight.w700 : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (warning != null) ...[
            const Gap(BullSpacing.xs),
            Tooltip(
              message: l10n.p2pReversibleTitle,
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

/// The maker's description of an order, once the robot that takes it read the order (#119): « Order description », the title of the reference's dialog, then the maker's words, as a quote under it.
///
/// The text is the coordinator's word for the maker's: shown as plain text through [CoordinatorText], never as markup, never opened as a link and never offered for copy; nothing in it is acted on.
class OrderDescriptionRow extends StatelessWidget {
  final String description;

  /// Whether it differs from the read the user saw before: marked as the other rows, its label and words in the warning colour, its words bold, and « New value: … » for a screen reader.
  final bool changed;

  const OrderDescriptionRow(
    this.description, {
    super.key,
    this.changed = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final label = l10n.p2pOrderDescription;
    final words = CoordinatorText.of(
      description,
      maxCodePoints: CoordinatorText.paragraph,
    );
    return Semantics(
      container: true,
      label: label,
      value: changed ? l10n.p2pOrderNewValue(words) : words,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: BullSpacing.xxs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                style: text.bodyMedium?.copyWith(
                  color: changed ? colors.warning : colors.textMuted,
                ),
              ),
              const Gap(BullSpacing.xxs),
              Container(
                padding: const EdgeInsets.only(left: BullSpacing.sm),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: colors.outline, width: 2),
                  ),
                ),
                child: Text(
                  words,
                  style: text.bodyLarge?.copyWith(
                    color: changed ? colors.warning : colors.text,
                    fontWeight: changed ? FontWeight.w700 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

/// « M 0.025% · T 0.175% » and the on-chain payout fee, as the coordinator announces them; nothing until it answers.
///
/// [takerFee], once a take is prepared, is the taker fee of its terms, shown in place of the announced one (#119).
class OrderFeeRow extends StatelessWidget {
  final CoordinatorInfo? info;
  final double? takerFee;

  const OrderFeeRow({super.key, required this.info, this.takerFee});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final info = this.info;
    final style = text.labelLarge?.copyWith(color: colors.textMuted);
    if (info == null) return SizedBox(height: style?.fontSize ?? 12);
    final swapRate = info.currentSwapFeeRate;
    return Wrap(
      spacing: BullSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Tooltip(
          message: l10n.p2pOrderFeeMakerTooltip,
          child: Text(
            '${_initial(l10n.p2pOrderFeeMaker)} ${formats.fee(info.makerFee)}',
            style: style,
          ),
        ),
        Text('·', style: style),
        Tooltip(
          message: l10n.p2pOrderFeeTakerTooltip,
          child: Text(
            '${_initial(l10n.p2pOrderFeeTaker)} ${formats.fee(takerFee ?? info.takerFee)}',
            style: style,
          ),
        ),
        Text('·', style: style),
        Tooltip(
          message: info.swapEnabled
              ? l10n.p2pOrderOnchainEnabled
              : l10n.p2pOrderOnchainDisabled,
          child: info.swapEnabled && swapRate != null
              ? BullBadge(
                  label: formats.swapFee(swapRate),
                  icon: Icons.link,
                  background: colors.surfaceContainer,
                  foreground: colors.success,
                )
              : Icon(Icons.link_off, size: 16, color: colors.textMuted),
        ),
      ],
    );
  }

  /// The first letter of a role, as the official client writes the fee row.
  static String _initial(String word) =>
      word.isEmpty ? word : String.fromCharCode(word.runes.first);
}

/// The maker of an order, with how recently its coordinator saw it (`components/OrderDetails/index.tsx:357-364`).
class OrderMakerRow extends StatelessWidget {
  final RobotHashId maker;
  final MakerActivity? activity;

  const OrderMakerRow({super.key, required this.maker, required this.activity});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final activity = switch (this.activity) {
      MakerActivity.active => l10n.p2pBookMakerStatusActive,
      MakerActivity.seenRecently => l10n.p2pBookMakerStatusSeenRecently,
      MakerActivity.inactive => l10n.p2pBookMakerStatusInactive,
      null => null,
    };
    return Row(
      children: [
        RobotAvatar(seed: maker.hex, size: 36),
        const Gap(BullSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                maker.nickname,
                style: text.headlineLarge?.copyWith(color: colors.text),
              ),
              Text(
                [l10n.p2pOrderMaker, ?activity].join(' · '),
                style: text.labelMedium?.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
