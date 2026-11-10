import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';

/// « Reversible payments »: the warning the official client shows for an order whose payment methods the community reports as reverting their transactions (`components/OrderDetails/index.tsx`).
///
/// The method names come from the official list, not from the maker's text.
class ReversiblePaymentsDialog extends StatelessWidget {
  final PaymentMethods methods;

  const ReversiblePaymentsDialog({super.key, required this.methods});

  /// Opens the warning for [methods].
  static Future<void> show(BuildContext context, PaymentMethods methods) =>
      BullDialog.show<void>(
        context: context,
        builder: (_) => ReversiblePaymentsDialog(methods: methods),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final body = text.bodyMedium?.copyWith(color: colors.text);
    final reversible = [
      for (final method in methods.recognized)
        if (method.reversible) method.name,
    ];
    Widget point(String line, {bool bold = false}) => Padding(
      padding: const EdgeInsets.only(top: BullSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•', style: body),
          const Gap(BullSpacing.xs),
          Expanded(
            child: Text(
              line,
              style: bold ? body?.copyWith(fontWeight: FontWeight.w700) : body,
            ),
          ),
        ],
      ),
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.warning),
              const Gap(BullSpacing.xs),
              Expanded(
                child: Text(
                  l10n.p2pReversibleTitle,
                  style: text.headlineLarge?.copyWith(color: colors.text),
                ),
              ),
            ],
          ),
          const Gap(BullSpacing.sm),
          Text(l10n.p2pReversibleIntro, style: body),
          const Gap(BullSpacing.sm),
          Center(
            child: Text(
              reversible.join(' · '),
              textAlign: TextAlign.center,
              style: text.headlineMedium?.copyWith(color: colors.warning),
            ),
          ),
          const Gap(BullSpacing.xs),
          point(l10n.p2pReversible80Days, bold: true),
          point(l10n.p2pReversibleNoControl),
          point(l10n.p2pReversibleScammers),
          const Gap(BullSpacing.md),
          BullButton.big(
            label: l10n.p2pCommonAcknowledged,
            onPressed: () => Navigator.of(context).pop(),
            bgColor: colors.primary,
            textColor: colors.onPrimary,
          ),
        ],
      ),
    );
  }
}
