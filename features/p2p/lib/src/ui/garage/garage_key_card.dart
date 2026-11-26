import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../presentation/garage_cubit.dart';
import '../../presentation/garage_state.dart';
import '../widgets/garage_key_clipboard.dart';
import '../widgets/garage_key_view.dart';
import '../widgets/trade_button.dart';
import '../widgets/word_fit_text.dart';
import 'garage_key_dialogs.dart';
import 'garage_reauthentication.dart';
import 'new_garage_key_dialog.dart';
import 'recovery_dialog.dart';

/// Where the ⓘ of the card sits: `false` at the right of the line under the field (placement A of the mock-up of 2026-11-26, built until the owner chooses), `true` in the title, beside the key's name (placement B).
const bool _infoInTitle = false;

/// The least room of each icon button of the card, a target of 48 points whatever the theme's density: never under the 44 points a finger needs.
const BoxConstraints _target = BoxConstraints(minWidth: 48, minHeight: 48);

/// The card « Garage Key » of the Garage (#81, design note `docs/design/garage-key-from-the-words.md` § 2, § 6; the mock-up decided on 2026-11-26), under the robot's panel, where the official client puts its Garage Key and its copy: the one thing of the Garage that changes with the Garage Keys.
///
/// On an internal Garage Key (a key of the default wallet's words), its title carries the arrows, « ‹ Internal Garage Key #N › »: they select another internal Garage Key without the PIN, as the robot arrows move between robots, from key 0 up to the highest this device activated, and never create one nor reach the external Garage Key. Under the field, « Backed up by the 12 words of your Bull Wallet. » and its ⓘ; then « New internal Garage Key », which asks « New Garage Key » and activates the key after the highest; then « Switch to the external Garage Key » when the vault keeps one, otherwise the discreet link « Import an external Garage Key », which opens « Robot recovery ».
/// On the external Garage Key, its title, « External Garage Key », has no arrows; under the field, « Not backed up by your Bull Wallet: keep a copy of it. » in the warning colour, and its ⓘ; then « Back to internal Garage Keys », which returns to the last internal one shown, and « Delete the external Garage Key », which asks « Delete the external Garage Key? », naming its trades in progress without ever refusing, and, when a robot of it may live on a coordinator, the PIN, which the cubit decides.
/// The key shown is the key of new trades (decided on 2026-11-26, #81).
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

  Future<void> _delete(GarageCubit cubit, bool disabled) async {
    if (disabled ||
        !await DeleteGarageKeyDialog.show(
          context,
          inProgress: widget.state.inProgressOfKeyShown,
        ) ||
        !mounted) {
      return;
    }
    await cubit.delete(
      reauthenticate: reauthenticationFrom(context, widget.reauthenticate),
    );
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
    final external = state.isExternal;
    final reauthenticate = widget.reauthenticate;
    // Without the shell's re-authentication, a key whose delete asks the PIN cannot be deleted here, as it cannot be shown.
    final deleteDisabled = state.deletionNeedsPin && reauthenticate == null;
    final info = _InfoButton(external: external);
    final title = index == null
        ? l10n.p2pGarageExternalKey
        : l10n.p2pGarageKeyNumber(index);
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
          if (index == null)
            _ExternalTitle(title: title, info: _infoInTitle ? info : null)
          else
            _KeyNavigator(
              title: title,
              onPrevious: index > 0 ? cubit.previousKey : null,
              onNext: highest != null && index < highest ? cubit.nextKey : null,
              info: _infoInTitle ? info : null,
            ),
          const Gap(BullSpacing.xs),
          if (_revealed)
            GarageKeyView(garageKey: state.key.key, clipboard: widget.clipboard)
          else
            _MaskedKey(
              onReveal: reauthenticate == null
                  ? null
                  : () => _reveal(reauthenticate),
            ),
          const Gap(BullSpacing.xs),
          Row(
            children: [
              Expanded(
                child: WordFitText(
                  external
                      ? l10n.p2pGarageKeyNotBackedUp
                      : l10n.p2pGarageKeyBackedUp,
                  style: text.labelMedium?.copyWith(
                    color: external ? colors.warning : colors.textMuted,
                  ),
                ),
              ),
              if (!_infoInTitle) info,
            ],
          ),
          const Gap(BullSpacing.md),
          if (!external) ...[
            if (highest != null)
              TradeButton(
                label: l10n.p2pGarageNewKey,
                icon: Icons.add,
                onPressed: () => _newKey(highest + 1),
                outlined: true,
              ),
            if (state.hasExternal) ...[
              const Gap(BullSpacing.sm),
              TradeButton(
                label: l10n.p2pGarageSwitchToExternal,
                icon: Icons.swap_horiz,
                onPressed: cubit.switchToExternal,
                outlined: true,
              ),
            ] else ...[
              const Gap(BullSpacing.xs),
              _CardLink(
                label: l10n.p2pGarageImportExternal,
                icon: Icons.key,
                color: colors.primary,
                onPressed: () => RecoveryDialog.show(context, cubit),
              ),
            ],
          ] else ...[
            TradeButton(
              label: l10n.p2pGarageBackToInternal,
              icon: Icons.swap_horiz,
              onPressed: cubit.returnToInternal,
              outlined: true,
            ),
            const Gap(BullSpacing.xs),
            _CardLink(
              label: l10n.p2pGarageDeleteExternal,
              icon: Icons.delete_outline,
              color: colors.error,
              onPressed: deleteDisabled
                  ? null
                  : () => _delete(cubit, deleteDisabled),
            ),
          ],
        ],
      ),
    );
  }
}

