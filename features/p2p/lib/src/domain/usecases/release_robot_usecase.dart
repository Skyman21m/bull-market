import '../network_garage_key.dart';
import '../robot_request_limiter.dart';
import 'close_robot_sessions_usecase.dart';

/// Lets go of a robot whose screen is gone: its requests still waiting are dropped, those in flight are let end, and then its Tor sessions are closed.
///
/// Closing the sessions is not a lock (`CoordinatorSessionsPort.closeRobotSessions`): a call still running may send one more request on a new session after a close, so the sessions are closed once the requests of the robot in flight have ended, or after [RobotRequestLimiter.releaseWait] at the latest and again once they have.
final class ReleaseRobotUsecase {
  final RobotRequestLimiter _limiter;
  final CloseRobotSessionsUsecase _closeSessions;

  const ReleaseRobotUsecase(this._limiter, this._closeSessions);

  /// Releases [robot] in [RobotRequestLimiter], then closes its sessions to every coordinator.
  ///
  /// The calls made for it so far send nothing more; a call opened for it since, as when the user comes back to it at once, keeps the sessions it uses, and its own release closes them.
  Future<void> execute(NetworkRobot robot) async {
    final identity = robot.identity;
    final release = _limiter.release(identity.sessionKey);
    final endedInTime = await release.endedInTime;
    if (!_limiter.isInUse(identity.sessionKey)) {
      await _closeSessions.execute(identity);
    }
    if (endedInTime) return;
    // A request still in flight at the bound fails on its closed session, or may open a new one: closed again once it has ended.
    await release.ended;
    if (!_limiter.isInUse(identity.sessionKey)) {
      await _closeSessions.execute(identity);
    }
  }
}
