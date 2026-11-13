import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/robot_bindings.dart';
import 'support/two_connections.dart';

/// The trade records of the robots in the feature's database: one record per robot, ever, written before the take's request, never deleted, and changed only from pending to taken or closed, from taken to closed.
void main() {
  const testnet = RobosatsNetwork.testnet;
  const mainnet = RobosatsNetwork.mainnet;

  // Fixed test bytes: not keys anyone uses.
  GarageKeyFingerprint fingerprintOf(int first) => switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => first + i)),
  )) {
    Ok(value: final key) => switch (GarageKeyFingerprint.of(key)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    },
    Err(:final failure) => throw StateError('$failure'),
  };
  final fingerprintA = fingerprintOf(1);
  final fingerprintB = fingerprintOf(2);

  CoordinatorIdentity identityOf(String alias, RobosatsNetwork network) =>
      switch (CoordinatorIdentity.of(coordinator(alias), network)) {
        final identity? => identity,
        null => throw StateError('$alias is not on $network'),
      };
  final temple = identityOf('temple', testnet);
  final lake = identityOf('lake', testnet);
  final templeMainnet = identityOf('temple', mainnet);

  Matcher refusedWith<T>() => isA<Err<Object?, P2pFailure>>().having(
    (err) => err.failure,
    'failure',
    isA<T>(),
  );
  Matcher reservedIs(bool bound) => isA<Ok<TradeReservation?, P2pFailure>>()
      .having((ok) => ok.value != null, 'bound', bound);
  TradeRecord valueOf(Result<TradeRecord, P2pFailure> result) =>
      switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
  Matcher recordOf(Object matcher) => isA<Ok<TradeRecord, P2pFailure>>().having(
    (ok) => ok.value,
    'record',
    matcher,
  );

  late DateTime now;
  late P2pDatabase database;
  late RobotBindingRepositoryImpl bindings;
  late TradeRecordRepositoryImpl trades;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    now = testNow;
    database = P2pDatabase.forTesting(NativeDatabase.memory());
    bindings = bindingsInMemory(database: database, clock: () => now);
    trades = TradeRecordRepositoryImpl(database, clock: () => now);
  });

  tearDown(() => database.close());

  Future<List<TradeRow>> tradeRows() => database.select(database.trades).get();
  Future<List<RobotBindingRow>> bindingRows() =>
      database.select(database.robotBindings).get();

  /// The reservation of a robot of key A on testnet for a new trade on [on].
  Future<TradeReservation> reserved(
    int index, [
    CoordinatorIdentity? on,
  ]) async {
    expect(await bindings.recordGeneratedKey(testnet, fingerprintA), isA<Ok>());
    final robot = RobotSlot(testnet, fingerprintA, index);
    return switch (await trades.reserveForNewTrade(robot, on ?? temple)) {
      Ok(value: final reservation?) => reservation,
      final other => fail('not reserved: $other'),
    };
  }

  /// The pending take of order [orderId] by the robot of [reservation].
  Future<TradeRecord> pendingTake(
    TradeReservation reservation, {
    int orderId = 7,
  }) async => switch (await trades.recordPendingTake(
    reservation,
    orderId: orderId,
    role: TradeRole.buyer,
  )) {
    Ok(:final value) => value,
    Err(:final failure) => fail('$failure'),
  };

  group('the reservation of a robot for a new trade', () {
    test(
      'binds a robot of a key drawn here to the coordinator, as drawn here, and says it did',
      () async {
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintA),
          isA<Ok>(),
        );

        expect(
          await trades.reserveForNewTrade(
            RobotSlot(testnet, fingerprintA, 4),
            temple,
          ),
          reservedIs(true),
        );

        expect(
          await bindings.standingOf(RobotSlot(testnet, fingerprintA, 4)),
          isA<Ok<RobotStanding, P2pFailure>>().having(
            (ok) => ok.value.binding,
            'binding',
            RobotBinding(temple, testNow, BindingProvenance.drawnHere),
          ),
        );
        expect(await tradeRows(), isEmpty);
      },
    );

    test(
      'never binds an index already bound, to any coordinator and on either network, and writes nothing',
      () async {
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintA),
          isA<Ok>(),
        );
        expect(
          await bindings.recordGeneratedKey(mainnet, fingerprintA),
          isA<Ok>(),
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
          isA<Ok>(),
        );
        expect(
          await bindings.bind(
            RobotSlot(mainnet, fingerprintA, 1),
            templeMainnet,
          ),
          isA<Ok>(),
        );
        expect(
          await trades.reserveForNewTrade(
            RobotSlot(testnet, fingerprintA, 2),
            temple,
          ),
          reservedIs(true),
        );
        final before = await bindingRows();

        for (final (index, coordinator) in [
          (0, temple),
          (0, lake),
          (1, temple),
          (2, temple),
          (2, lake),
        ]) {
          expect(
            await trades.reserveForNewTrade(
              RobotSlot(testnet, fingerprintA, index),
              coordinator,
            ),
            reservedIs(false),
            reason: '$index ${coordinator.alias}',
          );
        }
        expect(await bindingRows(), before);
      },
    );

    test(
      'never binds a robot of a key from elsewhere, on its network or the other one',
      () async {
        final robot = RobotSlot(testnet, fingerprintA, 0);
        // Not recorded at all.
        expect(
          await trades.reserveForNewTrade(robot, temple),
          reservedIs(false),
        );
        // Imported, then acknowledged, on its network.
        expect(
          await bindings.recordImportedKey(testnet, fingerprintA),
          isA<Ok>(),
        );
        expect(
          await trades.reserveForNewTrade(robot, temple),
          reservedIs(false),
        );
        expect(
          await bindings.recordAcknowledgedKey(testnet, fingerprintA),
          isA<Ok>(),
        );
        expect(
          await trades.reserveForNewTrade(robot, temple),
          reservedIs(false),
        );
        // Drawn here on its network, but pasted into the other slot, then acknowledged there: the same tokens may have travelled.
        final other = RobotSlot(testnet, fingerprintB, 0);
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintB),
          isA<Ok>(),
        );
        for (final record in [
          () => bindings.recordImportedKey(mainnet, fingerprintB),
          () => bindings.recordAcknowledgedKey(mainnet, fingerprintB),
        ]) {
          expect(await record(), isA<Ok>());
          expect(
            await trades.reserveForNewTrade(other, temple),
            reservedIs(false),
          );
        }
        expect(await bindingRows(), isEmpty);
        // The Garage's own binding of an acknowledged key still works: only new trades refuse it.
        expect(await bindings.bind(robot, temple), isA<Ok>());
      },
    );

    test(
      'a coordinator of another network than the robot\'s is refused',
      () async {
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintA),
          isA<Ok>(),
        );

        expect(
          await trades.reserveForNewTrade(
            RobotSlot(testnet, fingerprintA, 0),
            templeMainnet,
          ),
          refusedWith<RobotNotForNewTradeFailure>(),
        );
        expect(await bindingRows(), isEmpty);
      },
    );

    test(
      'never binds an index that has a trade record, even one whose binding is missing',
      () async {
        // A file whose foreign keys were not enforced when it was written: the reservation reads the records itself.
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintA),
          isA<Ok>(),
        );
        await database.customStatement('PRAGMA foreign_keys = OFF');
        await database.customInsert(
          "INSERT INTO trades VALUES ('testnet', ?, 3, 'temple', ?, 9, 'buyer', 'takenHere', 0, NULL, NULL)",
          variables: [
            Variable.withString(fingerprintA.hex),
            Variable.withString(temple.onion),
          ],
        );

        expect(
          await trades.reserveForNewTrade(
            RobotSlot(testnet, fingerprintA, 3),
            temple,
          ),
          reservedIs(false),
        );
        expect(await bindingRows(), isEmpty);
      },
    );
  });

  group('what a new trade may use of a key', () {
    Future<NewTradeStanding> standing(
      RobosatsNetwork network,
      GarageKeyFingerprint key,
    ) async => switch (await trades.newTradeStandingOf(network, key)) {
      Ok(:final value) => value,
      Err(:final failure) => fail('$failure'),
    };

    test(
      'a key is for new trades only when drawn here and nothing else anywhere',
      () async {
        expect(
          (await standing(testnet, fingerprintA)).keyDrawnHereOnly,
          isFalse,
        );
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintA),
          isA<Ok>(),
        );
        expect(
          (await standing(testnet, fingerprintA)).keyDrawnHereOnly,
          isTrue,
        );
        // Not on the other network, where it was not drawn.
        expect(
          (await standing(mainnet, fingerprintA)).keyDrawnHereOnly,
          isFalse,
        );
        expect(
          await bindings.recordGeneratedKey(mainnet, fingerprintA),
          isA<Ok>(),
        );
        expect(
          (await standing(mainnet, fingerprintA)).keyDrawnHereOnly,
          isTrue,
        );
        expect(
          await bindings.recordImportedKey(mainnet, fingerprintA),
          isA<Ok>(),
        );
        expect(
          (await standing(testnet, fingerprintA)).keyDrawnHereOnly,
          isFalse,
        );
        expect(
          (await standing(mainnet, fingerprintA)).keyDrawnHereOnly,
          isFalse,
        );
        expect(
          await bindings.recordAcknowledgedKey(mainnet, fingerprintA),
          isA<Ok>(),
        );
        expect(
          (await standing(testnet, fingerprintA)).keyDrawnHereOnly,
          isFalse,
        );
        // Another key's record does not count.
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintB),
          isA<Ok>(),
        );
        expect(
          (await standing(testnet, fingerprintB)).keyDrawnHereOnly,
          isTrue,
        );
      },
    );

    test(
      'the indexes in use are those bound on either network and those with a record, of that key only',
      () async {
        expect((await standing(testnet, fingerprintA)).indexesInUse, isEmpty);
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintA),
          isA<Ok>(),
        );
        expect(
          await bindings.recordGeneratedKey(mainnet, fingerprintA),
          isA<Ok>(),
        );
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintB),
          isA<Ok>(),
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 5), temple),
          isA<Ok>(),
        );
        expect(
          await bindings.bind(
            RobotSlot(mainnet, fingerprintA, 12),
            templeMainnet,
          ),
          isA<Ok>(),
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintB, 1), temple),
          isA<Ok>(),
        );
        await pendingTake(await reserved(0));

        expect((await standing(testnet, fingerprintA)).indexesInUse, {
          0,
          5,
          12,
        });
        expect((await standing(mainnet, fingerprintA)).indexesInUse, {
          0,
          5,
          12,
        });
        expect((await standing(testnet, fingerprintB)).indexesInUse, {1});
      },
    );

    test('a single index in use is read as well', () async {
      await reserved(9);

      expect((await standing(testnet, fingerprintA)).indexesInUse, {9});
    });

    test('reading writes nothing', () async {
      await standing(testnet, fingerprintA);

      expect(await bindingRows(), isEmpty);
      expect(await tradeRows(), isEmpty);
      expect(await database.select(database.garageKeyHistories).get(), isEmpty);
    });
  });

  group('a pending take', () {
    test(
      'is written for a robot reserved for a new trade, its network and coordinator copied from the binding',
      () async {
        final reservation = await reserved(2);
        final robot = reservation.robot;
        expect(reservation, TradeReservation(robot, temple));
        expect(reservation.network, testnet);
        now = testNow.add(const Duration(minutes: 1));

        final written = await trades.recordPendingTake(
          reservation,
          orderId: 1234,
          role: TradeRole.seller,
        );

        final expected = TradeRecord(
          robot: robot,
          coordinatorAlias: 'temple',
          coordinatorOnion: temple.onion,
          orderId: 1234,
          role: TradeRole.seller,
          origin: TradeOrigin.takenHere,
          takenAt: now,
          confirmedAt: null,
          closedAt: null,
        );
        expect(written, recordOf(expected));
        expect(expected.isPendingTake, isTrue);
        expect(expected.isActive, isTrue);
        expect(expected.network, testnet);
        final row = (await tradeRows()).single;
        expect(
          (
            row.network,
            row.keyFingerprint,
            row.robotIndex,
            row.coordinatorAlias,
            row.coordinatorOnion,
            row.orderId,
            row.role,
            row.origin,
            row.takenAt,
            row.confirmedAt,
            row.closedAt,
          ),
          (
            'testnet',
            fingerprintA.hex,
            2,
            'temple',
            temple.onion,
            1234,
            'seller',
            'takenHere',
            now.millisecondsSinceEpoch,
            null,
            null,
          ),
        );
      },
    );

    test('a robot has one record, ever, whatever the order', () async {
      final reservation = await reserved(0);
      final first = await pendingTake(reservation);

      // The same reservation used again.
      for (final orderId in [7, 8]) {
        expect(
          await trades.recordPendingTake(
            reservation,
            orderId: orderId,
            role: TradeRole.buyer,
          ),
          refusedWith<TradeAlreadyRecordedFailure>(),
        );
      }
      // Closed, it is still its robot's one record.
      expect(await trades.closeTrade(first), isA<Ok>());
      expect(
        await trades.recordPendingTake(
          reservation,
          orderId: 9,
          role: TradeRole.buyer,
        ),
        refusedWith<TradeAlreadyRecordedFailure>(),
      );
      expect(
        await trades.recordRecoveredTrade(
          reservation.robot,
          temple,
          orderId: 9,
          role: TradeRole.buyer,
        ),
        refusedWith<TradeAlreadyRecordedFailure>(),
      );
      expect(await tradeRows(), hasLength(1));
    });

    test(
      'a reservation the repository did not give is still checked by the statement, and nothing is written',
      () async {
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintA),
          isA<Ok>(),
        );
        expect(
          await bindings.recordGeneratedKey(mainnet, fingerprintA),
          isA<Ok>(),
        );
        expect(
          await bindings.recordImportedKey(testnet, fingerprintB),
          isA<Ok>(),
        );
        expect(
          await bindings.recordAcknowledgedKey(testnet, fingerprintB),
          isA<Ok>(),
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 1), lake),
          isA<Ok>(),
        );
        expect(
          await bindings.bind(
            RobotSlot(mainnet, fingerprintA, 2),
            templeMainnet,
          ),
          isA<Ok>(),
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintB, 0), temple),
          isA<Ok>(),
        );
        final changedTemple = CoordinatorIdentity(
          network: testnet,
          alias: 'temple',
          onion: temple.onion,
          nodeKeys: const ['another'],
          nostrKey: temple.nostrKey,
        );

        for (final (label, robot, coordinator, matcher) in [
          (
            'no binding',
            RobotSlot(testnet, fingerprintA, 0),
            temple,
            refusedWith<RobotNotForNewTradeFailure>(),
          ),
          (
            'bound to another coordinator',
            RobotSlot(testnet, fingerprintA, 1),
            temple,
            refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
          ),
          (
            'bound to a coordinator that changed',
            RobotSlot(testnet, fingerprintA, 1),
            CoordinatorIdentity(
              network: testnet,
              alias: 'lake',
              onion: lake.onion,
              nodeKeys: const ['another'],
              nostrKey: lake.nostrKey,
            ),
            refusedWith<RobotCoordinatorChangedFailure>(),
          ),
          (
            'bound on the other network',
            RobotSlot(testnet, fingerprintA, 2),
            temple,
            refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
          ),
          (
            'a coordinator of the other network',
            RobotSlot(testnet, fingerprintA, 1),
            templeMainnet,
            refusedWith<RobotNotForNewTradeFailure>(),
          ),
          (
            'bound under an acknowledged key',
            RobotSlot(testnet, fingerprintB, 0),
            temple,
            refusedWith<RobotNotForNewTradeFailure>(),
          ),
          (
            'a changed coordinator, unbound robot',
            RobotSlot(testnet, fingerprintA, 0),
            changedTemple,
            refusedWith<RobotNotForNewTradeFailure>(),
          ),
        ]) {
          // Only the repository makes a reservation in the feature (`trade_record_test.dart`): a test makes these by hand, as a bug or a lost file could make the statement see them.
          expect(
            await trades.recordPendingTake(
              TradeReservation(robot, coordinator),
              orderId: 5,
              role: TradeRole.buyer,
            ),
            matcher,
            reason: label,
          );
        }
        expect(await tradeRows(), isEmpty);
      },
    );
  });

  group('a recovered trade', () {
    test(
      'is written confirmed at once, for a robot of any provenance bound to that coordinator',
      () async {
        expect(
          await bindings.recordImportedKey(testnet, fingerprintB),
          isA<Ok>(),
        );
        expect(
          await bindings.recordAcknowledgedKey(testnet, fingerprintB),
          isA<Ok>(),
        );
        final pasted = RobotSlot(testnet, fingerprintB, 3);
        expect(await bindings.bind(pasted, temple), isA<Ok>());
        final drawn = (await reserved(1, lake)).robot;

        for (final (robot, coordinator) in [(pasted, temple), (drawn, lake)]) {
          expect(
            await trades.recordRecoveredTrade(
              robot,
              coordinator,
              orderId: 77,
              role: TradeRole.seller,
            ),
            recordOf(
              TradeRecord(
                robot: robot,
                coordinatorAlias: coordinator.alias,
                coordinatorOnion: coordinator.onion,
                orderId: 77,
                role: TradeRole.seller,
                origin: TradeOrigin.recovered,
                takenAt: testNow,
                confirmedAt: testNow,
                closedAt: null,
              ),
            ),
          );
        }
        expect(
          (await tradeRows()).map((row) => row.origin),
          everyElement('recovered'),
        );
      },
    );

    test(
      'is refused for a robot without a binding, or bound elsewhere',
      () async {
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintA),
          isA<Ok>(),
        );
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 1), lake),
          isA<Ok>(),
        );

        expect(
          await trades.recordRecoveredTrade(
            RobotSlot(testnet, fingerprintA, 0),
            temple,
            orderId: 1,
            role: TradeRole.buyer,
          ),
          refusedWith<RobotNotBoundFailure>(),
        );
        expect(
          await trades.recordRecoveredTrade(
            RobotSlot(testnet, fingerprintA, 1),
            temple,
            orderId: 1,
            role: TradeRole.buyer,
          ),
          refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
        );
        expect(
          await trades.recordRecoveredTrade(
            RobotSlot(testnet, fingerprintA, 1),
            templeMainnet,
            orderId: 1,
            role: TradeRole.buyer,
          ),
          refusedWith<RobotBoundToAnotherCoordinatorFailure>(),
        );
        // A pending take of the robot is its record: a recovery confirms it, it does not add one.
        final reservation = await reserved(2);
        await pendingTake(reservation);
        expect(
          await trades.recordRecoveredTrade(
            reservation.robot,
            temple,
            orderId: 7,
            role: TradeRole.buyer,
          ),
          refusedWith<TradeAlreadyRecordedFailure>(),
        );
        expect((await tradeRows()).map((row) => row.origin), ['takenHere']);
      },
    );
  });

  group('the state of a record', () {
    final later = testNow.add(const Duration(minutes: 2));
    final latest = testNow.add(const Duration(minutes: 5));

    test(
      'a pending take is confirmed once, and confirming again changes nothing',
      () async {
        final pending = await pendingTake(await reserved(0));
        now = later;

        final taken = await trades.confirmTake(pending);
        expect(
          taken,
          recordOf(
            isA<TradeRecord>()
                .having((r) => r.confirmedAt, 'confirmedAt', later)
                .having((r) => r.closedAt, 'closedAt', isNull)
                .having((r) => r.isPendingTake, 'isPendingTake', isFalse)
                .having((r) => r.isActive, 'isActive', isTrue),
          ),
        );
        now = latest;
        // Again, from the pending record or the taken one: the first confirmation stays.
        for (final record in [pending, valueOf(taken)]) {
          expect(await trades.confirmTake(record), recordOf(valueOf(taken)));
        }
      },
    );

    test(
      'a pending take that did not happen is closed, and never turns taken',
      () async {
        final pending = await pendingTake(await reserved(0));
        now = later;

        final closed = await trades.closeTrade(pending);
        expect(
          closed,
          recordOf(
            isA<TradeRecord>()
                .having((r) => r.confirmedAt, 'confirmedAt', isNull)
                .having((r) => r.closedAt, 'closedAt', later)
                .having((r) => r.isActive, 'isActive', isFalse),
          ),
        );
        now = latest;
        expect(
          await trades.confirmTake(pending),
          refusedWith<TradeClosedFailure>(),
        );
        expect(await trades.closeTrade(pending), recordOf(valueOf(closed)));
        final row = (await tradeRows()).single;
        expect(
          (row.confirmedAt, row.closedAt),
          (null, later.millisecondsSinceEpoch),
        );
      },
    );

    test(
      'a taken trade is closed once, and a closed record never changes',
      () async {
        final pending = await pendingTake(await reserved(0));
        now = later;
        final taken = switch (await trades.confirmTake(pending)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        now = latest;

        final closed = await trades.closeTrade(taken);
        expect(
          closed,
          recordOf(
            isA<TradeRecord>()
                .having((r) => r.confirmedAt, 'confirmedAt', later)
                .having((r) => r.closedAt, 'closedAt', latest),
          ),
        );
        now = latest.add(const Duration(hours: 1));
        for (final record in [pending, taken]) {
          expect(await trades.closeTrade(record), recordOf(valueOf(closed)));
          expect(
            await trades.confirmTake(record),
            refusedWith<TradeClosedFailure>(),
          );
        }
        final row = (await tradeRows()).single;
        expect(
          (row.confirmedAt, row.closedAt),
          (later.millisecondsSinceEpoch, latest.millisecondsSinceEpoch),
        );
      },
    );

    test('a recovered trade is closed as a taken one', () async {
      expect(
        await bindings.recordGeneratedKey(testnet, fingerprintA),
        isA<Ok>(),
      );
      expect(
        await bindings.bind(RobotSlot(testnet, fingerprintA, 0), temple),
        isA<Ok>(),
      );
      final recovered = switch (await trades.recordRecoveredTrade(
        RobotSlot(testnet, fingerprintA, 0),
        temple,
        orderId: 3,
        role: TradeRole.buyer,
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      now = later;

      expect(await trades.confirmTake(recovered), recordOf(recovered));
      expect(
        await trades.closeTrade(recovered),
        recordOf(
          isA<TradeRecord>()
              .having((r) => r.origin, 'origin', TradeOrigin.recovered)
              .having((r) => r.closedAt, 'closedAt', later),
        ),
      );
    });

    test(
      'a record the database does not hold, or not as given, is a storage failure, and nothing changes',
      () async {
        final pending = await pendingTake(await reserved(0), orderId: 7);
        TradeRecord like({
          RobotSlot? robot,
          int? orderId,
          TradeOrigin? origin,
        }) => TradeRecord(
          robot: robot ?? pending.robot,
          coordinatorAlias: pending.coordinatorAlias,
          coordinatorOnion: pending.coordinatorOnion,
          orderId: orderId ?? pending.orderId,
          role: pending.role,
          origin: origin ?? pending.origin,
          takenAt: pending.takenAt,
          confirmedAt: null,
          closedAt: null,
        );

        for (final (label, record) in [
          ('another robot', like(robot: RobotSlot(testnet, fingerprintA, 1))),
          ('another key', like(robot: RobotSlot(testnet, fingerprintB, 0))),
          ('another order', like(orderId: 8)),
          ('another network', like(robot: RobotSlot(mainnet, fingerprintA, 0))),
          ('another origin', like(origin: TradeOrigin.recovered)),
        ]) {
          expect(
            await trades.confirmTake(record),
            refusedWith<P2pStorageFailure>(),
            reason: label,
          );
          expect(
            await trades.closeTrade(record),
            refusedWith<P2pStorageFailure>(),
            reason: label,
          );
        }
        final row = (await tradeRows()).single;
        expect((row.confirmedAt, row.closedAt), (null, null));
      },
    );

    test(
      'a confirmation and a close at once leave one state that the statements allow',
      () async {
        for (var index = 0; index < 10; index++) {
          final pending = await pendingTake(await reserved(index));
          final results = await Future.wait([
            trades.confirmTake(pending),
            trades.closeTrade(pending),
          ]);
          expect(results.last, isA<Ok>());
        }
        for (final row in await tradeRows()) {
          expect(row.closedAt, isNotNull);
        }
      },
    );
  });

  group('the database itself', () {
    // The connection runs in its own isolate, and the error it sends back carries SQLite's code.
    Matcher sqliteError(int code) => throwsA(
      predicate((error) => '$error'.contains('SqliteException($code)')),
    );

    Future<void> insertTrade(
      String values,
      List<Variable<Object>> variables,
    ) => database.customInsert(
      'INSERT INTO trades (network, key_fingerprint, robot_index, coordinator_alias, coordinator_onion, order_id, role, origin, taken_at, confirmed_at, closed_at) VALUES $values',
      variables: variables,
    );

    test('enforces its foreign keys on every connection', () async {
      expect(
        (await database.customSelect('PRAGMA foreign_keys').getSingle())
            .data
            .values
            .single,
        1,
      );
    });

    test(
      'refuses a record of a robot without a binding, a second record of a robot, and values no version writes',
      () async {
        await pendingTake(await reserved(0));
        final key = Variable.withString(fingerprintA.hex);
        final onion = Variable.withString(temple.onion);

        // 787: a foreign key; 1555: the primary key; 275: a CHECK.
        for (final (label, values, code) in [
          (
            'no binding',
            "('testnet', ?, 1, 'temple', ?, 5, 'buyer', 'takenHere', 0, NULL, NULL)",
            787,
          ),
          (
            'second record',
            "('testnet', ?, 0, 'temple', ?, 6, 'buyer', 'takenHere', 0, NULL, NULL)",
            1555,
          ),
        ]) {
          await expectLater(
            insertTrade(values, [key, onion]),
            sqliteError(code),
            reason: label,
          );
        }
        // Each CHECK, on a robot bound and free of records, so that only the CHECK can refuse it.
        expect(
          await bindings.bind(RobotSlot(testnet, fingerprintA, 1), temple),
          isA<Ok>(),
        );
        for (final (label, values) in [
          (
            'recovered and pending',
            "('testnet', ?, 1, 'temple', ?, 6, 'buyer', 'recovered', 0, NULL, NULL)",
          ),
          (
            'origin',
            "('testnet', ?, 1, 'temple', ?, 6, 'buyer', 'elsewhere', 0, NULL, NULL)",
          ),
          (
            'role',
            "('testnet', ?, 1, 'temple', ?, 6, 'maker', 'takenHere', 0, NULL, NULL)",
          ),
          (
            'network',
            "('signet', ?, 1, 'temple', ?, 6, 'buyer', 'takenHere', 0, NULL, NULL)",
          ),
          (
            'order id',
            "('testnet', ?, 1, 'temple', ?, 0, 'buyer', 'takenHere', 0, NULL, NULL)",
          ),
          (
            'alias',
            "('testnet', ?, 1, '', ?, 6, 'buyer', 'takenHere', 0, NULL, NULL)",
          ),
        ]) {
          await expectLater(
            insertTrade(values, [key, onion]),
            sqliteError(275),
            reason: label,
          );
        }
        // The same values with a recorded origin pass: the CHECKs refused what they name.
        await insertTrade(
          "('testnet', ?, 1, 'temple', ?, 6, 'buyer', 'recovered', 0, 0, NULL)",
          [key, onion],
        );
        expect(await tradeRows(), hasLength(2));
      },
    );

    test('a binding that has a trade cannot be deleted, even by hand', () async {
      await pendingTake(await reserved(0));

      await expectLater(
        database.customStatement(
          "DELETE FROM robot_bindings WHERE key_fingerprint = '${fingerprintA.hex}'",
        ),
        sqliteError(787),
      );
      expect(await bindingRows(), hasLength(1));
    });

    test(
      'a record only gains its two times, once each, and is never deleted, even by hand',
      () async {
        // 1811: a trigger refused it (`trades.drift`).
        final pending = await pendingTake(await reserved(0));
        final where = "WHERE key_fingerprint = '${fingerprintA.hex}'";
        for (final (label, statement) in [
          ('a delete', 'DELETE FROM trades $where'),
          ('another order', 'UPDATE trades SET order_id = 8 $where'),
          ('another side', "UPDATE trades SET role = 'seller' $where"),
          (
            'another origin',
            "UPDATE trades SET origin = 'recovered', confirmed_at = 1 $where",
          ),
          ('another time of the take', 'UPDATE trades SET taken_at = 1 $where'),
          (
            'another coordinator',
            "UPDATE trades SET coordinator_alias = 'lake' $where",
          ),
        ]) {
          await expectLater(
            database.customStatement(statement),
            sqliteError(1811),
            reason: label,
          );
        }
        // Confirmed once: never cleared nor moved.
        expect(await trades.confirmTake(pending), isA<Ok>());
        for (final statement in [
          'UPDATE trades SET confirmed_at = NULL $where',
          'UPDATE trades SET confirmed_at = 5 $where',
        ]) {
          await expectLater(
            database.customStatement(statement),
            sqliteError(1811),
            reason: statement,
          );
        }
        // Closed: nothing changes any more, not even the close.
        expect(await trades.closeTrade(pending), isA<Ok>());
        for (final statement in [
          'UPDATE trades SET closed_at = NULL $where',
          'UPDATE trades SET closed_at = 5 $where',
          'UPDATE trades SET confirmed_at = 5 $where',
        ]) {
          await expectLater(
            database.customStatement(statement),
            sqliteError(1811),
            reason: statement,
          );
        }
        final row = (await tradeRows()).single;
        expect((row.orderId, row.role, row.origin), (7, 'buyer', 'takenHere'));
        expect(row.closedAt, isNotNull);
      },
    );

    test(
      'a record is on its binding\'s network, with a lowercase fingerprint and times from the epoch',
      () async {
        await reserved(0);
        final key = Variable.withString(fingerprintA.hex);
        final onion = Variable.withString(temple.onion);

        // The robot is bound on testnet: a mainnet record of it has no parent key (review of #102, R8).
        await expectLater(
          insertTrade(
            "('mainnet', ?, 0, 'temple', ?, 5, 'buyer', 'takenHere', 0, NULL, NULL)",
            [key, onion],
          ),
          sqliteError(787),
        );
        for (final (label, values, variables) in [
          (
            'a fingerprint in capitals',
            "('testnet', ?, 0, 'temple', ?, 5, 'buyer', 'takenHere', 0, NULL, NULL)",
            [Variable.withString(fingerprintA.hex.toUpperCase()), onion],
          ),
          (
            'a take before the epoch',
            "('testnet', ?, 0, 'temple', ?, 5, 'buyer', 'takenHere', -1, NULL, NULL)",
            [key, onion],
          ),
          (
            'a confirmation before the epoch',
            "('testnet', ?, 0, 'temple', ?, 5, 'buyer', 'takenHere', 0, -1, NULL)",
            [key, onion],
          ),
          (
            'a close before the epoch',
            "('testnet', ?, 0, 'temple', ?, 5, 'buyer', 'takenHere', 0, NULL, -1)",
            [key, onion],
          ),
        ]) {
          await expectLater(
            insertTrade(values, variables),
            sqliteError(275),
            reason: label,
          );
        }
        await insertTrade(
          "('testnet', ?, 0, 'temple', ?, 5, 'buyer', 'takenHere', 0, NULL, NULL)",
          [key, onion],
        );
        expect(await tradeRows(), hasLength(1));
      },
    );
  });

  group('the review of #102', () {
    test(
      'a robot the Garage bound gets no reservation, so no pending take (R2)',
      () async {
        expect(
          await bindings.recordGeneratedKey(testnet, fingerprintA),
          isA<Ok>(),
        );
        final robot = RobotSlot(testnet, fingerprintA, 0);
        expect(await bindings.bind(robot, temple), isA<Ok>());

        expect(
          await trades.reserveForNewTrade(robot, temple),
          reservedIs(false),
        );
        expect(await tradeRows(), isEmpty);
      },
    );

    test(
      'a key drawn here on the other network only gives no reservation (M01)',
      () async {
        expect(
          await bindings.recordGeneratedKey(mainnet, fingerprintA),
          isA<Ok>(),
        );

        expect(
          await trades.reserveForNewTrade(
            RobotSlot(testnet, fingerprintA, 0),
            temple,
          ),
          reservedIs(false),
        );
        expect(await bindingRows(), isEmpty);
      },
    );

    test(
      'a key pasted in again between the reservation and the pending take refuses the pending take (R13)',
      () async {
        final reservation = await reserved(0);
        expect(
          await bindings.recordImportedKey(mainnet, fingerprintA),
          isA<Ok>(),
        );

        expect(
          await trades.recordPendingTake(
            reservation,
            orderId: 3,
            role: TradeRole.buyer,
          ),
          refusedWith<GarageKeyNotForTradesFailure>(),
        );
        expect(await tradeRows(), isEmpty);
      },
    );
  });

  group('the active trades', () {
    test(
      'come with each change, oldest first, pending takes included, never a closed trade nor another network\'s',
      () async {
        final seen = <Result<List<TradeRecord>, P2pFailure>>[];
        final changes = StreamController<void>.broadcast();
        final subscription = trades.watchActiveTrades(testnet).listen((active) {
          seen.add(active);
          changes.add(null);
        });
        // The latest list once it is [expected]: drift may emit more than once for one write, never a list the writes did not make.
        Future<List<TradeRecord>> until(List<TradeRecord> expected) async {
          while (true) {
            if (seen.isNotEmpty) {
              final latest = switch (seen.last) {
                Ok(:final value) => value,
                Err(:final failure) => fail('$failure'),
              };
              if (latest.length == expected.length &&
                  latest.indexed.every((e) => e.$2 == expected[e.$1])) {
                return latest;
              }
            }
            await changes.stream.first.timeout(const Duration(seconds: 5));
          }
        }

        await until(const []);
        final first = await pendingTake(await reserved(0));
        await until([first]);
        now = testNow.add(const Duration(minutes: 1));
        final second = await pendingTake(await reserved(1), orderId: 8);
        await until([first, second]);
        final taken = switch (await trades.confirmTake(first)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        await until([taken, second]);
        expect(await trades.closeTrade(second), isA<Ok>());
        await until([taken]);
        expect(await trades.closeTrade(taken), isA<Ok>());
        await until(const []);
        // A trade of mainnet: recorded, recovered here, never listed for testnet.
        expect(
          await bindings.recordGeneratedKey(mainnet, fingerprintB),
          isA<Ok>(),
        );
        expect(
          await bindings.bind(
            RobotSlot(mainnet, fingerprintB, 0),
            templeMainnet,
          ),
          isA<Ok>(),
        );
        expect(
          await trades.recordRecoveredTrade(
            RobotSlot(mainnet, fingerprintB, 0),
            templeMainnet,
            orderId: 4,
            role: TradeRole.buyer,
          ),
          isA<Ok>(),
        );
        await until(const []);
        await subscription.cancel();
        await changes.close();
        expect(
          await trades.watchActiveTrades(testnet).first,
          isA<Ok<List<TradeRecord>, P2pFailure>>().having(
            (ok) => ok.value,
            'active',
            isEmpty,
          ),
        );
        expect(
          await trades.watchActiveTrades(mainnet).first,
          isA<Ok<List<TradeRecord>, P2pFailure>>().having(
            (ok) => ok.value.single.origin,
            'origin',
            TradeOrigin.recovered,
          ),
        );
      },
    );

    test('a row this code did not write gives a storage failure, never a list', () async {
      // The tables of schema 3 without their constraints, holding values no version writes.
      final loose = P2pDatabase.forTesting(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute(
              'CREATE TABLE trades (network TEXT, key_fingerprint TEXT, robot_index INTEGER, coordinator_alias TEXT, coordinator_onion TEXT, order_id INTEGER, role TEXT, origin TEXT, taken_at INTEGER, confirmed_at INTEGER, closed_at INTEGER, PRIMARY KEY (key_fingerprint, robot_index))',
            );
            raw.execute('PRAGMA user_version = ${P2pDatabase.schema}');
          },
        ),
      );
      final looseTrades = TradeRecordRepositoryImpl(loose, clock: () => now);
      final fingerprint = "'${fingerprintA.hex}'";
      for (final (index, values) in [
        (
          0,
          "'testnet', $fingerprint, 0, 'temple', 'o', 1, 'buyer', 'elsewhere', 0, NULL, NULL",
        ),
        (
          1,
          "'testnet', $fingerprint, 1, 'temple', 'o', 1, 'maker', 'takenHere', 0, NULL, NULL",
        ),
        (
          2,
          "'testnet', 'short', 2, 'temple', 'o', 1, 'buyer', 'takenHere', 0, NULL, NULL",
        ),
        (
          3,
          "'testnet', $fingerprint, 3, 'temple', 'o', 1, 'buyer', 'recovered', 0, NULL, NULL",
        ),
        (
          4,
          "'testnet', $fingerprint, 4, 'temple', 'o', 0, 'buyer', 'takenHere', 0, NULL, NULL",
        ),
        (
          5,
          "'testnet', $fingerprint, 5, 'temple', 'o', 1, 'buyer', 'takenHere', 'soon', NULL, NULL",
        ),
        (
          6,
          "'testnet', $fingerprint, 6, NULL, 'o', 1, 'buyer', 'takenHere', 0, NULL, NULL",
        ),
        (
          7,
          "'testnet', $fingerprint, 7, 'temple', 'o', 1, 'buyer', 'takenHere', 0, 99999999999999999, NULL",
        ),
        (
          8,
          "'testnet', '${fingerprintA.hex.toUpperCase()}', 8, 'temple', 'o', 1, 'buyer', 'takenHere', 0, NULL, NULL",
        ),
        (
          9,
          "'testnet', $fingerprint, 9, 'temple', 'o', 1, 'buyer', 'takenHere', -1, NULL, NULL",
        ),
      ]) {
        await loose.customStatement('DELETE FROM trades');
        await loose.customStatement('INSERT INTO trades VALUES ($values)');
        // A raw statement does not tell drift that the table changed: told so, each row is read afresh, not the answer of the row before.
        loose.markTablesUpdated([loose.trades]);
        expect(
          await looseTrades.watchActiveTrades(testnet).first,
          refusedWith<P2pStorageFailure>(),
          reason: '$index',
        );
      }
      await loose.close();
    });
  });

  group('on disk', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('p2p-trades-');
    });

    tearDown(() => directory.delete(recursive: true));

    test(
      'a record outlives its connection, and its foreign key holds there too',
      () async {
        final first = P2pDatabase.open(() async => directory);
        final one = TradeRecordRepositoryImpl(first, clock: () => testNow);
        expect(
          await bindingsInMemory(
            database: first,
          ).recordGeneratedKey(testnet, fingerprintA),
          isA<Ok>(),
        );
        final reservation = switch (await one.reserveForNewTrade(
          RobotSlot(testnet, fingerprintA, 0),
          temple,
        )) {
          Ok(value: final reservation?) => reservation,
          final other => fail('not reserved: $other'),
        };
        final written = await one.recordPendingTake(
          reservation,
          orderId: 3,
          role: TradeRole.buyer,
        );
        await first.close();

        final reopened = P2pDatabase.open(() async => directory);
        expect(
          (await reopened.customSelect('PRAGMA foreign_keys').getSingle())
              .data
              .values
              .single,
          1,
        );
        final again = TradeRecordRepositoryImpl(reopened, clock: () => testNow);
        expect(
          await again.watchActiveTrades(testnet).first,
          isA<Ok<List<TradeRecord>, P2pFailure>>().having(
            (ok) => ok.value,
            'active',
            [valueOf(written)],
          ),
        );
        await reopened.close();
      },
    );

    test(
      'two connections recording a pending take of one robot at once write one record',
      () async {
        final first = P2pDatabase.open(() async => directory);
        final second = P2pDatabase.open(() async => directory);
        await openInTurn([first, second]);
        final one = TradeRecordRepositoryImpl(first, clock: () => testNow);
        final other = TradeRecordRepositoryImpl(second, clock: () => testNow);
        expect(
          await bindingsInMemory(
            database: first,
          ).recordGeneratedKey(testnet, fingerprintA),
          isA<Ok>(),
        );

        for (var index = 0; index < 5; index++) {
          final robot = RobotSlot(testnet, fingerprintA, index);
          final reservation = switch (await untilNotBusy(
            () => one.reserveForNewTrade(robot, temple),
          )) {
            Ok(value: final reservation?) => reservation,
            final other => fail('not reserved: $other'),
          };
          // The one reservation handed to both connections, as a bug would: the database still writes one record.
          final results = await Future.wait([
            untilNotBusy(
              () => one.recordPendingTake(
                reservation,
                orderId: 10,
                role: TradeRole.buyer,
              ),
            ),
            untilNotBusy(
              () => other.recordPendingTake(
                reservation,
                orderId: 11,
                role: TradeRole.buyer,
              ),
            ),
          ]);
          expect(
            results.whereType<Ok<TradeRecord, P2pFailure>>(),
            hasLength(1),
            reason: 'index $index',
          );
          expect(
            results.whereType<Err<TradeRecord, P2pFailure>>().single.failure,
            isA<TradeAlreadyRecordedFailure>(),
            reason: 'index $index',
          );
        }
        await first.close();
        await second.close();

        final reopened = P2pDatabase.open(() async => directory);
        expect(await reopened.select(reopened.trades).get(), hasLength(5));
        await reopened.close();
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  test(
    'a record prints neither its key\'s fingerprint nor its coordinator\'s address',
    () async {
      final record = await pendingTake(await reserved(0));

      expect(
        '$record',
        'TradeRecord(RobotSlot(testnet, 0), temple, 7, buyer, takenHere, pending)',
      );
      expect('$record', isNot(contains(fingerprintA.hex)));
      expect('$record', isNot(contains(temple.onion)));
      expect(
        '${NewTradeStanding(keyDrawnHereOnly: true, indexesInUse: [1, 2])}',
        'NewTradeStanding(true, 2 in use)',
      );
    },
  );
}
