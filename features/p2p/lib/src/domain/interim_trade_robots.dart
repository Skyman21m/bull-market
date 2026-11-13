import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show Coordinator, RobosatsNetwork;

import 'garage_key_fingerprint.dart';
import 'network_garage_key.dart';
import 'p2p_failure.dart';
import 'repositories/garage_key_repository.dart';
import 'repositories/trade_record_repository.dart';
import 'robot_binding.dart';
import 'trade_record.dart';
import 'trade_robots.dart';

/// The robot layer of the trades until #79 and #81 land (design note `docs/design/phase-2-taking-an-order.md` § 2.1, § 3.3): the robots of the Garage Key of each network, as the vault holds it.
///
/// A new trade gets the first usable robot of the key, as `NetworkGarageKey.firstUsableRobot` finds it (an index whose token or nickname a coordinator would refuse is skipped, as for the Garage's account navigator), whose index has no binding, on either network, and no trade record.
/// It is bound to the trade's coordinator by `TradeRecordRepository.reserveForNewTrade`, one statement that writes only when the index is still free and the key's history allows it, and says whether this call wrote: a call that lost the index to another reads what is in use again and goes on to the next one.
/// So the binding is the reservation: a robot bound and never recorded with a trade, as when the app is killed between the two, stays bound to that coordinator, as every binding does, and is never returned again; the next call takes the next free index.
/// Only a key recorded as drawn on this device for the network, and as nothing else on any network, gives robots for new trades: a key pasted in, or acknowledged, may have robots on coordinators from elsewhere, which hold their credentials.
final class InterimTradeRobots implements TradeRobots {
  /// How many times a call reads what is in use again after another call took the index it chose: each time means one more robot reserved by someone else, and the app makes its reservations one at a time on one connection.
  static const int maxReservationAttempts = 32;

  final GarageKeyRepository _keys;
  final TradeRecordRepository _records;

  const InterimTradeRobots(this._keys, this._records);

  @override
  Future<Result<NetworkRobot, P2pFailure>> robotForNewTrade(
    RobosatsNetwork network,
    Coordinator coordinator,
  ) async {
    final identity = CoordinatorIdentity.of(coordinator, network);
    if (identity == null) {
      return const Err(TradeCoordinatorNotOnNetworkFailure());
    }
    final NetworkGarageKey key;
    switch (await _keys.read(network)) {
      case Ok(:final value):
        key = value;
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
    for (var attempt = 0; attempt < maxReservationAttempts; attempt++) {
      final NewTradeStanding standing;
      switch (await _records.newTradeStandingOf(network, fingerprint)) {
        case Ok(:final value):
          standing = value;
        case Err(:final failure):
          return Err(failure);
      }
      if (!standing.keyDrawnHereOnly) {
        return const Err(GarageKeyNotForTradesFailure());
      }
      final NetworkRobot candidate;
      switch (_firstFreeRobot(key, standing.indexesInUse)) {
        case Ok(:final value):
          candidate = value;
        case Err(:final failure):
          return Err(failure);
      }
      switch (await _records.reserveForNewTrade(candidate.slot, identity)) {
        case Ok(value: true):
          return Ok(candidate);
        case Ok(value: false):
          // Another call took that index, or the key's history changed: the next reading says which.
          continue;
        case Err(:final failure):
          return Err(failure);
      }
    }
    return const Err(P2pStorageFailure());
  }

  @override
  Future<Result<NetworkRobot, P2pFailure>> robotOfTrade(
    TradeRecord record,
  ) async {
    final NetworkGarageKey key;
    switch (await _keys.read(record.network)) {
      case Ok(:final value):
        key = value;
      case Err(failure: GarageKeyMissingFailure()):
        return const Err(TradeKeyMissingFailure());
      case Err(:final failure):
        return Err(failure);
    }
    // The index of the record, as the key gives it back: the same key (its fingerprint), network and index, or this is not the key of the trade.
    return switch (key.firstUsableRobot(record.robot.accountIndex)) {
      Ok(:final value) when value.slot == record.robot => Ok(value),
      _ => const Err(TradeKeyMissingFailure()),
    };
  }

  @override
  Stream<Result<List<TradeRecord>, P2pFailure>> activeTrades(
    RobosatsNetwork network,
  ) => _records.watchActiveTrades(network);

  /// The first robot of [key] that a coordinator can be contacted with whose index is not in [inUse].
  static Result<NetworkRobot, P2pFailure> _firstFreeRobot(
    NetworkGarageKey key,
    Set<int> inUse,
  ) => firstFreeAmong(inUse, key.firstUsableRobot, (robot) => robot.accountIndex);

  /// [_firstFreeRobot] over the robots [firstUsable] gives from an index, each robot's index read by [indexOf].
  ///
  /// For tests only: no Garage Key is known whose first usable robot from a free index is one in use.
  @visibleForTesting
  static Result<R, F> firstFreeAmong<R, F extends Failure>(
    Set<int> inUse,
    Result<R, F> Function(int fromIndex) firstUsable,
    int Function(R robot) indexOf,
  ) {
    var from = 0;
    while (true) {
      while (inUse.contains(from)) {
        from++;
      }
      switch (firstUsable(from)) {
        case Ok(:final value) when inUse.contains(indexOf(value)):
          // A skipped index led to one in use: go on after it.
          from = indexOf(value) + 1;
        case final found:
          return found;
      }
    }
  }
}
