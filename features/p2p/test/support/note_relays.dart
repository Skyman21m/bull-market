import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:p2p/src/domain/garage_note_compute_port.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

/// The JSON of the one event of [note], as a relay stores and answers it.
String eventOf(NostrRelayPublication note) =>
    jsonEncode((jsonDecode(note.relayMessages.single) as List<Object?>)[1]);

/// A note of [identity] saying [index], written at [at], as another device or the official client writes it: public test keys only.
String noteOf(NostrKeyPair identity, int index, DateTime at, {int seed = 1}) =>
    switch (GarageRecoveryNote.composeFor(
      identity,
      accountIndex: index,
      now: at,
      random: Random(seed),
    )) {
      Ok(:final value) => eventOf(value),
      Err(:final failure) => throw StateError('$failure'),
    };

/// The `p` tag values of the wrap [event].
Set<String> addresseesOf(String event) => {
  for (final tag
      in ((jsonDecode(event) as Map<String, Object?>)['tags'] as List<Object?>))
    if (tag is List<Object?> && tag.length >= 2 && tag[0] == 'p')
      tag[1] as String,
};

/// What one relay of [FakeNoteRelays] does with a read.
typedef RelayAnswer =
    Future<NostrRelayRead> Function(
      List<String> stored,
      List<NostrRelayFilter> filters,
    );

/// The relays of the coordinators, played in memory: each stores the events published to it and answers a read with those addressed to the filters' identities, its whole answer, unless the test gave it another behaviour.
final class FakeNoteRelays implements OwnSessionNostrRelayTransport {
  /// The events each relay holds, in the order received.
  final Map<Uri, List<String>> stored = {};

  /// What a relay does with a read, where the test set it; the others answer whole.
  final Map<Uri, RelayAnswer> answers = {};

  /// The relays that cannot be reached: a read gives nothing, a publication is unreachable.
  final Set<Uri> down = {};

  /// Every read, in order: the relay and the filters' JSON.
  final List<(Uri, List<String>)> reads = [];

  /// Every publication, in order: the relay and its event.
  final List<(Uri, String)> published = [];

  /// Every publication asked, in order, before [holdPublications] lets it through: the relay and its event.
  final List<(Uri, String)> asked = [];

  /// While set, each publication waits for it before it is stored and answered.
  Future<void>? holdPublications;

  /// The events of [relay].
  List<String> on(Uri relay) => stored.putIfAbsent(relay, () => []);

  @override
  Future<NostrRelayRead> readOnOwnSession(
    Uri relay,
    List<NostrRelayFilter> filters,
  ) async {
    reads.add((relay, [for (final filter in filters) filter.toJson()]));
    if (down.contains(relay)) return const NostrRelayRead.none('unreachable');
    final answer = answers[relay];
    if (answer != null) return answer(on(relay), filters);
    return NostrRelayRead(
      events: matching(on(relay), filters),
      complete: true,
      label: 'answered',
    );
  }

  @override
  Future<NostrRelayOutcome> publishOnOwnSession(
    Uri relay,
    NostrRelayPublication message,
  ) async {
    if (down.contains(relay)) return const NostrRelayUnreachable();
    final event = eventOf(message);
    asked.add((relay, event));
    if (holdPublications case final hold?) await hold;
    published.add((relay, event));
    on(relay).add(event);
    return const NostrRelayAccepted();
  }

  /// The events of [events] a relay gives for [filters]: those whose `p` tag names an identity of a filter.
  static List<String> matching(
    List<String> events,
    List<NostrRelayFilter> filters,
  ) {
    final identities = {
      for (final filter in filters)
        ...((jsonDecode(filter.toJson()) as Map<String, Object?>)['#p']
                as List<Object?>)
            .cast<String>(),
    };
    return [
      for (final event in events)
        if (addresseesOf(event).any(identities.contains)) event,
    ];
  }
}

/// The work on the notes run on the test's isolate, as the app's isolate runs it, each reading recorded.
final class InlineNoteCompute implements GarageNoteComputePort {
  /// The number of events of each reading, in order: one per relay that answered events.
  final List<int> readings = [];

  /// The number of notes composed, or asked to be.
  int composed = 0;

  /// Thrown in place of the next composition, then cleared: a bug of the work.
  Error? composeError;

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
  }) async {
    composed++;
    if (composeError case final error?) {
      composeError = null;
      throw error;
    }
    return Ok(
      GarageRecoveryNote.composeFor(
        identity,
        accountIndex: accountIndex,
        now: now,
        random: Random(3),
      ),
    );
  }

  @override
  Future<Result<GarageRecoveryReading?, RobotKeyComputeFailure>> readNotes(
    List<NostrKeyPair> identities,
    List<String> events, {
    required Duration limit,
  }) async {
    readings.add(events.length);
    return Ok(GarageRecoveryNote.latestNoteFor(identities, events));
  }
}
