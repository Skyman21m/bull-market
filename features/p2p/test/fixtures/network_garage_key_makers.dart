// Ways to make a `NetworkGarageKey` that a check reading names alone misses, for `test/network_garage_key_test.dart`: each one must be found.
// Never imported by the feature; the analyzer resolves it in that test only.
import 'package:p2p/src/domain/network_garage_key.dart' as domain;
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:robosats/robosats.dart' show GarageKey, RobosatsNetwork;

typedef Tagged = NetworkGarageKey;

NetworkGarageKey byAlias(GarageKey key) => Tagged(RobosatsNetwork.mainnet, key);

NetworkGarageKey byShorthand(GarageKey key) =>
    .new(RobosatsNetwork.mainnet, key);

NetworkGarageKey Function(RobosatsNetwork, GarageKey) byPrefixedTearOff() =>
    domain.NetworkGarageKey.new;

NetworkGarageKey Function(RobosatsNetwork, GarageKey) byAliasTearOff() =>
    Tagged.new;
