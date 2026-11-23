/// Short commit of the build, empty for a local build. Supplied at build time
/// with `--dart-define=BUILD_COMMIT=<short sha>`.
const _buildCommit = String.fromEnvironment('BUILD_COMMIT');

/// Returns the version shown in the settings, e.g. `6.13.0+228 (abc1234)`.
///
/// [version] already carries the build number. [commit] is appended in
/// parentheses only when it holds something once trimmed, so an empty or
/// whitespace-only commit leaves [version] untouched.
String formatAppVersion(String version, {String commit = _buildCommit}) {
  final shortCommit = commit.trim();
  if (shortCommit.isEmpty) return version;
  return '$version ($shortCommit)';
}
