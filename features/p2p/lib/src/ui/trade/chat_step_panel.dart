import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/trade_chat_step.dart';
import '../../domain/trade/trade_status.dart';
import '../../domain/trade/trade_watch.dart';
import '../../domain/trade_record.dart';
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

  /// The order the status comes from, whose amount and currency are compared with the trade's terms (the button is worded from the terms, `Chatting.amount`).
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

  /// The trade's amount and currency as the button and the dialog write them, from the trade's terms (`Chatting.amount`, `Chatting.currency`), never from a read: an amount in bitcoin in sats, as the payout's prompt.
  (String, String)? _amount(BuildContext context) =>
      switch (widget.seen.status) {
        Chatting(:final amount, :final currency) => _worded(
          context,
          amount,
          currency,
        ),
        _ => null,
      };

  /// [amount] in [currency] as the button writes it.
  static (String, String) _worded(
    BuildContext context,
    FiatAmount amount,
    RobosatsCurrency currency,
  ) {
    final bitcoin = currency.isBitcoin;
    return (
      P2pFormats.of(context).payoutAmount(amount.value, inBitcoin: bitcoin),
      bitcoin ? P2pLocalizations.of(context).p2pSatsUnit : currency.code,
    );
  }

  /// When the order read gives another amount or currency than the trade's terms, which the button keeps (a warning informs, it does not block): the coordinator's figure and the terms', in few words; `null` when they agree, or with no order read.
  String? _amountDiffers(BuildContext context, (String, String) stored) {
    final order = widget.order;
    final status = widget.seen.status;
    if (order == null || status is! Chatting) return null;
    final read =
        order.takenAmount ??
        switch (order.amount) {
          FixedOrderAmount(:final amount) => amount,
          RangeOrderAmount() => null,
        };
    final l10n = P2pLocalizations.of(context);
    if (read == null) {
      return l10n.p2pEndAmountMissing(widget.coordinator, stored.$1, stored.$2);
    }
    if (read == status.amount && order.currency == status.currency) return null;
    final shown = _worded(context, read, order.currency);
    return l10n.p2pEndAmountDiffers(
      widget.coordinator,
      shown.$1,
      shown.$2,
      stored.$1,
      stored.$2,
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
    // The buyer at 9, where the prompt says to press the button: shown off with why when the status shown does not offer it (not marked stored, or from no order read).
    final atNine =
        widget.offersFiatSent &&
        status is Chatting &&
        status.role == TradeRole.buyer &&
        !status.fiatSent;
    final body = text.bodyMedium?.copyWith(color: colors.text);
    // What the button waits for: its own action step by step, or another action of the order.
    final waiting = switch (chatStep) {
      ChatStepRunning(:final progress) => progress.toText(
        context,
        coordinator: widget.coordinator,
      ),
      _ when offered && widget.otherActionRunning =>
        l10n.p2pPayoutStepWaitingForOrder,
      _ => null,
    };
    final waitedLong = chatStep is ChatStepRunning && chatStep.waitedLong;
    final differs = amount == null || !atNine
        ? null
        : _amountDiffers(context, amount);
    final needsRead = atNine && !offered && !running && notice == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          fiatSent ? l10n.p2pEndWaitSeller : l10n.p2pEndChatBuyerHi,
          textAlign: TextAlign.center,
          style: body,
        ),
        const Gap(BullSpacing.xs),
        // Read out without the emoji's name.
        Semantics(
          container: true,
          label: withoutLeadingEmoji(l10n.p2pEndBewareScams),
          excludeSemantics: true,
          child: Text(
            l10n.p2pEndBewareScams,
            textAlign: TextAlign.center,
            style: body?.copyWith(color: colors.warning),
          ),
        ),
        if (widget.chat case final chat?) ...[const Gap(BullSpacing.md), chat],
        if (amount != null && (atNine || running)) ...[
          const Gap(BullSpacing.md),
          TradeButton(
            label: l10n.p2pEndConfirmSent(amount.$1, amount.$2),
            busy: running,
            onPressed: !offered || running || widget.otherActionRunning
                ? null
                : () => unawaited(_press(amount.$1, amount.$2)),
          ),
        ],
        if (differs != null) ...[
          const Gap(BullSpacing.sm),
          Text(
            differs,
            textAlign: TextAlign.center,
            style: body?.copyWith(color: colors.warning),
          ),
        ],
        if (waiting != null) ...[
          const Gap(BullSpacing.sm),
          _Wait(waiting),
          // The bar named by the step, and the long wait's line, as the payout and the take show them.
          if (running) ...[
            const Gap(BullSpacing.xs),
            LinearProgressIndicator(
              color: colors.primary,
              semanticsLabel: waiting,
            ),
          ],
          if (waitedLong) ...[
            const Gap(BullSpacing.xs),
            _Wait(l10n.p2pRobotStillWaiting(widget.coordinator)),
          ],
        ],
        if (needsRead) ...[
          const Gap(BullSpacing.sm),
          _Wait(l10n.p2pEndNeedsRead),
        ],
        if (notice != null) ...[
          const Gap(BullSpacing.sm),
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              notice.toText(context, coordinator: widget.coordinator),
              textAlign: TextAlign.center,
              // An outcome unknown is no failure: the confirmation may well have gone through (the payout's notice of the same kind is in the warning colour too); red only where it was not sent.
              style: body?.copyWith(
                color: notice is ChatStepWasUnknown
                    ? colors.warning
                    : colors.error,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// [text] without the emoji and the space it starts with (« ⚠️ Beware scams », « ✅ Confirm you sent … »), for a screen reader, which would read the emoji's name first.
String withoutLeadingEmoji(String text) =>
    text.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '');

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
