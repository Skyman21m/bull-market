import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';

/// « You do not have a Garage Key », what the official client shows when a page needs a robot the user does not have (`components/Dialogs/NoRobot.tsx` at commit ff1998c).
///
/// Its two ways out, to the Garage and to a new Garage Key, are shown disabled: the Garage of Troc is not there yet.
/// A tap outside closes it, as in the official client.
class NoRobotDialog extends StatelessWidget {
  const NoRobotDialog({super.key});

  static Future<void> show(BuildContext context) => BullDialog.show<void>(
    context: context,
    builder: (_) => const NoRobotDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.p2pNoRobotTitle,
            style: text.headlineLarge?.copyWith(color: colors.text),
          ),
          const Gap(BullSpacing.md),
          Text(
            l10n.p2pNoRobotText,
            style: text.bodyMedium?.copyWith(color: colors.textMuted),
          ),
          const Gap(BullSpacing.lg),
          BullButton.big(
            label: l10n.p2pNoRobotHaveKey,
            iconData: Icons.key,
            iconFirst: true,
            onPressed: () {},
            disabled: true,
            outlined: true,
            bgColor: colors.transparent,
            textColor: colors.primary,
            borderColor: colors.primary,
          ),
          const Gap(BullSpacing.sm),
          BullButton.big(
            label: l10n.p2pGarageOnboardingGenerateKey,
            iconData: Icons.add,
            iconFirst: true,
            onPressed: () {},
            disabled: true,
            bgColor: colors.primary,
            textColor: colors.onPrimary,
          ),
        ],
      ),
    );
  }
}
