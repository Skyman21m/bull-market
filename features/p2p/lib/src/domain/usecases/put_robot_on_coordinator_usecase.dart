import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../network_garage_key.dart';
import '../p2p_failure.dart';
import '../repositories/robot_binding_repository.dart';
import '../robot_binding.dart';
import '../robot_on_coordinator_face.dart';
import '../robot_request_limiter.dart';
import 'fetch_robot_usecase.dart';

/// Puts a robot of this device on the coordinator the user chose: its first contact, which creates it there when the coordinator does not know it, and binds it to that coordinator for good.
///
/// It runs only on the user's explicit request: a robot is an account on a third-party server, which this client cannot delete.
/// Both networks are accepted: the robot's network is that of its key's slot, which follows the wallet's (owner's decision of 2026-11-12); nothing here moves money.
final class PutRobotOnCoordinatorUsecase {
  final FetchRobotUsecase _fetch;
  final RobotBindingRepository _bindings;
  final RobotRequestLimiter _limiter;

  const PutRobotOnCoordinatorUsecase(
    this._fetch,
    this._bindings,
    this._limiter,
  );

  /// [robot] put on [coordinator], through the places of the coordinator in [RobotRequestLimiter], and what the coordinator then says of the robot.
  ///
  /// The robot's binding is read first, and nothing is sent when it names another coordinator, on either network, or one whose onion address or keys changed since ([RobotBoundToAnotherCoordinatorFailure], [RobotCoordinatorChangedFailure]), or when the database cannot be read ([P2pStorageFailure]).
  /// A robot already bound to [coordinator] is read back first, with the short header: a coordinator that knows it, as after a first contact whose answer was lost, gives it, and no first contact is sent, so it never receives a second pair for that robot; only [RobotUnknown] leads to a first contact.
  /// A robot without a binding goes straight to its first contact.
  ///
  /// The first contact goes through [FetchRobotUsecase], which binds the robot before anything leaves, makes its key pair away from the UI isolate, sends it, and proves any other pair the coordinator returns; the pair is made once and sent again with each retry, so the coordinator never gets two pairs from one call.
  /// A busy answer of the transport is sent again after a growing wait, on either request, as [RobotRequestLimiter] says; [RobotCoordinatorBusyFailure] when that does not get through.
  /// No other failure is sent again: a request that timed out or failed in the transport may have reached the coordinator, and a later call reads the robot, bound by then, before any new first contact.
  /// A nickname already taken (error 7004), which the client of the package has already read back once, is read back once more after [RobotRequestLimiter.nicknameRecheckWait], with the short header: the coordinator may have created the robot for another copy of the same request meanwhile, and the robot it holds is taken, proven by the token.
  /// Still unknown there, it is [RobotNicknameTaken]: the robot stays bound to that coordinator, and nothing moves to the next robot, which the user does by hand.
  /// A first contact holds a slot of the coordinator's cap of [RobotRequestLimiter.maxNicknameRefusals] refusals from before its request until its outcome is known, and a nickname taken that the read after it does not resolve (still unknown, unanswered, or never sent because the robot was released) uses the slot up for the run; with no slot left, a first contact fails at once with [RobotCoordinatorTooManyRefusalsFailure], before anything is written or sent for it.
  ///
  /// The outer [Err] is a [P2pFailure]: a refusal of the binding, of [FetchRobotUsecase] or of the limiter, or [RobotReleasedFailure] once the robot was released, from the start of the call, the read of the binding included: nothing is then bound or sent.
  /// The inner result is what the coordinator answered, checked, its robot shown as a [RobotOnCoordinatorFace] whose [RobotOnCoordinatorFace.alreadyExisted] says that the coordinator returned a key pair this call did not send: found by the first read of a robot already bound there, or another pair answered to the first contact.
  Future<Result<Result<RobotOnCoordinatorFace, CoordinatorFailure>, P2pFailure>>
  execute(NetworkRobot robot, Coordinator coordinator) async {
    // Opened before the binding is read, so that a release of the robot during that read stops the call before it binds or sends anything (security review of step 5).
    final requests = _limiter.open(robot.identity.sessionKey);
    try {
      final RobotStanding standing;
      switch (await _bindings.standingOf(robot.slot)) {
        case Ok(:final value):
          standing = value;
        case Err(:final failure):
          return Err(failure);
      }
      if (standing.binding case final binding?) {
        final identity = CoordinatorIdentity.of(coordinator, robot.network);
        if (identity == null) return const Ok(Err(CoordinatorNotOnNetwork()));
        if (binding.admits(identity) case Err(:final failure)) {
          return Err(failure);
        }
        final known = await requests.send(
          robot.network,
          coordinator,
          () => _fetch.execute(coordinator, RobotContact.readBack(robot)),
          isBusy: FetchRobotUsecase.answeredBusy,
        );
        if (!_isUnknown(known)) return _shown(known, (_) => true);
      }
      return await _firstContact(requests, robot, coordinator);
    } finally {
      requests.close();
    }
  }

