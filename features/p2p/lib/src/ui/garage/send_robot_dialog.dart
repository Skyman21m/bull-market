import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../presentation/coordinator_text.dart';

/// « Send {nickname} to {coordinator}? »: the confirmation before a robot's first contact, the only way a robot reaches a coordinator from the Garage.
///
/// The official client asks nothing: it sends every robot it shows to every coordinator.
/// Troc asks once per robot, since a robot lives on one coordinator only and an account there cannot be deleted; it says that another app holding the same Garage Key may send the robot everywhere.
/// A tap outside, a system back or « Cancel » sends nothing.
class SendRobotDialog extends StatelessWidget {
  final String nickname;
  final Coordinator coordinator;

  const SendRobotDialog({
    super.key,
    required this.nickname,
    required this.coordinator,
  });

  /// Opens the dialog; completes with `true` only when the user pressed « Continue ».
  static Future<bool> show(
    BuildContext context, {
    required String nickname,
    required Coordinator coordinator,
  }) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) =>
            SendRobotDialog(nickname: nickname, coordinator: coordinator),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final name = CoordinatorText.of(
      coordinator.longAlias,
      maxCodePoints: CoordinatorText.name,
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.p2pRobotSendTitle(nickname, name),
              style: text.headlineLarge?.copyWith(color: colors.text),
            ),
          ),
          const Gap(BullSpacing.md),
          Text(
            l10n.p2pRobotSendBody(name),
            style: text.bodyLarge?.copyWith(color: colors.text),
          ),
          const Gap(BullSpacing.md),
          Text(
            l10n.p2pRobotSendOtherApp,
            style: text.bodyMedium?.copyWith(color: colors.textMuted),
          ),
          const Gap(BullSpacing.lg),
          BullButton.big(
            label: l10n.p2pCommonContinue,
            onPressed: () => Navigator.of(context).pop(true),
            bgColor: colors.primary,
            textColor: colors.onPrimary,
          ),
          const Gap(BullSpacing.sm),
          BullButton.big(
            label: l10n.p2pCommonCancel,
            onPressed: () => Navigator.of(context).pop(false),
            outlined: true,
            bgColor: colors.transparent,
            textColor: colors.primary,
            borderColor: colors.primary,
          ),
        ],
      ),
    );
  }
}
