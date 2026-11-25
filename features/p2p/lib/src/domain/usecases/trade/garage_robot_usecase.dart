import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../../garage_opening.dart';
import '../../network_garage_key.dart';
import '../../p2p_failure.dart';
import '../../repositories/garage_key_repository.dart';
import '../../robot_binding.dart';
import 'follow_trades_usecase.dart';

/// The robot the Garage of a network would show now (#251, design note `docs/design/phase-3-fresh-robot.md` § 4.2): [GarageNavigation.robotOf] over the records [FollowTradesUsecase] reads first, else the first usable robot from index 0. Read from the vault and the device's records only, nothing sent, nothing written.
///
/// Only for the line of the order page, read by the take's screen before the take reserves its robot: no trade takes its robot from it, the take's being always `TradeRobots.robotForNewTrade`'s.
final class GarageRobotUsecase {
  final GarageKeyRepository _keys;
  final FollowTradesUsecase _follow;
  final GarageNavigation _navigation;

  const GarageRobotUsecase(this._keys, this._follow, this._navigation);

  /// The robot the Garage of [network] would show, or `null` when it cannot be told: no key, a vault or records that cannot be read, no usable robot.
  Future<RobotSlot?> execute(RobosatsNetwork network) async {
    final NetworkGarageKey key;
    switch (await _keys.read(network)) {
      case Ok(:final value):
        key = value;
      case Err():
        return null;
    }
    final records = await _follow.execute(key).first;
    if (records is Err) return null;
    if (_navigation.robotOf(key, records) case final robot?) return robot;
    return switch (key.firstUsableRobot(0)) {
      Ok(:final value) => value.slot,
      Err<NetworkRobot, P2pFailure>() => null,
    };
  }
}
