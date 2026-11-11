import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';

/// Deletes everything the feature stores for a network: today, its Garage Key, whatever the entry holds.
///
/// Destructive: the robots of the key are lost unless the user kept a copy of it, so call it only on the user's explicit confirmation.
/// It is also the only way out of a key that cannot be read.
/// When the feature stores the state of its robots, such as the coordinator each robot index is bound to, the key is deleted first and that state last.
/// So a failure part way leaves bindings without a key, which only restrict, and never a key without its bindings, whose robot 0 would look new and could be sent to a second coordinator: the loss of funds that the rule "one robot, one coordinator" of AGENTS.md prevents.
/// That state will also be tied to the key it belongs to, so that bindings left behind never pass for those of another key.
final class DeleteGarageKeyUsecase {
  final GarageKeyRepository _repository;

  const DeleteGarageKeyUsecase(this._repository);

  @useResult
  Future<Result<void, P2pFailure>> execute(RobosatsNetwork network) =>
      _repository.delete(network);
}
