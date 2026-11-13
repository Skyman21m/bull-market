import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/p2p_failure.dart';
import '../../domain/robot_on_coordinator_face.dart';
import '../../domain/tor_wait.dart';
import '../../presentation/book_cubit.dart';
import '../../presentation/book_state.dart';
import '../../presentation/coordinator_details_cubit.dart';
import '../../presentation/coordinator_text.dart';
import '../../presentation/p2p_failure_l10n.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/robot_coordinator_cubit.dart';
import '../../presentation/robot_coordinator_state.dart';
import '../widgets/coordinator_avatar.dart';
import 'robot_history_dialog.dart';
import 'select_host_sheet.dart';
import 'send_robot_dialog.dart';

/// « Coordinator that knows your robot: », under the robot navigator of the Garage profile: the coordinator of the robot shown, and what it says of the robot.
///
/// The official client shows « Coordinators that know your robot: » in its profile dialog, one line per coordinator, since it sends every robot to all of them (`components/Dialogs/Profile.tsx` and `components/RobotInfo/index.tsx` at commit ff1998c), and the orders and rewards of the robot on its Garage profile (`basic/GaragePage/GarageKeyProfile.tsx`).
/// In Troc a robot lives on one coordinator only, so the panel shows one: none yet, with « Select Host », the user's choice and never a requirement; or the coordinator of its binding, read back as soon as Tor is ready.
/// A robot reaches a coordinator from here only through « Select Host », the choice and « Continue » on the confirmation; for a key of unknown history, « Select Host » first asks « Robots from elsewhere » ([RobotHistoryDialog]), once per key and network, which the reference has no need of since it sends every robot everywhere.
/// The orders are plain text: Troc has no page for them yet.
class RobotCoordinatorPanel extends StatelessWidget {
  /// The nickname of the robot shown, for the confirmation.
  final String nickname;

  /// The network of the robot, the one of the Garage.
  final RobosatsNetwork network;

  /// Makes the cubit of the coordinator dialog, opened from « Select Host ».
  final CoordinatorDetailsCubit Function(CoordinatorDetailsRequest request)
  coordinatorDetails;

  const RobotCoordinatorPanel({
    super.key,
    required this.nickname,
    required this.network,
    required this.coordinatorDetails,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return Container(
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
          Semantics(
            header: true,
            child: Text(
              l10n.p2pRobotCoordinatorTitle,
              style: text.bodyLarge?.copyWith(
                color: colors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Gap(BullSpacing.sm),
          BlocBuilder<RobotCoordinatorCubit, RobotCoordinatorState>(
            builder: (context, state) => switch (state) {
              RobotStandingReading() => const _Progress(),
              RobotStandingUnreadable(:final failure, :final lastAttempt) =>
                switch (lastAttempt) {
                  // No request was made: nothing was sent.
                  null => _Failure(
                    message: switch (failure) {
                      P2pStorageFailure() => l10n.p2pRobotStorage,
                      _ => failure.toTranslated(context),
                    },
                    onRetry: context.read<RobotCoordinatorCubit>().retry,
                  ),
                  // A put the database refused, whose read back or first contact may have left before (a robot bound earlier, or a nickname taken read again): that the records cannot be read, never that nothing was sent (second security pass on step 5).
                  RobotAttempt(
                    problem: RobotRequestRefused(failure: P2pStorageFailure()),
                  ) =>
                    _Failure(
                      message: l10n.p2pRobotRecordsUnreadable,
                      onRetry: context.read<RobotCoordinatorCubit>().retry,
                    ),
                  // A first contact may have left: what it got, then that the records cannot be read, never that nothing was sent.
                  final attempt => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Line(
                        attempt.problem.toRobotText(
                          context,
                          coordinator: _nameOf(attempt.coordinator),
                        ),
                        color: context.bull.error,
                      ),
                      const Gap(BullSpacing.xs),
                      _Failure(
                        message: l10n.p2pRobotRecordsUnreadable,
                        onRetry: context.read<RobotCoordinatorCubit>().retry,
                      ),
                    ],
                  ),
                },
              final RobotWithoutCoordinator state => _WithoutCoordinator(
                state: state,
                onSelectHost: () => _selectHost(context),
              ),
              RobotOnCoordinator(:final coordinator, :final activity) =>
                _OnCoordinator(coordinator: coordinator, activity: activity),
              RobotOnOtherNetwork(:final network) => _Line(
                l10n.p2pRobotOnOtherNetwork(network.name),
              ),
              RobotCoordinatorChanged(:final alias, :final listed) => _Changed(
                alias: alias,
                listed: listed,
              ),
            },
          ),
        ],
      ),
    );
  }

