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
import '../widgets/word_fit_text.dart';
import 'chat_actions.dart';
import 'confirm_collab_cancel_dialog.dart';
import 'confirm_dispute_dialog.dart';
import 'confirm_fiat_received_dialog.dart';
import 'confirm_fiat_sent_dialog.dart';
import 'confirm_undo_fiat_sent_dialog.dart';
import 'order_options_dialog.dart';

/// The chat step, 9 and 10 (`TradeBox/Prompts/Chat.tsx`, commit ff1998c; #95, the seller's #96): the reference's prompt for the side and « ⚠️ Beware scams », the place of the chat, then the action buttons under it, as the reference lays them out: « … » (« Order options ») and, for the buyer, « Confirm {{amount}} {{currencyCode}} sent » at 9 and « Payment failed? » at 10; for the seller, « Confirm {{amount}} {{currencyCode}} received », shown off at 9 and on at 10, once « fiat sent » is recorded (`Prompts/Chat.tsx:237-247`).
///
/// « Confirm … received » opens the reference's dialog ([ConfirmFiatReceivedDialog]) and releases the escrow to the buyer on « Confirm »: once, for the status seen when the button was pressed, never again by itself.
/// « Confirm … sent » opens the reference's dialog ([ConfirmFiatSentDialog]), « Payment failed? » its own ([ConfirmUndoFiatSentDialog]), « Collaborative Cancel » in « Order options » its own ([ConfirmCollabCancelDialog]); each sends once through the trade's cubit, for the status shown when the button was pressed.
/// While an action of the trade runs (one of these, a cancel, a payout), the buttons are off and a line says what it waits for, step by step; what an action gave is said under them.
/// The status shown is the status stored: nothing here changes it before a read does.
class ChatStepPanel extends StatefulWidget {
  final TradeSeen seen;

  /// The order the status comes from, whose amount and currency are compared with the trade's terms (the buttons are worded from the terms, `Chatting.amount`).
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

  /// Whether the seller's « Confirm … received » may be offered: the screen's cubit sends it (#96).
  final bool offersFiatReceived;

  /// Whether « Open Dispute » may be offered in « Order options »: the screen's cubit sends it.
  final bool offersDispute;

  /// The screen's clock, for « Open Dispute »'s countdown.
  final DateTime Function() now;

  /// The chat of the trade (#93, `ChatPanel`), where the reference puts it: between the prompt's text and the action buttons; `null` where the feature holds no robot, and the step is shown without it.
  final Widget? chat;

  /// « Audit Chat » and « Export » of « Order options » (#157), built when « … » is pressed, over the cubit of [chat]; `null` with it, and « Order options » is shown without them.
  final ChatOptions Function()? chatOptions;

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
    this.offersFiatReceived = false,
    this.offersDispute = false,
    required this.now,
    this.chat,
    this.chatOptions,
  });

  @override
  State<ChatStepPanel> createState() => _ChatStepPanelState();
}

class _ChatStepPanelState extends State<ChatStepPanel> {
  /// Whether a dialog is open: a second press meanwhile opens nothing more.
  bool _asking = false;

  /// The undo dialog's counter, kept for this page as the reference's dialog keeps it (it stays mounted with the page): 60 seconds at first, running only while the dialog is open, 300 after « Confirm ».
  final ValueNotifier<int> _undoWait = ValueNotifier(
    ConfirmUndoFiatSentDialog.firstWait,
  );

  /// Rebuilds the panel when « Open Dispute »'s time comes, so that a « too early » notice goes then (review of #156).
  Timer? _disputeOpens;

  @override
  void dispose() {
    _disputeOpens?.cancel();
    _undoWait.dispose();
    super.dispose();
  }

  /// Whether [chatStep]'s notice is not « Open Dispute » refused as too early by its fresh read, or is still true: that refusal goes once the dispute's time has come by the status shown, which a new read may move, as « Open Dispute » turns on in « Order options » at that very time (review of #156); the panel is rebuilt then. The coordinator's own 1054 is not judged by this device's clock, which already said the time had come when it was sent: it goes as the other notices go.
  bool _tooEarlyStillTrue(ChatStepState chatStep) {
    final tooEarly = switch (chatStep) {
      ChatStepIdle(notice: ChatStepWasRefused(refusal: ChatStepTooEarly())) =>
        true,
      _ => false,
    };
    final status = widget.seen.status;
    if (!tooEarly || status is! Chatting) return true;
    final left = ChatStepAction.disputeOpensAt(status).difference(widget.now());
    if (left <= Duration.zero) return false;
    _disputeOpens = Timer(left, () {
      if (mounted) setState(() {});
    });
    return true;
  }

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

