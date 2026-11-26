import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../garage_key_fingerprint.dart';
import '../garage_keyring.dart';
import '../p2p_failure.dart';

/// What `p2p.sqlite` keeps of the Garage Keys derived from the words (#81, schema 10): the one-time switch of the book, and the indexes this device activated on each network with their fingerprints. Never a key.
///
/// Only `GarageKeyRepositoryImpl` reads or writes it.
abstract interface class GarageKeyBookRepository {
  /// Where the switch stands. The database empties its tables itself when it opens (`P2pDatabase`), so this is never [GarageSwitchState.emptying] once a query ran, unless the emptying failed.
  @useResult
  Future<Result<GarageSwitchState, P2pFailure>> switchState();

  /// Moves the switch from [GarageSwitchState.vaultPending] to [GarageSwitchState.derived], once the vault's slots are deleted; from any other state it changes nothing.
  @useResult
  Future<Result<void, P2pFailure>> markDerived();

  /// The keys activated on [network], by index from 0.
  @useResult
  Future<Result<List<ActivatedGarageKey>, P2pFailure>> activatedKeys(
    RobosatsNetwork network,
  );

  /// Activates [index] on [network] with [fingerprint], recorded as a key drawn on this device for that network (so that its robots may be bound and trade), only when [index] is the next one (0 when none is activated, otherwise the highest plus one) and the switch is [GarageSwitchState.derived].
  ///
  /// `Ok(true)` when this call wrote it; `Ok(false)` when it was not the next index any more (another call activated it, or a later one) or the switch is not there: nothing written.
  /// The history comes first, then the index, each one statement: a run killed between them leaves a history no index uses, never an index whose robots cannot be bound.
  @useResult
  Future<Result<bool, P2pFailure>> activate(
    RobosatsNetwork network,
    int index,
    GarageKeyFingerprint fingerprint,
  );
}
