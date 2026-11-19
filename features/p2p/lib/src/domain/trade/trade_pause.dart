import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show CoordinatorOrderStatus;

import '../p2p_failure.dart';
import '../trade_record.dart';
import 'trade_status.dart';
import 'trade_storable.dart';
import 'trade_watch.dart';

/// What the user asked of a public order made here (#184): to pause it (the pause button of `Prompts/PublicWait.tsx`) or to make it public again (« Unpause Order » of `Prompts/Paused.tsx`).
///
/// The reference sends the same request for both (`{"action":"pause"}`, `TradeBox/index.tsx:310-313`), which the coordinator reads as a toggle (`Logics.pause_unpause_public_order`, `api/logics.py:1758-1783`): the direction is never in the request, only here, taken from the status the user saw, so that the answer can be compared with it (design note `docs/design/phase-3-making-an-order.md` § 3.4).
enum PauseWanted {
  /// The user saw the order public (1) and asked to pause it (2).
  paused,

  /// The user saw the order paused (2) and asked to make it public again (1).
  public;

  /// What a tap at [seen] asks: `null` when [seen] offers neither, that is unless it is a maker's public or paused order read from an order at that very status, marked stored ([TradeSeen.stored]), and showing this robot as the maker.
  static PauseWanted? of(TradeSeen seen) {
    final order = seen.order;
    if (order == null || !seen.stored || !order.isMaker) return null;
    return switch ((seen.status, order.status)) {
      (MakerOrderPublic(paused: false), CoordinatorOrderStatus.public) =>
        PauseWanted.paused,
      (MakerOrderPublic(paused: true), CoordinatorOrderStatus.paused) =>
        PauseWanted.public,
      _ => null,
    };
  }

  /// Whether [seen] shows the order where this asks it to be, from a status marked stored: never from a request accepted alone, nor from a status whose trail could not be written.
  bool reachedAt(TradeSeen seen) =>
      seen.stored &&
      switch (seen.status) {
        MakerOrderPublic(:final paused) =>
          paused == (this == PauseWanted.paused),
        _ => false,
      };
}

/// Whether [seen] shows a maker's order public (1), from a status marked stored: one that robots can see and take, the maker's bond at stake if it does not reply in time.
bool showsPublicOrder(TradeSeen seen) =>
    seen.stored &&
    switch (seen.status) {
      MakerOrderPublic(paused: false) => true,
      _ => false,
    };

/// What stays uncertain after a pause or an unpause whose outcome is unknown (#184, security review C1 and C2): the request may have toggled the order, or may still reach the coordinator late and toggle it then, whatever the user asked, a pause or an unpause.
///
/// Until a read sent after the request shows the order paused, it is to be counted as possibly public ([pausedSinceRequest] false); once one does, a request still on its way could make it public again, so a reserve stays until a second read, at least [settleAfter] after the first, still shows it paused. The transport gives no sure bound past which a request sent can no longer reach the coordinator (a request leaves once, `retries = 0` for a `POST`, but bytes already relayed over Tor may arrive after the app gave up at its deadline of 132 s), hence two reads apart rather than a delay: they lower the risk without ruling it out (security review of #184, R-a, #214).
/// A read showing the order public restarts the wait; a read at another status (taken, expired, cancelled) ends it, a toggle being refused there (1033). Reads not marked stored, from no order, or sent before the request count for nothing.
/// The two reads must be [settleAfter] apart on the device's clock (when each was sent, [TradeSeen.requestedAt]) and [settleAfter] plus the transport's deadline for one request apart on a time that only moves forward (when each was taken into account, the `elapsed` of [observe]; `requestDeadline`, the deadline the transport sets, `coordinatorRequestDeadline`, 132 s): a read is taken into account at most that deadline after it was sent, so the second read was sent at least [settleAfter] after the first whatever the device's clock did (security review of #184, R-d, #214; security review of #219, R1: a clock set forward with a slow second answer let two reads sent 48 s apart lift it). A clock set back keeps it longer, the safe side; the device's clock still counts for a read taken into account late (a screen opened again on a read already older), where the time that only moves forward says nothing of when it was sent.
@immutable
final class PauseUncertainty {
  /// How far apart the two reads showing the order paused must be: a choice, past the transport's deadline of 132 s, at the reference's cadence for a paused order (180 s, `TradeCadence`).
  static const Duration settleAfter = Duration(minutes: 3);

