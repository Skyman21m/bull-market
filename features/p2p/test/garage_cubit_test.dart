import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/p2p.dart' show P2pGarageKeyPort, P2pGarageKeyRefusalReason;
import 'package:p2p/src/data/garage_key_book_repository_impl.dart';
import 'package:p2p/src/data/garage_key_repository_impl.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/garage_opening.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/order_history.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/robot_binding_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/new_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/read_garage_key_usecase.dart';
import 'package:p2p/src/presentation/garage_cubit.dart';
import 'package:p2p/src/presentation/garage_state.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeySlot, Secrets;
import 'package:secrets/testing.dart';

import 'support/fakes.dart';
import 'support/garage_words.dart';
import 'support/key_output.dart';
import 'support/robot_bindings.dart';

/// The keystore of the tests, counting the writes and the deletes that reach it.
final class _CountingStorage extends FakeSecureStoragePlatform {
  int writes = 0;
  int deletes = 0;

  _CountingStorage({super.entries});

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) {
    writes++;
    return super.write(key: key, value: value, options: options);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) {
    deletes++;
    return super.delete(key: key, options: options);
  }
}

/// A stand-in for the wallet's re-authentication: it records, each time it is asked, whether the slot still held a key then, and answers [answer], or waits for [pending] when it is set.
final class _Gate {
  final FakeSecureStoragePlatform storage;
  final String entry;
  bool answer;
  Completer<bool>? pending;
  final List<bool> heldKeyWhenAsked = [];

  _Gate(this.storage, this.entry, {this.answer = true});

  int get asked => heldKeyWhenAsked.length;

  Future<bool> call() {
    heldKeyWhenAsked.add(storage.entries.containsKey(entry));
    return pending?.future ?? Future.value(answer);
  }
}

