import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../presentation/garage_cubit.dart';
import '../../presentation/garage_state.dart';
import '../widgets/garage_key_clipboard.dart';
import '../widgets/garage_key_view.dart';
import 'delete_garage_key_dialog.dart';
import 'garage_reauthentication.dart';
import 'new_garage_key_dialog.dart';
import 'recovery_dialog.dart';

/// Whether the text of the key is asked for with an eye in a masked field, as the official client's field looks (the mock-up of 2026-11-26, question 3, answer A by default); `false` for today's button « Show Garage Key ».
const bool _revealWithEye = true;

/// The card « Garage Key » of the Garage (#81, design note `docs/design/garage-key-from-the-words.md` § 2, § 6), under the robot's panel, where the official client puts its Garage Key and its copy: the one thing of the Garage that changes with the keys of the words.
///
/// Its title carries the arrows of the keys, « ‹ Garage Key n° N › », « ‹ External Key › »: they select another key without the PIN, as the robot arrows move between robots, from key 0 up to the highest key of the words this device activated, then the external key when the vault keeps one, one position further (the defaults of the owner's decision of 2026-11-26, until the mock-up of the external key); « › » creates nothing. The key shown is the key of new trades (the owner's decisions of 2026-11-26).
/// « New key », in place of the official client's « Delete All », on every key, asks « New Garage Key » and activates the key of the words after the highest, which it selects.
/// The external key has today's helper text and, besides « New key », « Delete Garage Key », which asks today's « Delete Garage Key? » and, when a robot of it may live on a coordinator, the PIN, which the cubit decides. Without an external key, a link opens « Robot recovery », where one is pasted.
/// The text of every key is shown only after the wallet's re-authentication, which [reauthenticate] brings from the shell; without it the text cannot be shown. It is hidden again when the app goes to the background, and the card is built anew for each key, so that moving to another key hides the text. It is copied only through [clipboard], which empties the clipboard after 30 seconds.
class GarageKeyCard extends StatefulWidget {
  final GarageWithKey state;
  final GarageKeyClipboard clipboard;
  final P2pReauthentication? reauthenticate;

  const GarageKeyCard({
    super.key,
    required this.state,
    required this.clipboard,
    required this.reauthenticate,
  });

  @override
  State<GarageKeyCard> createState() => _GarageKeyCardState();
}

class _GarageKeyCardState extends State<GarageKeyCard> {
  /// Whether the text of the key is shown: only once the re-authentication said so, and until the card is left, another key shown or the app goes to the background.
  bool _revealed = false;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _hide, onPause: _hide);
  }

  @override
  void didUpdateWidget(GarageKeyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Another key under the same card: its text is asked for again.
    if (oldWidget.state.key != widget.state.key) _revealed = false;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _hide() {
    if (_revealed && mounted) setState(() => _revealed = false);
  }

  Future<void> _reveal(P2pReauthentication reauthenticate) async {
    final shown = widget.state.key;
    if (await askReauthentication(context, reauthenticate) &&
        mounted &&
        widget.state.key == shown) {
      setState(() => _revealed = true);
    }
  }

  Future<void> _newKey(int next) async {
    final cubit = context.read<GarageCubit>();
    if (!await NewGarageKeyDialog.show(context, index: next) || !mounted) {
      return;
    }
    await cubit.newKey();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final cubit = context.read<GarageCubit>();
    final state = widget.state;
    final index = state.key.index;
    final highest = state.highest;
    final reauthenticate = widget.reauthenticate;
    final deleteDisabled = state.deletionNeedsPin && reauthenticate == null;
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
          _KeyNavigator(
            title: index == null
                ? l10n.p2pGarageExternalKey
                : l10n.p2pGarageKeyNumber(index),
            onPrevious: index == 0 ? null : cubit.previousKey,
            onNext: index != null && (index < highest || state.hasExternal)
                ? cubit.nextKey
                : null,
          ),
          const Gap(BullSpacing.xs),
          if (_revealed)
            GarageKeyView(garageKey: state.key.key, clipboard: widget.clipboard)
          else if (_revealWithEye)
            _MaskedKey(
              onReveal: reauthenticate == null
                  ? null
                  : () => _reveal(reauthenticate),
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
            state.isExternal
                ? l10n.p2pGarageKeyHelper
                : l10n.p2pGarageKeyHelperWords,
            style: text.labelMedium?.copyWith(
              color: _revealed ? colors.text : colors.textMuted,
            ),
          ),
          const Gap(BullSpacing.md),
          BullButton.big(
            label: l10n.p2pGarageNewKey,
            iconData: Icons.add,
            iconFirst: true,
            onPressed: () => _newKey(highest + 1),
            outlined: true,
            bgColor: colors.transparent,
            textColor: colors.primary,
            borderColor: colors.primary,
          ),
          if (state.isExternal) ...[
            const Gap(BullSpacing.sm),
            // Without the shell's re-authentication, a key whose delete asks the PIN cannot be deleted here, as it cannot be shown.
            BullButton.big(
              label: l10n.p2pDeleteKeyConfirm,
              iconData: Icons.delete_sweep,
              iconFirst: true,
              disabled: deleteDisabled,
              onPressed: () async {
                if (deleteDisabled ||
                    !await DeleteGarageKeyDialog.show(context) ||
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
          ] else if (!state.hasExternal) ...[
            const Gap(BullSpacing.xs),
            Center(
              child: TextButton(
                onPressed: () => RecoveryDialog.show(context, cubit),
                child: Text(
                  l10n.p2pGarageWelcomeRecoverHint,
                  textAlign: TextAlign.center,
                  style: text.labelLarge?.copyWith(color: colors.primary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// « ‹ Garage Key n° N › » or « ‹ External Key › », in the title of the card, drawn as the robot navigator: the previous key, disabled at key 0, and the next one, disabled on the last position, where it creates nothing.
class _KeyNavigator extends StatelessWidget {
  final String title;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _KeyNavigator({
    required this.title,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: l10n.p2pGaragePreviousKey,
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
          color: colors.text,
          disabledColor: colors.textMuted,
        ),
        // Within the room the two arrows leave, so that a large text never overflows: the title, on one line, is scaled down just enough to fit when it is wider, never broken, as the robot navigator's label (#273).
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(color: colors.text),
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.p2pGarageNextKey,
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          color: colors.text,
          disabledColor: colors.textMuted,
        ),
      ],
    );
  }
}

/// The field of the key with its text masked, `robo1••••`, and an eye that asks the re-authentication before the text is shown; without [onReveal] the eye is disabled.
class _MaskedKey extends StatelessWidget {
  final VoidCallback? onReveal;

  const _MaskedKey({required this.onReveal});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        BullSpacing.sm,
        BullSpacing.xs,
        0,
        BullSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(BullRadius.xxs),
        border: Border.all(color: colors.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: ExcludeSemantics(
              child: Text(
                l10n.p2pGarageKeyMasked,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: text.bodyMedium?.copyWith(
                  color: colors.textMuted,
                  // No monospace token in the theme yet: the family is the platform's own, as on the Silent Payments settings.
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.p2pGarageKeyReveal,
            onPressed: onReveal,
            icon: const Icon(Icons.visibility),
            color: colors.primary,
            disabledColor: colors.textMuted,
          ),
        ],
      ),
    );
  }
}
