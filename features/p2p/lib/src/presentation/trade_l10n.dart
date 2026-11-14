import 'package:flutter/widgets.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/p2p_failure.dart';
import '../domain/trade/trade_cancel.dart';
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
      TradeMessageKind.notAvailable => l10n.p2pOrderNotAvailable,
      TradeMessageKind.takePending => l10n.p2pTradeTakePending(coordinator),
      TradeMessageKind.takeNeverSent => l10n.p2pTradeTakeNeverSent(coordinator),
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
