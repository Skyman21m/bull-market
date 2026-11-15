import 'package:flutter/widgets.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/p2p_failure.dart';
import '../domain/trade/trade_cancel.dart';
import '../domain/trade/trade_chat_step.dart';
import '../domain/trade/trade_storable.dart';
import '../domain/trade/trade_take.dart';
import '../domain/trade/trade_terms.dart';
import '../domain/trade/trade_warning.dart';
import 'p2p_failure_l10n.dart';
import 'take_order_cubit.dart';
import 'trade_cubit.dart';
import 'trade_panel.dart';

/// What the order details say when a take did not happen (#88): a text of the app for each reason, never the coordinator's.
///
/// Where the official client shows the coordinator's own message for an error code (`TakeButton.tsx:340-341`, `api/errors.py`), the text is that message, from the feature's translations.
extension TakeProblemL10n on TakeProblem {
  /// The text, naming [coordinator], the long alias of the order's coordinator.
  String toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      TakeWasRefused(:final refusal) => switch (refusal) {
        TakeCoordinatorUnreadable() => l10n.p2pTakeCoordinatorUnreadable(
          coordinator,
        ),
        TakeOrderGone() => l10n.p2pOrderNotAvailable,
        TakeOrderChanged() => l10n.p2pTakeOrderChanged,
        TakeOfBuyOrderRefused() => l10n.p2pTakeSellingLater,
        TakeAmountRefused() => l10n.p2pTakeAmountOutOfRange,
        TakeTermsRefused(reason: TakerFeeTooHigh()) => l10n.p2pTakeFeeTooHigh(
          coordinator,
        ),
        TakeTermsRefused() => l10n.p2pTakeTermsUnusable,
        TakeRobotRefused(:final failure) => _robotRefused(
          context,
          failure,
          coordinator,
        ),
        TakeRobotNotPut(:final cause) => l10n.p2pTakeNotTakenAfter(
          cause.toRobotText(context, coordinator: coordinator),
        ),
        TakeNotRecorded() => l10n.p2pTakeNotRecorded,
        // The cubit opens that trade; shown only when it is the trade on screen, whose close could not be written.
        TakeOrderAlreadyTraded() => l10n.p2pTakeNotMade,
        // The cubit never shows it: a preparation that gives it ends in silence, a confirmation that gives it prepares again (#119).
        TakePreparationGone() => l10n.p2pTakeNotMade,
      },
      TakeWasNotMade(:final refusal) => switch (refusal) {
        null => l10n.p2pTakeNotMade,
        RobotAlreadyMaker() => l10n.p2pTakeAlreadyMaker,
        RobotAlreadyTaker() => l10n.p2pTakeAlreadyTaker,
        RobotAlreadyTaking() => l10n.p2pTakeAlreadyTaking,
        RobotPayoutPending() => l10n.p2pTakePaymentPending,
        OrderAmountOutOfRange() => l10n.p2pTakeAmountOutOfRange,
        OrderTakePenalty(secondsLeft: final seconds?) => l10n.p2pTakePenalty(
          '$seconds',
        ),
        OrderTakePenalty() => l10n.p2pTakeWaitPenalty,
        OrderNotAvailable() || OrderNotPublic() => l10n.p2pOrderNotAvailable,
        OrderCancelled() => l10n.p2pOrderCancelled,
        final CoordinatorFailure failure => l10n.p2pTakeNotTakenAfter(
          failure.toRobotText(context, coordinator: coordinator),
        ),
        final P2pFailure failure => l10n.p2pTakeNotTakenAfter(
          failure.toTranslated(context),
        ),
        _ => l10n.p2pTakeNotMade,
      },
    };
  }

  static String _robotRefused(
    BuildContext context,
    P2pFailure failure,
    String coordinator,
  ) {
    final l10n = P2pLocalizations.of(context);
    return switch (failure) {
      GarageKeyNotForTradesFailure() => l10n.p2pTakeKeyNotForTrades,
      RobotNotForNewTradeFailure() => l10n.p2pTakeRobotNotNew(coordinator),
      P2pStorageFailure() => l10n.p2pTakeNotRecorded,
      GarageKeyMissingFailure() ||
      TradeKeyMissingFailure() => l10n.p2pNoRobotTitle,
      _ => l10n.p2pTakeNotTakenAfter(
        failure.toRobotText(context, coordinator: coordinator),
      ),
    };
  }
}