  /// When the latest request whose outcome is unknown left.
  final DateTime requestLeftAt;

  /// When the first read sent after it showed the order paused, since the last read that showed it otherwise; `null` while none did.
  final DateTime? pausedReadAt;

  /// When that read was taken into account, on the time that only moves forward given to [observe]; `null` while none was.
  final Duration? pausedObservedAt;

  const PauseUncertainty(
    this.requestLeftAt, {
    this.pausedReadAt,
    this.pausedObservedAt,
  });

  /// Whether a read sent after the request has shown the order paused.
  bool get pausedSinceRequest => pausedReadAt != null;

  /// What is left after [seen], taken into account at [elapsed] on a time that only moves forward (a running `Stopwatch`'s), a request taking at most [requestDeadline] (the transport's): `null` once settled, or once the order is no longer public or paused.
  PauseUncertainty? observe(
    TradeSeen seen, {
    required Duration elapsed,
    required Duration requestDeadline,
  }) {
    final readAt = seen.requestedAt;
    if (!seen.stored || seen.order == null || readAt == null) return this;
    if (!readAt.isAfter(requestLeftAt)) return this;
    return switch (seen.status) {
      MakerOrderPublic(paused: false) => PauseUncertainty(requestLeftAt),
      MakerOrderPublic(paused: true) => switch ((
        pausedReadAt,
        pausedObservedAt,
      )) {
        (final first?, final firstObserved?)
            when readAt.difference(first) >= settleAfter &&
                elapsed - firstObserved >= settleAfter + requestDeadline =>
          null,
        (_?, _?) => this,
        _ => PauseUncertainty(
          requestLeftAt,
          pausedReadAt: readAt,
          pausedObservedAt: elapsed,
        ),
      },
      _ => null,
    };
  }

  /// Another request with an unknown outcome left at [leftAt]: the reads must now follow the later of the two.
  PauseUncertainty after(DateTime leftAt) =>
      PauseUncertainty(leftAt.isAfter(requestLeftAt) ? leftAt : requestLeftAt);

  @override
  String toString() =>
      'PauseUncertainty(pausedSinceRequest: $pausedSinceRequest)';
}

/// Why a pause or an unpause was not sent: a type for each reason, which the screen words, never a coordinator's text.
sealed class PauseRefusal extends Failure {
  const PauseRefusal();

  @override
  String toString() => runtimeType.toString();
}

/// The status seen offers no pause ([PauseWanted.of]): it comes from no order read, is not marked stored, is not a maker's public or paused order, or the trade was not made here.
final class PauseNotOffered extends PauseRefusal {
  const PauseNotOffered();
}

/// The order seen is not the trade's.
final class PauseOfAnotherTrade extends PauseRefusal {
  const PauseOfAnotherTrade();
}

/// The trade cannot be opened: [failure] says why (the records cannot be read, the key is missing, the binding refuses the coordinator).
final class PauseTradeUnavailable extends PauseRefusal {
  final P2pFailure failure;

  const PauseTradeUnavailable(this.failure);

  @override
  String toString() => 'PauseTradeUnavailable(${failure.runtimeType})';
}

/// The trade's stored records cannot be restored: it is shown read-only, and nothing is sent.
final class PauseTradeUnrestorable extends PauseRefusal {
  final TradeRecordRefusal reason;

  const PauseTradeUnrestorable(this.reason);

  @override
  String toString() => 'PauseTradeUnrestorable(${reason.runtimeType})';
}

/// The order could not be read just before the request, or that read could not be stored: nothing was sent. [cause] is the read's failure or the write's; [seen] the trade as it then stands, when a read was kept.
final class PauseReadFailed extends PauseRefusal {
  final Failure? cause;
  final TradeSeen? seen;

