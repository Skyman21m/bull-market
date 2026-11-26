import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show GarageKey, RobosatsNetwork;
import 'package:secrets/secrets.dart'
    show
        GarageKeyAlreadyExistsFailure,
        GarageKeyCorruptFailure,
        GarageKeyMaterial,
        GarageKeySlot,
        GarageKeys,
        KeystoreLockedFailure,
        SecretFailure,
        SecretNotFoundFailure;

import '../../public/p2p_garage_key_port.dart';
import '../domain/garage_keyring.dart';
import '../domain/network_garage_key.dart';
import '../domain/p2p_failure.dart';
import '../domain/repositories/garage_key_book_repository.dart';
import '../domain/repositories/garage_key_repository.dart';
import '../domain/robot_binding.dart';

/// The Garage Keys of P2P (#81, design note `docs/design/garage-key-from-the-words.md`): the keys of the default wallet's words, through the shell's port, and, until the book is emptied once, the key drawn at random that the vault keeps in the slot of each network, through the handle the shell passes to the feature.
///
/// The only class of the feature that reads the bytes of a key: the custody gate allows `GarageKeyMaterial.bytes` and `GarageKey.revealBytes` here and nowhere else.
/// It turns the bytes into a [GarageKey], and a [GarageKey] into bytes to store it, and never lets the bytes out: its public members are the methods of [GarageKeyRepository], which `test/garage_key_surface_test.dart` pins.
/// A key leaves it only as a [NetworkGarageKey] tagged with its network (and its index, for a key of the words), and so does every robot derived from it.
/// A key of the words is derived at each call, never stored, and given out only once its fingerprint matches the one recorded for its index ([GarageKeyBookRepository]); when the words cannot give it, the call fails, and nothing ever draws a key in its place.
/// The copy it makes for an import is zeroed when the vault returns; the copies inside the vault's material and inside a [GarageKey] cannot be, and are dropped with the call.
/// It logs nothing, and the failures it returns carry no text of the vault.
final class GarageKeyRepositoryImpl implements GarageKeyRepository {
  final GarageKeys _garageKeys;
  final P2pGarageKeyPort _words;
  final GarageKeyBookRepository _book;

  const GarageKeyRepositoryImpl(this._garageKeys, this._words, this._book);

