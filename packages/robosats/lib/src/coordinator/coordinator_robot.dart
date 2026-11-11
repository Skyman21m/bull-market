import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/json_fields.dart';
import 'package:robosats/src/coordinator/read_bounds.dart';
import 'package:robosats/src/pgp/limits.dart';
import 'package:robosats/src/robosats_failure.dart';
import 'package:robosats/src/robot_hash_id.dart';
import 'package:robosats/src/robot_identity.dart';
import 'package:robosats/src/robot_pgp_key.dart';

/// What a coordinator holds about a robot of this device, once checked against what this device computed (`RobotView.get`, `api/views.py:697-743`, commit ff1998c).
///
/// It exists only when the hash id, the nickname and the OpenPGP key pair the coordinator returned are the ones of this device: see [CoordinatorRobotFailure].
/// The Telegram and webhook settings of the answer are not read: Troc uses neither, and two of them are credentials.
@immutable
final class CoordinatorRobot {
  final Coordinator coordinator;

  /// The hash id of the robot, with its nickname: the ones the coordinator returned, equal to the ones derived from the token.
  final RobotHashId hashId;

  /// Whether the coordinator says it created this robot more than five minutes ago (`found`, `api/views.py:738-741`).
  ///
  /// It is `false` right after a first contact, and it is the only sign an answer gives that the robot existed before: a coordinator answers a first contact about a robot it already knows exactly as it answers a new one.
  final bool found;

  /// The sats the robot can withdraw from this coordinator.
  final Sats earnedRewards;

  /// Whether the coordinator pays this robot with invoices that hide its node (`wants_stealth`), the default.
  final bool wantsStealth;

  /// The order this robot is the maker or the taker of, when it has one in progress.
  final int? activeOrderId;

  /// The last order this robot was part of, when it has none in progress.
  final int? lastOrderId;

  /// When the coordinator last saw this robot, which it records at most every two minutes.
  final DateTime? lastLogin;

  /// The Nostr public key the coordinator holds for this robot, 64 lowercase hexadecimal characters, or `null` when it holds none.
  ///
  /// The coordinator stores the key of the first contact without any check, hands it to the trade peer, and sends its notifications to it.
  /// A key made only of zeros is the placeholder of a coordinator that lost the real one.
  final String? nostrPublicKeyHex;

  /// Which Nostr key of the robot [nostrPublicKeyHex] is, or `null` when it is none of them: this device cannot read what is sent to that key.
  final NostrKeyDerivation? nostrKeyDerivation;

  const CoordinatorRobot._({
    required this.coordinator,
    required this.hashId,
    required this.found,
    required this.earnedRewards,
    required this.wantsStealth,
    required this.activeOrderId,
    required this.lastOrderId,
    required this.lastLogin,
    required this.nostrPublicKeyHex,
    required this.nostrKeyDerivation,
  });

  static final RegExp _nostrKey = RegExp(r'^[0-9a-f]{64}$');
  static const _maxOrderId = 1 << 53;

