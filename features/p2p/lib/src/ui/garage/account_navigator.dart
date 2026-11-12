import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';

/// « ‹ Robot #N › », the robot navigator of the official client (`basic/GaragePage/AccountNavigator.tsx` at commit ff1998c): the previous robot, disabled at robot 0, and the next one.
///
/// Troc derives each robot on the device and asks no coordinator about it.
class AccountNavigator extends StatelessWidget {
  final int index;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const AccountNavigator({
    super.key,
    required this.index,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: l10n.p2pGaragePreviousAccount,
          onPressed: index == 0 ? null : onPrevious,
          icon: const Icon(Icons.chevron_left),
          color: colors.text,
          disabledColor: colors.textMuted,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 96),
          child: Text(
            '${l10n.p2pGarageRobotLabel} #$index',
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(
              color: colors.text,
              // No monospace token in the theme yet: the family is the platform's own, as on the Silent Payments settings.
              fontFamily: 'monospace',
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.p2pGarageNextAccount,
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          color: colors.text,
          disabledColor: colors.textMuted,
        ),
      ],
    );
  }
}
