import 'package:flutter/widgets.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/p2p_failure.dart';
import '../domain/trade/trade_cancel.dart';
import '../domain/trade/trade_chat_step.dart';
import '../domain/trade/trade_pause.dart';
import '../domain/trade/trade_status.dart';
import '../domain/trade/trade_storable.dart';
import '../domain/trade/trade_take.dart';
import '../domain/trade/trade_terms.dart';
import '../domain/trade/trade_warning.dart';
import 'p2p_failure_l10n.dart';
import 'p2p_formats.dart';
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
        // The screen asks for the password before sending; said should the use case refuse it all the same (#245).
        TakePasswordMissing() => l10n.p2pTakePasswordMissing,
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
        // Error 1045, the reference's message (`api/errors.py:52`), under the button as the reference shows it (`TakeButton.tsx:360-366`, #245).
        OrderWrongPassword() => l10n.p2pTakeWrongPassword,
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
      TakerFeeAboveAnnounced() ||
      MakerFeeAboveAnnounced() => l10n.p2pTradeWarnAmounts(coordinator),
      // Breaches of a maker's contract (#178): the coordinator contradicted what it said before, as an unexpected change.
      TradeTakerChanged() ||
      EscrowNotOfThisContract() => l10n.p2pTradeWarnUnexpected,
      // Information, not a breach (#178): a next contract seen late, in its own words (#182).
      ContractSeenLate() => l10n.p2pTradeWarnContractSeenLate,
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
  /// [amountSats] is the bond of the title at 3, or the seller's escrow at 6 and 7, written already (`TradeContract.titleSats`).
  String toText(BuildContext context, {required String amountSats}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      TradeTitle.lockBond => l10n.p2pTradeTitleLockBond(amountSats),
      TradeTitle.lockBondToPublish => l10n.p2pTradeTitleLockBondPublish(
        amountSats,
      ),
      TradeTitle.orderPublic => l10n.p2pTradeTitleOrderPublic,
      TradeTitle.orderPaused => l10n.p2pTradeTitleOrderPaused,
      TradeTitle.lockEscrow => l10n.p2pTradeTitleLockEscrow(amountSats),
      TradeTitle.collateralLocked => l10n.p2pTradeTitleCollateralLocked,
      TradeTitle.chatWithBuyer => l10n.p2pTradeTitleChatWithBuyer,
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

/// What a pause or an unpause gave, when it says something (#184): a text of the app, never the coordinator's (the reference shows nothing, its button only stops spinning, `TradeBox/index.tsx:226-241`).
extension TradePauseNoticeL10n on TradePauseNotice {
  String toText(BuildContext context, {required String coordinator}) {
    final l10n = P2pLocalizations.of(context);
    return switch (this) {
      PauseWasRefused(:final refusal) => switch (refusal) {
        PauseNotOffered() => l10n.p2pTradePauseNeedsRead,
        // The status moved before anything was sent: the screen shows the fresh status, and its button.
        PauseStatusMoved() => l10n.p2pTradePauseMovedOn,
        PauseReadFailed() => l10n.p2pTradePauseReadFailed(coordinator),
        PauseOfAnotherTrade() => l10n.p2pTradeUnavailable,
        PauseTradeUnavailable(
          failure: GarageKeyMissingFailure() || TradeKeyMissingFailure(),
        ) =>
          l10n.p2pTradeKeyMissing,
        PauseTradeUnavailable() => l10n.p2pTradeUnavailable,
        PauseTradeUnrestorable(reason: TradeCoordinatorGone()) =>
          l10n.p2pTradeCoordinatorGone(coordinator),
        PauseTradeUnrestorable() => l10n.p2pTradeUnrestorable,
      },
      // Decided by the package from the fresh read, nothing sent: as the read before sending would have said.
      PauseWasNotDone(
        cause: TradeActionRefused(fromLastRead: true) || OrderReadElsewhere(),
      ) =>
        l10n.p2pTradePauseMovedOn,
      // The request never left: a busy transport or robot.
      PauseWasNotDone(
        cause: CoordinatorTransportBusy() ||
            RobotCoordinatorBusyFailure() ||
            RobotReleasedFailure(),
      ) =>
        l10n.p2pTradePauseNotDoneAfter(l10n.p2pRobotBusy),
      // Never left either, the coordinator not on the trade's network (unreachable here, the read just before having reached it): the generic words.
      PauseWasNotDone(cause: CoordinatorNotOnNetwork()) =>
        l10n.p2pTradePauseNotDoneAfter(l10n.p2pBookError),
      // The signature refused for a reason of its own (1059, 1060, 1061): its words, before nothing changed.
      PauseWasNotDone(
        cause: ActionSignatureRefused(
              reason: ActionSignatureRefusal.clockSkew ||
                  ActionSignatureRefusal.missing ||
                  ActionSignatureRefusal.otherCoordinator,
            ) &&
            final CoordinatorFailure refused,
      ) =>
        l10n.p2pTradePauseNotDoneAfter(
          refused.toRobotText(context, coordinator: coordinator),
        ),
      // Any other refusal left and changed nothing (1032, 1033, 1047, the empty 400 of the form check, the authentication's): the coordinator's, never its text.
      PauseWasNotDone(cause: CoordinatorFailure()) =>
        l10n.p2pTradePauseRefusedBy(coordinator),
      PauseWasNotDone(cause: final P2pFailure failure) =>
        l10n.p2pTradePauseNotDoneAfter(failure.toTranslated(context)),
      PauseWasNotDone() => l10n.p2pTradePauseNotDoneAfter(l10n.p2pBookError),
      PauseWasUnknown() => l10n.p2pTradePauseUnknown(coordinator),
      PauseWasNotReached(wanted: PauseWanted.paused) =>
        l10n.p2pTradePauseNotReachedPaused(coordinator),
      PauseWasNotReached(wanted: PauseWanted.public) =>
        l10n.p2pTradePauseNotReachedPublic(coordinator),
      PausePublicAgain() => l10n.p2pTradePublicAgain,
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
    // Each action in its own words: « confirmation » for « fiat sent » and the seller's « received », « request » for « Payment failed? », the dispute named for « Open Dispute », so that the user knows whether the dispute is open, not open, or not known yet (review of #156).
    String said({
      required String confirmation,
      required String request,
      required String dispute,
    }) => switch (action) {
      ChatStepAction.confirmFiatSent ||
      ChatStepAction.confirmFiatReceived => confirmation,
      // A rating is a request too: « Rate your trade experience » says nothing when it is done, as the reference.
      ChatStepAction.undoFiatSent || ChatStepAction.rate => request,
      ChatStepAction.dispute => dispute,
    };
    final movedOn = said(
      confirmation: l10n.p2pEndMovedOn,
      request: l10n.p2pEndTradeMovedOn,
      dispute: l10n.p2pEndDisputeMovedOn,
    );
    String notSent(String reason) => said(
      confirmation: l10n.p2pEndNotDoneAfter(reason),
      request: l10n.p2pEndRequestNotDoneAfter(reason),
      dispute: l10n.p2pEndDisputeNotSentAfter(reason),
    );
    return switch (this) {
      ChatStepWasRefused(:final refusal) => switch (refusal) {
        // The rating in its own words: the user rated, confirmed nothing; and no read of an end is coming to wait for.
        ChatStepNotOffered() when action == ChatStepAction.rate =>
          l10n.p2pEndRateNotSent,
        ChatStepNotOffered() =>
          action == ChatStepAction.dispute
              ? l10n.p2pEndDisputeNeedsRead
              : l10n.p2pEndNeedsReadNotSent,
        // Too early by the fresh read: the reference coordinator's own words, as its 1054 would say; no countdown here, which would stand still (the countdown is under « Open Dispute »), and the panel stops showing it once the dispute's time has come (review of #156).
        ChatStepTooEarly() => l10n.p2pEndDisputeTooEarly,
        // The fresh read refused (a status kept from no order, or none understood): nothing moved, the read carries an alert, which the screen shows above (security review of #219, C2).
        ChatStepStatusMoved(:final seen)
            when (seen.order == null || seen.status is StatusUnknown) &&
                seen.status.warnings.isNotEmpty =>
          l10n.p2pEndNotSentReadRefused,
        // Refused before sending with no alert to point at (an order the coordinator says cancelled, error 1043): only that nothing was sent (security review of #219, R5).
        ChatStepStatusMoved(:final seen)
            when seen.order == null || seen.status is StatusUnknown =>
          l10n.p2pEndNotSent,
        // The status moved before anything was sent: the screen shows the fresh status, and its buttons.
        ChatStepStatusMoved() => movedOn,
        ChatStepReadFailed() when action == ChatStepAction.rate =>
          l10n.p2pEndRateReadFailed(coordinator),
        ChatStepReadFailed() =>
          action == ChatStepAction.dispute
              ? l10n.p2pEndDisputeReadFailed(coordinator)
              : l10n.p2pEndReadFailed(coordinator),
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
      // « Open Dispute » too early, by the coordinator's clock (1054) or the package's for the last read: the reference coordinator's own words.
      ChatStepWasNotDone(cause: DisputeTooEarly()) =>
        l10n.p2pEndDisputeTooEarly,
      // The seller's confirmation refused because the escrow is not above the buyer's payout (1028): the order did not move, the coordinator refused it.
      ChatStepWasNotDone(cause: EscrowBelowPayout()) => l10n.p2pEndRefusedBy(
        coordinator,
      ),
      // Decided here from the read, nothing sent: as the read before sending would have said.
      ChatStepWasNotDone(cause: TradeActionRefused(fromLastRead: true)) =>
        movedOn,
      // The request left and the coordinator did nothing (1029, 1030, 1031): it says the order moved on.
      ChatStepWasNotDone(cause: TradeActionRefused()) => said(
        confirmation: l10n.p2pEndNotRecordedMovedOn(coordinator),
        request: l10n.p2pEndRequestNotRecordedMovedOn(coordinator),
        dispute: l10n.p2pEndDisputeNotRecordedMovedOn(coordinator),
      ),
      // The request never left: a busy transport (the robot panel's sentence, which ends with its full stop), a coordinator not on the network (its own sentence: the label « Coordinator offline » has no full stop to join).
      ChatStepWasNotDone(cause: CoordinatorTransportBusy()) => notSent(
        l10n.p2pRobotBusy,
      ),
      ChatStepWasNotDone(cause: CoordinatorNotOnNetwork()) => said(
        confirmation: l10n.p2pEndOffline(coordinator),
        request: l10n.p2pEndRequestOffline(coordinator),
        dispute: l10n.p2pEndDisputeOffline(coordinator),
      ),
      // Refused here before sending: never left.
      ChatStepWasNotDone(cause: OrderReadElsewhere()) => notSent(
        l10n.p2pBookError,
      ),
      // The signature refused for a reason of its own (1059, 1060, 1061): its words; nothing was recorded.
      ChatStepWasNotDone(
        cause: ActionSignatureRefused(
              reason: ActionSignatureRefusal.clockSkew ||
                  ActionSignatureRefusal.missing ||
                  ActionSignatureRefusal.otherCoordinator,
            ) &&
            final CoordinatorFailure refused,
      ) =>
        notSent(refused.toRobotText(context, coordinator: coordinator)),
      // Any other refusal (1047, the empty 400 of the form check, the authentication's) left and was not recorded: the coordinator's, not « this robot ».
      ChatStepWasNotDone(cause: CoordinatorFailure()) => said(
        confirmation: l10n.p2pEndRefusedBy(coordinator),
        request: l10n.p2pEndRequestRefusedBy(coordinator),
        dispute: l10n.p2pEndDisputeRefusedBy(coordinator),
      ),
      // The robot's places in the limiter, busy or released: never sent, said in the robot panel's full sentence.
      ChatStepWasNotDone(
        cause: RobotCoordinatorBusyFailure() || RobotReleasedFailure(),
      ) =>
        notSent(l10n.p2pRobotBusy),
      ChatStepWasNotDone() => notSent(l10n.p2pBookError),
      // No read tells a rating: nothing keeps checking it.
      ChatStepWasUnknown() when action == ChatStepAction.rate =>
        l10n.p2pEndRateUnknown,
      // The seller's release of the escrow: the reference coordinator answers `200` at 10 when it could not settle it and does not try again by itself, so the reads alone may never move on: say what to do (#96).
      ChatStepWasUnknown() when action == ChatStepAction.confirmFiatReceived =>
        l10n.p2pEndUnknownReceived,
      ChatStepWasUnknown() => said(
        confirmation: l10n.p2pEndUnknown,
        request: l10n.p2pEndUnknownRequest,
        dispute: l10n.p2pEndDisputeUnknown,
      ),
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
      ChatStepProgress.sending => switch (action) {
        ChatStepAction.confirmFiatSent || ChatStepAction.confirmFiatReceived =>
          l10n.p2pEndStepSending(coordinator),
        ChatStepAction.undoFiatSent ||
        ChatStepAction.rate => l10n.p2pEndStepSendingRequest(coordinator),
        ChatStepAction.dispute => l10n.p2pEndStepSendingDispute(coordinator),
      },
      ChatStepProgress.readingAfter => l10n.p2pPayoutStepReadingAfter(
        coordinator,
      ),
    };
  }
}

/// « To open a dispute you need to wait {{hours}}h {{minutes}}m » for [left], as the reference's countdown writes it (`Prompts/Chat.tsx:86-96`: whole hours, then the minutes on two digits); nothing below zero.
String disputeWait(P2pLocalizations l10n, Duration left) {
  final minutes = left.isNegative ? 0 : left.inMinutes;
  return l10n.p2pEndDisputeWait(
    '${minutes ~/ 60}',
    '${minutes % 60}'.padLeft(2, '0'),
  );
}

extension MakeOrderRequestL10n on MakeOrderRequest {
  /// The terms kept of an order made here, as the create form's summary says them (« Buy BTC for 100 EUR at market price », `MakerForm.tsx:576-625`), a range as « min-max » with every decimal kept: the trade screen's line of the terms kept (#216). Only the side, the amount, the currency and the premium: the payment methods and the options are shown on the renewal's page.
  String summary(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final start = switch (type) {
      OrderType.buy => l10n.p2pMakeBuyBtcFor,
      OrderType.sell => l10n.p2pMakeSellBtcFor,
    };
    final shown = switch (amount) {
      FixedOrderAmount(:final amount) => formats.typedNumber(amount.value),
      RangeOrderAmount(:final min, :final max) =>
        '${formats.typedNumber(min.value)}-${formats.typedNumber(max.value)}',
    };
    final percent = premium.percent;
    final price = percent == 0
        ? l10n.p2pMakeAtMarketPrice
        : percent > 0
        ? l10n.p2pMakeAtPremium(formats.number(percent))
        : l10n.p2pMakeAtDiscount(formats.number(-percent));
    return '$start$shown ${currency.code}$price';
  }
}
