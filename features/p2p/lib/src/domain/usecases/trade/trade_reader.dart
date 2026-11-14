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
import '../../trade/trade_tolerances.dart';
import '../../trade/trade_watch.dart';
import '../../trade_record.dart';
import '../../trade_robots.dart';

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

/// A pending take with no terms recorded: its request never left.
final class TradeTakeNeverSent extends TradeOpening {
  /// Its robot and coordinator, for the read that tells it may be closed.
  final NetworkRobot robot;
  final Coordinator coordinator;

  const TradeTakeNeverSent(this.robot, this.coordinator);
}

/// One step of a trade after an answer: the trade as it now stands, and what could not be written.
@immutable
final class TradeStep {
  final OpenTrade trade;

  /// A write that failed (the trail, the confirmation, the close), or [TradeClosedFailure] from a confirmation of a closed record.
  final P2pFailure? recordProblem;

  /// Whether the answer was held: a pending take that a read shows is not this robot's before the time to lock the taker bond is over, so nothing was written.
  final bool held;

  const TradeStep(this.trade, {this.recordProblem, this.held = false});
}

/// What the trade use cases share: opening a recorded trade from its stored terms and trail, reading its order through the robot's places, and keeping what each answer gives (#87).
///
/// It writes the trail only through [TradeTrailRepository.storeTrail], which asks [TradeTrailRecord.whyNotReplace] first; it confirms a record only when an answer shows the robot as the taker, and closes it only at a terminal status whose trail is stored, a pending take only once the time to lock the taker bond is over.
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

  const TradeReader(
    this._robots,
    this._records,
    this._trails,
    this._bindings,
    this._client,
    this._federation,
    this._invoices, {
    required this._clock,
  });

  /// How long after a take a pending take may still turn into a pre-take: the longest pre-take and the coordinator's loops (`TradeTolerances`).
  static const Duration pendingTakeWindow = Duration(minutes: 31);

  DateTime now() => _clock().toUtc();

  /// Whether a pending take of [record] may still turn into a pre-take at [at].
  static bool mayStillBeTaken(TradeRecord record, DateTime at) =>
      record.isPendingTake &&
      at.isBefore(
        record.takenAt
            .add(TradeTolerances.longestPreTake)
            .add(TradeTolerances.coordinatorLoops),
      );

  /// [record] opened from what is stored: its terms restored ([TradeTerms.restore]), its trail restored ([TradeTrail.restore]) or, for a pending take with none (the app killed between the writes of the take, before its request), the trail of a pending take; a recovered trade without a trail starts on [TradeTrail.recovered]; any other trade without a trail is refused, never restarted on a fresh trail.
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
    if (termsRecord == null) {
      if (!record.isPendingTake) {
        return const TradeNotRestorable(TradeRecordMalformed());
      }
      switch (await _robotAndCoordinator(record)) {
        case Ok(value: (final robot, final coordinator)):
          return TradeTakeNeverSent(robot, coordinator);
        case Err(:final failure):
          return TradeNotOpened(failure);
      }
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
    } else if (record.isPendingTake) {
      // The take sends its request only once this trail is written: none means it never left, and only a take's answers may come first.
      trail = TradeTrail.forPendingTake(terms, record.takenAt);
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

  /// One read of the order of [trade] (or of the never-sent take of [robot] on [coordinator]) through [requests], the robot's places in [RobotRequestLimiter]: a busy answer is sent again as the limiter says.
  Future<Result<Result<CoordinatorOrder, CoordinatorFailure>, P2pFailure>>
  readOrder(
    RobotRequests requests,
    TradeRecord record,
    NetworkRobot robot,
    Coordinator coordinator,
  ) => requests.send(
    record.network,
    coordinator,
    () => _client.fetchOrder(
      coordinator,
      record.network,
      identity: robot.identity,
      orderId: record.orderId,
    ),
    isBusy: answeredBusy,
  );

  /// Whether a read was answered busy by the transport: nothing reached the coordinator.
  static bool answeredBusy(Result<Object?, CoordinatorFailure> answer) =>
      switch (answer) {
        Err(failure: CoordinatorTransportBusy()) => true,
        _ => false,
      };

  /// [trade] after [answer], read at [at]: its status from `TradeStatus.from`, then kept as [keep] keeps it; a pending take that the answer does not show as this robot's, at a terminal status, is held while it may still turn into a pre-take.
  Future<TradeStep> advance(
    OpenTrade trade,
    TradeAnswer answer, {
    required DateTime at,
  }) {
    final status = TradeStatus.from(
      previous: trade.seen.status,
      answer: answer,
      terms: trade.terms,
      now: at,
      reader: _invoices,
    );
    final taker = showsTaker(answer, trade.terms);
    if (status.isTerminal && !taker && mayStillBeTaken(trade.record, at)) {
      return Future.value(TradeStep(trade, held: true));
    }
    // The order of the answer, when the status comes from it: an answer refused as a whole leaves the last status, whose order is no longer known.
    final order = switch (answer) {
      TradeOrderRead(:final order) when status.seenAt == at => order,
      _ => null,
    };
    return keep(trade, TradeSeen(status, order: order), showsTaker: taker);
  }

  /// [trade] at [seen]: its trail stored over the stored one (a trail kept instead wins, and the trade goes on from it), its record confirmed when [showsTaker], and closed at a terminal status whose trail is stored.
  Future<TradeStep> keep(
    OpenTrade trade,
    TradeSeen seen, {
    required bool showsTaker,
  }) async {
    var record = trade.record;
    var current = seen;
    P2pFailure? problem;
    var stored = false;
    switch (await _trails.storeTrail(record, seen.status.trail.record)) {
      case Ok(value: TrailStored()):
        stored = true;
      case Ok(value: TrailKept(stored: final kept)):
        // An earlier read that ended late, or a trail another call stored first: the stored trail wins, and the status shown is the one it gives.
        switch (TradeTrail.restore(kept, terms: trade.terms, now: now())) {
          case Ok(:final value):
            current = TradeSeen(
              TradeStatus.beforeFirstRead(value),
              order: null,
            );
            stored = true;
          case Err():
            problem = const P2pStorageFailure();
        }
      case Err(:final failure):
        problem = failure;
    }
    if (showsTaker && record.confirmedAt == null) {
      switch (await _records.confirmTake(record)) {
        case Ok(:final value):
          record = value;
        case Err(:final failure):
          problem ??= failure;
      }
    }
    if (stored && current.status.isTerminal && record.isActive) {
      switch (await _records.closeTrade(record)) {
        case Ok(:final value):
          record = value;
        case Err(:final failure):
          problem ??= failure;
      }
    }
    return TradeStep(
      trade._with(record: record, seen: current),
      recordProblem: problem,
    );
  }

  /// Closes [record] at an end its stored trail already holds (the app was killed between the trail and the close).
  Future<Result<TradeRecord, P2pFailure>> closeAtEnd(TradeRecord record) =>
      _records.closeTrade(record);

  /// Closes the pending take [record] whose request never left, once the time to lock a taker bond is over and [read] shows the robot is not the order's taker.
  ///
  /// `null` while it may not be closed yet, or while the read says nothing.
  Future<Result<TradeRecord, P2pFailure>?> closeNeverSent(
    TradeRecord record,
    Result<CoordinatorOrder, CoordinatorFailure> read, {
    required DateTime at,
  }) async {
    if (mayStillBeTaken(record, at)) return null;
    final notTaker = switch (TradeAnswer.ofRead(read)) {
      TradeOrderRead(:final order) => !order.isTaker,
      TradeOrderCancelled() || TradeOrderNotAvailable() => true,
      null => false,
    };
    if (!notTaker) return null;
    return _records.closeTrade(record);
  }

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
