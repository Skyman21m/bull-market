import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../presentation/garage_cubit.dart';
import '../../presentation/garage_state.dart';
import '../../presentation/p2p_failure_l10n.dart';
import '../widgets/garage_key_field.dart';

/// « Robot recovery » in Garage Key mode, opened by « Recovery » on the welcome screen (`components/Dialogs/Recovery.tsx` at commit ff1998c): the user pastes a Garage Key and « Recover » stores it, then the Garage shows its profile.
///
/// The official client then asks Nostr relays for the last robot used and the coordinators for the robot; Troc only stores the key, so its first robot is robot 0.
/// « Recover » is disabled until the field holds a Garage Key; a tap outside closes the dialog, except while the key is stored.
/// When the vault refuses the key, the dialog says why in the words of the app rather than the official client's single « Failed to recover robot », which would send the user to check a key that is fine when the keystore is locked.
class RecoveryDialog extends StatefulWidget {
  const RecoveryDialog({super.key});

  /// Opens the dialog over the Garage of [cubit].
  static Future<void> show(BuildContext context, GarageCubit cubit) =>
      BullDialog.show<void>(
        context: context,
        builder: (_) =>
            BlocProvider.value(value: cubit, child: const RecoveryDialog()),
      );

  @override
  State<RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<RecoveryDialog> {
  final _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _recover() async {
    final cubit = context.read<GarageCubit>();
    await cubit.import(_key.text);
    if (!mounted) return;
    // Stored, or the vault cannot tell any more: the Garage itself says what follows.
    if (cubit.state is GarageWithKey || cubit.state is GarageUnknown) {
      _key.clear();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final state = context.watch<GarageCubit>().state;
    final working = state is GarageWorking;
    final failure = switch (state) {
      GarageWithoutKey(:final failure?) => failure,
      _ => null,
    };
    return PopScope(
      canPop: !working,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: BullSpacing.sm,
              runSpacing: BullSpacing.xs,
              children: [
                Text(
                  l10n.p2pRecoveryTitle,
                  style: text.headlineLarge?.copyWith(color: colors.text),
                ),
                BullLabelChip(
                  label: l10n.p2pRecoveryModeGarageKey,
                  icon: Icons.key,
                ),
              ],
            ),
            const Gap(BullSpacing.md),
            Text(
              l10n.p2pRecoveryGarageKeyText,
              style: text.bodyMedium?.copyWith(color: colors.textMuted),
            ),
            if (failure != null) ...[
              const Gap(BullSpacing.md),
              Text(
                failure.toTranslated(context),
                style: text.bodyMedium?.copyWith(color: colors.error),
              ),
            ],
            const Gap(BullSpacing.md),
            GarageKeyField(
              controller: _key,
              label: l10n.p2pRecoveryPasteHere,
              enabled: !working,
            ),
            if (working) ...[
              const Gap(BullSpacing.md),
              Text(
                l10n.p2pRecoveryInProgress,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: colors.text),
              ),
              const Gap(BullSpacing.xs),
              LinearProgressIndicator(color: colors.primary),
            ],
            const Gap(BullSpacing.lg),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _key,
              builder: (context, value, _) => BullButton.big(
                label: l10n.p2pRecoveryRecover,
                iconData: Icons.key,
                iconFirst: true,
                disabled:
                    working ||
                    value.text.isEmpty ||
                    garageKeyTextError(value.text, l10n) != null,
                onPressed: _recover,
                bgColor: colors.primary,
                textColor: colors.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
