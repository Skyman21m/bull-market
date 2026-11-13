import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show Coordinator, RobosatsNetwork;

import 'p2p_failure.dart';
import 'robot_binding.dart';

/// A coordinator a robot of this device may be put on, as the « Select Host » sheet of the Garage lists it.
///
/// It holds the coordinator as the federation list of the app gives it, public data only, and whether this run of the app still lets a first contact go to it.
@immutable
final class RobotHost {
  final Coordinator coordinator;

  /// Whether first contacts to this coordinator fail at once in this run of the app: it refused too many robots with a nickname already taken (`RobotCoordinatorTooManyRefusalsFailure`).
  final bool refusesFirstContacts;

  const RobotHost(this.coordinator, {required this.refusesFirstContacts});

  @override
  bool operator ==(Object other) =>
      other is RobotHost &&
      other.coordinator == coordinator &&
      other.refusesFirstContacts == refusesFirstContacts;

  @override
  int get hashCode => Object.hash(coordinator, refusesFirstContacts);

  @override
  String toString() =>
      'RobotHost(${coordinator.shortAlias}, refuses: $refusesFirstContacts)';
}

/// The coordinators of the federation list of the app that robots of one network may go to, in the order of the federation: those with an onion address on that network.
@immutable
final class RobotHosts {
  /// The network of the robots.
  final RobosatsNetwork network;

  /// The coordinators with an onion address on [network], in the order of the federation.
  final List<RobotHost> choices;

  RobotHosts(this.network, Iterable<RobotHost> choices)
    : choices = List.unmodifiable(choices);

  /// The coordinator of the list whose short alias is [alias], or `null` when the list has none on [network].
  Coordinator? listed(String alias) {
    for (final host in choices) {
      if (host.coordinator.shortAlias == alias) return host.coordinator;
    }
    return null;
  }

  /// The coordinator [binding] names, as the list gives it now on [network], where a robot of that network bound to it may be read back.
  ///
  /// It is the coordinator of the alias the binding recorded, only when the binding admits it ([RobotBinding.admits]): the same onion address and keys as when the robot was bound.
  /// A coordinator the list no longer has on [network], or whose address or keys changed since, is a [RobotCoordinatorChangedFailure], as `ReadRobotOnCoordinatorUsecase` and `FetchRobotUsecase` refuse it; a binding of the other network is the [RobotBoundToAnotherCoordinatorFailure] of [RobotBinding.admits].
  Result<Coordinator, P2pFailure> boundTo(RobotBinding binding) {
    final coordinator = listed(binding.coordinator.alias);
    final identity = coordinator == null
        ? null
        : CoordinatorIdentity.of(coordinator, network);
    if (coordinator == null || identity == null) {
      return const Err(RobotCoordinatorChangedFailure());
    }
    return switch (binding.admits(identity)) {
      Ok() => Ok(coordinator),
      Err(:final failure) => Err(failure),
    };
  }
}
