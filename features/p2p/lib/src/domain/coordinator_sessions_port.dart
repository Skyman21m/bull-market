import 'package:robosats/robosats.dart';

/// The Tor sessions the feature keeps open to the coordinators.
abstract interface class CoordinatorSessionsPort {
  /// Closes every session: requests still running on them fail, and the next request opens new sessions.
  Future<void> closeSessions();

  /// Closes the sessions of [robot] to every coordinator: its requests still running fail, and its next request opens a new session.
  Future<void> closeRobotSessions(RobotSessionKey robot);
}
