import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import 'fakes.dart';

/// The real bindings over a database in memory, read at [testNow] unless [clock] says otherwise.
///
/// Each test makes its own database, so the warning drift prints for a second database of one class is turned off.
RobotBindingRepositoryImpl bindingsInMemory({
  DateTime Function()? clock,
  P2pDatabase? database,
}) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return RobotBindingRepositoryImpl(
    database ?? P2pDatabase.forTesting(NativeDatabase.memory()),
    clock: clock ?? () => testNow,
  );
}

/// One call made to [RecordingBindings].
typedef BindingCall = (String method, Object? first, Object? second);

/// Bindings that keep the calls made to them and give [failure] to every write, or to the first [failures] writes when it is set, or success without it; the reads give [readFailure] when it is set.
///
/// Its reads follow its writes, as the database's do: a key is drawn here once a record of its draw succeeded, or when [drawnHere] names it, until a record of its import succeeds; an imported or unrecorded key is acknowledged once a record of its acknowledgement succeeded; a robot is bound, with the provenance its key's history gives, only when that history on its network is drawn here or acknowledged, and is refused otherwise, as by the database; a robot bound admits its coordinator only; [exposure], when set, answers instead.
final class RecordingBindings implements RobotBindingRepository {
  final List<BindingCall> calls = [];
  P2pFailure? failure;
  int? failures;

  /// What [exposureOf] answers when it succeeds, instead of what the writes made.
  GarageKeyExposure? exposure;

  /// What the reads give instead, when it is set: the writes follow [failure].
  P2pFailure? readFailure;

  /// Called when a read starts; then, when [readsWait] is set, the read waits for it, as a slow database would.
  void Function()? onRead;
  Future<void>? readsWait;

  /// The history recorded for each network and key fingerprint.
  final Map<(RobosatsNetwork, GarageKeyFingerprint), GarageKeyHistory>
  _histories;

  /// The fingerprints of the keys with a robot bound, whatever the network.
  final Set<GarageKeyFingerprint> _bound = {};

  /// The binding of each robot index of each key, whatever the network.
  final Map<(GarageKeyFingerprint, int), RobotBinding> _bindings = {};

  /// [drawnHere] are the networks and keys recorded as drawn here from the start, as for a key the test stored in the keystore.
  RecordingBindings({
    this.failure,
    this.failures,
    Iterable<(RobosatsNetwork, GarageKeyFingerprint)> drawnHere = const [],
  }) : _histories = {
         for (final slot in drawnHere) slot: GarageKeyHistory.drawnHere,
       };

  Future<void> _slowRead() async {
    onRead?.call();
    if (readsWait case final wait?) await wait;
  }

  Result<void, P2pFailure> get _result {
    final failure = this.failure;
    if (failure == null) return const Ok(null);
    if (failures case final left?) {
      if (left <= 0) return const Ok(null);
      failures = left - 1;
    }
    return Err(failure);
  }

  @override
  Future<Result<void, P2pFailure>> recordGeneratedKey(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) async {
    calls.add(('recordGeneratedKey', network, key));
    final result = _result;
    // It never overrides a key recorded as imported.
    if (result case Ok()) {
      _histories.putIfAbsent((network, key), () => GarageKeyHistory.drawnHere);
    }
    return result;
  }

  @override
  Future<Result<void, P2pFailure>> recordImportedKey(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) async {
    calls.add(('recordImportedKey', network, key));
    final result = _result;
    if (result case Ok()) _histories[(network, key)] = GarageKeyHistory.unknown;
    return result;
  }

  @override
  Future<Result<void, P2pFailure>> recordAcknowledgedKey(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) async {
    calls.add(('recordAcknowledgedKey', network, key));
    final result = _result;
    // It never overrides a key recorded as drawn here.
    if (result case Ok()) {
      _histories.update(
        (network, key),
        (history) => history == GarageKeyHistory.drawnHere
            ? history
            : GarageKeyHistory.acknowledged,
        ifAbsent: () => GarageKeyHistory.acknowledged,
      );
    }
    return result;
  }

  @override
  Future<Result<void, P2pFailure>> bind(
    RobotSlot robot,
    CoordinatorIdentity coordinator,
  ) async {
    calls.add(('bind', robot, coordinator));
    if (_result case Err(:final failure)) return Err(failure);
    // As the database: a binding made admits its coordinator only, and a robot without one is bound only under a key drawn here or acknowledged on its network, with that provenance.
    final slot = (robot.keyFingerprint, robot.accountIndex);
    if (_bindings[slot] case final existing?) {
      return existing.admits(coordinator);
    }
    final provenance = switch (_histories[(
      robot.network,
      robot.keyFingerprint,
    )]) {
      GarageKeyHistory.drawnHere => BindingProvenance.drawnHere,
      GarageKeyHistory.acknowledged => BindingProvenance.acknowledged,
      GarageKeyHistory.unknown || null => null,
    };
    if (provenance == null) return const Err(RobotHistoryUnknownFailure());
    _bound.add(robot.keyFingerprint);
    _bindings[slot] = RobotBinding(coordinator, testNow, provenance);
    return const Ok(null);
  }

  @override
  Future<Result<RobotStanding, P2pFailure>> standingOf(RobotSlot robot) async {
    calls.add(('standingOf', robot, null));
    await _slowRead();
    return switch (readFailure) {
      final failure? => Err(failure),
      null => Ok(
        RobotStanding(
          network: robot.network,
          binding: _bindings[(robot.keyFingerprint, robot.accountIndex)],
          history:
              _histories[(robot.network, robot.keyFingerprint)] ??
              GarageKeyHistory.unknown,
        ),
      ),
    };
  }

  @override
  Future<Result<GarageKeyExposure, P2pFailure>> exposureOf(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) async {
    calls.add(('exposureOf', network, key));
    await _slowRead();
    return switch (readFailure) {
      final failure? => Err(failure),
      null => Ok(
        exposure ??
            GarageKeyExposure(
              history: _histories[(network, key)] ?? GarageKeyHistory.unknown,
              hasBinding: _bound.contains(key),
            ),
      ),
    };
  }
}
