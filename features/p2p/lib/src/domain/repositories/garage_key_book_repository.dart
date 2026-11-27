import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../garage_key_fingerprint.dart';
import '../garage_keyring.dart';
import '../p2p_failure.dart';

/// What `p2p.sqlite` keeps of the Garage Keys of the words (#81, schema 10): the indexes this device activated on each network with their fingerprints, the key selected on each network with the last internal Garage Key selected there, and whether « Your Garage Keys » is due. Never a key.
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

  /// The last internal Garage Key selected on [network], kept while the external Garage Key is selected; `null` when none was selected yet.
  @useResult
  Future<Result<int?, P2pFailure>> lastInternal(RobosatsNetwork network);

  /// Whether « Your Garage Keys » is due: made due by the step to schema 10 (an update) and not shown yet.
  @useResult
  Future<Result<bool, P2pFailure>> externalNoticeDue();

  /// Records that « Your Garage Keys » was shown, or has nothing to say: it is never due again. Nothing is written when it is not due.
  @useResult
  Future<Result<void, P2pFailure>> externalNoticeShown();

  /// Selects [selection] on [network]: an internal Garage Key only when its index is activated there (`Ok(false)` otherwise, nothing written), which is kept as the last internal one; the external Garage Key as it is, its presence in the vault being the caller's to check, the internal one selected until then kept as the last.
  @useResult
  Future<Result<bool, P2pFailure>> select(
    RobosatsNetwork network,
    GarageKeySelection selection,
  );
}
