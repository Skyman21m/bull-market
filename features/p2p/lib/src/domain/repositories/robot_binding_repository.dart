import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../garage_key_fingerprint.dart';
import '../p2p_failure.dart';
import '../robot_binding.dart';

/// The rule « one robot, one coordinator » of AGENTS.md, kept on the device: the coordinator each robot index of each Garage Key is bound to, and what this device knows of the history of each key.
///
/// It holds no secret: networks, key fingerprints, robot indexes, the identities of coordinators and times.
/// A binding is written before the first request of its robot leaves, and is never changed or removed, not even when the key is deleted: the keystore's delete reaches the disk asynchronously on Android, so a key can come back, and a deleted key can be pasted back later from the user's copy.
/// Only a key drawn on this device, and recorded as such, has a known history: for any other key, imported or never recorded, a robot without a binding may already live on another coordinator.
abstract interface class RobotBindingRepository {
  /// Records that the key of [key] was drawn on this device for [network], so that its robots have no history elsewhere.
  ///
  /// It never overrides a key recorded as imported.
  @useResult
  Future<Result<void, P2pFailure>> recordGeneratedKey(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  );

  /// Records that the key of [key] was imported for [network]: its history is unknown from now on, even if this device drew it before.
  @useResult
  Future<Result<void, P2pFailure>> recordImportedKey(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  );

  /// Binds [robot] to [coordinator] if it has no binding and its key was drawn on this device, then checks the binding of [robot] against [coordinator].
  ///
  /// It returns only once the binding is on disk.
  /// Two calls for one robot and two coordinators, at once, from any number of connections, bind it to one coordinator only, and the other call fails.
  /// A robot bound to another coordinator is a [RobotBoundToAnotherCoordinatorFailure], one bound to a coordinator whose onion address or keys changed since is a [RobotCoordinatorChangedFailure], and one without a binding whose key's history is unknown is a [RobotHistoryUnknownFailure], with nothing written.
  @useResult
  Future<Result<void, P2pFailure>> bind(
    RobotSlot robot,
    CoordinatorIdentity coordinator,
  );
}
