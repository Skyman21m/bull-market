import 'package:robosats/robosats.dart' show RobosatsNetwork;

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

/// While a trade of the key drawn at random before #81 is in progress, the vault holds no such key for this network, as it concluded after its full read budget: the Garage only says that the key of the words comes once the trades are finished.
final class GarageWithoutKey extends GarageState {
  /// Why the last action of the user failed, when it did.
  final P2pFailure? failure;

  const GarageWithoutKey(super.network, {this.failure});
}

/// A Garage Key shown: its robot shown, and the key itself for `GarageKeyView`.
///
/// A key of the words (#81) has an index, `key.index`, from 0 to [highest]: the highest is the key of every new trade, the others are earlier keys, shown with the arrows of the Garage Key card to finish their trades. The key drawn at random before #81 has neither, while the trades it finishes are in progress.
final class GarageWithKey extends GarageState {
  final NetworkGarageKey key;
  final GarageRobotFace robot;

  /// The highest key of the words activated on this network, the key of new trades; `null` for the key drawn at random before #81.
  final int? highest;

  /// Why the last action of the user failed, when it did: a robot that could not be derived, or a key that could not be activated.
  final P2pFailure? failure;

  /// The orders (coordinator's short alias, order id) of the robot shown that this device holds finished with an end that has not served, an expiry or a take that never started (#251, `GarageRecords.ordersNotServedOf`): the panel does not say the reference's sentence on a robot involved in a trade for such a last order.
  final Set<(String, int)> ordersNotServed;

  const GarageWithKey(
    super.network, {
    required this.key,
    required this.robot,
    this.highest,
    this.failure,
    this.ordersNotServed = const {},
  });

  /// Whether this is the key drawn at random before #81, kept only to finish its trades: no arrows of keys, no « New key ».
  bool get isLegacy => key.index == null;

  /// Whether this is a key of the words before the highest: shown to finish its trades, never the key of a new trade.
  bool get isEarlierKey => switch ((key.index, highest)) {
    (final index?, final top?) => index < top,
    _ => false,
  };

  /// This state with the fields given changed; [failure] is the outcome of the action that leads to the copy, so it is replaced, by nothing when it is not given.
  GarageWithKey copyWith({
    GarageRobotFace? robot,
    Set<(String, int)>? ordersNotServed,
    P2pFailure? failure,
  }) => GarageWithKey(
    network,
    key: key,
    robot: robot ?? this.robot,
    highest: highest,
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
