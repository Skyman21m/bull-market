import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show GarageKey, GarageRobot, RobosatsNetwork;
import 'package:secrets/secrets.dart'
    show
        GarageKeyAlreadyExistsFailure,
        GarageKeyCorruptFailure,
        GarageKeySlot,
        GarageKeys,
        KeystoreLockedFailure,
        SecretFailure,
        SecretNotFoundFailure;

import '../domain/p2p_failure.dart';
import '../domain/repositories/garage_key_repository.dart';

/// The Garage Keys of P2P in the vault of `package:secrets`, one per network, through the handle the shell passes to the feature.
///
/// The only class of the feature that reads the bytes of a stored key: the custody gate allows `GarageKeyMaterial.bytes` and `GarageKey.revealBytes` here and nowhere else.
/// It turns the stored bytes into a [GarageKey] to derive a robot, and a [GarageKey] into bytes to store it, and today lets neither out: its public members are the methods of [GarageKeyRepository], which `test/garage_key_surface_test.dart` pins.
/// The copy it makes for an import is zeroed when the vault returns; the copies inside the vault's material and inside a [GarageKey] cannot be, and are dropped with the call.
/// It logs nothing, and the failures it returns carry no text of the vault.
final class GarageKeyRepositoryImpl implements GarageKeyRepository {
  final GarageKeys _garageKeys;

  const GarageKeyRepositoryImpl(this._garageKeys);

  @override
  Future<Result<void, P2pFailure>> create(RobosatsNetwork network) async =>
      switch (await _garageKeys.create(slot: _slotOf(network))) {
        Ok() => const Ok(null),
        Err(:final failure) => Err(_writeFailureOf(failure)),
      };

  @override
  Future<Result<void, P2pFailure>> import(
    RobosatsNetwork network,
    GarageKey key,
  ) async {
    final bytes = key.revealBytes();
    try {
      return switch (await _garageKeys.import(
        slot: _slotOf(network),
        bytes: bytes,
      )) {
        Ok() => const Ok(null),
        Err(:final failure) => Err(_writeFailureOf(failure)),
      };
    } finally {
      // Zeroed only once the vault is done with the call, so that the vault can never store a zeroed buffer.
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  @override
  Future<Result<bool, P2pFailure>> exists(RobosatsNetwork network) async =>
      switch (await _garageKeys.read(slot: _slotOf(network))) {
        Ok() => const Ok(true),
        Err(failure: SecretNotFoundFailure()) => const Ok(false),
        Err(:final failure) => Err(_readFailureOf(failure)),
      };

  @override
  Future<Result<GarageRobot, P2pFailure>> firstUsableRobot(
    RobosatsNetwork network,
  ) async {
    switch (await _garageKeys.read(slot: _slotOf(network))) {
      case Err(:final failure):
        return Err(_readFailureOf(failure));
      case Ok(value: final material):
        final key = switch (GarageKey.fromBytes(material.bytes)) {
          Ok(:final value) => value,
          // The vault hands out exactly 32 bytes, which `fromBytes` accepts, so a refusal is a bug between the two packages (AGENTS.md, rule 11).
          // It is never reported as a failure of the stored key, which would advise the user to delete a key that may be good.
          Err() => throw StateError(
            'GarageKey.fromBytes refused the bytes the vault handed out',
          ),
        };
        return switch (key.firstUsableRobot(0)) {
          Ok(value: final robot) => Ok(robot),
          Err() => const Err(GarageRobotUnavailableFailure()),
        };
    }
  }

  @override
  Future<Result<void, P2pFailure>> delete(RobosatsNetwork network) async =>
      switch (await _garageKeys.delete(slot: _slotOf(network))) {
        Ok() => const Ok(null),
        Err(failure: KeystoreLockedFailure()) => const Err(
          GarageKeyLockedFailure(),
        ),
        Err() => const Err(GarageKeyNotDeletedFailure()),
      };

  /// Each network has its own slot, and an operation never reaches the slot of another network.
  static GarageKeySlot _slotOf(RobosatsNetwork network) => switch (network) {
    RobosatsNetwork.mainnet => GarageKeySlot.mainnet,
    RobosatsNetwork.testnet => GarageKeySlot.testnet,
  };

  /// What a failed read means for the screens.
  ///
  /// Any other failure of the vault is the vault's own category for a read that failed.
  static P2pFailure _readFailureOf(SecretFailure failure) => switch (failure) {
    SecretNotFoundFailure() => const GarageKeyMissingFailure(),
    KeystoreLockedFailure() => const GarageKeyLockedFailure(),
    GarageKeyCorruptFailure() => const GarageKeyUnusableFailure(),
    _ => const GarageKeyUnreadableFailure(),
  };

  /// What a failed create or import means for the screens.
  ///
  /// Any other failure of the vault is the vault's own category for a write that failed.
  static P2pFailure _writeFailureOf(SecretFailure failure) => switch (failure) {
    GarageKeyAlreadyExistsFailure() => const GarageKeyAlreadyStoredFailure(),
    KeystoreLockedFailure() => const GarageKeyLockedFailure(),
    _ => const GarageKeyNotSavedFailure(),
  };
}