  /// The trade's record as the read left it, when a read was kept: an end closes it.
  final TradeRecord? record;

  const PauseReadFailed({this.cause, this.seen, this.record});

  @override
  String toString() => 'PauseReadFailed(${cause.runtimeType})';
}

/// The order read just before the request no longer shows the status the user saw (paused or unpaused from another app, taken, expired, cancelled): nothing was sent, since the toggle would have gone the other way; [seen] is the status now.
final class PauseStatusMoved extends PauseRefusal {
  final TradeSeen seen;

  /// The trade's record as the read left it: an end closes it.
  final TradeRecord? record;

  const PauseStatusMoved(this.seen, {this.record});

  @override
  String toString() => 'PauseStatusMoved(${seen.status})';
}

/// What a pause or an unpause sent gave, with the trade as the read after it shows it.
@immutable
sealed class PauseOutcome {
  /// What the user asked.
  PauseWanted get wanted;

  /// The trade's record as stored once the request's writes are over.
  TradeRecord get record;

  /// The status after the request and the read that followed it, as stored (or the trail on disk's own): never one made up, never the direction asked.
  TradeSeen get seen;

  /// A write that failed after the coordinator answered.
  P2pFailure? get recordProblem;

  const PauseOutcome();
}

/// The order is read where the user asked ([PauseWanted.reachedAt]), from a status marked stored.
final class PauseDone extends PauseOutcome {
  @override
  final PauseWanted wanted;
  @override
  final TradeRecord record;
  @override
  final TradeSeen seen;
  @override
  final P2pFailure? recordProblem;

  const PauseDone(this.wanted, this.record, this.seen, {this.recordProblem});

  @override
  String toString() => 'PauseDone(${wanted.name}, ${seen.status})';
}

/// The coordinator answered the request as done, but the order is not read where the user asked: toggled the other way or twice (the same robot paused or resumed it from another client meanwhile), taken, expired, or a coordinator that answers falsely. [seen] is the status shown: when the user asked to pause and [seen] is public, the order can be taken.
final class PauseNotReached extends PauseOutcome {
  @override
  final PauseWanted wanted;
  @override
  final TradeRecord record;
  @override
  final TradeSeen seen;
  @override
  final P2pFailure? recordProblem;

  const PauseNotReached(
    this.wanted,
    this.record,
    this.seen, {
    this.recordProblem,
  });

  @override
  String toString() => 'PauseNotReached(${wanted.name}, ${seen.status})';
}

/// Nothing was done: the coordinator refused before acting (1032, 1033, 1047, the empty `400` of its form check, the authentication's), or the request never left (a busy transport, the robot released); [cause] says which.
final class PauseNotDone extends PauseOutcome {
  @override
  final PauseWanted wanted;
  @override
  final TradeRecord record;
  @override
  final TradeSeen seen;
  @override
  final P2pFailure? recordProblem;
  final Failure cause;

  const PauseNotDone(
    this.wanted,
    this.record,
    this.seen, {
    required this.cause,
    this.recordProblem,
  });

  @override
  String toString() => 'PauseNotDone(${wanted.name}, ${cause.runtimeType})';
}

/// The request may have arrived: its answer was lost or unreadable, and the read after it does not show the order where the user asked. Never sent again by itself: the watch of the trade tells the rest, and only a new tap of the user may send again, after a fresh read.
final class PauseOutcomeUnknown extends PauseOutcome {
  @override
  final PauseWanted wanted;
  @override
  final TradeRecord record;
  @override
  final TradeSeen seen;
  @override
  final P2pFailure? recordProblem;

  /// When the request left this device, as far as known: reads sent after it are the only ones that say where it left the order ([PauseUncertainty]).
  final DateTime? requestLeftAt;

  const PauseOutcomeUnknown(
    this.wanted,
    this.record,
    this.seen, {
    this.recordProblem,
    this.requestLeftAt,
  });

  @override
  String toString() => 'PauseOutcomeUnknown(${wanted.name}, ${seen.status})';
}
