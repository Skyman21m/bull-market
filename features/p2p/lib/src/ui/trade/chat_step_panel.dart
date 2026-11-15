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
import 'confirm_collab_cancel_dialog.dart';
import 'confirm_fiat_sent_dialog.dart';
import 'confirm_undo_fiat_sent_dialog.dart';
import 'order_options_dialog.dart';

/// The buyer's chat step, 9 and 10 (`TradeBox/Prompts/Chat.tsx`, commit ff1998c; #95): the reference's prompt and « ⚠️ Beware scams », the place of the chat, then the action buttons under it, as the reference lays them out: « … » (« Order options ») and, at 9, « Confirm {{amount}} {{currencyCode}} sent », at 10, « Payment failed? ».
///
/// « Confirm … sent » opens the reference's dialog ([ConfirmFiatSentDialog]), « Payment failed? » its own ([ConfirmUndoFiatSentDialog]), « Collaborative Cancel » in « Order options » its own ([ConfirmCollabCancelDialog]); each sends once through the trade's cubit, for the status shown when the button was pressed.
/// While an action of the trade runs (one of these, a cancel, a payout), the buttons are off and a line says what it waits for, step by step; what an action gave is said under them.
/// The status shown is the status stored: nothing here changes it before a read does.
class ChatStepPanel extends StatefulWidget {
  final TradeSeen seen;

  /// The order the status comes from, for the trade's amount and currency.
  final CoordinatorOrder? order;

  /// The long alias of the trade's coordinator, which the waits name.
  final String coordinator;

  /// Where an action of the chat step stands.
  final ChatStepState chatStep;

  /// Where a cancel stands: the collaborative cancel of this step.
  final TradeCancelState cancel;

  /// Whether another action of the trade runs that this panel does not follow (a payout): the buttons are off meanwhile.
  final bool otherActionRunning;

  /// Whether « fiat sent », « Payment failed? » and the collaborative cancel may be offered: the screen's cubit sends them.
  final bool offersFiatSent;
  final bool offersUndoFiatSent;
  final bool offersCollaborativeCancel;

  /// The chat of the trade (#93), where the reference puts it: between the prompt's text and the action buttons; `null` until the chat panel is wired, and the step is shown without it.
  final Widget? chat;

  const ChatStepPanel({
    super.key,
    required this.seen,
    required this.order,
    required this.coordinator,
    required this.chatStep,
    required this.cancel,
    required this.otherActionRunning,
    required this.offersFiatSent,
    required this.offersUndoFiatSent,
    required this.offersCollaborativeCancel,
    this.chat,
  });

  @override
  State<ChatStepPanel> createState() => _ChatStepPanelState();
}

class _ChatStepPanelState extends State<ChatStepPanel> {
  /// Whether a dialog is open: a second press meanwhile opens nothing more.
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

  /// Runs [ask] once at a time, for the status seen when the button was pressed, never the one shown when its dialog closes: the cubit and the use cases refuse an action if the order moved meanwhile.
  Future<void> _once(
    Future<void> Function(TradeCubit cubit, TradeSeen seen) ask,
  ) async {
    if (_asking) return;
    _asking = true;
    try {
      await ask(context.read<TradeCubit>(), widget.seen);
    } finally {
      _asking = false;
    }
  }

  Future<void> _confirmFiatSent(String amount, String currencyCode) =>
      _once((cubit, seen) async {
        if (await ConfirmFiatSentDialog.show(
          context,
          amount: amount,
          currencyCode: currencyCode,
        )) {
          await cubit.confirmFiatSent(seen);
        }
      });

  Future<void> _undoFiatSent() => _once((cubit, seen) async {
    if (await ConfirmUndoFiatSentDialog.show(context)) {
      await cubit.undoFiatSent(seen);
    }
  });

