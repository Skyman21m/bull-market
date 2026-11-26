import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade_record.dart';
import '../widgets/trade_button.dart';
import '../widgets/word_fit_text.dart';

/// The body of the dialogs of the Garage Key card (#81, the mock-up decided on 2026-11-26): a title, a text, a line in the warning colour when there is one, then the button that goes on, filled, over « Cancel », outlined, when there is one.
///
/// The buttons are stacked, each the dialog's width, and their labels wrap, so that a long French label at three times the text size never overflows on a phone of 320 points; the whole body scrolls.
class GarageDialogBody extends StatelessWidget {
  final String title;
  final String text;

  /// A line in the warning colour under [text]; `null` for none.
  final String? warning;
  final String goLabel;
  final VoidCallback onGo;

  /// What closes the dialog without going on; `null` for a dialog with one button.
  final VoidCallback? onCancel;

  const GarageDialogBody({
    super.key,
    required this.title,
    required this.text,
    required this.goLabel,
    required this.onGo,
    this.warning,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final styles = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final onCancel = this.onCancel;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            header: true,
            child: WordFitText(
              title,
              textAlign: TextAlign.center,
              style: styles.headlineLarge?.copyWith(color: colors.text),
            ),
          ),
          const Gap(BullSpacing.md),
          WordFitText(
            text,
            style: styles.bodyMedium?.copyWith(color: colors.text),
          ),
          if (warning case final warning?) ...[
            const Gap(BullSpacing.sm),
            Container(
              padding: const EdgeInsets.only(left: BullSpacing.sm),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: colors.warning, width: 2),
                ),
              ),
              child: WordFitText(
                warning,
                style: styles.bodyMedium?.copyWith(color: colors.warning),
              ),
            ),
          ],
          const Gap(BullSpacing.lg),
          TradeButton(label: goLabel, onPressed: onGo),
          if (onCancel != null) ...[
            const Gap(BullSpacing.sm),
            TradeButton(
              label: l10n.p2pCommonCancel,
              onPressed: onCancel,
              outlined: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// The explanation the ⓘ of the Garage Key card opens (#81, plate 7 of the mock-up decided on 2026-11-26): one for the internal Garage Keys, one for the external Garage Key, then « Got it ».
class GarageKeyInfoDialog extends StatelessWidget {
  /// Whether it explains the external Garage Key, rather than the internal ones.
  final bool external;

  const GarageKeyInfoDialog({super.key, required this.external});

  /// Opens the explanation; a tap outside closes it as « Got it » does.
  static Future<void> show(BuildContext context, {required bool external}) =>
      BullDialog.show<void>(
        context: context,
        builder: (_) => GarageKeyInfoDialog(external: external),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return GarageDialogBody(
      title: external
          ? l10n.p2pGarageExternalKey
          : l10n.p2pGarageInternalKeysTitle,
      text: external
          ? l10n.p2pGarageExternalKeyInfo
          : l10n.p2pGarageInternalKeysInfo,
      goLabel: l10n.p2pCommonAcknowledged,
      onGo: () => Navigator.of(context).pop(),
    );
  }
}

/// « Your Garage Keys » (#81, plate 5 of the mock-up decided on 2026-11-26): shown once on this device, at the first opening of a Garage whose vault kept a key from before #81, now named the external Garage Key; the Garage stays on it.
class ExternalKeyNoticeDialog extends StatelessWidget {
  const ExternalKeyNoticeDialog({super.key});

  /// Opens the notice; a tap outside closes it as « Got it » does.
  static Future<void> show(BuildContext context) => BullDialog.show<void>(
    context: context,
    builder: (_) => const ExternalKeyNoticeDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return GarageDialogBody(
      title: l10n.p2pGarageNoticeTitle,
      text: l10n.p2pGarageNoticeText,
      goLabel: l10n.p2pCommonAcknowledged,
      onGo: () => Navigator.of(context).pop(),
    );
  }
}

/// « Delete the external Garage Key? » (#81, plate 4 of the mock-up decided on 2026-11-26): it is not backed up by the wallet, then « Delete » and « Cancel ».
///
/// Never refused: with a trade in progress of that key, a line in the warning colour names it and says it could not be continued, and « Delete » stays enabled. The PIN, when the delete asks it, comes after this confirmation, as before #81.
/// A tap outside closes it without deleting.
class DeleteGarageKeyDialog extends StatelessWidget {
  /// The trades in progress of the external Garage Key: each is named.
  final List<TradeRecord> inProgress;

  const DeleteGarageKeyDialog({super.key, this.inProgress = const []});

  /// Opens the dialog; completes with `true` only when the user confirmed.
  static Future<bool> show(
    BuildContext context, {
    List<TradeRecord> inProgress = const [],
  }) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => DeleteGarageKeyDialog(inProgress: inProgress),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return GarageDialogBody(
      title: l10n.p2pGarageDeleteExternalTitle,
      text: l10n.p2pGarageDeleteExternalText,
      warning: inProgress.isEmpty
          ? null
          : l10n.p2pGarageDeleteExternalTrades(
              inProgress.length,
              inProgress.map((record) => '#${record.orderId}').join(', '),
            ),
      goLabel: l10n.p2pGarageDeleteConfirm,
      onGo: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
    );
  }
}
