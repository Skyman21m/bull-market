import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';

/// Draws a new Garage Key for a network that has none, on the user's explicit request.
///
/// Call it only from an action of the user, never at startup, from a constructor or in the background, and only after `HasGarageKeyUsecase` said that no key is stored.
/// A stored key is never replaced: a slot that holds anything is a [GarageKeyAlreadyStoredFailure], which the caller reports and never works around.
final class GenerateGarageKeyUsecase {
  final GarageKeyRepository _repository;

  const GenerateGarageKeyUsecase(this._repository);

  @useResult
  Future<Result<void, P2pFailure>> execute(RobosatsNetwork network) =>
      _repository.create(network);
}
