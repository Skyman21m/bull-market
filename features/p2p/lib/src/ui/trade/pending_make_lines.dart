import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/robot_binding.dart';
import '../../domain/trade/trade_make.dart';
import '../../domain/trade_record.dart';
import '../../presentation/coordinator_text.dart';
import '../../presentation/make_order_l10n.dart';
import '../../presentation/pending_makes_cubit.dart';
import '../widgets/coordinator_avatar.dart';
import '../widgets/trade_dialog_body.dart';

/// The lines of the pending makes of a network (#182, design note § 3.4): « Creating your order… » with its coordinator, where its resolution stands, « Retry », and « Set aside » once a resolution left it pending (a make that does not resolve: its coordinator gone or moved, its robot unknown, an order not its own, an outcome unknown again), from the [PendingMakesCubit] above; then why the last make a resolution closed made no order.
///
/// A make a resolution confirms is opened by the screen that holds the cubit (its `started`), not here.
class PendingMakeLines extends StatelessWidget {
  /// When given, only the makes of these robots are listed: the create form, while it sends a make itself, lists the makes it saw listed when it sent it, and not its own, recorded as pending just before its request leaves (#317); `null` lists every make.
  final Set<RobotSlot>? only;

  const PendingMakeLines({super.key, this.only});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final state = context.watch<PendingMakesCubit>().state;
    final closed = state.closed;
    final closedAlias = state.closedAlias;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.unreadable)
          Text(
            l10n.p2pRobotRecordsUnreadable,
            style: text.bodyMedium?.copyWith(color: colors.error),
          ),
        for (final make in state.makes ?? const <ActivePendingMake>[])
          if (only?.contains(make.make.robot) ?? true)
            _Line(make: make.make, step: state.steps[make.make.robot]),
        if (closed != null && closedAlias != null)
          Semantics(
            container: true,
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: BullSpacing.xs),
              child: Text(
                closed.toText(context, coordinator: nameOf(closedAlias)),
                style: text.bodyMedium?.copyWith(color: colors.textMuted),
              ),
            ),
          ),
      ],
    );
  }

  /// The long alias of the coordinator [alias], as the federation list gives it, else the alias recorded.
  static String nameOf(String alias) => CoordinatorText.of(
    Federation.robosats.byAlias(alias)?.longAlias ?? alias,
    maxCodePoints: CoordinatorText.name,
  );
}

class _Line extends StatelessWidget {
  final PendingMake make;
  final PendingMakeStep? step;

  const _Line({required this.make, required this.step});

  Future<void> _setAside(BuildContext context, String name) async {
    final cubit = context.read<PendingMakesCubit>();
    final l10n = P2pLocalizations.of(context);
    final confirmed =
        await BullDialog.show<bool>(
          context: context,
          builder: (dialog) => TradeDialogBody(
            title: l10n.p2pPendingMakeSetAsideTitle,
            text: l10n.p2pPendingMakeSetAsideText(name),
            backLabel: l10n.p2pCommonGoBack,
            onBack: () => Navigator.of(dialog).pop(false),
            goLabel: l10n.p2pPendingMakeSetAside,
            backFirst: true,
            onGo: () => Navigator.of(dialog).pop(true),
          ),
        ) ??
        false;
    if (confirmed) await cubit.dismiss(make);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final coordinator = Federation.robosats.byAlias(make.coordinatorAlias);
    final name = PendingMakeLines.nameOf(make.coordinatorAlias);
    final step = this.step;
    final checking = step is PendingMakeChecking;
    final said = switch (step) {
      PendingMakeChecking() => l10n.p2pPendingMakeChecking(name),
      PendingMakeLeftPending() => l10n.p2pPendingMakeUnknown(name),
      PendingMakeNotSetAside() => l10n.p2pRobotRecordsUnreadable,
      null => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BullSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (coordinator != null) ...[
                ExcludeSemantics(
                  child: CoordinatorAvatar(coordinator: coordinator, size: 32),
                ),
                const Gap(BullSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.p2pMakeCreating,
                      style: text.bodyLarge?.copyWith(color: colors.text),
                    ),
                    Text(
                      name,
                      style: text.labelMedium?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (said != null) ...[
            const Gap(BullSpacing.xs),
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                said,
                style: text.bodyMedium?.copyWith(
                  color: step is PendingMakeNotSetAside
                      ? colors.error
                      : colors.textMuted,
                ),
              ),
            ),
          ],
          if (checking) ...[
            const Gap(BullSpacing.xs),
            LinearProgressIndicator(color: colors.primary),
          ],
          Wrap(
            alignment: WrapAlignment.end,
            spacing: BullSpacing.sm,
            children: [
              TextButton(
                onPressed: checking
                    ? null
                    : () => unawaited(
                        context.read<PendingMakesCubit>().resolve(make),
                      ),
                child: Text(
                  l10n.p2pCommonRetry,
                  style: TextStyle(color: checking ? null : colors.primary),
                ),
              ),
              if (step is PendingMakeLeftPending ||
                  step is PendingMakeNotSetAside)
                TextButton(
                  onPressed: () => unawaited(_setAside(context, name)),
                  child: Text(
                    l10n.p2pPendingMakeSetAside,
                    style: TextStyle(color: colors.secondary),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
