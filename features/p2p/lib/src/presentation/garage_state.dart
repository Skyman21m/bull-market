import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../domain/garage_key_fingerprint.dart';
import '../domain/network_garage_key.dart';
import '../domain/p2p_failure.dart';

/// What the Garage knows about the Garage Key of its network.
///
/// No state holds the text of a key, a token or anything typed by the user: a key is held as a [NetworkGarageKey], whose clear forms only `GarageKeyView` and the repository may reach, and a robot as the [GarageRobotFace] the screens draw.
/// The states are compared by identity and print their type only.
sealed class GarageState {
  /// The network of the keys the Garage shows.
  final RobosatsNetwork network;

  const GarageState(this.network);

  @override
  String toString() => '$runtimeType(${network.name})';
}

/// A key is being read, derived or activated.
final class GarageWorking extends GarageState {
  const GarageWorking(super.network);
}

/// A Garage Key shown: its robot shown, and the key itself for `GarageKeyView`.
///
/// The key shown is the key selected on the network, the key of every new trade (the owner's decisions of 2026-11-26): a key of the words (#81), with an index, `key.index`, from 0 to [highest], or the external key, without one, the key the vault keeps for the network (drawn at random on this device before #81, or pasted in « Robot recovery »).
final class GarageWithKey extends GarageState {
  final NetworkGarageKey key;
  final GarageRobotFace robot;

  /// The highest key of the words activated on this network: « New key » activates the one after it, whichever key is shown. The external key does not count.
  final int highest;

  /// The number of each key of the words activated on this network, by its fingerprint: which key a line of the history is of (#81).
  final Map<GarageKeyFingerprint, int> keyNumbers;

  /// Whether the vault keeps an external key for this network, readable or not: one more position of the arrows of the keys, after [highest].
  final bool hasExternal;

  /// The fingerprint of the external key, when it can be read: which lines of the history are of it.
  final GarageKeyFingerprint? externalKey;

  /// Whether removing the external key shown asks the wallet's PIN after « Delete Garage Key? », as the feature's database said when the user last asked (`NeedsPinToDeleteGarageKeyUsecase`): `true` until then, so that the button is never shown as free of the PIN by mistake.
  final bool deletionNeedsPin;

  /// Why the last action of the user failed, when it did: a robot that could not be derived, or a key that could not be activated.
  final P2pFailure? failure;

  /// The orders (coordinator's short alias, order id) of the robot shown that this device holds finished with an end that has not served, an expiry or a take that never started (#251, `GarageRecords.ordersNotServedOf`): the panel does not say the reference's sentence on a robot involved in a trade for such a last order.
  final Set<(String, int)> ordersNotServed;

  const GarageWithKey(
    super.network, {
    required this.key,
    required this.robot,
    required this.highest,
    this.keyNumbers = const {},
    this.hasExternal = false,
    this.externalKey,
    this.deletionNeedsPin = true,
    this.failure,
    this.ordersNotServed = const {},
  });

  /// Whether the key shown is the external key.
  bool get isExternal => key.index == null;

  /// This state with the fields given changed; [failure] is the outcome of the action that leads to the copy, so it is replaced, by nothing when it is not given.
  GarageWithKey copyWith({
    GarageRobotFace? robot,
    Set<(String, int)>? ordersNotServed,
    bool? deletionNeedsPin,
    P2pFailure? failure,
  }) => GarageWithKey(
    network,
    key: key,
    robot: robot ?? this.robot,
    highest: highest,
    keyNumbers: keyNumbers,
    hasExternal: hasExternal,
    externalKey: externalKey,
    deletionNeedsPin: deletionNeedsPin ?? this.deletionNeedsPin,
    failure: failure,
    ordersNotServed: ordersNotServed ?? this.ordersNotServed,
  );
}

/// No key can be shown: a locked keystore, a key the vault or the words cannot give (no default wallet, a passphrase, a seed without words, a wallet that cannot be read), a key the words give again that is not the one recorded, or a database that cannot be read. Never a key drawn in its place; the user may try again.
final class GarageUnknown extends GarageState {
  /// Why no key can be shown.
  final P2pFailure failure;

  /// Why the last action of the user failed, when it did.
  final P2pFailure? actionFailure;

  /// The highest key of the words when the key that cannot be shown is the external key, selected: the Garage then offers the way back to that key, and, unless the keystore is only locked, the way out of a key that cannot be read, its delete, which always asks the PIN. `null` otherwise.
  final int? externalHighest;

  const GarageUnknown(
    super.network,
    this.failure, {
    this.actionFailure,
    this.externalHighest,
  });
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
