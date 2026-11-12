import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';

/// « You do not have a Garage Key », what the official client shows when a page needs a robot the user does not have (`components/Dialogs/NoRobot.tsx` at commit ff1998c).
///
/// « I have a Garage Key » closes it and opens the Garage, as in the official client, when [onOpenGarage] is given: the Garage is there only when the feature has the vault's handle.
/// « Generate Garage Key » is shown disabled: the official client makes a key and a robot on the coordinators from it, which Troc does not do yet.
/// A tap outside closes it, as in the official client.
class NoRobotDialog extends StatelessWidget {
  final VoidCallback? onOpenGarage;

  const NoRobotDialog({super.key, this.onOpenGarage});

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onOpenGarage,
  }) => BullDialog.show<void>(
    context: context,
    builder: (_) => NoRobotDialog(onOpenGarage: onOpenGarage),
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
            onPressed: () {
              Navigator.of(context).pop();
              onOpenGarage?.call();
            },
            disabled: onOpenGarage == null,
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
