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
/// [bind] holds without a transaction around its two statements: the insert is one statement, so SQLite runs it atomically, it writes only when no binding exists and the key is recorded as drawn on this device or acknowledged, copying that record as the binding's provenance, and a binding is never changed or deleted, so the read that follows sees the binding that won.
/// The primary key (key fingerprint, robot index), whatever the network, keeps it so across connections and isolates as well: a robot's credential is the same on both networks, so an index bound on one is bound on the other.
/// Every statement commits on its own, synced to disk, before its future completes.
/// It returns no row of the database: the domain types only, and a [P2pStorageFailure] for any [Exception] the database or the directory the shell gave throws.
/// An [Error] is a bug (AGENTS.md, rule 11) and is not caught: the call throws, and the caller sends nothing.
/// Several connections writing at once can make SQLite give up after its busy timeout, a [P2pStorageFailure] that refuses the request; the app opens one connection, in the foreground only, and drift runs its statements one at a time, so it is not exposed to that.
final class RobotBindingRepositoryImpl implements RobotBindingRepository {
  static const String _generated = 'generated';
  static const String _imported = 'imported';
  static const String _acknowledged = 'acknowledged';

  /// Writes the binding only when the robot has none, on either network, and its key was drawn on this device or acknowledged for the robot's network, with that origin as its provenance; an existing binding wins over any later one.
  ///
  /// The history has one row per network and key, so the select gives at most one row.
  /// Its `WHERE` also keeps SQLite from reading `ON CONFLICT` as a join constraint.
  static const String _bindIfFreshSql =
      'INSERT INTO robot_bindings (network, key_fingerprint, robot_index, '
      'coordinator_alias, coordinator_onion, coordinator_node_keys, '
      'coordinator_nostr_key, bound_at, provenance) '
      'SELECT ?, ?, ?, ?, ?, ?, ?, ?, origin FROM garage_key_histories '
      'WHERE network = ? AND key_fingerprint = ? AND origin IN (?, ?) '
      'ON CONFLICT (key_fingerprint, robot_index) DO NOTHING';

  /// Whether any robot index of a key is bound, whatever the network, and the origin of the key on one network, absent when none is recorded, in one statement.
  static const String _exposureSql =
      'SELECT EXISTS (SELECT 1 FROM robot_bindings WHERE key_fingerprint = ?) '
      'AS bound, (SELECT origin FROM garage_key_histories '
      'WHERE network = ? AND key_fingerprint = ?) AS origin';