/// What the wait of a take says it is doing (#119): one short line per step, naming the coordinator where it is the one asked.
extension TakeStepL10n on TakeStep {
  String toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      TakeStep.checkingOrder => l10n.p2pTakeStepCheckingOrder(coordinator),
      TakeStep.creatingRobot => l10n.p2pTakeStepCreatingRobot,
      TakeStep.readingOrder => l10n.p2pTakeStepReadingOrder,
      TakeStep.readingOrderAgain => l10n.p2pTakeStepReadingOrderAgain,
      TakeStep.sendingTake => l10n.p2pTakeStepSendingTake(coordinator),
    };
  }
}

/// The words of the trade screen for what the state machine (#86) and the watch (#87) give: a text of the app for each, naming the coordinator where it helps, never the coordinator's own text.
extension TradeWarningL10n on TradeWarning {
  String toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      TradeRoleMismatch() => l10n.p2pTradeWarnRole(coordinator),
      TradeOrderMismatch() => l10n.p2pTradeWarnOrder(coordinator),
      TradeTermsChanged() => l10n.p2pTradeWarnTerms,
      TradeStatusUnexpected() => l10n.p2pTradeWarnUnexpected,
      TradeStatusRegressed() => l10n.p2pTradeWarnRegressed(coordinator),
      CoordinatorInconsistent() => l10n.p2pTradeWarnInconsistent(coordinator),
      TradeHistoryUnknown() => l10n.p2pTradeWarnHistoryUnknown,
      BondAmountOutsideOrder() => l10n.p2pTradeWarnBond,
      TradePriceOutsideOrder() => l10n.p2pTradeWarnPrice,
      EscrowAmountMismatch() ||
      PayoutAmountMismatch() ||
      TakerFeeAboveAnnounced() => l10n.p2pTradeWarnAmounts(coordinator),
      DeadlineMovedBack() => l10n.p2pTradeWarnDeadline(coordinator),
      InvoiceUnreadable() => l10n.p2pTradeWarnUnreadable(coordinator),
      InvoiceWrongNetwork() => l10n.p2pTradeWarnWrongNetwork(coordinator),
      InvoiceAmountMismatch() => l10n.p2pTradeWarnInvoiceAmount,
      InvoiceExpired() => l10n.p2pTradeWarnExpired,
      InvoiceExpiringSoon() => l10n.p2pTradeWarnExpiringSoon,
      InvoiceHashChanged() => l10n.p2pTradeWarnHashChanged(coordinator),
      InvoicePayeeNotCoordinator() => l10n.p2pTradeWarnPayee(coordinator),
    };
  }
}

/// The message the trade screen shows alone.
extension TradeMessageKindL10n on TradeMessageKind {
  String toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      TradeMessageKind.cancelled => l10n.p2pOrderCancelled,
      TradeMessageKind.ended => l10n.p2pTradeEnded,
      TradeMessageKind.notAvailable => l10n.p2pOrderNotAvailable,
      TradeMessageKind.takePending => l10n.p2pTradeTakePending(coordinator),
      TradeMessageKind.takeNeverSent => l10n.p2pTradeTakeNeverSent(coordinator),
      TradeMessageKind.takeNotMade => l10n.p2pTakeNotMade,
      TradeMessageKind.unrestorable => l10n.p2pTradeUnrestorable,
      TradeMessageKind.coordinatorGone => l10n.p2pTradeCoordinatorGone(
        coordinator,
      ),
      TradeMessageKind.unavailable => l10n.p2pTradeUnavailable,
      TradeMessageKind.keyMissing => l10n.p2pTradeKeyMissing,
      TradeMessageKind.recordsUnreadable => l10n.p2pRobotRecordsUnreadable,
    };
  }
}

