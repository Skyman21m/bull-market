import '../coordinator_sessions_port.dart';

/// Releases the Tor sessions to the coordinators, when the P2P screens no longer need them.
final class CloseCoordinatorSessionsUsecase {
  final CoordinatorSessionsPort _sessions;

  const CloseCoordinatorSessionsUsecase(this._sessions);

  Future<void> execute() => _sessions.closeSessions();
}
