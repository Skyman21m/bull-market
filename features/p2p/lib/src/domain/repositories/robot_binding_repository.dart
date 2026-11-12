import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../garage_key_fingerprint.dart';
import '../p2p_failure.dart';
import '../robot_binding.dart';

/// The rule « one robot, one coordinator » of AGENTS.md, kept on the device: the coordinator each robot index of each Garage Key is bound to, and what this device knows of the history of each key.
///
/// It holds no secret: networks, key fingerprints, robot indexes, the identities of coordinators, the provenance of each binding and times.
/// A binding is written before the first request of its robot leaves, and is never changed or removed, not even when the key is deleted: the keystore's delete reaches the disk asynchronously on Android, so a key can come back, and a deleted key can be pasted back later from the user's copy.
/// Only a key drawn on this device, and recorded as such, has a known history: for any other key, imported or never recorded, a robot without a binding may already live on another coordinator, and it is bound only once the user acknowledged that.
abstract interface class RobotBindingRepository {
  /// Records that the key of [key] was drawn on this device for [network], so that its robots have no history elsewhere.
  ///
  /// It never overrides a key recorded as imported or acknowledged.
  @useResult
  Future<Result<void, P2pFailure>> recordGeneratedKey(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  );

  /// Records that the key of [key] was imported for [network]: its history is unknown from now on, even if this device drew it before or the user acknowledged it.
  @useResult
  Future<Result<void, P2pFailure>> recordImportedKey(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  );

  /// Records that the user acknowledged the unknown history of the key of [key] on [network]: its robots without a binding may be bound from now on, each binding recording that provenance.
  ///
  /// It writes the record when the key has none on [network], and turns `imported` into `acknowledged`.
  /// A key recorded as drawn on this device keeps that record, and a key already acknowledged keeps its first acknowledgement.
  /// [recordImportedKey] makes the history unknown again.
  @useResult
  Future<Result<void, P2pFailure>> recordAcknowledgedKey(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  );

  /// Binds [robot] to [coordinator] if its index has no binding, on either network, and its key was drawn on this device, or acknowledged, for the robot's network, then checks the binding of [robot] against [coordinator].
  ///
  /// A robot index has one binding whatever the network: its token, so its token hash, does not depend on the network.
  /// The binding records the history of the key it was made under as its provenance, read by the same statement that writes it.
  ///
  /// It returns only once the binding is on disk.
  /// Two calls for one robot and two coordinators, at once, from any number of connections, bind it to one coordinator only, and the other call fails.
  /// A robot bound to another coordinator, a coordinator of the other network included, is a [RobotBoundToAnotherCoordinatorFailure], one bound to a coordinator whose onion address or keys changed since is a [RobotCoordinatorChangedFailure], and one without a binding whose key's history is unknown and not acknowledged is a [RobotHistoryUnknownFailure], with nothing written.
  @useResult
  Future<Result<void, P2pFailure>> bind(
    RobotSlot robot,
    CoordinatorIdentity coordinator,
  );

  /// What this device records about the key of [key]: its history on [network], `drawnHere` only when it is recorded as drawn on this device for [network], and whether any robot index of it is bound, on either network.
  ///
  /// It is what the PIN rule of a delete reads (`NeedsPinToDeleteGarageKeyUsecase`): whether a robot of the key may live on a coordinator.
  /// Both are read in one statement, so they describe the same moment.
  /// It reads only: a database that cannot be read is a [P2pStorageFailure].
  @useResult
  Future<Result<GarageKeyExposure, P2pFailure>> exposureOf(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  );

  /// Where [robot] stands: the binding of its index, made on either network, with its provenance, or none, and the history of its key on the robot's network.
  ///
  /// Both are read in one statement, so they describe the same moment.
  /// It reads only: a database that cannot be read, or a row this code did not write, is a [P2pStorageFailure].
  @useResult
  Future<Result<RobotStanding, P2pFailure>> standingOf(RobotSlot robot);
}
