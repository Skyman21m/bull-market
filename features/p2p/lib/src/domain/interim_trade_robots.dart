import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show Coordinator, RobosatsNetwork;

import 'garage_key_fingerprint.dart';
import 'network_garage_key.dart';
import 'next_trade_robot.dart';
import 'p2p_failure.dart';
import 'repositories/garage_key_repository.dart';
import 'repositories/trade_record_repository.dart';
import 'robot_binding.dart';
import 'trade_record.dart';
import 'trade_robots.dart';

/// The robot layer of the trades until #79 lands (design note `docs/design/phase-2-taking-an-order.md` § 2.1, § 3.3): the robots of the Garage Keys of the default wallet's words (#81, design note `docs/design/garage-key-from-the-words.md`).
///
/// A new trade takes its robot from the key selected in the Garage Key card, a key of the words whatever its number or the external key, and from no other ([GarageKeyRepository.forNewTrade], the owner's decisions of 2026-11-26).
/// A recorded trade finishes with the key whose robot it is ([GarageKeyRepository.ofSlot]: a key of the words derived again by its index, after its fingerprint was compared with the one recorded, or the external key the vault keeps, when the fingerprint is its own).
/// A new trade gets the first usable robot of the key ([NextTradeRobot.of], which the Garage shows as the fresh robot, #251), strictly above the floor of the key's recovery note read on the relays (#81, its first reading awaited within its limit), as `NetworkGarageKey.firstUsableRobot` finds it (an index whose token or nickname a coordinator would refuse is skipped, as for the Garage's account navigator), whose index has no binding, on either network, and no trade record.
/// It is bound to the trade's coordinator by `TradeRecordRepository.reserveForNewTrade`, one statement that writes only when the index is still free, and says whether this call wrote: a call that lost the index to another reads what is in use again and goes on to the next one.
/// So the binding is the reservation: a robot bound and never recorded with a trade, as when the app is killed between the two, stays bound to that coordinator, as every binding does, and is never returned again; the next call takes the next free index.
/// Every key gives robots for new trades, whatever its origin: a key of the words, the key drawn here before #81, a key imported (decided on 2026-11-26, #81). Any of them may have robots on coordinators from elsewhere (the same words on another device, the key pasted into the official client, a key imported from it): what stands in for that is the refusal of a robot the coordinator of the trade already knows (`RobotOnCoordinatorFace.alreadyExisted`, design note § 3), after which the next call takes the next free index, the robot refused staying bound there.
final class InterimTradeRobots implements TradeRobots {
  /// How many times a call reads what is in use again after another call took the index it chose: each time means one more robot reserved by someone else, and the app makes its reservations one at a time on one connection.
  static const int maxReservationAttempts = 32;

  final GarageKeyRepository _keys;
  final TradeRecordRepository _records;

  /// `RecoveryNoteSync.beforeNewTrade` (#81): the first reading of the key's recovery note, awaited within its limit before the robot is chosen, so that the robot is above the note's floor; `null` where nothing reads the notes.
  final Future<void> Function(NetworkGarageKey key)? _beforeNewTrade;

  const InterimTradeRobots(this._keys, this._records, {this._beforeNewTrade});

  @override
  Future<Result<ReservedRobot, P2pFailure>> robotForNewTrade(
    RobosatsNetwork network,
    Coordinator coordinator,
  ) async {
    final identity = CoordinatorIdentity.of(coordinator, network);
    if (identity == null) {
      return const Err(TradeCoordinatorNotOnNetworkFailure());
    }
    final NetworkGarageKey key;
    switch (await _keys.forNewTrade(network)) {
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
    // The floor of the key's recovery note (#81): its first reading, still running or started now, is awaited within its limit; whatever it gave, the standing read below holds the floor recorded.
    await _beforeNewTrade?.call(key);
    for (var attempt = 0; attempt < maxReservationAttempts; attempt++) {
      final NewTradeStanding standing;
      switch (await _records.newTradeStandingOf(network, fingerprint)) {
        case Ok(:final value):
          standing = value;
        case Err(:final failure):
          return Err(failure);
      }
      // The robot the Garage shows as fresh is this very computation (#251).
      final NetworkRobot candidate;
      switch (NextTradeRobot.of(key, standing)) {
        case Ok(:final value):
          candidate = value;
        case Err(:final failure):
          return Err(failure);
      }
      switch (await _records.reserveForNewTrade(candidate.slot, identity)) {
        case Ok(value: final reservation?):
          return switch (ReservedRobot.of(candidate, reservation)) {
            final reserved? => Ok(reserved),
            // The repository reserved another robot than the one asked: a bug of this code, never a robot to use.
            null => throw StateError('A reservation of another robot.'),
          };
        case Ok(value: null):
          // Another call took that index: the next reading goes on to the next free one.
          continue;
        case Err(:final failure):
          return Err(failure);
      }
    }
    return const Err(P2pStorageFailure());
  }

  @override
  Future<Result<NetworkRobot, P2pFailure>> robotOfTrade(TradeRecord record) =>
      robotOfSlot(record.robot);

  @override
  Future<Result<NetworkRobot, P2pFailure>> robotOfSlot(RobotSlot slot) async {
    final NetworkGarageKey key;
    switch (await _keys.ofSlot(slot)) {
      case Ok(:final value):
        key = value;
      case Err(failure: GarageKeyMissingFailure()):
        return const Err(TradeKeyMissingFailure());
      case Err(:final failure):
        return Err(failure);
    }
    // The index of the slot, as the key gives it back: the same key (its fingerprint), network and index, or this is not the key of the robot.
    return switch (key.firstUsableRobot(slot.accountIndex)) {
      Ok(:final value) when value.slot == slot => Ok(value),
      _ => const Err(TradeKeyMissingFailure()),
    };
  }

  @override
  Stream<Result<List<TradeRecord>, P2pFailure>> activeTrades(
    RobosatsNetwork network,
  ) => _records.watchActiveTrades(network);

  /// [NextTradeRobot.firstFreeAmong], for the tests that played it here before #251.
  @visibleForTesting
  static Result<R, F> firstFreeAmong<R, F extends Failure>(
    Set<int> inUse,
    Result<R, F> Function(int fromIndex) firstUsable,
    int Function(R robot) indexOf,
  ) => NextTradeRobot.firstFreeAmong(inUse, firstUsable, indexOf);
}
