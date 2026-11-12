import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';

/// « Delete Garage Key? », with the texts of the official client (`components/Dialogs/DeleteGarageKeyConfirmation.tsx` at commit ff1998c): the question, the warning that it cannot be undone, what to have done first, « Cancel » and a red « Delete Garage Key ».
///
/// Asked before every delete of a stored key: « Delete All », « Generate new » with a key stored, and the way out of a key that cannot be read.
/// A tap outside closes it without deleting, as in the official client.
class DeleteGarageKeyDialog extends StatelessWidget {
  const DeleteGarageKeyDialog({super.key});

  /// Opens the dialog; completes with `true` only when the user confirmed.
  static Future<bool> show(BuildContext context) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => const DeleteGarageKeyDialog(),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    Widget bullet(String line) => Padding(
      padding: const EdgeInsets.only(left: BullSpacing.sm, top: BullSpacing.xs),
      child: Text(
        '•  $line',
        style: text.bodyMedium?.copyWith(color: colors.text),
      ),
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: colors.warning),
              const Gap(BullSpacing.xs),
              Expanded(
                child: Text(
                  l10n.p2pDeleteKeyTitle,
                  style: text.headlineLarge?.copyWith(color: colors.text),
                ),
              ),
            ],
          ),
          const Gap(BullSpacing.md),
          Text(
            l10n.p2pDeleteKeyQuestion,
            style: text.bodyLarge?.copyWith(color: colors.text),
          ),
          const Gap(BullSpacing.md),
          Text(
            l10n.p2pDeleteCannotBeUndone,
            style: text.bodyMedium?.copyWith(
              color: colors.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Gap(BullSpacing.md),
          Text(
            l10n.p2pDeleteBeforeDeleting,
            style: text.bodyMedium?.copyWith(color: colors.text),
          ),
          bullet(l10n.p2pDeleteKeyStoredKey),
          bullet(l10n.p2pDeleteKeyNoActiveOrders),
          bullet(l10n.p2pDeleteExportedData),
          const Gap(BullSpacing.lg),
          BullButton.big(
            label: l10n.p2pDeleteKeyConfirm,
            iconData: Icons.delete_sweep,
            iconFirst: true,
            onPressed: () => Navigator.of(context).pop(true),
            bgColor: colors.error,
            textColor: colors.onError,
          ),
          const Gap(BullSpacing.sm),
          BullButton.big(
            label: l10n.p2pCommonCancel,
            onPressed: () => Navigator.of(context).pop(false),
            outlined: true,
            bgColor: colors.transparent,
            textColor: colors.primary,
            borderColor: colors.primary,
          ),
        ],
      ),
    );
  }
}
