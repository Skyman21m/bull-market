import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../network_garage_key.dart';
import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';

/// The Garage Key stored for a network, with that network, for the screens of the Garage: `GarageKeyView` shows it for backup, and the account navigator derives robot number N from it.
///
/// Call it when the user opens the Garage, or right after a key was generated or imported, never in the background.
/// No key is a [GarageKeyMissingFailure], the only failure after which a screen may offer to generate or import one; after any other, follow `HasGarageKeyUsecase`.
/// Hold the key no longer than the screen that uses it.
final class ReadGarageKeyUsecase {
  final GarageKeyRepository _repository;

  const ReadGarageKeyUsecase(this._repository);

  @useResult
  Future<Result<NetworkGarageKey, P2pFailure>> execute(
    RobosatsNetwork network,
  ) => _repository.read(network);
}
