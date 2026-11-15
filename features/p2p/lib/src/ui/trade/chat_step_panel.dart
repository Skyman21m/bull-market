import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/trade_chat_step.dart';
import '../../domain/trade/trade_status.dart';
import '../../domain/trade/trade_watch.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/trade_cubit.dart';
import '../../presentation/trade_l10n.dart';
import '../widgets/trade_button.dart';
import 'confirm_fiat_sent_dialog.dart';

/// The buyer's chat step, 9 and 10 (`TradeBox/Prompts/Chat.tsx`, commit ff1998c; #95): the reference's prompt and « ⚠️ Beware scams », the place of the chat, then the action buttons under it, as the reference lays them out.
///
/// At 9, « Confirm {{amount}} {{currencyCode}} sent » opens the reference's dialog ([ConfirmFiatSentDialog]), whose « Confirm » sends « fiat sent » once through the trade's cubit, for the status shown when the button was pressed; at 10, « Wait for the seller to confirm they have received the payment. ».
/// While an action of the trade runs (this one, a cancel, a payout), the button is off and a line says what it waits for, step by step; what the action gave is said under it ([ChatStepNotice]).
/// The status shown is the status stored: nothing here changes it before a read does.
class ChatStepPanel extends StatefulWidget {
  final TradeSeen seen;

  /// The order the status comes from, for the trade's amount and currency.
  final CoordinatorOrder? order;

  /// The long alias of the trade's coordinator, which the waits name.
  final String coordinator;

  /// Where an action of the chat step stands.
  final ChatStepState chatStep;

  /// Whether another action of the trade runs (a cancel, a payout): the buttons are off meanwhile.
  final bool otherActionRunning;

  /// Whether « fiat sent » may be offered: the screen's cubit sends it.
  final bool offersFiatSent;

  /// The chat of the trade (#93), where the reference puts it: between the prompt's text and the action buttons; `null` until the chat panel is wired, and the step is shown without it.
  final Widget? chat;

  const ChatStepPanel({
    super.key,
    required this.seen,
    required this.order,
    required this.coordinator,
    required this.chatStep,
    required this.otherActionRunning,
    required this.offersFiatSent,
    this.chat,
  });

  @override
  State<ChatStepPanel> createState() => _ChatStepPanelState();
}

class _ChatStepPanelState extends State<ChatStepPanel> {
  /// Whether the dialog is open: a second press meanwhile opens nothing more.
  bool _asking = false;

  /// The trade's amount and currency as the reference writes them on the button and in the dialog: an amount in bitcoin in sats, as the payout's prompt.
  (String, String)? _amount(BuildContext context) {
    final order = widget.order;
    if (order == null) return null;
    final l10n = P2pLocalizations.of(context);
    final bitcoin = order.currency.isBitcoin;
    return (
      P2pFormats.of(context).payoutAmount(
        (order.takenAmount ?? order.amount.max).value,
        inBitcoin: bitcoin,
      ),
      bitcoin ? l10n.p2pSatsUnit : order.currency.code,
    );
  }

  /// Opens the reference's dialog, then sends « fiat sent » for the status seen when the button was pressed, never the one shown when the dialog closes: the cubit and the use case refuse it if the order moved meanwhile.
  Future<void> _press(String amount, String currencyCode) async {
    if (_asking) return;
    _asking = true;
    final cubit = context.read<TradeCubit>();
    final seen = widget.seen;
    try {
      if (await ConfirmFiatSentDialog.show(
        context,
        amount: amount,
        currencyCode: currencyCode,
      )) {
        await cubit.confirmFiatSent(seen);
      }
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final status = widget.seen.status;
    final fiatSent = status is Chatting && status.fiatSent;
    final chatStep = widget.chatStep;
    final running = chatStep is ChatStepRunning;
    final notice = switch (chatStep) {
      ChatStepIdle(:final notice?) => notice,
      _ => null,
    };
    final amount = _amount(context);
    final offered =
        widget.offersFiatSent &&
        amount != null &&
        ChatStepAction.confirmFiatSent.offeredAt(widget.seen);
    final body = text.bodyMedium?.copyWith(color: colors.text);
    // What the button waits for: its own action step by step, or another action of the order.
    final waiting = switch (chatStep) {
      ChatStepRunning(:final progress) => progress.toText(
        context,
        coordinator: widget.coordinator,
      ),
      _ when offered && widget.otherActionRunning =>
        l10n.p2pEndStepWaitingForOrder,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          fiatSent ? l10n.p2pEndWaitSeller : l10n.p2pEndChatBuyerHi,
          textAlign: TextAlign.center,
          style: body,
        ),
        const Gap(BullSpacing.xs),
        Text(
          l10n.p2pEndBewareScams,
          textAlign: TextAlign.center,
          style: body?.copyWith(color: colors.warning),
        ),
        if (widget.chat case final chat?) ...[const Gap(BullSpacing.md), chat],
        if (amount != null && (offered || running)) ...[
          const Gap(BullSpacing.md),
          TradeButton(
            label: l10n.p2pEndConfirmSent(amount.$1, amount.$2),
            busy: running,
            onPressed: !offered || running || widget.otherActionRunning
                ? null
                : () => unawaited(_press(amount.$1, amount.$2)),
          ),
        ],
        if (waiting != null) ...[const Gap(BullSpacing.sm), _Wait(waiting)],
        if (notice != null) ...[
          const Gap(BullSpacing.sm),
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              notice.toText(context, coordinator: widget.coordinator),
              textAlign: TextAlign.center,
              style: body?.copyWith(color: colors.error),
            ),
          ),
        ],
      ],
    );
  }
}

/// What an action waits for, read out as it changes.
class _Wait extends StatelessWidget {
  final String text;

  const _Wait(this.text);

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.bull.textMuted),
    ),
  );
}
