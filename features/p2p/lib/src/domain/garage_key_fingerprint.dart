import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show GarageKey, RobosatsFailure, RobotToken, TokenEntropyTooLow;

import 'p2p_failure.dart';

/// What ties the state the feature keeps about the robots of a Garage Key, such as the coordinator each robot index is bound to, to that key, without revealing it.
///
/// It is the HMAC-SHA256, keyed by the token of the first robot of the key whose token derives, from index 0, of a text that names this use.
/// The token never leaves the device: a coordinator receives only its SHA-256, and publishes the hash id, so no coordinator can compute the fingerprint.
/// The fingerprint does not give the token back, and the text keeps it apart from every value RoboSats derives from a token.
/// It is the same for the same key on both networks, as the robots' tokens are (`GarageKey.deriveToken` takes no network): so a robot index has one binding, whatever the network.
/// It is not secret, but it lets whoever holds the key, or a robot token, recognise the database: it is not printed.
/// Changing how it is computed orphans every stored binding: that is a new version of the database, with a migration.
@immutable
final class GarageKeyFingerprint {
  static const String _purpose = 'troc/p2p/garage-key-fingerprint/v1';

  /// 64 lowercase hexadecimal characters: not a secret, and safe to store.
  final String hex;

  const GarageKeyFingerprint._(this.hex);

  /// The fingerprint of [key].
  ///
  /// A key none of whose first `GarageKey.maxAccountSearch` tokens derives, which does not happen with a key drawn at random, is a [GarageRobotUnavailableFailure]: no robot of it can be made either.
  static Result<GarageKeyFingerprint, P2pFailure> of(GarageKey key) =>
      fromTokens(key.deriveToken);

  /// [of] over the tokens [tokenOf] gives for each index: a token that fails the entropy rule is skipped, any other failure stops the search.
  ///
  /// For tests only: no Garage Key is known whose robot 0 has a token to skip.
  @visibleForTesting
  static Result<GarageKeyFingerprint, P2pFailure> fromTokens(
    Result<RobotToken, RobosatsFailure> Function(int accountIndex) tokenOf,
  ) {
    for (var index = 0; index < GarageKey.maxAccountSearch; index++) {
      switch (tokenOf(index)) {
        case Ok(value: final token):
          final mac = Hmac(sha256, utf8.encode(token.reveal()));
          return Ok(
            GarageKeyFingerprint._(
              mac.convert(utf8.encode(_purpose)).toString(),
            ),
          );
        case Err(failure: TokenEntropyTooLow()):
          continue;
        case Err():
          return const Err(GarageRobotUnavailableFailure());
      }
    }
    return const Err(GarageRobotUnavailableFailure());
  }

  @override
  bool operator ==(Object other) =>
      other is GarageKeyFingerprint && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;

  /// Never the value: a log line could otherwise tie a device to its keys.
  @override
  String toString() => 'GarageKeyFingerprint(<redacted>)';
}
