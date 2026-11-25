import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../../robot_binding.dart';
import '../../trade/trade_take.dart';
import '../../trade_robots.dart';

/// The take prepared and not sent in this process (#119), and the robot its order's preparation reserved (a lazy singleton of the composition, `P2pLocator.registerTrades`).
///
/// One order at a time: a robot reserved and put on the coordinator for an order's preparation serves every new preparation of that order (a second tap, a read that failed, figures that changed) until the take is confirmed, the user abandons it, the order is gone or refused for good, or an order of another coordinator or id is prepared; then the robot is forgotten, bound to that coordinator, without a trade, never returned again (the rule of a robot reserved by a take not made).
/// So no more than one robot and its token are held here, and only while its order's take is on the screen: `ReservedRobot`'s « no longer than the requests of the take ».
/// In memory only: after a restart nothing is prepared, and the robots reserved stay bound, unused.
/// Each change names the preparation it is about, compared by identity: a preparation replaced by a newer one changes nothing any more (review of #126).
final class PreparedTakes {
  _OrderPreparation? _current;

  static (RobosatsNetwork, String, int) _keyOf(PreparedTake prepared) => (
    prepared.terms.network,
    prepared.terms.coordinator.shortAlias,
    prepared.terms.orderId,
  );

  /// The robot reserved for the preparation of order [orderId] of the coordinator [alias] on [network], if any.
  ReservedRobot? robotFor(RobosatsNetwork network, String alias, int orderId) =>
      switch (_current) {
        final current? when current.key == (network, alias, orderId) =>
          current.robot,
        _ => null,
      };

  /// Keeps [robot] for the preparations of that order: the order prepared before it, if another, is forgotten with its robot.
  ///
  /// [garageRobot] is the robot the Garage showed before [robot] was reserved (#251, § 4.2), `null` when it could not be told: whether they differ is kept with [robot], so that every preparation of the order says the same, the robot reserved being in use, and so never the fresh one, once it is.
  void keepRobot(
    RobosatsNetwork network,
    String alias,
    int orderId,
    ReservedRobot robot, {
    required RobotSlot? garageRobot,
  }) => _current = _OrderPreparation(
    (network, alias, orderId),
    robot,
    changedRobot: garageRobot != null && robot.robot.slot != garageRobot,
  );

  /// Whether the robot kept for order [orderId] of the coordinator [alias] on [network] is not the one the Garage showed before it was reserved; `false` with none kept.
  bool changedRobotFor(RobosatsNetwork network, String alias, int orderId) =>
      switch (_current) {
        final current? when current.key == (network, alias, orderId) =>
          current.changedRobot,
        _ => false,
      };

  /// Records [prepared] as its order's current preparation, the one [robotOf] gives a robot for: any earlier one of the order can no longer be confirmed, nor abandoned.
  ///
  /// Only for the order whose robot is kept ([keepRobot]); anything else is a bug of the use case.
  void add(PreparedTake prepared) {
    final current = _current;
    if (current == null || current.key != _keyOf(prepared)) {
      throw StateError('A preparation without its robot.');
    }
    current
      ..latest = prepared
      ..confirmable = true;
  }

  /// The robot of [prepared] when it is its order's current preparation and can still be confirmed, else `null`.
  ReservedRobot? robotOf(PreparedTake prepared) => switch (_current) {
    final current?
        when identical(current.latest, prepared) && current.confirmable =>
      current.robot,
    _ => null,
  };

  /// [prepared] can no longer be confirmed; its order's robot stays for a new preparation, and an [release] of [prepared] still forgets it.
  void forget(PreparedTake prepared) {
    if (_current case final current? when identical(current.latest, prepared)) {
      current.confirmable = false;
    }
  }

  /// Forgets [prepared] and its order's robot, when [prepared] is still its order's latest preparation: the take was sent, or abandoned.
  void release(PreparedTake prepared) {
    if (_current case final current? when identical(current.latest, prepared)) {
      _current = null;
    }
  }

  /// Forgets the preparation of order [orderId] of the coordinator [alias] on [network], and its robot: the order is gone, refused for good, or left.
  void releaseOrder(RobosatsNetwork network, String alias, int orderId) {
    if (_current?.key == (network, alias, orderId)) _current = null;
  }
}

/// The robot of one order's preparations, whether it is not the robot the Garage showed before it was reserved, and the latest preparation made with it.
final class _OrderPreparation {
  final (RobosatsNetwork, String, int) key;
  final ReservedRobot robot;
  final bool changedRobot;
  PreparedTake? latest;
  bool confirmable = false;

  _OrderPreparation(this.key, this.robot, {required this.changedRobot});
}
