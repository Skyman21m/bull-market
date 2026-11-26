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
import '../domain/garage_key_fingerprint.dart';
import '../domain/garage_keyring.dart';
import '../domain/network_garage_key.dart';
import '../domain/p2p_failure.dart';
import '../domain/repositories/garage_key_book_repository.dart';
import '../domain/repositories/garage_key_repository.dart';
import '../domain/robot_binding.dart';

/// The Garage Keys of P2P (#81, design note `docs/design/garage-key-from-the-words.md`): the keys of the default wallet's words, through the shell's port, and the external key, the one the vault keeps in the slot of each network (drawn at random on this device before #81, or pasted), through the handle the shell passes to the feature.
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
    final List<ActivatedGarageKey> keys;
    switch (await _activated(network)) {
      case Ok(:final value):
        keys = value;
      case Err(:final failure):
        return Err(failure);
    }
    GarageKeyFingerprint? external;
    P2pFailure? externalFailure;
    switch (await _readSlot(network)) {
      case Ok(:final value):
        switch (value.fingerprint) {
          case Ok(value: final fingerprint):
            external = fingerprint;
          case Err(:final failure):
            externalFailure = failure;
        }
      case Err(failure: GarageKeyMissingFailure()):
        break;
      // A slot that cannot be read may hold a key with trades: its position stays, so that the user may try again or remove it, and it is never taken for an empty slot.
      case Err(:final failure):
        externalFailure = failure;
    }
    final hasExternal = external != null || externalFailure != null;
    final highest = keys.last.index;
    final GarageKeySelection selected;
    switch (await _book.selected(network)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: SelectedExternalKey()) when hasExternal:
        selected = const SelectedExternalKey();
      case Ok(value: SelectedWordsKey(:final index)) when index <= highest:
        selected = SelectedWordsKey(index);
      case Ok(:final value):
        // The first opening (nothing recorded): the user stays on the key the vault kept, the external key, when there is one, otherwise key 0. An external key selected that the vault no longer holds: the highest key of the words.
        selected = value == null
            ? (hasExternal
                  ? const SelectedExternalKey()
                  : const SelectedWordsKey(0))
            : SelectedWordsKey(highest);
        if (await _book.select(network, selected) case Err(:final failure)) {
          return Err(failure);
        }
    }
    return Ok(
      GarageKeyring(
        highest: highest,
        selected: selected,
        fingerprints: [for (final key in keys) key.fingerprint],
        external: external,
        externalFailure: externalFailure,
      ),
    );
  }

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> read(
    RobosatsNetwork network,
  ) async => switch (await keyring(network)) {
    Ok(value: GarageKeyring(selected: SelectedWordsKey(:final index))) =>
      await derived(network, index),
    Ok(value: GarageKeyring(selected: SelectedExternalKey())) =>
      await _readSlot(network),
    Err(:final failure) => Err(failure),
  };

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> derived(
    RobosatsNetwork network,
    int index,
  ) async {
    final ActivatedGarageKey activated;
    switch (await _activated(network)) {
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
  ) async {
    // The key selected in the Garage Key card, whatever it is (the owner's decisions of 2026-11-26), and no other; read without the vault when it is a key of the words.
    switch (await _book.selected(network)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: SelectedWordsKey(:final index)):
        return derived(network, index);
      case Ok(value: SelectedExternalKey()):
        return _readSlot(network);
      case Ok(value: null):
        return read(network);
    }
  }

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> ofSlot(RobotSlot slot) async {
    final network = slot.network;
    switch (await _book.activatedKeys(network)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        for (final activated in value) {
          if (activated.fingerprint == slot.keyFingerprint) {
            return derived(network, activated.index);
          }
        }
    }
    // Not a key of the words: the external key, when the robot is one of its own.
    switch (await _readSlot(network)) {
      case Ok(:final value):
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
  }

  @override
  Future<Result<int, P2pFailure>> activateNext(
    RobosatsNetwork network, {
    required int after,
  }) async {
    if (after >= 0x7fffffff) return const Err(GarageKeyLastIndexFailure());
    final List<ActivatedGarageKey> keys;
    switch (await _activated(network)) {
      case Ok(:final value):
        keys = value;
      case Err(:final failure):
        return Err(failure);
    }
    // After the highest key of the words, whichever key is selected; the external key does not count.
    if (keys.last.index != after) return const Err(GarageKeyMissingFailure());
    // The words must still give back the highest key recorded: a key after another wallet's is never activated.
    if (await derived(network, after) case Err(:final failure)) {
      return Err(failure);
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
          // The new key is selected at once: new trades take it.
          Ok(value: true) => switch (await _book.select(
            network,
            SelectedWordsKey(next),
          )) {
            Ok() => Ok(next),
            Err(:final failure) => Err(failure),
          },
          // Another call activated it, or a later one, first: nothing written here.
          Ok(value: false) => const Err(GarageKeyMissingFailure()),
          Err(:final failure) => Err(failure),
        };
      case Err(:final failure):
        return Err(failure);
    }
  }

  @override
  Future<Result<void, P2pFailure>> select(
    RobosatsNetwork network,
    GarageKeySelection selection,
  ) async {
    // The external key only when the vault keeps one, readable or not: a key that cannot be read is selected so that the Garage says why, and offers to try again or to remove it.
    if (selection is SelectedExternalKey) {
      if (await _readSlot(network) case Err(
        failure: final GarageKeyMissingFailure failure,
      )) {
        return Err(failure);
      }
    }
    return switch (await _book.select(network, selection)) {
      Ok(value: true) => const Ok(null),
      Ok(value: false) => const Err(GarageKeyMissingFailure()),
      Err(:final failure) => Err(failure),
    };
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
      switch (await _garageKeys.import(slot: _slotOf(network), bytes: bytes)) {
        case Ok():
          break;
        case Err(:final failure):
          return Err(_writeFailureOf(failure));
      }
    } finally {
      // Zeroed only once the vault is done with the call, so that the vault can never store a zeroed buffer.
      bytes.fillRange(0, bytes.length, 0);
    }
    // The key pasted is shown at once, as the official client shows the key it recovers. It is stored whatever the book says: a selection that cannot be written leaves the selection as it was, and the Garage, reading the keys again, says the database cannot be read.
    switch (await _book.select(network, const SelectedExternalKey())) {
      case Ok() || Err():
        return const Ok(null);
    }
  }

  @override
  Future<Result<void, P2pFailure>> delete(RobosatsNetwork network) async {
    switch (await _garageKeys.delete(slot: _slotOf(network))) {
      case Ok():
        break;
      case Err(failure: KeystoreLockedFailure()):
        return const Err(GarageKeyLockedFailure());
      case Err():
        return const Err(GarageKeyNotDeletedFailure());
    }
    // The external key gone, the highest key of the words is selected when the external key was.
    if (await _book.selected(network) case Ok(value: SelectedExternalKey())) {
      if (await _activated(network) case Ok(value: [..., final highest])) {
        if (await _book.select(network, SelectedWordsKey(highest.index))
            case Err(:final failure)) {
          return Err(failure);
        }
      }
    }
    return const Ok(null);
  }

  /// The keys of the words activated on [network], key 0 activated first when none is, recorded with its fingerprint as a key drawn here: so at the first opening of the Garage, key 0 is there.
  Future<Result<List<ActivatedGarageKey>, P2pFailure>> _activated(
    RobosatsNetwork network,
  ) async {
    switch (await _book.activatedKeys(network)) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value) when value.isNotEmpty:
        return Ok(value);
      case Ok():
    }
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
      Ok(:final value) when value.isNotEmpty => Ok(value),
      Ok() => const Err(P2pStorageFailure()),
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

  /// The external key, the one the vault keeps in the slot of [network]: drawn at random on this device before #81, or pasted from elsewhere.
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
