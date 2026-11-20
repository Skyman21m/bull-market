import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/data/trade_payment_repository_impl.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/data/trade_trail_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/trade_status.dart' show InvoiceStep;
import 'package:p2p/src/domain/trade/trade_payment.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/robot_bindings.dart';

/// The records of a maker in `p2p.sqlite` schema 8 (#176; design note `docs/design/phase-3-making-an-order.md` § 3.2, § 3.4, § 3.5): a pending make with no order id, its terms in `maker_terms`, its order id written once with its confirmation, a maker's contracts in the trail, and a payment per contract, each hash paid once.
///
/// Each rule of the database is tried with raw SQL, for what it refuses and what it lets pass, and each write of the repositories for what it gives; a taker's trade keeps every rule it had, and none of a maker's applies to it.
void main() {
  const testnet = RobosatsNetwork.testnet;

  // Fixed test bytes: not keys anyone uses.
  final fingerprint = switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => 1 + i)),
  )) {
    Ok(value: final key) => switch (GarageKeyFingerprint.of(key)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    },
    Err(:final failure) => throw StateError('$failure'),
  };
  CoordinatorIdentity identityOf(String alias) =>
      switch (CoordinatorIdentity.of(coordinator(alias), testnet)) {
        final identity? => identity,
        null => throw StateError('$alias is not on testnet'),
      };
  final temple = identityOf('temple');
  final lake = identityOf('lake');

  // Payment hashes and robot hash ids: fixed test text, none of anything real.
  final hashA = 'a' * 64;
  final hashB = 'b' * 64;
  final hashC = 'c' * 64;
  final hashD = 'd' * 64;
  final takerOne = '1' * 64;
  final takerTwo = '2' * 64;
  final deadline = testNow.microsecondsSinceEpoch + 3600000000;

  late P2pDatabase database;
  late RobotBindingRepositoryImpl bindings;
  late TradeRecordRepositoryImpl trades;
  late TradeTrailRepositoryImpl trails;
  late TradePaymentRepositoryImpl payments;
  var now = testNow;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    now = testNow;
    database = P2pDatabase.forTesting(NativeDatabase.memory());
    bindings = bindingsInMemory(database: database);
    trades = TradeRecordRepositoryImpl(database, clock: () => now);
    trails = TradeTrailRepositoryImpl(database);
    payments = TradePaymentRepositoryImpl(database);
    expect(await bindings.recordGeneratedKey(testnet, fingerprint), isA<Ok>());
  });

  tearDown(() => database.close());

  T valueOf<T>(Result<T, P2pFailure> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => fail('$failure'),
  };

  Matcher refusedWith<T>() => isA<Err<Object?, P2pFailure>>().having(
    (err) => err.failure,
    'failure',
    isA<T>(),
  );

  /// Refused by SQLite, with [message] in its error: a trigger's text, or [check].
  Matcher refusedBy(String message, [String? or]) => throwsA(
    predicate(
      (error) =>
          '$error'.contains(message) || (or != null && '$error'.contains(or)),
    ),
  );
  const check = 'CHECK constraint failed';

  RobotSlot robot(int index) => RobotSlot(testnet, fingerprint, index);

  /// Robot [index] reserved for a new trade on [on] (temple by default).
  Future<TradeReservation> reserve(
    int index, [
    CoordinatorIdentity? on,
  ]) async =>
      switch (await trades.reserveForNewTrade(robot(index), on ?? temple)) {
        Ok(value: final reservation?) => reservation,
        final other => fail('not reserved: $other'),
      };

  Future<PendingMake> pendingMake({
    int index = 0,
    TradeRole role = TradeRole.buyer,
    CoordinatorIdentity? on,
  }) async => valueOf(
    await trades.recordPendingMake(await reserve(index, on), role: role),
  );

  MakerTermsRecord makerTerms({
    String role = 'buyer',
    int type = 0,
    String alias = 'temple',
    double? amount = 100,
    double? minAmount,
    double? maxAmount,
    String? description,
    double? latitude,
    double? longitude,
  }) => MakerTermsRecord(
    version: 1,
    network: 'testnet',
    coordinatorAlias: alias,
    role: role,
    type: type,
    currencyId: 2,
    amount: amount,
    minAmount: minAmount,
    maxAmount: maxAmount,
    premiumPercent: 1.5,
    paymentMethod: 'Revolut SEPA',
    bondSizePercent: 3,
    publicSeconds: 86340,
    escrowSeconds: 10800,
    description: description,
    hasPassword: false,
    latitude: latitude,
    longitude: longitude,
    createdPrice: 93545.25,
    makerFee: 0.00025,
  );

  /// A make of robot [index], its terms recorded, confirmed with order [orderId].
  Future<TradeRecord> confirmedMake({
    int index = 0,
    int orderId = 42,
    CoordinatorIdentity? on,
    TradeRole role = TradeRole.buyer,
  }) async {
    final make = await pendingMake(index: index, on: on, role: role);
    expect(
      await trails.recordMakerTerms(
        make,
        makerTerms(
          alias: (on ?? temple).alias,
          role: role.name,
          type: role == TradeRole.buyer ? 0 : 1,
        ),
      ),
      isA<Ok>(),
    );
    return valueOf(await trades.confirmMake(make, orderId: orderId));
  }

  Future<TradeRecord> pendingTake({int index = 10, int orderId = 7}) async =>
      valueOf(
        await trades.recordPendingTake(
          await reserve(index),
          orderId: orderId,
          role: TradeRole.buyer,
        ),
      );

  TradeTermsRecord takerTerms({int orderId = 7}) => TradeTermsRecord(
    version: 1,
    network: 'testnet',
    coordinatorAlias: 'temple',
    orderId: orderId,
    role: 'buyer',
    type: 1,
    currencyId: 2,
    amount: 100,
    isRange: false,
    premiumPercent: 2,
    explicitSatoshis: null,
    bondSizePercent: 3,
    escrowSeconds: 10800,
    bookPrice: 93545.25,
    takerFee: 0.00175,
  );

  TradeTrailRecord trailOf({
    int orderId = 42,
    String role = 'buyer',
    String earlierEscrows = '',
    bool seenLate = false,
    String position = 'waitingForBoth',
    int readAt = 1000,
    String? bondHash,
    String? escrowHash,
    int take = 0,
    int? takeDeadline,
    String? takerHashId,
    double? takenAmount,
  }) => TradeTrailRecord(
    version: 1,
    network: 'testnet',
    coordinatorAlias: 'temple',
    orderId: orderId,
    role: role,
    position: position,
    readAtMicros: readAt,
    bondHash: bondHash,
    escrowHash: escrowHash,
    deadlineMicros: null,
    bondStepSeenAtMicros: null,
    bondStepDeadlineMicros: null,
    breached: false,
    historyUnknown: false,
    take: take,
    takeDeadlineMicros: takeDeadline,
    takerHashId: takerHashId,
    takenAmount: takenAmount,
    earlierEscrows: earlierEscrows,
    seenLate: seenLate,
  );

  /// The row of `trades` of robot [index].
  Future<Map<String, Object?>> tradeRow(int index) async =>
      (await database
              .customSelect(
                'SELECT * FROM trades WHERE robot_index = ?',
                variables: [Variable.withInt(index)],
              )
              .getSingle())
          .data;

  group('a pending make', () {
    test(
      'is written with no order id, under the very rules of a pending take, and listed apart from the trades',
      () async {
        final make = await pendingMake(role: TradeRole.seller);
        expect(make.robot, robot(0));
        expect(make.coordinatorAlias, temple.alias);
        expect(make.coordinatorOnion, temple.onion);
        expect(make.role, TradeRole.seller);
        expect(make.writtenAt, testNow);
        expect(make.isActive, isTrue);
        expect(await tradeRow(0), containsPair('order_id', null));
        expect(await tradeRow(0), containsPair('origin', 'madeHere'));
        expect(await tradeRow(0), containsPair('confirmed_at', null));
        // A robot has one record, ever; a robot with no binding none.
        expect(
          await trades.recordPendingMake(
            TradeReservation(robot(0), temple),
            role: TradeRole.buyer,
          ),
          refusedWith<TradeAlreadyRecordedFailure>(),
        );
        expect(
          await trades.recordPendingMake(
            TradeReservation(robot(5), temple),
            role: TradeRole.buyer,
          ),
          refusedWith<RobotNotForNewTradeFailure>(),
        );
        // A pending make is not a trade: it has no order yet.
        expect(valueOf(await trades.watchActiveTrades(testnet).first), isEmpty);
        expect(valueOf(await trades.watchPendingMakes(testnet).first), [make]);
        expect(
          valueOf(
            await trades.watchPendingMakes(RobosatsNetwork.mainnet).first,
          ),
          isEmpty,
        );
      },
    );

    test(
      'is confirmed with its order id only once its terms are recorded, and is then a trade made here',
      () async {
        final make = await pendingMake();
        expect(
          await trades.confirmMake(make, orderId: 42),
          refusedWith<P2pStorageFailure>(),
        );
        expect(await tradeRow(0), containsPair('order_id', null));

        final terms = makerTerms(
          amount: null,
          minAmount: 20,
          maxAmount: 300,
          description: 'Fast',
          latitude: 48.8566,
          longitude: 2.3522,
        );
        expect(await trails.recordMakerTerms(make, terms), isA<Ok>());
        expect(valueOf(await trails.makerTermsOf(robot(0))), terms);
        expect(valueOf(await trails.makerTermsOf(robot(1))), isNull);

        now = testNow.add(const Duration(minutes: 1));
        final record = valueOf(await trades.confirmMake(make, orderId: 42));
        expect(record.robot, robot(0));
        expect(record.orderId, 42);
        expect(record.origin, TradeOrigin.madeHere);
        expect(record.role, TradeRole.buyer);
        expect(record.takenAt, testNow);
        expect(record.confirmedAt, now);
        expect(record.closedAt, isNull);
        // Confirmed again with its order, it is as it was; with another, it is not the make asked.
        expect(valueOf(await trades.confirmMake(make, orderId: 42)), record);
        expect(
          await trades.confirmMake(make, orderId: 43),
          refusedWith<P2pStorageFailure>(),
        );
        expect(valueOf(await trades.watchActiveTrades(testnet).first), [
          record,
        ]);
        expect(valueOf(await trades.watchPendingMakes(testnet).first), isEmpty);
        // Its terms are kept as they were, never written again (refused, a confirmed make being no pending make); a confirmed make is not closed as pending.
        expect(
          await trails.recordMakerTerms(make, makerTerms()),
          refusedWith<P2pStorageFailure>(),
        );
        await expectLater(
          database.customStatement(
            "INSERT INTO maker_terms (key_fingerprint, robot_index, version, network, coordinator_alias, role, order_type, currency_id, amount, premium_percent, payment_method, bond_size_percent, public_seconds, escrow_seconds, has_password, created_price, maker_fee) VALUES (?, 0, 1, 'testnet', 'temple', 'buyer', 0, 2, 100.0, 1.5, 'Revolut', 3.0, 86340, 10800, 0, 93545.25, 0.00025)",
            [fingerprint.hex],
          ),
          refusedBy('terms of no pending make'),
        );
        expect(valueOf(await trails.makerTermsOf(robot(0))), terms);
        expect(
          await trades.closePendingMake(make),
          refusedWith<P2pStorageFailure>(),
        );
        // The refusal leaves the trade open: the write's own guard (`order_id IS NULL`), not only its answer (security review of #182, M02).
        expect(valueOf(await trades.watchActiveTrades(testnet).first), [
          record,
        ]);
        // Closed as any trade, it is never confirmed again.
        final closed = valueOf(await trades.closeTrade(record));
        expect(closed.closedAt, now);
        expect(
          await trades.confirmMake(make, orderId: 42),
          refusedWith<TradeClosedFailure>(),
        );
      },
    );

    test(
      'closed as not made keeps its first time of closing and is never confirmed',
      () async {
        final make = await pendingMake();
        expect(await trails.recordMakerTerms(make, makerTerms()), isA<Ok>());
        now = testNow.add(const Duration(minutes: 5));
        final closed = valueOf(await trades.closePendingMake(make));
        expect(closed.closedAt, now);
        expect(closed.isActive, isFalse);
        final firstClose = now;
        now = testNow.add(const Duration(minutes: 9));
        expect(
          valueOf(await trades.closePendingMake(make)).closedAt,
          firstClose,
        );
        expect(
          await trades.confirmMake(make, orderId: 42),
          refusedWith<TradeClosedFailure>(),
        );
        expect(await tradeRow(0), containsPair('order_id', null));
        expect(valueOf(await trades.watchPendingMakes(testnet).first), isEmpty);
        expect(valueOf(await trades.watchActiveTrades(testnet).first), isEmpty);
      },
    );

    test(
      'takes no order id that another open trade of its coordinator holds, nor a take an order a make holds',
      () async {
        final take = await pendingTake(orderId: 42);
        final make = await pendingMake();
        expect(await trails.recordMakerTerms(make, makerTerms()), isA<Ok>());
        expect(
          await trades.confirmMake(make, orderId: 42),
          refusedWith<P2pStorageFailure>(),
        );
        expect(await tradeRow(0), containsPair('order_id', null));
        // On another coordinator, the same number is another order.
        final elsewhere = await confirmedMake(index: 1, orderId: 42, on: lake);
        expect(elsewhere.coordinatorAlias, lake.alias);
        // Once the take is closed, the order is free here.
        expect(await trades.closeTrade(take), isA<Ok>());
        final made = valueOf(await trades.confirmMake(make, orderId: 42));
        expect(made.orderId, 42);
        // And a take of the order a make holds is refused before anything leaves.
        expect(
          await trades.recordPendingTake(
            await reserve(11),
            orderId: 42,
            role: TradeRole.seller,
          ),
          refusedWith<P2pStorageFailure>(),
        );
      },
    );
  });

  group('the database keeps the trades of schema 8, whatever the code:', () {
    /// A row of `trades` for robot [index], bound first, written by hand.
    Future<void> insertTrade(
      int index, {
      required String origin,
      required int? orderId,
      int? confirmedAt,
      int? closedAt,
    }) async {
      await reserve(index);
      await database.customStatement(
        "INSERT INTO trades VALUES ('testnet', ?, ?, ?, ?, ?, 'buyer', ?, 1, ?, ?)",
        [
          fingerprint.hex,
          index,
          temple.alias,
          temple.onion,
          orderId,
          origin,
          confirmedAt,
          closedAt,
        ],
      );
    }

    test(
      'an order id, but for a pending make; a make confirmed with it only; a recovered trade confirmed',
      () async {
        var index = 20;
        for (final (label, origin, orderId, confirmed) in [
          ('a take with no order', 'takenHere', null, null),
          ('a take confirmed with no order', 'takenHere', null, 5),
          ('a recovered trade with no order', 'recovered', null, 5),
          ('a make confirmed with no order', 'madeHere', null, 5),
          ('an order id of 0', 'takenHere', 0, null),
          ('a negative order id', 'takenHere', -3, null),
          ('a recovered trade not confirmed', 'recovered', 3, null),
          ('another origin', 'made', 3, null),
        ]) {
          await expectLater(
            insertTrade(
              index++,
              origin: origin,
              orderId: orderId,
              confirmedAt: confirmed,
            ),
            refusedBy(check),
            reason: label,
          );
        }
        // What the code writes: a pending make, a pending take, a recovered trade.
        await insertTrade(30, origin: 'madeHere', orderId: null);
        await insertTrade(31, origin: 'takenHere', orderId: 31);
        await insertTrade(32, origin: 'recovered', orderId: 32, confirmedAt: 2);
        // A make confirmed by an update with its confirmation only is refused by its CHECK, the trigger letting a confirmation through.
        await expectLater(
          database.customStatement(
            'UPDATE trades SET confirmed_at = 5 WHERE robot_index = 30',
          ),
          refusedBy(check),
        );
      },
    );

    test(
      'a make is recorded pending: never with an order id, nor closed',
      () async {
        for (final (index, orderId, confirmed, closed) in [
          (40, 40, 5, null),
          (41, 41, null, null),
          (42, null, null, 5),
        ]) {
          await expectLater(
            insertTrade(
              index,
              origin: 'madeHere',
              orderId: orderId,
              confirmedAt: confirmed,
              closedAt: closed,
            ),
            refusedBy('a make is recorded pending'),
            reason: '$index',
          );
        }
        // A take may be written closed, as before.
        await insertTrade(43, origin: 'takenHere', orderId: 43, closedAt: 5);
      },
    );

    test(
      'the order id of a pending make, written once, with its confirmation, once its terms are recorded',
      () async {
        const gains = 'a trade record only gains its times';
        final make = await pendingMake();
        // Without its terms, the order id is refused, with or without the confirmation.
        await expectLater(
          database.customStatement(
            'UPDATE trades SET order_id = 5, confirmed_at = 5 WHERE robot_index = 0',
          ),
          refusedBy(gains),
        );
        await expectLater(
          database.customStatement(
            'UPDATE trades SET order_id = 5 WHERE robot_index = 0',
          ),
          refusedBy(gains),
        );
        expect(await trails.recordMakerTerms(make, makerTerms()), isA<Ok>());
        // With its terms: the order id without its confirmation is refused by the trigger, an order id out of bounds with it by the CHECK.
        await expectLater(
          database.customStatement(
            'UPDATE trades SET order_id = 5 WHERE robot_index = 0',
          ),
          refusedBy(gains),
        );
        await expectLater(
          database.customStatement(
            'UPDATE trades SET order_id = 0, confirmed_at = 5 WHERE robot_index = 0',
          ),
          refusedBy(check),
        );
        // With its terms and its confirmation: written.
        await database.customStatement(
          'UPDATE trades SET order_id = 5, confirmed_at = 5 WHERE robot_index = 0',
        );
        // Then never again, nor taken back, nor its confirmation moved, nor the origin changed.
        for (final change in [
          'order_id = 6',
          'order_id = NULL, confirmed_at = NULL',
          'order_id = NULL',
          'confirmed_at = 6',
          "origin = 'takenHere'",
        ]) {
          await expectLater(
            database.customStatement(
              'UPDATE trades SET $change WHERE robot_index = 0',
            ),
            refusedBy(gains, check),
            reason: change,
          );
        }
        expect(await tradeRow(0), containsPair('order_id', 5));
        // A pending take keeps its order id, as before.
        await pendingTake();
        await expectLater(
          database.customStatement(
            'UPDATE trades SET order_id = 8, confirmed_at = 5 WHERE robot_index = 10',
          ),
          refusedBy(gains),
        );
        // A pending make closed is never confirmed, its terms recorded or not.
        final closed = await pendingMake(index: 1);
        expect(await trails.recordMakerTerms(closed, makerTerms()), isA<Ok>());
        expect(await trades.closePendingMake(closed), isA<Ok>());
        await expectLater(
          database.customStatement(
            'UPDATE trades SET order_id = 9, confirmed_at = 9 WHERE robot_index = 1',
          ),
          refusedBy(gains),
        );
      },
    );

    test('one open trade per order when an order id is written after the insert', () async {
      await pendingTake(orderId: 7);
      final make = await pendingMake();
      expect(await trails.recordMakerTerms(make, makerTerms()), isA<Ok>());
      await expectLater(
        database.customStatement(
          'UPDATE trades SET order_id = 7, confirmed_at = 5 WHERE robot_index = 0',
        ),
        refusedBy('an order has one open trade'),
      );
      // The same number on the other network is another order: written.
      await database.customStatement(
        "INSERT INTO robot_bindings VALUES ('mainnet', ?, 50, 'temple', 'http://temple.onion', '', 'nostr', 10, 'generated')",
        [fingerprint.hex],
      );
      await database.customStatement(
        "INSERT INTO trades VALUES ('mainnet', ?, 50, 'temple', 'http://temple.onion', 8, 'buyer', 'takenHere', 1, NULL, NULL)",
        [fingerprint.hex],
      );
      await database.customStatement(
        'UPDATE trades SET order_id = 8, confirmed_at = 5 WHERE robot_index = 0',
      );
      // An update that names the order id and keeps it is no second trade of the order: the take of order 7 closed so.
      await database.customStatement(
        'UPDATE trades SET order_id = order_id, closed_at = 6 WHERE robot_index = 10',
      );
    });
  });

  group('the terms of a make', () {
    /// The terms of a make written by hand for robot [index], the columns of [changes] in place of a valid make's.
    Future<void> insertTerms(
      int index, [
      Map<String, Object?> changes = const {},
    ]) {
      final values = <String, Object?>{
        'key_fingerprint': fingerprint.hex,
        'robot_index': index,
        'version': 1,
        'network': 'testnet',
        'coordinator_alias': 'temple',
        'role': 'buyer',
        'order_type': 0,
        'currency_id': 2,
        'amount': 100.0,
        'min_amount': null,
        'max_amount': null,
        'premium_percent': 1.5,
        'payment_method': 'Revolut',
        'bond_size_percent': 3.0,
        'public_seconds': 86340,
        'escrow_seconds': 10800,
        'description': null,
        'has_password': 0,
        'latitude': null,
        'longitude': null,
        'created_price': 93545.25,
        'maker_fee': 0.00025,
        ...changes,
      };
      return database.customStatement(
        'INSERT INTO maker_terms (${values.keys.join(', ')}) VALUES (${values.keys.map((_) => '?').join(', ')})',
        values.values.toList(),
      );
    }

    test(
      'are bounded as the make is, every bound true or false, never NULL',
      () async {
        await pendingMake();
        // The trigger that asks for a pending make of the same network, coordinator and role is set aside, so that each CHECK is tried alone, then made again from its own text.
        final trigger = await database
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE name = 'maker_terms_of_their_make'",
            )
            .getSingle();
        await database.customStatement(
          'DROP TRIGGER maker_terms_of_their_make',
        );
        for (final (label, changes) in [
          (
            'both a fixed amount and a range',
            {'min_amount': 10.0, 'max_amount': 20.0},
          ),
          ('neither', {'amount': null}),
          ('a minimum only', {'amount': null, 'min_amount': 10.0}),
          ('a maximum only', {'amount': null, 'max_amount': 20.0}),
          ('an amount of 0', {'amount': 0.0}),
          ('an amount of 10^10', {'amount': 10000000000.0}),
          ('an amount as text', {'amount': 'a hundred'}),
          (
            'a range below 1.5',
            {'amount': null, 'min_amount': 10.0, 'max_amount': 14.99},
          ),
          (
            'a range above 15',
            {'amount': null, 'min_amount': 10.0, 'max_amount': 150.01},
          ),
          (
            'a range from 0',
            {'amount': null, 'min_amount': 0.0, 'max_amount': 10.0},
          ),
          (
            'a range to 10^10',
            {
              'amount': null,
              'min_amount': 1000000000.0,
              'max_amount': 10000000000.0,
            },
          ),
          ('a premium of -100', {'premium_percent': -100.0}),
          ('a premium above 999', {'premium_percent': 999.01}),
          ('a premium as text', {'premium_percent': 'high'}),
          ('no payment method', {'payment_method': ''}),
          ('a payment method of 71 characters', {'payment_method': 'x' * 71}),
          ('a bond below 2 %', {'bond_size_percent': 1.99}),
          ('a bond above 15 %', {'bond_size_percent': 15.01}),
          ('a public duration of 599 s', {'public_seconds': 599}),
          ('a public duration above a day', {'public_seconds': 86401}),
          ('a public duration not whole', {'public_seconds': 600.5}),
          ('an escrow duration of 1,799 s', {'escrow_seconds': 1799}),
          ('an escrow duration above 10 h', {'escrow_seconds': 36001}),
          ('an empty description', {'description': ''}),
          ('a description of 241 characters', {'description': 'x' * 241}),
          // A NUL would end the text early for `length`, which counts characters up to it (security review of #176).
          ('a payment method with a NUL', {'payment_method': 'a\u0000b'}),
          (
            'a description with a NUL past its bound',
            {'description': 'a\u0000${'b' * 400}'},
          ),
          ('a description with a NUL', {'description': 'a\u0000'}),
          ('a coordinator with a NUL', {'coordinator_alias': 'temple\u0000'}),
          // The bounds count code points, not bytes nor UTF-16 units.
          (
            'a description of 241 code points of four bytes',
            {'description': '\u{1F600}' * 241},
          ),
          (
            'a payment method of 71 code points of two bytes',
            {'payment_method': '\u00e9' * 71},
          ),
          ('a password flag of 2', {'has_password': 2}),
          ('a latitude alone', {'latitude': 1.0}),
          ('a longitude alone', {'longitude': 1.0}),
          ('a latitude above 90', {'latitude': 90.5, 'longitude': 0.0}),
          ('a longitude below -180', {'latitude': 0.0, 'longitude': -180.5}),
          ('a latitude as text', {'latitude': 'north', 'longitude': 0.0}),
          ('a price of 0', {'created_price': 0.0}),
          ('a maker fee above 1 %', {'maker_fee': 0.0101}),
          ('a negative maker fee', {'maker_fee': -0.001}),
          ('a buy order whose maker sells', {'role': 'seller'}),
          ('a sell order whose maker buys', {'order_type': 1}),
          ('another network', {'network': 'regtest'}),
          ('no coordinator', {'coordinator_alias': ''}),
          ('version 0', {'version': 0}),
          ('currency 0', {'currency_id': 0}),
        ]) {
          await expectLater(
            insertTerms(0, changes),
            refusedBy(check),
            reason: label,
          );
        }
        expect(
          await database.customSelect('SELECT * FROM maker_terms').get(),
          isEmpty,
        );
        await database.customStatement(trigger.read<String>('sql'));
        // Every bound itself is taken, each by a pending make of its own.
        var index = 1;
        for (final (label, changes) in [
          (
            'a range of exactly 1.5',
            {'amount': null, 'min_amount': 10.0, 'max_amount': 15.0},
          ),
          (
            'a range of exactly 15',
            {'amount': null, 'min_amount': 10.0, 'max_amount': 150.0},
          ),
          ('a premium just above -100', {'premium_percent': -99.99}),
          ('a premium of 999', {'premium_percent': 999.0}),
          ('a payment method of 70 characters', {'payment_method': 'x' * 70}),
          ('a bond of 2 %', {'bond_size_percent': 2.0}),
          ('a bond of 15 %', {'bond_size_percent': 15.0}),
          ('a public duration of 600 s', {'public_seconds': 600}),
          ('a public duration of a day', {'public_seconds': 86400}),
          ('an escrow duration of 30 min', {'escrow_seconds': 1800}),
          ('an escrow duration of 10 h', {'escrow_seconds': 36000}),
          ('a description of 240 characters', {'description': 'x' * 240}),
          (
            'a description of 240 code points of four bytes',
            {'description': '\u{1F600}' * 240},
          ),
          (
            'a payment method of 70 code points of two bytes',
            {'payment_method': '\u00e9' * 70},
          ),
          ('a password', {'has_password': 1}),
          (
            'a meeting point at a corner of the map',
            {'latitude': -90.0, 'longitude': 180.0},
          ),
          ('no maker fee', {'maker_fee': 0.0}),
          ('a maker fee of 1 %', {'maker_fee': 0.01}),
          (
            'a sell order whose maker sells',
            {'role': 'seller', 'order_type': 1},
          ),
        ]) {
          await pendingMake(
            index: index,
            role: changes['role'] == 'seller'
                ? TradeRole.seller
                : TradeRole.buyer,
          );
          await insertTerms(index, changes);
          expect(
            await database
                .customSelect(
                  'SELECT 1 FROM maker_terms WHERE robot_index = ?',
                  variables: [Variable.withInt(index)],
                )
                .get(),
            hasLength(1),
            reason: label,
          );
          index++;
        }
      },
    );

    test(
      'are written once, for a pending make of their network, coordinator and role only, and never changed nor deleted',
      () async {
        const noMake = 'terms of no pending make';
        // A pending take, and a recovered trade, have no terms of a make.
        await pendingTake();
        await expectLater(insertTerms(10), refusedBy(noMake));
        // A pending make of another coordinator, role or network.
        await pendingMake();
        await expectLater(
          insertTerms(0, {'coordinator_alias': 'lake'}),
          refusedBy(noMake),
        );
        await expectLater(
          insertTerms(0, {'role': 'seller', 'order_type': 1}),
          refusedBy(noMake),
        );
        await expectLater(
          insertTerms(0, {'network': 'mainnet'}),
          refusedBy(noMake),
        );
        // A make closed.
        final closed = await pendingMake(index: 1);
        expect(await trades.closePendingMake(closed), isA<Ok>());
        await expectLater(insertTerms(1), refusedBy(noMake));
        // Its own: written once, a second insert writing nothing.
        await insertTerms(0);
        await insertTerms(0, {'amount': 200.0});
        await database.customStatement(
          'INSERT OR REPLACE INTO maker_terms SELECT key_fingerprint, robot_index, version, network, coordinator_alias, role, order_type, currency_id, 300.0, min_amount, max_amount, premium_percent, payment_method, bond_size_percent, public_seconds, escrow_seconds, description, has_password, latitude, longitude, created_price, maker_fee FROM maker_terms',
        );
        expect(
          (await database
                  .customSelect('SELECT amount FROM maker_terms')
                  .getSingle())
              .read<double>('amount'),
          100.0,
        );
        await expectLater(
          database.customStatement('UPDATE maker_terms SET amount = 50.0'),
          refusedBy('the terms of a make are set once'),
        );
        await expectLater(
          database.customStatement('DELETE FROM maker_terms'),
          refusedBy('the terms of a make are kept'),
        );
      },
    );

    test(
      'are never the terms of a take, which a trade made here never has',
      () async {
        final made = await confirmedMake();
        expect(
          await trails.recordTerms(made, takerTerms(orderId: 42)),
          refusedWith<P2pStorageFailure>(),
        );
        // A take's terms, for a take: as before.
        final take = await pendingTake();
        expect(await trails.recordTerms(take, takerTerms()), isA<Ok>());
      },
    );
  });

  group('the trail of a make', () {
    test(
      'is written once its order id is known, at its first contract, and read back as it was',
      () async {
        final made = await confirmedMake();
        final first = trailOf(
          position: 'waitingForBoth',
          takeDeadline: deadline,
          takerHashId: takerOne,
          takenAmount: 75.5,
        );
        expect(
          await trails.storeTrail(made, first),
          isA<Ok<TrailStoreOutcome, P2pFailure>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TrailStored>(),
          ),
        );
        expect(
          valueOf(await trails.historyOf(made)),
          StoredTradeHistory(terms: null, trail: first),
        );
        // A later contract, with a later deadline: stored and read back.
        final next = trailOf(
          readAt: 2000,
          take: 1,
          takeDeadline: deadline + 1,
          takerHashId: takerTwo,
          takenAmount: 80,
        );
        expect(
          await trails.storeTrail(made, next),
          isA<Ok<TrailStoreOutcome, P2pFailure>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TrailStored>(),
          ),
        );
        expect(valueOf(await trails.historyOf(made)).trail, next);
        // One moving the contract back is kept out by `whyNotReplace` before the database.
        expect(
          await trails.storeTrail(made, trailOf(readAt: 3000, take: 0)),
          isA<Ok<TrailStoreOutcome, P2pFailure>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TrailKept>().having(
              (kept) => kept.reason,
              'reason',
              TrailReplacementRefusal.contractMoved,
            ),
          ),
        );
      },
    );

    test(
      'is refused for a later contract, and for a take with a contract',
      () async {
        const noTrade = 'a trail of no open trade';
        final made = await confirmedMake();
        expect(
          await trails.storeTrail(
            made,
            trailOf(take: 1, takeDeadline: deadline),
          ),
          refusedWith<P2pStorageFailure>(),
        );
        final take = await pendingTake();
        expect(await trails.recordTerms(take, takerTerms()), isA<Ok>());
        for (final trail in [
          trailOf(orderId: 7, takeDeadline: deadline),
          trailOf(orderId: 7, takerHashId: takerOne),
          trailOf(orderId: 7, takenAmount: 5),
          trailOf(orderId: 7, take: 1, takeDeadline: deadline),
        ]) {
          expect(
            await trails.storeTrail(take, trail),
            refusedWith<P2pStorageFailure>(),
            reason: '$trail',
          );
        }
        // The same, by hand, says why.
        await expectLater(
          database.customStatement(
            "INSERT INTO trade_trails (key_fingerprint, robot_index, version, network, coordinator_alias, order_id, role, position, read_at, breached, history_unknown, taker_hash_id) VALUES (?, 10, 1, 'testnet', 'temple', 7, 'buyer', 'start', 0, 0, 0, ?)",
            [fingerprint.hex, takerOne],
          ),
          refusedBy(noTrade),
        );
        // A pending make has no order to write a trail of.
        await pendingMake(index: 1);
        await expectLater(
          database.customStatement(
            "INSERT INTO trade_trails (key_fingerprint, robot_index, version, network, coordinator_alias, order_id, role, position, read_at, breached, history_unknown) VALUES (?, 1, 1, 'testnet', 'temple', 1, 'buyer', 'start', 0, 0, 0)",
            [fingerprint.hex],
          ),
          refusedBy(noTrade),
        );
        // The take's own trail: as before.
        expect(
          await trails.storeTrail(take, trailOf(orderId: 7, position: 'start')),
          isA<Ok<TrailStoreOutcome, P2pFailure>>(),
        );
      },
    );

    test('holds the maker positions and a contract within its bounds', () async {
      // The trigger that asks for a trade is set aside, so that each CHECK is tried alone.
      await database.customStatement(
        'DROP TRIGGER trade_trails_of_their_trade',
      );
      const columns =
          'key_fingerprint, robot_index, version, network, coordinator_alias, order_id, role, position, read_at, breached, history_unknown, take, take_deadline, taker_hash_id, taken_amount';
      var index = 0;
      Future<void> insert(
        String position,
        Object? take,
        Object? takeDeadline,
        Object? taker,
        Object? amount,
      ) async {
        await confirmedMake(index: index, orderId: 100 + index);
        final row = index++;
        await database.customStatement(
          "INSERT INTO trade_trails ($columns) VALUES (?, ?, 1, 'testnet', 'temple', ?, 'buyer', ?, 0, 0, 0, ?, ?, ?, ?)",
          [
            fingerprint.hex,
            row,
            100 + row,
            position,
            take,
            takeDeadline,
            taker,
            amount,
          ],
        );
      }

      for (final position in ['makerBondStep', 'public', 'paused']) {
        await insert(position, 0, null, null, null);
      }
      await insert('waitingForBoth', 3, deadline, takerOne, 0.01);
      for (final (label, values) in [
        ('a contract below 0', (-1, null, null, null)),
        ('a later contract with no deadline', (1, null, null, null)),
        ('a contract as text', ('one', deadline, null, null)),
        ('a deadline before the epoch', (0, -1, null, null)),
        ('a deadline after the year 9999', (0, 253402300800000000, null, null)),
        ('a deadline as text', (0, 'soon', null, null)),
        (
          'an uppercase taker',
          (0, null, takerOne.toUpperCase().replaceAll('1', 'A'), null),
        ),
        ('a short taker', (0, null, 'ab', null)),
        ('a taker that is no hash id', (0, null, 'g' * 64, null)),
        ('an amount of 0', (0, null, null, 0.0)),
        ('a negative amount', (0, null, null, -5.0)),
        ('an amount of 10^10', (0, null, null, 10000000000.0)),
        ('an amount as text', (0, null, null, 'five')),
      ]) {
        final (take, takeDeadline, taker, amount) = values;
        await expectLater(
          insert('waitingForBoth', take, takeDeadline, taker, amount),
          refusedBy(check),
          reason: label,
        );
      }
    });
  });

  group(
    'the escrows of earlier contracts and the mark of a contract seen late (schema 8 as amended by #178)',
    () {
      test(
        'a first trail, a make\'s or a take\'s, holds neither: the database refuses either at contract 0',
        () async {
          final made = await confirmedMake();
          final take = await pendingTake();
          expect(await trails.recordTerms(take, takerTerms()), isA<Ok>());
          Future<void> insert(
            TradeRecord trade,
            String earlier,
            int late,
          ) => database.customStatement(
            'INSERT INTO trade_trails (key_fingerprint, robot_index, version, '
            'network, coordinator_alias, order_id, role, position, read_at, '
            'breached, history_unknown, earlier_escrows, seen_late) '
            "VALUES (?, ?, 1, 'testnet', 'temple', ?, 'buyer', 'start', 0, 0, 0, ?, ?)",
            [
              trade.robot.keyFingerprint.hex,
              trade.robot.accountIndex,
              trade.orderId,
              earlier,
              late,
            ],
          );
          for (final trade in [made, take]) {
            for (final (label, earlier, late) in [
              ('an earlier escrow', '$hashA;', 0),
              ('the mark', '', 1),
              ('both', '$hashA;', 1),
            ]) {
              await expectLater(
                insert(trade, earlier, late),
                refusedBy(check),
                reason: '${trade.origin.name}: $label',
              );
            }
            // Neither, and the first trail is written.
            await insert(trade, '', 0);
          }
        },
      );
    },
  );

  group('the contract of a make only moves forward, whatever the code:', () {
    const forward = 'a trail only moves forward';

    /// The trail of a make of robot [index] at [position], at contract 0 with its deadline, taker and amount, its bond and escrow hashes pinned.
    /// The trail of a make of robot [index] at [position], of a maker seller there (a maker buyer's 8 never goes back to the book) unless [role] says otherwise.
    Future<void> makeAt(int index, String position, {TradeRole? role}) async {
      final side =
          role ??
          (position == 'waitingForPayout' ? TradeRole.seller : TradeRole.buyer);
      final made = await confirmedMake(
        index: index,
        orderId: 100 + index,
        role: side,
      );
      expect(
        await trails.storeTrail(
          made,
          trailOf(
            orderId: 100 + index,
            role: side.name,
            position: position,
            bondHash: hashA,
            escrowHash: hashB,
            takeDeadline: deadline,
            takerHashId: takerOne,
            takenAmount: 75.5,
          ),
        ),
        isA<Ok<TrailStoreOutcome, P2pFailure>>(),
      );
    }

    Future<void> update(int index, String change) => database.customStatement(
      'UPDATE trade_trails SET $change, read_at = read_at + 1 WHERE robot_index = $index',
    );

    /// The escrow held joins those of the earlier contracts in the write that moves `take` (amended by #178 after its security review).
    const earlierGrows =
        "earlier_escrows = earlier_escrows || coalesce(escrow_hash || ';', '')";

    String moveTo(String position, {int by = 1, int later = 10}) =>
        "take = take + $by, take_deadline = take_deadline + $later, position = '$position', taker_hash_id = '$takerTwo', escrow_hash = '$hashC', $earlierGrows";

    test(
      'its contract moves by one, from where a new take is read, to where it is read, with a later deadline',
      () async {
        var index = 0;
        for (final from in [
          'public',
          'paused',
          'waitingForBoth',
          'waitingForEscrow',
          'waitingForPayout',
        ]) {
          for (final to in [
            'waitingForBoth',
            'waitingForEscrow',
            'waitingForPayout',
          ]) {
            await makeAt(index, from);
            await update(index, moveTo(to));
            index++;
          }
        }
        for (final (from, to) in [
          ('chatting', 'waitingForBoth'),
          ('fiatSent', 'waitingForEscrow'),
          ('makerBondStep', 'waitingForBoth'),
          ('start', 'waitingForBoth'),
          ('public', 'public'),
          ('waitingForBoth', 'chatting'),
          ('paused', 'paused'),
        ]) {
          await makeAt(index, from);
          await expectLater(
            update(index, moveTo(to)),
            refusedBy(forward),
            reason: '$from to $to',
          );
          index++;
        }
      },
    );

    test(
      'a next contract seen late: by one, from where a new take is read, to the chat or later, with the same deadline and a taker (amended by #178 before any release)',
      () async {
        const lateAt = [
          'chatting',
          'fiatSent',
          'inDispute',
          'sendingSats',
          'succeeded',
          'routingFailed',
          'waitingDisputeResolution',
          'makerLostDispute',
          'takerLostDispute',
        ];
        String lateTo(String position) =>
            "take = take + 1, position = '$position', taker_hash_id = '$takerTwo', escrow_hash = NULL, seen_late = 1, $earlierGrows";
        var index = 0;
        for (final from in [
          'public',
          'paused',
          'waitingForBoth',
          'waitingForEscrow',
          'waitingForPayout',
        ]) {
          for (final to in lateAt) {
            await makeAt(index, from);
            await update(index, lateTo(to));
            index++;
          }
        }
        for (final (label, from, change) in [
          ('from the chat', 'chatting', lateTo('succeeded')),
          ('before any take', 'makerBondStep', lateTo('chatting')),
          ('to an end with no taker', 'public', lateTo('expired')),
          ('to a cancel', 'public', lateTo('cancelled')),
          (
            'with another deadline',
            'public',
            '${lateTo('chatting')}, take_deadline = take_deadline + 10',
          ),
          ('by two', 'public', "take = take + 2, position = 'chatting'"),
          (
            'keeping the escrow',
            'waitingForEscrow',
            "take = take + 1, position = 'chatting', taker_hash_id = '$takerTwo'",
          ),
        ]) {
          await makeAt(index, from);
          await expectLater(
            update(index, change),
            refusedBy(forward),
            reason: label,
          );
          index++;
        }
      },
    );

    test(
      'never back, by more than one, nor with the same or an earlier deadline',
      () async {
        await makeAt(0, 'waitingForBoth');
        for (final change in [
          moveTo('waitingForBoth', by: 2),
          moveTo('waitingForBoth', later: 0),
          moveTo('waitingForBoth', later: -1),
          'take = take - 1',
        ]) {
          await expectLater(
            update(0, change),
            refusedBy(forward),
            reason: change,
          );
        }
        await update(0, moveTo('waitingForEscrow'));
        await expectLater(
          update(0, 'take = 0, take_deadline = take_deadline + 20'),
          refusedBy(forward),
        );
      },
    );

    test(
      'a contract with no deadline is followed by none: its index never moves from a trail that has no contract deadline',
      () async {
        for (final (index, from) in [(0, 'public'), (1, 'waitingForBoth')]) {
          final made = await confirmedMake(index: index, orderId: 100 + index);
          expect(
            await trails.storeTrail(
              made,
              trailOf(orderId: 100 + index, position: from),
            ),
            isA<Ok<TrailStoreOutcome, P2pFailure>>(),
          );
          // A NULL deadline compared with a later one is NULL, never true: the move is refused all the same (functional review of #176, mutant T02).
          await expectLater(
            update(
              index,
              "take = 1, take_deadline = $deadline, position = 'waitingForBoth'",
            ),
            refusedBy(forward),
            reason: from,
          );
        }
      },
    );

    test(
      'its deadline, taker and amount: written once within a contract, changed only by the next, never cleared',
      () async {
        await makeAt(0, 'waitingForBoth');
        for (final change in [
          'take_deadline = take_deadline + 1',
          "taker_hash_id = '$takerTwo'",
          'taken_amount = 80.0',
          'take_deadline = NULL',
          'taker_hash_id = NULL',
          'taken_amount = NULL',
          '${moveTo('waitingForBoth')}, taker_hash_id = NULL',
          '${moveTo('waitingForBoth')}, taken_amount = NULL',
          '${moveTo('waitingForBoth')}, take_deadline = NULL',
        ]) {
          await expectLater(
            update(0, change),
            refusedBy(forward),
            reason: change,
          );
        }
        // A contract of no taker or amount yet: written within it, never in the write that moves it.
        final made = await confirmedMake(index: 1, orderId: 101);
        expect(
          await trails.storeTrail(
            made,
            trailOf(orderId: 101, position: 'public'),
          ),
          isA<Ok<TrailStoreOutcome, P2pFailure>>(),
        );
        await update(1, 'take_deadline = $deadline');
        await expectLater(
          update(1, moveTo('waitingForBoth')),
          refusedBy(forward),
        );
        await expectLater(
          update(
            1,
            "take = 1, take_deadline = take_deadline + 10, position = 'waitingForBoth', taken_amount = 5.0",
          ),
          refusedBy(forward),
        );
        await update(1, "taker_hash_id = '$takerOne', taken_amount = 5.0");
        await update(1, moveTo('waitingForBoth'));
        // The taker of a trail that reached the chat with none: written there.
        final chat = await confirmedMake(index: 2, orderId: 102);
        expect(
          await trails.storeTrail(
            chat,
            trailOf(orderId: 102, position: 'chatting'),
          ),
          isA<Ok<TrailStoreOutcome, P2pFailure>>(),
        );
        await update(2, "taker_hash_id = '$takerOne'");
      },
    );

    test(
      'its escrow pinned within a contract, replaced by another or cleared in the write that moves it, never kept; its bond pinned for good',
      () async {
        await makeAt(0, 'waitingForBoth');
        for (final change in [
          "escrow_hash = '$hashC'",
          'escrow_hash = NULL',
          '${moveTo('waitingForBoth')}, escrow_hash = \'$hashB\'',
          '${moveTo('waitingForBoth')}, bond_hash = \'$hashC\'',
          '${moveTo('waitingForBoth')}, bond_hash = NULL',
        ]) {
          await expectLater(
            update(0, change),
            refusedBy(forward),
            reason: change,
          );
        }
        await update(0, moveTo('waitingForBoth'));
        await makeAt(1, 'waitingForEscrow');
        await update(1, '${moveTo('waitingForPayout')}, escrow_hash = NULL');
        // The escrow of an earlier contract is never pinned again, whatever came in between; another is, within the next.
        await expectLater(
          update(1, "escrow_hash = '$hashB'"),
          refusedBy(forward),
        );
        await update(1, "escrow_hash = '$hashD'");
      },
    );

    test(
      'the escrows of earlier contracts only grow, in the write that moves take; a contract seen late is marked so in that write and stays so (amended by #178 after its security review)',
      () async {
        await makeAt(0, 'waitingForEscrow');
        for (final (label, change) in [
          ('grown without a next contract', "earlier_escrows = '$hashB;'"),
          ('marked late without a next contract', 'seen_late = 1'),
          (
            'a next contract that forgets the escrow it leaves',
            "take = take + 1, take_deadline = take_deadline + 10, position = 'waitingForBoth', taker_hash_id = '$takerTwo', escrow_hash = NULL",
          ),
          (
            'a next contract that writes another escrow as earlier',
            "take = take + 1, take_deadline = take_deadline + 10, position = 'waitingForBoth', taker_hash_id = '$takerTwo', escrow_hash = NULL, earlier_escrows = '$hashD;'",
          ),
          (
            'a next contract at a step marked late',
            '${moveTo('waitingForBoth')}, seen_late = 1',
          ),
          (
            'a contract seen late not marked so',
            "take = take + 1, position = 'chatting', taker_hash_id = '$takerTwo', escrow_hash = NULL, $earlierGrows",
          ),
          (
            'a contract seen late that pins an escrow',
            "take = take + 1, position = 'chatting', taker_hash_id = '$takerTwo', escrow_hash = '$hashC', seen_late = 1, $earlierGrows",
          ),
          (
            'a contract seen late from 7 with the same taker',
            "take = take + 1, position = 'chatting', escrow_hash = NULL, seen_late = 1, $earlierGrows",
          ),
        ]) {
          await expectLater(
            update(0, change),
            refusedBy(forward),
            reason: label,
          );
        }
        // Seen late: marked, and never unmarked while it lasts.
        await update(
          0,
          "take = take + 1, position = 'chatting', taker_hash_id = '$takerTwo', escrow_hash = NULL, seen_late = 1, $earlierGrows",
        );
        await expectLater(update(0, 'seen_late = 0'), refusedBy(forward));
        await update(0, "position = 'fiatSent'");
      },
    );

    test(
      'no next contract from a maker buyer\'s 8, where the order never goes back to the book',
      () async {
        await makeAt(0, 'waitingForPayout', role: TradeRole.buyer);
        await expectLater(
          update(0, moveTo('waitingForBoth')),
          refusedBy(forward),
        );
      },
    );

    test(
      'a take has no contract: none written, none moved, its escrow pinned as before',
      () async {
        final take = await pendingTake();
        expect(await trails.recordTerms(take, takerTerms()), isA<Ok>());
        expect(
          await trails.storeTrail(
            take,
            trailOf(orderId: 7, position: 'waitingForBoth', escrowHash: hashB),
          ),
          isA<Ok<TrailStoreOutcome, P2pFailure>>(),
        );
        for (final change in [
          'take_deadline = 5',
          "taker_hash_id = '$takerOne'",
          'taken_amount = 5.0',
          "take = 1, take_deadline = 5, position = 'waitingForEscrow'",
          "escrow_hash = '$hashC'",
          'escrow_hash = NULL',
        ]) {
          await expectLater(
            update(10, change),
            refusedBy(forward),
            reason: change,
          );
        }
        // Forward as before: written.
        await update(10, "position = 'waitingForEscrow'");
      },
    );
  });

  group('the payments of a make', () {
    Future<TradeRecord> makeAtContract() async {
      final made = await confirmedMake();
      expect(
        await trails.storeTrail(
          made,
          trailOf(position: 'waitingForEscrow', takeDeadline: deadline),
        ),
        isA<Ok<TrailStoreOutcome, P2pFailure>>(),
      );
      return made;
    }

    test(
      'keep what each payment takes out of the wallet with its start, never lower, never invented, never cleared (schema 9, #233)',
      () async {
        final made = await makeAtContract();
        Future<Sats?> kept() async =>
            switch (await payments.paymentOf(made, InvoiceStep.escrow)) {
              Ok(value: final payment?) => payment.confirmedSats,
              final other => fail('$other'),
            };
        expect(
          valueOf(
            await payments.recordStart(
              made,
              InvoiceStep.escrow,
              paymentHash: hashA,
              at: testNow,
              sats: Sats.fromInt(200150),
            ),
          ),
          isTrue,
        );
        expect(await kept(), Sats.fromInt(200150));
        // A new attempt of the same invoice with a cheaper quote: an earlier attempt may still hold its funds, so the larger stays.
        expect(
          valueOf(
            await payments.recordStart(
              made,
              InvoiceStep.escrow,
              paymentHash: hashA,
              at: testNow.add(const Duration(seconds: 1)),
              sats: Sats.fromInt(200100),
            ),
          ),
          isTrue,
        );
        expect(await kept(), Sats.fromInt(200150));
        expect(
          valueOf(
            await payments.recordStart(
              made,
              InvoiceStep.escrow,
              paymentHash: hashA,
              at: testNow.add(const Duration(seconds: 2)),
              sats: Sats.fromInt(200400),
            ),
          ),
          isTrue,
        );
        expect(await kept(), Sats.fromInt(200400));
        // An amount the records cannot hold is refused before anything is written: the wallet is never asked.
        expect(
          await payments.recordStart(
            made,
            InvoiceStep.escrow,
            paymentHash: hashA,
            at: testNow.add(const Duration(seconds: 3)),
            sats: Sats(BigInt.from(2100000000000001)),
          ),
          refusedWith<P2pStorageFailure>(),
        );
        expect(
          await payments.recordStart(
            made,
            InvoiceStep.escrow,
            paymentHash: hashA,
            at: testNow.add(const Duration(seconds: 3)),
            sats: Sats(BigInt.two.pow(64)),
          ),
          refusedWith<P2pStorageFailure>(),
        );
        expect(await kept(), Sats.fromInt(200400));
        // Whatever the code, the database: no payment without its amount, never lowered nor cleared.
        for (final (statement, message) in [
          (
            "INSERT INTO trade_payments (key_fingerprint, robot_index, step, take, payment_hash, started_at) VALUES ('${made.robot.keyFingerprint.hex}', ${made.robot.accountIndex}, 'bond', 0, '${'0f' * 32}', 0)",
            'a payment is recorded with its amount',
          ),
          (
            'UPDATE trade_payments SET confirmed_sats = 200399 WHERE robot_index = ${made.robot.accountIndex}',
            'the amount of a payment never goes down',
          ),
          (
            'UPDATE trade_payments SET confirmed_sats = NULL WHERE robot_index = ${made.robot.accountIndex}',
            'the amount of a payment never goes down',
          ),
        ]) {
          await expectLater(
            database.customStatement(statement),
            throwsA(predicate((error) => '$error'.contains(message))),
            reason: statement,
          );
        }
        expect(await kept(), Sats.fromInt(200400));
      },
    );

    test(
      'are one per contract, at the contract the trail is at, and read by it',
      () async {
        final made = await makeAtContract();
        final at = testNow;
        expect(
          valueOf(
            await payments.recordStart(
              made,
              InvoiceStep.escrow,
              paymentHash: hashA,
              at: at,
              sats: Sats.fromInt(5000),
            ),
          ),
          isTrue,
        );
        // Contract 1 is not the trail's yet.
        expect(
          await payments.recordStart(
            made,
            InvoiceStep.escrow,
            paymentHash: hashB,
            at: at,
            sats: Sats.fromInt(5000),
            take: 1,
          ),
          refusedWith<P2pStorageFailure>(),
        );
        expect(
          await trails.storeTrail(
            made,
            trailOf(
              readAt: 2000,
              position: 'waitingForEscrow',
              take: 1,
              takeDeadline: deadline + 1,
            ),
          ),
          isA<Ok<TrailStoreOutcome, P2pFailure>>(),
        );
        expect(
          valueOf(
            await payments.recordStart(
              made,
              InvoiceStep.escrow,
              paymentHash: hashB,
              at: at,
              sats: Sats.fromInt(5000),
              take: 1,
            ),
          ),
          isTrue,
        );
        // Neither a contract the trail has not reached nor one it has left takes a first payment; a new attempt of an invoice already recorded is written.
        expect(
          await payments.recordStart(
            made,
            InvoiceStep.escrow,
            paymentHash: hashC,
            at: at,
            sats: Sats.fromInt(5000),
            take: 2,
          ),
          refusedWith<P2pStorageFailure>(),
        );
        expect(
          await payments.recordStart(
            made,
            InvoiceStep.bond,
            paymentHash: hashD,
            at: at,
            sats: Sats.fromInt(5000),
          ),
          refusedWith<P2pStorageFailure>(),
        );
        expect(
          valueOf(
            await payments.recordStart(
              made,
              InvoiceStep.escrow,
              paymentHash: hashA,
              at: at.add(const Duration(seconds: 1)),
              sats: Sats.fromInt(5000),
            ),
          ),
          isTrue,
        );
        expect(
          valueOf(
            await payments.recordWalletPayment(
              made,
              InvoiceStep.escrow,
              paymentHash: hashB,
              walletPaymentId: 'swap-1',
              take: 1,
            ),
          ),
          isTrue,
        );
        expect(
          valueOf(
            await payments.recordWalletPayment(
              made,
              InvoiceStep.escrow,
              paymentHash: hashB,
              walletPaymentId: 'swap-1',
            ),
          ),
          isFalse,
        );
        expect(
          valueOf(await payments.paymentOf(made, InvoiceStep.escrow)),
          TradePaymentRecord(
            step: InvoiceStep.escrow,
            paymentHash: hashA,
            startedAt: at.add(const Duration(seconds: 1)),
            confirmedSats: Sats.fromInt(5000),
          ),
        );
        expect(
          valueOf(await payments.paymentOf(made, InvoiceStep.escrow, take: 1)),
          TradePaymentRecord(
            step: InvoiceStep.escrow,
            paymentHash: hashB,
            startedAt: at,
            walletPaymentId: 'swap-1',
            take: 1,
            confirmedSats: Sats.fromInt(5000),
          ),
        );
        expect(
          valueOf(await payments.paymentOf(made, InvoiceStep.escrow, take: 2)),
          isNull,
        );
      },
    );

    test('pay each invoice once, whatever the trade, step or contract', () async {
      const once = 'an invoice is paid once';
      final made = await makeAtContract();
      expect(
        valueOf(
          await payments.recordStart(
            made,
            InvoiceStep.escrow,
            paymentHash: hashA,
            at: testNow,
            sats: Sats.fromInt(5000),
          ),
        ),
        isTrue,
      );
      // The same hash as this trade's bond, as another trade's bond: refused.
      expect(
        await payments.recordStart(
          made,
          InvoiceStep.bond,
          paymentHash: hashA,
          at: testNow,
          sats: Sats.fromInt(5000),
        ),
        refusedWith<P2pStorageFailure>(),
      );
      final take = await pendingTake();
      expect(await trails.recordTerms(take, takerTerms()), isA<Ok>());
      expect(
        await trails.storeTrail(take, trailOf(orderId: 7, position: 'start')),
        isA<Ok<TrailStoreOutcome, P2pFailure>>(),
      );
      expect(
        await payments.recordStart(
          take,
          InvoiceStep.bond,
          paymentHash: hashA,
          at: testNow,
          sats: Sats.fromInt(5000),
        ),
        refusedWith<P2pStorageFailure>(),
      );
      await expectLater(
        database.customStatement(
          "INSERT INTO trade_payments (key_fingerprint, robot_index, step, take, payment_hash, started_at, confirmed_sats) VALUES (?, 10, 'bond', 0, ?, 0, 5000)",
          [fingerprint.hex, hashA],
        ),
        refusedBy(once),
      );
      // Its own row written again writes nothing, as before.
      await database.customStatement(
        "INSERT INTO trade_payments (key_fingerprint, robot_index, step, take, payment_hash, started_at, confirmed_sats) VALUES (?, 0, 'escrow', 0, ?, 0, 5000)",
        [fingerprint.hex, hashA],
      );
      // Another hash: the take's bond, paid.
      expect(
        valueOf(
          await payments.recordStart(
            take,
            InvoiceStep.bond,
            paymentHash: hashB,
            at: testNow,
            sats: Sats.fromInt(5000),
          ),
        ),
        isTrue,
      );
    });

    test(
      'pay a hash once whatever differs: the contract, the robot or the key',
      () async {
        const once = 'an invoice is paid once';
        final made = await makeAtContract();
        expect(
          valueOf(
            await payments.recordStart(
              made,
              InvoiceStep.escrow,
              paymentHash: hashA,
              at: testNow,
              sats: Sats.fromInt(5000),
            ),
          ),
          isTrue,
        );
        // The trigger that asks for the trail's contract is set aside, so that the rule of one hash is tried alone, each key apart.
        await database.customStatement(
          'DROP TRIGGER trade_payments_of_their_trade',
        );
        await pendingTake();
        final otherKey = 'e' * 64;
        await database.customStatement(
          "INSERT INTO robot_bindings VALUES ('testnet', ?, 0, 'temple', 'http://temple.onion', '', 'nostr', 10, 'generated')",
          [otherKey],
        );
        await database.customStatement(
          "INSERT INTO trades VALUES ('testnet', ?, 0, 'temple', 'http://temple.onion', 77, 'buyer', 'takenHere', 1, NULL, NULL)",
          [otherKey],
        );
        for (final (label, key, index, take) in [
          (
            'another contract of the same trade and step',
            fingerprint.hex,
            0,
            1,
          ),
          ('another robot of the same key', fingerprint.hex, 10, 0),
          ('the same robot index of another key', otherKey, 0, 0),
        ]) {
          await expectLater(
            database.customStatement(
              "INSERT INTO trade_payments (key_fingerprint, robot_index, step, take, payment_hash, started_at, confirmed_sats) VALUES (?, ?, 'escrow', ?, ?, 0, 5000)",
              [key, index, take, hashA],
            ),
            refusedBy(once),
            reason: label,
          );
        }
      },
    );

    test(
      'never change their contract, and a bond, and a take, have contract 0 only',
      () async {
        final made = await makeAtContract();
        expect(
          valueOf(
            await payments.recordStart(
              made,
              InvoiceStep.escrow,
              paymentHash: hashA,
              at: testNow,
              sats: Sats.fromInt(5000),
            ),
          ),
          isTrue,
        );
        await expectLater(
          database.customStatement('UPDATE trade_payments SET take = 1'),
          refusedBy('a payment only moves forward'),
        );
        await expectLater(
          database.customStatement(
            "INSERT INTO trade_payments (key_fingerprint, robot_index, step, take, payment_hash, started_at, confirmed_sats) VALUES (?, 0, 'bond', 1, ?, 0, 5000)",
            [fingerprint.hex, hashB],
          ),
          refusedBy(check, 'a payment of no open trade'),
        );
        await expectLater(
          database.customStatement(
            "INSERT INTO trade_payments (key_fingerprint, robot_index, step, take, payment_hash, started_at, confirmed_sats) VALUES (?, 0, 'escrow', -1, ?, 0, 5000)",
            [fingerprint.hex, hashB],
          ),
          refusedBy(check, 'a payment of no open trade'),
        );
        // With the trigger set aside, the CHECKs alone refuse them.
        await database.customStatement(
          'DROP TRIGGER trade_payments_of_their_trade',
        );
        for (final (step, take) in [
          ('bond', 1),
          ('escrow', -1),
          ('escrow', 'one'),
        ]) {
          await expectLater(
            database.customStatement(
              'INSERT INTO trade_payments (key_fingerprint, robot_index, step, take, payment_hash, started_at, confirmed_sats) VALUES (?, 0, ?, ?, ?, 0, 5000)',
              [fingerprint.hex, step, take, hashC],
            ),
            refusedBy(check),
            reason: '$step $take',
          );
        }
      },
    );

    test(
      'of a take, at a later contract, are refused: a take has one',
      () async {
        final take = await pendingTake();
        expect(await trails.recordTerms(take, takerTerms()), isA<Ok>());
        expect(
          await trails.storeTrail(take, trailOf(orderId: 7, position: 'start')),
          isA<Ok<TrailStoreOutcome, P2pFailure>>(),
        );
        expect(
          await payments.recordStart(
            take,
            InvoiceStep.escrow,
            paymentHash: hashA,
            at: testNow,
            sats: Sats.fromInt(5000),
            take: 1,
          ),
          refusedWith<P2pStorageFailure>(),
        );
        expect(
          valueOf(
            await payments.recordStart(
              take,
              InvoiceStep.bond,
              paymentHash: hashA,
              at: testNow,
              sats: Sats.fromInt(5000),
            ),
          ),
          isTrue,
        );
      },
    );
  });

  group('whyNotReplace keeps a contract moving forward', () {
    final stored = trailOf(
      readAt: 1000,
      position: 'waitingForEscrow',
      takeDeadline: deadline,
      takerHashId: takerOne,
      takenAmount: 75.5,
    );

    test('a next contract with a later deadline replaces it', () {
      for (final position in [
        'waitingForBoth',
        'waitingForEscrow',
        'waitingForPayout',
      ]) {
        expect(
          trailOf(
            readAt: 2000,
            position: position,
            take: 1,
            takeDeadline: deadline + 1,
            takerHashId: takerTwo,
            takenAmount: 80,
          ).whyNotReplace(stored, madeHere: true),
          isNot(TrailReplacementRefusal.contractMoved),
          reason: position,
        );
      }
      expect(
        trailOf(
          readAt: 2000,
          position: 'waitingForEscrow',
          take: 1,
          takeDeadline: deadline + 1,
          takerHashId: takerTwo,
          takenAmount: 80,
        ).whyNotReplace(stored, madeHere: true),
        isNull,
      );
      // Within a contract, a deadline, taker or amount written for the first time.
      expect(
        trailOf(
          readAt: 2000,
          position: 'waitingForEscrow',
        ).whyNotReplace(trailOf(position: 'waitingForEscrow'), madeHere: true),
        isNull,
      );
      expect(
        trailOf(
          readAt: 2000,
          position: 'waitingForEscrow',
          takeDeadline: deadline,
        ).whyNotReplace(trailOf(position: 'waitingForEscrow'), madeHere: true),
        isNull,
      );
    });

    test('anything else is contractMoved', () {
      for (final (label, trail) in [
        ('back', trailOf(readAt: 2000, position: 'waitingForEscrow', take: -1)),
        (
          'by two',
          trailOf(
            readAt: 2000,
            position: 'waitingForEscrow',
            take: 2,
            takeDeadline: deadline + 1,
            takerHashId: takerTwo,
            takenAmount: 80,
          ),
        ),
        (
          'the same deadline',
          trailOf(
            readAt: 2000,
            position: 'waitingForEscrow',
            take: 1,
            takeDeadline: deadline,
            takerHashId: takerTwo,
            takenAmount: 80,
          ),
        ),
        (
          'an earlier deadline',
          trailOf(
            readAt: 2000,
            position: 'waitingForEscrow',
            take: 1,
            takeDeadline: deadline - 1,
            takerHashId: takerTwo,
            takenAmount: 80,
          ),
        ),
        (
          'no deadline',
          trailOf(
            readAt: 2000,
            position: 'waitingForEscrow',
            take: 1,
            takerHashId: takerTwo,
            takenAmount: 80,
          ),
        ),
        (
          'to the chat',
          trailOf(
            readAt: 2000,
            position: 'chatting',
            take: 1,
            takeDeadline: deadline + 1,
            takerHashId: takerTwo,
            takenAmount: 80,
          ),
        ),
        (
          'a taker cleared at the next',
          trailOf(
            readAt: 2000,
            position: 'waitingForEscrow',
            take: 1,
            takeDeadline: deadline + 1,
            takenAmount: 80,
          ),
        ),
        (
          'an amount cleared at the next',
          trailOf(
            readAt: 2000,
            position: 'waitingForEscrow',
            take: 1,
            takeDeadline: deadline + 1,
            takerHashId: takerTwo,
          ),
        ),
        (
          'another deadline within the contract',
          trailOf(
            readAt: 2000,
            position: 'waitingForEscrow',
            takeDeadline: deadline + 1,
            takerHashId: takerOne,
            takenAmount: 75.5,
          ),
        ),
        (
          'another taker within the contract',
          trailOf(
            readAt: 2000,
            position: 'waitingForEscrow',
            takeDeadline: deadline,
            takerHashId: takerTwo,
            takenAmount: 75.5,
          ),
        ),
        (
          'another amount within the contract',
          trailOf(
            readAt: 2000,
            position: 'waitingForEscrow',
            takeDeadline: deadline,
            takerHashId: takerOne,
            takenAmount: 80,
          ),
        ),
        (
          'a deadline cleared',
          trailOf(
            readAt: 2000,
            position: 'waitingForEscrow',
            takerHashId: takerOne,
            takenAmount: 75.5,
          ),
        ),
      ]) {
        expect(
          trail.whyNotReplace(stored, madeHere: true),
          TrailReplacementRefusal.contractMoved,
          reason: label,
        );
      }
      // From a contract of no deadline, no next one.
      expect(
        trailOf(
          readAt: 2000,
          position: 'waitingForEscrow',
          take: 1,
          takeDeadline: deadline,
        ).whyNotReplace(trailOf(position: 'public'), madeHere: true),
        TrailReplacementRefusal.contractMoved,
      );
      // At the next, a taker or an amount written for the first time.
      expect(
        trailOf(
          readAt: 2000,
          position: 'waitingForEscrow',
          take: 1,
          takeDeadline: deadline + 1,
          takerHashId: takerTwo,
        ).whyNotReplace(
          trailOf(position: 'waitingForEscrow', takeDeadline: deadline),
          madeHere: true,
        ),
        TrailReplacementRefusal.contractMoved,
      );
    });

    test(
      'a next contract seen late: the same deadline, a taker, from the chat on',
      () {
        final kept = trailOf(
          readAt: 1000,
          position: 'public',
          takeDeadline: deadline,
          takerHashId: takerOne,
        );
        TradeTrailRecord late({
          String position = 'succeeded',
          int? takeDeadline,
          String? takerHashId,
        }) => trailOf(
          readAt: 2000,
          position: position,
          take: 1,
          takeDeadline: takeDeadline ?? deadline,
          takerHashId: takerHashId ?? takerTwo,
          seenLate: true,
        );
        expect(late().whyNotReplace(kept, madeHere: true), isNull);
        expect(
          late(position: 'chatting').whyNotReplace(kept, madeHere: true),
          isNull,
        );
        for (final (label, trail) in [
          ('another deadline', late(takeDeadline: deadline + 1)),
          ('to an end with no contract', late(position: 'expired')),
        ]) {
          expect(
            trail.whyNotReplace(kept, madeHere: true),
            isNotNull,
            reason: label,
          );
        }
        expect(
          late().whyNotReplace(
            trailOf(
              readAt: 1000,
              position: 'chatting',
              takeDeadline: deadline,
              takerHashId: takerOne,
            ),
            madeHere: true,
          ),
          TrailReplacementRefusal.contractMoved,
        );
      },
    );

    test(
      'whyNotReplace says the trigger\'s rule exactly: role, escrow, taker, mark and earlier escrows (security review of #178)',
      () {
        TradeTrailRecord at(
          String position, {
          String role = 'seller',
          int readAt = 1000,
          int take = 0,
          int? takeDeadline,
          String? taker,
          String? escrow,
          String earlier = '',
          bool late = false,
        }) => trailOf(
          role: role,
          readAt: readAt,
          position: position,
          take: take,
          takeDeadline: takeDeadline ?? deadline,
          takerHashId: taker ?? takerOne,
          escrowHash: escrow,
          earlierEscrows: earlier,
          seenLate: late,
        );
        final fromSeven = at('waitingForEscrow');
        TradeTrailRecord late({
          String? taker,
          String? escrow,
          bool mark = true,
        }) => at(
          'chatting',
          readAt: 2000,
          take: 1,
          taker: taker ?? takerTwo,
          escrow: escrow,
          late: mark,
        );
        expect(late().whyNotReplace(fromSeven, madeHere: true), isNull);
        for (final (label, trail) in [
          ('a contract seen late with an escrow', late(escrow: hashC)),
          (
            'a contract seen late from 7 with the same taker',
            late(taker: takerOne),
          ),
          ('a contract seen late not marked', late(mark: false)),
          (
            'a next contract at a step marked late',
            at(
              'waitingForBoth',
              readAt: 2000,
              take: 1,
              takeDeadline: deadline + 1,
              taker: takerTwo,
              late: true,
            ),
          ),
        ]) {
          expect(
            trail.whyNotReplace(fromSeven, madeHere: true),
            TrailReplacementRefusal.contractMoved,
            reason: label,
          );
        }
        // No next contract from a maker buyer's 8, where the order never goes back to the book; from a maker seller's, one.
        for (final (role, refused) in [('buyer', true), ('seller', false)]) {
          final eight = at('waitingForPayout', role: role);
          final next = at(
            'waitingForBoth',
            role: role,
            readAt: 2000,
            take: 1,
            takeDeadline: deadline + 1,
            taker: takerTwo,
          );
          expect(
            next.whyNotReplace(eight, madeHere: true),
            refused ? TrailReplacementRefusal.contractMoved : isNull,
            reason: role,
          );
        }
        // Within a contract, neither the earlier escrows nor the mark change.
        final later = at('chatting', take: 1, earlier: '$hashA;', late: true);
        for (final (label, trail) in [
          (
            'earlier escrows grown',
            at(
              'fiatSent',
              readAt: 2000,
              take: 1,
              earlier: '$hashA;$hashB;',
              late: true,
            ),
          ),
          (
            'earlier escrows cleared',
            at('fiatSent', readAt: 2000, take: 1, late: true),
          ),
          (
            'the mark cleared',
            at('fiatSent', readAt: 2000, take: 1, earlier: '$hashA;'),
          ),
        ]) {
          expect(
            trail.whyNotReplace(later, madeHere: true),
            TrailReplacementRefusal.contractMoved,
            reason: label,
          );
        }
        expect(
          at(
            'fiatSent',
            readAt: 2000,
            take: 1,
            earlier: '$hashA;',
            late: true,
          ).whyNotReplace(later, madeHere: true),
          isNull,
        );
      },
    );

    test(
      'the escrow at a next contract: cleared or replaced by another, never kept; within a contract, kept',
      () {
        final pinned = trailOf(
          readAt: 1000,
          position: 'waitingForEscrow',
          escrowHash: hashA,
          takeDeadline: deadline,
          takerHashId: takerOne,
        );
        TradeTrailRecord nextWith(String? escrow, {String? earlier}) => trailOf(
          readAt: 2000,
          position: 'waitingForBoth',
          escrowHash: escrow,
          take: 1,
          takeDeadline: deadline + 1,
          takerHashId: takerTwo,
          earlierEscrows: earlier ?? '$hashA;',
        );
        expect(nextWith(null).whyNotReplace(pinned, madeHere: true), isNull);
        expect(nextWith(hashB).whyNotReplace(pinned, madeHere: true), isNull);
        expect(
          nextWith(hashA).whyNotReplace(pinned, madeHere: true),
          TrailReplacementRefusal.hashChanged,
        );
        // The escrow it leaves joins the earlier ones, exactly, and stays there.
        for (final earlier in ['', '$hashB;', '$hashA;$hashA;']) {
          expect(
            nextWith(
              null,
              earlier: earlier,
            ).whyNotReplace(pinned, madeHere: true),
            TrailReplacementRefusal.contractMoved,
            reason: earlier,
          );
        }
        expect(
          trailOf(
            readAt: 3000,
            position: 'waitingForBoth',
            escrowHash: hashA,
            take: 1,
            takeDeadline: deadline + 1,
            takerHashId: takerTwo,
            earlierEscrows: '$hashA;',
          ).whyNotReplace(nextWith(null), madeHere: true),
          TrailReplacementRefusal.hashChanged,
        );
        TradeTrailRecord sameWith(String? escrow) => trailOf(
          readAt: 2000,
          position: 'chatting',
          escrowHash: escrow,
          takeDeadline: deadline,
          takerHashId: takerOne,
        );
        expect(sameWith(hashA).whyNotReplace(pinned, madeHere: true), isNull);
        for (final escrow in [null, hashB]) {
          expect(
            sameWith(escrow).whyNotReplace(pinned, madeHere: true),
            TrailReplacementRefusal.hashChanged,
          );
        }
      },
    );

    test('a taker trail, with no contract, is replaced as before', () {
      final before = trailOf(orderId: 7, position: 'waitingForBoth');
      expect(
        trailOf(
          orderId: 7,
          readAt: 2000,
          position: 'waitingForEscrow',
        ).whyNotReplace(before, madeHere: false),
        isNull,
      );
      // A trade not made here never has a contract (#178), as the trigger says.
      for (final trail in [
        trailOf(orderId: 7, readAt: 2000, takeDeadline: deadline),
        trailOf(orderId: 7, readAt: 2000, takerHashId: takerOne),
        trailOf(orderId: 7, readAt: 2000, takenAmount: 80),
      ]) {
        expect(
          trail.whyNotReplace(before, madeHere: false),
          TrailReplacementRefusal.contractMoved,
        );
        expect(trail.whyNotReplace(before, madeHere: true), isNull);
      }
    });
  });
}
