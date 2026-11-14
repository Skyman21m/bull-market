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

/// This device could not make or check the OpenPGP key pair of a robot: its clock is outside the dates an OpenPGP key can hold, or the isolate that does that work could not be started.
///
/// Before a first contact, nothing was sent, and the binding written just before stays, as after any request that failed.
/// After an answer whose key pair was to be proven, the request was sent and its answer is dropped, neither taken nor refused: asking again is harmless, since a read creates nothing and a coordinator keeps the pair of the first contact.
final class RobotKeyComputeFailure extends P2pFailure {
  const RobotKeyComputeFailure();
}

/// This robot has no binding, and the history of its Garage Key is unknown: nothing was written or sent.
///
/// The key was imported, or this device has no record of drawing it, so the robot may already live on another coordinator, and sending it here could hand its token hash to a second one.
final class RobotHistoryUnknownFailure extends P2pFailure {
  const RobotHistoryUnknownFailure();
}

/// This robot was sent to no coordinator from this device, so there is none to read it back from: nothing was sent.
///
/// Its coordinator is the one its binding names, never one a screen chooses; a robot without a binding can only be put on a coordinator, on the user's request.
final class RobotNotBoundFailure extends P2pFailure {
  const RobotNotBoundFailure();
}

/// The robot requests to this coordinator found the transport busy too often: after several attempts with growing waits, or so many times lately that its requests now fail at once until that passes.
///
/// Nothing was sent on the attempt that got the last busy answer, and none is made while the coordinator is in that state; the robot stays bound as it was.
/// It is a sign about that coordinator, which may hold or drop the connections of its robots: try again in a moment.
final class RobotCoordinatorBusyFailure extends P2pFailure {
  const RobotCoordinatorBusyFailure();
}

/// This coordinator answered too many first contacts with a nickname already taken (error 7004) during this run of the app: first contacts to it fail at once, and nothing was written or sent.
///
/// A coordinator can answer that error to every robot, and each such answer leaves a robot index bound to it for good: the cap keeps it from using up the Garage Key.
/// It is kept in memory only and ends with the run; reading back a robot already bound to that coordinator is not affected.
final class RobotCoordinatorTooManyRefusalsFailure extends P2pFailure {
  const RobotCoordinatorTooManyRefusalsFailure();
}

/// The Garage Key of this network may not start a trade: it is not recorded as drawn on this device for the network, or it is recorded as imported or acknowledged on a network.
///
/// Its robots may live on coordinators from elsewhere, which hold their credentials, so none is used for a new trade (design note `docs/design/phase-2-taking-an-order.md` § 3.3); nothing was written or sent.
/// A robot of such a key may still finish an order it already holds, once the user takes that trade over.
final class GarageKeyNotForTradesFailure extends P2pFailure {
  const GarageKeyNotForTradesFailure();
}

/// The federation list of this version of the app gives this coordinator no onion address on the network of the trade: no robot request can go there, and nothing was written or sent.
final class TradeCoordinatorNotOnNetworkFailure extends P2pFailure {
  const TradeCoordinatorNotOnNetworkFailure();
}

/// The Garage Key of this trade's robot is not the one the vault holds for the trade's network, or the vault holds none: nothing was sent.
///
/// The trade can be finished once the key is pasted back, or with the official client and that key.
final class TradeKeyMissingFailure extends P2pFailure {
  const TradeKeyMissingFailure();
}

/// This robot already has a trade record: a robot is never used for a second trade, and nothing was written.
final class TradeAlreadyRecordedFailure extends P2pFailure {
  const TradeAlreadyRecordedFailure();
}

/// This robot may not start a trade: it has no binding, or its binding was made under a key from elsewhere or on another network than the take's, and nothing was written.
///
/// Only a robot the robot layer returned for a new trade is recorded as a pending take.
final class RobotNotForNewTradeFailure extends P2pFailure {
  const RobotNotForNewTradeFailure();
}

/// This trade record is closed, and a closed record never changes: nothing was written.
final class TradeClosedFailure extends P2pFailure {
  const TradeClosedFailure();
}

/// This robot was released, its screen left, before the request could leave: nothing more was sent for it.
///
/// A request already in flight when the robot was released runs to its end, and its answer is returned to the call that sent it, like any other: the screen that is gone drops it.
final class RobotReleasedFailure extends P2pFailure {
  const RobotReleasedFailure();
}
