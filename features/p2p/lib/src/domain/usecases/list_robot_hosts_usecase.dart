import 'package:robosats/robosats.dart' show Federation, RobosatsNetwork;

import '../robot_host.dart';
import '../robot_request_limiter.dart';

/// The coordinators a robot of this device may be put on, for the Garage's « Select Host » sheet, and the coordinator a robot's binding names, for its panel.
///
/// It reads the federation list of the app and what [RobotRequestLimiter] remembers of this run: it sends nothing and writes nothing.
final class ListRobotHostsUsecase {
  final Federation _federation;
  final RobotRequestLimiter _limiter;

  const ListRobotHostsUsecase(this._federation, this._limiter);

  /// The coordinators with an onion address on [network], in the order of the federation, each with whether first contacts to it fail at once in this run ([RobotRequestLimiter.refusesFirstContacts]).
  RobotHosts execute(RobosatsNetwork network) => RobotHosts(network, [
    for (final coordinator in _federation.on(network))
      RobotHost(
        coordinator,
        refusesFirstContacts: _limiter.refusesFirstContacts(
          network,
          coordinator,
        ),
      ),
  ]);
}
