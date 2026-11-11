import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';

/// Deletes everything the feature stores for a network: today, its Garage Key, whatever the entry holds.
///
/// Destructive: the robots of the key are lost unless the user kept a copy of it, so call it only on the user's explicit confirmation.
/// It is also the only way out of a key that cannot be read.
/// When the feature stores the state of its robots, that state is to be erased here first and the key last, so that a failure leaves the key.
final class DeleteGarageKeyUsecase {
  final GarageKeyRepository _repository;

  const DeleteGarageKeyUsecase(this._repository);

  @useResult
  Future<Result<void, P2pFailure>> execute(RobosatsNetwork network) =>
      _repository.delete(network);
}
