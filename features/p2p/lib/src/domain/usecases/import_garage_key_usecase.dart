import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show GarageKey, RobosatsNetwork;

import '../garage_key_fingerprint.dart';
import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';
import '../repositories/robot_binding_repository.dart';

/// Stores the Garage Key the user restores from the copy they kept, for a network that has none, and records that its history is unknown.
///
/// Call it only from an action of the user, and only after `HasGarageKeyUsecase` said that no key is stored.
/// A stored key is never replaced: a slot that holds anything is a [GarageKeyAlreadyStoredFailure], which the caller reports and never works around.
final class ImportGarageKeyUsecase {
  final GarageKeyRepository _repository;
  final RobotBindingRepository _bindings;

  const ImportGarageKeyUsecase(this._repository, this._bindings);

  /// Parses [text], the `robo1…` form of the key, records it as imported, then stores it.
  ///
  /// Text that is not a Garage Key is a [GarageKeyInvalidFailure] that carries none of it, and nothing reaches the vault.
  /// The robots of an imported key may already live on coordinators, from another device: the record keeps any of them without a binding from being taken for a new one, even when this device drew the same key before.
  /// So the record comes first: a record that cannot be written is a [P2pStorageFailure], and the key is not stored.
  /// A record whose key the vault then refuses, as when a key is already stored, only restricts that key.
  @useResult
  Future<Result<void, P2pFailure>> execute(
    RobosatsNetwork network, {
    required String text,
  }) async {
    final GarageKey key;
    switch (GarageKey.parse(text)) {
      case Ok(:final value):
        key = value;
      case Err(:final failure):
        return Err(GarageKeyInvalidFailure(failure));
    }
    final GarageKeyFingerprint fingerprint;
    switch (GarageKeyFingerprint.of(key)) {
      case Ok(:final value):
        fingerprint = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (await _bindings.recordImportedKey(network, fingerprint) case Err(
      :final failure,
    )) {
      return Err(failure);
    }
    return _repository.import(network, key);
  }
}
