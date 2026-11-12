import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show Coordinator, CoordinatorFailure;

import '../domain/network_garage_key.dart';
import '../domain/p2p_failure.dart';
import '../domain/p2p_tor_state.dart';
import '../domain/robot_binding.dart';
import '../domain/robot_host.dart';
import '../domain/robot_on_coordinator_face.dart';
import '../domain/tor_wait.dart';
import '../domain/usecases/list_robot_hosts_usecase.dart';
import '../domain/usecases/put_robot_on_coordinator_usecase.dart';
import '../domain/usecases/read_robot_on_coordinator_usecase.dart';
import '../domain/usecases/read_robot_standing_usecase.dart';
import '../domain/usecases/release_robot_usecase.dart';
import '../domain/usecases/watch_p2p_tor_state_usecase.dart';
import 'robot_coordinator_state.dart';

/// The panel of one robot of the Garage: where the robot stands with a coordinator, read on the device, then what its coordinator says of it.
///
/// There is one per robot shown, made from the Garage Key of the Garage and the robot's index, and closed when the user moves to another robot or leaves the Garage.
/// It derives the robot from the key only when it calls a use case, and keeps no robot: its states hold no token, no key and no fingerprint.
///
/// A robot that no coordinator received from this device is put on one only by [putOn], which the screen calls once the user chose a coordinator in « Select Host » and confirmed it.
/// A robot bound to a coordinator of its network is read back from it at once when Tor is ready, as the official client reads its robots each time it shows them; the coordinator is always the one the binding names, never one a screen gives.
/// Closing it releases the robot ([ReleaseRobotUsecase]): its requests still waiting are dropped, one already sent ends and its answer is ignored.
/// The rules (binding, places, retries, refusal caps, proof of the key pair) are the use cases': this cubit only calls them and shows what they return.
class RobotCoordinatorCubit extends Cubit<RobotCoordinatorState> {
  final NetworkGarageKey _key;
  final int _index;
  final ReadRobotStandingUsecase _readStanding;
  final PutRobotOnCoordinatorUsecase _putOnCoordinator;
  final ReadRobotOnCoordinatorUsecase _readOnCoordinator;
  final ReleaseRobotUsecase _release;
  final WatchP2pTorStateUsecase _watchTor;
  final ListRobotHostsUsecase _listHosts;

  /// How long a request runs before the panel says it is still waiting.
  final Duration _stillWaitingAfter;

  /// The panel says that a request is still waiting once it has run this long.
  static const stillWaitingAfter = Duration(seconds: 30);

  StreamSubscription<P2pTorReport>? _torReports;
  TorWait _tor = TorWait.initializing;
  Timer? _stillWaiting;

  /// Whether a read of the database or a request is running: an action of the user meanwhile is ignored.
  bool _working = false;

  RobotCoordinatorCubit(
    this._key,
    this._index,
    this._readStanding,
    this._putOnCoordinator,
    this._readOnCoordinator,
    this._release,
    this._watchTor,
    this._listHosts, {
    this._stillWaitingAfter = RobotCoordinatorCubit.stillWaitingAfter,
  }) : super(const RobotStandingReading());

  /// Follows Tor and reads where the robot stands: when the panel is shown.
  ///
  /// It starts nothing: the book of the tab starts Tor.
  Future<void> load() async {
    _torReports ??= _watchTor.execute().listen(_onTor);
    await _settle();
  }

  /// The coordinators « Select Host » lists for this robot's network, in the order of the federation.
  List<RobotHost> hosts() => _listHosts.execute(_key.network).choices;

  /// Puts the robot on [coordinator], which the user chose in « Select Host » and confirmed: the robot's first contact, which binds it to that coordinator for good.
  ///
  /// Only for a robot that no coordinator received from this device, whose key needs no acknowledgement, once Tor is ready, and while nothing else runs; ignored otherwise.
  Future<void> putOn(Coordinator coordinator) async {
    final current = state;
    if (_working || current is! RobotWithoutCoordinator) return;
    if (!current.mayChooseHost) return;
    await _firstContact(coordinator, afterSelectHost: true);
  }