  /// The first contact of [robot] with [coordinator], with the read 10 s after a nickname taken, holding a slot of the coordinator's cap meanwhile.
  Future<Result<Result<RobotOnCoordinatorFace, CoordinatorFailure>, P2pFailure>>
  _firstContact(
    RobotRequests requests,
    NetworkRobot robot,
    Coordinator coordinator,
  ) async {
    final slot = _limiter.holdFirstContactSlot(robot.network, coordinator);
    if (slot == null) {
      return const Err(RobotCoordinatorTooManyRefusalsFailure());
    }
    var refused = false;
    try {
      final contact = RobotContact.firstContact(robot);
      bool sentAnother(CoordinatorRobot found) => !contact.sentThePairOf(found);
      final first = await requests.send(
        robot.network,
        coordinator,
        () => _fetch.execute(coordinator, contact),
        isBusy: FetchRobotUsecase.answeredBusy,
      );
      final nicknameTaken = switch (first) {
        Ok(value: Ok(value: Err(failure: RobotNicknameTaken()))) => true,
        _ => false,
      };
      if (!nicknameTaken) return _shown(first, sentAnother);
      // A refusal received: it counts unless the read that follows finds the robot.
      refused = true;
      final again = await requests.send(
        robot.network,
        coordinator,
        () => _fetch.execute(coordinator, RobotContact.readBack(robot)),
        isBusy: FetchRobotUsecase.answeredBusy,
        after: RobotRequestLimiter.nicknameRecheckWait,
      );
      if (again case Ok(value: Ok(value: Ok()))) refused = false;
      if (_isUnknown(again)) return const Ok(Err(RobotNicknameTaken()));
      return _shown(again, sentAnother);
    } finally {
      slot.end(refused: refused);
    }
  }

  static bool _isUnknown(
    Result<
      Result<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure>,
      P2pFailure
    >
    result,
  ) => switch (result) {
    Ok(value: Ok(value: Err(failure: RobotUnknown()))) => true,
    _ => false,
  };

  /// [result] with its robot shown, [alreadyExisted] telling whether it came back with a pair this call did not send.
  static Result<Result<RobotOnCoordinatorFace, CoordinatorFailure>, P2pFailure>
  _shown(
    Result<
      Result<Result<CoordinatorRobot, CoordinatorFailure>, P2pFailure>,
      P2pFailure
    >
    result,
    bool Function(CoordinatorRobot robot) alreadyExisted,
  ) => switch (result) {
    Err(:final failure) || Ok(value: Err(:final failure)) => Err(failure),
    Ok(value: Ok(value: Err(:final failure))) => Ok(Err(failure)),
    Ok(value: Ok(value: Ok(value: final robot))) => Ok(
      Ok(
        RobotOnCoordinatorFace.of(robot, alreadyExisted: alreadyExisted(robot)),
      ),
    ),
  };
}
