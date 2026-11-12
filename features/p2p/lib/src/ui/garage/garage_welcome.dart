import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/p2p_failure.dart';
import '../../presentation/p2p_failure_l10n.dart';

/// The welcome screen of the Garage when no Garage Key is stored for the network, as the official client draws it (`basic/RobotPage/Welcome.tsx` at commit ff1998c), in the same order.
///
/// « Start » opens the wizard, « Recovery » the dialog where a key is pasted, and « Search for Orders » shows the offers, where the official client opens its guided search, which Troc does not have.
/// « Fast Generate Order » makes a key and a robot then opens « Create », which comes in a later phase: it is shown disabled.
/// Where the official client draws its logo, Troc has none yet and shows the tagline alone.
class GarageWelcome extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onRecovery;
  final VoidCallback onSearchOrders;

  /// Why the last action failed, when it did.
  final P2pFailure? failure;

  const GarageWelcome({
    super.key,
    required this.onStart,
    required this.onRecovery,
    required this.onSearchOrders,
    this.failure,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    Widget textButton(String label, IconData icon, VoidCallback? onPressed) =>
        TextButton.icon(
          onPressed: onPressed,
          icon: Icon(
            icon,
            color: onPressed == null ? colors.textMuted : colors.primary,
          ),
          label: Text(
            label,
            style: text.labelLarge?.copyWith(
              color: onPressed == null ? colors.textMuted : colors.primary,
            ),
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BullSpacing.md),
      child: Column(
        children: [
          const Gap(BullSpacing.lg),
          Text(
            l10n.p2pGarageWelcomeTagline,
            textAlign: TextAlign.center,
            style: text.headlineLarge?.copyWith(color: colors.secondary),
          ),
          const Gap(BullSpacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(BullSpacing.md),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(BullRadius.xxs),
              border: Border.all(color: colors.outline),
            ),
            child: Column(
              children: [
                Text(
                  l10n.p2pGarageWelcomeCreateRobot,
                  textAlign: TextAlign.center,
                  style: text.bodyLarge?.copyWith(color: colors.text),
                ),
                const Gap(BullSpacing.sm),
                BullButton.big(
                  label: l10n.p2pGarageWelcomeStart,
                  iconData: Icons.rocket_launch,
                  iconFirst: true,
                  onPressed: onStart,
                  bgColor: colors.primary,
                  textColor: colors.onPrimary,
                ),
                const Gap(BullSpacing.md),
                Text(
                  l10n.p2pGarageWelcomeRecoverHint,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: colors.text),
                ),
                textButton(
                  l10n.p2pGarageWelcomeRecovery,
                  Icons.key,
                  onRecovery,
                ),
              ],
            ),
          ),
          if (failure case final failure?) ...[
            const Gap(BullSpacing.sm),
            Text(
              failure.toTranslated(context),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.error),
            ),
          ],
          const Gap(BullSpacing.sm),
          textButton(
            l10n.p2pGarageWelcomeSearchForOrders,
            Icons.search,
            onSearchOrders,
          ),
          textButton(
            l10n.p2pGarageWelcomeFastGenerateOrder,
            Icons.fast_forward,
            null,
          ),
        ],
      ),
    );
  }
}