  /// Reads the decoded body of a `200` answer of `GET /api/robot/` for the robot [identity], whose key pair on this device is [pgpKey].
  ///
  /// Any invalid field rejects the whole answer with [CoordinatorResponseMalformed].
  /// `hash_id`, `nickname`, `public_key` and `encrypted_private_key` are required; `earned_rewards`, `wants_stealth`, `found`, the order ids, `last_login` and `nostr_pubkey` may be missing, as the official client allows.
  /// Then the answer must describe the robot of this device, in this order: the hash id ([RobotHashIdMismatch]), the nickname ([RobotNicknameMismatch]), and the key pair ([RobotPgpKeyMismatch]); the keys are only parsed once the hash id and the nickname are the right ones.
  /// A public key that is well-formed but of a kind this package does not make is a [RobotPgpKeyMismatch] too.
  /// The public key is compared by the fingerprints of its primary key and of its encryption subkey, since a coordinator returns it re-exported by GnuPG; the encrypted private key is compared by its packets, whatever its armor.
  @internal
  static Result<CoordinatorRobot, CoordinatorFailure> parse(
    Object? body,
    Coordinator coordinator, {
    required RobotIdentity identity,
    required RobotPgpKey pgpKey,
  }) {
    if (body is! Map<String, Object?>) {
      return const Err(CoordinatorResponseMalformed('robot'));
    }
    final fields = JsonFields(body);
    final hashId = fields.requiredString('hash_id', maxLength: 64);
    final nickname = fields.requiredString('nickname', maxLength: 64);
    final publicKey = fields.requiredString(
      'public_key',
      maxLength: PgpLimits.keyArmorChars,
    );
    final encryptedPrivateKey = fields.requiredString(
      'encrypted_private_key',
      maxLength: PgpLimits.keyArmorChars,
    );
    final nostrKey = fields.optionalString('nostr_pubkey', maxLength: 64);
    final earnedRewards = fields.optionalInt(
      'earned_rewards',
      min: 0,
      max: CoordinatorReadBounds.maxSats,
    );
    final wantsStealth = fields.optionalBool('wants_stealth');
    final activeOrderId = fields.optionalInt(
      'active_order_id',
      min: 1,
      max: _maxOrderId,
    );
    final lastOrderId = fields.optionalInt(
      'last_order_id',
      min: 1,
      max: _maxOrderId,
    );
    final found = fields.optionalBool('found');
    final lastLogin = fields.optionalDate('last_login');
    if (fields.rejected case final field?) {
      return Err(CoordinatorResponseMalformed(field));
    }
    final storedNostrKey = nostrKey == null || nostrKey.isEmpty
        ? null
        : nostrKey;
    if (storedNostrKey != null && !_nostrKey.hasMatch(storedNostrKey)) {
      return const Err(CoordinatorResponseMalformed('nostr_pubkey'));
    }
    // The cheap comparisons first: nothing of an answer about another robot is parsed as a key.
    if (hashId != identity.hashId.hex) return const Err(RobotHashIdMismatch());
    if (nickname != identity.nickname) {
      return const Err(RobotNicknameMismatch());
    }
    final PgpPublicKey storedPublicKey;
    switch (PgpPublicKey.parse(publicKey)) {
      case Ok(:final value):
        storedPublicKey = value;
      // A key of a kind this package does not make is the key of another client.
      case Err(failure: PgpKeyUnsupported()):
        return const Err(RobotPgpKeyMismatch());
      case Err():
        return const Err(CoordinatorResponseMalformed('public_key'));
    }
    if (storedPublicKey != pgpKey.publicKey) {
      return const Err(RobotPgpKeyMismatch());
    }
    final RobotPgpKey storedKey;
    switch (RobotPgpKey.parse(
      publicKey: publicKey,
      encryptedPrivateKey: encryptedPrivateKey,
    )) {
      case Ok(:final value):
        storedKey = value;
      case Err():
        return const Err(CoordinatorResponseMalformed('encrypted_private_key'));
    }
    // Both are canonical armor, so this compares the packets, whatever armor the coordinator wrapped them in.
    if (storedKey.encryptedPrivateKeyArmored !=
        pgpKey.encryptedPrivateKeyArmored) {
      return const Err(RobotPgpKeyMismatch());
    }

    NostrKeyDerivation? nostrKeyDerivation;
    for (final derivation in NostrKeyDerivation.values) {
      if (identity.nostrKeyPair(derivation).publicKeyHex == storedNostrKey) {
        nostrKeyDerivation = derivation;
      }
    }
    return Ok(
      CoordinatorRobot._(
        coordinator: coordinator,
        hashId: identity.hashId,
        found: found ?? false,
        earnedRewards: Sats.fromInt(earnedRewards ?? 0),
        wantsStealth: wantsStealth ?? true,
        activeOrderId: activeOrderId,
        lastOrderId: lastOrderId,
        lastLogin: lastLogin,
        nostrPublicKeyHex: storedNostrKey,
        nostrKeyDerivation: nostrKeyDerivation,
      ),
    );
  }

  /// Public identifiers and numbers only.
  @override
  String toString() =>
      'CoordinatorRobot(${coordinator.shortAlias}, ${hashId.nickname}, found: $found)';
}