  Future<void> _confirmFiatReceived(String amount, String currencyCode) =>
      _once((cubit, seen) async {
        if (await ConfirmFiatReceivedDialog.show(
          context,
          amount: amount,
          currencyCode: currencyCode,
        )) {
          await cubit.confirmFiatReceived(seen);
        }
      });

  Future<void> _undoFiatSent() => _once((cubit, seen) async {
    if (await ConfirmUndoFiatSentDialog.show(context, left: _undoWait)) {
      await cubit.undoFiatSent(seen);
    }
  });

  Future<void> _options({required bool collaborativeCancel}) => _once((
    cubit,
    seen,
  ) async {
    final status = seen.status;
    final chatOptions = widget.chatOptions?.call();
    final chosen = await OrderOptionsDialog.show(
      context,
      // First, as the reference places them: the chat's « Audit Chat » and « Export ».
      auditChat: chatOptions?.auditChat,
      export: chatOptions?.export,
      collaborativeCancel: collaborativeCancel,
      // « Open Dispute » where the status shown offers it, with its time; not drawn otherwise.
      disputeOpensAt:
          widget.offersDispute &&
              status is Chatting &&
              ChatStepAction.dispute.offeredAt(seen)
          ? ChatStepAction.disputeOpensAt(status)
          : null,
      now: widget.now,
    );
    if (!mounted) return;
    if (chosen == OrderOption.dispute) {
      if (await ConfirmDisputeDialog.show(context)) {
        await cubit.startDispute(seen);
      }
      return;
    }
    if (chosen != OrderOption.collaborativeCancel) return;
    // The dialog follows the cubit: a peer's ask that arrives while it is open turns its button into « Accept Cancelation ».
    if (await ConfirmCollabCancelDialog.show(context, cubit: cubit)) {
      await cubit.cancel(seen);
    }
  });

