import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show Coordinator, RobosatsNetwork;

import 'garage_key_fingerprint.dart';
import 'p2p_failure.dart';

/// A robot as its binding knows it: the network of its Garage Key, the fingerprint of that key and its index.
///
/// It holds no token, so it is what the feature's database is handed; a `NetworkRobot` gives it as `slot`.
/// Its binding is looked up by fingerprint and index alone, since the robot's credential is the same on both networks; its network decides which history of the key applies and must match the network of the coordinator it is bound to.
@immutable
final class RobotSlot {
  final RobosatsNetwork network;
  final GarageKeyFingerprint keyFingerprint;

  /// The index of the robot in its Garage Key, from 0.
  final int accountIndex;

  const RobotSlot(this.network, this.keyFingerprint, this.accountIndex);

  @override
  bool operator ==(Object other) =>
      other is RobotSlot &&
      other.network == network &&
      other.keyFingerprint == keyFingerprint &&
      other.accountIndex == accountIndex;

  @override
  int get hashCode => Object.hash(network, keyFingerprint, accountIndex);

  @override
  String toString() => 'RobotSlot(${network.name}, $accountIndex)';
}

/// What this device knows of the history of a Garage Key: where its robots may already have gone.
enum GarageKeyHistory {
  /// The key was drawn on this device and recorded so: a robot of it without a binding has been sent to no coordinator, and may be bound for the first time.
  drawnHere,

  /// The key was imported, or this device has no record of drawing it (the record could not be written, or the database was lost): a robot of it without a binding may already live on a coordinator, so it is never bound.
  unknown,
}

/// What this device records about where the robots of one Garage Key may be: the history of the key on one network, and whether any robot index of it is bound to a coordinator, on either network.
///
/// It holds no key, no fingerprint and no coordinator: only what decides whether a robot of the key may live on a coordinator.
@immutable
final class GarageKeyExposure {
  /// The history of the key on the network of its slot.
  final GarageKeyHistory history;

  /// Whether a robot index of the key is bound to a coordinator, on either network.
  final bool hasBinding;

  const GarageKeyExposure({required this.history, required this.hasBinding});

  /// Whether a robot of the key may live on a coordinator: one is bound, on either network, or the key was not recorded as drawn on this device for its network, so its robots may have reached coordinators from elsewhere.
  ///
  /// Only a key drawn here, recorded so, with no robot bound, has none: deleting it loses no robot that a coordinator knows.
  bool get mayHaveRobotsOnCoordinators =>
      hasBinding || history != GarageKeyHistory.drawnHere;

  @override
  bool operator ==(Object other) =>
      other is GarageKeyExposure &&
      other.history == history &&
      other.hasBinding == hasBinding;

  @override
  int get hashCode => Object.hash(history, hasBinding);

  @override
  String toString() => 'GarageKeyExposure(${history.name}, $hasBinding)';
}

/// A coordinator as a binding records it: the network of its instance, its short alias, the onion address of that instance, and the keys the federation list publishes for it there.
///
/// Its alias alone would not do: the federation list of a later version of the app could give that alias another server, node or Nostr key, which must not receive the robot without a review.
/// Its network is part of it: a robot index has one credential on both networks, so its binding to a coordinator of one network refuses every coordinator of the other.
@immutable
final class CoordinatorIdentity {
  /// The network of the instance the binding names.
  final RobosatsNetwork network;

  /// The short alias of the coordinator in the federation list, such as `temple`.
  final String alias;

  /// The onion origin of its instance on the network, `http://<56 characters>.onion`, where the requests of the robot go.
  final String onion;

  /// The public keys of the Lightning nodes of that instance, sorted.
  final List<String> nodeKeys;

  /// The Nostr public key of the coordinator, in hexadecimal.
  final String nostrKey;

  CoordinatorIdentity({
    required this.network,
    required this.alias,
    required this.onion,
    required Iterable<String> nodeKeys,
    required this.nostrKey,
  }) : nodeKeys = List.unmodifiable([...nodeKeys]..sort());

  /// The identity of [coordinator] on [network], as the federation list of this version of the app gives it, or `null` when it has no onion address there, where no robot request can go.
  static CoordinatorIdentity? of(
    Coordinator coordinator,
    RobosatsNetwork network,
  ) {
    final onion = coordinator.origins(network).onion;
    if (onion == null) return null;
    return CoordinatorIdentity(
      network: network,
      alias: coordinator.shortAlias,
      onion: onion,
      nodeKeys: coordinator.nodesPubkeys(network),
      nostrKey: coordinator.nostrHexPubkey,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CoordinatorIdentity &&
      other.network == network &&
      other.alias == alias &&
      other.onion == onion &&
      _sameList(other.nodeKeys, nodeKeys) &&
      other.nostrKey == nostrKey;

  @override
  int get hashCode =>
      Object.hash(network, alias, onion, Object.hashAll(nodeKeys), nostrKey);

  @override
  String toString() => 'CoordinatorIdentity(${network.name}, $alias)';

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The coordinator a robot index is bound to: the first coordinator that was sent its token hash, as it was then.
///
/// A binding is never changed or removed: a robot whose token hash went to a coordinator never goes to another one.
@immutable
final class RobotBinding {
  final CoordinatorIdentity coordinator;

  /// When the binding was written, just before the first request of the robot left for [coordinator].
  final DateTime boundAt;

  const RobotBinding(this.coordinator, this.boundAt);

  /// Whether a request of the robot may go to [requested]: only to the coordinator it is bound to, on the same network, with the onion address and the keys it had then.
  ///
  /// A coordinator of the other network, whatever its alias, and any other coordinator are a [RobotBoundToAnotherCoordinatorFailure]; the same alias or onion address on the same network, with anything else changed, is a [RobotCoordinatorChangedFailure].
  Result<void, P2pFailure> admits(CoordinatorIdentity requested) {
    if (requested == coordinator) return const Ok(null);
    if (requested.network != coordinator.network) {
      return const Err(RobotBoundToAnotherCoordinatorFailure());
    }
    if (requested.alias == coordinator.alias ||
        requested.onion == coordinator.onion) {
      return const Err(RobotCoordinatorChangedFailure());
    }
    return const Err(RobotBoundToAnotherCoordinatorFailure());
  }

  @override
  bool operator ==(Object other) =>
      other is RobotBinding &&
      other.coordinator == coordinator &&
      other.boundAt == boundAt;

  @override
  int get hashCode => Object.hash(coordinator, boundAt);

  @override
  String toString() => 'RobotBinding($coordinator)';
}
