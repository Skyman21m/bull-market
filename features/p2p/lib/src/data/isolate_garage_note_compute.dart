import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show
        AccountIndexOutOfRange,
        GarageRecoveryNote,
        GarageRecoveryReading,
        NostrKeyPair,
        OutgoingGarageRecoveryNote;

import '../domain/garage_note_compute_port.dart';
import '../domain/p2p_failure.dart';

/// Runs the work on the recovery note of a Garage Key in a short-lived isolate of its own (#81), so that the UI isolate never unwraps nor signs a note.
///
/// What is copied there: the key's recovery identities (never the Garage Key), the events of one relay, [DateTime] and an index; what comes back: the note composed, or the reading kept. Each closure is made in a static method, where it holds nothing but its arguments.
/// A reading that takes longer than its limit is stopped: its isolate is killed at once, so that a relay's hostile batch costs at most that time of computing. An isolate that cannot be started is a [RobotKeyComputeFailure]; an [Error] of the work is a bug and reaches the caller, as rule 11 of AGENTS.md wants.
final class IsolateGarageNoteCompute implements GarageNoteComputePort {
  const IsolateGarageNoteCompute();

  @override
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
  }) => _composeApart(identity, accountIndex, now);

  @override
  Future<Result<GarageRecoveryReading?, RobotKeyComputeFailure>> readNotes(
    List<NostrKeyPair> identities,
    List<String> events, {
    required Duration limit,
  }) => _readApart(identities, events, limit);

  static Future<
    Result<
      Result<OutgoingGarageRecoveryNote, AccountIndexOutOfRange>,
      RobotKeyComputeFailure
    >
  >
  _composeApart(NostrKeyPair identity, int accountIndex, DateTime now) async {
    try {
      return Ok(
        await Isolate.run(
          () => GarageRecoveryNote.composeFor(
            identity,
            accountIndex: accountIndex,
            now: now,
            random: Random.secure(),
          ),
          debugName: 'garage note',
        ),
      );
    } on IsolateSpawnException {
      return const Err(RobotKeyComputeFailure());
    }
  }

  static Future<Result<GarageRecoveryReading?, RobotKeyComputeFailure>>
  _readApart(
    List<NostrKeyPair> identities,
    List<String> events,
    Duration limit,
  ) => runStopped(
    () => GarageRecoveryNote.latestNoteFor(identities, events),
    limit,
  );

  /// The result of [work], computed in a new isolate that is killed once [limit] has passed: then, or when the isolate cannot be started, a [RobotKeyComputeFailure].
  ///
  /// An [Error] or an [Exception] the work throws is given to the caller, as `Isolate.run` gives it.
  static Future<Result<T, RobotKeyComputeFailure>> runStopped<T>(
    T Function() work,
    Duration limit,
  ) async {
    final port = RawReceivePort();
    final answer = Completer<Result<T, RobotKeyComputeFailure>>();
    Isolate? isolate;
    Timer? timer;
    void end(Result<T, RobotKeyComputeFailure> result) {
      timer?.cancel();
      port.close();
      isolate?.kill(priority: Isolate.immediate);
      if (!answer.isCompleted) answer.complete(result);
    }

    port.handler = (Object? message) {
      if (answer.isCompleted) return;
      switch (message) {
        case _Done<T>(:final value):
          end(Ok(value));
        case _Failed(:final error, :final trace):
          timer?.cancel();
          port.close();
          answer.completeError(error, trace);
        // The isolate ended without an answer.
        case _:
          end(const Err(RobotKeyComputeFailure()));
      }
    };
    try {
      isolate = await Isolate.spawn(
        _entry<T>,
        (work, port.sendPort),
        onExit: port.sendPort,
        debugName: 'garage note',
      );
    } on IsolateSpawnException {
      port.close();
      return const Err(RobotKeyComputeFailure());
    }
    if (!answer.isCompleted) {
      timer = Timer(limit, () => end(const Err(RobotKeyComputeFailure())));
    } else {
      isolate.kill(priority: Isolate.immediate);
    }
    return answer.future;
  }

  static void _entry<T>((T Function(), SendPort) message) {
    final (work, reply) = message;
    try {
      reply.send(_Done<T>(work()));
    } on Object catch (error, trace) {
      // Sent to the caller, which rethrows it: an error of the work is a bug, as with `Isolate.run`.
      reply.send(_Failed(error, trace));
    }
  }
}

final class _Done<T> {
  final T value;

  const _Done(this.value);
}

final class _Failed {
  final Object error;
  final StackTrace trace;

  const _Failed(this.error, this.trace);
}