  @override
  Future<Result<GarageKeyring, P2pFailure>> keyring(
    RobosatsNetwork network,
  ) async {
    switch (await _switched()) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: false):
        return const Ok(LegacyGarageKeyring());
      case Ok(value: true):
    }
    switch (await _book.activatedKeys(network)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: [..., final highest]):
        return Ok(DerivedGarageKeyring(highest.index));
      case Ok(value: []):
    }
    // The first visit on this network: key 0, recorded with its fingerprint as a key drawn here.
    final NetworkGarageKey first;
    switch (await _derive(network, 0)) {
      case Ok(:final value):
        first = value;
      case Err(:final failure):
        return Err(failure);
    }
    switch (first.fingerprint) {
      case Ok(:final value):
        if (await _book.activate(network, 0, value) case Err(:final failure)) {
          return Err(failure);
        }
      case Err(:final failure):
        return Err(failure);
    }
    // Written by this call or by another one meanwhile: what is recorded now decides.
    return switch (await _book.activatedKeys(network)) {
      Ok(value: [..., final highest]) => Ok(
        DerivedGarageKeyring(highest.index),
      ),
      Ok() => const Err(P2pStorageFailure()),
      Err(:final failure) => Err(failure),
    };
  }

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> read(
    RobosatsNetwork network,
  ) async => switch (await keyring(network)) {
    Ok(value: LegacyGarageKeyring()) => await _readSlot(network),
    Ok(value: DerivedGarageKeyring(:final highest)) => await derived(
      network,
      highest,
    ),
    Err(:final failure) => Err(failure),
  };

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> derived(
    RobosatsNetwork network,
    int index,
  ) async {
    switch (await _switched()) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: false):
        return const Err(GarageKeySwitchPendingFailure());
      case Ok(value: true):
    }
    final ActivatedGarageKey activated;
    switch (await _book.activatedKeys(network)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        if (index < 0 || index >= value.length) {
          return const Err(GarageKeyMissingFailure());
        }
        activated = value[index];
    }
    final NetworkGarageKey key;
    switch (await _derive(network, index)) {
      case Ok(:final value):
        key = value;
      case Err(:final failure):
        return Err(failure);
    }
    // The words must give back the very key recorded at this index: other words, or another default wallet, give another key, whose robots are never mixed with these.
    return switch (key.fingerprint) {
      Ok(:final value) when value == activated.fingerprint => Ok(key),
      Ok() => const Err(GarageKeyMismatchFailure()),
      Err(:final failure) => Err(failure),
    };
  }

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> forNewTrade(
    RobosatsNetwork network,
  ) async => switch (await keyring(network)) {
    Ok(value: LegacyGarageKeyring()) => const Err(
      GarageKeySwitchPendingFailure(),
    ),
    // The highest key, never an earlier one: the rule « never a new trade on an earlier key ».
    Ok(value: DerivedGarageKeyring(:final highest)) => await derived(
      network,
      highest,
    ),
    Err(:final failure) => Err(failure),
  };

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> ofSlot(RobotSlot slot) async {
    final network = slot.network;
    switch (await _switched()) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: false):
        switch (await _readSlot(network)) {
          case Ok(:final value):
            // The key drawn at random of the slot, when the robot is one of its own.
            return switch (value.fingerprint) {
              Ok(value: final fingerprint)
                  when fingerprint == slot.keyFingerprint =>
                Ok(value),
              _ => const Err(TradeKeyMissingFailure()),
            };
          case Err(failure: GarageKeyMissingFailure()):
            return const Err(TradeKeyMissingFailure());
          case Err(:final failure):
            return Err(failure);
        }
      case Ok(value: true):
    }
    switch (await _book.activatedKeys(network)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        for (final activated in value) {
          if (activated.fingerprint == slot.keyFingerprint) {
            return derived(network, activated.index);
          }
        }
        return const Err(TradeKeyMissingFailure());
    }
  }

  @override
  Future<Result<int, P2pFailure>> activateNext(
    RobosatsNetwork network, {
    required int after,
  }) async {
    if (after >= 0x7fffffff) return const Err(GarageKeyLastIndexFailure());
    switch (await keyring(network)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: LegacyGarageKeyring()):
        return const Err(GarageKeySwitchPendingFailure());
      case Ok(value: DerivedGarageKeyring(:final highest)):
        if (highest != after) return const Err(GarageKeyMissingFailure());
    }
    final next = after + 1;
    final NetworkGarageKey key;
    switch (await _derive(network, next)) {
      case Ok(:final value):
        key = value;
      case Err(:final failure):
        return Err(failure);
    }
    switch (key.fingerprint) {
      case Ok(:final value):
        return switch (await _book.activate(network, next, value)) {
          Ok(value: true) => Ok(next),
          // Another call activated it, or a later one, first: nothing written here.
          Ok(value: false) => const Err(GarageKeyMissingFailure()),
          Err(:final failure) => Err(failure),
        };
      case Err(:final failure):
        return Err(failure);
    }
  }

  @override
  Future<Result<bool, P2pFailure>> exists(RobosatsNetwork network) async =>
      switch (await read(network)) {
        Ok() => const Ok(true),
        Err(failure: GarageKeyMissingFailure()) => const Ok(false),
        Err(:final failure) => Err(failure),
      };

  @override
  Future<Result<NetworkRobot, P2pFailure>> firstUsableRobot(
    RobosatsNetwork network,
  ) async => switch (await read(network)) {
    Ok(value: final key) => key.firstUsableRobot(0),
    Err(:final failure) => Err(failure),
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

  /// Whether the book is on the keys of the words, after finishing the one-time switch where the database left it: at `vaultPending`, the vault's two slots are deleted, then the switch is marked `derived`; a delete that fails leaves the switch where it is, for the next call.
  ///
  /// `false` while a trade of the key drawn at random is in progress (`legacy`), and for `emptying`, which only a failed opening leaves.
  Future<Result<bool, P2pFailure>> _switched() async {
    switch (await _book.switchState()) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: GarageSwitchState.derived):
        return const Ok(true);
      case Ok(value: GarageSwitchState.legacy || GarageSwitchState.emptying):
        return const Ok(false);
      case Ok(value: GarageSwitchState.vaultPending):
    }
    for (final slot in GarageKeySlot.values) {
      switch (await _garageKeys.delete(slot: slot)) {
        case Ok() || Err(failure: SecretNotFoundFailure()):
          continue;
        case Err(failure: KeystoreLockedFailure()):
          return const Err(GarageKeyLockedFailure());
        case Err():
          return const Err(GarageKeyNotDeletedFailure());
      }
    }
    return switch (await _book.markDerived()) {
      Ok() => const Ok(true),
      Err(:final failure) => Err(failure),
    };
  }

  /// The key the words give at [index] on [network], tagged with both, or why they cannot give it; never a key drawn at random.
  Future<Result<NetworkGarageKey, P2pFailure>> _derive(
    RobosatsNetwork network,
    int index,
  ) async => switch (await _words.garageKey(network, index: index)) {
    Ok(value: final material) => Ok(_keyOf(network, material, index: index)),
    Err(:final failure) => Err(switch (failure.reason) {
      P2pGarageKeyRefusalReason.noDefaultWallet =>
        const GarageKeyNoWalletFailure(),
      P2pGarageKeyRefusalReason.passphrase =>
        const GarageKeyPassphraseFailure(),
      P2pGarageKeyRefusalReason.noWords => const GarageKeyNoWordsFailure(),
      P2pGarageKeyRefusalReason.locked => const GarageKeyLockedFailure(),
      P2pGarageKeyRefusalReason.unreadable =>
        const GarageKeyUnreadableFailure(),
    }),
  };

  /// The key drawn at random before #81 that the vault keeps for [network], while the switch waits.
  Future<Result<NetworkGarageKey, P2pFailure>> _readSlot(
    RobosatsNetwork network,
  ) async => switch (await _garageKeys.read(slot: _slotOf(network))) {
    Err(:final failure) => Err(_readFailureOf(failure)),
    Ok(value: final material) => Ok(_keyOf(network, material)),
  };

  /// The key the bytes of [material] make, tagged with [network] and, for a key of the words, its [index].
  ///
  /// The vault and the port hand out exactly 32 bytes, which `fromBytes` accepts, so a refusal is a bug between the packages (AGENTS.md, rule 11).
  /// It is never reported as a failure of the key, which would advise the user to act on a key that may be good.
  static NetworkGarageKey _keyOf(
    RobosatsNetwork network,
    GarageKeyMaterial material, {
    int? index,
  }) => switch (GarageKey.fromBytes(material.bytes)) {
    Ok(:final value) => NetworkGarageKey(network, value, index: index),
    Err() => throw StateError(
      'GarageKey.fromBytes refused the bytes handed out',
    ),
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

  /// What a failed import means for the screens.
  ///
  /// Any other failure of the vault is the vault's own category for a write that failed.
  static P2pFailure _writeFailureOf(SecretFailure failure) => switch (failure) {
    GarageKeyAlreadyExistsFailure() => const GarageKeyAlreadyStoredFailure(),
    KeystoreLockedFailure() => const GarageKeyLockedFailure(),
    _ => const GarageKeyNotSavedFailure(),
  };
}
