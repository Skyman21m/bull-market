import 'dart:isolate';
import 'dart:math';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show
        ChatDecryptionKey,
        Coordinator,
        CoordinatorOrder,
        CoordinatorRobot,
        HostRating,
        HostReviewToken,
        NostrChatFailure,
        NostrKeyPair,
        OutgoingHostRating,
        OutgoingNostrChatMessage,
        RobosatsNetwork,
        DecryptedChatMessage,
        PgpClockOutOfRange,
        PgpFailure,
        RobotIdentity,
        RobotPgpKey,
        RobotPgpKeyNotProven,
        UnlockedRobotPgpKey,
        UnprovenCoordinatorRobot;

import '../domain/p2p_failure.dart';
import '../domain/robot_key_compute_port.dart';

/// Runs the work on the key pair of a robot in a short-lived isolate of its own (`Isolate.run`), so that the UI isolate never does the hashing.
///
/// The isolate receives a copy of what the work needs, the robot's identity with its token included, and ends as soon as the work is done: the passphrase and the secret values a proof unlocks are wiped in it before it ends, and only the locked pair comes back.
/// An unlock (#90) is the one work whose result holds secret values: the unlocked key comes back to the calling isolate, for `TradeKeyring` to keep as its rules say; the passphrase is wiped in the isolate before it ends.
/// An isolate started so belongs to the group of the app's isolates and shares their heap: running elsewhere keeps the screens fluid, it does not keep the token or the unlocked values apart in memory.
/// Each closure handed to `Isolate.run` is made in a static method, where it can hold nothing but its arguments, so that nothing else of the feature is copied to the isolate.
/// An isolate that cannot be started is a [RobotKeyComputeFailure]; an [Error] of the work is a bug and reaches the caller, as rule 11 of AGENTS.md wants.
final class IsolateRobotKeyCompute implements RobotKeyComputePort {
  const IsolateRobotKeyCompute();

  @override
  Future<Result<RobotPgpKey, RobotKeyComputeFailure>> generate(
    RobotIdentity identity,
  ) async => switch (await _generateApart(identity)) {
    Ok(value: Ok(:final value)) => Ok(value),
    // The clock is outside the dates an OpenPGP key can hold.
    Ok(value: Err()) || Err() => const Err(RobotKeyComputeFailure()),
  };

  @override
  Future<
    Result<
      Result<CoordinatorRobot, RobotPgpKeyNotProven>,
      RobotKeyComputeFailure
    >
  >
  prove(UnprovenCoordinatorRobot robot) => _proveApart(robot);

  @override
  Future<
    Result<Result<UnlockedRobotPgpKey, PgpFailure>, RobotKeyComputeFailure>
  >
  unlock(RobotPgpKey key, RobotIdentity identity) =>
      _unlockApart(key, identity);

  @override
  Future<
    Result<
      List<Result<DecryptedChatMessage, PgpFailure>>,
      RobotKeyComputeFailure
    >
  >
  decryptChat(
    UnlockedRobotPgpKey key,
    List<ChatDecryptJob> jobs, {
    required DateTime now,
  }) => _decryptApart(key.chatDecryption, jobs, now);

  @override
  Future<
    Result<
      Result<OutgoingNostrChatMessage, NostrChatFailure>,
      RobotKeyComputeFailure
    >
  >
  composeNostrChat(
    NostrKeyPair sender, {
    required CoordinatorOrder order,
    required Coordinator coordinator,
    required RobosatsNetwork network,
    required String text,
    required DateTime now,
  }) => _composeApart(sender, order, coordinator, network, text, now);

  @override
  Future<Result<OutgoingHostRating, RobotKeyComputeFailure>> composeHostRating(
    NostrKeyPair sender, {
    required HostReviewToken token,
    required Coordinator coordinator,
    required int orderId,
    required HostRating rating,
    required DateTime now,
  }) => _rateApart(sender, token, coordinator, orderId, rating, now);

  /// The rating of the coordinator composed apart, in an isolate of its own for each tap of a star (#95): see [RobotKeyComputePort.composeHostRating] for what is copied there.
  static Future<Result<OutgoingHostRating, RobotKeyComputeFailure>> _rateApart(
    NostrKeyPair sender,
    HostReviewToken token,
    Coordinator coordinator,
    int orderId,
    HostRating rating,
    DateTime now,
  ) => _run(
    () => OutgoingHostRating.compose(
      sender,
      token: token,
      coordinator: coordinator,
      orderId: orderId,
      rating: rating,
      now: now,
      random: Random.secure(),
    ),
  );

  /// The Nostr copy composed apart, in an isolate of its own for each message (#94): see [RobotKeyComputePort.composeNostrChat] for what is copied there.
  static Future<
    Result<
      Result<OutgoingNostrChatMessage, NostrChatFailure>,
      RobotKeyComputeFailure
    >
  >
  _composeApart(
    NostrKeyPair sender,
    CoordinatorOrder order,
    Coordinator coordinator,
    RobosatsNetwork network,
    String text,
    DateTime now,
  ) => _run(
    () => OutgoingNostrChatMessage.composeFor(
      sender,
      order: order,
      coordinator: coordinator,
      network: network,
      text: text,
      now: now,
      random: Random.secure(),
    ),
  );

  /// The chat's messages decrypted apart, in an isolate of its own for each page that holds something to decrypt (review of #93).
  ///
  /// What is copied there: [key], the key and the scalar of its encryption subkey only, never the robot's identity or token nor the seed that signs; the jobs, armored messages and public keys; and [now]. What comes back: the decrypted results, their texts included. The worker's memory is freed when it exits, not wiped, as for the unlock; the work is bounded by `PgpLimits`, and nothing cancels it.
  static Future<
    Result<
      List<Result<DecryptedChatMessage, PgpFailure>>,
      RobotKeyComputeFailure
    >
  >
  _decryptApart(
    ChatDecryptionKey key,
    List<ChatDecryptJob> jobs,
    DateTime now,
  ) => _run(
    () => [
      for (final job in jobs)
        key.decryptChatMessage(job.armored, sender: job.sender, now: now),
    ],
  );

  static Future<
    Result<Result<UnlockedRobotPgpKey, PgpFailure>, RobotKeyComputeFailure>
  >
  _unlockApart(RobotPgpKey key, RobotIdentity identity) =>
      _run(() => key.unlock(identity));

  static Future<
    Result<Result<RobotPgpKey, PgpClockOutOfRange>, RobotKeyComputeFailure>
  >
  _generateApart(RobotIdentity identity) =>
      _run(() => RobotPgpKey.generate(identity));

  static Future<
    Result<
      Result<CoordinatorRobot, RobotPgpKeyNotProven>,
      RobotKeyComputeFailure
    >
  >
  _proveApart(UnprovenCoordinatorRobot robot) => _run(robot.prove);

  /// The result of [work], computed in a new isolate.
  static Future<Result<T, RobotKeyComputeFailure>> _run<T>(
    T Function() work,
  ) async {
    try {
      return Ok(await Isolate.run(work, debugName: 'robot key'));
    } on IsolateSpawnException {
      return const Err(RobotKeyComputeFailure());
    }
  }
}