/// The Garage of one network over the real vault of `package:secrets`, on its in-memory keystore: empty, holding a key, corrupt, locked or unreadable, and the slot of the other network never touched.
///
/// The vault settles an empty slot with its full read budget, so each test that finds a slot empty waits about 4.5 s of real time.
void main() {
  const mainnetEntry = 'com.bullbitcoin.secrets/garage/p2p/mainnet';
  const testnetEntry = 'com.bullbitcoin.secrets/garage/p2p/testnet';
  const slow = Timeout(Duration(seconds: 120));

  // Fixed test bytes, 0x01 to 0x20: not a key anyone uses.
  final fixedKey = switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final fixedFingerprint = switch (GarageKeyFingerprint.of(fixedKey)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  final fixedRobot = switch (fixedKey.firstUsableRobot(0)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  // The example key of the RoboSats frontend tests and its first robot, as `packages/robosats` records them.
  final vector =
      (jsonDecode(
                File(
                  '../../packages/robosats/test/fixtures/robot-identity-vectors.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>)['garage_key']
          as Map<String, dynamic>;
  final exampleText = vector['garage_key'] as String;
  final exampleRobot =
      (vector['derived'] as List).first as Map<String, dynamic>;

  // The fixed key stored in each slot, the way the vault stores it.
  late Map<String, String> storedFixedKeys;

  GarageCubit cubitOver(
    FakeSecureStoragePlatform storage, {
    RobosatsNetwork network = RobosatsNetwork.testnet,
    P2pGarageKeyPort? words,
    Stream<Result<GarageRecords, P2pFailure>> Function(NetworkGarageKey key)?
    tradesOf,
    GarageNavigation? navigation,
    Future<void> Function(TradeRecord record)? readOnce,
  }) {
    storage.install();
    final vault = Secrets(scratchDirectory: () async => '.').garageKeys();
    final database = P2pDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    // The cubit's own tests: by default key 0 of the words is the fixed key the tests store in the slot of the network (`SlotAsWordsPort`).
    final repository = GarageKeyRepositoryImpl(
      vault,
      words ?? SlotAsWordsPort(vault),
      GarageKeyBookRepositoryImpl(database, clock: DateTime.now),
    );
    return GarageCubit(
      network,
      ReadGarageKeyUsecase(repository),
      NewGarageKeyUsecase(repository),
      ImportGarageKeyUsecase(
        repository,
        RobotBindingRepositoryImpl(database, clock: DateTime.now),
      ),
      tradesOf: tradesOf,
      navigation: navigation,
      readOnce: readOnce,
    );
  }

  FakeSecureStoragePlatform holding(
    Iterable<String> entries, {
    bool locked = false,
    List<Object?>? scripted,
    List<Object?>? scriptedWrites,
  }) => FakeSecureStoragePlatform(
    entries: {for (final entry in entries) entry: storedFixedKeys[entry] ?? ''},
    // A locked keystore refuses writes and deletes as well as reads.
    locked: locked,
    writesFail: locked,
    scripted: scripted,
    scriptedWrites: scriptedWrites,
  );

  /// The key stored in [slot], read through the vault itself: the test compares it, never shows it.
  Future<GarageKey?> storedIn(GarageKeySlot slot) async =>
      switch (await Secrets(
        scratchDirectory: () async => '.',
      ).garageKeys().read(slot: slot)) {
        Ok(:final value) => switch (GarageKey.fromBytes(
          Uint8List.fromList(value.bytes),
        )) {
          Ok(:final value) => value,
          Err() => null,
        },
        Err() => null,
      };

  setUpAll(() async {
    final storage = FakeSecureStoragePlatform()..install();
    final vault = Secrets(scratchDirectory: () async => '.').garageKeys();
    for (final slot in GarageKeySlot.values) {
      final result = await vault.import(
        slot: slot,
        bytes: fixedKey.revealBytes(),
      );
      expect(result, isA<Ok<Object?, Failure>>());
    }
    storedFixedKeys = Map.of(storage.entries);
  });

  test('touches nothing until it is loaded', () async {
    final storage = holding([testnetEntry]);
    final cubit = cubitOver(storage);

    expect(cubit.state, isA<GarageWorking>());
    expect(storage.reads, 0);
    expect(storage.readKeys, isEmpty);
    await cubit.close();
  });

  group('a stored key', () {
    test('goes to the profile, hidden, never as a new key', () async {
      final cubit = cubitOver(holding([testnetEntry]));

      await cubit.load();

      final state = cubit.state as GarageWithKey;
      expect(state.key.key, fixedKey);
      expect(state.robot.index, fixedRobot.accountIndex);
      expect(state.robot.nickname, fixedRobot.identity.nickname);
      expect('$state', 'GarageWithKey(testnet)');
      await cubit.close();
    });

    test('moves from robot to robot, and not below robot 0', () async {
      final cubit = cubitOver(holding([testnetEntry]));
      await cubit.load();

      cubit
        ..next()
        ..next();
      expect((cubit.state as GarageWithKey).robot.index, 2);
      cubit.previous();
      final state = cubit.state as GarageWithKey;
      expect(state.robot.index, 1);
      expect(state.robot.nickname, switch (fixedKey.deriveIdentity(1)) {
        Ok(:final value) => value.nickname,
        Err() => fail('no robot 1'),
      });
      cubit
        ..previous()
        ..previous();
      expect(
        cubit.state,
        isA<GarageWithKey>()
            .having((state) => state.robot.index, 'index', 0)
            .having(
              (state) => state.failure,
              'failure',
              isA<GarageRobotUnavailableFailure>(),
            ),
      );
      await cubit.close();
    });
  });

  test(
    'nothing printed or logged while the Garage is used holds a key',
    () async {
      final storage = FakeSecureStoragePlatform();
      final cubit = cubitOver(storage, words: TestWordsPort());
      final seen = <GarageKey>[];

      final output = await captureKeyOutput(() async {
        await cubit.load();
        seen.add((cubit.state as GarageWithKey).key.key);
        cubit
          ..next()
          ..previous();
        await cubit.newKey();
        seen.add((cubit.state as GarageWithKey).key.key);
        await cubit.previousKey();
        await cubit.nextKey();
        await cubit.import(exampleText);
        await cubit.import('${exampleText.substring(0, 20)}x');
      });

      expect(seen, hasLength(2));
      expect(seen.toSet(), hasLength(2));
      final example = switch (GarageKey.parse(exampleText)) {
        Ok(:final value) => value,
        Err() => fail('not a key'),
      };
      expectNoKeyIn(output, [...seen, example]);
      await cubit.close();
    },
    timeout: slow,
  );

  group(
    'the robot shown by the records, « Last order #N » and the hand (#227, #251)',
    () {
      final madeAt = DateTime.utc(2026, 11, 19, 9);

      TradeRecord recordOf(
        RobotSlot robot, {
        bool closed = true,
        TradeOrigin origin = TradeOrigin.madeHere,
      }) => TradeRecord(
        robot: robot,
        coordinatorAlias: 'temple',
        coordinatorOnion:
            Federation.robosats.byAlias('temple')?.testnet.onion ??
            (throw StateError('temple')),
        orderId: 4300 + robot.accountIndex,
        role: TradeRole.buyer,
        origin: origin,
        takenAt: madeAt.add(Duration(hours: robot.accountIndex)),
        confirmedAt: madeAt,
        closedAt: closed
            ? madeAt.add(Duration(days: 1, hours: robot.accountIndex))
            : null,
      );

      final otherFingerprint = switch (GarageKey.fromBytes(
        Uint8List.fromList(List<int>.generate(32, (i) => 64 - i)),
      )) {
        Ok(:final value) => switch (GarageKeyFingerprint.of(value)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        },
        Err(:final failure) => throw StateError('$failure'),
      };

      RobotSlot slot(
        int index, {
        RobosatsNetwork network = RobosatsNetwork.testnet,
        GarageKeyFingerprint? key,
      }) => RobotSlot(network, key ?? fixedFingerprint, index);

      int shown(GarageCubit cubit) =>
          (cubit.state as GarageWithKey).robot.index;

      /// Records with [locked] trades in progress whose bond is locked and [ended] finished ones, at their trail's last position, the newest end last; the fresh robot [fresh].
      Result<GarageRecords, P2pFailure> recordsOf({
        List<int> locked = const [],
        List<(int, TradePosition?)> ended = const [],
        int? fresh = 9,
        bool drawnHere = true,
        GarageKeyFingerprint? key,
      }) => Ok(
        GarageRecords(
          keyDrawnHereOnly: drawnHere,
          inProgress: [
            for (final index in locked)
              ActiveTrade(
                recordOf(slot(index, key: key), closed: false),
                const ActiveTradeAt(
                  TradePosition.chatting,
                  deadline: null,
                  breached: false,
                  historyUnknown: false,
                ),
              ),
          ],
          closed: [
            for (final (index, position) in ended)
              ClosedTrade(recordOf(slot(index, key: key)), position),
          ],
          fresh: fresh == null ? null : slot(fresh),
        ),
      );

      /// The records as the use case gives them: [start] first, what the Garage opens on, then what the test adds.
      ({
        StreamController<Result<GarageRecords, P2pFailure>> records,
        List<NetworkGarageKey> asked,
        Stream<Result<GarageRecords, P2pFailure>> Function(NetworkGarageKey key)
        follow,
      })
      recordsStarting(Result<GarageRecords, P2pFailure> start) {
        final records =
            StreamController<Result<GarageRecords, P2pFailure>>.broadcast();
        final asked = <NetworkGarageKey>[];
        return (
          records: records,
          asked: asked,
          follow: (key) {
            asked.add(key);
            scheduleMicrotask(() => records.add(start));
            return records.stream;
          },
        );
      }

      test(
        'opens on the robot of the newest trade in progress whose bond is locked, then moves to one seen locked later',
        () async {
          final trades = recordsStarting(recordsOf(locked: [3]));
          final cubit = cubitOver(
            holding([testnetEntry]),
            tradesOf: trades.follow,
          );
          await cubit.load();
          final state = cubit.state as GarageWithKey;
          expect(state.robot.index, 3);
          expect(state.robot.nickname, switch (fixedKey.deriveIdentity(3)) {
            Ok(:final value) => value.nickname,
            Err() => fail('no robot 3'),
          });
          expect(trades.asked, [state.key]);
          trades.records.add(recordsOf(locked: [3, 5]));
          await pumpEventQueue();
          expect(shown(cubit), 5);
          await cubit.close();
          expect(trades.records.hasListener, isFalse);
          await trades.records.close();
        },
      );

      test(
        'after a trade that served: the fresh robot; after an expiry: the robot of the trade, which it keeps',
        () async {
          final served = recordsStarting(
            recordsOf(ended: [(3, TradePosition.succeeded)]),
          );
          final cubit = cubitOver(
            holding([testnetEntry]),
            tradesOf: served.follow,
          );
          await cubit.load();
          expect(shown(cubit), 9);
          await cubit.close();
          await served.records.close();

          final expired = recordsStarting(
            recordsOf(ended: [(3, TradePosition.expired)]),
          );
          final again = cubitOver(
            holding([testnetEntry]),
            tradesOf: expired.follow,
          );
          await again.load();
          expect(shown(again), 3);
          expect((again.state as GarageWithKey).ordersNotServed, {
            ('temple', 4303),
          });
          await again.close();
          await expired.records.close();
        },
      );

      test(
        'a trade that ends served while the Garage is shown moves it to the fresh robot; one that expires does not',
        () async {
          final trades = recordsStarting(recordsOf(locked: [3]));
          final cubit = cubitOver(
            holding([testnetEntry]),
            tradesOf: trades.follow,
          );
          await cubit.load();
          expect(shown(cubit), 3);
          trades.records.add(recordsOf(ended: [(3, TradePosition.expired)]));
          await pumpEventQueue();
          expect(shown(cubit), 3);
          trades.records.add(
            recordsOf(
              ended: [(3, TradePosition.expired), (4, TradePosition.cancelled)],
            ),
          );
          await pumpEventQueue();
          expect(shown(cubit), 9);
          // Records that cannot be read move nothing.
          trades.records.add(const Err(P2pStorageFailure()));
          await pumpEventQueue();
          expect(shown(cubit), 9);
          await cubit.close();
          await trades.records.close();
        },
      );

      test(
        'opens on the first usable robot with no trade, or a trade of another key or network',
        () async {
          for (final start in [
            recordsOf(),
            recordsOf(locked: [3], key: otherFingerprint),
            recordsOf(
              ended: [(3, TradePosition.succeeded)],
              key: otherFingerprint,
            ),
            const Err<GarageRecords, P2pFailure>(P2pStorageFailure()),
          ]) {
            final trades = recordsStarting(start);
            final cubit = cubitOver(
              holding([testnetEntry]),
              tradesOf: trades.follow,
            );
            await cubit.load();
            expect(shown(cubit), 0, reason: '$start');
            await cubit.close();
            await trades.records.close();
          }
        },
      );

      test(
        'a key from elsewhere never moves: the robot of its line whatever its end',
        () async {
          final trades = recordsStarting(
            recordsOf(
              drawnHere: false,
              fresh: null,
              ended: [(3, TradePosition.succeeded)],
            ),
          );
          final cubit = cubitOver(
            holding([testnetEntry]),
            tradesOf: trades.follow,
          );
          await cubit.load();
          expect(shown(cubit), 3);
          await cubit.close();
          await trades.records.close();
        },
      );

      test(
        'the arrows leave it by hand: kept when the Garage is left and opened again, a read of the vault included, until a trade of the key ends at 14',
        () async {
          final navigation = GarageNavigation();
          final start = recordsOf(ended: [(3, TradePosition.succeeded)]);
          final trades = recordsStarting(start);
          final cubit = cubitOver(
            holding([testnetEntry]),
            tradesOf: trades.follow,
            navigation: navigation,
          );
          await cubit.load();
          expect(shown(cubit), 9);
          // « Previous account » down to the robot of the trade.
          for (var i = 0; i < 6; i++) {
            cubit.previous();
          }
          expect(shown(cubit), 3);
          expect(
            (cubit.state as GarageWithKey).ordersNotServed,
            isEmpty,
            reason: 'a trade served: the sentence is said',
          );
          // Records written again, the same trades: it stays.
          trades.records.add(start);
          await pumpEventQueue();
          expect(shown(cubit), 3);
          await cubit.load();
          expect(shown(cubit), 3);
          await cubit.close();
          await trades.records.close();

          // The Garage left and opened again: still there.
          final again = recordsStarting(start);
          final next = cubitOver(
            holding([testnetEntry]),
            tradesOf: again.follow,
            navigation: navigation,
          );
          await next.load();
          expect(shown(next), 3);
          // Another trade of the key ends at 14: the rule again.
          again.records.add(
            recordsOf(
              ended: [
                (3, TradePosition.succeeded),
                (5, TradePosition.succeeded),
              ],
            ),
          );
          await pumpEventQueue();
          expect(shown(next), 9);
          await next.close();
          await again.records.close();

          // A new run of the app: a new object, the rule.
          final restarted = recordsStarting(start);
          final fresh = cubitOver(
            holding([testnetEntry]),
            tradesOf: restarted.follow,
            navigation: GarageNavigation(),
          );
          await fresh.load();
          expect(shown(fresh), 9);
          await fresh.close();
          await restarted.records.close();
        },
      );

      test(
        'one following at a time: two reads of the vault at once leave none after the Garage is left (review of #229, R3)',
        () async {
          final trades = recordsStarting(recordsOf(locked: [3]));
          final cubit = cubitOver(
            holding([testnetEntry]),
            tradesOf: trades.follow,
          );
          unawaited(cubit.load());
          await cubit.load();
          await pumpEventQueue();
          expect(shown(cubit), 3);
          await cubit.close();
          expect(trades.records.hasListener, isFalse);
          await trades.records.close();
        },
      );

      test(
        'the vault read again while following, the key gone from it: nothing followed any more (review of #229, R6)',
        () async {
          final trades = recordsStarting(recordsOf(locked: [3]));
          final storage = holding([testnetEntry]);
          final cubit = cubitOver(storage, tradesOf: trades.follow);
          await cubit.load();
          expect(trades.records.hasListener, isTrue);
          storage.entries.remove(testnetEntry);
          await cubit.load();
          expect(cubit.state, isA<GarageWithoutKey>());
          expect(trades.records.hasListener, isFalse);
          await cubit.close();
          await trades.records.close();
        },
        timeout: slow,
      );

      test(
        'a tap on « Last order #N » shows that order\'s robot, which the rule does not replace; a trade seen locked after it does, as a trade ending at 14',
        () async {
          final trades = recordsStarting(
            recordsOf(locked: [3], ended: [(1, TradePosition.succeeded)]),
          );
          final cubit = cubitOver(
            holding([testnetEntry]),
            tradesOf: trades.follow,
          );
          await cubit.load();
          expect(shown(cubit), 3);
          cubit.showOrderRobot(recordOf(slot(1)));
          expect(shown(cubit), 1);
          trades.records.add(
            recordsOf(locked: [3], ended: [(1, TradePosition.succeeded)]),
          );
          await pumpEventQueue();
          expect(shown(cubit), 1);
          trades.records.add(
            recordsOf(locked: [3, 7], ended: [(1, TradePosition.succeeded)]),
          );
          await pumpEventQueue();
          expect(shown(cubit), 7);
          cubit.showOrderRobot(recordOf(slot(1)));
          expect(shown(cubit), 1);
          trades.records.add(
            recordsOf(
              locked: [7],
              ended: [
                (1, TradePosition.succeeded),
                (3, TradePosition.succeeded),
              ],
            ),
          );
          await pumpEventQueue();
          expect(shown(cubit), 7);
          await cubit.close();
          await trades.records.close();
        },
      );

      test(
        'a tap on an order of another Garage Key or network, or on the robot shown, changes nothing',
        () async {
          final cubit = cubitOver(holding([testnetEntry]));
          await cubit.load();
          cubit.previous();
          final before = cubit.state;
          expect((before as GarageWithKey).failure, isNotNull);
          for (final robot in [
            slot(2, key: otherFingerprint),
            slot(2, network: RobosatsNetwork.mainnet),
            slot(-1),
            slot(0),
          ]) {
            cubit.showOrderRobot(recordOf(robot));
            expect(cubit.state, same(before), reason: '$robot');
          }
          cubit.showOrderRobot(recordOf(slot(2)));
          expect(shown(cubit), 2);
          expect((cubit.state as GarageWithKey).failure, isNull);
          await cubit.close();
        },
      );

      test(
        'the orders of the robot shown that have not served follow the records',
        () async {
          final trades = recordsStarting(recordsOf(locked: [3], fresh: 4));
          final cubit = cubitOver(
            holding([testnetEntry]),
            tradesOf: trades.follow,
          );
          await cubit.load();
          expect((cubit.state as GarageWithKey).ordersNotServed, isEmpty);
          trades.records.add(
            recordsOf(ended: [(3, TradePosition.publicAgain)], fresh: 4),
          );
          await pumpEventQueue();
          expect(shown(cubit), 3);
          expect((cubit.state as GarageWithKey).ordersNotServed, {
            ('temple', 4303),
          });
          expect(OrderEnd.served(TradePosition.publicAgain), isFalse);
          await cubit.close();
          await trades.records.close();
        },
      );

      test(
        'step 0: the open record of the robot it opened on, read once per visit when its panel says no active order; never another robot, a key from elsewhere, nor twice',
        () async {
          final read = <int>[];
          Future<void> readOnce(TradeRecord record) async =>
              read.add(record.robot.accountIndex);

          final trades = recordsStarting(recordsOf(locked: [3]));
          final cubit = cubitOver(
            holding([testnetEntry]),
            tradesOf: trades.follow,
            readOnce: readOnce,
          );
          await cubit.load();
          expect(shown(cubit), 3);
          // Another robot's panel: nothing.
          cubit.robotWithoutActiveOrder(4);
          expect(read, isEmpty);
          cubit.robotWithoutActiveOrder(3);
          expect(read, [3]);
          // Once per visit, a read of the vault included.
          cubit.robotWithoutActiveOrder(3);
          await cubit.load();
          cubit.robotWithoutActiveOrder(3);
          expect(read, [3]);
          await cubit.close();
          await trades.records.close();

          // A robot shown by the arrows after the opening: nothing.
          final moved = recordsStarting(recordsOf(locked: [3, 5]));
          final byHand = cubitOver(
            holding([testnetEntry]),
            tradesOf: moved.follow,
            readOnce: readOnce,
          );
          await byHand.load();
          expect(shown(byHand), 5);
          byHand.previous();
          byHand.previous();
          expect(shown(byHand), 3);
          byHand.robotWithoutActiveOrder(3);
          expect(read, [3]);
          await byHand.close();
          await moved.records.close();

          // A key from elsewhere, a robot with no open record, records that cannot be read: nothing.
          for (final start in [
            recordsOf(
              drawnHere: false,
              fresh: null,
              // An open record of the robot it opens on, made here: only the guard on the key's history stops the read.
              locked: [3],
            ),
            recordsOf(ended: [(3, TradePosition.expired)]),
            const Err<GarageRecords, P2pFailure>(P2pStorageFailure()),
          ]) {
            final other = recordsStarting(start);
            final again = cubitOver(
              holding([testnetEntry]),
              tradesOf: other.follow,
              readOnce: readOnce,
            );
            await again.load();
            if (start case Ok(value: GarageRecords(keyDrawnHereOnly: false))) {
              expect(shown(again), 3);
            }
            again.robotWithoutActiveOrder(shown(again));
            expect(read, [3], reason: '$start');
            await again.close();
            await other.records.close();
          }
        },
      );
    },
  );

  group('the keys of the words (#81)', () {
    GarageWithKey shown(GarageCubit cubit) => cubit.state as GarageWithKey;

    test(
      'opens on key 0 at the first opening, with nothing to generate or back up',
      () async {
        final cubit = cubitOver(
          FakeSecureStoragePlatform(),
          words: TestWordsPort(),
        );
        await cubit.load();
        expect(shown(cubit).key.index, 0);
        expect(shown(cubit).highest, 0);
        expect(shown(cubit).key.key.revealBech32(), abandonTestnet0);
        expect(shown(cubit).isEarlierKey, isFalse);
        await cubit.close();
      },
    );

    test(
      '« › » never creates a key; « New key » does, from the highest key only',
      () async {
        final words = TestWordsPort();
        final cubit = cubitOver(FakeSecureStoragePlatform(), words: words);
        await cubit.load();
        await cubit.nextKey();
        expect(shown(cubit).key.index, 0);
        expect(words.asked.map((asked) => asked.$2), everyElement(0));
        await cubit.newKey();
        expect(shown(cubit).key.index, 1);
        expect(shown(cubit).highest, 1);
        expect(shown(cubit).robot.index, 0);
        await cubit.previousKey();
        expect(shown(cubit).key.index, 0);
        expect(shown(cubit).isEarlierKey, isTrue);
        // From an earlier key, « New key » does nothing.
        await cubit.newKey();
        expect(shown(cubit).highest, 1);
        expect(shown(cubit).key.index, 0);
        await cubit.previousKey();
        expect(shown(cubit).key.index, 0);
        await cubit.nextKey();
        expect(shown(cubit).key.index, 1);
        await cubit.nextKey();
        expect(shown(cubit).key.index, 1);
        expect(shown(cubit).highest, 1);
        await cubit.close();
      },
    );

    test('two taps on « New key » at once make one key', () async {
      final cubit = cubitOver(
        FakeSecureStoragePlatform(),
        words: TestWordsPort(),
      );
      await cubit.load();
      await Future.wait([cubit.newKey(), cubit.newKey()]);
      expect(shown(cubit).highest, 1);
      await cubit.close();
    });

    test('the robots shown change with the key', () async {
      final cubit = cubitOver(
        FakeSecureStoragePlatform(),
        words: TestWordsPort(),
      );
      await cubit.load();
      final first = shown(cubit).robot;
      await cubit.newKey();
      expect(shown(cubit).robot.hashId, isNot(first.hashId));
      await cubit.previousKey();
      expect(shown(cubit).robot, first);
      await cubit.close();
    });

    test('words that cannot give a key show why, and draw none', () async {
      final storage = FakeSecureStoragePlatform();
      final cubit = cubitOver(
        storage,
        words: TestWordsPort(
          refusal: P2pGarageKeyRefusalReason.noDefaultWallet,
        ),
      );
      await cubit.load();
      expect(
        cubit.state,
        isA<GarageUnknown>().having(
          (state) => state.failure,
          'failure',
          isA<GarageKeyNoWalletFailure>(),
        ),
      );
      expect(storage.entries, isEmpty);
      await cubit.close();
    });
  });
}
