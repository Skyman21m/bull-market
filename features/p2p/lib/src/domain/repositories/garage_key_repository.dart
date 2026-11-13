import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show GarageKey, RobosatsNetwork;

import '../network_garage_key.dart';
import '../p2p_failure.dart';

/// The RoboSats Garage Key of each network, kept by the vault of the wallet, and the robots derived from it.
///
/// What leaves it is deliberately narrow: whether a key is stored, robots derived from it, each with the network of its key, the key a draw has just made, for the record of its history, and, for the screens of the Garage only, the key of a network as a [NetworkGarageKey].
/// The bytes of the key never leave it, and its text form is made by `GarageKeyView` alone, the only class the custody gate allows to reveal it.
///
/// The rules of the vault hold for every caller: create or import a key only on an explicit action of the user, never at startup or in the background; only after [exists] said that no key is stored, never after a failure; a stored key is never replaced; after a key that cannot be read, the only way out is [delete].
abstract interface class GarageKeyRepository {
  /// Draws a new key in the vault, stores it for [network], whose slot must be empty, and returns it with that network.
  ///
  /// A slot that holds anything, readable or not, is a [GarageKeyAlreadyStoredFailure], and nothing is written.
  /// The key returned is built from the bytes the vault drew, not read back from the slot, so that the draw records the history of that very key; only `GenerateGarageKeyUsecase` calls this, and it hands the key to no one (`test/robot_bindings_architecture_test.dart`).
  /// The screen that shows the key for backup, right after, reads it again.
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> create(RobosatsNetwork network);

  /// Stores [key], a key the user restores, for [network], whose slot must be empty.
  ///
  /// A slot that holds anything, readable or not, is a [GarageKeyAlreadyStoredFailure], and nothing is written.
  @useResult
  Future<Result<void, P2pFailure>> import(
    RobosatsNetwork network,
    GarageKey key,
  );

  /// Whether a usable key is stored for [network]: `false` only when the vault concluded, after its full read budget, that the slot is empty.
  ///
  /// A slot it cannot read is a failure, never `false`: the key may well be there.
  @useResult
  Future<Result<bool, P2pFailure>> exists(RobosatsNetwork network);

  /// The key stored for [network], with that network, for the screens of the Garage (`GarageKeyView`, which shows it for backup, and the account navigator, which derives robot number N from it) and for the robots of the trades (`InterimTradeRobots`, which derives the robot of a new trade or of a recorded one from it).
  ///
  /// No key is a [GarageKeyMissingFailure].
  /// Hold it no longer than the screen that uses it.
  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> read(RobosatsNetwork network);

  /// The first robot of the key stored for [network] that a coordinator can be contacted with, from index 0, tagged with [network].
  ///
  /// No key is a [GarageKeyMissingFailure].
  @useResult
  Future<Result<NetworkRobot, P2pFailure>> firstUsableRobot(
    RobosatsNetwork network,
  );

  /// Deletes the entry of [network], whatever it holds: destructive, as the robots of the key are lost unless the user kept a copy of it.
  @useResult
  Future<Result<void, P2pFailure>> delete(RobosatsNetwork network);
}
