import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/robot_host.dart';
import '../../presentation/coordinator_details_cubit.dart';
import '../../presentation/coordinator_text.dart';
import '../coordinator_details_dialog.dart';
import '../widgets/coordinator_avatar.dart';
import 'closes_with_panel.dart';

/// « Select Host »: the coordinators a robot may be put on, with the label of the official client's coordinator choice (`components/BookTable/BookControl.tsx` and `components/MakerForm/SelectCoordinator.tsx` at commit ff1998c), as a sheet of the wallet's design.
///
/// It lists the coordinators of the federation list with an onion address on the robot's network, in the order of the federation, each with its avatar and long alias, « Coordinator offline » when the book of the tab could not reach it, and an info button that opens the coordinator dialog.
/// A coordinator that refused too many robots in this run of the app is shown, disabled, with why.
/// Choosing one sends nothing: the screen asks for a confirmation first.
class SelectHostSheet extends StatelessWidget {
  final List<RobotHost> hosts;

  /// The short aliases of the coordinators the book of the tab could not reach.
  final Set<String> offline;

  final RobosatsNetwork network;
  final CoordinatorDetailsCubit Function(CoordinatorDetailsRequest request)
  coordinatorDetails;

  const SelectHostSheet({
    super.key,
    required this.hosts,
    required this.offline,
    required this.network,
    required this.coordinatorDetails,
  });

  /// Opens the sheet; completes with the coordinator chosen, or `null` when it is closed without a choice.
  ///
  /// It closes, without a choice, when [closeWhen] completes: when the panel that opened it is gone (security review of step 6).
  static Future<Coordinator?> show(
    BuildContext context, {
    required List<RobotHost> hosts,
    required Set<String> offline,
    required RobosatsNetwork network,
    required CoordinatorDetailsCubit Function(CoordinatorDetailsRequest request)
    coordinatorDetails,
    required Future<void> closeWhen,
  }) => BullBottomSheet.show<Coordinator>(
    context: context,
    child: ClosesWithPanel(
      until: closeWhen,
      child: SelectHostSheet(
        hosts: hosts,
        offline: offline,
        network: network,
        coordinatorDetails: coordinatorDetails,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Gap(BullSpacing.md),
          Row(
            children: [
              const Gap(48),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.p2pRobotSelectHost,
                    textAlign: TextAlign.center,
                    style: text.headlineMedium?.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                iconSize: 20,
                onPressed: () => Navigator.of(context).pop(),
                color: colors.onSurface,
                icon: const Icon(Icons.close),
              ),
              const Gap(BullSpacing.md),
            ],
          ),
          const Gap(BullSpacing.sm),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final host in hosts)
                  _HostTile(
                    host: host,
                    offline: offline.contains(host.coordinator.shortAlias),
                    onDetails: () => CoordinatorDetailsDialog.show(
                      context,
                      () => coordinatorDetails(
                        CoordinatorDetailsRequest(host.coordinator, network),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Gap(BullSpacing.lg),
        ],
      ),
    );
  }
}

/// One coordinator of the sheet: a tap chooses it, unless it refuses first contacts; the info button opens its dialog.
class _HostTile extends StatelessWidget {
  final RobotHost host;
  final bool offline;
  final VoidCallback onDetails;

  const _HostTile({
    required this.host,
    required this.offline,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final coordinator = host.coordinator;
    final name = CoordinatorText.of(
      coordinator.longAlias,
      maxCodePoints: CoordinatorText.name,
    );
    final enabled = !host.refusesFirstContacts;
    final notes = [
      if (offline) l10n.p2pCoordinatorOffline,
      if (!enabled) l10n.p2pRobotCoordinatorTooManyRefusals,
    ];
    return ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: BullSpacing.lg),
      leading: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: CoordinatorAvatar(coordinator: coordinator, size: 40),
      ),
      title: Text(
        name,
        style: text.headlineSmall?.copyWith(
          color: enabled ? colors.onSurface : colors.textMuted,
        ),
      ),
      subtitle: notes.isEmpty
          ? null
          : Text(
              notes.join('\n'),
              style: text.labelMedium?.copyWith(color: colors.textMuted),
            ),
      trailing: IconButton(
        tooltip: l10n.p2pRobotHostDetails(name),
        onPressed: onDetails,
        color: colors.onSurface,
        icon: const Icon(Icons.info_outline),
      ),
      onTap: enabled ? () => Navigator.of(context).pop(coordinator) : null,
    );
  }
}
