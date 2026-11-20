import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../p2p_failure.dart';
import '../trade_record.dart';
import 'payout_trace.dart';
import 'trade_status.dart';
import 'trade_storable.dart';
import 'trade_tolerances.dart';
import 'trade_warning.dart';

/// A status of a trade as the user saw it, with the order it was read from: what `CancelTradeUsecase` cancels with.
@immutable
final class TradeSeen {
  final TradeStatus status;

  /// The order of the read [status] comes from, as the coordinator described it to the trade's robot; `null` when the status comes from no order (error 1043 or 1044, a trail restored and not read yet, a read refused as a whole).
  final CoordinatorOrder? order;

  /// Whether [status] is the one computed from the read it carries and stored with its trail by this read: **only such a status may show an invoice or offer a payment** (review of #117).
  ///
  /// False for a status of the trail on disk when the read's own could not be stored, or was kept out by another write (`TradeStatus.beforeFirstRead`: no invoice, no order), for a trail restored and not read yet, and for an end that another write stored first.
  final bool stored;

  /// When the read [status] comes from was sent, when known: what it shows is no older than that, where [TradeStatus.seenAt] is when its answer was read (review of #132: a read sent before a payout was recorded can come back after it).
  final DateTime? requestedAt;

  /// For a trade made here, the order's amount as its maker asked it (the terms' fixed amount or range), so that a screen judges the amount read against it without the terms at hand ([contractAmount], [contractAmountMoved]); `null` for a taker, whose amounts come from its take or the order as before, and where the terms were not at hand.
  final OrderAmount? asked;

  /// For a buyer's trade, where the payout of the contract [status]'s trail stands at came from, as this device's records say (schema 9, #204), which « Confirm … sent » is preceded by; `null` where it was not read (a seller's trade, a status no reader of the records built).
  final PayoutTrace? payout;

  const TradeSeen(
    this.status, {
    required this.order,
    this.stored = false,
    this.requestedAt,
    this.asked,
    this.payout,
  });

  /// This status, with [payout] as where its contract's payout came from.
  TradeSeen withPayout(PayoutTrace? payout) => TradeSeen(
    status,
    order: order,
    stored: stored,
    requestedAt: requestedAt,
    asked: asked,
    payout: payout,
  );

  /// Whether the order read gives the contract another amount than the one asked here: for a range, other than the one kept with the contract (`TradeTrail.takenAmount`, kept from the contract's first read), or none; for a fixed amount ([asked], or [madeAs]), another amount or a range (security review of #183, C4, a defect of #182). The state machine then says the terms changed (`TradeTermsChanged`, or refuses the read as a whole), and nothing compares or words a figure with either amount while it lasts, so that no line reassures beside that alert (#183, C5). A status from no order says nothing moved.
  bool get contractAmountMoved => contractAmountMovedFrom(asked);

  /// [contractAmountMoved], the order's amount as asked here being [madeAs] (the maker's terms' amount), for a caller that holds the terms.
  bool contractAmountMovedFrom(OrderAmount? madeAs) {
    final order = this.order;
    if (order == null) return false;
    final kept = status.trail.takenAmount;
    if (kept != null) {
      final read = order.takenAmount?.value;
      // The state machine's own comparison, the amount read first (`_madeTermsChanged`): its warning and this never diverge.
      return read == null || !TradeTolerances.sameFiat(read, kept);
    }
    return switch ((madeAs, order.amount)) {
      (
        FixedOrderAmount(amount: final asked),
        FixedOrderAmount(amount: final read),
      ) =>
        !TradeTolerances.sameFiat(read.value, asked.value),
      (FixedOrderAmount(), RangeOrderAmount()) => true,
      (RangeOrderAmount(), FixedOrderAmount()) => true,
      _ => false,
    };
  }

  /// The contract's amount as asked here, for a trade made here: a range's amount kept with the contract, or the fixed amount of [asked]; `null` for a taker, a range with none kept, or while the amount read does not agree ([contractAmountMoved]), so that no figure is written from a read alone.
  FiatAmount? get contractAmount {
    if (contractAmountMoved) return null;
    final kept = status.trail.takenAmount;
    if (kept != null) return FiatAmount.tryCreate(kept);
    return switch (asked) {
      FixedOrderAmount(:final amount) => amount,
      _ => null,
    };
  }

  /// The contract's amount a screen names and compares for the status shown (#183; the trade screen's and, since #188, a maker seller's escrow confirmation's, one rule for both, security review of #183, C2, C4, functional review of #188, C1): what was asked here ([contractAmount]); `null`, so that no figure is written, while the order read shows another ([contractAmountMoved]: the state machine's alert speaks alone) or none is kept; the order's fixed amount only where nothing asked here is known ([asked] unset: a taker, a status restored without its terms).
  FiatAmount? get contractAmountShown {
    if (contractAmountMoved) return null;
    if (contractAmount case final amount?) return amount;
    return switch ((asked, order?.amount)) {
      (null, FixedOrderAmount(:final amount)) => amount,
      _ => null,
    };
  }

