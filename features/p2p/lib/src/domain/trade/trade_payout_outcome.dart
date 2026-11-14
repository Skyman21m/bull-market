import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show PayoutRefused;

import '../p2p_failure.dart';
import '../trade_record.dart';
import 'trade_payout.dart';
import 'trade_storable.dart';
import 'trade_watch.dart';

/// Why `SubmitPayoutUsecase.execute` sent nothing to the coordinator: a type for each reason, which the panel words (#91), never a coordinator's text.
sealed class PayoutNotSent extends Failure {
  const PayoutNotSent();

  @override
  String toString() => runtimeType.toString();
}

/// The payout shown was checked for another trade than the one given.
final class PayoutOfAnotherTrade extends PayoutNotSent {
  const PayoutOfAnotherTrade();
}

/// The trade cannot be opened: [failure] says why (the records cannot be read, the Garage Key of the trade is not on this device, the binding refuses the coordinator).
final class PayoutTradeUnavailable extends PayoutNotSent {
  final P2pFailure failure;

  const PayoutTradeUnavailable(this.failure);

  @override
  String toString() => 'PayoutTradeUnavailable(${failure.runtimeType})';
}

/// The trade's stored records cannot be restored: it is shown read-only.
final class PayoutTradeUnrestorable extends PayoutNotSent {
  final TradeRecordRefusal reason;

  const PayoutTradeUnrestorable(this.reason);

  @override
  String toString() => 'PayoutTradeUnrestorable(${reason.runtimeType})';
}

/// The robot's key could not be read back or unlocked: [cause] says why (a `P2pFailure`, a `CoordinatorFailure` such as `RobotUnknown`, or a `PgpFailure`).
final class PayoutKeyUnavailable extends PayoutNotSent {
  final Failure cause;

  const PayoutKeyUnavailable(this.cause);

  @override
  String toString() => 'PayoutKeyUnavailable(${cause.runtimeType})';
}

/// The order could not be read just before signing, or the read could not be stored: nothing was signed. [cause] is the read's failure, or the write's; [seen] the trade as it then stands, when a read was kept.
final class PayoutReadFailed extends PayoutNotSent {
  final Failure? cause;
  final TradeSeen? seen;

  const PayoutReadFailed({this.cause, this.seen});

  @override
  String toString() => 'PayoutReadFailed(${cause?.runtimeType})';
}

/// The fresh read just before signing no longer lets this payout be given: [reason] says why ([PayoutNotAsked] when the status moved on, a payout given meanwhile or the step over), [seen] what the read showed.
final class PayoutNoLongerValid extends PayoutNotSent {
  final PayoutCheckRefusal reason;
  final TradeSeen seen;

  const PayoutNoLongerValid(this.reason, this.seen);

  @override
  String toString() => 'PayoutNoLongerValid($reason)';
}

/// The fresh read just before signing changed what the user would see (an amount, a fee, a warning): nothing was signed; [fresh] is the same destination checked again, to show and confirm again.
final class PayoutChangedSinceShown extends PayoutNotSent {
  final CheckedPayout fresh;
  final TradeSeen seen;

  const PayoutChangedSinceShown(this.fresh, this.seen);

  @override
  String toString() => 'PayoutChangedSinceShown($fresh)';
}

/// The robot's key did not sign it ([cause]), or what it signed is not exactly what was shown ([cause] `null`): nothing was sent.
final class PayoutNotSigned extends PayoutNotSent {
  final Failure? cause;

  const PayoutNotSigned(this.cause);

  @override
  String toString() => 'PayoutNotSigned(${cause?.runtimeType})';
}

/// The coordinator client refused it from the last read, twice, sending nothing ([PayoutRefused.fromLastRead], or no swap offered): [seen] is the last read.
final class PayoutRefusedFromRead extends PayoutNotSent {
  final PayoutRefused cause;
  final TradeSeen seen;

  const PayoutRefusedFromRead(this.cause, this.seen);

  @override
  String toString() => 'PayoutRefusedFromRead(${cause.runtimeType})';
}

/// What a payout sent gave, with the trade as the read after it shows it (the answer kept, then a read kept: a status marked stored, or the trail on disk's own, never one made up).
@immutable
sealed class PayoutSubmission {
  /// The trade's record as stored once the payout's writes are over.
  TradeRecord get record;

  /// The status after the answer and the read that followed it.
  TradeSeen get seen;

  /// A write that failed after the coordinator answered (the trail, the confirmation, the close).
  P2pFailure? get recordProblem;

  const PayoutSubmission();
}

/// The coordinator recorded the payout (`PayoutAccepted`): the order moves to 7 or 9 from 6, to 9 from 8, to 13 from 15 (`api/logics.py:909-947`).
final class PayoutGiven extends PayoutSubmission {
  @override
  final TradeRecord record;
  @override
  final TradeSeen seen;
  @override
  final P2pFailure? recordProblem;

  const PayoutGiven(this.record, this.seen, {this.recordProblem});

  @override
  String toString() => 'PayoutGiven(${seen.status})';
}

/// The coordinator recorded no payout: it refused it before recording one ([cause] a `PayoutRefused` kind, `OrderNotParticipant`, a refusal of the authentication), or the request never reached it (a busy transport every time, the robot released: [cause] a `P2pFailure`).
final class PayoutNotTaken extends PayoutSubmission {
  @override
  final TradeRecord record;
  @override
  final TradeSeen seen;
  @override
  final P2pFailure? recordProblem;
  final Failure cause;

  const PayoutNotTaken(
    this.record,
    this.seen, {
    required this.cause,
    this.recordProblem,
  });

  @override
  String toString() => 'PayoutNotTaken(${cause.runtimeType})';
}

/// The payout may have been recorded: no answer, or one that does not tell. Never sent again by the use case: [seen] is what the read after it showed (a status past the payout's step means the coordinator has it), and the watch of the trade tells the rest.
final class PayoutOutcomeUnknown extends PayoutSubmission {
  @override
  final TradeRecord record;
  @override
  final TradeSeen seen;
  @override
  final P2pFailure? recordProblem;

  const PayoutOutcomeUnknown(this.record, this.seen, {this.recordProblem});

  @override
  String toString() => 'PayoutOutcomeUnknown(${seen.status})';
}

/// Where a payout being given stands, for the panel to say what it waits for (`SubmitPayoutUsecase.execute`'s `onProgress`): each step is told when it starts.
enum PayoutProgress {
  /// Another action of the trade's order (a take, a cancel, another payout) is under way: the payout waits for it to end (`TradeTakeLocks`).
  waitingForOrder,

  /// The robot read back from its coordinator and its key unlocked away from the UI isolate: a few seconds the first time, nothing while the trade screen's hold keeps the key.
  unlockingKey,

  /// The order read again, just before the payout is signed.
  readingOrder,

  /// The payout sent to the coordinator, its answer awaited.
  sending,

  /// The order read again after the answer, to show what the coordinator recorded.
  readingAfter,
}