/// « ‹ Internal Garage Key #N › », in the title of the card, drawn as the robot navigator: the previous internal Garage Key, disabled at key 0, and the next one, disabled on the highest, where it creates nothing.
class _KeyNavigator extends StatelessWidget {
  final String title;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// The ⓘ beside the title (placement B), `null` for none.
  final Widget? info;

  const _KeyNavigator({
    required this.title,
    required this.onPrevious,
    required this.onNext,
    required this.info,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final info = this.info;
    return Row(
      children: [
        IconButton(
          constraints: _target,
          tooltip: l10n.p2pGaragePreviousKey,
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
          color: colors.text,
          disabledColor: colors.textMuted,
        ),
        Expanded(child: _Title(title: title)),
        ?info,
        IconButton(
          constraints: _target,
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

/// « External Garage Key », the title of the card on the external Garage Key: no arrows (decided on 2026-11-26, #81).
class _ExternalTitle extends StatelessWidget {
  final String title;

  /// The ⓘ beside the title (placement B), `null` for none.
  final Widget? info;

  const _ExternalTitle({required this.title, required this.info});

  @override
  Widget build(BuildContext context) {
    final info = this.info;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Expanded(child: _Title(title: title)),
          ?info,
        ],
      ),
    );
  }
}

/// The name of the key shown, a header for a screen reader; within the room the arrows leave, on one line, scaled down just enough to fit when it is wider, never broken, as the robot navigator's label (#273).
class _Title extends StatelessWidget {
  final String title;

  const _Title({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: text.titleSmall?.copyWith(color: colors.text),
        ),
      ),
    );
  }
}

/// The ⓘ that opens the explanation of the key shown ([GarageKeyInfoDialog]).
class _InfoButton extends StatelessWidget {
  final bool external;

  const _InfoButton({required this.external});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    return IconButton(
      constraints: _target,
      tooltip: l10n.p2pGarageKeyExplain,
      onPressed: () => GarageKeyInfoDialog.show(context, external: external),
      icon: const Icon(Icons.info_outline),
      color: colors.text,
    );
  }
}

/// A discreet link of the card, its icon before its label, which wraps between words: « Import an external Garage Key », « Delete the external Garage Key ». At least 44 points high; `null` [onPressed] draws it disabled.
class _CardLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _CardLink({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final shown = onPressed == null ? colors.textMuted : color;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: shown),
          const Gap(BullSpacing.xs),
          Flexible(
            child: WordFitText(
              label,
              textAlign: TextAlign.center,
              style: text.labelLarge?.copyWith(color: shown),
            ),
          ),
        ],
      ),
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
            constraints: _target,
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
