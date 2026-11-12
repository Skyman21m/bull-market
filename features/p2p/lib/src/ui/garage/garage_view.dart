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
      builder: (context) => BlocBuilder<GarageCubit, GarageState>(
        builder: (context, state) => _content(context, state),
      ),
    );
  }

  Widget _content(BuildContext context, GarageState state) {
    final cubit = context.read<GarageCubit>();
    final step = _step;
    return switch (state) {
      GarageUnknown() => _GarageUnavailable(state: state),
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

/// The vault could not say whether a key is stored: why, then « Retry », and, unless the keystore is only locked, the way out of a key that cannot be read, with the warning of « Delete Garage Key? ».
class _GarageUnavailable extends StatelessWidget {
  final GarageUnknown state;

  const _GarageUnavailable({required this.state});

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
              onPressed: () async {
                if (await DeleteGarageKeyDialog.show(context)) {
                  await cubit.delete();
                }
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