  /// The origin of a key on one network, absent when none is recorded, and the binding of one of its robot indexes, its columns absent when there is none, in one statement that always gives one row.
  ///
  /// A recorded origin that is NULL, which the schema forbids, reads as an empty text, which no version writes, so that it is not taken for a key without a record.
  static const String _standingSql =
      'SELECT (SELECT coalesce(origin, \'\') FROM garage_key_histories '
      'WHERE network = ? AND key_fingerprint = ?) AS key_origin, '
      'robot_bindings.* FROM (SELECT 1) LEFT JOIN robot_bindings '
      'ON robot_bindings.key_fingerprint = ? '
      'AND robot_bindings.robot_index = ?';

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
  Future<Result<void, P2pFailure>> recordAcknowledgedKey(
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
            origin: _acknowledged,
            recordedAt: now,
          ),
          // Only an imported key turns acknowledged: a key drawn here keeps its record, and one already acknowledged its first time.
          onConflict: DoUpdate(
            (_) => GarageKeyHistoriesCompanion(
              origin: const Value(_acknowledged),
              recordedAt: Value(now),
            ),
            where: (old) => old.origin.equals(_imported),
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
          Variable.withString(_acknowledged),
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
      // Not written: the key was neither drawn on this device nor acknowledged, so the robot may live on a coordinator already.
      null => const Err(RobotHistoryUnknownFailure()),
      final stored => switch (_bindingFrom(
        network: stored.network,
        alias: stored.coordinatorAlias,
        onion: stored.coordinatorOnion,
        nodeKeys: stored.coordinatorNodeKeys,
        nostrKey: stored.coordinatorNostrKey,
        boundAt: stored.boundAt,
        provenance: stored.provenance,
      )) {
        final binding? => binding.admits(coordinator),
        // A network, a provenance or a time the constraints of the table, or a `DateTime`, do not allow: a row this code did not write.
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
        history: _historyFrom(row.readNullable<String>('origin')),
        hasBinding: row.read<bool>('bound'),
      ),
    );
  }

  @override
  Future<Result<RobotStanding, P2pFailure>> standingOf(RobotSlot robot) async {
    final fingerprint = robot.keyFingerprint.hex;
    try {
      final row = await _database
          .customSelect(
            _standingSql,
            variables: [
              Variable.withString(_networkValue(robot.network)),
              Variable.withString(fingerprint),
              Variable.withString(fingerprint),
              Variable.withInt(robot.accountIndex),
            ],
            readsFrom: {_database.robotBindings, _database.garageKeyHistories},
          )
          .getSingle();
      return _standingFrom(robot.network, row.data);
    } on Exception {
      return const Err(P2pStorageFailure());
    }
  }

  /// The standing the row of [_standingSql] gives for a robot of [network], or a [P2pStorageFailure] for a row this code never writes.
  ///
  /// The values are read as SQLite gives them, with no conversion that could throw: a value of another type, a NULL the schema forbids, an origin, network or provenance outside the constraints, or a time outside what a `DateTime` holds is such a row.
  /// Unlike [exposureOf], whose `unknown` asks the PIN, an origin this code never writes is not read as an unknown history here: a robot shown as free could be bound.
  static Result<RobotStanding, P2pFailure> _standingFrom(
    RobosatsNetwork network,
    Map<String, Object?> data,
  ) {
    final GarageKeyHistory history;
    switch (data['key_origin']) {
      case null:
        // No record of the key on that network.
        history = GarageKeyHistory.unknown;
      case _generated:
        history = GarageKeyHistory.drawnHere;
      case _acknowledged:
        history = GarageKeyHistory.acknowledged;
      case _imported:
        history = GarageKeyHistory.unknown;
      default:
        return const Err(P2pStorageFailure());
    }
    // A column of the primary key is absent only when the join found no binding.
    if (data['key_fingerprint'] == null) {
      return Ok(
        RobotStanding(network: network, binding: null, history: history),
      );
    }
    final binding = switch (data) {
      {
        'network': final String boundNetwork,
        'coordinator_alias': final String alias,
        'coordinator_onion': final String onion,
        'coordinator_node_keys': final String nodeKeys,
        'coordinator_nostr_key': final String nostrKey,
        'bound_at': final int boundAt,
        'provenance': final String provenance,
      } =>
        _bindingFrom(
          network: boundNetwork,
          alias: alias,
          onion: onion,
          nodeKeys: nodeKeys,
          nostrKey: nostrKey,
          boundAt: boundAt,
          provenance: provenance,
        ),
      _ => null,
    };
    if (binding == null) return const Err(P2pStorageFailure());
    return Ok(
      RobotStanding(network: network, binding: binding, history: history),
    );
  }

  /// The history an origin of the table gives, absent when the key has no row on the network.
  ///
  /// Only a key recorded as drawn here or acknowledged has a history the bindings follow: `imported`, no row, or a value this code never writes leave it unknown, which is the answer that asks the PIN.
  static GarageKeyHistory _historyFrom(String? origin) => switch (origin) {
    _generated => GarageKeyHistory.drawnHere,
    _acknowledged => GarageKeyHistory.acknowledged,
    _ => GarageKeyHistory.unknown,
  };

  /// The largest distance from the epoch a `DateTime` holds, in milliseconds.
  static const int _maxMilliseconds = 8640000000000000;

  /// The binding the values of a row make, or `null` for a value this code never writes: a network or a provenance outside the constraints, or a time outside what a `DateTime` holds.
  static RobotBinding? _bindingFrom({
    required String network,
    required String alias,
    required String onion,
    required String nodeKeys,
    required String nostrKey,
    required int boundAt,
    required String provenance,
  }) {
    final coordinatorNetwork = _networkFrom(network);
    final bindingProvenance = switch (provenance) {
      _generated => BindingProvenance.drawnHere,
      _acknowledged => BindingProvenance.acknowledged,
      _ => null,
    };
    if (coordinatorNetwork == null ||
        bindingProvenance == null ||
        boundAt < -_maxMilliseconds ||
        boundAt > _maxMilliseconds) {
      return null;
    }
    return RobotBinding(
      CoordinatorIdentity(
        network: coordinatorNetwork,
        alias: alias,
        onion: onion,
        nodeKeys: nodeKeys.split(',').where((key) => key.isNotEmpty),
        nostrKey: nostrKey,
      ),
      DateTime.fromMillisecondsSinceEpoch(boundAt, isUtc: true),
      bindingProvenance,
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
