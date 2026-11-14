import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../../trade/trade_take.dart';
import '../../trade_robots.dart';

/// The takes prepared and not sent in this process (#119), and the robot each order's preparation reserved (a lazy singleton of the composition, `P2pLocator.registerTrades`).
///
/// A robot reserved and put on the coordinator for an order's preparation serves every new preparation of that order (a second tap, a read that failed, figures that changed) until the take is confirmed or the user abandons it: then it is forgotten, bound to that coordinator, without a trade, never returned again (the rule of a robot reserved by a take not made).
/// In memory only: after a restart nothing is prepared, and the robots reserved stay bound, unused.
final class PreparedTakes {
  final Map<(RobosatsNetwork, String, int), ReservedRobot> _robots = {};
  final Map<PreparedTake, (RobosatsNetwork, String, int)> _prepared =
      Map.identity();

  static (RobosatsNetwork, String, int) _keyOf(PreparedTake prepared) => (
    prepared.terms.network,
    prepared.terms.coordinator.shortAlias,
    prepared.terms.orderId,
  );

  /// The robot reserved for the preparation of order [orderId] of the coordinator [alias] on [network], if any.
  ReservedRobot? robotFor(RobosatsNetwork network, String alias, int orderId) =>
      _robots[(network, alias, orderId)];

  /// Keeps [robot] for the preparations of that order.
  void keepRobot(
    RobosatsNetwork network,
    String alias,
    int orderId,
    ReservedRobot robot,
  ) => _robots[(network, alias, orderId)] = robot;

  /// Records [prepared] as the order's current preparation: any earlier one of the same order can no longer be confirmed.
  void add(PreparedTake prepared) {
    final key = _keyOf(prepared);
    _prepared.removeWhere((_, other) => other == key);
    _prepared[prepared] = key;
  }

  /// The robot of [prepared] when it is the current preparation of its order, else `null`.
  ReservedRobot? robotOf(PreparedTake prepared) {
    final key = _prepared[prepared];
    return key == null ? null : _robots[key];
  }

  /// [prepared] can no longer be confirmed; its order's robot stays for a new preparation.
  void forget(PreparedTake prepared) => _prepared.remove(prepared);

  /// Forgets [prepared] and its order's robot: the take was sent, or abandoned.
  void release(PreparedTake prepared) {
    final key = _keyOf(prepared);
    _prepared.removeWhere((_, other) => other == key);
    _robots.remove(key);
  }
}
