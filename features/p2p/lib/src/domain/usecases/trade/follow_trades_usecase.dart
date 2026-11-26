import 'dart:async';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../../garage_key_fingerprint.dart';
import '../../garage_opening.dart';
import '../../network_garage_key.dart';
import '../../next_trade_robot.dart';
import '../../order_history.dart';
import '../../p2p_failure.dart';
import '../../trade/active_trade.dart';
import '../../trade_record.dart';

/// `ListActiveTradesUsecase.execute`, the device's trades not closed with where their stored trail says they stand, which the locator gives the use case.
typedef ActiveTradesOf =
    Stream<Result<List<ActiveTrade>, P2pFailure>> Function(
      RobosatsNetwork network,
    );

/// `TradeRecordRepository.watchClosedTrades`, the closed records with the last position of their trail, which the locator gives the use case.
typedef ClosedTradesOf =
    Stream<Result<List<ClosedTrade>, P2pFailure>> Function(
      RobosatsNetwork network,
    );

/// `TradeRecordRepository.newTradeStandingOf`, what a new trade may use of a key, which the locator gives the use case.
typedef NewTradeStandingOf =
    Future<Result<NewTradeStanding, P2pFailure>> Function(
      RobosatsNetwork network,
      GarageKeyFingerprint key,
    );

/// The records the Garage shows its robot from (#227, #251, design note `docs/design/phase-3-fresh-robot.md` § 4.1): the trades in progress, the finished ones with how their trail stopped, and the robot the next trade of the key would reserve, again after each write of the records or the trails. Read from the device only, nothing sent, nothing written.
///
/// What the Garage makes of them is [GarageOpening] and [GarageNavigation]'s; the take reads them once, before its reservation, for the line of the order page (§ 4.2), and never takes its robot from them.
/// A trade counts as in progress while its record is not closed (`ListActiveTradesUsecase`, over `TradeRecordRepository.watchActiveTrades`), the very complement of the closed records the « Last order #N » line may show (review of #229, C3).
final class FollowTradesUsecase {
  final ActiveTradesOf _activeTrades;
  final ClosedTradesOf _closedTrades;
  final NewTradeStandingOf _standing;

  const FollowTradesUsecase(
    this._activeTrades,
    this._closedTrades,
    this._standing,
  );

  /// The records of [key]'s network for the Garage of [key]: a first value once both lists were read, then one after each new list, in order; a database that cannot be read, or a key that gives no fingerprint, gives a failure in place of the records.
  ///
  /// Cancelling it cancels the watches of the records at once.
  Stream<Result<GarageRecords, P2pFailure>> execute(NetworkGarageKey key) {
    Result<List<ActiveTrade>, P2pFailure>? active;
    Result<List<ClosedTrade>, P2pFailure>? closed;
    StreamSubscription<Result<List<ActiveTrade>, P2pFailure>>? activeSub;
    StreamSubscription<Result<List<ClosedTrade>, P2pFailure>>? closedSub;
    late final StreamController<Result<GarageRecords, P2pFailure>> out;
    // Each read of the standing waits for the one before it, so that the records come out in the order of the lists.
    var chain = Future<void>.value();
    var cancelled = false;

    void changed() {
      final (a, c) = (active, closed);
      if (a == null || c == null) return;
      chain = chain.then((_) async {
        if (cancelled) return;
        final records = await _recordsOf(key, a, c);
        if (!cancelled) out.add(records);
      });
    }

    void failed(Object error, StackTrace stackTrace) {
      if (cancelled) return;
      if (error is Exception) {
        out.add(const Err(P2pStorageFailure()));
      } else {
        out.addError(error, stackTrace);
      }
    }

    out = StreamController(
      onListen: () {
        activeSub = _activeTrades(key.network).listen((value) {
          active = value;
          changed();
        }, onError: failed);
        closedSub = _closedTrades(key.network).listen((value) {
          closed = value;
          changed();
        }, onError: failed);
      },
      onCancel: () async {
        cancelled = true;
        await activeSub?.cancel();
        await closedSub?.cancel();
      },
    );
    return out.stream;
  }

  /// The records of [key] from the lists [active] and [closed], with what a new trade may use of [key] read now.
  Future<Result<GarageRecords, P2pFailure>> _recordsOf(
    NetworkGarageKey key,
    Result<List<ActiveTrade>, P2pFailure> active,
    Result<List<ClosedTrade>, P2pFailure> closed,
  ) async {
    final List<ActiveTrade> inProgress;
    switch (active) {
      case Ok(:final value):
        inProgress = value;
      case Err(:final failure):
        return Err(failure);
    }
    final List<ClosedTrade> finished;
    switch (closed) {
      case Ok(:final value):
        finished = value;
      case Err(:final failure):
        return Err(failure);
    }
    final GarageKeyFingerprint fingerprint;
    switch (key.fingerprint) {
      case Ok(:final value):
        fingerprint = value;
      case Err(:final failure):
        return Err(failure);
    }
    final NewTradeStanding standing;
    try {
      switch (await _standing(key.network, fingerprint)) {
        case Ok(:final value):
          standing = value;
        case Err(:final failure):
          return Err(failure);
      }
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    return Ok(
      GarageRecords(
        inProgress: inProgress,
        closed: finished,
        fresh: switch (NextTradeRobot.of(key, standing)) {
          Ok(:final value) => value.slot,
          Err() => null,
        },
      ),
    );
  }
}