  Future<void> _options({required bool collaborativeCancel}) => _once((
    cubit,
    seen,
  ) async {
    final chosen = await OrderOptionsDialog.show(
      context,
      collaborativeCancel: collaborativeCancel,
    );
    if (chosen != OrderOption.collaborativeCancel || !mounted) return;
    final peerAsked = switch (seen.status) {
      Chatting(:final peerAskedToCancel) => peerAskedToCancel,
      _ => false,
    };
    if (await ConfirmCollabCancelDialog.show(context, peerAsked: peerAsked)) {
      await cubit.cancel(seen);
    }
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final seen = widget.seen;
    final status = seen.status;
    final fiatSent = status is Chatting && status.fiatSent;
    final chatStep = widget.chatStep;
    final cancelling = widget.cancel is CancelRunning;
    final busy =
        chatStep is ChatStepRunning || cancelling || widget.otherActionRunning;
    final amount = _amount(context);
    final confirmOffered =
        widget.offersFiatSent &&
        amount != null &&
        ChatStepAction.confirmFiatSent.offeredAt(seen);
    final undoOffered =
        widget.offersUndoFiatSent &&
        ChatStepAction.undoFiatSent.offeredAt(seen);
    // « Collaborative Cancel » at 9 only, from a status marked stored read from an order (`Prompts/Chat.tsx:108`, `:135`).
    final collaborative =
        widget.offersCollaborativeCancel &&
        seen.stored &&
        seen.order?.status == CoordinatorOrderStatus.sendingFiat &&
        status is Chatting &&
        !status.fiatSent;
    final running = switch (chatStep) {
      ChatStepRunning(:final action) => action,
      _ => null,
    };
    // What the buttons wait for: an action of this step step by step, the collaborative cancel, or another action of the order.
    final waiting = switch (chatStep) {
      ChatStepRunning(:final progress, :final action) => progress.toText(
        context,
        coordinator: widget.coordinator,
        action: action,
      ),
      _ when cancelling => l10n.p2pEndStepSendingUndo(widget.coordinator),
      _ when widget.otherActionRunning && (confirmOffered || undoOffered) =>
        l10n.p2pEndStepWaitingForOrder,
      _ => null,
    };
    final chatNotice = switch (chatStep) {
      ChatStepIdle(:final notice?, :final action) => notice.toText(
        context,
        coordinator: widget.coordinator,
        action: action,
      ),
      _ => null,
    };
    final cancelNotice = switch (widget.cancel) {
      CancelIdle(:final notice?) => notice.toText(
        context,
        coordinator: widget.coordinator,
      ),
      _ => null,
    };
    final body = text.bodyMedium?.copyWith(color: colors.text);
    final showOptions = widget.offersCollaborativeCancel;
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
        const Gap(BullSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showOptions)
              _OptionsButton(
                onPressed: busy
                    ? null
                    : () => unawaited(
                        _options(collaborativeCancel: collaborative),
                      ),
              ),
            if (showOptions && (amount != null || undoOffered))
              const Gap(BullSpacing.sm),
            if (amount != null &&
                (confirmOffered || running == ChatStepAction.confirmFiatSent))
              Expanded(
                child: TradeButton(
                  label: l10n.p2pEndConfirmSent(amount.$1, amount.$2),
                  busy: running == ChatStepAction.confirmFiatSent,
                  onPressed: !confirmOffered || busy
                      ? null
                      : () => unawaited(_confirmFiatSent(amount.$1, amount.$2)),
                ),
              )
            else if (undoOffered || running == ChatStepAction.undoFiatSent)
              Expanded(
                child: TradeButton(
                  label: l10n.p2pEndPaymentFailed,
                  outlined: true,
                  color: colors.textMuted,
                  busy: running == ChatStepAction.undoFiatSent,
                  onPressed: !undoOffered || busy
                      ? null
                      : () => unawaited(_undoFiatSent()),
                ),
              ),
          ],
        ),
        if (waiting != null) ...[
          const Gap(BullSpacing.sm),
          _Live(waiting, color: colors.textMuted),
        ],
        for (final notice in [chatNotice, cancelNotice])
          if (notice != null) ...[
            const Gap(BullSpacing.sm),
            _Live(notice, color: colors.error),
          ],
      ],
    );
  }
}

/// « … », which opens « Order options » (`Prompts/Chat.tsx:205-215`: an outlined button with the reference's « open options » label).
class _OptionsButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _OptionsButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final label = P2pLocalizations.of(context).p2pEndOrderOptions;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        excludeSemantics: true,
        child: Opacity(
          opacity: onPressed == null ? 0.5 : 1,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(BullRadius.xxs),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52, minWidth: 52),
              decoration: BoxDecoration(
                border: Border.all(color: colors.primary),
                borderRadius: BorderRadius.circular(BullRadius.xxs),
              ),
              child: Icon(Icons.more_horiz, color: colors.primary),
            ),
          ),
        ),
      ),
    );
  }
}

/// A line read out as it changes: what an action waits for, or what it gave.
class _Live extends StatelessWidget {
  final String text;
  final Color color;

  const _Live(this.text, {required this.color});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
    ),
  );
}
