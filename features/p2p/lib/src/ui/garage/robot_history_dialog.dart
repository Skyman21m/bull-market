import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';

/// « Robots from elsewhere »: what « Select Host » asks first for a robot of a Garage Key of unknown history, pasted in or whose draw this device could not record, once per key and network.
///
/// The official client has no such step: it sends each robot it shows to every coordinator, so the robots of such a key may already live on coordinators.
/// Troc puts a robot on one coordinator only, so the dialog says where to put each robot and that a new Garage Key starts clean; it states facts, for a key from the user's own backup as for any other.
/// Only « I understand » goes on, and the screen then records the acknowledgement; « Cancel », a system back or a tap outside records nothing and opens nothing.
class RobotHistoryDialog extends StatelessWidget {
  const RobotHistoryDialog({super.key});

  /// Opens the dialog; completes with `true` only when the user pressed « I understand ».
  static Future<bool> show(BuildContext context) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => const RobotHistoryDialog(),
      ) ??
      false;

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
          Semantics(
            header: true,
            child: Text(
              l10n.p2pRobotHistoryTitle,
              style: text.headlineLarge?.copyWith(color: colors.text),
            ),
          ),
          const Gap(BullSpacing.md),
          Text(
            l10n.p2pRobotHistoryBody,
            style: text.bodyLarge?.copyWith(color: colors.text),
          ),
          const Gap(BullSpacing.lg),
          BullButton.big(
            label: l10n.p2pRobotHistoryConfirm,
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