  /// « Select Host »: for a key of unknown history, « Robots from elsewhere » first, recorded only on « I understand »; then the sheet, the confirmation, and the first contact: nothing leaves before « Continue ».
  Future<void> _selectHost(BuildContext context) async {
    final cubit = context.read<RobotCoordinatorCubit>();
    if (cubit.state case RobotWithoutCoordinator(needsAcknowledgement: true)) {
      if (!await RobotHistoryDialog.show(context) || !context.mounted) return;
      await cubit.acknowledge();
      if (!context.mounted) return;
    }
    // The sheet only for a robot that may be given a coordinator now: not when the acknowledgement could not be recorded.
    final mayChooseHost = switch (cubit.state) {
      RobotWithoutCoordinator(:final mayChooseHost) => mayChooseHost,
      _ => false,
    };
    if (!mayChooseHost) return;
    final coordinator = await SelectHostSheet.show(
      context,
      hosts: cubit.hosts(),
      offline: _offline(context.read<BookCubit>().state),
      network: network,
      coordinatorDetails: coordinatorDetails,
    );
    if (coordinator == null || !context.mounted) return;
    final confirmed = await SendRobotDialog.show(
      context,
      nickname: nickname,
      coordinator: coordinator,
    );
    if (!confirmed || !context.mounted) return;
    await cubit.putOn(coordinator);
  }

  /// The coordinators the book of the tab shows as offline: those it could not reach.
  static Set<String> _offline(BookState book) => {
    for (final MapEntry(:key, :value) in book.coordinators.entries)
      if (value case CoordinatorBookFailed(
        failure: CoordinatorNotOnNetwork() ||
            CoordinatorUnreachable() ||
            CoordinatorTimedOut() ||
            CoordinatorResponseTooLarge() ||
            CoordinatorTransportFailed(),
      ))
        key.shortAlias,
  };
}

/// The name of [coordinator] as the screens show it.
String _nameOf(Coordinator coordinator) => CoordinatorText.of(
  coordinator.longAlias,
  maxCodePoints: CoordinatorText.name,
);

class _WithoutCoordinator extends StatelessWidget {
  final RobotWithoutCoordinator state;
  final VoidCallback onSelectHost;

  const _WithoutCoordinator({required this.state, required this.onSelectHost});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final attempt = state.lastAttempt;
    final acknowledgementFailure = state.acknowledgementFailure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Line(l10n.p2pRobotNoCoordinator),
        if (attempt != null) ...[
          const Gap(BullSpacing.xs),
          _Line(
            attempt.problem.toRobotText(
              context,
              coordinator: _nameOf(attempt.coordinator),
            ),
            color: colors.error,
          ),
        ],
        // The acknowledgement was not recorded, and nothing was sent: « Select Host » asks it again.
        if (acknowledgementFailure != null) ...[
          const Gap(BullSpacing.xs),
          _Line(
            switch (acknowledgementFailure) {
              P2pStorageFailure() => l10n.p2pRobotStorage,
              _ => acknowledgementFailure.toTranslated(context),
            },
            color: colors.error,
            live: true,
          ),
        ],
        const Gap(BullSpacing.sm),
        BullButton.big(
          label: l10n.p2pRobotSelectHost,
          iconData: Icons.dns_outlined,
          iconFirst: true,
          // Disabled until Tor is ready; for a key whose history must be acknowledged, it asks that first.
          disabled: !state.maySelectHost,
          onPressed: () {
            if (state.maySelectHost) onSelectHost();
          },
          outlined: true,
          bgColor: colors.transparent,
          textColor: colors.primary,
          borderColor: colors.primary,
        ),
        if (state.tor != TorWait.ready) ...[
          const Gap(BullSpacing.xs),
          _TorLine(tor: state.tor),
        ],
      ],
    );
  }
}

