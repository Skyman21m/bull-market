import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show GarageKey, RobosatsNetwork;

import '../garage_key_fingerprint.dart';
import '../p2p_failure.dart';
import '../repositories/garage_key_repository.dart';
import '../repositories/robot_binding_repository.dart';

/// Stores the Garage Key the user pastes in « Robot recovery », for a network whose vault slot is empty, as the external Garage Key of that network (#81), and records that it was imported; it trades as any other key (decided on 2026-11-26, #81).
///
/// Call it only from an action of the user, and only when the Garage shows no external key for the network.
/// A stored key is never replaced: a slot that holds anything is a [GarageKeyAlreadyStoredFailure], which the caller reports and never works around.
final class ImportGarageKeyUsecase {
  final GarageKeyRepository _repository;
  final RobotBindingRepository _bindings;

  const ImportGarageKeyUsecase(this._repository, this._bindings);

  /// Parses [text], the `robo1…` form of the key, records it as imported, then stores it.
  ///
  /// Text that is not a Garage Key is a [GarageKeyInvalidFailure] that carries none of it, and nothing reaches the vault.
  /// A key that is one of the internal Garage Keys activated on [network] is a [GarageKeyIsInternalFailure], and nothing is recorded or stored: one key is never both internal and external.
  /// The robots of an imported key may already live on coordinators, from another device: the record says so, and a robot of it bound to a coordinator for « Select Host » asks « Robots from elsewhere » first; a new trade relies on the coordinator's refusal of a robot it already knows.
  /// So the record comes first: a record that cannot be written is a [P2pStorageFailure], and the key is not stored.
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
    switch (await _repository.internalIndexOf(network, fingerprint)) {
      case Ok(value: final index?):
        return Err(GarageKeyIsInternalFailure(index));
      case Ok():
        break;
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
