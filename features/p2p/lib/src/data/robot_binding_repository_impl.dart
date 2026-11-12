import 'package:drift/drift.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../domain/garage_key_fingerprint.dart';
import '../domain/p2p_failure.dart';
import '../domain/repositories/robot_binding_repository.dart';
import '../domain/robot_binding.dart';
import 'p2p_database.dart';

/// The bindings of the robots and the history of the Garage Keys in the feature's database.
///
/// [bind] holds without a transaction around its two statements: the insert is one statement, so SQLite runs it atomically, it writes only when no binding exists and the key is recorded as drawn on this device, and a binding is never changed or deleted, so the read that follows sees the binding that won.
/// The primary key (key fingerprint, robot index), whatever the network, keeps it so across connections and isolates as well: a robot's credential is the same on both networks, so an index bound on one is bound on the other.
/// Every statement commits on its own, synced to disk, before its future completes.
/// It returns no row of the database: the domain types only, and a [P2pStorageFailure] for any [Exception] the database or the directory the shell gave throws.
/// An [Error] is a bug (AGENTS.md, rule 11) and is not caught: the call throws, and the caller sends nothing.
/// Several connections writing at once can make SQLite give up after its busy timeout, a [P2pStorageFailure] that refuses the request; the app opens one connection, in the foreground only, and drift runs its statements one at a time, so it is not exposed to that.
final class RobotBindingRepositoryImpl implements RobotBindingRepository {
  static const String _generated = 'generated';
  static const String _imported = 'imported';

  /// Writes the binding only when the robot has none, on either network, and its key was drawn on this device for the robot's network; an existing binding wins over any later one.
  static const String _bindIfFreshSql =
      'INSERT INTO robot_bindings (network, key_fingerprint, robot_index, '
      'coordinator_alias, coordinator_onion, coordinator_node_keys, '
      'coordinator_nostr_key, bound_at) '
      'SELECT ?, ?, ?, ?, ?, ?, ?, ? '
      'WHERE EXISTS (SELECT 1 FROM garage_key_histories '
      'WHERE network = ? AND key_fingerprint = ? AND origin = ?) '
      'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING';

  /// Whether any robot index of a key is bound, whatever the network, and the origin of the key on one network, absent when none is recorded, in one statement.
  static const String _exposureSql =
      'SELECT EXISTS (SELECT 1 FROM robot_bindings WHERE key_fingerprint = ?) '
      'AS bound, (SELECT origin FROM garage_key_histories '
      'WHERE network = ? AND key_fingerprint = ?) AS origin';

  final P2pDatabase _database;
  final DateTime Function() _clock;

  const RobotBindingRepositoryImpl(this._database, {required this._clock});

  @override
  Future<Result<void, P2pFailure>> recordGeneratedKey(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) => _guard(() async {
    await _database
        .into(_database.garageKeyHistories)
        .insert(
          GarageKeyHistoriesCompanion.insert(
            network: _networkValue(network),
            keyFingerprint: key.hex,
            origin: _generated,
            recordedAt: _clock().millisecondsSinceEpoch,
          ),
          onConflict: DoNothing(),
        );
  });

  @override
  Future<Result<void, P2pFailure>> recordImportedKey(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) => _guard(() async {
    final now = _clock().millisecondsSinceEpoch;
    await _database
        .into(_database.garageKeyHistories)
        .insert(
          GarageKeyHistoriesCompanion.insert(
            network: _networkValue(network),
            keyFingerprint: key.hex,
            origin: _imported,
            recordedAt: now,
          ),
          onConflict: DoUpdate(
            (_) => GarageKeyHistoriesCompanion(
              origin: const Value(_imported),
              recordedAt: Value(now),
            ),
          ),
        );
  });

