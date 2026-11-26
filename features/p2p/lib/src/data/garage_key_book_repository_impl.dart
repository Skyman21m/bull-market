import 'package:drift/drift.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../domain/garage_key_fingerprint.dart';
import '../domain/garage_keyring.dart';
import '../domain/p2p_failure.dart';
import '../domain/repositories/garage_key_book_repository.dart';
import 'p2p_database.dart';

/// The Garage Keys of the words this device activated, the key selected on each network with the last internal one, and the Garage's notices shown once, in the feature's database (schema 10, #81).
///
/// Every statement commits on its own, synced to disk, before its future completes; it returns no row of the database, and a [P2pStorageFailure] for any [Exception] the database throws, or for a row this code never writes.
final class GarageKeyBookRepositoryImpl implements GarageKeyBookRepository {
  /// The history of the key on its network, written as a key drawn here unless one is recorded already (an earlier record wins, as `RobotBindingRepositoryImpl.recordGeneratedKey` writes it).
  static const String _recordDrawnHere =
      'INSERT INTO garage_key_histories (network, key_fingerprint, origin, recorded_at) '
      "VALUES (?, ?, 'generated', ?) "
      'ON CONFLICT (network, key_fingerprint) DO NOTHING';

  /// The key of an index, written only when it is the next one of its network (0 when none is): one statement, so two calls never both write the same index or skip one.
  static const String _activateNext =
      'INSERT INTO derived_garage_keys (network, key_index, key_fingerprint, activated_at) '
      'SELECT ?, ?, ?, ? '
      'WHERE (SELECT coalesce(max(key_index), -1) FROM derived_garage_keys WHERE network = ?) = ? - 1 '
      'ON CONFLICT DO NOTHING RETURNING key_fingerprint';

  /// The selection of an internal Garage Key, written only when its index is activated on its network, and kept as the last internal one: one statement, so a selection never names a key of the words this device does not have.
  static const String _selectWords =
      'INSERT INTO selected_garage_keys (network, key_index, last_internal_index) '
      'SELECT ?, ?, ? WHERE EXISTS (SELECT 1 FROM derived_garage_keys WHERE network = ? AND key_index = ?) '
      'ON CONFLICT (network) DO UPDATE SET key_index = excluded.key_index, '
      'last_internal_index = excluded.last_internal_index '
      'RETURNING network';

  /// The selection of the external Garage Key, with no index; the internal one selected until then is kept as the last internal one (SQLite reads every column of the update in the row as it was).
  static const String _selectExternal =
      'INSERT INTO selected_garage_keys (network, key_index, last_internal_index) VALUES (?, NULL, NULL) '
      'ON CONFLICT (network) DO UPDATE SET key_index = NULL, '
      'last_internal_index = coalesce(key_index, last_internal_index) '
      'RETURNING network';

  /// « Your Garage Keys » turned shown, only when it is due.
  static const String _noticeShown =
      'UPDATE garage_notices SET shown = 1 WHERE notice = ? AND shown = 0';

  /// The one notice of the table.
  static const String _externalKeyNamed = 'externalKeyNamed';

  final P2pDatabase _database;
  final DateTime Function() _clock;

  const GarageKeyBookRepositoryImpl(this._database, {required this._clock});

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

  @override
  Future<Result<GarageKeySelection?, P2pFailure>> selected(
    RobosatsNetwork network,
  ) async {
    try {
      final row = await _database
          .customSelect(
            'SELECT key_index FROM selected_garage_keys WHERE network = ?',
            variables: [Variable.withString(_networkValue(network))],
            readsFrom: {_database.selectedGarageKeys},
          )
          .getSingleOrNull();
      return switch (row) {
        null => const Ok(null),
        _ => switch (row.data['key_index']) {
          null => const Ok(SelectedExternalKey()),
          final int index => Ok(SelectedWordsKey(index)),
          _ => const Err(P2pStorageFailure()),
        },
      };
    } on Exception {
      return const Err(P2pStorageFailure());
    }
  }

  @override
  Future<Result<int?, P2pFailure>> lastInternal(RobosatsNetwork network) async {
    try {
      final row = await _database
          .customSelect(
            'SELECT last_internal_index FROM selected_garage_keys WHERE network = ?',
            variables: [Variable.withString(_networkValue(network))],
            readsFrom: {_database.selectedGarageKeys},
          )
          .getSingleOrNull();
      return switch (row?.data['last_internal_index']) {
        null => const Ok(null),
        final int index => Ok(index),
        _ => const Err(P2pStorageFailure()),
      };
    } on Exception {
      return const Err(P2pStorageFailure());
    }
  }

  @override
  Future<Result<bool, P2pFailure>> externalNoticeDue() async {
    try {
      final row = await _database
          .customSelect(
            'SELECT shown FROM garage_notices WHERE notice = ?',
            variables: [Variable.withString(_externalKeyNamed)],
            readsFrom: {_database.garageNotices},
          )
          .getSingleOrNull();
      return switch (row?.data['shown']) {
        null || 1 => const Ok(false),
        0 => const Ok(true),
        _ => const Err(P2pStorageFailure()),
      };
    } on Exception {
      return const Err(P2pStorageFailure());
    }
  }

  @override
  Future<Result<void, P2pFailure>> externalNoticeShown() async {
    try {
      await _database.customUpdate(
        _noticeShown,
        variables: [Variable.withString(_externalKeyNamed)],
        updates: {_database.garageNotices},
        updateKind: UpdateKind.update,
      );
      return const Ok(null);
    } on Exception {
      return const Err(P2pStorageFailure());
    }
  }

  @override
  Future<Result<bool, P2pFailure>> select(
    RobosatsNetwork network,
    GarageKeySelection selection,
  ) async {
    final value = _networkValue(network);
    try {
      final written = switch (selection) {
        SelectedWordsKey(:final index) => await _database.customWriteReturning(
          _selectWords,
          variables: [
            Variable.withString(value),
            Variable.withInt(index),
            Variable.withInt(index),
            Variable.withString(value),
            Variable.withInt(index),
          ],
          updates: {_database.selectedGarageKeys},
        ),
        SelectedExternalKey() => await _database.customWriteReturning(
          _selectExternal,
          variables: [Variable.withString(value)],
          updates: {_database.selectedGarageKeys},
        ),
      };
      return Ok(written.isNotEmpty);
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
