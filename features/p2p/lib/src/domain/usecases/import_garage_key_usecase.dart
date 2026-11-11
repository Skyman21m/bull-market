import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show GarageKey, RobosatsNetwork;

import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';

/// Stores the Garage Key the user restores from the copy they kept, for a network that has none.
///
/// Call it only from an action of the user, and only after `HasGarageKeyUsecase` said that no key is stored.
/// A stored key is never replaced: a slot that holds anything is a [GarageKeyAlreadyStoredFailure], which the caller reports and never works around.
final class ImportGarageKeyUsecase {
  final GarageKeyRepository _repository;

  const ImportGarageKeyUsecase(this._repository);

  /// Parses [text], the `robo1…` form of the key, and stores it.
  ///
  /// Text that is not a Garage Key is a [GarageKeyInvalidFailure] that carries none of it, and nothing reaches the vault.
  @useResult
  Future<Result<void, P2pFailure>> execute(
    RobosatsNetwork network, {
    required String text,
  }) async => switch (GarageKey.parse(text)) {
    Ok(value: final key) => await _repository.import(network, key),
    Err(:final failure) => Err(GarageKeyInvalidFailure(failure)),
  };
}
