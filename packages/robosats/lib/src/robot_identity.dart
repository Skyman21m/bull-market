import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/base91.dart';
import 'package:robosats/src/coordinator/robot_session_key.dart';
import 'package:robosats/src/nostr_key_pair.dart';
import 'package:robosats/src/pgp_wire.dart';
import 'package:robosats/src/robosats_failure.dart';
import 'package:robosats/src/robot_hash_id.dart';
import 'package:robosats/src/robot_token.dart';

/// Which formula turns a robot token into its Nostr secret key.
///
/// The RoboSats repository (commit ff1998c, v0.8.8) holds two, and they give different keys.
/// The coordinator of that source checks neither: it stores the 64 hexadecimal characters the first contact carries, hands them to the trade peer and sends its notifications to them (`robosats/middleware.py:29-37` and `:126-172`).
/// It never changes them afterwards, with one exception: a stored key made only of zeros, its placeholder for a lost key, is replaced by the one a later request carries (`:98-107`).
/// One testnet coordinator, running v0.8.6, was seen to behave so on 2026-11-11 with the two keys of this enum, and with no other: it stored each as sent, and kept the first when the other was sent later: see `docs/spikes/robot-coordinator.md`.
/// So the formula only has to be the one of the client that reads the messages, and Troc uses [currentFrontend].
enum NostrKeyDerivation {
  /// `sha256(sha512(utf8(token)))`, the code of the official client since July 2025 (`frontend/src/models/Slot.model.ts:34-38`).
  ///
  /// The default, and the only one to use for a robot: a robot shared with the official client reads the same Nostr messages in both.
  currentFrontend,

  /// `sha256(utf8(token))`, the first formula of the official client, from April to July 2025: it reproduces `tests/robots/{1,2,3}/nostr_pubkey` and is what `development/docs.md:80` still describes.
  ///
  /// Never create a robot with it: this secret key is the SHA-256 of the token, the very 32 bytes every request sends to the coordinator as the credential, so any coordinator the robot contacts can compute it.
  /// It is kept to recognise a key a coordinator holds for an old robot, and for the test vectors.
  repositoryFixtures,
}

/// Everything RoboSats derives from a robot token.
///
/// It reproduces the constructor of `Slot` in `frontend/src/models/Slot.model.ts` and the first-request handling of `robosats/middleware.py` (commit ff1998c).
@immutable
final class RobotIdentity {
  /// The secret this identity is derived from.
  final RobotToken token;

  /// The hexadecimal SHA-256 of the UTF-8 token, the `token_sha256_hex` query parameter of the chat websocket.
  ///
  /// It authenticates the robot, like [tokenSha256Base91]: never log it.
  final String tokenSha256Hex;

  /// The basE91 encoding of the 32 raw bytes of that SHA-256, 39 or 40 characters long: `tokenSHA256` in the frontend.
  ///
  /// It is the credential the coordinator stores and receives on every request: never log it.
  final String tokenSha256Base91;

  /// The public identifier of the robot, with its nickname.
  final RobotHashId hashId;

  final NostrKeyPair _currentFrontendNostrKeyPair;
  final NostrKeyPair _repositoryFixturesNostrKeyPair;

  const RobotIdentity._(
    this.token,
    this.tokenSha256Hex,
    this.tokenSha256Base91,
    this.hashId,
    this._currentFrontendNostrKeyPair,
    this._repositoryFixturesNostrKeyPair,
  );

  /// Derives the identity of the robot whose secret is [token].
  ///
  /// Fails with [NicknameUnavailable] for the tokens, about one in 2^54, whose hash id makes the coordinator's nickname generator fail: no coordinator can create such a robot, so take another token or the next Garage Key index.
  static Result<RobotIdentity, NicknameUnavailable> fromToken(
    RobotToken token,
  ) {
    final tokenBytes = utf8.encode(token.reveal());
    final tokenDigest = sha256.convert(tokenBytes);
    final tokenSha256Hex = tokenDigest.toString();
    // The second round hashes the 64 hexadecimal characters, not the 32 bytes: `sha256(sha256(token))` of js-sha256, and `robosats/middleware.py:145-146`.
    final hashId = RobotHashId.fromDigest(
      sha256.convert(ascii.encode(tokenSha256Hex)).toString(),
    );
    if (hashId == null) return const Err(NicknameUnavailable());
    return Ok(
      RobotIdentity._(
        token,
        tokenSha256Hex,
        base91Encode(tokenDigest.bytes),
        hashId,
        NostrKeyPair.fromSecretKey(
          sha256.convert(sha512.convert(tokenBytes).bytes).bytes,
        ),
        NostrKeyPair.fromSecretKey(tokenDigest.bytes),
      ),
    );
  }

  /// The nickname the coordinator assigns to this robot.
  String get nickname => hashId.nickname;

  /// What a transport keys the connections and Tor circuits of this robot by: see [RobotSessionKey].
  RobotSessionKey get sessionKey => RobotSessionKey.of(hashId);

  /// The user id the official client gives to the PGP key of this robot (`frontend/src/pgp/index.ts:26`).
  String get pgpUserId => 'RoboSats ID ${hashId.hex}';

  /// The Nostr identity of this robot under [derivation].
  NostrKeyPair nostrKeyPair([
    NostrKeyDerivation derivation = NostrKeyDerivation.currentFrontend,
  ]) => switch (derivation) {
    NostrKeyDerivation.currentFrontend => _currentFrontendNostrKeyPair,
    NostrKeyDerivation.repositoryFixtures => _repositoryFixturesNostrKeyPair,
  };

  /// The value of the `Authorization` header of every request but the first: `Token <tokenSha256Base91>`.
  ///
  /// It is a credential: never log it.
  String authorizationHeader() => 'Token $tokenSha256Base91';

  /// The value of the `Authorization` header that creates the robot on a coordinator.
  ///
  /// The official client sends this form on `GET /api/robot/`, `POST /api/make/` and `GET /api/order/`.
  /// [pgpPublicKey] and [pgpEncryptedPrivateKey] are the ASCII-armored PGP blocks, taken as opaque strings: each line break becomes a backslash, as in `frontend/src/models/Robot.model.ts:82-83`.
  /// The coordinator splits the value on `" | "` and requires exactly four parts (`robosats/middleware.py:53-59`).
  /// So pass the blocks of a `RobotPgpKey`, which are canonical armor, base64 between two fixed lines: an armor header of another origin could hold a `" | "`, or a character an HTTP header cannot carry.
  /// It is a credential: never log it.
  String firstContactAuthorizationHeader({
    required String pgpPublicKey,
    required String pgpEncryptedPrivateKey,
    NostrKeyDerivation nostrKeyDerivation = NostrKeyDerivation.currentFrontend,
  }) =>
      '${authorizationHeader()}'
      ' | Public ${pgpArmorToWire(pgpPublicKey)}'
      ' | Private ${pgpArmorToWire(pgpEncryptedPrivateKey)}'
      ' | Nostr ${nostrKeyPair(nostrKeyDerivation).publicKeyHex}';

  @override
  bool operator ==(Object other) =>
      other is RobotIdentity && other.token == token;

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() =>
      'RobotIdentity(nickname: $nickname, hashId: ${hashId.hex})';
}
