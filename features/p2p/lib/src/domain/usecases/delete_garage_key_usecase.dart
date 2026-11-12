import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';

/// Deletes the Garage Key of a network, whatever the entry holds.
///
/// Destructive: the robots of the key are lost unless the user kept a copy of it, so call it only on the user's explicit confirmation.
/// It is also the only way out of a key that cannot be read.
/// It leaves the bindings of the robots of the key, and the record of its history, in the feature's database, tied to the key's fingerprint, for good (the rule « one robot, one coordinator » of AGENTS.md): the keystore's delete reaches the disk asynchronously on Android, so a key can come back after the app dies, and its robot 0 must not look new then; and a deleted key can be pasted back later from the user's copy, whose robots are still bound where they were.
/// They hold no secret, and they only restrict the robots of that key.
final class DeleteGarageKeyUsecase {
  final GarageKeyRepository _repository;

  const DeleteGarageKeyUsecase(this._repository);

  @useResult
  Future<Result<void, P2pFailure>> execute(RobosatsNetwork network) =>
      _repository.delete(network);
}
