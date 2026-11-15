import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../network_garage_key.dart';
import '../../p2p_failure.dart';
import '../../repositories/robot_binding_repository.dart';
import '../../repositories/trade_record_repository.dart';
import '../../repositories/trade_trail_repository.dart';
import '../../robot_binding.dart';
import '../../robot_request_limiter.dart';
import '../../trade/bolt11.dart';
import '../../trade/trade_answer.dart';
import '../../trade/trade_edges.dart';
import '../../trade/trade_status.dart';
import '../../trade/trade_storable.dart';
import '../../trade/trade_terms.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import '../../trade_robots.dart';
import 'trade_read_order.dart';

/// A recorded trade opened for reading: its record, its robot, its coordinator, its terms and the last status seen.
@immutable
final class OpenTrade {
  final TradeRecord record;

  /// The robot of the record, derived again from the Garage Key of its network: keep it no longer than the use case's call.
  final NetworkRobot robot;

  /// The coordinator of the record, from the federation list, admitted by the robot's binding.
  final Coordinator coordinator;
  final TradeTerms terms;
  final TradeSeen seen;

  const OpenTrade({
    required this.record,
    required this.robot,
    required this.coordinator,
    required this.terms,
    required this.seen,
  });

  OpenTrade _with({TradeRecord? record, TradeSeen? seen}) => OpenTrade(
    record: record ?? this.record,
    robot: robot,
    coordinator: coordinator,
    terms: terms,
    seen: seen ?? this.seen,
  );

  @override
  String toString() => 'OpenTrade($record, ${seen.status})';
}

/// What opening a recorded trade gave.
@immutable
sealed class TradeOpening {
  const TradeOpening();
}

final class TradeOpened extends TradeOpening {
  final OpenTrade trade;

  const TradeOpened(this.trade);
}

/// The stored terms or trail cannot be restored: the trade is shown read-only, never resumed.
final class TradeNotRestorable extends TradeOpening {
  final TradeRecordRefusal reason;

  const TradeNotRestorable(this.reason);
}

/// The trade cannot be opened: the records cannot be read, the key is missing, the binding refuses the coordinator.
final class TradeNotOpened extends TradeOpening {
  final P2pFailure failure;

  const TradeNotOpened(this.failure);
}

/// A pending take whose terms or first trail were never written: the take sends its request only once both are, so it never left, and the record may be closed at once.
final class TradeTakeNeverSent extends TradeOpening {
  const TradeTakeNeverSent();
}

/// One step of a trade after an answer: the trade as it now stands, and what could not be written.
@immutable
final class TradeStep {
  final OpenTrade trade;

  /// A write that failed (the trail, the confirmation, the close), or [TradeClosedFailure] from a confirmation of a closed record.
  final P2pFailure? recordProblem;

  /// Whether [trade]'s status is the one this step stored ([TradeSeen.stored]): only such a status may show an invoice or offer a payment.
  final bool stored;

  /// Whether the step ended a take this robot never held: a pending take, never confirmed, on which no pre-take (so no invoice) was ever seen, now at an end; it is closed as a take not made, whatever the end says of a bond (none can have been paid from here).
  final bool takeNotMade;

  /// Whether the answer was superseded ([TradeReadOrder.claim]): nothing was written, [trade] stands at the newest status stored in this process, and [stored] is false, since this step stored nothing (#141). Not a failed write: [recordProblem] stays `null`.
  final bool superseded;

  const TradeStep(
    this.trade, {
    this.recordProblem,
    required this.stored,
    this.takeNotMade = false,
    this.superseded = false,
  });
}

/// What the trade use cases share: opening a recorded trade from its stored terms and trail, reading its order through the robot's places, and keeping what each answer gives (#87).
///
/// It writes the trail only through [TradeTrailRepository.storeTrail], which asks [TradeTrailRecord.whyNotReplace] first; it never returns a status computed from a trail that was not stored, but the stored trail's own; it confirms a record only when an answer shows the robot as the taker, and closes it only at a terminal status whose trail is stored.
/// Only the trade use cases and the composition name it (`robot_bindings_architecture_test.dart`): its members write trails and close records.
/// The network and the coordinator of every call come from the record, checked against the robot's binding; nothing here moves money.
final class TradeReader {
  final TradeRobots _robots;
  final TradeRecordRepository _records;
  final TradeTrailRepository _trails;
  final RobotBindingRepository _bindings;
  final CoordinatorClient _client;
  final Federation _federation;
  final Bolt11Reader _invoices;
  final DateTime Function() _clock;
  final TradeReadOrder _requestOrder;

