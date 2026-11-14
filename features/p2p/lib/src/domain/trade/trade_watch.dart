import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../p2p_failure.dart';
import '../trade_record.dart';
import 'trade_status.dart';
import 'trade_storable.dart';

/// A status of a trade as the user saw it, with the order it was read from: what `CancelTradeUsecase` cancels with.
@immutable
final class TradeSeen {
  final TradeStatus status;

  /// The order of the read [status] comes from, as the coordinator described it to the trade's robot; `null` when the status comes from no order (error 1043 or 1044, a trail restored and not read yet, a read refused as a whole).
  final CoordinatorOrder? order;

  const TradeSeen(this.status, {required this.order});

  @override
  String toString() => 'TradeSeen($status, read: ${order != null})';
}

/// What `WatchTradeUsecase` emits about one trade.
@immutable
sealed class TradeWatchState {
  /// The trade's record as last stored.
  TradeRecord get record;

  const TradeWatchState();
}

/// The trade's last status, after its record was restored or after a read.
final class TradeWatchStatus extends TradeWatchState {
  @override
  final TradeRecord record;
  final TradeSeen seen;

  /// How many reads in a row failed since the last one that told something (no answer, an answer that says nothing of the trade, a busy coordinator): the screen says it cannot reach the coordinator after three, and keeps [seen] with its age.
  final int failedReads;

  /// Why the last read failed, when [failedReads] is not zero: a `CoordinatorFailure` or a `P2pFailure`, never a coordinator's text.
  final Failure? lastReadFailure;

  /// A write of the trade's records that failed after the coordinator answered (the trail, the confirmation, the close), or a [TradeClosedFailure] when the record was closed and the coordinator now shows this robot as the taker: shown, never dropped (#87).
  ///
  /// When the trail could not be stored, [seen] is the stored trail's status, never the one the read computed: an invoice is shown or offered only from a status whose trail is stored (review of #117).
  final P2pFailure? recordProblem;

  /// Whether the trade is a take whose answer was lost, and no read has shown yet whether it happened: the reads go on until one shows this robot as the taker, or brings the take to an end ([TradeWatchTakeNotMade]).
  final bool takePending;

  const TradeWatchStatus(
    this.record,
    this.seen, {
    this.failedReads = 0,
    this.lastReadFailure,
    this.recordProblem,
    required this.takePending,
  });

  @override
  String toString() =>
      'TradeWatchStatus($record, ${seen.status}, failed: $failedReads, problem: ${recordProblem?.runtimeType}, pending: $takePending)';
}

/// The trade's stored records cannot be restored: shown read-only with [reason], never resumed, and nothing is sent ([TradeRecordMalformed], [TradeRecordOfAnotherTrade], or [TradeCoordinatorGone] for a coordinator that left the federation list).
final class TradeWatchUnrestorable extends TradeWatchState {
  @override
  final TradeRecord record;
  final TradeRecordRefusal reason;

  const TradeWatchUnrestorable(this.record, this.reason);

  @override
  String toString() => 'TradeWatchUnrestorable($record, ${reason.runtimeType})';
}

/// The trade cannot be read: [failure] is why, and nothing is sent (the records cannot be read, the Garage Key of the trade is not on this device, the robot's binding does not admit the coordinator any more…).
///
/// Listening again tries again.
final class TradeWatchUnavailable extends TradeWatchState {
  @override
  final TradeRecord record;
  final P2pFailure failure;

  const TradeWatchUnavailable(this.record, this.failure);

  @override
  String toString() => 'TradeWatchUnavailable($record, ${failure.runtimeType})';
}

/// A pending take whose terms or first trail were never written: its request never left, since the take sends nothing before both are written.
///
/// The record is closed at once, with no read ([closed]: false when the close could not be written, [recordProblem]); the stream ends.
final class TradeWatchTakeNeverSent extends TradeWatchState {
  @override
  final TradeRecord record;
  final bool closed;
  final P2pFailure? recordProblem;

  const TradeWatchTakeNeverSent(
    this.record, {
    required this.closed,
    this.recordProblem,
  });

  @override
  String toString() => 'TradeWatchTakeNeverSent($record, closed: $closed)';
}

/// A take this robot never held, closed: a pending take never confirmed, on which no pre-take (so no invoice) was ever seen, that a read brought to an end (the order public again with this robot no participant, cancelled, expired, or out of reach once the pre-take is certainly gone).
///
/// Nothing can have been paid from this app for it: the screen says the take was not made, never that a bond may have been lost. [closed] is false when the close could not be written ([recordProblem]); the stream ends.
final class TradeWatchTakeNotMade extends TradeWatchState {
  @override
  final TradeRecord record;
  final bool closed;
  final P2pFailure? recordProblem;

  const TradeWatchTakeNotMade(
    this.record, {
    required this.closed,
    this.recordProblem,
  });

  @override
  String toString() => 'TradeWatchTakeNotMade($record, closed: $closed)';
}

/// The trade is already watched by another subscription: one subscription per trade, so that a trade is never read twice at once; this one reads nothing, and ends.
final class TradeWatchAlreadyWatched extends TradeWatchState {
  @override
  final TradeRecord record;

  const TradeWatchAlreadyWatched(this.record);

  @override
  String toString() => 'TradeWatchAlreadyWatched($record)';
}

/// What the screen tells the watch of a trade.
enum TradeWatchSignal {
  /// The trade's screen is the one shown: the reference's cadence.
  onScreen,

  /// The app is in the foreground but the trade's screen is not the one shown: five times slower.
  offScreen,

  /// Read now, as on the return of the app to the foreground: at once, or right after the read in flight.
  readNow,
}
