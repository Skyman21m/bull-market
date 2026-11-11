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

/// The entry stored for this network is present but is not a usable Garage Key, and it was kept as it is.
///
/// No retry helps: the only way out is to delete it, then import the user's copy of the key if there is one.
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
