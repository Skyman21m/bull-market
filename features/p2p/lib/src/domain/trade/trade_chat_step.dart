import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show CoordinatorClient, CoordinatorOrderStatus;

import '../p2p_failure.dart';
import '../trade_record.dart';
import 'trade_status.dart';
import 'trade_storable.dart';
import 'trade_watch.dart';

/// An action of the chat step (9 and 10) that `ChatStepActionUsecase` sends, one per button of the reference's `TradeBox/Prompts/Chat.tsx` this slice brings (#95).
enum ChatStepAction {
  /// « Confirm {{amount}} {{currencyCode}} sent »: the buyer's « fiat sent », 9 → 10 (`Logics.confirm_fiat`, `api/logics.py:1686-1735`).
  confirmFiatSent,

  /// « Payment failed? »: the buyer takes back « fiat sent », 10 → 9 (`Logics.undo_confirm_fiat_sent`, `api/logics.py:1737-1756`: the buyer only, 1030, at 10 only, 1031, with no time limit).
  undoFiatSent,

  /// « Open Dispute »: either side opens a dispute at 9 or 10, not earlier than 18 hours before the chat's end (`Logics.open_dispute`, `api/logics.py:485-533`: 1013 outside 9 and 10, 1054 too early); the escrow and both bonds go to the coordinator at once.
  openDispute;

  /// When « Open Dispute » becomes possible at [status]: the chat's end less `CoordinatorClient.disputeWindow` (18 hours, a constant of the reference's code), as the reference's prompt computes it (`Prompts/Chat.tsx:100-104`).
  static DateTime disputeOpensAt(Chatting status) =>
      status.deadline.subtract(CoordinatorClient.disputeWindow);

  /// Whether [seen] offers this action, as the reference's prompt offers its button (`Prompts/Chat.tsx:98-149`), and only from a status marked stored (`TradeSeen.stored`) that comes from an order read: « fiat sent » to the buyer at 9, « Payment failed? » to the buyer at 10, exactly where the coordinator takes each.
  bool offeredAt(TradeSeen seen) => switch (this) {
    ChatStepAction.confirmFiatSent =>
      seen.stored &&
          seen.order?.status == CoordinatorOrderStatus.sendingFiat &&
          switch (seen.status) {
            Chatting(role: TradeRole.buyer, fiatSent: false) => true,
            _ => false,
          },
    ChatStepAction.undoFiatSent =>
      seen.stored &&
          seen.order?.status == CoordinatorOrderStatus.fiatSent &&
          switch (seen.status) {
            Chatting(role: TradeRole.buyer, fiatSent: true) => true,
            _ => false,
          },
    // At 9 or 10; its time is checked apart ([disputeOpensAt]), against the clock.
    ChatStepAction.openDispute =>
      seen.stored &&
          (seen.order?.status == CoordinatorOrderStatus.sendingFiat ||
              seen.order?.status == CoordinatorOrderStatus.fiatSent) &&
          seen.status is Chatting,
  };

  /// Whether [seen] shows this action as recorded already: « fiat sent » at 10, or past it once the seller confirmed (13, 14, 15). A request that landed late, after the read that followed it, is found this way by the next tap's fresh read: nothing is sent again, and the action is done.
  bool doneAt(TradeSeen seen) => switch (this) {
    ChatStepAction.confirmFiatSent => switch (seen.status) {
      Chatting(role: TradeRole.buyer, fiatSent: true) ||
      SendingSats(role: TradeRole.buyer) ||
      Succeeded(role: TradeRole.buyer) ||
      RoutingFailed(role: TradeRole.buyer) => true,
      _ => false,
    },
    // Back at 9: only the buyer moves 10 to 9, so an earlier request of this robot landed.
    ChatStepAction.undoFiatSent => switch (seen.status) {
      Chatting(role: TradeRole.buyer, fiatSent: false) => true,
      _ => false,
    },
    // A dispute open, its statements, its decision.
    ChatStepAction.openDispute => switch (seen.status) {
      InDispute() ||
      WaitingDisputeResolution() ||
      DisputeWon() ||
      DisputeLost() => true,
      _ => false,
    },
  };
}

/// What `ChatStepActionUsecase` is doing, told as each step starts, for the screen to say what it waits for (the owner's rule: every wait says what it waits for).
enum ChatStepProgress {
  /// Another action of the trade's order (a take, a cancel, a payout, another action of the chat) is under way: this one waits for it to end (`TradeTakeLocks`).
  waitingForOrder,

  /// The order read again, just before the action is sent: it is sent only if the order is still at the status shown.
  readingOrder,

  /// The action sent to the coordinator, its answer awaited.
  sending,

