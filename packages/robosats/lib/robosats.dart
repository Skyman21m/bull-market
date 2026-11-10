/// Pure-Dart RoboSats client primitives: the identity of a robot.
///
/// A [GarageKey] derives one [RobotToken] per robot index, and a [RobotIdentity] holds everything RoboSats derives from a token: the token hash sent to coordinators, the [RobotHashId] with its nickname, the Nostr key and the `Authorization` header values.
/// Invalid input is reported as a [RobosatsFailure] in a `Result`, never thrown.
/// No Flutter, no networking, no PGP, no logging.
library;

export 'src/garage_key.dart' show GarageKey;
export 'src/nostr_key_pair.dart' show NostrKeyPair;
export 'src/robosats_failure.dart';
export 'src/robot_hash_id.dart' show RobotHashId;
export 'src/robot_identity.dart' show NostrKeyDerivation, RobotIdentity;
export 'src/robot_token.dart' show RobotToken, TokenEntropy;
