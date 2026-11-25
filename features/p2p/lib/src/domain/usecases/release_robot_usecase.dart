import 'dart:async';

import '../network_garage_key.dart';
import '../robot_request_limiter.dart';
import 'close_robot_sessions_usecase.dart';

/// Lets go of a robot whose screen is gone: the requests of that screen's calls still waiting are dropped, those in flight are let end, and then the robot's Tor sessions are closed once nothing uses the robot any more.
///
/// Only the calls of the screen's [RobotCallOwner] are stopped: a trade of the robot (its watch, its chat, its actions) goes on (#251, security review of PR 274, C1). Its sessions are then closed when the last call of the trade has ended ([RobotRequestLimiter.idle]), never under one.
/// The Nostr copies of a chat message use the robot's sessions outside the limiter and are not waited for: one sent just before that closing may fail, the message itself having reached the coordinator (#275).
/// Closing the sessions is not a lock (`CoordinatorSessionsPort.closeRobotSessions`): a call still running may send one more request on a new session after a close, so the sessions are closed once the requests of the robot in flight have ended, or after [RobotRequestLimiter.releaseWait] at the latest and again once they have.
final class ReleaseRobotUsecase {
  final RobotRequestLimiter _limiter;
  final CloseRobotSessionsUsecase _closeSessions;

  const ReleaseRobotUsecase(this._limiter, this._closeSessions);

  /// Releases the calls of [owner] for [robot] in [RobotRequestLimiter], then closes the robot's sessions to every coordinator.
  ///
  /// The calls [owner] made for it so far send nothing more; a call opened for it since, as when the user comes back to it at once, keeps the sessions it uses, and its own release closes them.
  /// When calls no release stops are still running, those of a trade, the sessions are left to them and closed once the robot is idle, without the caller waiting for it.
  Future<void> execute(
    NetworkRobot robot, {
    required RobotCallOwner owner,
  }) async {
    final identity = robot.identity;
    final release = _limiter.release(identity.sessionKey, owner: owner);
    final endedInTime = await release.endedInTime;
    if (_limiter.isInUse(identity.sessionKey)) {
      unawaited(_closeWhenIdle(robot));
      return;
    }
    await _closeSessions.execute(identity);
    if (endedInTime) return;
    // A request still in flight at the bound fails on its closed session, or may open a new one: closed again once it has ended.
    await release.ended;
    if (!_limiter.isInUse(identity.sessionKey)) {
      await _closeSessions.execute(identity);
    }
  }

  /// Closes the sessions of [robot] once no call uses it any more and no request of a released call is in flight: the robot's trade ended its last call.
  Future<void> _closeWhenIdle(NetworkRobot robot) async {
    final key = robot.identity.sessionKey;
    await _limiter.idle(key);
    if (!_limiter.isInUse(key)) await _closeSessions.execute(robot.identity);
  }
}