  /// « Retry » after a failure: the database read again, or the robot read back from the coordinator of its binding, or the robot put on that same coordinator again when it said it does not know the robot or refused its key as too recent (`PutRobotOnCoordinatorUsecase` reads a bound robot back first, and makes a first contact only when the coordinator does not know it).
  Future<void> retry() async {
    if (_working) return;
    switch (state) {
      case RobotStandingUnreadable():
        await _settle();
      case RobotOnCoordinator(
        :final coordinator,
        activity: RobotFailed(:final problem),
      ):
        switch (problem.wayOut) {
          case RobotWayOut.readBack:
            await _readBack(coordinator);
          case RobotWayOut.firstContact:
            await _firstContact(coordinator, afterSelectHost: false);
          case RobotWayOut.none:
            return;
        }
      case _:
        return;
    }
  }

  void _onTor(P2pTorReport report) {
    final previous = _tor;
    _tor = previous.after(report.state);
    if (_tor == previous || isClosed) return;
    switch (state) {
      case final RobotWithoutCoordinator current:
        emit(current.withTor(_tor));
      case RobotOnCoordinator(
        :final coordinator,
        activity: RobotWaitingForTor(),
      ):
        if (_tor == TorWait.ready) {
          unawaited(_readBack(coordinator));
        } else {
          emit(RobotOnCoordinator(coordinator, RobotWaitingForTor(_tor)));
        }
      case _:
        return;
    }
  }

  /// Reads where the robot stands and shows it, with [attempt] when a first contact just failed; a robot bound to a coordinator of its network is read back once Tor is ready, unless [attempt] says why its last request failed.
  Future<void> _settle({RobotAttempt? attempt}) async {
    if (isClosed) return;
    _working = true;
    try {
      if (state is RobotStandingUnreadable) emit(const RobotStandingReading());
      final RobotStanding standing;
      switch (switch (_robot()) {
        Ok(value: final robot) => await _readStanding.execute(robot),
        Err(:final failure) => Err<RobotStanding, P2pFailure>(failure),
      }) {
        case Ok(:final value):
          standing = value;
        case Err(:final failure):
          if (!isClosed) emit(RobotStandingUnreadable(failure));
          return;
      }
      if (isClosed) return;
      final binding = standing.binding;
      if (binding == null) {
        emit(
          RobotWithoutCoordinator(
            needsAcknowledgement: standing.needsAcknowledgement,
            tor: _tor,
            lastAttempt: attempt,
          ),
        );
        return;
      }
      if (standing.isBoundOnOtherNetwork) {
        emit(RobotOnOtherNetwork(binding.coordinator.network));
        return;
      }
      final hosts = _listHosts.execute(_key.network);
      switch (hosts.boundTo(binding)) {
        case Ok(value: final coordinator):
          if (attempt != null) {
            emit(RobotOnCoordinator(coordinator, RobotFailed(attempt.problem)));
          } else if (_tor != TorWait.ready) {
            emit(RobotOnCoordinator(coordinator, RobotWaitingForTor(_tor)));
          } else {
            _working = false;
            await _readBack(coordinator);
          }
        case Err():
          final alias = binding.coordinator.alias;
          emit(RobotCoordinatorChanged(alias, hosts.listed(alias)));
      }
    } finally {
      _working = false;
    }
  }