  const TradeReader(
    this._robots,
    this._records,
    this._trails,
    this._bindings,
    this._client,
    this._federation,
    this._invoices, {
    required this._clock,
    required this._requestOrder,
  });

  DateTime now() => _clock().toUtc();

  /// The times of a new request that gives a status of a trade (a read, or an action whose answer is kept): filled when it is sent, through [readOrder] or [timed], and given to [advance] or [keep] with its answer.
  RequestTimes request() => _requestOrder.request();

  /// [call], an action's request, sent now from the closure handed to the request limiter: ranked in [times] at each attempt, when it leaves and when its answer arrives ([TradeReadOrder.send]).
  Future<T> timed<T>(RequestTimes times, Future<T> Function() call) =>
      _requestOrder.send(times, now(), call);

  /// [body], an action of [record]'s trade (its take, payout, bond payment, cancel or chat step, each under the order's lock): while it runs, the watch sends no read of the trade ([readOrder] with `watch`).
  Future<T> duringAction<T>(TradeRecord record, Future<T> Function() body) =>
      _requestOrder.duringAction(record.robot, body);

  /// Completes once no action of [record]'s trade runs.
  Future<void> actionEnded(TradeRecord record) =>
      _requestOrder.actionEnded(record.robot);

  /// [record] opened from what is stored: its terms restored ([TradeTerms.restore]) and its trail restored ([TradeTrail.restore]); a pending take without its terms or its first trail never sent its request ([TradeTakeNeverSent]); a recovered trade without a trail starts on [TradeTrail.recovered]; any other trade without a trail is refused, never restarted on a fresh trail.
  Future<TradeOpening> open(TradeRecord record) async {
    final StoredTradeHistory history;
    switch (await _trails.historyOf(record)) {
      case Ok(:final value):
        history = value;
      case Err(:final failure):
        return TradeNotOpened(failure);
    }
    if (history.unreadable) {
      return const TradeNotRestorable(TradeRecordMalformed());
    }
    final termsRecord = history.terms;
    // The take sends its request only once its terms and its first trail are written.
    if (record.isPendingTake &&
        (termsRecord == null || history.trail == null)) {
      return const TradeTakeNeverSent();
    }
    if (termsRecord == null) {
      return const TradeNotRestorable(TradeRecordMalformed());
    }
    final TradeTerms terms;
    switch (TradeTerms.restore(termsRecord)) {
      case Ok(:final value):
        terms = value;
      case Err(:final failure):
        return TradeNotRestorable(failure);
    }
    if (terms.network != record.network ||
        terms.coordinator.shortAlias != record.coordinatorAlias ||
        terms.orderId != record.orderId ||
        terms.role != record.role) {
      return const TradeNotRestorable(TradeRecordOfAnotherTrade());
    }
    final TradeTrail trail;
    final storedTrail = history.trail;
    if (storedTrail != null) {
      switch (TradeTrail.restore(storedTrail, terms: terms, now: now())) {
        case Ok(:final value):
          trail = value;
        case Err(:final failure):
          return TradeNotRestorable(failure);
      }
    } else if (record.origin == TradeOrigin.recovered) {
      trail = TradeTrail.recovered(terms, now());
    } else {
      return const TradeNotRestorable(TradeRecordMalformed());
    }
    switch (await _robotAndCoordinator(record)) {
      case Ok(value: (final robot, final coordinator)):
        return TradeOpened(
          OpenTrade(
            record: record,
            robot: robot,
            coordinator: coordinator,
            terms: terms,
            seen: TradeSeen(TradeStatus.beforeFirstRead(trail), order: null),
          ),
        );
      case Err(:final failure):
        return TradeNotOpened(failure);
    }
  }