class _OnCoordinator extends StatelessWidget {
  final Coordinator coordinator;
  final RobotActivity activity;

  const _OnCoordinator({required this.coordinator, required this.activity});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final name = _nameOf(coordinator);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CoordinatorRow(coordinator: coordinator),
        const Gap(BullSpacing.sm),
        ...switch (activity) {
          RobotWaitingForTor(:final tor) => [
            _TorLine(tor: tor),
            if (tor != TorWait.failed) ...[
              const Gap(BullSpacing.xs),
              const _Progress(),
            ],
          ],
          RobotContacting(:final kind, :final slow) => [
            Semantics(
              liveRegion: true,
              child: Text(
                switch (kind) {
                  RobotContactKind.create => l10n.p2pGarageBuildingRobot,
                  RobotContactKind.read => l10n.p2pRobotLookingForOrders,
                },
                style: text.bodyMedium?.copyWith(
                  color: colors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Gap(BullSpacing.xs),
            const _Progress(),
            if (slow) ...[
              const Gap(BullSpacing.xs),
              _Line(
                l10n.p2pRobotStillWaiting(name),
                color: colors.textMuted,
                live: true,
              ),
            ],
          ],
          RobotKnown(:final face) => [_Known(face: face, name: name)],
          RobotFailed(:final problem, :final kind) => [
            _Failure(
              message: switch ((problem, kind)) {
                // A put the database refused may follow its read back or its first contact: never « Nothing was sent. » (second security pass on step 5).
                (
                  RobotRequestRefused(failure: P2pStorageFailure()),
                  RobotContactKind.create,
                ) =>
                  l10n.p2pRobotRecordsUnreadable,
                _ => problem.toRobotText(context, coordinator: name),
              },
              onRetry: problem.wayOut == RobotWayOut.none
                  ? null
                  : context.read<RobotCoordinatorCubit>().retry,
            ),
          ],
        },
      ],
    );
  }
}

/// What the coordinator says of the robot: its order, if any, then what the user should know.
class _Known extends StatelessWidget {
  final RobotOnCoordinatorFace face;
  final String name;

  const _Known({required this.face, required this.name});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final active = face.activeOrderId;
    final last = face.lastOrderId;
    final rewards = face.earnedRewards.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Line(switch ((active, last)) {
          (final active?, _) => l10n.p2pRobotActiveOrder('$active'),
          (null, final last?) => l10n.p2pRobotLastOrder('$last'),
          (null, null) => l10n.p2pRobotNoOrders,
        }, live: true),
        // As the official client, which counts a last order of unknown status as used: Troc does not read the order yet.
        if (active == null && last != null) ...[
          const Gap(BullSpacing.sm),
          BullInfoBar(
            message: l10n.p2pRobotUsedInTrade,
            icon: Icons.info_outline,
          ),
        ],
        if (rewards > BigInt.zero) ...[
          const Gap(BullSpacing.sm),
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(Icons.emoji_events, color: colors.bitcoinOrange),
              ),
              const Gap(BullSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.p2pRobotRewards,
                      style: text.labelMedium?.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    Text(
                      l10n.p2pAmountSats(
                        rewards.isValidInt
                            ? P2pFormats.of(context).sats(rewards.toInt())
                            : '$rewards',
                      ),
                      style: text.bodyLarge?.copyWith(color: colors.text),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        // Only when the first contact this panel asked for came back with another pair, after « Select Host » or « Retry » alike: see `RobotOnCoordinatorFace.alreadyExisted`.
        if (face.alreadyExisted) ...[
          const Gap(BullSpacing.sm),
          _Line(l10n.p2pRobotAlreadyExisted(name), color: colors.textMuted),
        ],
        ...switch (face.nostrKey) {
          RobotNostrKeyStatus.current => const <Widget>[],
          RobotNostrKeyStatus.old => [
            const Gap(BullSpacing.sm),
            BullInfoBar(
              message: l10n.p2pRobotNostrOld(name),
              tone: BullInfoTone.warning,
              icon: Icons.warning_amber,
            ),
          ],
          RobotNostrKeyStatus.unknown => [
            const Gap(BullSpacing.sm),
            BullInfoBar(
              message: l10n.p2pRobotNostrUnknown(name),
              tone: BullInfoTone.warning,
              icon: Icons.warning_amber,
            ),
          ],
        },
      ],
    );
  }
}