/// The title of a contract.
extension TradeTitleL10n on TradeTitle {
  /// [bondSats] is the bond of the title at 3, written already.
  String toText(BuildContext context, {required String bondSats}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      TradeTitle.lockBond => l10n.p2pTradeTitleLockBond(bondSats),
      TradeTitle.payout => l10n.p2pTradeTitlePayout,
      TradeTitle.infoGood => l10n.p2pTradeTitleInfoGood,
      TradeTitle.expired => l10n.p2pOrderExpired,
      TradeTitle.chat => l10n.p2pTradeTitleChat,
      TradeTitle.dispute => l10n.p2pTradeTitleDispute,
      TradeTitle.statementReceived => l10n.p2pTradeTitleStatementReceived,
      TradeTitle.sendingSats => l10n.p2pTradeTitleSendingSats,
      TradeTitle.finished => l10n.p2pTradeTitleFinished,
      TradeTitle.routingFailed => l10n.p2pTradeTitleRoutingFailed,
      TradeTitle.statements => l10n.p2pTradeTitleStatements,
      TradeTitle.disputeWon => l10n.p2pTradeTitleDisputeWon,
      TradeTitle.disputeLost => l10n.p2pTradeTitleDisputeLost,
      TradeTitle.unknown => l10n.p2pTradeTitleUnknown,
    };
  }
}

/// The expiry message of the official client's `Prompts/Expired.tsx`: the coordinator's label of the reason (`api/models/order.py:56-61`), from the feature's translations.
extension OrderExpiryReasonL10n on OrderExpiryReason {
  String toText(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      OrderExpiryReason.notTaken => l10n.p2pTradeExpiredNotTaken,
      OrderExpiryReason.makerBondNotLocked => l10n.p2pTradeExpiredMakerBond,
      OrderExpiryReason.escrowNotLocked => l10n.p2pTradeExpiredEscrow,
      OrderExpiryReason.invoiceNotSubmitted => l10n.p2pTradeExpiredInvoice,
      OrderExpiryReason.neitherEscrowNorInvoice => l10n.p2pTradeExpiredNeither,
    };
  }
}

/// What a cancel gave, when it says something.
extension TradeCancelNoticeL10n on TradeCancelNotice {
  String toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      CancelWasRefused(:final refusal) => switch (refusal) {
        CancelNeedsARead() => l10n.p2pTradeCancelNeedsRead,
        CancelLosesTheBond() => l10n.p2pTradeCancelBondText,
        CancelOnlyTogether() => l10n.p2pTradeCancelOnlyTogether,
        CancelNotPossible() => l10n.p2pTradeCancelNotPossible,
        // The status moved since the dialog was opened: nothing was sent, the screen shows the fresh status and its « Cancel ».
        CancelAcknowledgementMismatch() => l10n.p2pTradeCancelMovedOn,
        CancelOfAnotherTrade() => l10n.p2pTradeUnavailable,
        CancelTradeUnavailable(
          failure: GarageKeyMissingFailure() || TradeKeyMissingFailure(),
        ) =>
          l10n.p2pTradeKeyMissing,
        CancelTradeUnavailable() => l10n.p2pTradeUnavailable,
        CancelTradeUnrestorable(reason: TradeCoordinatorGone()) =>
          l10n.p2pTradeCoordinatorGone(coordinator),
        CancelTradeUnrestorable() => l10n.p2pTradeUnrestorable,
      },
      CancelWasNotDone(cause: OrderStatusChanged()) =>
        l10n.p2pTradeCancelMovedOn,
      CancelWasNotDone(cause: final CoordinatorFailure failure) =>
        l10n.p2pTradeCancelNotDoneAfter(
          failure.toRobotText(context, coordinator: coordinator),
        ),
      CancelWasNotDone(cause: final P2pFailure failure) =>
        l10n.p2pTradeCancelNotDoneAfter(failure.toTranslated(context)),
      CancelWasNotDone() => l10n.p2pTradeCancelNotDoneAfter(l10n.p2pBookError),
      CancelWasUnknown() => l10n.p2pTradeCancelUnknown,
    };
  }
}

