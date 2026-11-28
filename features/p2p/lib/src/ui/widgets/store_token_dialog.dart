import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../garage/garage_reauthentication.dart';
import 'garage_key_backup.dart';
import 'garage_key_view.dart';
import 'trade_dialog_body.dart';

/// « Store your garage key », the official client's reminder before a take (`components/Dialogs/StoreToken.tsx`, opened by `Dialogs/Confirmation.tsx` from `OrderDetails/TakeButton.tsx:378-390`, at commit ff1998c), and here before a make too: « Done » goes on, « Go back » or a tap outside sends nothing.
///
/// Since #318 (decided on 2026-11-28) it is shown only when the trade uses the external Garage Key, the key the vault keeps (drawn at random before #81, or imported), which nothing else backs up; a key of the wallet's words comes back with the words, and the trade goes on without it.
/// The reference shows the key itself in its field « Back it up! », with a copy button; here the field is masked, a fixed row of dots that does not tell the key's length, and its copy button asks first the wallet's re-authentication the Garage asks before it shows a key, then reads the key and hands it to the Garage's clipboard helper, which empties the clipboard 30 seconds later; leaving the re-authentication copies nothing. The key is shown in clear only in the Garage, behind that re-authentication (`AGENTS.md`, « The Garage »), a deviation for security.
class StoreTokenDialog extends StatefulWidget {
  /// The copy of « Back it up! », `null` where the shell lends no re-authentication or the feature has no Garage: the button is then disabled.
  final GarageKeyCopy? copy;

  const StoreTokenDialog({super.key, required this.copy});

  /// Whether the user pressed « Done ».
  static Future<bool> show(
    BuildContext context, {
    required GarageKeyCopy? copy,
  }) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => StoreTokenDialog(copy: copy),
      ) ??
      false;

  @override
  State<StoreTokenDialog> createState() => _StoreTokenDialogState();
}

class _StoreTokenDialogState extends State<StoreTokenDialog> {
  /// Whether the key is on the clipboard since a copy made here: « Copied! » shows.
  bool _copied = false;

  /// Whether a copy runs: another tap meanwhile does nothing.
  bool _copying = false;

  /// The re-authentication, then the key read and handed to the clipboard helper at once: it is kept in no field, and goes nowhere else.
  Future<void> _copy(GarageKeyCopy copy) async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      if (!await askReauthentication(context, copy.reauthenticate) ||
          !mounted) {
        return;
      }
      final key = await copy.read();
      if (key == null || !mounted) return;
      if (await GarageKeyView.copy(copy.clipboard, key.key) && mounted) {
        setState(() => _copied = true);
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final copy = widget.copy;
    return TradeDialogBody(
      title: l10n.p2pStoreKeyTitle,
      text: l10n.p2pStoreKeyText,
      field: _BackItUp(
        copied: _copied,
        onCopy: copy == null || _copying ? null : () => _copy(copy),
      ),
      backLabel: l10n.p2pCommonGoBack,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: l10n.p2pCommonDone,
      onGo: () => Navigator.of(context).pop(true),
    );
  }
}

/// The reference's field « Back it up! » (`TextField` `disabled`, `variant='filled'`, its copy button at its end, « Copied! » once copied), masked: it holds no key.
class _BackItUp extends StatelessWidget {
  /// The mask: always this many dots, whatever the key, so that its length is not told.
  static const String mask = '••••••••••••••••';

  final bool copied;
  final VoidCallback? onCopy;

  const _BackItUp({required this.copied, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: l10n.p2pStoreKeyBackItUp,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              BullSpacing.sm,
              BullSpacing.xs,
              BullSpacing.xs,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.p2pStoreKeyBackItUp,
                          style: text.labelMedium?.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                        Text(
                          mask,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: text.bodyMedium?.copyWith(color: colors.text),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton.filled(
                  tooltip: copied ? l10n.p2pCommonCopied : l10n.p2pCommonCopy,
                  onPressed: onCopy,
                  style: IconButton.styleFrom(
                    backgroundColor: copied ? colors.success : colors.primary,
                    foregroundColor: colors.onPrimary,
                  ),
                  icon: Icon(copied ? Icons.check : Icons.copy),
                ),
              ],
            ),
          ),
        ),
        if (copied) ...[
          const Gap(BullSpacing.xs),
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              l10n.p2pCommonCopied,
              style: text.bodyMedium?.copyWith(color: colors.success),
            ),
          ),
        ],
      ],
    );
  }
}
