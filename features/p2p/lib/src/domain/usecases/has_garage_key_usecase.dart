import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';

/// Tells whether a usable Garage Key is stored for a network.
///
/// `false` is the only answer after which a screen may offer to generate or import a key.
/// A failure is never an absence: after [GarageKeyLockedFailure], ask to unlock the device and try again; after [GarageKeyUnreadableFailure] that persists, or [GarageKeyUnusableFailure], the only way out is `DeleteGarageKeyUsecase`.
final class HasGarageKeyUsecase {
  final GarageKeyRepository _repository;

  const HasGarageKeyUsecase(this._repository);

  @useResult
  Future<Result<bool, P2pFailure>> execute(RobosatsNetwork network) =>
      _repository.exists(network);
}
