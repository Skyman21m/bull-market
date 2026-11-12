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

/// Bindings that keep the calls made to them and give [failure] to every write, or to the first [failures] writes when it is set, or success without it; the reads give [readFailure] when it is set, and [exposure] and [anyBinding] otherwise.
final class RecordingBindings implements RobotBindingRepository {
  final List<BindingCall> calls = [];
  P2pFailure? failure;
  int? failures;

  /// What [exposureOf] answers when it succeeds: by default a key drawn here, with no robot bound, whose delete asks no PIN.
  GarageKeyExposure exposure = const GarageKeyExposure(
    history: GarageKeyHistory.drawnHere,
    hasBinding: false,
  );

  /// What [hasAnyBinding] answers when it succeeds.
  bool anyBinding = false;

  /// What the reads, [exposureOf] and [hasAnyBinding], give instead, when it is set: the writes follow [failure].
  P2pFailure? readFailure;

  /// Called when a read starts; then, when [readsWait] is set, the read waits for it, as a slow database would.
  void Function()? onRead;
  Future<void>? readsWait;

  RecordingBindings({this.failure, this.failures});

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
    return _result;
  }

  @override
  Future<Result<void, P2pFailure>> recordImportedKey(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) async {
    calls.add(('recordImportedKey', network, key));
    return _result;
  }

  @override
  Future<Result<void, P2pFailure>> bind(
    RobotSlot robot,
    CoordinatorIdentity coordinator,
  ) async {
    calls.add(('bind', robot, coordinator));
    return _result;
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
      null => Ok(exposure),
    };
  }

  @override
  Future<Result<bool, P2pFailure>> hasAnyBinding() async {
    calls.add(('hasAnyBinding', null, null));
    await _slowRead();
    return switch (readFailure) {
      final failure? => Err(failure),
      null => Ok(anyBinding),
    };
  }
}
