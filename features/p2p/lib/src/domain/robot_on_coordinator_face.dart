import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show CoordinatorRobot, NostrKeyDerivation;

/// Which Nostr key a coordinator holds for a robot, as the robot's token tells it.
enum RobotNostrKeyStatus {
  /// The key of the official client since July 2025, which Troc sends: the robot reads what the coordinator sends to it.
  current,

  /// The key of the official client's first formula, whose secret is the token hash every coordinator holds: what is sent to it is not private.
  old,

  /// No key of this robot, or none at all, or the placeholder of a coordinator that lost the real one: what is sent to it does not reach the robot.
  unknown,
}

/// What a coordinator said about a robot of this device, for a screen: no token, no key, no fingerprint and no text the coordinator chose.
///
/// The coordinator itself is not in it: a screen names it from the binding it read.
/// Every field is the coordinator's word, read and bounded by the package: the proof of the robot's key pair covers none of them.
@immutable
final class RobotOnCoordinatorFace {
  /// The order the robot is the maker or the taker of, when it has one in progress.
  final int? activeOrderId;

  /// The last order the robot was part of, when it has none in progress.
  final int? lastOrderId;

  /// The sats the robot can claim from the coordinator.
  final Sats earnedRewards;

  /// Which Nostr key the coordinator holds for the robot.
  final RobotNostrKeyStatus nostrKey;

  /// Whether the first contact this call sent found the robot already there: the coordinator answered it, or the read 10 s after a nickname taken, with a key pair, proven by the robot's token, that this call did not send.
  ///
  /// It was made by another device or client, or by an earlier request of this device whose answer was lost: the coordinator says so, no more (AGENTS.md, « A robot on a coordinator »).
  /// False when no first contact was sent: for a robot already bound to that coordinator, which `PutRobotOnCoordinatorUsecase` reads back first and finds there, as this device put it there before, and always for `ReadRobotOnCoordinatorUsecase`, which puts nothing (security review of step 5).
  final bool alreadyExisted;

  const RobotOnCoordinatorFace({
    required this.activeOrderId,
    required this.lastOrderId,
    required this.earnedRewards,
    required this.nostrKey,
    required this.alreadyExisted,
  });

  /// What [robot] shows of itself; [alreadyExisted] as the call that read it tells it.
  factory RobotOnCoordinatorFace.of(
    CoordinatorRobot robot, {
    required bool alreadyExisted,
  }) => RobotOnCoordinatorFace(
    activeOrderId: robot.activeOrderId,
    lastOrderId: robot.lastOrderId,
    earnedRewards: robot.earnedRewards,
    nostrKey: switch (robot.nostrKeyDerivation) {
      NostrKeyDerivation.currentFrontend => RobotNostrKeyStatus.current,
      NostrKeyDerivation.repositoryFixtures => RobotNostrKeyStatus.old,
      null => RobotNostrKeyStatus.unknown,
    },
    alreadyExisted: alreadyExisted,
  );

  @override
  bool operator ==(Object other) =>
      other is RobotOnCoordinatorFace &&
      other.activeOrderId == activeOrderId &&
      other.lastOrderId == lastOrderId &&
      other.earnedRewards == earnedRewards &&
      other.nostrKey == nostrKey &&
      other.alreadyExisted == alreadyExisted;

  @override
  int get hashCode => Object.hash(
    activeOrderId,
    lastOrderId,
    earnedRewards,
    nostrKey,
    alreadyExisted,
  );

  @override
  String toString() =>
      'RobotOnCoordinatorFace(active: $activeOrderId, last: $lastOrderId, rewards: $earnedRewards, nostr: ${nostrKey.name}, alreadyExisted: $alreadyExisted)';
}