/// The robot's coordinator changed its address or keys, or left the list: no request, no way out but another robot.
class _Changed extends StatelessWidget {
  final String alias;
  final Coordinator? listed;

  const _Changed({required this.alias, required this.listed});

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final listed = this.listed;
    final name = listed == null
        ? CoordinatorText.of(alias, maxCodePoints: CoordinatorText.name)
        : _nameOf(listed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (listed != null) ...[
          _CoordinatorRow(coordinator: listed),
          const Gap(BullSpacing.sm),
        ],
        BullInfoBar(
          message: l10n.p2pRobotCoordinatorChanged(name),
          tone: BullInfoTone.warning,
          icon: Icons.warning_amber,
        ),
      ],
    );
  }
}

/// The avatar and the long alias of the robot's coordinator.
class _CoordinatorRow extends StatelessWidget {
  final Coordinator coordinator;

  const _CoordinatorRow({required this.coordinator});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        CoordinatorAvatar(coordinator: coordinator, size: 40),
        const Gap(BullSpacing.sm),
        Expanded(
          child: Text(
            _nameOf(coordinator),
            style: text.headlineLarge?.copyWith(color: colors.text),
          ),
        ),
      ],
    );
  }
}

/// What Tor is doing while the panel waits for it: the texts of the Tor states of the official client's menu.
class _TorLine extends StatelessWidget {
  final TorWait tor;

  const _TorLine({required this.tor});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    return _Line(
      tor == TorWait.failed
          ? l10n.p2pTorConnectionError
          : l10n.p2pTorConnecting,
      color: tor == TorWait.failed ? colors.error : colors.textMuted,
      live: true,
    );
  }
}

/// Why the last request failed, and « Retry » when it helps.
class _Failure extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _Failure({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final onRetry = this.onRetry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Line(message, color: colors.error, live: true),
        if (onRetry != null) ...[
          const Gap(BullSpacing.sm),
          BullButton.big(
            label: l10n.p2pCommonRetry,
            iconData: Icons.refresh,
            iconFirst: true,
            onPressed: onRetry,
            outlined: true,
            bgColor: colors.transparent,
            textColor: colors.primary,
            borderColor: colors.primary,
          ),
        ],
      ],
    );
  }
}

/// A line of the panel, which wraps at any text size; a screen reader reads a [live] line out when it changes.
class _Line extends StatelessWidget {
  final String text;
  final Color? color;
  final bool live;

  const _Line(this.text, {this.color, this.live = false});

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: live,
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: color ?? context.bull.text),
    ),
  );
}

/// The bar of a wait: it runs until the wait ends, with reduced motion too, as the waits of the tab do before they know a share.
class _Progress extends StatelessWidget {
  const _Progress();

  @override
  Widget build(BuildContext context) =>
      LinearProgressIndicator(color: context.bull.primary);
}
