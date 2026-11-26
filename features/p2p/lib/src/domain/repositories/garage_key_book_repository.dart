import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../garage_key_fingerprint.dart';
import '../garage_keyring.dart';
import '../p2p_failure.dart';

/// What `p2p.sqlite` keeps of the Garage Keys of the words (#81, schema 10): the indexes this device activated on each network with their fingerprints, and the key selected on each network. Never a key.
///
/// Only `GarageKeyRepositoryImpl` reads or writes it.
abstract interface class GarageKeyBookRepository {
  /// The keys activated on [network], by index from 0.
  @useResult
  Future<Result<List<ActivatedGarageKey>, P2pFailure>> activatedKeys(
    RobosatsNetwork network,
  );

  /// Activates [index] on [network] with [fingerprint], recorded as a key drawn on this device for that network (so that its robots may be bound and trade), only when [index] is the next one (0 when none is activated, otherwise the highest plus one).
  ///
  /// `Ok(true)` when this call wrote it; `Ok(false)` when it was not the next index any more (another call activated it, or a later one): nothing written.
  /// The history comes first, then the index, each one statement: a run killed between them leaves a history no index uses, never an index whose robots cannot be bound.
  @useResult
  Future<Result<bool, P2pFailure>> activate(
    RobosatsNetwork network,
    int index,
    GarageKeyFingerprint fingerprint,
  );

  /// The key selected on [network], the key of new trades there; `null` when none is recorded yet.
  @useResult
  Future<Result<GarageKeySelection?, P2pFailure>> selected(
    RobosatsNetwork network,
  );

  /// Selects [selection] on [network]: a key of the words only when its index is activated there (`Ok(false)` otherwise, nothing written); the external key as it is, its presence in the vault being the caller's to check.
  @useResult
  Future<Result<bool, P2pFailure>> select(
    RobosatsNetwork network,
    GarageKeySelection selection,
  );
}
