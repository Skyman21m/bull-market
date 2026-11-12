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

/// Bindings that keep the calls made to them and give [failure] to every call, or success without it.
final class RecordingBindings implements RobotBindingRepository {
  final List<BindingCall> calls = [];
  P2pFailure? failure;

  RecordingBindings({this.failure});

  Result<void, P2pFailure> get _result => switch (failure) {
    final failure? => Err(failure),
    null => const Ok(null),
  };

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
}
