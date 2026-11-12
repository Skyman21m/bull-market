import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:screen_privacy/screen_privacy.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/p2p_failure.dart';
import '../../presentation/garage_cubit.dart';
import '../../presentation/garage_state.dart';
import '../../presentation/p2p_failure_l10n.dart';
import '../widgets/garage_key_clipboard.dart';
import 'delete_garage_key_dialog.dart';
import 'garage_profile.dart';
import 'garage_reauthentication.dart';
import 'garage_welcome.dart';
import 'garage_wizard.dart';
import 'recovery_dialog.dart';

/// The Garage of the P2P tab, for the network of its [GarageCubit]: the welcome screen and the wizard when no Garage Key is stored, the profile when one is, and what to do when the vault cannot tell.
///
/// Every screen of the Garage shows a Garage Key, or a field where one is pasted, or leads to one: the whole Garage is protected from screenshots, screen recording and the preview of recent apps, as the wallet protects its seeds (`PrivacyScreen`), and nothing of it is drawn until the protection said it is on.
/// Where the platform refuses it, the Garage shows that the key stays hidden, with « Retry », and nothing else; the dialogs and the re-authentication opened from it stay under the same protection, which lasts until the Garage is left.
/// The user may turn the protection off in the settings of the wallet, which then applies here too.
class GarageView extends StatefulWidget {
  final GarageKeyClipboard clipboard;
  final P2pReauthentication? reauthenticate;

  /// Shows the offers of the tab: « Search for Orders » and « Search ».
  final VoidCallback onBrowseOffers;

  const GarageView({
    super.key,
    required this.clipboard,
    required this.reauthenticate,
    required this.onBrowseOffers,
  });

  @override
  State<GarageView> createState() => _GarageViewState();
}

class _GarageViewState extends State<GarageView> with PrivacyScreen {
  late Future<bool> _protection = enableScreenPrivacy();

  /// The step of the wizard shown, or `null` outside the wizard: local to this visit of the Garage.
  int? _step;

  /// The cubit of the Garage, once the gate has built the Garage: before that, nothing has read the vault, and nothing can be shown.
  GarageCubit? _cubit;

  /// Tells the cubit whenever the app is hidden or paused, for the whole visit, whatever the Garage shows, the wait of a draw included: a key drawn without the app staying in the foreground is shown only behind the PIN.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _conceal, onPause: _conceal);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(disableScreenPrivacy());
    super.dispose();
  }

  void _conceal() => _cubit?.conceal();

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
      builder: (context) {
        // Reading the cubit here creates it, so only once the protection is on.
        _cubit = context.read<GarageCubit>();
        return BlocBuilder<GarageCubit, GarageState>(
          builder: (context, state) => _content(context, state),
        );
      },
    );
  }

  Widget _content(BuildContext context, GarageState state) {
    final cubit = context.read<GarageCubit>();
    final step = _step;
    return switch (state) {
      GarageUnknown() => _GarageUnavailable(
        state: state,
        reauthenticate: widget.reauthenticate,
      ),
      // A key drawn and not acknowledged yet, in this visit or an earlier one: the wizard's backup step, the key behind the PIN unless it was just drawn.
      GarageWithKey(awaitsBackup: true) => _wizard(state, step ?? 1),
      // A key read from the vault rather than made in this visit goes to the profile, whatever the wizard showed.
      GarageWithKey(isNew: true) when step != null => _wizard(state, step),
      GarageWithKey() => GarageProfile(
        state: state,
        clipboard: widget.clipboard,
        reauthenticate: widget.reauthenticate,
      ),
      GarageWithoutKey() ||
      GarageWorking() when step != null => _wizard(state, step),
      GarageWithoutKey(:final failure) => GarageWelcome(
        onStart: () => setState(() => _step = 1),
        onRecovery: () => RecoveryDialog.show(context, cubit),
        onSearchOrders: widget.onBrowseOffers,
        failure: failure,
      ),
      GarageWorking() => Center(
        child: CircularProgressIndicator(color: context.bull.primary),
      ),
    };
  }

  Widget _wizard(GarageState state, int step) => GarageWizard(
    step: step,
    state: state,
    clipboard: widget.clipboard,
    reauthenticate: widget.reauthenticate,
    onStep: (step) => setState(() => _step = step),
    onSearch: widget.onBrowseOffers,
    onSeeProfile: () => setState(() => _step = null),
  );
}

/// The vault could not say whether a key is stored: why, then « Retry », and, unless the keystore is only locked, the way out of a key that cannot be read, with the warning of « Delete Garage Key? », then the PIN, which such a delete always asks.
///
/// Without [reauthenticate], that delete is disabled.
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
    final locked = state.failure is GarageKeyLockedFailure;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BullSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.actionFailure case final failure?) ...[
            Text(
              failure.toTranslated(context),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.error),
            ),
            const Gap(BullSpacing.sm),
          ],
          Text(
            state.failure.toTranslated(context),
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: colors.text),
          ),
          if (!locked) ...[
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
          if (!locked) ...[
            const Gap(BullSpacing.sm),
            BullButton.big(
              label: l10n.p2pDeleteKeyConfirm,
              iconData: Icons.delete_sweep,
              iconFirst: true,
              disabled: state.deletionNeedsPin && reauthenticate == null,
              onPressed: () async {
                if (!await DeleteGarageKeyDialog.show(context) ||
                    !context.mounted) {
                  return;
                }
                await cubit.delete(
                  reauthenticate: reauthenticationFrom(context, reauthenticate),
                );
              },
              outlined: true,
              bgColor: colors.transparent,
              textColor: colors.error,
              borderColor: colors.error,
            ),
          ],
        ],
      ),
    );
  }
}
