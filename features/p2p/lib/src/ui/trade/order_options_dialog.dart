import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../presentation/trade_l10n.dart';
import '../widgets/trade_button.dart';

/// What the user chose in « Order options ».
enum OrderOption { openDispute, collaborativeCancel }

/// « Order options », the dialog behind « … » of the chat step (`TradeBox/Prompts/Chat.tsx:254-353`, commit ff1998c), with its buttons in the reference's order: « Audit Chat », « Export », « Open Dispute », « Collaborative Cancel ».
///
/// « Audit Chat » and « Export » belong to the chat (#93): their places are kept, `null` until then, and nothing is drawn for them.
/// « Open Dispute » is off until 18 hours before the chat's end ([disputeOpensAt]), with the reference's « To open a dispute you need to wait {{hours}}h {{minutes}}m » counting down under it, so that it is never offered when the coordinator would refuse it (1054); it is not drawn when the status shown does not offer it.
/// « Collaborative Cancel » is off once the fiat is sent, with the reference's « Orders can't be cancelled if fiat has been sent. ».
class OrderOptionsDialog extends StatefulWidget {
  /// The places of « Audit Chat » and « Export » (#93), `null` for now.
  final Widget? auditChat;
  final Widget? export;

  /// When « Open Dispute » becomes possible, or `null` when the status shown does not offer it.
  final DateTime? disputeOpensAt;

  /// The screen's clock, for the countdown.
  final DateTime Function() now;

  /// Whether « Collaborative Cancel » may be pressed: at 9, before « fiat sent ».
  final bool collaborativeCancel;

  const OrderOptionsDialog({
    super.key,
    required this.collaborativeCancel,
    required this.disputeOpensAt,
    required this.now,
    this.auditChat,
    this.export,
  });

  /// What the user chose, or `null` when the dialog was closed.
  static Future<OrderOption?> show(
    BuildContext context, {
    required bool collaborativeCancel,
    required DateTime? disputeOpensAt,
    required DateTime Function() now,
  }) => BullDialog.show<OrderOption>(
    context: context,
    builder: (_) => OrderOptionsDialog(
      collaborativeCancel: collaborativeCancel,
      disputeOpensAt: disputeOpensAt,
      now: now,
    ),
  );

  @override
  State<OrderOptionsDialog> createState() => _OrderOptionsDialogState();
}

class _OrderOptionsDialogState extends State<OrderOptionsDialog> {
  late DateTime _now = widget.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The countdown moves every second, as the screen's clock does.
    if (widget.disputeOpensAt != null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = widget.now());
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final styles = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final opensAt = widget.disputeOpensAt;
    final disputeOpen = opensAt != null && !_now.isBefore(opensAt);
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
          for (final place in [widget.auditChat, widget.export])
            if (place != null) ...[const Gap(BullSpacing.md), place],
          if (opensAt != null) ...[
            const Gap(BullSpacing.md),
            TradeButton(
              label: l10n.p2pEndOpenDispute,
              icon: Icons.balance,
              outlined: true,
              color: colors.warning,
              onPressed: disputeOpen
                  ? () => Navigator.of(context).pop(OrderOption.openDispute)
                  : null,
            ),
            if (!disputeOpen) ...[
              const Gap(BullSpacing.xs),
              Text(
                disputeWait(l10n, opensAt.difference(_now)),
                textAlign: TextAlign.center,
                style: styles.bodySmall?.copyWith(color: colors.textMuted),
              ),
            ],
          ],
          const Gap(BullSpacing.md),
          TradeButton(
            label: l10n.p2pEndCollabCancel,
            icon: Icons.handshake_outlined,
            // Outlined in the colour of « Cancel »: a filled button in that colour would hide its own label.
            outlined: true,
            color: colors.secondary,
            onPressed: widget.collaborativeCancel
                ? () =>
                      Navigator.of(context).pop(OrderOption.collaborativeCancel)
                : null,
          ),
          if (!widget.collaborativeCancel) ...[
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
