import 'package:robosats/robosats.dart'
    show
        Coordinator,
        CoordinatorFailure,
        CoordinatorNotJson,
        CoordinatorNotOnNetwork,
        CoordinatorResponseMalformed,
        CoordinatorUnexpectedStatus,
        CoordinatorIdentityFailure,
        CoordinatorTransportFailure,
        RobosatsNetwork,
        RobotCredentialsRejected,
        RobotKeysRefusal,
        RobotKeysRefused,
        RobotMismatchFailure,
        RobotNicknameTaken,
        RobotUnknown;

import '../domain/p2p_failure.dart';
import '../domain/robot_on_coordinator_face.dart';
import '../domain/tor_wait.dart';

/// Where the robot shown in the Garage stands with a coordinator, for its panel under the robot navigator.
///
/// No state holds a token, a key, a fingerprint or a robot: the coordinator as the federation list of the app gives it, public data only, and the faces the robot use cases return.
/// The states are compared by identity and print their type only.
sealed class RobotCoordinatorState {
  const RobotCoordinatorState();

  @override
  String toString() => '$runtimeType';
}

/// The feature's database is being read for where the robot stands.
final class RobotStandingReading extends RobotCoordinatorState {
  const RobotStandingReading();
}

/// The feature's database could not be read, so nothing is known of the robot's coordinator, and nothing is sent: « Retry » reads it again.
final class RobotStandingUnreadable extends RobotCoordinatorState {
  final P2pFailure failure;

  const RobotStandingUnreadable(this.failure);
}

/// No coordinator received the robot from this device: « Select Host » may put it on one, on the user's request.
final class RobotWithoutCoordinator extends RobotCoordinatorState {
  /// Whether the history of the robot's key must be acknowledged before the robot can go anywhere: « Select Host » is disabled until a later step asks it.
  final bool needsAcknowledgement;

  /// Where Tor stands: « Select Host » waits for it to be ready.
  final TorWait tor;

  /// The coordinator a first contact that failed before binding the robot was for, and why it failed, when one did.
  final RobotAttempt? lastAttempt;

  const RobotWithoutCoordinator({
    required this.needsAcknowledgement,
    required this.tor,
    this.lastAttempt,
  });

  /// Whether « Select Host » may be used now: Tor is ready, and the key's history needs no acknowledgement.
  bool get mayChooseHost => tor == TorWait.ready && !needsAcknowledgement;

  /// This state with Tor at [tor].
  RobotWithoutCoordinator withTor(TorWait tor) => RobotWithoutCoordinator(
    needsAcknowledgement: needsAcknowledgement,
    tor: tor,
    lastAttempt: lastAttempt,
  );
}

/// The robot is bound to [coordinator], on the robot's network, as the binding recorded it: the coordinator a screen never chooses again.
final class RobotOnCoordinator extends RobotCoordinatorState {
  /// The coordinator of the binding, as the federation list of the app gives it: the one this robot's requests go to.
  final Coordinator coordinator;

  /// What the panel is doing with it.
  final RobotActivity activity;

  const RobotOnCoordinator(this.coordinator, this.activity);
}

/// The robot is bound to a coordinator of the other network: no coordinator of this network may receive it, and nothing is sent.
///
/// It happens only when the same Garage Key is in both slots, since a robot's token does not depend on the network.
final class RobotOnOtherNetwork extends RobotCoordinatorState {
  /// The network of the coordinator the robot is bound to.
  final RobosatsNetwork network;

  const RobotOnOtherNetwork(this.network);
}

/// The coordinator the robot is bound to changed its address or keys in the federation list of the app since the robot was sent to it, or left the list: nothing is sent, and the robot is not to be used until a reviewed update of the app.
final class RobotCoordinatorChanged extends RobotCoordinatorState {
  /// The short alias the binding recorded.
  final String alias;

  /// The coordinator of that alias as the list gives it now, when it still has it.
  final Coordinator? listed;

  const RobotCoordinatorChanged(this.alias, this.listed);
}

/// What the panel of a robot bound to a coordinator is doing.
sealed class RobotActivity {
  const RobotActivity();

  @override
  String toString() => '$runtimeType';
}

/// The robot is read back once Tor is ready, which it is not yet: [tor] says whether it connects or failed.
final class RobotWaitingForTor extends RobotActivity {
  final TorWait tor;

  const RobotWaitingForTor(this.tor);
}

/// Which request the panel is making.
enum RobotContactKind {
  /// A first contact, which creates the robot on a coordinator that does not know it: « Building your robot! ».
  create,

  /// A read back, which creates nothing: « Looking for orders! ».
  read,
}