/// What an action of the chat step gave, when it says something (#95): a text of the app, never the coordinator's.
extension ChatStepNoticeL10n on ChatStepNotice {
  /// The text of what [action] gave.
  String toText(
    BuildContext context, {
    required String coordinator,
    required ChatStepAction action,
  }) {
    final l10n = P2pLocalizations.of(context);
    final confirm = action == ChatStepAction.confirmFiatSent;
    final movedOn = confirm ? l10n.p2pEndMovedOn : l10n.p2pEndTradeMovedOn;
    String notSent(String reason) => confirm
        ? l10n.p2pEndNotDoneAfter(reason)
        : l10n.p2pEndRequestNotDoneAfter(reason);
    return switch (this) {
      ChatStepWasRefused(:final refusal) => switch (refusal) {
        ChatStepNotOffered() => l10n.p2pEndNeedsReadNotSent,
        // The status moved before anything was sent: the screen shows the fresh status, and its buttons.
        ChatStepStatusMoved() => movedOn,
        ChatStepReadFailed() => l10n.p2pEndReadFailed(coordinator),
        ChatStepOfAnotherTrade() => l10n.p2pTradeUnavailable,
        ChatStepTradeUnavailable(
          failure: GarageKeyMissingFailure() || TradeKeyMissingFailure(),
        ) =>
          l10n.p2pTradeKeyMissing,
        ChatStepTradeUnavailable() => l10n.p2pTradeUnavailable,
        ChatStepTradeUnrestorable(reason: TradeCoordinatorGone()) =>
          l10n.p2pTradeCoordinatorGone(coordinator),
        ChatStepTradeUnrestorable() => l10n.p2pTradeUnrestorable,
      },
      // Decided here from the read, nothing sent: as the read before sending would have said.
      ChatStepWasNotDone(cause: TradeActionRefused(fromLastRead: true)) =>
        movedOn,
      // The request left and the coordinator did nothing (1029, 1030, 1031): it says the order moved on.
      ChatStepWasNotDone(cause: TradeActionRefused()) =>
        confirm
            ? l10n.p2pEndNotRecordedMovedOn(coordinator)
            : l10n.p2pEndRequestNotRecordedMovedOn(coordinator),
      // The request never left: a busy transport (the robot panel's sentence, which ends with its full stop), a coordinator not on the network (its own sentence: the label « Coordinator offline » has no full stop to join).
      ChatStepWasNotDone(cause: CoordinatorTransportBusy()) => notSent(
        l10n.p2pRobotBusy,
      ),
      ChatStepWasNotDone(cause: CoordinatorNotOnNetwork()) =>
        confirm
            ? l10n.p2pEndOffline(coordinator)
            : l10n.p2pEndRequestOffline(coordinator),
      // Refused here before sending: never left.
      ChatStepWasNotDone(cause: OrderReadElsewhere()) => notSent(
        l10n.p2pBookError,
      ),
      // Any other refusal (1047, the empty 400 of the form check, the authentication's) left and was not recorded: the coordinator's, not « this robot ».
      ChatStepWasNotDone(cause: CoordinatorFailure()) =>
        confirm
            ? l10n.p2pEndRefusedBy(coordinator)
            : l10n.p2pEndRequestRefusedBy(coordinator),
      // The robot's places in the limiter, busy or released: never sent, said in the robot panel's full sentence.
      ChatStepWasNotDone(
        cause: RobotCoordinatorBusyFailure() || RobotReleasedFailure(),
      ) =>
        notSent(l10n.p2pRobotBusy),
      ChatStepWasNotDone() => notSent(l10n.p2pBookError),
      ChatStepWasUnknown() =>
        confirm ? l10n.p2pEndUnknown : l10n.p2pEndUnknownRequest,
    };
  }
}

/// What an action of the chat step waits for, step by step (the owner's rule: every wait says what it waits for).
extension ChatStepProgressL10n on ChatStepProgress? {
  /// The text of [action]'s step.
  String toText(
    BuildContext context, {
    required String coordinator,
    required ChatStepAction action,
  }) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      // The payout's words for the same waits (#91).
      null => l10n.p2pPayoutStepOpening,
      ChatStepProgress.waitingForOrder => l10n.p2pPayoutStepWaitingForOrder,
      ChatStepProgress.readingOrder => l10n.p2pPayoutStepReading(coordinator),
      ChatStepProgress.sending =>
        action == ChatStepAction.confirmFiatSent
            ? l10n.p2pEndStepSending(coordinator)
            : l10n.p2pEndStepSendingRequest(coordinator),
      ChatStepProgress.readingAfter => l10n.p2pPayoutStepReadingAfter(
        coordinator,
      ),
    };
  }
}