  @override
  String toString() =>
      'TradeSeen($status, read: ${order != null}, stored: $stored)';
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
  /// Its causes are told apart by [stored]: a trail that could not be stored leaves [seen] unmarked, at the trail on disk's own status (no invoice); a failed confirmation or close, and a [TradeClosedFailure], leave [seen] as the read gave it.
  final P2pFailure? recordProblem;

  /// Whether the trade is a take whose answer was lost, and no read has shown yet whether it happened: the reads go on until one shows this robot as the taker, or brings the take to an end ([TradeWatchTakeNotMade]).
  final bool takePending;

  /// What the one read of an end that the screen asks when it opens a trade ended at 5 or 14 (#95, #216) gave, when it did not show that end as this device kept it; `null` when it did, or no such read was made (functional review of #220, C1). [seen] is then the end the records hold, unless the read showed that very end with other terms ([TradeEndShownOtherwise] with the read's status as [seen]).
  final TradeEndReread? endReread;

  const TradeWatchStatus(
    this.record,
    this.seen, {
    this.failedReads = 0,
    this.lastReadFailure,
    this.recordProblem,
    required this.takePending,
    this.endReread,
  });

  /// Whether [seen]'s status is the one this read stored ([TradeSeen.stored]): show an invoice, or offer a payment, only when it is.
  bool get stored => seen.stored;

  @override
  String toString() =>
      'TradeWatchStatus($record, ${seen.status}, stored: $stored, failed: $failedReads, problem: ${recordProblem?.runtimeType}, pending: $takePending, endReread: $endReread)';
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

/// Another subscription to the same trade took it over: the newest subscription reads the trade, this one stops, and its stream ends after this state (a screen that is going away, as the previous route while Flutter builds the next): not an error to show.
///
/// A read of this subscription already in flight is dropped as for a cancel; the writes of an answer already being kept finish (the stored trail stays correct), and the new subscription reads only once they have.
final class TradeWatchSuperseded extends TradeWatchState {
  @override
  final TradeRecord record;

  const TradeWatchSuperseded(this.record);

  @override
  String toString() => 'TradeWatchSuperseded($record)';
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

/// What the one read of an end gave when it did not show that end as this device kept it (#216, functional review of #220, C1): each said in its own words, never one for another.
@immutable
sealed class TradeEndReread {
  const TradeEndReread();
}

/// The one read of the end runs: no answer yet, so the end the records hold is not confirmed (security review of #220, C1): the screen says the order is being read again, never that it is over.
final class TradeEndReading extends TradeEndReread {
  const TradeEndReading();

  @override
  String toString() => 'TradeEndReading';
}

/// No answer to tell from: the coordinator out of reach, a timeout, an error of the transport, an answer that does not parse (`package:robosats` refuses as malformed an order of another number, or one that shows another robot as its maker), or a read held back. The app could not read the order again.
final class TradeEndNotRead extends TradeEndReread {
  const TradeEndNotRead();

  @override
  String toString() => 'TradeEndNotRead';
}

/// The coordinator answered that it does not know the order: error 1042 (`api/views.py:240-242`, with a `404`), or a `404` without a code.
final class TradeEndUnknownToCoordinator extends TradeEndReread {
  const TradeEndUnknownToCoordinator();

  @override
  String toString() => 'TradeEndUnknownToCoordinator';
}

/// The coordinator answered with the order at a status that is not an end (0, 1, 2, 3, 6 to 11, 13, 15, 16): the order may still be under way there, its bond locked, open to a take, while this device's record of it is closed and nothing follows it any more (security review of #220, C1). The screen keeps the end the records hold, never as « over », and says it in the colour of an alert.
final class TradeEndShownAlive extends TradeEndReread {
  const TradeEndShownAlive();

  @override
  String toString() => 'TradeEndShownAlive';
}

/// The coordinator answered otherwise than the end this device kept, at another end: another end status, the order cancelled (1043) or not available to this robot (1044), or that very end with other terms ([asRead]). [warnings] are the state machine's alerts of that answer when the screen keeps showing the end the records hold; empty when the screen shows the answer's own status ([asRead]), which carries them.
final class TradeEndShownOtherwise extends TradeEndReread {
  final List<TradeWarning> warnings;

  /// Whether the status shown is the answer's own, that very end read with other terms, whose panel says its alerts.
  final bool asRead;

  TradeEndShownOtherwise(Iterable<TradeWarning> warnings, {this.asRead = false})
    : warnings = List.unmodifiable(warnings);

  @override
  String toString() => 'TradeEndShownOtherwise($warnings, asRead: $asRead)';
}
