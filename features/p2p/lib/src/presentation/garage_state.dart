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

  /// Whether the key was generated or imported by the user during this visit of the Garage, which then stays in the wizard rather than going to the profile.
  final bool isNew;

  /// Whether the key was drawn in this run of the app and the user has not yet seen it and pressed « Continue »: the Garage shows the backup alert.
  final bool awaitsBackup;

  /// Whether the key may be shown without asking for the PIN: only right after the vault drew it, while the user stays in the Garage with the app in the foreground.
  final bool showWithoutPin;

  /// Why the last action of the user failed, when it did: a robot that could not be derived, or a key that could not be deleted.
  final P2pFailure? failure;

  /// Whether this cubit drew the key and this device could not record that it did: its history is unknown, and the robot step and the profile say so.
  final bool historyNotRecorded;

  /// Whether deleting the key, by « Delete All » or « Generate new », asks the wallet's PIN after « Delete Garage Key? », as the feature's database said when the key was read: without the shell's re-authentication, the delete is then disabled.
  ///
  /// The cubit reads the database again when the user deletes, and decides from that read; this only greys the buttons, and is `true` unless the database said otherwise.
  final bool deletionNeedsPin;

  const GarageWithKey(
    super.network, {
    required this.key,
    required this.robot,
    required this.isNew,
    this.awaitsBackup = false,
    this.showWithoutPin = false,
    this.failure,
    this.historyNotRecorded = false,
    this.deletionNeedsPin = true,
  });

  /// This state with the fields given changed; [failure] is the outcome of the action that leads to the copy, so it is replaced, by nothing when it is not given.
  GarageWithKey copyWith({
    GarageRobotFace? robot,
    bool? awaitsBackup,
    bool? showWithoutPin,
    bool? deletionNeedsPin,
    P2pFailure? failure,
  }) => GarageWithKey(
    network,
    key: key,
    robot: robot ?? this.robot,
    isNew: isNew,
    awaitsBackup: awaitsBackup ?? this.awaitsBackup,
    showWithoutPin: showWithoutPin ?? this.showWithoutPin,
    failure: failure,
    historyNotRecorded: historyNotRecorded,
    deletionNeedsPin: deletionNeedsPin ?? this.deletionNeedsPin,
  );
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

  /// Deleting the entry always asks the wallet's PIN after « Delete Garage Key? »: the keystore may give its key back later, intact and possibly with robots on coordinators, and nothing tells which key it holds; so without the shell's re-authentication the delete is disabled.
  ///
  /// This covers a key that can be read but gives no robot, and so no fingerprint either.
  bool get deletionNeedsPin => true;
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