/// A request is running: [kind] says which, and [slow] that it has run for a while, which the panel says.
final class RobotContacting extends RobotActivity {
  final RobotContactKind kind;
  final bool slow;

  const RobotContacting(this.kind, {this.slow = false});
}

/// The coordinator answered with the robot: what the use case shows of it.
final class RobotKnown extends RobotActivity {
  final RobotOnCoordinatorFace face;

  /// Whether this answer is that of « Select Host » for a robot no coordinator had received from this device.
  ///
  /// Only then does [RobotOnCoordinatorFace.alreadyExisted] tell the user something new: the robot was there before the user sent it, made elsewhere.
  /// After « Retry » the robot is bound there already, and the use case reads it back before any first contact: a robot found so « already existed » because this device put it there earlier.
  final bool afterSelectHost;

  const RobotKnown(this.face, {this.afterSelectHost = false});
}

/// The last request failed: why, and the way out the panel offers.
final class RobotFailed extends RobotActivity {
  final RobotRequestProblem problem;

  const RobotFailed(this.problem);
}

/// A first contact to [coordinator] that failed, and why.
final class RobotAttempt {
  final Coordinator coordinator;
  final RobotRequestProblem problem;

  const RobotAttempt(this.coordinator, this.problem);

  @override
  String toString() => 'RobotAttempt(${coordinator.shortAlias}, $problem)';
}

/// The way out of a failed robot request, as the design note of #29 (§ 2.3) gives it.
enum RobotWayOut {
  /// « Retry » reads the robot back from its coordinator: a request that may have reached it is never sent again as a first contact.
  readBack,

  /// « Retry » puts the robot on the coordinator of its binding again, which the use case does by reading it back first and making a new first contact only when the coordinator does not know it: the coordinator said it does not know the robot, or refused its key as too recent.
  firstContact,

  /// No button: the text says to use another robot, or there is nothing to retry.
  none,
}

/// Why a robot request failed: refused by the feature ([RobotRequestRefused]), or answered with a failure by the coordinator or its transport ([RobotRequestAnswered]).
sealed class RobotRequestProblem {
  const RobotRequestProblem();

  /// What « Retry » does after it, if anything.
  RobotWayOut get wayOut;
}

/// The feature refused the request, before it left or after its answer: a [P2pFailure].
final class RobotRequestRefused extends RobotRequestProblem {
  final P2pFailure failure;

  const RobotRequestRefused(this.failure);

  @override
  RobotWayOut get wayOut => switch (failure) {
    P2pStorageFailure() ||
    RobotCoordinatorBusyFailure() ||
    RobotKeyComputeFailure() => RobotWayOut.readBack,
    GarageKeyMissingFailure() ||
    GarageKeyAlreadyStoredFailure() ||
    GarageKeyLockedFailure() ||
    GarageKeyUnreadableFailure() ||
    GarageKeyUnusableFailure() ||
    GarageKeyNotSavedFailure() ||
    GarageKeyNotDeletedFailure() ||
    GarageKeyInvalidFailure() ||
    GarageRobotUnavailableFailure() ||
    RobotBoundToAnotherCoordinatorFailure() ||
    RobotCoordinatorChangedFailure() ||
    RobotHistoryUnknownFailure() ||
    RobotNotBoundFailure() ||
    RobotCoordinatorTooManyRefusalsFailure() ||
    RobotReleasedFailure() => RobotWayOut.none,
  };

  @override
  String toString() => 'RobotRequestRefused(${failure.runtimeType})';
}

/// The coordinator, or the transport to it, answered with a [CoordinatorFailure].
final class RobotRequestAnswered extends RobotRequestProblem {
  final CoordinatorFailure failure;

  const RobotRequestAnswered(this.failure);

  @override
  RobotWayOut get wayOut => switch (failure) {
    RobotUnknown() => RobotWayOut.firstContact,
    RobotKeysRefused(reason: RobotKeysRefusal.keyTooRecent) =>
      RobotWayOut.firstContact,
    RobotKeysRefused() ||
    RobotCredentialsRejected() ||
    RobotNicknameTaken() ||
    RobotMismatchFailure() => RobotWayOut.none,
    CoordinatorTransportFailure() ||
    CoordinatorNotOnNetwork() ||
    CoordinatorUnexpectedStatus() ||
    CoordinatorNotJson() ||
    CoordinatorResponseMalformed() ||
    CoordinatorIdentityFailure() => RobotWayOut.readBack,
  };

  @override
  String toString() => 'RobotRequestAnswered(${failure.runtimeType})';
}
