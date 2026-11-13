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

  /// The first contact that failed just before this read, when one did: its request may have left, so the panel says what it got and does not say that nothing was sent (security review of step 5).
  final RobotAttempt? lastAttempt;

  const RobotStandingUnreadable(this.failure, {this.lastAttempt});
}

/// No coordinator received the robot from this device: « Select Host » may put it on one, on the user's request.
final class RobotWithoutCoordinator extends RobotCoordinatorState {
  /// Whether the history of the robot's key must be acknowledged before the robot can go anywhere: « Select Host » asks it first, « Robots from elsewhere », once per key and network.
  final bool needsAcknowledgement;

  /// Where Tor stands: « Select Host » waits for it to be ready.
  final TorWait tor;

  /// The coordinator a first contact that failed before binding the robot was for, and why it failed, when one did.
  final RobotAttempt? lastAttempt;

  /// Why the acknowledgement the user just gave could not be recorded, when it could not: nothing was recorded or sent, and « Select Host » asks it again.
  final P2pFailure? acknowledgementFailure;

  const RobotWithoutCoordinator({
    required this.needsAcknowledgement,
    required this.tor,
    this.lastAttempt,
    this.acknowledgementFailure,
  });

  /// Whether « Select Host » may be pressed now: Tor is ready; for a key whose history needs the acknowledgement, it asks that first.
  bool get maySelectHost => tor == TorWait.ready;

  /// Whether the robot may be given a coordinator now, from the sheet of « Select Host »: Tor is ready, and the key's history needs no acknowledgement.
  bool get mayChooseHost => maySelectHost && !needsAcknowledgement;

  /// This state with Tor at [tor].
  RobotWithoutCoordinator withTor(TorWait tor) => RobotWithoutCoordinator(
    needsAcknowledgement: needsAcknowledgement,
    tor: tor,
    lastAttempt: lastAttempt,
    acknowledgementFailure: acknowledgementFailure,
  );

  /// This state with the acknowledgement refused by [failure]: still needed, nothing recorded.
  RobotWithoutCoordinator withAcknowledgementFailure(P2pFailure failure) =>
      RobotWithoutCoordinator(
        needsAcknowledgement: needsAcknowledgement,
        tor: tor,
        lastAttempt: lastAttempt,
        acknowledgementFailure: failure,
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

  const RobotKnown(this.face);
}

/// The last request failed: why, and the way out the panel offers.
final class RobotFailed extends RobotActivity {
  final RobotRequestProblem problem;

  /// Which call failed: a put of the robot on its coordinator ([RobotContactKind.create]), whose read back or first contact may have left before a later step was refused, or a read back ([RobotContactKind.read]), which sends nothing when the feature refuses it.
  ///
  /// So a refusal of the database after a put never says that nothing was sent (second security pass on step 5).
  final RobotContactKind kind;

  const RobotFailed(this.problem, {required this.kind});
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
    RobotReleasedFailure() ||
    // The failures of the trade records and of the robot of a new trade (#85): no robot request of the panel gives them.
    GarageKeyNotForTradesFailure() ||
    TradeCoordinatorNotOnNetworkFailure() ||
    TradeKeyMissingFailure() ||
    TradeAlreadyRecordedFailure() ||
    RobotNotForNewTradeFailure() ||
    TradeClosedFailure() => RobotWayOut.none,
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
