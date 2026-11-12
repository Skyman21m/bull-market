import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';

/// Deletes everything the feature stores for a network: today, its Garage Key, whatever the entry holds.
///
/// Destructive: the robots of the key are lost unless the user kept a copy of it, so call it only on the user's explicit confirmation.
/// It is also the only way out of a key that cannot be read.
/// The feature stores no state of its robots yet, such as the coordinator each robot index is bound to (the rule "one robot, one coordinator" of AGENTS.md).
/// When it does, that state is tied to a fingerprint of its key and is not erased here: the keystore's delete reaches the disk asynchronously on Android, so a key can come back after the app dies, and its robot 0 must not look new then.
final class DeleteGarageKeyUsecase {
  final GarageKeyRepository _repository;

  const DeleteGarageKeyUsecase(this._repository);

  @useResult
  Future<Result<void, P2pFailure>> execute(RobosatsNetwork network) =>
      _repository.delete(network);
}
