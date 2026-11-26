import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:screen_privacy/screen_privacy.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/network_garage_key.dart';
import '../../domain/p2p_failure.dart';
import '../../domain/trade_record.dart';
import '../../presentation/coordinator_details_cubit.dart';
import '../../presentation/garage_cubit.dart';
import '../../presentation/garage_state.dart';
import '../../presentation/order_history_cubit.dart';
import '../../presentation/p2p_failure_l10n.dart';
import '../../presentation/robot_coordinator_cubit.dart';
import '../widgets/garage_key_clipboard.dart';
import 'delete_garage_key_dialog.dart';
import 'garage_profile.dart';
import 'garage_reauthentication.dart';

/// The Garage of the P2P tab, for the network of its [GarageCubit] (#81): the profile of the key shown, a key of the default wallet's words or the external key; and what to do when no key can be shown.
///
/// Every screen of the Garage shows a Garage Key or leads to one: the whole Garage is protected from screenshots, screen recording and the preview of recent apps, as the wallet protects its seeds (`PrivacyScreen`), and nothing of it is drawn until the protection said it is on.
/// Where the platform refuses it, the Garage shows that the key stays hidden, with « Retry », and nothing else; the dialogs and the re-authentication opened from it stay under the same protection, which lasts until the Garage is left.
/// The user may turn the protection off in the settings of the wallet, which then applies here too.
/// There is no wizard and no welcome screen any more: at the first opening, key 0 is there.
class GarageView extends StatefulWidget {
  final GarageKeyClipboard clipboard;
  final P2pReauthentication? reauthenticate;

  /// Makes the cubit of the panel of the robot at an index of a Garage Key, on the profile.
  final RobotCoordinatorCubit Function(NetworkGarageKey key, int index)
  robotCoordinator;

  /// Makes the cubit of the coordinator dialog, opened from « Select Host ».
  final CoordinatorDetailsCubit Function(CoordinatorDetailsRequest request)
  coordinatorDetails;

  /// Opens the trade of « Last order #N » on the profile (#216), with a `LastOrdersCubit` above the Garage; `null` where the feature holds no trades, and the profile shows no such line.
  final Future<void> Function(TradeRecord record)? onOpenTrade;

  /// Makes the cubit of the history of finished orders of a Garage Key, under « Last order #N » on the profile (#253); `null` where the feature holds no trades, and the profile shows no history.
  final OrderHistoryCubit Function(NetworkGarageKey key)? orderHistory;

  const GarageView({
    super.key,
    required this.clipboard,
    required this.reauthenticate,
    required this.robotCoordinator,
    required this.coordinatorDetails,
    this.onOpenTrade,
    this.orderHistory,
  });

  @override
  State<GarageView> createState() => _GarageViewState();
}

class _GarageViewState extends State<GarageView> with PrivacyScreen {
  late Future<bool> _protection = enableScreenPrivacy();

  @override
  void dispose() {
    unawaited(disableScreenPrivacy());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return BullScreenPrivacyGate(
      protection: _protection,
      unavailableMessage: l10n.p2pGarageScreenPrivacyUnavailable,
      retryLabel: l10n.p2pCommonRetry,
      onRetry: () => setState(() {
        _protection = enableScreenPrivacy();
      }),
      // Reading the cubit in the builder creates it, so only once the protection is on.
      builder: (context) => BlocBuilder<GarageCubit, GarageState>(
        builder: (context, state) => switch (state) {
          GarageUnknown() => _GarageUnavailable(
            state: state,
            reauthenticate: widget.reauthenticate,
          ),
          GarageWithKey() => GarageProfile(
            state: state,
            clipboard: widget.clipboard,
            reauthenticate: widget.reauthenticate,
            robotCoordinator: widget.robotCoordinator,
            coordinatorDetails: widget.coordinatorDetails,
            onOpenTrade: widget.onOpenTrade,
            orderHistory: widget.orderHistory,
          ),
          GarageWorking() => Center(
            child: CircularProgressIndicator(color: context.bull.primary),
          ),
        },
      ),
    );
  }
}

/// No key can be shown: why, then « Retry ». Nothing is drawn from here, and no key of the words is deleted: the words remake them.
///
/// When the key that cannot be shown is the external key, selected, the way back to the highest key of the words, and, unless the keystore is only locked, the way out of that key, as before #81: « Delete Garage Key? », then the PIN, which such a delete always asks; without [reauthenticate], that delete is disabled.
class _GarageUnavailable extends StatelessWidget {
  final GarageUnknown state;
  final P2pReauthentication? reauthenticate;

  const _GarageUnavailable({required this.state, required this.reauthenticate});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final cubit = context.read<GarageCubit>();
    final failure = state.failure;
    final externalHighest = state.externalHighest;
    final locked = failure is GarageKeyLockedFailure;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BullSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.actionFailure case final action?) ...[
            Text(
              action.toTranslated(context),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.error),
            ),
            const Gap(BullSpacing.sm),
          ],
          if (externalHighest != null) ...[
            Text(
              l10n.p2pGarageExternalKey,
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(color: colors.text),
            ),
            const Gap(BullSpacing.sm),
          ],
          Text(
            // A database that cannot be read says so: the keys activated on this device are recorded there (#81).
            failure is P2pStorageFailure
                ? l10n.p2pRobotRecordsUnreadable
                : failure.toTranslated(context),
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: colors.text),
          ),
          if (externalHighest != null && !locked) ...[
            const Gap(BullSpacing.sm),
            Text(
              l10n.p2pGarageKeyUnreadableHelp,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.textMuted),
            ),
          ],
          const Gap(BullSpacing.lg),
          BullButton.big(
            label: l10n.p2pCommonRetry,
            iconData: Icons.refresh,
            iconFirst: true,
            onPressed: cubit.load,
            bgColor: colors.primary,
            textColor: colors.onPrimary,
          ),
          if (externalHighest != null) ...[
            const Gap(BullSpacing.sm),
            BullButton.big(
              label: l10n.p2pGarageKeyNumber(externalHighest),
              iconData: Icons.chevron_left,
              iconFirst: true,
              onPressed: cubit.previousKey,
              outlined: true,
              bgColor: colors.transparent,
              textColor: colors.primary,
              borderColor: colors.primary,
            ),
            if (!locked) ...[
              const Gap(BullSpacing.sm),
              BullButton.big(
                label: l10n.p2pDeleteKeyConfirm,
                iconData: Icons.delete_sweep,
                iconFirst: true,
                disabled: reauthenticate == null,
                onPressed: () async {
                  if (reauthenticate == null ||
                      !await DeleteGarageKeyDialog.show(context) ||
                      !context.mounted) {
                    return;
                  }
                  await cubit.delete(
                    reauthenticate: reauthenticationFrom(
                      context,
                      reauthenticate,
                    ),
                  );
                },
                outlined: true,
                bgColor: colors.transparent,
                textColor: colors.error,
                borderColor: colors.error,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
