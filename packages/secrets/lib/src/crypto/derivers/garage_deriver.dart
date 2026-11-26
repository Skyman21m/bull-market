import 'dart:typed_data';

import 'package:bip85_entropy/bip85_entropy.dart' as bip85;
import 'package:meta/meta.dart';
import 'package:secrets/src/crypto/derivers/bip85_deriver.dart';
import 'package:secrets/src/crypto/exceptions.dart';
import 'package:secrets/src/domain/domain.dart';

/// The RoboSats Garage Keys of a secret, as BIP85 children. Reached as `Deriver.garage`.
///
/// A Garage Key is the first 32 bytes of the 64 bytes of BIP85 entropy at `m/83696968'/82796679'/0'/{network}'/{index}'`: BIP85's own branch, the application `82796679'` (« ROBO » in ASCII decimal), the purpose `0'` (a Garage Key, this layout), the network `0'` for mainnet and `1'` for testnet, and the index of the key, `0'` for the first. The path, the purpose and the truncation are frozen once a version that derives a key has shipped: a change gives other keys, so other robots. The application number and its purpose `0'` are reserved for this key; `1'` is reserved for a later key of the same application.
///
/// The path is built here from the enum and one integer, never from a caller's string, and checked before `bip85_entropy` sees it: that library accepts an unhardened step without a word, and its entropy is then an HMAC over a non-hardened child, which this deriver must never hand out.
final class GarageDeriver {
  @internal
  const GarageDeriver();

  /// BIP85's branch, the first step of every BIP85 path.
  static const _bip85Branch = 83696968;

  /// The application number, « ROBO » in ASCII decimal (82 79 66 79). Reserved.
  static const application = 82796679;

  /// The purpose of a Garage Key in this layout. Reserved.
  static const purpose = 0;

  /// The first hardened child number: every step is below it once its hardening mark is read.
  static const _hardened = 0x80000000;

  /// The 64 bytes BIP85 gives for this application, of which a Garage Key keeps the first 32.
  static const _entropyLength = 64;

  /// The Garage Key of [secret] for [network] at [index].
  ///
  /// Refuses a secret with a passphrase: the words alone must give the key back, after a reinstall as on another device. The caller checks [index].
  GarageKeyMaterial key(
    Mnemonic secret, {
    required GarageKeySlot network,
    required int index,
  }) {
    if (secret.hasPassphrase) {
      throw const PassphraseUnsupported(
        'a Garage Key must come back from the words alone',
      );
    }
    return keyFromRoot(
      const Bip85Deriver().root(secret),
      network: network,
      index: index,
    );
  }

  /// [key], from a root already in hand.
  ///
  /// The seam the vectors are pinned through, as `Bip85Deriver.hexFromRoot`. Package-internal; the xprv never leaves `crypto/`.
  GarageKeyMaterial keyFromRoot(
    String xprv, {
    required GarageKeySlot network,
    required int index,
  }) => keyAtPath(xprv, path(network: network, index: index));

  /// The path of the Garage Key for [network] at [index].
  static String path({required GarageKeySlot network, required int index}) {
    final networkNumber = switch (network) {
      GarageKeySlot.mainnet => 0,
      GarageKeySlot.testnet => 1,
    };
    return "m/$_bip85Branch'/$application'/$purpose'/$networkNumber'/$index'";
  }

  /// The key at [path], once [path] passed every check of a Garage Key path.
  ///
  /// Refuses with an [ArgumentError], before `bip85_entropy` is called, a path that is not `m` followed by exactly five steps, a step without its hardening mark or not in canonical decimal below 2^31, a branch other than BIP85's, another application, another purpose, or a network other than `0'` and `1'`. Only [keyFromRoot] passes a path; the tests pass malformed ones.
  @visibleForTesting
  GarageKeyMaterial keyAtPath(String xprv, String path) {
    final steps = path.split('/');
    if (steps.length != 6 || steps.first != 'm') {
      throw ArgumentError.value(path, 'path', 'not m and five steps');
    }
    final numbers = <int>[];
    for (final step in steps.skip(1)) {
      final match = RegExp(r"^(0|[1-9][0-9]{0,9})'$").firstMatch(step);
      final number = match == null ? null : int.parse(match.group(1) ?? '');
      if (number == null || number >= _hardened) {
        throw ArgumentError.value(path, 'path', 'a step is not hardened, or not a canonical number below 2^31');
      }
      numbers.add(number);
    }
    if (numbers[0] != _bip85Branch ||
        numbers[1] != application ||
        numbers[2] != purpose ||
        !const {0, 1}.contains(numbers[3])) {
      throw ArgumentError.value(path, 'path', 'not a Garage Key path');
    }
    final entropy = bip85.Bip85Entropy.derive(
      xprvBase58: xprv,
      application: bip85.CustomApplication.fromNumber(application),
      path: steps.skip(3).join('/'),
    );
    if (entropy.length != _entropyLength) {
      throw StateError('BIP85 gave ${entropy.length} bytes, not 64');
    }
    return GarageKeyMaterial(
      Uint8List.fromList(entropy.sublist(0, GarageKeyMaterial.lengthInBytes)),
    );
  }
}
