import 'package:meta/meta.dart';
import 'package:robosats/src/robot_hash_id.dart';

/// Names the robot a request to a coordinator is made for, so that the transport keeps the requests of one robot apart from everything else.
///
/// Two keys are equal when they name the same robot.
/// It is built from the public hash id of the robot and holds no credential.
/// It still prints nothing: a line that ties requests to a robot is what the isolation is there to prevent.
@immutable
final class RobotSessionKey {
  final String _hashId;

  /// The key of the robot identified by [hashId]: use `RobotIdentity.sessionKey`.
  @internal
  RobotSessionKey.of(RobotHashId hashId) : _hashId = hashId.hex;

  @override
  bool operator ==(Object other) =>
      other is RobotSessionKey && other._hashId == _hashId;

  @override
  int get hashCode => _hashId.hashCode;

  @override
  String toString() => 'RobotSessionKey(<redacted>)';
}
