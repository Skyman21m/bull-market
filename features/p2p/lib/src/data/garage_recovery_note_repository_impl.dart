import 'package:drift/drift.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../domain/garage_key_fingerprint.dart';
import '../domain/p2p_failure.dart';
import '../domain/repositories/garage_recovery_note_repository.dart';
import 'p2p_database.dart';

/// What this device read of the RoboSats recovery notes, in the feature's database (schema 11, #81).
///
/// Every statement commits on its own, synced to disk, before its future completes; a [P2pStorageFailure] for any [Exception] the database throws, or for a row this code never writes.
/// The triggers of `garage_recovery_notes.drift` refuse, whatever the code, any delete, a second insert of a key's row (`INSERT OR REPLACE` included), a floor lowered or cleared, a reading cleared or changed, and a row moved to another network or key.
final class GarageRecoveryNoteRepositoryImpl
    implements GarageRecoveryNoteRepository {
  /// The row of a key made when missing, with the reading's floor and time; when it exists, the trigger `garage_recovery_notes_inserted_once` makes it write nothing, and [_raiseSql] records the reading.
  static const String _insertSql =
      'INSERT INTO garage_recovery_notes (network, key_fingerprint, account_floor, read_at) '
      'VALUES (?, ?, ?, ?)';

  /// A reading over the row of its key: the floor raised when the new one is above (never lowered, never cleared) and the reading kept once recorded (SQLite reads every column of the update in the row as it was). Run after [_insertSql], it gives a row that statement has just made the values it already holds; an app stopped between the two leaves the row the insert made, which already holds the reading.
  static const String _raiseSql =
      'UPDATE garage_recovery_notes SET '
      'account_floor = CASE WHEN account_floor IS NULL THEN ?1 '
      'WHEN ?1 IS NULL THEN account_floor '
      'ELSE max(account_floor, ?1) END, '
      'read_at = coalesce(read_at, ?2) '
      'WHERE network = ?3 AND key_fingerprint = ?4';

  static const String _standingSql =
      'SELECT account_floor, read_at FROM garage_recovery_notes '
      'WHERE network = ? AND key_fingerprint = ?';

  static const String _floorSql =
      'SELECT max(account_floor) AS floor FROM garage_recovery_notes '
      'WHERE key_fingerprint = ?';

  final P2pDatabase _database;
  final DateTime Function() _clock;

  const GarageRecoveryNoteRepositoryImpl(
    this._database, {
    required this._clock,
  });

  @override
  Future<Result<GarageNoteStanding, P2pFailure>> standingOf(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) async {
    final QueryRow? row;
    try {
      row = await _database
          .customSelect(
            _standingSql,
            variables: [
              Variable.withString(_networkValue(network)),
              Variable.withString(key.hex),
            ],
            readsFrom: {_database.storedGarageRecoveryNotes},
          )
          .getSingleOrNull();
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    if (row == null) {
      return const Ok(GarageNoteStanding(floor: null, read: false));
    }
    final floor = row.data['account_floor'];
    final readAt = row.data['read_at'];
    if ((floor != null && !_isIndex(floor)) ||
        (readAt != null && readAt is! int)) {
      return const Err(P2pStorageFailure());
    }
    return Ok(GarageNoteStanding(floor: floor as int?, read: readAt != null));
  }

  @override
  Future<Result<void, P2pFailure>> recordReading(
    RobosatsNetwork network,
    GarageKeyFingerprint key, {
    required int? floor,
    required bool answered,
  }) async {
    if (floor != null && !_isIndex(floor)) {
      return const Err(P2pStorageFailure());
    }
    final readAt = answered ? _clock().millisecondsSinceEpoch : null;
    try {
      await _database.customInsert(
        _insertSql,
        variables: [
          Variable.withString(_networkValue(network)),
          Variable.withString(key.hex),
          Variable<int>(floor),
          Variable<int>(readAt),
        ],
        updates: {_database.storedGarageRecoveryNotes},
      );
      await _database.customUpdate(
        _raiseSql,
        variables: [
          Variable<int>(floor),
          Variable<int>(readAt),
          Variable.withString(_networkValue(network)),
          Variable.withString(key.hex),
        ],
        updates: {_database.storedGarageRecoveryNotes},
        updateKind: UpdateKind.update,
      );
    } on Exception {
      return const Err(P2pStorageFailure());
    }
    return const Ok(null);
  }

  @override
  Stream<Result<int?, P2pFailure>> watchFloor(GarageKeyFingerprint key) =>
      _database
          .customSelect(
            _floorSql,
            variables: [Variable.withString(key.hex)],
            readsFrom: {_database.storedGarageRecoveryNotes},
          )
          .watchSingle()
          .map<Result<int?, P2pFailure>>((row) {
            final floor = row.data['floor'];
            if (floor == null) return const Ok(null);
            return _isIndex(floor)
                ? Ok(floor as int)
                : const Err(P2pStorageFailure());
          });

  static bool _isIndex(Object? value) =>
      value is int && value >= 0 && value <= 0x7fffffff;

  static String _networkValue(RobosatsNetwork network) => switch (network) {
    RobosatsNetwork.mainnet => 'mainnet',
    RobosatsNetwork.testnet => 'testnet',
  };
}
