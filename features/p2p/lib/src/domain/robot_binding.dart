import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show Coordinator, RobosatsNetwork;

import 'garage_key_fingerprint.dart';
import 'p2p_failure.dart';

/// A robot as its binding knows it: the network of its Garage Key, the fingerprint of that key and its index.
///
/// It holds no token, so it is what the feature's database is handed; a `NetworkRobot` gives it as `slot`.
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

/// A coordinator as a binding records it: its short alias, the onion address of its instance on one network, and the keys the federation list publishes for it there.
///
/// Its alias alone would not do: the federation list of a later version of the app could give that alias another server, node or Nostr key, which must not receive the robot without a review.
@immutable
final class CoordinatorIdentity {
  /// The short alias of the coordinator in the federation list, such as `temple`.
  final String alias;

  /// The onion origin of its instance on the network, `http://<56 characters>.onion`, where the requests of the robot go.
  final String onion;

  /// The public keys of the Lightning nodes of that instance, sorted.
  final List<String> nodeKeys;

  /// The Nostr public key of the coordinator, in hexadecimal.
  final String nostrKey;

  CoordinatorIdentity({
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
      alias: coordinator.shortAlias,
      onion: onion,
      nodeKeys: coordinator.nodesPubkeys(network),
      nostrKey: coordinator.nostrHexPubkey,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CoordinatorIdentity &&
      other.alias == alias &&
      other.onion == onion &&
      _sameList(other.nodeKeys, nodeKeys) &&
      other.nostrKey == nostrKey;

  @override
  int get hashCode =>
      Object.hash(alias, onion, Object.hashAll(nodeKeys), nostrKey);

  @override
  String toString() => 'CoordinatorIdentity($alias)';

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

  /// Whether a request of the robot may go to [requested]: only to the coordinator it is bound to, with the onion address and the keys it had then.
  ///
  /// The same alias or onion address with anything else changed is a [RobotCoordinatorChangedFailure]; any other coordinator is a [RobotBoundToAnotherCoordinatorFailure].
  Result<void, P2pFailure> admits(CoordinatorIdentity requested) {
    if (requested == coordinator) return const Ok(null);
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
