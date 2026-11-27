import 'package:meta/meta.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show RobosatsNetwork;

import '../garage_key_fingerprint.dart';
import '../p2p_failure.dart';

/// What `p2p.sqlite` keeps of the RoboSats recovery note of each Garage Key on each network's relays (schema 11, #81, design note `docs/design/garage-key-from-the-words.md` § 3): the robot index the note said, the floor of the key's new trades, and whether a reading counted as read for good (the whole answer of a strict majority of the network's relays, review of #302). Never a key, a recovery identity or a note: the key's fingerprint and numbers only.
///
/// The floor only goes up, a reading once recorded stays, a row stays the row of its key, and a row is never deleted nor written twice, as the database's triggers enforce (`garage_recovery_notes.drift`), whatever statement writes.
abstract interface class GarageRecoveryNoteRepository {
  /// What this device read of the note of [key] on the relays of [network].
  @useResult
  Future<Result<GarageNoteStanding, P2pFailure>> standingOf(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  );

  /// Records a reading of the note of [key] on the relays of [network]: the floor raised to [floor] when it is above the one recorded (a lower one changes nothing), and the key recorded as read for good when [answered], which the caller sets only on the whole answer of a strict majority of the network's relays (a reading recorded stays). A floor recorded without [answered] leaves the key unread, to be read again at the next run; a later reading with [answered] then records it read, the floor kept or raised.
  @useResult
  Future<Result<void, P2pFailure>> recordReading(
    RobosatsNetwork network,
    GarageKeyFingerprint key, {
    required int? floor,
    required bool answered,
  });

  /// The floor recorded for [key], at its highest over both networks, again after each write of the readings: first the value now.
  Stream<Result<int?, P2pFailure>> watchFloor(GarageKeyFingerprint key);
}

/// What this device read of the recovery note of one key on one network's relays.
@immutable
final class GarageNoteStanding {
  /// The robot index the note said, at its highest over the readings; `null` while none was read.
  final int? floor;

  /// Whether a reading counted as read for good, on the whole answer of a strict majority of the network's relays: in a later run, a majority of the relays that gives no note then lets new trades of the key go without waiting for the relays left (its one use, security review of #302); the key is still read at each run.
  final bool read;

  const GarageNoteStanding({required this.floor, required this.read});

  @override
  bool operator ==(Object other) =>
      other is GarageNoteStanding && other.floor == floor && other.read == read;

  @override
  int get hashCode => Object.hash(floor, read);

  @override
  String toString() => 'GarageNoteStanding(floor: $floor, read: $read)';
}
