import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../domain/network_garage_key.dart';
import '../domain/p2p_failure.dart';

/// What the Garage knows about the Garage Key of its network.
///
/// No state holds the text of a key, a token or anything typed by the user: a key is held as a [NetworkGarageKey], whose clear forms only `GarageKeyView` and the repository may reach, and a robot as the [GarageRobotFace] the screens draw.
/// The states are compared by identity and print their type only.
sealed class GarageState {
  /// The network whose slot of the vault the Garage reads.
  final RobosatsNetwork network;

  const GarageState(this.network);

  @override
  String toString() => '$runtimeType(${network.name})';
}

/// The vault is being read or written.
final class GarageWorking extends GarageState {
  const GarageWorking(super.network);
}

/// No Garage Key is stored for this network, as the vault concluded after its full read budget, or after a delete it confirmed: the only state in which a key may be generated or imported.
final class GarageWithoutKey extends GarageState {
  /// Why the last action of the user failed, when it did: a key that could not be stored, or text that is not a Garage Key.
  final P2pFailure? failure;

  const GarageWithoutKey(super.network, {this.failure});
}

/// A Garage Key is stored for this network: its robot shown, and the key itself for `GarageKeyView`.
final class GarageWithKey extends GarageState {
  final NetworkGarageKey key;
  final GarageRobotFace robot;

  /// Whether the key was generated or imported by the user during this visit of the Garage: only such a key is shown for backup without asking the user to authenticate again.
  final bool isNew;

  /// Why the last action of the user failed, when it did: a robot that could not be derived, or a key that could not be deleted.
  final P2pFailure? failure;

  const GarageWithKey(
    super.network, {
    required this.key,
    required this.robot,
    required this.isNew,
    this.failure,
  });
}

/// The vault could not say whether a key is stored: a locked keystore, or an entry that cannot be read or is damaged.
///
/// Nothing may be generated or imported then; the user may try again, and delete the entry unless the keystore is locked.
final class GarageUnknown extends GarageState {
  /// Why the vault could not say.
  final P2pFailure failure;

  /// Why the last action of the user failed, when it did: a key that could not be deleted, for one.
  final P2pFailure? actionFailure;

  const GarageUnknown(super.network, this.failure, {this.actionFailure});
}

/// What the screens show of a robot: its number, nickname and hash id, all public, and never its token.
final class GarageRobotFace {
  /// The robot number, the « Robot #N » of the account navigator.
  final int index;

  final String nickname;

  /// The hash id of the robot in hexadecimal, the seed of its avatar.
  final String hashId;

  const GarageRobotFace({
    required this.index,
    required this.nickname,
    required this.hashId,
  });

  /// The face of [robot], which is then dropped with its token.
  factory GarageRobotFace.of(NetworkRobot robot) => GarageRobotFace(
    index: robot.accountIndex,
    nickname: robot.identity.nickname,
    hashId: robot.identity.hashId.hex,
  );

  @override
  bool operator ==(Object other) =>
      other is GarageRobotFace &&
      other.index == index &&
      other.nickname == nickname &&
      other.hashId == hashId;

  @override
  int get hashCode => Object.hash(index, nickname, hashId);

  @override
  String toString() => 'GarageRobotFace($index, $nickname)';
}
