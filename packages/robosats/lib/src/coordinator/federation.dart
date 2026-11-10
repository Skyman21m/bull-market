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
  ///
  /// It is validated twice: `test/coordinator/embedded_data_test.dart` checks that it equals the RoboSats file and that [problems] finds nothing, and `FederationBookReader.requestAll` asserts it in debug and test builds for whatever federation it is given.
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

  static final RegExp _alias = RegExp(r'^[a-z0-9]{1,20}$');
  static final RegExp _onion = RegExp(r'^http://[a-z2-7]{56}\.onion$');
  static final RegExp _nodeKey = RegExp(r'^0[23][0-9a-f]{64}$');
  static final RegExp _nostrKey = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Whether [text] is a `YYYY-MM-DD` date that exists, which `DateTime.tryParse` alone does not check.
  static bool _isDate(String text) {
    if (!_date.hasMatch(text)) return false;
    final [year, month, day] = text.split('-').map(int.parse).toList();
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }

  /// What makes this list unusable, one label per problem naming the coordinator: empty for a valid list.
  ///
  /// It applies the rules a coordinator applies to a federation document (`_load_federation_doc` in `api/views.py`: alias of 1 to 20 lowercase letters and digits, a mainnet onion address), and requires well-formed onion addresses, node keys, Nostr key and date, unique aliases, and at least one node key on every network with an onion address.
  List<String> problems() {
    final problems = <String>[];
    final aliases = <String>{};
    for (final coordinator in coordinators) {
      final alias = coordinator.shortAlias;
      if (!aliases.add(alias)) problems.add('$alias: duplicated alias');
      if (!_alias.hasMatch(alias)) problems.add('$alias: malformed alias');
      if (coordinator.mainnet.onion == null) {
        problems.add('$alias: no mainnet onion');
      }
      for (final network in RobosatsNetwork.values) {
        final onion = coordinator.origins(network).onion;
        final keys = coordinator.nodesPubkeys(network);
        if (onion != null && !_onion.hasMatch(onion)) {
          problems.add('$alias: malformed ${network.name} onion');
        }
        if (onion != null && keys.isEmpty) {
          problems.add('$alias: no ${network.name} node key');
        }
        if (keys.any((key) => !_nodeKey.hasMatch(key))) {
          problems.add('$alias: malformed ${network.name} node key');
        }
      }
      if (!_nostrKey.hasMatch(coordinator.nostrHexPubkey)) {
        problems.add('$alias: malformed Nostr key');
      }
      if (!_isDate(coordinator.established)) {
        problems.add('$alias: malformed established date');
      }
    }
    return problems;
  }

  @override
  String toString() =>
      'Federation(${coordinators.map((c) => c.shortAlias).join(', ')})';
}
