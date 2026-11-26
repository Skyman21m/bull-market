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
import 'package:p2p/src/domain/usecases/delete_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/import_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/needs_pin_to_delete_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/new_garage_key_usecase.dart';
import 'package:p2p/src/domain/usecases/read_garage_key_usecase.dart';
import 'package:p2p/src/presentation/garage_cubit.dart';
import 'package:p2p/src/presentation/garage_state.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeySlot, Secrets;
import 'package:secrets/testing.dart';

import 'migrations_test/p2p_database/generated/schema_v9.dart' as v9;
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
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
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
    RobotBindingRepository? bindings,
    File? databaseFile,
  }) {
    storage.install();
    final vault = Secrets(scratchDirectory: () async => '.').garageKeys();
    final database = P2pDatabase.forTesting(
      databaseFile == null
          ? NativeDatabase.memory()
          : NativeDatabase(databaseFile),
    );
    addTearDown(database.close);
    final recorded =
        bindings ?? RobotBindingRepositoryImpl(database, clock: DateTime.now);
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
      ImportGarageKeyUsecase(repository, recorded),
      DeleteGarageKeyUsecase(repository),
      NeedsPinToDeleteGarageKeyUsecase(recorded),
      tradesOf: tradesOf,
      navigation: navigation,
      readOnce: readOnce,
    );
  }

  /// The re-authentication of a delete that must not ask it: a key drawn here, with no robot bound.
  Future<bool> neverAsked() async => fail('the PIN was asked');

  GarageWithKey shown(GarageCubit cubit) => cubit.state as GarageWithKey;

  /// A file of schema 9 with nothing in it: the book an update finds, which the step to schema 10 gives « Your Garage Keys » due.
  Future<File> schema9File() async {
    final directory = await Directory.systemTemp.createTemp(
      'p2p-garage-cubit-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/nine.sqlite');
    final nine = v9.DatabaseAtV9(NativeDatabase(file));
    await nine.customSelect('SELECT 1').get();
    await nine.close();
    return file;
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

  /// The internal Garage Keys of the public test words, derived once and then given from memory, so that a test's keystore holds nothing but its Garage Key entries.
  late TestWordsPort memoryWords;

  setUpAll(() async {
    memoryWords = TestWordsPort();
    FakeSecureStoragePlatform().install();
    await memoryWords.precompute([
      for (final network in RobosatsNetwork.values)
        for (var index = 0; index < 4; index++) (network, index),
    ]);
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
        GarageKeyFingerprint? key,
      }) => Ok(
        GarageRecords(
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
        'with no fresh robot left, the robot of its line stays whatever its end (every key alike since 2026-11-26, #81)',
        () async {
          final trades = recordsStarting(
            recordsOf(fresh: null, ended: [(3, TradePosition.succeeded)]),
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
        'the keys read again while following, the key no longer given: nothing followed any more (review of #229, R6)',
        () async {
          final trades = recordsStarting(recordsOf(locked: [3]));
          final storage = holding([testnetEntry]);
          final cubit = cubitOver(storage, tradesOf: trades.follow);
          await cubit.load();
          expect(trades.records.hasListener, isTrue);
          // Key 0 of the words is the key of the slot here: gone from it, the words no longer give it.
          storage.entries.remove(testnetEntry);
          await cubit.load();
          expect(cubit.state, isA<GarageUnknown>());
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

          // A robot with no open record, records that cannot be read: nothing. Where the key comes from no longer counts (decided on 2026-11-26, #81).
          for (final start in [
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
        await cubit.close();
      },
    );

    test(
      '« › » never creates a key; the arrows select a key, kept across a new cubit; « New key » creates the key after the highest from any key',
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
        expect(shown(cubit).highest, 1);
        await cubit.previousKey();
        expect(shown(cubit).key.index, 0);
        await cubit.nextKey();
        expect(shown(cubit).key.index, 1);
        await cubit.nextKey();
        expect(shown(cubit).key.index, 1);
        expect(shown(cubit).highest, 1);
        // From key 0, « New key » creates key 2, the one after the highest, and selects it.
        await cubit.previousKey();
        await cubit.newKey();
        expect(shown(cubit).key.index, 2);
        expect(shown(cubit).highest, 2);
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

  group('the external Garage Key (#81, the mock-up decided on 2026-11-26)', () {
    test(
      'the key the vault kept is selected at the first opening after the update with « Your Garage Keys » due; the arrows never reach it, a button does, and « Back » returns to the last internal key shown',
      () async {
        final file = await schema9File();
        final cubit = cubitOver(
          holding([testnetEntry]),
          words: memoryWords,
          databaseFile: file,
        );
        await cubit.load();
        expect(shown(cubit).isExternal, isTrue);
        expect(shown(cubit).key.key, fixedKey);
        expect(shown(cubit).hasExternal, isTrue);
        expect(shown(cubit).externalKey, fixedFingerprint);
        expect(shown(cubit).externalNoticeDue, isTrue);
        // No arrows and no « New internal Garage Key » on the external Garage Key.
        await cubit.nextKey();
        await cubit.previousKey();
        await cubit.newKey();
        expect(shown(cubit).isExternal, isTrue);
        expect(shown(cubit).highest, 0);
        // « Back to internal Garage Keys »: none shown yet, so the highest, key 0.
        await cubit.returnToInternal();
        expect(shown(cubit).key.index, 0);
        expect(shown(cubit).key.key.revealBech32(), abandonTestnet0);
        await cubit.newKey();
        await cubit.newKey();
        await cubit.previousKey();
        expect(shown(cubit).key.index, 1);
        // « › » stops at the highest internal key, never at the external one.
        await cubit.nextKey();
        await cubit.nextKey();
        expect(shown(cubit).key.index, 2);
        await cubit.previousKey();
        await cubit.switchToExternal();
        expect(shown(cubit).isExternal, isTrue);
        await cubit.returnToInternal();
        expect(shown(cubit).key.index, 1);
        await cubit.switchToExternal();
        await cubit.close();
        // Kept across a restart: the external key, then key 1.
        final again = cubitOver(
          holding([testnetEntry]),
          words: memoryWords,
          databaseFile: file,
        );
        await again.load();
        expect(shown(again).isExternal, isTrue);
        await again.returnToInternal();
        expect(shown(again).key.index, 1);
        await again.close();
      },
      timeout: slow,
    );

    test(
      '« Your Garage Keys » is shown once: the state forgets it at once, and the keys read again, or a new cubit, never bring it back',
      () async {
        final file = await schema9File();
        final cubit = cubitOver(
          holding([testnetEntry]),
          words: memoryWords,
          databaseFile: file,
        );
        await cubit.load();
        expect(shown(cubit).externalNoticeDue, isTrue);
        await cubit.externalNoticeShown();
        expect(shown(cubit).externalNoticeDue, isFalse);
        await cubit.load();
        expect(shown(cubit).externalNoticeDue, isFalse);
        await cubit.returnToInternal();
        await cubit.switchToExternal();
        expect(shown(cubit).externalNoticeDue, isFalse);
        await cubit.close();
        final again = cubitOver(
          holding([testnetEntry]),
          words: memoryWords,
          databaseFile: file,
        );
        await again.load();
        expect(shown(again).externalNoticeDue, isFalse);
        await again.close();
        // A new install: never due, even with a key in the vault.
        final kept = cubitOver(holding([testnetEntry]), words: memoryWords);
        await kept.load();
        expect(shown(kept).isExternal, isTrue);
        expect(shown(kept).externalNoticeDue, isFalse);
        await kept.close();
        final fresh = cubitOver(
          FakeSecureStoragePlatform(),
          words: memoryWords,
        );
        await fresh.load();
        expect(shown(fresh).externalNoticeDue, isFalse);
        expect(await fresh.import(exampleText), isNull);
        expect(shown(fresh).isExternal, isTrue);
        expect(shown(fresh).externalNoticeDue, isFalse);
        await fresh.close();
      },
      timeout: slow,
    );

    test(
      'a key imported becomes the external key, selected; a text that is not a key, or an internal key, is given back and changes nothing',
      () async {
        final storage = FakeSecureStoragePlatform();
        final cubit = cubitOver(storage, words: memoryWords);
        await cubit.load();
        expect(shown(cubit).hasExternal, isFalse);
        expect(
          await cubit.import('${exampleText.substring(0, 20)}x'),
          isA<GarageKeyInvalidFailure>(),
        );
        expect(
          await cubit.import(abandonTestnet0),
          isA<GarageKeyIsInternalFailure>().having(
            (failure) => failure.index,
            'index',
            0,
          ),
        );
        expect(shown(cubit).key.index, 0);
        expect(storage.entries, isNot(contains(testnetEntry)));
        expect(await cubit.import(exampleText), isNull);
        expect(shown(cubit).isExternal, isTrue);
        expect(shown(cubit).key.key.revealBech32(), exampleText);
        // One at a time: a second import is not even tried.
        expect(await cubit.import(exampleText), isNull);
        await cubit.close();
      },
      timeout: slow,
    );

    test(
      'deleting the external key asks the PIN when its robots may live on a coordinator, deletes only it, then shows the last internal key shown',
      () async {
        final storage = FakeSecureStoragePlatform();
        final cubit = cubitOver(storage, words: memoryWords);
        await cubit.load();
        await cubit.newKey();
        await cubit.previousKey();
        expect(shown(cubit).key.index, 0);
        expect(await cubit.import(exampleText), isNull);
        // Without the re-authentication, a key from elsewhere is not deleted.
        await cubit.delete(reauthenticate: null);
        expect(shown(cubit).isExternal, isTrue);
        expect(shown(cubit).deletionNeedsPin, isTrue);
        expect(storage.entries, contains(testnetEntry));
        // A PIN left deletes nothing.
        await cubit.delete(reauthenticate: () async => false);
        expect(storage.entries, contains(testnetEntry));
        var asked = 0;
        await cubit.delete(
          reauthenticate: () async {
            asked++;
            return true;
          },
        );
        expect(asked, 1);
        expect(storage.entries, isNot(contains(testnetEntry)));
        // Back on key 0, the last internal key shown, not on key 1, the highest.
        expect(shown(cubit).key.index, 0);
        expect(shown(cubit).hasExternal, isFalse);
        // An internal key is never deleted.
        await cubit.delete(reauthenticate: () async => true);
        expect(shown(cubit).key.index, 0);
        await cubit.close();
      },
      timeout: slow,
    );

    test(
      'the trades in progress of the network come with the state: those of another key than the one shown, and those of the key shown',
      () async {
        final otherKey = switch (GarageKey.fromBytes(
          Uint8List.fromList(List<int>.generate(32, (i) => i + 2)),
        )) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        final other = switch (GarageKeyFingerprint.of(otherKey)) {
          Ok(:final value) => value,
          Err(:final failure) => throw StateError('$failure'),
        };
        TradeRecord recordOf(GarageKeyFingerprint key, int index, int order) =>
            TradeRecord(
              robot: RobotSlot(RobosatsNetwork.testnet, key, index),
              coordinatorAlias: 'temple',
              coordinatorOnion: 'http://temple.onion',
              orderId: order,
              role: TradeRole.buyer,
              origin: TradeOrigin.takenHere,
              takenAt: DateTime.utc(2026, 11, 26),
              confirmedAt: DateTime.utc(2026, 11, 26),
              closedAt: null,
            );
        final mine = recordOf(fixedFingerprint, 3, 48120);
        final elsewhere = recordOf(other, 1, 48121);
        ActiveTrade active(TradeRecord record) => ActiveTrade(
          record,
          const ActiveTradeAt(
            TradePosition.chatting,
            deadline: null,
            breached: false,
            historyUnknown: false,
          ),
        );
        final records =
            StreamController<Result<GarageRecords, P2pFailure>>.broadcast();
        final cubit = cubitOver(
          holding([testnetEntry]),
          words: memoryWords,
          tradesOf: (_) {
            scheduleMicrotask(
              () => records.add(
                Ok(
                  GarageRecords(
                    inProgress: [active(mine), active(elsewhere)],
                    closed: const [],
                    fresh: null,
                  ),
                ),
              ),
            );
            return records.stream;
          },
        );
        await cubit.load();
        expect(shown(cubit).isExternal, isTrue);
        expect(shown(cubit).inProgressOfKeyShown, [mine]);
        expect(shown(cubit).inProgressElsewhere, [elsewhere]);
        // A trade that ends leaves the lines at the next records.
        records.add(
          Ok(
            GarageRecords(
              inProgress: [active(mine)],
              closed: const [],
              fresh: null,
            ),
          ),
        );
        await pumpEventQueue();
        expect(shown(cubit).inProgressElsewhere, isEmpty);
        await cubit.close();
        await records.close();
      },
      timeout: slow,
    );

    for (final reason in P2pGarageKeyRefusalReason.values) {
      test(
        'words that refuse (${reason.name}): the external key stays shown and usable; the internal side says why, with the way back (C-passphrase)',
        () async {
          final storage = holding([testnetEntry]);
          final cubit = cubitOver(
            storage,
            words: TestWordsPort(refusal: reason),
          );
          await cubit.load();
          expect(shown(cubit).isExternal, isTrue);
          expect(shown(cubit).key.key, fixedKey);
          expect(shown(cubit).highest, isNull);
          await cubit.returnToInternal();
          expect(
            cubit.state,
            isA<GarageUnknown>()
                .having((state) => state.canSwitchToExternal, 'switch', isTrue)
                .having((state) => state.externalSelected, 'external', isFalse),
          );
          // « Retry » on the internal side asks again, and says why again.
          await cubit.returnToInternal();
          expect(
            cubit.state,
            isA<GarageUnknown>().having(
              (state) => state.canSwitchToExternal,
              'switch',
              isTrue,
            ),
          );
          await cubit.switchToExternal();
          expect(shown(cubit).isExternal, isTrue);
          // Its delete stays (the PIN, a key of unknown history).
          await cubit.delete(reauthenticate: () async => true);
          expect(storage.entries, isNot(contains(testnetEntry)));
          // Without it: the refusal alone, as before.
          expect(
            cubit.state,
            isA<GarageUnknown>().having(
              (state) => state.canSwitchToExternal,
              'switch',
              isFalse,
            ),
          );
          await cubit.close();
        },
        timeout: slow,
      );
    }
  });

  // Restored from `main` for the external Garage Key (review of #292): the other network, a slot the vault cannot read, and the PIN before a delete. The delete of `main` led to the welcome screen, gone with #81: here it leads back to the internal Garage Keys; « Generate new », gone with #81, has no test any more.
  group('the other network', () {
    test('is never read, written or deleted', () async {
      final storage = holding([testnetEntry]);
      final cubit = cubitOver(
        storage,
        network: RobosatsNetwork.mainnet,
        words: memoryWords,
      );

      await cubit.load();
      expect(cubit.state, isA<GarageWithKey>());
      await cubit.delete(reauthenticate: neverAsked);
      await cubit.switchToExternal();

      expect(storage.readKeys.toSet(), {mainnetEntry});
      expect(storage.entries[testnetEntry], storedFixedKeys[testnetEntry]);
      expect(storage.entries.containsKey(mainnetEntry), isFalse);
      await cubit.close();
    }, timeout: slow);
  });

  group('a slot the vault cannot read', () {
    test(
      'that is corrupt offers only retry, the way back and delete',
      () async {
        final storage = FakeSecureStoragePlatform(
          entries: {testnetEntry: 'not json at all'},
        );
        final cubit = cubitOver(storage, words: memoryWords);

        await cubit.load();
        expect(
          cubit.state,
          isA<GarageUnknown>()
              .having(
                (state) => state.failure,
                'failure',
                isA<GarageKeyUnusableFailure>(),
              )
              .having((state) => state.externalSelected, 'external', isTrue),
        );
        await cubit.import(exampleText);
        expect(storage.entries, {testnetEntry: 'not json at all'});

        // A slot that cannot be read always asks the PIN.
        var asked = 0;
        await cubit.delete(
          reauthenticate: () async {
            asked++;
            return true;
          },
        );
        expect(asked, 1);
        expect(shown(cubit).key.index, 0);
        expect(storage.entries, isEmpty);
        await cubit.close();
      },
    );

    test('that keeps failing to read is unreadable', () async {
      final storage = holding([
        testnetEntry,
      ], scripted: List.generate(5, (_) => PlatformException(code: 'read')));
      final cubit = cubitOver(storage, words: memoryWords);

      await cubit.load();

      expect(
        cubit.state,
        isA<GarageUnknown>().having(
          (state) => state.failure,
          'failure',
          isA<GarageKeyUnreadableFailure>(),
        ),
      );
      expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
      await cubit.close();
    }, timeout: slow);

    test(
      'that is locked is said so, and nothing is written or deleted',
      () async {
        final storage = holding([testnetEntry], locked: true);
        final cubit = cubitOver(storage, words: memoryWords);

        await cubit.load();
        // The screens offer no delete then; the cubit asks the PIN, and the vault refuses.
        await cubit.delete(reauthenticate: () async => true);

        expect(
          cubit.state,
          isA<GarageUnknown>()
              .having(
                (state) => state.failure,
                'failure',
                isA<GarageKeyLockedFailure>(),
              )
              .having(
                (state) => state.actionFailure,
                'actionFailure',
                isA<GarageKeyLockedFailure>(),
              ),
        );
        expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
        await cubit.close();
      },
    );
  });

  group('the PIN before a delete', () {
    // Another key's fingerprint: fixed test bytes, 0x02 to 0x21.
    final otherFingerprint = switch (GarageKey.fromBytes(
      Uint8List.fromList(List<int>.generate(32, (i) => i + 2)),
    )) {
      Ok(:final value) => switch (GarageKeyFingerprint.of(value)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      },
      Err(:final failure) => throw StateError('$failure'),
    };
    CoordinatorIdentity identityOf(String alias, RobosatsNetwork network) =>
        switch (CoordinatorIdentity.of(coordinator(alias), network)) {
          final identity? => identity,
          null => throw StateError('$alias is not on $network'),
        };
    final passes = isA<Ok<void, P2pFailure>>();

    late RobotBindingRepositoryImpl bindings;

    setUp(() => bindings = bindingsInMemory());

    /// Records the fixed key as drawn here on [network], then binds its robot [index] to temple there.
    Future<void> bindFixedRobot(
      RobosatsNetwork network, {
      int index = 0,
    }) async {
      expect(
        await bindings.recordGeneratedKey(network, fixedFingerprint),
        passes,
      );
      expect(
        await bindings.bind(
          RobotSlot(network, fixedFingerprint, index),
          identityOf('temple', network),
        ),
        passes,
      );
    }

    /// Loads the Garage of the testnet slot holding the fixed key, the external Garage Key, over the bindings in memory.
    Future<(GarageCubit, _CountingStorage)> loaded({
      RobotBindingRepository? over,
    }) async {
      final storage = _CountingStorage(
        entries: {testnetEntry: storedFixedKeys[testnetEntry] ?? ''},
      );
      final cubit = cubitOver(
        storage,
        words: memoryWords,
        bindings: over ?? bindings,
      );
      await cubit.load();
      expect(shown(cubit).isExternal, isTrue);
      return (cubit, storage);
    }

    Matcher shows({required bool needsPin}) => isA<GarageWithKey>().having(
      (state) => state.deletionNeedsPin,
      'deletionNeedsPin',
      needsPin,
    );

    Matcher backOnInternal() => isA<GarageWithKey>()
        .having((state) => state.key.index, 'index', 0)
        .having((state) => state.hasExternal, 'hasExternal', isFalse);

    test(
      'a key drawn here, with no robot bound, is deleted on the confirmation alone',
      () async {
        expect(
          await bindings.recordGeneratedKey(
            RobosatsNetwork.testnet,
            fixedFingerprint,
          ),
          passes,
        );
        // A robot of another key is bound: not this key's.
        expect(
          await bindings.recordGeneratedKey(
            RobosatsNetwork.testnet,
            otherFingerprint,
          ),
          passes,
        );
        expect(
          await bindings.bind(
            RobotSlot(RobosatsNetwork.testnet, otherFingerprint, 0),
            identityOf('temple', RobosatsNetwork.testnet),
          ),
          passes,
        );
        final (cubit, storage) = await loaded();
        await cubit.delete(reauthenticate: neverAsked);

        expect(cubit.state, backOnInternal());
        expect(storage.entries, isEmpty);
        await cubit.close();
      },
    );

    for (final (rule, prepare) in <(String, Future<void> Function())>[
      (
        'a robot bound on its network',
        () => bindFixedRobot(RobosatsNetwork.testnet, index: 5),
      ),
      (
        'a robot bound on the other network',
        () async {
          expect(
            await bindings.recordGeneratedKey(
              RobosatsNetwork.testnet,
              fixedFingerprint,
            ),
            passes,
          );
          await bindFixedRobot(RobosatsNetwork.mainnet);
        },
      ),
      (
        'an imported key',
        () async => expect(
          await bindings.recordImportedKey(
            RobosatsNetwork.testnet,
            fixedFingerprint,
          ),
          passes,
        ),
      ),
      ('a key never recorded, as one drawn before the records', () async {}),
    ]) {
      test(
        '$rule: the PIN after the confirmation, before anything is deleted',
        () async {
          await prepare();
          final (cubit, storage) = await loaded();
          final gate = _Gate(storage, testnetEntry);

          await cubit.delete(reauthenticate: gate.call);

          // Asked once, while the key was still stored.
          expect(gate.heldKeyWhenAsked, [true]);
          expect(storage.deletes, 1);
          expect(cubit.state, backOnInternal());
          expect(storage.entries, isEmpty);
          await cubit.close();
        },
      );
    }

    group('a slot that cannot be read', () {
      Future<(GarageCubit, _CountingStorage)> unreadable() async {
        final storage = _CountingStorage(
          entries: {testnetEntry: 'not json at all'},
        );
        final cubit = cubitOver(
          storage,
          words: memoryWords,
          bindings: bindings,
        );
        await cubit.load();
        expect(cubit.state, isA<GarageUnknown>());
        return (cubit, storage);
      }

      test(
        'with no robot of any key bound, nor any history: the PIN all the same',
        () async {
          final (cubit, storage) = await unreadable();
          final gate = _Gate(storage, testnetEntry, answer: false);

          await cubit.delete(reauthenticate: gate.call);
          expect(gate.heldKeyWhenAsked, [true]);
          expect(storage.deletes, 0);
          expect(cubit.state, isA<GarageUnknown>());

          await cubit.delete(reauthenticate: null);
          expect(storage.deletes, 0);

          gate.answer = true;
          await cubit.delete(reauthenticate: gate.call);
          expect(gate.asked, 2);
          expect(storage.entries, isEmpty);
          expect(cubit.state, backOnInternal());
          await cubit.close();
        },
      );

      test('with a robot of any key bound: the PIN', () async {
        expect(
          await bindings.recordGeneratedKey(
            RobosatsNetwork.mainnet,
            otherFingerprint,
          ),
          passes,
        );
        expect(
          await bindings.bind(
            RobotSlot(RobosatsNetwork.mainnet, otherFingerprint, 1),
            identityOf('lake', RobosatsNetwork.mainnet),
          ),
          passes,
        );
        final (cubit, storage) = await unreadable();
        final gate = _Gate(storage, testnetEntry);

        await cubit.delete(reauthenticate: gate.call);
        expect(gate.heldKeyWhenAsked, [true]);
        expect(storage.entries, isEmpty);
        await cubit.close();
      });

      test(
        '« Retry » while its delete asks the PIN reads nothing, and the PIN decides',
        () async {
          // An intact key, imported, that the keystore fails to read for a while: no robot of any key is bound.
          expect(
            await bindings.recordImportedKey(
              RobosatsNetwork.testnet,
              fixedFingerprint,
            ),
            passes,
          );
          final storage = _CountingStorage(
            entries: {testnetEntry: storedFixedKeys[testnetEntry] ?? ''},
          );
          storage.scripted.addAll(
            List.generate(5, (_) => PlatformException(code: 'read')),
          );
          final cubit = cubitOver(
            storage,
            words: memoryWords,
            bindings: bindings,
          );
          await cubit.load();
          expect(cubit.state, isA<GarageUnknown>());
          final gate = _Gate(storage, testnetEntry, answer: false)
            ..pending = Completer();

          final deleting = cubit.delete(reauthenticate: gate.call);
          await pumpEventQueue();
          expect(gate.asked, 1);
          // The user taps « Retry »: the keystore has recovered, but the delete under way is not swapped for another key.
          final reads = storage.reads;
          await cubit.load();
          expect(storage.reads, reads);
          expect(cubit.state, isA<GarageUnknown>());
          gate.pending?.complete(false);
          await deleting;

          expect(storage.deletes, 0);
          expect(storage.entries, {
            testnetEntry: storedFixedKeys[testnetEntry],
          });
          // Once the delete is over, « Retry » reads the key, which asks the PIN as imported.
          await cubit.load();
          expect(
            cubit.state,
            isA<GarageWithKey>().having(
              (state) => state.deletionNeedsPin,
              'deletionNeedsPin',
              isTrue,
            ),
          );
          await cubit.close();
        },
        timeout: slow,
      );
    });

    test(
      'a database that cannot be read: the PIN, and none without the gate',
      () async {
        final broken = RecordingBindings()
          ..readFailure = const P2pStorageFailure();
        final (cubit, storage) = await loaded(over: broken);
        expect(cubit.state, shows(needsPin: true));

        await cubit.delete(reauthenticate: null);
        expect(storage.deletes, 0);
        expect(cubit.state, shows(needsPin: true));

        final gate = _Gate(storage, testnetEntry);
        await cubit.delete(reauthenticate: gate.call);
        expect(gate.asked, 1);
        expect(storage.entries, isEmpty);
        await cubit.close();
      },
    );

    test(
      'without the gate, nothing is deleted, and the screen stays',
      () async {
        await bindFixedRobot(RobosatsNetwork.testnet);
        final (cubit, storage) = await loaded();
        cubit.next();
        final before = cubit.state;
        final reads = storage.reads;

        await cubit.delete(reauthenticate: null);

        expect(cubit.state, isA<GarageWithKey>());
        expect(shown(cubit).robot, (before as GarageWithKey).robot);
        expect(storage.deletes, 0);
        expect(storage.reads, reads);
        expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
        await cubit.close();
      },
    );

    test(
      'a PIN the user leaves deletes nothing and leaves the screen as it was',
      () async {
        await bindFixedRobot(RobosatsNetwork.testnet);
        final (cubit, storage) = await loaded();
        cubit
          ..next()
          ..next();
        final reads = storage.reads;
        final gate = _Gate(storage, testnetEntry, answer: false);

        await cubit.delete(reauthenticate: gate.call);

        expect(gate.asked, 1);
        expect(shown(cubit).robot.index, 2);
        expect(shown(cubit).isExternal, isTrue);
        expect(storage.deletes, 0);
        expect(storage.writes, 0);
        expect(storage.reads, reads);
        await cubit.close();
      },
    );

    test(
      'decides from the database when the user deletes, not when the key was read',
      () async {
        expect(
          await bindings.recordGeneratedKey(
            RobosatsNetwork.testnet,
            fixedFingerprint,
          ),
          passes,
        );
        final (cubit, storage) = await loaded();
        // A robot of the key is bound while the Garage shows it.
        expect(
          await bindings.bind(
            RobotSlot(RobosatsNetwork.testnet, fixedFingerprint, 0),
            identityOf('temple', RobosatsNetwork.testnet),
          ),
          passes,
        );

        await cubit.delete(reauthenticate: null);
        expect(storage.deletes, 0);
        // The state now says so, which greys the delete without the gate.
        expect(cubit.state, shows(needsPin: true));

        final gate = _Gate(storage, testnetEntry);
        await cubit.delete(reauthenticate: gate.call);
        expect(gate.asked, 1);
        expect(storage.entries, isEmpty);
        await cubit.close();
      },
    );

    test('a second tap while the PIN is asked is ignored', () async {
      await bindFixedRobot(RobosatsNetwork.testnet);
      final (cubit, storage) = await loaded();
      final gate = _Gate(storage, testnetEntry)..pending = Completer();

      final first = cubit.delete(reauthenticate: gate.call);
      // Lets the first tap read the database and open the PIN.
      await pumpEventQueue();
      expect(gate.asked, 1);
      final second = cubit.delete(reauthenticate: gate.call);
      final third = cubit.returnToInternal();
      await pumpEventQueue();
      gate.pending?.complete(true);
      await Future.wait([first, second, third]);

      expect(gate.asked, 1);
      expect(storage.deletes, 1);
      expect(storage.writes, 0);
      expect(cubit.state, backOnInternal());
      await cubit.close();
    });

    test(
      'a cubit closed while the database is read for a delete asks nothing and deletes nothing',
      () async {
        final slowReads = RecordingBindings(
          drawnHere: [(RobosatsNetwork.testnet, fixedFingerprint)],
        );
        final (cubit, storage) = await loaded(over: slowReads);
        final reading = Completer<void>();
        final started = Completer<void>();
        slowReads
          ..readsWait = reading.future
          ..onRead = () {
            if (!started.isCompleted) started.complete();
          }
          // The read now says the key has a robot bound: the PIN would be asked.
          ..exposure = const GarageKeyExposure(
            history: GarageKeyHistory.drawnHere,
            hasBinding: true,
          );
        final gate = _Gate(storage, testnetEntry);

        final deleting = cubit.delete(reauthenticate: gate.call);
        await started.future;
        await cubit.close();
        reading.complete();
        await deleting;

        expect(gate.asked, 0);
        expect(storage.deletes, 0);
        expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
      },
    );

    test('a cubit closed while the PIN is asked deletes nothing', () async {
      await bindFixedRobot(RobosatsNetwork.testnet);
      final (cubit, storage) = await loaded();
      final gate = _Gate(storage, testnetEntry)..pending = Completer();

      final deleting = cubit.delete(reauthenticate: gate.call);
      await pumpEventQueue();
      await cubit.close();
      gate.pending?.complete(true);
      await deleting;

      expect(gate.asked, 1);
      expect(storage.deletes, 0);
      expect(storage.entries, {testnetEntry: storedFixedKeys[testnetEntry]});
    });

    test(
      'the key deleted: its records followed no more (review of #229, R4), and where it was left by hand forgotten',
      () async {
        // A key drawn here, with no robot bound: deleted on the confirmation alone.
        expect(
          await bindings.recordGeneratedKey(
            RobosatsNetwork.testnet,
            fixedFingerprint,
          ),
          passes,
        );
        final navigation = GarageNavigation();
        final records =
            StreamController<Result<GarageRecords, P2pFailure>>.broadcast();
        final asked = <NetworkGarageKey>[];
        final cubit = cubitOver(
          _CountingStorage(
            entries: {testnetEntry: storedFixedKeys[testnetEntry] ?? ''},
          ),
          words: memoryWords,
          bindings: bindings,
          navigation: navigation,
          tradesOf: (key) {
            asked.add(key);
            scheduleMicrotask(
              () => records.add(
                Ok(
                  GarageRecords(
                    inProgress: const [],
                    closed: const [],
                    fresh: null,
                  ),
                ),
              ),
            );
            return records.stream;
          },
        );
        await cubit.load();
        cubit.next();
        final key = shown(cubit).key;
        expect(key.isExternalForTest, isTrue);
        expect(navigation.leftByHand(key), isNotNull);
        await cubit.delete(reauthenticate: neverAsked);
        expect(cubit.state, backOnInternal());
        // Only the internal key is followed now.
        expect(asked.last.index, 0);
        expect(navigation.leftByHand(key), isNull);
        await cubit.close();
        await records.close();
      },
      timeout: slow,
    );
  });
}

extension on NetworkGarageKey {
  bool get isExternalForTest => index == null;
}
