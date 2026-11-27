import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:p2p/src/data/garage_recovery_note_repository_impl.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/interim_trade_robots.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/recovery_note_sync.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/garage_recovery_note_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/trade_robots.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/garage_words.dart';
import 'support/note_relays.dart';

/// The RoboSats recovery note kept on the coordinators' relays (#81, design note `docs/design/garage-key-from-the-words.md` § 3, « As PR 3 built it »): read at the first visit of a key, each relay apart, its floor kept across restarts and applied to new trades, written after each confirmed trade and at each opening, against relays played in memory. Keys: the public test phrase « abandon ×11 about » only.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const network = RobosatsNetwork.mainnet;
  final relays = nostrRelaysOfNetwork(Federation.robosats, network);
  final at = DateTime.utc(2026, 11, 27, 10);

  GarageKey parsed(String text) => switch (GarageKey.parse(text)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  // Internal Garage Keys #0 and #1 of the test words on mainnet, and a key standing for an external one.
  final internal0 = NetworkGarageKey(
    network,
    parsed(abandonMainnet0),
    index: 0,
  );
  final internal1 = NetworkGarageKey(
    network,
    parsed(abandonMainnet1),
    index: 1,
  );
  final external = NetworkGarageKey(network, parsed(abandonMainnet2));

  GarageKeyFingerprint fingerprintOf(NetworkGarageKey key) =>
      switch (key.fingerprint) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  late P2pDatabase database;
  late FakeNoteRelays relaysPlayed;
  late InlineNoteCompute compute;
  late _Keys keys;

  setUp(() {
    database = P2pDatabase.forTesting(NativeDatabase.memory());
    relaysPlayed = FakeNoteRelays();
    compute = InlineNoteCompute();
    keys = _Keys([internal0, internal1, external]);
  });

  tearDown(() => database.close());

  TradeRecordRepositoryImpl records() =>
      TradeRecordRepositoryImpl(database, clock: () => at);
  GarageRecoveryNoteRepositoryImpl notes() =>
      GarageRecoveryNoteRepositoryImpl(database, clock: () => at);

  RecoveryNoteSync sync({
    Duration newTradeWait = const Duration(seconds: 5),
    Duration readDeadline = const Duration(seconds: 5),
  }) => RecoveryNoteSync(
    relays: relaysPlayed,
    compute: compute,
    notes: notes(),
    standing: records().newTradeStandingOf,
    keysInUse: records().keysInUse,
    keys: keys,
    federation: Federation.robosats,
    clock: () => at,
    newTradeWait: newTradeWait,
    readDeadline: readDeadline,
  );

  Future<GarageNoteStanding> standingOf(NetworkGarageKey key) async =>
      switch (await notes().standingOf(network, fingerprintOf(key))) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  Future<NewTradeStanding> tradeStandingOf(NetworkGarageKey key) async =>
      switch (await records().newTradeStandingOf(network, fingerprintOf(key))) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  /// The robots [indexes] of [key] bound to a coordinator, as reservations made before this pull request left them.
  Future<void> bind(NetworkGarageKey key, List<int> indexes) async {
    final fingerprint = fingerprintOf(key);
    expect(
      await RobotBindingRepositoryImpl(
        database,
        clock: () => at,
      ).recordGeneratedKey(network, fingerprint),
      isA<Ok>(),
    );
    final coordinator = CoordinatorIdentity.of(
      Federation.robosats.coordinators.first,
      network,
    )!;
    for (final index in indexes) {
      expect(
        await records().reserveForNewTrade(
          RobotSlot(network, fingerprint, index),
          coordinator,
        ),
        isA<Ok<TradeReservation?, P2pFailure>>().having(
          (ok) => ok.value,
          'reservation',
          isNotNull,
        ),
      );
    }
  }

  /// The robot a new trade of [key] would reserve now, through the robot layer the locator builds, the first reading of the note awaited.
  Future<int> nextRobot(
    NetworkGarageKey key,
    RecoveryNoteSync notesSync, {
    int coordinator = 0,
  }) async {
    keys.selected = key;
    final robots = InterimTradeRobots(
      keys,
      records(),
      beforeNewTrade: notesSync.beforeNewTrade,
    );
    return switch (await robots.robotForNewTrade(
      network,
      Federation.robosats.coordinators[coordinator],
    )) {
      Ok(:final value) => value.robot.accountIndex,
      Err(:final failure) => throw StateError('$failure'),
    };
  }

  /// The indexes the notes published for [key] say, one per publication.
  List<int> publishedIndexes(NetworkGarageKey key) => [
    for (final (_, event) in relaysPlayed.published)
      if (GarageRecoveryNote.latestNote(key.key, [event]) case final reading?)
        reading.accountIndex,
  ];

  group('reading', () {
    test(
      'a first visit reads every coordinator relay of the network apart, for the recovery identity and the legacy one, and keeps the floor across a restart',
      () async {
        relaysPlayed
            .on(relays[2])
            .add(noteOf(internal0.key.recoveryNostrKeyPair, 7, at));
        final first = sync();
        await first.beforeNewTrade(internal0);
        expect(relaysPlayed.reads.map((read) => read.$1), relays);
        for (final (_, filters) in relaysPlayed.reads) {
          expect(filters, [
            for (final filter in GarageRecoveryNote.filters(internal0.key))
              filter.toJson(),
          ]);
        }
        // Each relay that answered events is read apart.
        expect(compute.readings, [1]);
        expect(
          await standingOf(internal0),
          const GarageNoteStanding(floor: 7, read: true),
        );
        // A new run of the app: the floor holds, and nothing is read again.
        relaysPlayed.reads.clear();
        final again = sync();
        again.visit(internal0);
        expect(await nextRobot(internal0, again), 8);
        expect(relaysPlayed.reads, isEmpty);
      },
    );

    test(
      'internal Garage Key #1 and the external Garage Key are read at their first visit, each under its own fingerprint',
      () async {
        relaysPlayed.on(relays[0]).addAll([
          noteOf(internal1.key.recoveryNostrKeyPair, 4, at),
          noteOf(external.key.recoveryNostrKeyPair, 11, at),
        ]);
        final notesSync = sync();
        await notesSync.beforeNewTrade(internal1);
        await notesSync.beforeNewTrade(external);
        expect(
          await standingOf(internal1),
          const GarageNoteStanding(floor: 4, read: true),
        );
        expect(
          await standingOf(external),
          const GarageNoteStanding(floor: 11, read: true),
        );
        // Key #0 was never visited: nothing read for it.
        expect(
          await standingOf(internal0),
          const GarageNoteStanding(floor: null, read: false),
        );
      },
    );

    test(
      'a note of the legacy identity counts, as in the official client',
      () async {
        relaysPlayed
            .on(relays[1])
            .add(noteOf(internal0.key.legacyRecoveryNostrKeyPair, 5, at));
        await sync().beforeNewTrade(internal0);
        expect((await standingOf(internal0)).floor, 5);
      },
    );

    test(
      'among relays the latest note wins, whatever its index, and the floor never goes down',
      () async {
        relaysPlayed
            .on(relays[0])
            .add(noteOf(internal0.key.recoveryNostrKeyPair, 9, at));
        relaysPlayed
            .on(relays[1])
            .add(
              noteOf(
                internal0.key.recoveryNostrKeyPair,
                3,
                at.subtract(const Duration(days: 2)),
              ),
            );
        await sync().beforeNewTrade(internal0);
        expect((await standingOf(internal0)).floor, 9);
        // A later reading on another network's relays, or a lying relay, giving a smaller index: the floor stays.
        expect(
          await notes().recordReading(
            network,
            fingerprintOf(internal0),
            floor: 2,
            answered: true,
          ),
          isA<Ok>(),
        );
        expect((await standingOf(internal0)).floor, 9);
        expect((await tradeStandingOf(internal0)).noteFloor, 9);
      },
    );

    test(
      'a relay that gives only an older, smaller note cannot take the robots below what the device knows',
      () async {
        await bind(internal0, [0, 1, 2, 3, 4, 5]);
        relaysPlayed
            .on(relays[0])
            .add(noteOf(internal0.key.recoveryNostrKeyPair, 1, at));
        final notesSync = sync();
        expect(await nextRobot(internal0, notesSync), 6);
      },
    );

    test(
      'a note of another Garage Key, addressed to its own identity, moves nothing: nobody without the key can make a note that counts',
      () async {
        final other = parsed(abandonMainnet2);
        // Even when a relay gives it for the filters of this key.
        relaysPlayed.answers[relays[0]] = (stored, filters) async =>
            NostrRelayRead(
              events: [noteOf(other.recoveryNostrKeyPair, 900, at)],
              complete: true,
              label: 'answered',
            );
        await sync().beforeNewTrade(internal0);
        expect(
          await standingOf(internal0),
          const GarageNoteStanding(floor: null, read: true),
        );
      },
    );

    test(
      'a relay that floods a thousand made-up events does not hide the note another relay gives: each relay is read apart',
      () async {
        final identity = internal0.key.recoveryNostrKeyPair.publicKeyHex;
        relaysPlayed.answers[relays[0]] = (stored, filters) async =>
            NostrRelayRead(
              events: [
                for (var i = 0; i < GarageRecoveryNote.maxEvents; i++)
                  jsonEncode({
                    'kind': 1059,
                    'id': '$i',
                    'tags': [
                      ['p', identity],
                    ],
                    'content': 'not a note',
                  }),
              ],
              complete: true,
              label: 'answered',
            );
        relaysPlayed
            .on(relays[1])
            .add(noteOf(internal0.key.recoveryNostrKeyPair, 12, at));
        await sync().beforeNewTrade(internal0);
        expect(compute.readings, [GarageRecoveryNote.maxEvents, 1]);
        expect((await standingOf(internal0)).floor, 12);
      },
    );

    test(
      'one relay of three with the note is enough; the others answer with nothing',
      () async {
        relaysPlayed
            .on(relays[4])
            .add(noteOf(internal0.key.recoveryNostrKeyPair, 6, at));
        await sync().beforeNewTrade(internal0);
        expect(
          await standingOf(internal0),
          const GarageNoteStanding(floor: 6, read: true),
        );
      },
    );

    test(
      'no relay reachable: the key stays unread, the trade goes on from what the device knows, and the next run reads again',
      () async {
        relaysPlayed.down.addAll(relays);
        final first = sync();
        expect(await nextRobot(internal0, first), 0);
        expect(
          await standingOf(internal0),
          const GarageNoteStanding(floor: null, read: false),
        );
        // One reading per run: a second trade of the same run does not read again.
        final reads = relaysPlayed.reads.length;
        expect(await nextRobot(internal0, first, coordinator: 1), 1);
        expect(relaysPlayed.reads, hasLength(reads));
        // The next run reads again.
        relaysPlayed.down.clear();
        relaysPlayed
            .on(relays[0])
            .add(noteOf(internal0.key.recoveryNostrKeyPair, 20, at));
        expect(await nextRobot(internal0, sync(), coordinator: 2), 21);
      },
    );

    test(
      'relays whose answer is cut short (no EOSE, a connection cut, an endless flow stopped at the bound) count for their notes, never as an answer',
      () async {
        for (final relay in relays) {
          relaysPlayed.answers[relay] = (stored, filters) async =>
              NostrRelayRead(
                events: FakeNoteRelays.matching(stored, filters),
                complete: false,
                label: 'timedOut',
              );
        }
        relaysPlayed
            .on(relays[3])
            .add(noteOf(internal0.key.recoveryNostrKeyPair, 8, at));
        await sync().beforeNewTrade(internal0);
        expect(
          await standingOf(internal0),
          const GarageNoteStanding(floor: 8, read: false),
        );
      },
    );

    test('the note of one key never moves the floor of another', () async {
      relaysPlayed
          .on(relays[0])
          .add(noteOf(internal0.key.recoveryNostrKeyPair, 30, at));
      final notesSync = sync();
      await notesSync.beforeNewTrade(internal0);
      await notesSync.beforeNewTrade(internal1);
      expect((await standingOf(internal0)).floor, 30);
      expect(
        await standingOf(internal1),
        const GarageNoteStanding(floor: null, read: true),
      );
      expect(await nextRobot(internal1, notesSync), 0);
      expect(await nextRobot(internal0, notesSync, coordinator: 1), 31);
    });
  });

  group('the floor of a new trade', () {
    test(
      'a new trade asked while the first reading runs waits for it, within its limit, then takes a robot above the note',
      () async {
        final release = Completer<void>();
        relaysPlayed.answers[relays[0]] = (stored, filters) async {
          await release.future;
          return NostrRelayRead(
            events: [noteOf(internal0.key.recoveryNostrKeyPair, 14, at)],
            complete: true,
            label: 'answered',
          );
        };
        final notesSync = sync();
        notesSync.visit(internal0);
        var reserved = false;
        final robot = nextRobot(internal0, notesSync).then((index) {
          reserved = true;
          return index;
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(reserved, isFalse);
        release.complete();
        expect(await robot, 15);
      },
    );

    test(
      'a first reading that does not end within the limit lets the trade go on without the floor, and the key stays unread',
      () async {
        relaysPlayed.answers[relays[0]] = (stored, filters) =>
            Completer<NostrRelayRead>().future;
        final notesSync = sync(newTradeWait: const Duration(milliseconds: 100));
        final waited = Stopwatch()..start();
        expect(await nextRobot(internal0, notesSync), 0);
        expect(waited.elapsed, lessThan(const Duration(seconds: 2)));
        expect((await standingOf(internal0)).read, isFalse);
      },
    );

    test(
      'the robot of a new trade is never at or below the note, nor one the device holds',
      () async {
        await bind(internal0, [0, 1, 9, 10]);
        relaysPlayed
            .on(relays[0])
            .add(noteOf(internal0.key.recoveryNostrKeyPair, 9, at));
        final notesSync = sync();
        expect(await nextRobot(internal0, notesSync), 11);
        expect(await nextRobot(internal0, notesSync, coordinator: 1), 12);
      },
    );

    test(
      'a note at the last index leaves the key no robot for a new trade',
      () async {
        relaysPlayed
            .on(relays[0])
            .add(
              noteOf(
                internal0.key.recoveryNostrKeyPair,
                GarageKey.maxAccountIndex,
                at,
              ),
            );
        final notesSync = sync();
        keys.selected = internal0;
        final robots = InterimTradeRobots(
          keys,
          records(),
          beforeNewTrade: notesSync.beforeNewTrade,
        );
        expect(
          await robots.robotForNewTrade(
            network,
            Federation.robosats.coordinators.first,
          ),
          isA<Err<ReservedRobot, P2pFailure>>(),
        );
      },
    );
  });

  group('writing', () {
    test(
      'a confirmed trade writes, on every relay of the network, the highest robot the device knows was used for its key, after reading it',
      () async {
        await bind(internal0, [3, 5]);
        final notesSync = sync();
        notesSync.tradeConfirmed(_record(fingerprintOf(internal0), 3));
        await _settled(relaysPlayed, relays.length);
        expect(relaysPlayed.published.map((p) => p.$1), relays);
        // Two trades in progress, robots 3 and 5: the note says 5, whichever trade was confirmed.
        expect(publishedIndexes(internal0), List.filled(relays.length, 5));
        // Read before written.
        expect(relaysPlayed.reads, hasLength(relays.length));
      },
    );

    test(
      'the note written never goes below the floor read, even when the device used lower robots only',
      () async {
        await bind(internal0, [0, 1]);
        relaysPlayed
            .on(relays[0])
            .add(noteOf(internal0.key.recoveryNostrKeyPair, 40, at));
        sync().opened(network);
        await _settled(relaysPlayed, relays.length);
        expect(publishedIndexes(internal0), List.filled(relays.length, 40));
      },
    );

    test(
      'the first opening after the update writes the note of every key with robots bound before it, once per run',
      () async {
        await bind(internal0, [0, 1, 2]);
        await bind(external, [4]);
        final notesSync = sync();
        notesSync.opened(network);
        await _settled(relaysPlayed, 2 * relays.length);
        expect(publishedIndexes(internal0), List.filled(relays.length, 2));
        expect(publishedIndexes(external), List.filled(relays.length, 4));
        expect(publishedIndexes(internal1), isEmpty);
        notesSync.opened(network);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(relaysPlayed.published, hasLength(2 * relays.length));
      },
    );

    test('nothing is written over a note the device could not read', () async {
      await bind(internal0, [0]);
      for (final relay in relays) {
        relaysPlayed.answers[relay] = (stored, filters) async =>
            const NostrRelayRead.none('unreachable');
      }
      final notesSync = sync();
      notesSync.tradeConfirmed(_record(fingerprintOf(internal0), 0));
      notesSync.opened(network);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(relaysPlayed.published, isEmpty);
    });
  });
}

/// A record of robot [index] of the key of [fingerprint], confirmed.
TradeRecord _record(GarageKeyFingerprint fingerprint, int index) => TradeRecord(
  robot: RobotSlot(RobosatsNetwork.mainnet, fingerprint, index),
  coordinatorAlias: Federation.robosats.coordinators.first.shortAlias,
  coordinatorOnion: 'temple.onion',
  orderId: 1,
  role: TradeRole.buyer,
  origin: TradeOrigin.takenHere,
  takenAt: DateTime.utc(2026, 11, 27),
  confirmedAt: DateTime.utc(2026, 11, 27),
  closedAt: null,
);

/// Waits until [relays] has [count] publications, or a second has passed.
Future<void> _settled(FakeNoteRelays relays, int count) async {
  final waited = Stopwatch()..start();
  while (relays.published.length < count &&
      waited.elapsed < const Duration(seconds: 2)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// The Garage Keys of the test: the key a new trade takes is [selected], and a robot's key is found by its fingerprint, as `GarageKeyRepositoryImpl.ofSlot` finds it.
final class _Keys with KeysFromRead implements GarageKeyRepository {
  final List<NetworkGarageKey> _keys;
  NetworkGarageKey? selected;

  _Keys(this._keys);

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> read(
    RobosatsNetwork network,
  ) async => switch (selected) {
    final key? => Ok(key),
    null => const Err(GarageKeyMissingFailure()),
  };

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> ofSlot(RobotSlot slot) async {
    for (final key in _keys) {
      if (key.fingerprint case Ok(
        :final value,
      ) when value == slot.keyFingerprint) {
        return Ok(key);
      }
    }
    return const Err(TradeKeyMissingFailure());
  }

  @override
  Future<Result<void, P2pFailure>> import(
    RobosatsNetwork network,
    GarageKey key,
  ) => throw UnimplementedError();

  @override
  Future<Result<bool, P2pFailure>> exists(RobosatsNetwork network) =>
      throw UnimplementedError();

  @override
  Future<Result<NetworkRobot, P2pFailure>> firstUsableRobot(
    RobosatsNetwork network,
  ) => throw UnimplementedError();
}
