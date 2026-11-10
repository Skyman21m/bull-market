import 'package:meta/meta.dart';
import 'package:robosats/src/coordinator/coordinator.dart';
import 'package:robosats/src/coordinator/federation_data.dart';
import 'package:robosats/src/coordinator/robosats_network.dart';

/// A set of coordinators the client reads from.
@immutable
final class Federation {
  /// The coordinators, in the order the client lists them.
  final List<Coordinator> coordinators;

  const Federation(this.coordinators);

  /// The federation list embedded in this package: `frontend/static/federation.json` of RoboSats at commit ff1998c.
  static const Federation robosats = Federation(robosatsCoordinators);

  /// The coordinator with this short alias, or `null`.
  Coordinator? byAlias(String shortAlias) {
    for (final coordinator in coordinators) {
      if (coordinator.shortAlias == shortAlias) return coordinator;
    }
    return null;
  }

  /// The coordinators that have an onion address on [network].
  List<Coordinator> on(RobosatsNetwork network) => [
    for (final coordinator in coordinators)
      if (coordinator.isOn(network)) coordinator,
  ];

  @override
  String toString() =>
      'Federation(${coordinators.map((c) => c.shortAlias).join(', ')})';
}