  /// The order read again after the answer, to show what the coordinator recorded.
  readingAfter,
}

/// Why an action of the chat step was not sent: a type for each reason, which the screen words, never a coordinator's text.
sealed class ChatStepRefusal extends Failure {
  const ChatStepRefusal();

  @override
  String toString() => runtimeType.toString();
}

/// « Open Dispute » before its time ([ChatStepAction.disputeOpensAt]), by this device's clock: nothing was sent.
final class ChatStepTooEarly extends ChatStepRefusal {
  final DateTime opensAt;

  /// How long was left then, by this device's clock.
  final Duration left;

  const ChatStepTooEarly(this.opensAt, this.left);
}

/// The status seen does not offer the action ([ChatStepAction.offeredAt]): it comes from no order read, is not marked stored, or is another status or role.
final class ChatStepNotOffered extends ChatStepRefusal {
  const ChatStepNotOffered();
}

/// The order seen is not the trade's.
final class ChatStepOfAnotherTrade extends ChatStepRefusal {
  const ChatStepOfAnotherTrade();
}

/// The trade cannot be opened: [failure] says why (the records cannot be read, the key is missing, the binding refuses the coordinator).
final class ChatStepTradeUnavailable extends ChatStepRefusal {
  final P2pFailure failure;

  const ChatStepTradeUnavailable(this.failure);

  @override
  String toString() => 'ChatStepTradeUnavailable(${failure.runtimeType})';
}

/// The trade's stored records cannot be restored: it is shown read-only, and nothing is sent.
final class ChatStepTradeUnrestorable extends ChatStepRefusal {
  final TradeRecordRefusal reason;

  const ChatStepTradeUnrestorable(this.reason);

  @override
  String toString() => 'ChatStepTradeUnrestorable(${reason.runtimeType})';
}

/// The order could not be read just before the action, or that read could not be stored: nothing was sent. [cause] is the read's failure or the write's; [seen] the trade as it then stands, when a read was kept.
final class ChatStepReadFailed extends ChatStepRefusal {
  final Failure? cause;
  final TradeSeen? seen;

  /// The trade's record as the read left it, when a read was kept: an end closes it.
  final TradeRecord? record;

  const ChatStepReadFailed({this.cause, this.seen, this.record});

  @override
  String toString() => 'ChatStepReadFailed(${cause.runtimeType})';
}

/// The order read just before the action no longer shows the status the user saw (the seller confirmed, a dispute opened, the time ran out…): nothing was sent; [seen] is the status now.
final class ChatStepStatusMoved extends ChatStepRefusal {
  final TradeSeen seen;

  /// The trade's record as the read left it: an end closes it.
  final TradeRecord? record;

  const ChatStepStatusMoved(this.seen, {this.record});

  @override
  String toString() => 'ChatStepStatusMoved(${seen.status})';
}

/// What an action of the chat step sent gave, with the trade as the read after it shows it.
@immutable
sealed class ChatStepOutcome {
  /// The trade's record as stored once the action's writes are over.
  TradeRecord get record;

  /// The status after the action and the read that followed it, as stored (or the trail on disk's own): never one made up.
  TradeSeen get seen;

  /// A write that failed after the coordinator answered.
  P2pFailure? get recordProblem;

  const ChatStepOutcome();
}

/// The coordinator did the action.
final class ChatStepDone extends ChatStepOutcome {
  @override
  final TradeRecord record;
  @override
  final TradeSeen seen;
  @override
  final P2pFailure? recordProblem;

  const ChatStepDone(this.record, this.seen, {this.recordProblem});

  @override
  String toString() => 'ChatStepDone($record, ${seen.status})';
}

/// Nothing was done: the coordinator refused before acting, or the request never left (a busy transport, the robot released); [cause] says which.
final class ChatStepNotDone extends ChatStepOutcome {
  @override
  final TradeRecord record;
  @override
  final TradeSeen seen;
  @override
  final P2pFailure? recordProblem;
  final Failure cause;

  const ChatStepNotDone(
    this.record,
    this.seen, {
    required this.cause,
    this.recordProblem,
  });

  @override
  String toString() => 'ChatStepNotDone($record, ${cause.runtimeType})';
}

/// The action may have happened: its answer was lost or unreadable. The read after it shows [seen]; the screen shows that status as stored, and the watch of the trade tells the rest. Never sent again by itself.
final class ChatStepOutcomeUnknown extends ChatStepOutcome {
  @override
  final TradeRecord record;
  @override
  final TradeSeen seen;
  @override
  final P2pFailure? recordProblem;

  const ChatStepOutcomeUnknown(this.record, this.seen, {this.recordProblem});

  @override
  String toString() => 'ChatStepOutcomeUnknown($record, ${seen.status})';
}
