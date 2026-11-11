import 'package:robosats/robosats.dart';

import '../coordinator_sessions_port.dart';

/// Releases the Tor sessions of one robot, when it is no longer used.
///
/// Call it once the calls made for that robot have ended: see [CoordinatorSessionsPort.closeRobotSessions].
final class CloseRobotSessionsUsecase {
  final CoordinatorSessionsPort _sessions;

  const CloseRobotSessionsUsecase(this._sessions);

  Future<void> execute(RobotIdentity identity) =>
      _sessions.closeRobotSessions(identity.sessionKey);
}
