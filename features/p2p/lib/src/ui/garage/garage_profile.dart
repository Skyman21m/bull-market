import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../presentation/garage_cubit.dart';
import '../../presentation/garage_state.dart';
import '../../presentation/p2p_failure_l10n.dart';
import '../widgets/garage_key_clipboard.dart';
import '../widgets/garage_key_view.dart';
import '../widgets/robot_avatar.dart';
import 'account_navigator.dart';
import 'delete_garage_key_dialog.dart';
import 'garage_reauthentication.dart';
import 'garage_wizard.dart' show RobotNickname;

/// The profile of the Garage when a Garage Key is stored, as the official client draws it (`basic/GaragePage/GarageKeyProfile.tsx` at commit ff1998c): the nickname, the avatar, the robot navigator, then the Garage Key and « Delete All ».
///
/// The Garage Key is hidden until the user asks for it and passes the app's own re-authentication, the PIN the wallet asks before it shows its seeds, which [reauthenticate] brings from the shell; the official client shows it at once.
/// Without [reauthenticate] the key cannot be shown here at all.
/// What needs a coordinator is not shown: the settings of the robot, its orders and rewards, and whether it was used in a trade.
class GarageProfile extends StatefulWidget {
  final GarageWithKey state;
  final GarageKeyClipboard clipboard;
  final P2pReauthentication? reauthenticate;

  const GarageProfile({
    super.key,
    required this.state,
    required this.clipboard,
    required this.reauthenticate,
  });

  @override
  State<GarageProfile> createState() => _GarageProfileState();
}

class _GarageProfileState extends State<GarageProfile> {
  /// Whether the key is shown: only once the re-authentication said so, and until the profile is left.
  bool _revealed = false;

  Future<void> _reveal(P2pReauthentication reauthenticate) async {
    if (await askReauthentication(context, reauthenticate) && mounted) {
      setState(() => _revealed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final cubit = context.read<GarageCubit>();
    final state = widget.state;
    final robot = state.robot;
    final reauthenticate = widget.reauthenticate;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BullSpacing.md),
      child: Column(
        children: [
          RobotNickname(nickname: robot.nickname),
          const Gap(BullSpacing.sm),
          Tooltip(
            message: l10n.p2pGarageTradingAvatar,
            child: RobotAvatar(seed: robot.hashId, size: 160),
          ),
          const Gap(BullSpacing.sm),
          AccountNavigator(
            index: robot.index,
            onPrevious: cubit.previous,
            onNext: cubit.next,
          ),
          if (state.failure case final failure?) ...[
            const Gap(BullSpacing.xs),
            Text(
              failure.toTranslated(context),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.error),
            ),
          ],
          const Gap(BullSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(BullSpacing.md),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(BullRadius.xxs),
              border: Border.all(color: colors.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.p2pGarageKeyLabel,
                  style: text.labelMedium?.copyWith(color: colors.textMuted),
                ),
                const Gap(BullSpacing.xs),
                if (_revealed)
                  GarageKeyView(
                    garageKey: state.key.key,
                    clipboard: widget.clipboard,
                  )
                else
                  BullButton.big(
                    label: l10n.p2pGarageKeyReveal,
                    iconData: Icons.visibility,
                    iconFirst: true,
                    disabled: reauthenticate == null,
                    onPressed: () {
                      if (reauthenticate != null) _reveal(reauthenticate);
                    },
                    outlined: true,
                    bgColor: colors.transparent,
                    textColor: colors.primary,
                    borderColor: colors.primary,
                  ),
                const Gap(BullSpacing.xs),
                Text(
                  l10n.p2pGarageKeyHelper,
                  style: text.labelMedium?.copyWith(color: colors.textMuted),
                ),
                const Gap(BullSpacing.md),
                Center(
                  child: Tooltip(
                    message: l10n.p2pGarageProfileDeleteAllTooltip,
                    child: TextButton.icon(
                      onPressed: () async {
                        if (await DeleteGarageKeyDialog.show(context)) {
                          await cubit.delete();
                        }
                      },
                      icon: Icon(Icons.delete_sweep, color: colors.error),
                      label: Text(
                        l10n.p2pGarageProfileDeleteAll,
                        style: text.labelLarge?.copyWith(color: colors.error),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
