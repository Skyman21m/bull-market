import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show GarageKey, GarageRobot, RobosatsNetwork;

import '../p2p_failure.dart';

/// The RoboSats Garage Key of each network, kept by the vault of the wallet, and the robots derived from it.
///
/// What leaves it is deliberately narrow: whether a key is stored, and robots derived from it.
/// The key itself, its bytes and its text form never do: the master key of every robot lives for the time of one call.
///
/// The rules of the vault hold for every caller: create or import a key only on an explicit action of the user, never at startup or in the background; only after [exists] said that no key is stored, never after a failure; a stored key is never replaced; after a key that cannot be read, the only way out is [delete].
abstract interface class GarageKeyRepository {
  /// Draws a new key in the vault and stores it for [network], whose slot must be empty.
  ///
  /// A slot that holds anything, readable or not, is a [GarageKeyAlreadyStoredFailure], and nothing is written.
  /// The key is not returned: the screen that shows it for backup, right after, reads it again.
  @useResult
  Future<Result<void, P2pFailure>> create(RobosatsNetwork network);

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

  /// The first robot of the key stored for [network] that a coordinator can be contacted with, from index 0.
  ///
  /// No key is a [GarageKeyMissingFailure].
  @useResult
  Future<Result<GarageRobot, P2pFailure>> firstUsableRobot(
    RobosatsNetwork network,
  );

  /// Deletes the entry of [network], whatever it holds: destructive, as the robots of the key are lost unless the user kept a copy of it.
  @useResult
  Future<Result<void, P2pFailure>> delete(RobosatsNetwork network);
}
