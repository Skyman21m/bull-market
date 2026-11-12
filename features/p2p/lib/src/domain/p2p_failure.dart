import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show GarageKeyFailure;

/// Every modeled, recoverable failure of the operations of the P2P feature itself.
///
/// A failure of this family is a type and nothing else: it carries no key material, no text from the vault and no message from a library, so that logging or showing one cannot reveal what the keystore or the user held.
/// The failures of a coordinator are the `CoordinatorFailure` family of `package:robosats`.
sealed class P2pFailure extends Failure {
  const P2pFailure();
}

/// No Garage Key is stored for this network, as the vault concluded after its full read budget.
///
/// The only failure after which the screens may offer to generate or import a key.
final class GarageKeyMissingFailure extends P2pFailure {
  const GarageKeyMissingFailure();
}

/// A Garage Key, readable or not, is already stored for this network, and nothing was written.
///
/// A stored key is never replaced: replacing it would lose every robot derived from it.
final class GarageKeyAlreadyStoredFailure extends P2pFailure {
  const GarageKeyAlreadyStoredFailure();
}

/// The keystore is locked, as on a device not unlocked since it started: a stored key, if any, is intact.
///
/// Ask the user to unlock the device and try again; never offer to generate, import or delete a key after it.
final class GarageKeyLockedFailure extends P2pFailure {
  const GarageKeyLockedFailure();
}

/// The entry stored for this network could not be read.
///
/// Try again; if it keeps failing, the only way out is to delete it, with the warning that the key and its robots are lost unless the user kept a copy.
final class GarageKeyUnreadableFailure extends P2pFailure {
  const GarageKeyUnreadableFailure();
}

/// The entry stored for this network is present but does not read as a Garage Key, and it was kept as it is: a value that does not parse, or one the keystore keeps returning empty.
///
/// A keystore that misbehaved may give the key back on a later read; if it does not, the only way out is to delete the entry, with the warning that the key and its robots are lost unless the user kept a copy, then to import that copy.
final class GarageKeyUnusableFailure extends P2pFailure {
  const GarageKeyUnusableFailure();
}

/// The keystore did not store the new key: read the slot again before offering anything.
final class GarageKeyNotSavedFailure extends P2pFailure {
  const GarageKeyNotSavedFailure();
}

/// The keystore did not delete the entry: the key, if there was one, may still be stored.
final class GarageKeyNotDeletedFailure extends P2pFailure {
  const GarageKeyNotDeletedFailure();
}

/// What the user gave is not a Garage Key, and nothing was stored.
final class GarageKeyInvalidFailure extends P2pFailure {
  /// Why, as `package:robosats` says it: a type that carries none of the text it rejected.
  final GarageKeyFailure reason;

  const GarageKeyInvalidFailure(this.reason);
}

/// No robot can be derived from the stored key: every index searched gave a token that a coordinator cannot be contacted with.
///
/// It does not happen with a key drawn at random.
final class GarageRobotUnavailableFailure extends P2pFailure {
  const GarageRobotUnavailableFailure();
}

/// The feature's database could not be read or written: nothing was sent to a coordinator, and no key was stored.
///
/// Try again; the database holds no secret, and a failure of it never loosens a binding.
final class P2pStorageFailure extends P2pFailure {
  const P2pStorageFailure();
}

/// This robot is bound to another coordinator, which received its token hash first: nothing was sent.
///
/// The token hash is the whole credential of a robot and the same on every coordinator, so a robot never goes to a second coordinator (AGENTS.md, « One robot, one coordinator »).
final class RobotBoundToAnotherCoordinatorFailure extends P2pFailure {
  const RobotBoundToAnotherCoordinatorFailure();
}

/// The coordinator this robot is bound to no longer has the onion address or the keys it had when the robot was bound: nothing was sent.
///
/// The federation list of the app changed that coordinator since: a change to assess before the robot goes there again, as the refresh of the RoboSats reference in AGENTS.md requires.
final class RobotCoordinatorChangedFailure extends P2pFailure {
  const RobotCoordinatorChangedFailure();
}

/// This robot has no binding, and the history of its Garage Key is unknown: nothing was written or sent.
///
/// The key was imported, or this device has no record of drawing it, so the robot may already live on another coordinator, and sending it here could hand its token hash to a second one.
final class RobotHistoryUnknownFailure extends P2pFailure {
  const RobotHistoryUnknownFailure();
}