  @override
  Future<Result<void, P2pFailure>> bind(
    RobotSlot robot,
    CoordinatorIdentity coordinator,
  ) async {
    final network = _networkValue(robot.network);
    final fingerprint = robot.keyFingerprint.hex;
    final RobotBindingRow? row;
    try {
      await _database.customInsert(
        _bindIfFreshSql,
        variables: [
          Variable.withString(network),
          Variable.withString(fingerprint),
          Variable.withInt(robot.accountIndex),
          Variable.withString(coordinator.alias),
          Variable.withString(coordinator.onion),
          Variable.withString(coordinator.nodeKeys.join(',')),
          Variable.withString(coordinator.nostrKey),
          Variable.withInt(_clock().millisecondsSinceEpoch),
          Variable.withString(network),
          Variable.withString(fingerprint),
          Variable.withString(_generated),
        ],
        updates: {_database.robotBindings},
      );
      row =
          await (_database.select(_database.robotBindings)..where(
                (binding) =>
                    binding.keyFingerprint.equals(fingerprint) &
                    binding.robotIndex.equals(robot.accountIndex),
              ))
              .getSingleOrNull();
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    return switch (row) {
      // Not written: the key was not drawn on this device, so the robot may live on a coordinator already.
      null => const Err(RobotHistoryUnknownFailure()),
      final stored => switch (_bindingOf(stored)) {
        final binding? => binding.admits(coordinator),
        // A network the constraints of the table forbid: a row this code did not write.
        null => const Err(P2pStorageFailure()),
      },
    };
  }

  @override
  Future<Result<GarageKeyExposure, P2pFailure>> exposureOf(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) async {
    final QueryRow row;
    try {
      row = await _database
          .customSelect(
            _exposureSql,
            variables: [
              Variable.withString(key.hex),
              Variable.withString(_networkValue(network)),
              Variable.withString(key.hex),
            ],
            readsFrom: {_database.robotBindings, _database.garageKeyHistories},
          )
          .getSingle();
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    return Ok(
      GarageKeyExposure(
        // Only a key recorded as drawn here has a known history: `imported`, no row, or a value this code never writes leave it unknown.
        history: row.readNullable<String>('origin') == _generated
            ? GarageKeyHistory.drawnHere
            : GarageKeyHistory.unknown,
        hasBinding: row.read<bool>('bound'),
      ),
    );
  }

  @override
  Future<Result<bool, P2pFailure>> hasAnyBinding() async {
    try {
      final any = await (_database.select(
        _database.robotBindings,
      )..limit(1)).getSingleOrNull();
      return Ok(any != null);
    } on Exception {
      return const Err(P2pStorageFailure());
    }
  }

  static RobotBinding? _bindingOf(RobotBindingRow row) {
    final network = _networkFrom(row.network);
    if (network == null) return null;
    return RobotBinding(
      CoordinatorIdentity(
        network: network,
        alias: row.coordinatorAlias,
        onion: row.coordinatorOnion,
        nodeKeys: row.coordinatorNodeKeys
            .split(',')
            .where((key) => key.isNotEmpty),
        nostrKey: row.coordinatorNostrKey,
      ),
      DateTime.fromMillisecondsSinceEpoch(row.boundAt, isUtc: true),
    );
  }

  /// The network a row stores, or `null` for a value this code never writes.
  static RobosatsNetwork? _networkFrom(String value) {
    for (final network in RobosatsNetwork.values) {
      if (_networkValue(network) == value) return network;
    }
    return null;
  }

  /// The network as the database stores it; a new network does not compile without a decision.
  static String _networkValue(RobosatsNetwork network) => switch (network) {
    RobosatsNetwork.mainnet => 'mainnet',
    RobosatsNetwork.testnet => 'testnet',
  };

  /// Runs [statement], turning anything the database throws into a [P2pStorageFailure].
  static Future<Result<void, P2pFailure>> _guard(
    Future<void> Function() statement,
  ) async {
    try {
      await statement();
      return const Ok(null);
    } on Exception {
      return const Err(P2pStorageFailure());
    }
  }
}
