import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../network_garage_key.dart';
import '../p2p_failure.dart';
import '../repositories/robot_binding_repository.dart';
import '../robot_binding.dart';
import '../robot_on_coordinator_face.dart';
import '../robot_request_limiter.dart';
import 'fetch_robot_usecase.dart';

/// Reads a robot of this device back from the coordinator it is bound to, as the Garage does each time it shows a bound robot: no key is sent, nothing is created, and nothing is stored.
///
/// The coordinator is the one the robot's binding names, read from the feature's database: a screen never chooses it.
/// Both networks are accepted: the robot's network is that of its key's slot, which follows the wallet's (owner's decision of 2026-11-12); nothing here moves money.
final class ReadRobotOnCoordinatorUsecase {
  final FetchRobotUsecase _fetch;
  final RobotBindingRepository _bindings;
  final RobotRequestLimiter _limiter;
  final Federation _federation;

  const ReadRobotOnCoordinatorUsecase(
    this._fetch,
    this._bindings,
    this._limiter,
    this._federation,
  );

  /// [robot] read back from its coordinator with the short header, its key pair proven by its token, through the places of the coordinator in [RobotRequestLimiter].
  ///
  /// The binding is read first, and nothing is sent when it does not name a coordinator of the robot's network: [RobotNotBoundFailure] for a robot sent to no coordinator, [RobotBoundToAnotherCoordinatorFailure] for one bound on the other network, [RobotCoordinatorChangedFailure] for a coordinator that the federation list of this version of the app no longer has on that network, [P2pStorageFailure] for a database that cannot be read.
  /// [FetchRobotUsecase] checks the binding again against the coordinator as the list gives it now.
  /// A busy answer of the transport is sent again after a growing wait, as [RobotRequestLimiter] says; [RobotCoordinatorBusyFailure] when that does not get through, and [RobotReleasedFailure] once the robot was released.
  /// The inner result is what the coordinator answered, checked: [RobotUnknown] for a robot bound there whose first contact never created it, or its robot shown as a [RobotOnCoordinatorFace].
  Future<Result<Result<RobotOnCoordinatorFace, CoordinatorFailure>, P2pFailure>>
  execute(NetworkRobot robot) async {
    final RobotStanding standing;
    switch (await _bindings.standingOf(robot.slot)) {
      case Ok(:final value):
        standing = value;
      case Err(:final failure):
        return Err(failure);
    }
    final binding = standing.binding;
    if (binding == null) return const Err(RobotNotBoundFailure());
    if (standing.isBoundOnOtherNetwork) {
      return const Err(RobotBoundToAnotherCoordinatorFailure());
    }
    final coordinator = _federation.byAlias(binding.coordinator.alias);
    if (coordinator == null ||
        CoordinatorIdentity.of(coordinator, robot.network) == null) {
      return const Err(RobotCoordinatorChangedFailure());
    }
    final requests = _limiter.open(robot.identity.sessionKey);
    try {
      return switch (await requests.send(
        robot.network,
        coordinator,
        () => _fetch.execute(coordinator, RobotContact.readBack(robot)),
        isBusy: FetchRobotUsecase.answeredBusy,
      )) {
        Err(:final failure) || Ok(value: Err(:final failure)) => Err(failure),
        Ok(value: Ok(value: Err(:final failure))) => Ok(Err(failure)),
        Ok(value: Ok(value: Ok(value: final known))) => Ok(
          Ok(RobotOnCoordinatorFace.of(known, alreadyExisted: false)),
        ),
      };
    } finally {
      requests.close();
    }
  }
}
