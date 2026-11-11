import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart' as convert;
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:secrets/src/data/boundary.dart';
import 'package:secrets/src/data/fss_datasource.dart';
import 'package:secrets/src/data/models/key_model.dart';
import 'package:secrets/src/domain/domain.dart';

/// The RoboSats Garage Keys this package keeps for the P2P feature, one per network.
///
/// A repository by role, like `DatabaseKeyRepository`, and as separate from `SecretRepository`: a Garage Key is 32 random bytes, never derived from a seed, never stored with one and never part of a wallet backup. So this file reads no seed and imports nothing from `crypto/`, which the invariant suite checks.
///
/// Stored under `com.bullbitcoin.secrets/garage/p2p/<slot>` in the module-key envelope. A key is never replaced: creating or importing one needs an empty slot, settled under the lock (see [FlutterSecureStorageDatasource.storeModuleKeyIfAbsent]), and a corrupt one is refused and kept until the user deletes it.
class GarageKeyRepository {
  static const _kind = KeyKind.garage;

  /// The package segment of the storage key: the one module these keys are kept for. Frozen.
  static const _package = 'p2p';

  final _source = FlutterSecureStorageDatasource();

  @internal
  GarageKeyRepository();

  /// The name segment of the storage key for [slot]. Frozen: a renamed slot would hide the stored key.
  static String _nameOf(GarageKeySlot slot) => switch (slot) {
    GarageKeySlot.mainnet => 'mainnet',
    GarageKeySlot.testnet => 'testnet',
  };

  /// Draws a new key and stores it in an empty [slot].
  ///
  /// The bytes are drawn under the lock, only once the slot is known to be empty, so two calls give one key and a refused call draws nothing.
  Future<Result<GarageKeyMaterial, SecretFailure>> create({
    required GarageKeySlot slot,
  }) => boundary(() async {
    final model = await _source.storeModuleKeyIfAbsent(
      kind: _kind,
      package: _package,
      name: _nameOf(slot),
      bytesHex: () =>
          convert.hex.encode(GarageKeyMaterial(_randomBytes()).bytes),
    );
    return _materialOf(model);
  }, orElse: StoreSecretFailure.new);

  /// Stores [material], a key the user restores, in an empty [slot].
  Future<Result<GarageKeyMaterial, SecretFailure>> import({
    required GarageKeySlot slot,
    required GarageKeyMaterial material,
  }) => boundary(() async {
    final model = await _source.storeModuleKeyIfAbsent(
      kind: _kind,
      package: _package,
      name: _nameOf(slot),
      bytesHex: () => convert.hex.encode(material.bytes),
    );
    return _materialOf(model);
  }, orElse: StoreSecretFailure.new);

  /// The key in [slot], **never creating one**: a miss is a [SecretNotFoundFailure] after the full retry budget.
  Future<Result<GarageKeyMaterial, SecretFailure>> read({
    required GarageKeySlot slot,
  }) async {
    final read = await boundary(
      () => _source.fetchModuleKey(
        kind: _kind,
        package: _package,
        name: _nameOf(slot),
      ),
      orElse: FetchSecretFailure.new,
    );
    return switch (read) {
      Err(:final failure) => Err(failure),
      Ok(value: null) => const Err(
        SecretNotFoundFailure('no Garage Key in that slot'),
      ),
      Ok(value: final KeyModel model) => Ok(_materialOf(model)),
    };
  }

  /// Deletes the entry in [slot], whatever it holds, a corrupt one included: the user's way out of [GarageKeyCorruptFailure].
  Future<Result<void, SecretFailure>> delete({required GarageKeySlot slot}) =>
      boundary(
        () => _source.deleteModuleKey(
          kind: _kind,
          package: _package,
          name: _nameOf(slot),
        ),
        orElse: TrashSecretFailure.new,
      );

  /// `KeyModel.fromJson` has checked 64 hex characters, so this cannot fail on stored input.
  static GarageKeyMaterial _materialOf(KeyModel model) =>
      GarageKeyMaterial(Uint8List.fromList(convert.hex.decode(model.bytesHex)));

  static final _random = Random.secure();

  static Uint8List _randomBytes() => Uint8List.fromList(
    List<int>.generate(
      GarageKeyMaterial.lengthInBytes,
      // The platform CSPRNG: /dev/urandom on Android and Linux,
      // SecRandomCopyBytes on Apple.
      (_) => _random.nextInt(256),
    ),
  );
}
