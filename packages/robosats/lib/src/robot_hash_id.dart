import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/nickname.dart';
import 'package:robosats/src/robosats_failure.dart';

/// The public identifier of a robot: the SHA-256, in hexadecimal, of the hexadecimal SHA-256 of its token.
///
/// Coordinators send the hash id of the peer (`maker_hash_id`, `taker_hash_id`), and nickname and avatar are both computed from it.
@immutable
final class RobotHashId {
  static final RegExp _pattern = RegExp(r'^[0-9a-f]{64}$');

  /// 64 lowercase hexadecimal characters.
  final String hex;

  /// The nickname every coordinator assigns to this robot, at most 18 characters long.
  ///
  /// The official client compares it with the `nick` the coordinator returns to tell who wrote a chat message.
  final String nickname;

  const RobotHashId._(this.hex, this.nickname);

  /// Validates a hash id received from a coordinator or computed locally.
  ///
  /// Fails with [HashIdMalformed], or with [NicknameUnavailable] for the hash ids, about one in 2^54, on which the coordinator's own nickname generator fails.
  static Result<RobotHashId, RobosatsFailure> parse(String hex) {
    if (!_pattern.hasMatch(hex)) return const Err(HashIdMalformed());
    final hashId = fromDigest(hex);
    if (hashId == null) return const Err(NicknameUnavailable());
    return Ok(hashId);
  }

  /// Wraps a hexadecimal SHA-256 digest computed by this package, or returns `null` when it has no nickname.
  @internal
  static RobotHashId? fromDigest(String hex) {
    final derivation = deriveNickname(hex);
    return derivation == null ? null : RobotHashId._(hex, derivation.nickname);
  }

  @override
  bool operator ==(Object other) => other is RobotHashId && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;

  @override
  String toString() => 'RobotHashId($hex, $nickname)';
}