  @override
  Widget build(BuildContext context) {
    // The timer of a « too early » notice lives no longer than the build that shows it: armed again below while that notice is still shown (review of #156).
    _disputeOpens?.cancel();
    _disputeOpens = null;
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
    final seller = status is Chatting && status.role == TradeRole.seller;
    final receivedOffered =
        widget.offersFiatReceived &&
        amount != null &&
        ChatStepAction.confirmFiatReceived.offeredAt(seen);
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
      _ when cancelling => l10n.p2pEndStepSendingRequest(widget.coordinator),
      _
          when widget.otherActionRunning &&
              (confirmOffered || undoOffered || receivedOffered) =>
        l10n.p2pPayoutStepWaitingForOrder,
      _ => null,
    };
    final waitedLong =
        (chatStep is ChatStepRunning && chatStep.waitedLong) ||
        switch (widget.cancel) {
          CancelRunning(:final waitedLong) => waitedLong,
          _ => false,
        };
    // The buyer at 9, where the prompt says to press « Confirm … sent »: shown off with why when the status shown does not offer it (not marked stored, or from no order read).
    final atNine =
        widget.offersFiatSent &&
        status is Chatting &&
        status.role == TradeRole.buyer &&
        !status.fiatSent;
    // The seller's button, shown at 9 (off, as the reference's `disabled={order.status < 10}`) and at 10.
    final sellerButton = widget.offersFiatReceived && seller;
    final differs = amount == null || !(atNine || sellerButton)
        ? null
        : _amountDiffers(context, amount);
    final chatNotice = switch (chatStep) {
      ChatStepIdle(:final notice?, :final action)
          when _tooEarlyStillTrue(chatStep) =>
        notice.toText(context, coordinator: widget.coordinator, action: action),
      _ => null,
    };
    final cancelNotice = switch (widget.cancel) {
      // A collaborative ask whose answer was lost: said as a request, never as a cancel that may have happened.
      CancelIdle(notice: CancelWasUnknown()) => l10n.p2pEndUnknownRequest,
      CancelIdle(:final notice?) => notice.toText(
        context,
        coordinator: widget.coordinator,
      ),
      _ => null,
    };
    // At 9 the seller's button is off by the reference's own rule, with no line; at 10 it is off only while the status shown cannot be acted on.
    final needsRead =
        ((atNine && !confirmOffered) ||
            (sellerButton && fiatSent && !receivedOffered)) &&
        running == null &&
        chatNotice == null;
    // An outcome unknown is no failure: the action may well have gone through (the payout's notice of the same kind is in the warning colour too); red only where it was not recorded.
    final chatNoticeColor = switch (chatStep) {
      ChatStepIdle(notice: ChatStepWasUnknown()) => colors.warning,
      _ => colors.error,
    };
    final cancelNoticeColor = switch (widget.cancel) {
      CancelIdle(notice: CancelWasUnknown()) => colors.warning,
      _ => colors.error,
    };
    final body = text.bodyMedium?.copyWith(color: colors.text);
    final showOptions = widget.offersCollaborativeCancel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          switch ((seller, fiatSent)) {
            (false, false) => l10n.p2pEndChatBuyerHi,
            (false, true) => l10n.p2pEndWaitSeller,
            (true, false) => l10n.p2pEndChatSellerHi(
              amount?.$1 ?? '',
              amount?.$2 ?? '',
            ),
            (true, true) => l10n.p2pEndBuyerSentFiat,
          },
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
                (sellerButton || running == ChatStepAction.confirmFiatReceived))
              Expanded(
                child: TradeButton(
                  label: l10n.p2pEndConfirmReceived(amount.$1, amount.$2),
                  busy: running == ChatStepAction.confirmFiatReceived,
                  onPressed: !receivedOffered || busy
                      ? null
                      : () => unawaited(
                          _confirmFiatReceived(amount.$1, amount.$2),
                        ),
                ),
              )
            else if (amount != null &&
                (atNine || running == ChatStepAction.confirmFiatSent))
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
              // The reference's small grey text button, deliberately discreet (`size='small'`, `text.secondary`).
              Expanded(
                child: _QuietButton(
                  label: l10n.p2pEndPaymentFailed,
                  busy: running == ChatStepAction.undoFiatSent,
                  onPressed: !undoOffered || busy
                      ? null
                      : () => unawaited(_undoFiatSent()),
                ),
              ),
          ],
        ),
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
          _Live(waiting, color: colors.textMuted),
          // The bar named by the step, and the long wait's line, as the payout and the take show them; for the collaborative cancel's ask too.
          if (running != null || cancelling) ...[
            const Gap(BullSpacing.xs),
            LinearProgressIndicator(
              color: colors.primary,
              semanticsLabel: waiting,
            ),
          ],
          if (waitedLong) ...[
            const Gap(BullSpacing.xs),
            _Live(
              l10n.p2pRobotStillWaiting(widget.coordinator),
              color: colors.textMuted,
            ),
          ],
        ],
        if (needsRead) ...[
          const Gap(BullSpacing.sm),
          _Live(l10n.p2pEndNeedsRead, color: colors.textMuted),
        ],
        for (final (notice, color) in [
          (chatNotice, chatNoticeColor),
          (cancelNotice, cancelNoticeColor),
        ])
          if (notice != null) ...[
            const Gap(BullSpacing.sm),
            _Live(notice, color: color),
          ],
      ],
    );
  }
}

/// [text] without the emoji and the space it starts with (« ⚠️ Beware scams », « ✅ Confirm you sent … »), for a screen reader, which would read the emoji's name first.
String withoutLeadingEmoji(String text) =>
    text.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '');

/// What an action of the chat step gave, read out as it appears: in the warning colour for an outcome unknown, which is no failure (the confirmation may well have gone through, as the payout's notice of the same kind), red only where it was not recorded; shown by the chat step's panel at 9 and 10, and by the trade screen under any other status the order moved to.
class ChatStepNoticeLine extends StatelessWidget {
  final ChatStepNotice notice;
  final String coordinator;

  /// The action the notice is about, whose words it takes.
  final ChatStepAction action;

  const ChatStepNoticeLine({
    super.key,
    required this.notice,
    required this.coordinator,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Text(
        notice.toText(context, coordinator: coordinator, action: action),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: notice is ChatStepWasUnknown ? colors.warning : colors.error,
        ),
      ),
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
    // One node of its own, with its tap, read as the reference's label (`aria-label='open options'`); no tooltip, as the reference has none.
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: P2pLocalizations.of(context).p2pEndOpenOptions,
      onTap: onPressed,
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
    );
  }
}

/// A small text button in the muted colour, as the reference's « Payment failed? » (`Prompts/Chat.tsx:226-237`: `size='small'`, `text.secondary`), in the wallet's look; its label wraps at word boundaries only.
class _QuietButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  const _QuietButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final enabled = onPressed != null && !busy;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(BullRadius.xxs),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy) ...[
                  SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.textMuted,
                    ),
                  ),
                  const Gap(BullSpacing.xs),
                ],
                Flexible(
                  child: WordFitText(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: colors.textMuted),
                  ),
                ),
              ],
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
