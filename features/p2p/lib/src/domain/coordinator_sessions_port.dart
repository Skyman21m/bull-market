import 'package:robosats/robosats.dart';

/// The Tor sessions the feature keeps open to the coordinators.
abstract interface class CoordinatorSessionsPort {
  /// Closes every session: requests still running on them fail, and the next request opens new sessions.
  Future<void> closeSessions();

  /// Closes the sessions of [robot] to every coordinator: its requests still running fail, and its next request opens a new session.
  ///
  /// It is not a lock: a call for that robot that is still running, such as a `fetchRobot` between its two requests, may send its next request on a new session after this.
  /// So let the calls made for a robot end, or drop them, before closing its sessions for good.
  Future<void> closeRobotSessions(RobotSessionKey robot);
}
