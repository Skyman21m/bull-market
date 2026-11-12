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

/// What a coordinator answered about a robot of this device, once the hash id and the nickname it returned are the ones this device computed (`RobotView.get`, `api/views.py:697-743`, commit ff1998c).
///
/// A [CoordinatorRobot] when the key pair it returned is the one this device has just sent in the same call, and an [UnprovenCoordinatorRobot] otherwise, whose [UnprovenCoordinatorRobot.prove] alone gives the robot.
sealed class CoordinatorRobotAnswer {
  const CoordinatorRobotAnswer();

  /// Reads the decoded body of a `200` answer of `GET /api/robot/` for the robot [identity], to which this device has just sent the key pair [sentKey] in a first contact, if it sent one.
  ///
  /// The answer is read and checked as [UnprovenCoordinatorRobot.parse] says.
  /// Then a key pair equal to [sentKey] gives a [CoordinatorRobot] that carries [sentKey]: the public key is compared by the fingerprints of its primary key and of its encryption subkey, since a coordinator returns it re-exported by GnuPG, and the private key by its packets, whatever its armor.
  /// Any other pair, and every pair when [sentKey] is `null`, gives an [UnprovenCoordinatorRobot].
  @internal
  static Result<CoordinatorRobotAnswer, CoordinatorFailure> parse(
    Object? body,
    Coordinator coordinator, {
    required RobotIdentity identity,
    required RobotPgpKey? sentKey,
  }) => switch (UnprovenCoordinatorRobot.parse(
    body,
    coordinator,
    identity: identity,
  )) {
    Err(:final failure) => Err(failure),
    Ok(value: final unproven)
        when sentKey != null && unproven._pgpKey == sentKey =>
      Ok(CoordinatorRobot._(unproven._facts, sentKey, pgpKeyProven: false)),
    Ok(value: final unproven) => Ok(unproven),
  };
}

/// What a coordinator holds about a robot of this device, once checked against what this device computed and knows.
///
/// It exists only when the hash id and the nickname the coordinator returned are the ones this device derived from the token, and the OpenPGP key pair it returned is either the one this device has just sent in the same call or one the robot's token proved ([UnprovenCoordinatorRobot.prove]): see [CoordinatorRobotFailure].
/// The Telegram and webhook settings of the answer are not read: Troc uses neither, and two of them are credentials.
@immutable
final class CoordinatorRobot extends CoordinatorRobotAnswer {
  final Coordinator coordinator;

  /// The hash id of the robot, with its nickname: the ones the coordinator returned, equal to the ones derived from the token.
  final RobotHashId hashId;

  /// Whether the coordinator says it created this robot more than five minutes ago (`found`, `api/views.py:738-741`).
  ///
  /// It is `false` right after a first contact, and it is the only sign an answer gives that the robot existed before, with [pgpKeyProven] after a first contact: a coordinator answers a first contact about a robot it already knows exactly as it answers a new one, but with the key pair it already held.
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

  /// The OpenPGP key pair the coordinator holds for this robot, still locked by the token: the one this device sent in the same call, or one the token proved.
  ///
  /// Its private key is only as secret as the token, and the coordinator holds a copy: never log it all the same.
  final RobotPgpKey pgpKey;

  /// Whether [pgpKey] is not a pair this device sent in the call that read the robot, and was taken because the robot's token proved it.
  ///
  /// Always true after a read with the short header, which sends no pair; after a first contact, it means the robot existed on the coordinator before, with that pair.
  final bool pgpKeyProven;

  CoordinatorRobot._(_Facts facts, this.pgpKey, {required this.pgpKeyProven})
    : coordinator = facts.coordinator,
      hashId = facts.hashId,
      found = facts.found,
      earnedRewards = facts.earnedRewards,
      wantsStealth = facts.wantsStealth,
      activeOrderId = facts.activeOrderId,
      lastOrderId = facts.lastOrderId,
      lastLogin = facts.lastLogin,
      nostrPublicKeyHex = facts.nostrPublicKeyHex,
      nostrKeyDerivation = facts.nostrKeyDerivation;

  /// Public identifiers and numbers only.
  @override
  String toString() =>
      'CoordinatorRobot(${coordinator.shortAlias}, ${hashId.nickname}, found: $found)';
}

/// What a coordinator answered about a robot of this device whose key pair is not one this device has just sent: the hash id and the nickname are this robot's, the key pair is still to be proven.
///
/// Only [prove] gives the robot, and nothing else of the answer can be read before: an answer whose pair the token does not prove is dropped whole.
/// It holds the identity of the robot, its token included, for [prove]: keep it no longer than the call that proves it.
/// It prints the coordinator and the nickname only.
@immutable
final class UnprovenCoordinatorRobot extends CoordinatorRobotAnswer {
  final _Facts _facts;
  final RobotIdentity _identity;
  final RobotPgpKey _pgpKey;

