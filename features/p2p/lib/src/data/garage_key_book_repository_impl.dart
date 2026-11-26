import 'package:drift/drift.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../domain/garage_key_fingerprint.dart';
import '../domain/garage_keyring.dart';
import '../domain/p2p_failure.dart';
import '../domain/repositories/garage_key_book_repository.dart';
import 'p2p_database.dart';

/// The Garage Keys of the words this device activated, and the one-time switch of the book, in the feature's database (schema 10, #81).
///
/// Every statement commits on its own, synced to disk, before its future completes; it returns no row of the database, and a [P2pStorageFailure] for any [Exception] the database throws, or for a row this code never writes.
final class GarageKeyBookRepositoryImpl implements GarageKeyBookRepository {
  /// The history of the key on its network, written as a key drawn here unless one is recorded already (an earlier record wins, as `RobotBindingRepositoryImpl.recordGeneratedKey` writes it).
  static const String _recordDrawnHere =
      'INSERT INTO garage_key_histories (network, key_fingerprint, origin, recorded_at) '
      "SELECT ?, ?, 'generated', ? WHERE EXISTS (SELECT 1 FROM garage_switch WHERE id = 1 AND state = 'derived') "
      'ON CONFLICT (network, key_fingerprint) DO NOTHING';

  /// The key of an index, written only when it is the next one of its network (0 when none is) and the switch is `derived`: one statement, so two calls never both write the same index or skip one.
  static const String _activateNext =
      'INSERT INTO derived_garage_keys (network, key_index, key_fingerprint, activated_at) '
      'SELECT ?, ?, ?, ? '
      'WHERE (SELECT coalesce(max(key_index), -1) FROM derived_garage_keys WHERE network = ?) = ? - 1 '
      "AND EXISTS (SELECT 1 FROM garage_switch WHERE id = 1 AND state = 'derived') "
      'ON CONFLICT DO NOTHING RETURNING key_fingerprint';

  final P2pDatabase _database;
  final DateTime Function() _clock;

  const GarageKeyBookRepositoryImpl(this._database, {required this._clock});

  @override
  Future<Result<GarageSwitchState, P2pFailure>> switchState() async {
    try {
      final row = await _database
          .customSelect(
            'SELECT state FROM garage_switch WHERE id = 1',
            readsFrom: {_database.garageSwitch},
          )
          .getSingleOrNull();
      return switch (row?.data['state']) {
        'legacy' => const Ok(GarageSwitchState.legacy),
        'emptying' => const Ok(GarageSwitchState.emptying),
        'vaultPending' => const Ok(GarageSwitchState.vaultPending),
        'derived' => const Ok(GarageSwitchState.derived),
        // No row, which the opening always writes, or a state the constraints forbid: never read as a switch done.
        _ => const Err(P2pStorageFailure()),
      };
    } on Exception {
      return const Err(P2pStorageFailure());
    }
  }

  @override
  Future<Result<void, P2pFailure>> markDerived() async {
    try {
      await _database.customUpdate(
        "UPDATE garage_switch SET state = 'derived' WHERE id = 1 AND state = 'vaultPending'",
        updates: {_database.garageSwitch},
      );
      return const Ok(null);
    } on Exception {
      return const Err(P2pStorageFailure());
    }
  }

  @override
  Future<Result<List<ActivatedGarageKey>, P2pFailure>> activatedKeys(
    RobosatsNetwork network,
  ) async {
    final List<QueryRow> rows;
    try {
      rows = await _database
          .customSelect(
            'SELECT key_index, key_fingerprint FROM derived_garage_keys '
            'WHERE network = ? ORDER BY key_index',
            variables: [Variable.withString(_networkValue(network))],
            readsFrom: {_database.derivedGarageKeys},
          )
          .get();
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    final keys = <ActivatedGarageKey>[];
    for (final row in rows) {
      final fingerprint = switch (row.data['key_fingerprint']) {
        final String hex => GarageKeyFingerprint.stored(hex),
        _ => null,
      };
      final index = row.data['key_index'];
      // Indexes from 0, one by one: anything else is a row this code never writes.
      if (fingerprint == null || index is! int || index != keys.length) {
        return const Err(P2pStorageFailure());
      }
      keys.add(ActivatedGarageKey(index, fingerprint));
    }
    return Ok(List.unmodifiable(keys));
  }

  @override
  Future<Result<bool, P2pFailure>> activate(
    RobosatsNetwork network,
    int index,
    GarageKeyFingerprint fingerprint,
  ) async {
    if (index < 0 || index > 0x7fffffff) {
      throw ArgumentError.value(
        index,
        'index',
        'must be between 0 and 0x7fffffff',
      );
    }
    final value = _networkValue(network);
    final now = _clock().millisecondsSinceEpoch;
    try {
      await _database.customInsert(
        _recordDrawnHere,
        variables: [
          Variable.withString(value),
          Variable.withString(fingerprint.hex),
          Variable.withInt(now),
        ],
        updates: {_database.garageKeyHistories},
      );
      final written = await _database.customWriteReturning(
        _activateNext,
        variables: [
          Variable.withString(value),
          Variable.withInt(index),
          Variable.withString(fingerprint.hex),
          Variable.withInt(now),
          Variable.withString(value),
          Variable.withInt(index),
        ],
        updates: {_database.derivedGarageKeys},
      );
      return switch (written) {
        [] => const Ok(false),
        // The row this call wrote holds the fingerprint it was given.
        [final row] when row.data['key_fingerprint'] == fingerprint.hex =>
          const Ok(true),
        _ => const Err(P2pStorageFailure()),
      };
    } on Exception {
      return const Err(P2pStorageFailure());
    }
  }

  /// The network as the database stores it; a new network does not compile without a decision.
  static String _networkValue(RobosatsNetwork network) => switch (network) {
    RobosatsNetwork.mainnet => 'mainnet',
    RobosatsNetwork.testnet => 'testnet',
  };
}
