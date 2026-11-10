/// The Tor sessions the feature keeps open to the coordinators.
abstract interface class CoordinatorSessionsPort {
  /// Closes every session: requests still running on them fail, and the next request opens new sessions.
  Future<void> closeSessions();
}
