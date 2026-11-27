import 'dart:convert';

import 'package:p2p/src/data/isolate_garage_note_compute.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

/// The work on the recovery note in an isolate of its own (#81): a note composed there reads back, and a reading that takes longer than its limit is stopped.
void main() {
  final key = switch (GarageKey.fromBytes(List.filled(32, 9))) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  const compute = IsolateGarageNoteCompute();

  test('a note composed apart reads back apart, from the identities only', () async {
    final note = switch (await compute.composeNote(
      key.recoveryNostrKeyPair,
      accountIndex: 17,
      now: DateTime.utc(2026, 11, 27),
    )) {
      Ok(value: Ok(:final value)) => value,
      final other => throw StateError('$other'),
    };
    final event = jsonEncode(
      (jsonDecode(note.relayMessages.single) as List<Object?>)[1],
    );
    final reading = await compute.readNotes(
      [key.recoveryNostrKeyPair, key.legacyRecoveryNostrKeyPair],
      [event],
      limit: const Duration(seconds: 30),
    );
    expect(
      reading,
      isA<Ok<GarageRecoveryReading?, RobotKeyComputeFailure>>().having(
        (ok) => ok.value?.accountIndex,
        'index',
        17,
      ),
    );
  });

  test('an index out of range is the package\'s refusal', () async {
    expect(
      await compute.composeNote(
        key.recoveryNostrKeyPair,
        accountIndex: -1,
        now: DateTime.utc(2026, 11, 27),
      ),
      isA<Ok<Result<OutgoingGarageRecoveryNote, AccountIndexOutOfRange>, RobotKeyComputeFailure>>()
          .having((ok) => ok.value, 'inner', isA<Err>()),
    );
  });

  test('work past its limit is stopped, its isolate killed', () async {
    final waited = Stopwatch()..start();
    final result = await IsolateGarageNoteCompute.runStopped(() {
      var x = 0;
      while (true) {
        x++;
        if (x < 0) return x;
      }
    }, const Duration(milliseconds: 200));
    expect(result, isA<Err<int, RobotKeyComputeFailure>>());
    expect(waited.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('an error of the work reaches the caller', () async {
    await expectLater(
      IsolateGarageNoteCompute.runStopped<int>(
        () => throw StateError('a bug'),
        const Duration(seconds: 5),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
