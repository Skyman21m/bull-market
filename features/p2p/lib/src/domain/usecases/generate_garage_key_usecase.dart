import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../network_garage_key.dart';
import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';
import '../repositories/robot_binding_repository.dart';
import '../robot_binding.dart';

/// Draws a new Garage Key for a network that has none, on the user's explicit request, and records that this device drew it.
///
/// Call it only from an action of the user, never at startup, from a constructor or in the background, and only after `HasGarageKeyUsecase` said that no key is stored.
/// A stored key is never replaced: a slot that holds anything is a [GarageKeyAlreadyStoredFailure], which the caller reports and never works around.
final class GenerateGarageKeyUsecase {
  final GarageKeyRepository _repository;
  final RobotBindingRepository _bindings;

  const GenerateGarageKeyUsecase(this._repository, this._bindings);

  /// Draws the key, then records the fingerprint of the key the vault drew, as the repository hands it back, as drawn on this device: only such a key lets its robots be bound to a coordinator for the first time.
  ///
  /// Nothing is read back from the slot in between, so the record is about the key this draw made and no other.
  /// The record comes after the key, whose bytes the vault draws, and is tried twice while the drawn key is still in hand, since nothing can record it afterwards: when neither write succeeds, the key is stored all the same and the result is `Ok(GarageKeyHistory.unknown)`, so the caller learns that the robots of this key will be refused; `Ok(GarageKeyHistory.drawnHere)` otherwise.
  /// The Garage tells the user of a key of unknown history right after the draw, on the robot step and the profile, and its delete asks the PIN.
  /// The key itself is not handed out: the screen that shows it for backup reads it.
  @useResult
  Future<Result<GarageKeyHistory, P2pFailure>> execute(
    RobosatsNetwork network,
  ) async => switch (await _repository.create(network)) {
    Ok(value: final key) => Ok(await _record(key)),
    Err(:final failure) => Err(failure),
  };

  Future<GarageKeyHistory> _record(NetworkGarageKey key) async {
    if (key.fingerprint case Ok(value: final fingerprint)) {
      // A second try for a write that failed for a moment, such as a busy database.
      for (var attempt = 0; attempt < 2; attempt++) {
        if (await _bindings.recordGeneratedKey(key.network, fingerprint)
            case Ok()) {
          return GarageKeyHistory.drawnHere;
        }
      }
    }
    return GarageKeyHistory.unknown;
  }
}
