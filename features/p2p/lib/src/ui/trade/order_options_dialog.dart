import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../widgets/trade_button.dart';

/// What the user chose in « Order options ».
enum OrderOption { collaborativeCancel }

/// « Order options », the dialog behind « … » of the chat step (`TradeBox/Prompts/Chat.tsx:254-353`, commit ff1998c), with its buttons in the reference's order: « Audit Chat », « Export », « Open Dispute », « Collaborative Cancel ».
///
/// « Audit Chat » and « Export » belong to the chat (#93) and « Open Dispute » to a later pull request of #95: their places are kept, `null` until then, and nothing is drawn for them. « Collaborative Cancel » is off once the fiat is sent, with the reference's « Orders can't be cancelled if fiat has been sent. ».
class OrderOptionsDialog extends StatelessWidget {
  /// The places of « Audit Chat » and « Export » (#93) and of « Open Dispute » (#95), `null` for now.
  final Widget? auditChat;
  final Widget? export;
  final Widget? openDispute;

  /// Whether « Collaborative Cancel » may be pressed: at 9, before « fiat sent ».
  final bool collaborativeCancel;

  const OrderOptionsDialog({
    super.key,
    required this.collaborativeCancel,
    this.auditChat,
    this.export,
    this.openDispute,
  });

  /// What the user chose, or `null` when the dialog was closed.
  static Future<OrderOption?> show(
    BuildContext context, {
    required bool collaborativeCancel,
  }) => BullDialog.show<OrderOption>(
    context: context,
    builder: (_) =>
        OrderOptionsDialog(collaborativeCancel: collaborativeCancel),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final styles = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            header: true,
            child: Text(
              l10n.p2pEndOrderOptions,
              style: styles.headlineLarge?.copyWith(color: colors.text),
            ),
          ),
          for (final place in [auditChat, export, openDispute])
            if (place != null) ...[const Gap(BullSpacing.md), place],
          const Gap(BullSpacing.md),
          TradeButton(
            label: l10n.p2pEndCollabCancel,
            icon: Icons.handshake_outlined,
            // Outlined in the colour of « Cancel »: a filled button in that colour would hide its own label.
            outlined: true,
            color: colors.secondary,
            onPressed: collaborativeCancel
                ? () =>
                      Navigator.of(context).pop(OrderOption.collaborativeCancel)
                : null,
          ),
          if (!collaborativeCancel) ...[
            const Gap(BullSpacing.xs),
            Text(
              l10n.p2pEndCollabAfterFiat,
              textAlign: TextAlign.center,
              style: styles.bodySmall?.copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