  /// The robot read back from [coordinator], the coordinator of its binding; [ReadRobotOnCoordinatorUsecase] reads the binding again and sends nothing to any other.
  Future<void> _readBack(Coordinator coordinator) async {
    if (isClosed || _working) return;
    _working = true;
    try {
      _contacting(coordinator, RobotContactKind.read);
      final _Shown result = switch (_robot()) {
        Ok(value: final robot) => await _readOnCoordinator.execute(robot),
        Err(:final failure) => Err(failure),
      };
      _stillWaiting?.cancel();
      if (isClosed) return;
      emit(switch (result) {
        Err(failure: RobotCoordinatorChangedFailure()) =>
          RobotCoordinatorChanged(coordinator.shortAlias, coordinator),
        Err(:final failure) => RobotOnCoordinator(
          coordinator,
          RobotFailed(RobotRequestRefused(failure)),
        ),
        Ok(value: Err(:final failure)) => RobotOnCoordinator(
          coordinator,
          RobotFailed(RobotRequestAnswered(failure)),
        ),
        Ok(value: Ok(value: final face)) => RobotOnCoordinator(
          coordinator,
          RobotKnown(face),
        ),
      });
    } finally {
      _working = false;
    }
  }

  /// The robot put on [coordinator] (`PutRobotOnCoordinatorUsecase`): the first contact of a robot without a binding, which binds it there before anything leaves, or, for a robot bound there, a read back and a first contact only if the coordinator does not know it; a failure is shown where the robot stands afterwards, read again on the device.
  ///
  /// [afterSelectHost] tells the card whether this is the user's « Select Host » for a robot no coordinator had received from this device (`RobotKnown.afterSelectHost`).
  Future<void> _firstContact(
    Coordinator coordinator, {
    required bool afterSelectHost,
  }) async {
    if (isClosed || _working) return;
    _working = true;
    final RobotRequestProblem problem;
    try {
      _contacting(coordinator, RobotContactKind.create);
      final _Shown result = switch (_robot()) {
        Ok(value: final robot) => await _putOnCoordinator.execute(
          robot,
          coordinator,
        ),
        Err(:final failure) => Err(failure),
      };
      _stillWaiting?.cancel();
      if (isClosed) return;
      switch (result) {
        case Ok(value: Ok(value: final face)):
          emit(
            RobotOnCoordinator(
              coordinator,
              RobotKnown(face, afterSelectHost: afterSelectHost),
            ),
          );
          return;
        case Ok(value: Err(:final failure)):
          problem = RobotRequestAnswered(failure);
        case Err(:final failure):
          problem = RobotRequestRefused(failure);
      }
    } finally {
      _working = false;
    }
    await _settle(attempt: RobotAttempt(coordinator, problem));
  }

  /// Shows that a request of [kind] to [coordinator] runs, and that it is still waiting after [_stillWaitingAfter].
  void _contacting(Coordinator coordinator, RobotContactKind kind) {
    emit(RobotOnCoordinator(coordinator, RobotContacting(kind)));
    _stillWaiting?.cancel();
    _stillWaiting = Timer(_stillWaitingAfter, () {
      final current = state;
      if (isClosed || current is! RobotOnCoordinator) return;
      if (current.activity case RobotContacting(:final kind, slow: false)) {
        emit(
          RobotOnCoordinator(
            current.coordinator,
            RobotContacting(kind, slow: true),
          ),
        );
      }
    });
  }

  /// The robot of this panel, derived from the key now: the robot at the index shown, or a failure when the key gives another one there.
  Result<NetworkRobot, P2pFailure> _robot() =>
      switch (_key.firstUsableRobot(_index)) {
        Ok(value: final robot) when robot.accountIndex == _index => Ok(robot),
        Ok() => const Err(GarageRobotUnavailableFailure()),
        Err(:final failure) => Err(failure),
      };

  @override
  Future<void> close() async {
    _stillWaiting?.cancel();
    unawaited(_torReports?.cancel());
    _torReports = null;
    await super.close();
    // Closed first, so that an answer arriving during the release is ignored.
    if (_robot() case Ok(value: final robot)) {
      await _release.execute(robot);
    }
  }
}

/// What the robot use cases return: a refusal of the feature, or what the coordinator answered, its robot shown.
typedef _Shown =
    Result<Result<RobotOnCoordinatorFace, CoordinatorFailure>, P2pFailure>;
