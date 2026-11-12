import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show
        AccountIndexOutOfRange,
        GarageKey,
        GarageRobot,
        NicknameUnavailable,
        NoUsableAccountIndex,
        RobosatsFailure,
        RobosatsNetwork,
        RobotIdentity,
        TokenEntropyTooLow;

import 'garage_key_fingerprint.dart';
import 'p2p_failure.dart';
import 'robot_binding.dart';

/// The Garage Key of one network, as the vault keeps it in the slot of that network, and the robots derived from it.
///
/// Every robot it gives is a [NetworkRobot] that carries [network] and the [fingerprint] of the key, so that a robot of the testnet key can never be handed to a call for mainnet, nor checked against the bindings of another key.
/// Only the repository makes one, from the slot it has just read: `test/network_garage_key_test.dart` pins that no other library of the feature calls this constructor.
/// It holds the key itself: keep it no longer than the screen that uses it, never log it, and let only `GarageKeyView` turn it into text.
@immutable
final class NetworkGarageKey {
  /// The network whose slot of the vault holds [key].
  final RobosatsNetwork network;

  /// The key: its clear forms are for `GarageKeyView` (its text) and the repository (its bytes) only, as the custody gate checks.
  final GarageKey key;

  const NetworkGarageKey(this.network, this.key);

  /// What ties the bindings of the robots of this key to it: see [GarageKeyFingerprint].
  Result<GarageKeyFingerprint, P2pFailure> get fingerprint =>
      GarageKeyFingerprint.of(key);

  /// The first robot at or after [fromIndex] that a coordinator can be contacted with, as `GarageKey.firstUsableRobot` finds it.
  ///
  /// No such robot is a [GarageRobotUnavailableFailure].
  Result<NetworkRobot, P2pFailure> firstUsableRobot(int fromIndex) =>
      _tagged(key.firstUsableRobot(fromIndex));

  /// The last robot at or before [atOrBefore] that a coordinator can be contacted with: the robot before the one shown, for the account navigator.
  ///
  /// It skips the indexes `GarageKey.firstUsableRobot` skips, and looks at as many of them, down to index 0; no such robot, or an index below 0, is a [GarageRobotUnavailableFailure].
  Result<NetworkRobot, P2pFailure> lastUsableRobot(int atOrBefore) =>
      _tagged(lastUsableRobotAmong(atOrBefore, key.deriveIdentity));

  /// [lastUsableRobot] over the identities [identityOf] gives for each index.
  ///
  /// For tests only: no Garage Key is known that has an index to skip.
  @visibleForTesting
  static Result<GarageRobot, RobosatsFailure> lastUsableRobotAmong(
    int atOrBefore,
    Result<RobotIdentity, RobosatsFailure> Function(int accountIndex)
    identityOf,
  ) {
    if (atOrBefore < 0) return const Err(AccountIndexOutOfRange());
    final from = atOrBefore > GarageKey.maxAccountIndex
        ? GarageKey.maxAccountIndex
        : atOrBefore;
    for (
      var index = from;
      index >= 0 && index > from - GarageKey.maxAccountSearch;
      index--
    ) {
      switch (identityOf(index)) {
        case Ok(value: final identity):
          return Ok(GarageRobot(index, identity));
        case Err(failure: TokenEntropyTooLow() || NicknameUnavailable()):
          continue;
        case Err(:final failure):
          return Err(failure);
      }
    }
    return const Err(NoUsableAccountIndex());
  }

  Result<NetworkRobot, P2pFailure> _tagged(
    Result<GarageRobot, RobosatsFailure> robot,
  ) => switch ((robot, fingerprint)) {
    (Ok(value: final derived), Ok(value: final keyFingerprint)) => Ok(
      NetworkRobot._(network, keyFingerprint, derived),
    ),
    _ => const Err(GarageRobotUnavailableFailure()),
  };

  @override
  bool operator ==(Object other) =>
      other is NetworkGarageKey && other.network == network && other.key == key;

  @override
  int get hashCode => Object.hash(network, key);

  @override
  String toString() => 'NetworkGarageKey(${network.name}, <redacted>)';
}

/// A robot of the Garage Key of one network, with that network: the only form in which a robot leaves the repository.
///
/// Only a [NetworkGarageKey] makes one, with its own network and the fingerprint of the key, so a call that takes a [NetworkRobot] reads them from it and never from elsewhere.
/// It holds the token of the robot: keep it no longer than the requests made for it, and never in the state of a cubit.
@immutable
final class NetworkRobot {
  /// The network of the key the robot was derived from.
  final RobosatsNetwork network;

  /// The fingerprint of the key the robot was derived from, which its binding is kept under.
  final GarageKeyFingerprint keyFingerprint;

  final GarageRobot robot;

  const NetworkRobot._(this.network, this.keyFingerprint, this.robot);

  /// The index of the robot, the « Robot #N » of the screens.
  int get accountIndex => robot.accountIndex;

  RobotIdentity get identity => robot.identity;

  /// The robot as its binding knows it, without its token.
  RobotSlot get slot => RobotSlot(network, keyFingerprint, accountIndex);

  @override
  bool operator ==(Object other) =>
      other is NetworkRobot &&
      other.network == network &&
      other.keyFingerprint == keyFingerprint &&
      other.robot == robot;

  @override
  int get hashCode => Object.hash(network, keyFingerprint, robot);

  @override
  String toString() => 'NetworkRobot(${network.name}, $robot)';
}