  /// The robot of [record] and its coordinator, admitted by the robot's binding: the coordinator of the list under the record's alias, on the record's network, at the record's onion address.
  Future<Result<(NetworkRobot, Coordinator), P2pFailure>> _robotAndCoordinator(
    TradeRecord record,
  ) async {
    final coordinator = _federation.byAlias(record.coordinatorAlias);
    final identity = coordinator == null
        ? null
        : CoordinatorIdentity.of(coordinator, record.network);
    if (coordinator == null ||
        identity == null ||
        identity.onion != record.coordinatorOnion) {
      return const Err(RobotCoordinatorChangedFailure());
    }
    final NetworkRobot robot;
    switch (await _robots.robotOfTrade(record)) {
      case Ok(:final value):
        robot = value;
      case Err(:final failure):
        return Err(failure);
    }
    switch (await _bindings.standingOf(robot.slot)) {
      case Ok(value: RobotStanding(binding: final binding?)):
        if (binding.admits(identity) case Err(:final failure)) {
          return Err(failure);
        }
      case Ok():
        return const Err(RobotNotBoundFailure());
      case Err(:final failure):
        return Err(failure);
    }
    return Ok((robot, coordinator));
  }

  /// One read of the order of the trade of [record], by [robot] on [coordinator], through [requests], the robot's places in [RobotRequestLimiter]: a busy answer is sent again as the limiter says. [times] is filled at each attempt ([timed]).
  ///
  /// With [watch], the read is not sent while an action of the trade runs: checked inside the closure the limiter runs, once a place is held, at each attempt; [RequestTimes.heldBack] then says so, and the answer is no read of the order.
  Future<Result<Result<CoordinatorOrder, CoordinatorFailure>, P2pFailure>>
  readOrder(
    RobotRequests requests,
    TradeRecord record,
    NetworkRobot robot,
    Coordinator coordinator, {
    required RequestTimes times,
    bool watch = false,
  }) => requests.send(
    record.network,
    coordinator,
    () {
      if (watch && _requestOrder.actionRunning(record.robot)) {
        _requestOrder.heldBack(times);
        return Future.value(const Err(CoordinatorTransportBusy()));
      }
      return timed(
        times,
        () => _client.fetchOrder(
          coordinator,
          record.network,
          identity: robot.identity,
          orderId: record.orderId,
        ),
      );
    },
    isBusy: (answer) => !times.heldBack && answeredBusy(answer),
  );

  /// One read of order [orderId] of [coordinator] on [network], by [robot], through [requests]: the read of a take being prepared, which has no record yet (#119); a busy answer is sent again as the limiter says.
  Future<Result<Result<CoordinatorOrder, CoordinatorFailure>, P2pFailure>>
  readOrderOf(
    RobotRequests requests,
    RobosatsNetwork network,
    int orderId,
    NetworkRobot robot,
    Coordinator coordinator,
  ) => requests.send(
    network,
    coordinator,
    () => _client.fetchOrder(
      coordinator,
      network,
      identity: robot.identity,
      orderId: orderId,
    ),
    isBusy: answeredBusy,
  );

  /// Whether a read was answered busy by the transport: nothing reached the coordinator.
  static bool answeredBusy(Result<Object?, CoordinatorFailure> answer) =>
      switch (answer) {
        Err(failure: CoordinatorTransportBusy()) => true,
        _ => false,
      };

