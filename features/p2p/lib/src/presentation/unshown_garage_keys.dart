import 'package:robosats/robosats.dart' show RobosatsNetwork;

/// The networks whose Garage Key was drawn in this run of the app and not shown yet for backup: in memory only, one object for the feature.
///
/// The vault stores a key as soon as it draws it, and its rule is to show it right after, since it is never part of the wallet backup.
/// When the user leaves the Garage before the vault answered (it takes about 4.5 s), the next visit of the Garage shows it once, with the backup alert and without asking for the PIN, as if the user had stayed.
/// If the app dies in between, nothing remembers it: the key is then shown only behind the PIN, on the profile.
final class UnshownGarageKeys {
  final Set<RobosatsNetwork> _networks = {};

  /// The key of [network] was just drawn and waits to be shown.
  void add(RobosatsNetwork network) => _networks.add(network);

  /// Whether the key of [network] waited to be shown; it no longer waits, since the caller shows it now or deleted it.
  bool take(RobosatsNetwork network) => _networks.remove(network);
}
