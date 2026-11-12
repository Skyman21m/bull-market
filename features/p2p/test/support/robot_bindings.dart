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
/// Its reads follow its writes, as the database's do: a key is drawn here once a record of its draw succeeded, or when [drawnHere] names it, until a record of its import succeeds; a key is bound once a binding of one of its robots succeeded; [exposure], when set, answers instead.
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
  Future<Result<void, P2pFailure>> bind(
    RobotSlot robot,
    CoordinatorIdentity coordinator,
  ) async {
    calls.add(('bind', robot, coordinator));
    final result = _result;
    if (result case Ok()) _bound.add(robot.keyFingerprint);
    return result;
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