  const UnprovenCoordinatorRobot._(this._facts, this._identity, this._pgpKey);

  static final RegExp _nostrKey = RegExp(r'^[0-9a-f]{64}$');
  static const _maxOrderId = 1 << 53;

  /// Reads the decoded body of a `200` answer of `GET /api/robot/` for the robot [identity], without proving its key pair.
  ///
  /// Any invalid field rejects the whole answer with [CoordinatorResponseMalformed].
  /// `hash_id`, `nickname`, `public_key` and `encrypted_private_key` are required, each key block of at most `PgpLimits.keyArmorChars` characters; `earned_rewards`, `wants_stealth`, `found`, the order ids, `last_login` and `nostr_pubkey` may be missing, as the official client allows.
  /// Then the answer must describe the robot of this device: the hash id ([RobotHashIdMismatch]), then the nickname ([RobotNicknameMismatch]), both compared before anything of the keys is parsed.
  /// Then each key block must be an armored key of its kind ([CoordinatorResponseMalformed], `public_key` or `encrypted_private_key`), and the two must be one key pair of the kind this package reads: a key of another kind, a private key that is not passphrase-protected as the official client and GnuPG protect it, or a private key of another key than the public one is a [RobotPgpKeyNotProven].
  /// Nothing is hashed or unlocked here.
  @internal
  static Result<UnprovenCoordinatorRobot, CoordinatorFailure> parse(
    Object? body,
    Coordinator coordinator, {
    required RobotIdentity identity,
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
    // The public key alone first, so that a block that is not an armored public key is named.
    if (PgpPublicKey.parse(publicKey) case Err(:final failure)) {
      return Err(switch (failure) {
        // A key of a kind this package does not read cannot be proven.
        PgpKeyUnsupported() => const RobotPgpKeyNotProven(),
        _ => const CoordinatorResponseMalformed('public_key'),
      });
    }
    final RobotPgpKey pgpKey;
    switch (RobotPgpKey.parse(
      publicKey: publicKey,
      encryptedPrivateKey: encryptedPrivateKey,
    )) {
      case Ok(:final value):
        pgpKey = value;
      // Another kind of private key, or the private key of another key: no token can prove such a pair.
      case Err(failure: PgpKeyUnsupported() || PgpKeyPairMismatch()):
        return const Err(RobotPgpKeyNotProven());
      case Err():
        return const Err(CoordinatorResponseMalformed('encrypted_private_key'));
    }

    NostrKeyDerivation? nostrKeyDerivation;
    for (final derivation in NostrKeyDerivation.values) {
      if (identity.nostrKeyPair(derivation).publicKeyHex == storedNostrKey) {
        nostrKeyDerivation = derivation;
      }
    }
    return Ok(
      UnprovenCoordinatorRobot._(
        (
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
        identity,
        pgpKey,
      ),
    );
  }

  /// The coordinator that answered.
  Coordinator get coordinator => _facts.coordinator;

  /// The hash id of the robot, with its nickname, equal to the ones derived from the token.
  RobotHashId get hashId => _facts.hashId;

  /// Proves the key pair with the robot's token, and gives the robot, which carries the pair still locked; anything else is a [RobotPgpKeyNotProven].
  ///
  /// The pair is proven when its private key unlocks with the token and holds the secret values of its public key: see [RobotPgpKeyNotProven] for why that proves a holder of the token made it.
  /// It hashes what unlocking the private key hashes, synchronously: 32 MiB of SHA-256 for a key of the official client or of Troc, and at most `PgpLimits.proofHashedBytes` (62 MiB), a pair that would ask for more being refused before anything is hashed.
  /// Call it off the UI isolate.
  /// The passphrase and the secret values unlocked are wiped before it returns, and the robot keeps only the locked pair.
  /// Calling it again gives the same result.
  Result<CoordinatorRobot, RobotPgpKeyNotProven> prove() =>
      switch (_pgpKey.proveMadeBy(_identity)) {
        Ok() => Ok(CoordinatorRobot._(_facts, _pgpKey, pgpKeyProven: true)),
        Err() => const Err(RobotPgpKeyNotProven()),
      };

  /// Public identifiers only.
  @override
  String toString() =>
      'UnprovenCoordinatorRobot(${coordinator.shortAlias}, ${hashId.nickname})';
}

/// What an answer says about a robot, read and checked, but its key pair.
typedef _Facts = ({
  Coordinator coordinator,
  RobotHashId hashId,
  bool found,
  Sats earnedRewards,
  bool wantsStealth,
  int? activeOrderId,
  int? lastOrderId,
  DateTime? lastLogin,
  String? nostrPublicKeyHex,
  NostrKeyDerivation? nostrKeyDerivation,
});
