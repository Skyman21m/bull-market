import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';
import '../repositories/robot_binding_repository.dart';

/// Draws a new Garage Key for a network that has none, on the user's explicit request, and records that this device drew it.
///
/// Call it only from an action of the user, never at startup, from a constructor or in the background, and only after `HasGarageKeyUsecase` said that no key is stored.
/// A stored key is never replaced: a slot that holds anything is a [GarageKeyAlreadyStoredFailure], which the caller reports and never works around.
final class GenerateGarageKeyUsecase {
  final GarageKeyRepository _repository;
  final RobotBindingRepository _bindings;

  const GenerateGarageKeyUsecase(this._repository, this._bindings);

  /// Draws the key, then reads it back to record its fingerprint as drawn on this device: only such a key lets its robots be bound to a coordinator for the first time.
  ///
  /// The record comes after the key, whose bytes the vault draws: if it cannot be read back or recorded, the key stays stored with an unknown history, which only restricts its robots, and the result is still [Ok], since the key exists.
  @useResult
  Future<Result<void, P2pFailure>> execute(RobosatsNetwork network) async {
    if (await _repository.create(network) case Err(:final failure)) {
      return Err(failure);
    }
    await _recordDrawn(network);
    return const Ok(null);
  }

  Future<void> _recordDrawn(RobosatsNetwork network) async {
    if (await _repository.read(network) case Ok(value: final key)) {
      if (key.fingerprint case Ok(value: final fingerprint)) {
        switch (await _bindings.recordGeneratedKey(network, fingerprint)) {
          case Ok():
          // Left unrecorded: an unknown history, which only restricts.
          case Err():
        }
      }
    }
  }
}