  /// [trade] after [answer], read at [at]: its status from `TradeStatus.from` over the last status, then kept as [keep] keeps it.
  ///
  /// A pending take never confirmed, on which no pre-take was ever seen, that the answer brings to an end without showing this robot as the taker, is a take not made ([TradeStep.takeNotMade]): the coordinator never showed this robot an invoice, so nothing can have been paid from here, whatever the end says of a bond.
  /// Such an end comes at once when the order is public again with this robot no participant (the coordinator shows a live pre-take to its robot as 3, `api/views.py:381-396`, so this robot holds none), cancelled or expired; error 1044 stays `PreTakeUnavailable` until the pre-take is certainly gone (`TradeStatus.from`).
  ///
  /// [request] holds when the request [answer] answers left and when its answer arrived ([readOrder], [timed]): what orders it against the other answers of the trade ([keep]). With [keepsTime], the status keeps the time it left ([TradeSeen.requestedAt]), as the watch's reads and the payout's do since #132; the other answers keep none, as before, which the payout panel reads as not after its payout.
  Future<TradeStep> advance(
    OpenTrade trade,
    TradeAnswer answer, {
    required DateTime at,
    required RequestTimes request,
    bool keepsTime = false,
  }) async {
    // A terminal status is never left, and its trail and record are kept already: nothing to write.
    if (trade.seen.status.isTerminal) {
      return TradeStep(trade, stored: trade.seen.stored);
    }
    final taker = showsTaker(answer, trade.terms);
    final step = await keep(
      trade,
      _seenAfter(
        trade.seen.status,
        answer,
        trade.terms,
        at,
        requestedAt: keepsTime ? request.leftAt : null,
      ),
      showsTaker: taker,
      answer: answer,
      at: at,
      request: request,
    );
    // From the trail now on disk (stored or kept), never from one only in memory.
    final notMade =
        !taker &&
        trade.record.confirmedAt == null &&
        trade.record.origin == TradeOrigin.takenHere &&
        step.trade.seen.status.trail.bondStepSeenAt == null &&
        step.trade.seen.status.isTerminal;
    if (!notMade || step.superseded) return step;
    return TradeStep(
      step.trade,
      recordProblem: step.recordProblem,
      stored: step.stored,
      takeNotMade: true,
    );
  }

  /// The status after [answer] read at [at], from [previous], with the order it was read from when the status comes from it (an answer refused as a whole leaves the last status, whose order is no longer known).
  TradeSeen _seenAfter(
    TradeStatus previous,
    TradeAnswer answer,
    TradeTerms terms,
    DateTime at, {
    DateTime? requestedAt,
  }) {
    final status = TradeStatus.from(
      previous: previous,
      answer: answer,
      terms: terms,
      now: at,
      reader: _invoices,
    );
    return TradeSeen(
      status,
      order: switch (answer) {
        TradeOrderRead(:final order) when status.seenAt == at => order,
        _ => null,
      },
      requestedAt: status.seenAt == at ? requestedAt : null,
    );
  }

