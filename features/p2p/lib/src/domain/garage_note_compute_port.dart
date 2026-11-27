import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show
        AccountIndexOutOfRange,
        GarageRecoveryReading,
        NostrKeyPair,
        OutgoingGarageRecoveryNote;

import 'p2p_failure.dart';

/// Runs the work on the RoboSats recovery note of a Garage Key away from the UI isolate (#81): tests replace it.
///
/// Composing a note takes three BIP-340 signatures checked, two key agreements and a throwaway key in pure Dart, and reading one relay's answer can cost about 25 seconds of computing on a desktop for a thousand events a hostile relay made up (`packages/robosats/README.md`, « The recovery note of a Garage Key »): on the UI isolate, either would freeze the screens.
/// What crosses to the other isolate is the key's recovery identities, never the Garage Key: they are secrets too, enough to write notes that count, so they are kept no longer than the work.
abstract interface class GarageNoteComputePort {
  /// The note of [identity] that says [accountIndex], as `GarageRecoveryNote.composeFor` builds it with a secure source of randomness, at [now].
  ///
  /// The inner result is the package's: [AccountIndexOutOfRange] for an index outside 0 to 2,147,483,647. The outer [RobotKeyComputeFailure] when the work could not be started: nothing was built.
  Future<
    Result<
      Result<OutgoingGarageRecoveryNote, AccountIndexOutOfRange>,
      RobotKeyComputeFailure
    >
  >
  composeNote(
    NostrKeyPair identity, {
    required int accountIndex,
    required DateTime now,
  });

  /// The latest note of [identities] among [events], the events one relay answered, as `GarageRecoveryNote.latestNoteFor` reads them (at most its bound of events), or `null` when none counts; one call per relay, never a list that mixes relays.
  ///
  /// The work is stopped when it takes longer than [limit], which gives a [RobotKeyComputeFailure], as does work that could not be started: nothing was read.
  Future<Result<GarageRecoveryReading?, RobotKeyComputeFailure>> readNotes(
    List<NostrKeyPair> identities,
    List<String> events, {
    required Duration limit,
  });
}