  /// [trade] at [seen]: its trail stored over the stored one, its record confirmed when [showsTaker], and closed at a terminal status whose trail is on disk.
  ///
  /// [trade]'s own status must come from the trail on disk (as every status [TradeReader] gives).
  /// - Stored: the trade goes on at [seen], marked [TradeSeen.stored].
  /// - Not stored (the database refused the write): the status is the trail on disk's own (`TradeStatus.beforeFirstRead`, no invoice, no order), never [seen], whose invoice and pinned hash are on no disk, nor the last status shown, whose invoice may be stale (review of #117); [TradeStep.recordProblem] says why.
  /// - Kept (the stored trail changed, or was refused over): when [answer] read at [at] is newer than the stored trail, [answer] is read again over the stored trail and stored, once; at an end the stored trail already holds, [seen] stays, unmarked (an end holds no invoice, and says what the end means); otherwise the status is the stored trail's own.
  /// Only a status marked [TradeSeen.stored] may show an invoice or offer a payment.
  ///
  /// [request] holds the ranks of the request [seen] comes from, when it left and when its answer arrived. Its answer replaces the stored status only if it left after the answer of the newest status accepted for the trade in this process arrived ([TradeReadOrder.claim], claimed here before anything is awaited, #141). Otherwise it is superseded: nothing is written, and the trade stands at that newest status with its record (or at [trade] while none was stored in this process), the step marked [TradeStep.superseded] and not [TradeStep.stored], so that no use case acts on it as its own read.
  Future<TradeStep> keep(
    OpenTrade trade,
    TradeSeen seen, {
    required bool showsTaker,
    required RequestTimes request,
    TradeAnswer? answer,
    DateTime? at,
  }) async {
    if (_requestOrder.claim(trade.record.robot, request) case final newer?) {
      final newerRecord = newer.record;
      return TradeStep(
        trade._with(
          record:
              newerRecord != null && _furtherOn(newerRecord, than: trade.record)
              ? newerRecord
              : trade.record,
          seen: newer.seen ?? trade.seen,
        ),
        stored: false,
        superseded: true,
      );
    }
    var record = trade.record;
    // The trail last known on disk, and its own status: what stays when nothing is stored.
    var onDiskTrail = trade.seen.status.trail;
    TradeSeen ownStatus(TradeTrail trail) =>
        TradeSeen(TradeStatus.beforeFirstRead(trail), order: null);
    var current = ownStatus(onDiskTrail);
    var attempt = seen;
    P2pFailure? problem;
    var onDisk = false;
    for (var round = 0; round < 2; round++) {
      switch (await _trails.storeTrail(record, attempt.status.trail.record)) {
        case Ok(value: TrailStored()):
          current = TradeSeen(
            attempt.status,
            order: attempt.order,
            stored: true,
            requestedAt: attempt.requestedAt,
          );
          onDisk = true;
        case Err(:final failure):
          problem = failure;
          current = ownStatus(onDiskTrail);
        case Ok(value: TrailKept(stored: final kept)):
          final restored = TradeTrail.restore(
            kept,
            terms: trade.terms,
            now: now(),
          );
          if (restored case Ok(value: final keptTrail)) {
            onDisk = true;
            onDiskTrail = keptTrail;
            if (attempt.status.isTerminal &&
                keptTrail.position == attempt.status.position) {
              current = TradeSeen(
                attempt.status,
                order: attempt.order,
                requestedAt: attempt.requestedAt,
              );
            } else if (round == 0 &&
                answer != null &&
                at != null &&
                kept.readAtMicros < at.toUtc().microsecondsSinceEpoch) {
              // A newer read that lost to an older write: a normal step from the stored trail.
              attempt = _seenAfter(
                TradeStatus.beforeFirstRead(keptTrail),
                answer,
                trade.terms,
                at,
                requestedAt: seen.requestedAt,
              );
              current = ownStatus(keptTrail);
              continue;
            } else {
              current = ownStatus(keptTrail);
            }
          } else {
            problem = const P2pStorageFailure();
            current = ownStatus(onDiskTrail);
          }
      }
      break;
    }
    if (showsTaker && record.confirmedAt == null) {
      switch (await _records.confirmTake(record)) {
        case Ok(:final value):
          record = value;
        case Err(:final failure):
          problem ??= failure;
      }
    }
    if (onDisk && current.status.isTerminal && record.isActive) {
      switch (await _records.closeTrade(record)) {
        case Ok(:final value):
          record = value;
        case Err(:final failure):
          problem ??= failure;
      }
    }
    _requestOrder.noted(record);
    if (current.stored) _requestOrder.stored(record, current);
    return TradeStep(
      trade._with(record: record, seen: current),
      recordProblem: problem,
      stored: current.stored,
    );
  }

  /// Whether [record] is further on than [than]: confirmed where it was not, or closed where it was not.
  static bool _furtherOn(TradeRecord record, {required TradeRecord than}) =>
      (record.closedAt != null && than.closedAt == null) ||
      (record.confirmedAt != null && than.confirmedAt == null);

  /// Closes [record] at an end its stored trail already holds (the app was killed between the trail and the close).
  Future<Result<TradeRecord, P2pFailure>> closeAtEnd(TradeRecord record) =>
      _records.closeTrade(record);

  /// Closes the pending take [record] whose request never left ([TradeTakeNeverSent]): at once, since no coordinator can hold a pre-take of it.
  Future<Result<TradeRecord, P2pFailure>> closeNeverSent(TradeRecord record) =>
      _records.closeTrade(record);

  /// Whether [answer] shows this robot as the taker of the trade of [terms]: an order of that coordinator, network and number, this robot its taker and not its maker (the package has checked it was read by this robot).
  static bool showsTaker(TradeAnswer answer, TradeTerms terms) =>
      switch (answer) {
        TradeOrderRead(:final order) =>
          order.isTaker &&
              !order.isMaker &&
              order.coordinator == terms.coordinator &&
              order.network == terms.network &&
              order.id == terms.orderId,
        _ => false,
      };

  /// The position of [seen], for the cadence.
  static TradePosition positionOf(TradeSeen seen) => seen.status.position;
}
