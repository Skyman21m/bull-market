import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/data/trade_trail_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/robot_bindings.dart';

/// The terms and the trail of each trade in the feature's database (schema 4, #87): the terms written once, the trail only forward, every write of a trail asked of `whyNotReplace` first and made only over the trail it compared, and the database's own triggers, tried with raw SQL.
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
  final temple = switch (CoordinatorIdentity.of(coordinator('temple'), testnet)) {
    final identity? => identity,
    null => throw StateError('temple is not on testnet'),
  };

  const hashA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const hashB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  final takenAt = testNow.microsecondsSinceEpoch;

  TradeTermsRecord termsOf({int orderId = 7, double amount = 100}) =>
      TradeTermsRecord(
        version: 1,
        network: 'testnet',
        coordinatorAlias: 'temple',
        orderId: orderId,
        role: 'buyer',
        type: 1,
        currencyId: 2,
        amount: amount,
        isRange: false,
        premiumPercent: 2,
        explicitSatoshis: null,
        bondSizePercent: 3,
        escrowSeconds: 10800,
        bookPrice: 93545.25,
        takerFee: 0.00175,
      );

  TradeTrailRecord trailOf({
    String position = 'start',
    int? readAt,
    String? bondHash,
    String? escrowHash,
    int? bondStepSeenAt,
    int? bondStepDeadline,
    bool breached = false,
    bool historyUnknown = false,
    int version = 1,
    int orderId = 7,
  }) => TradeTrailRecord(
    version: version,
    network: 'testnet',
    coordinatorAlias: 'temple',
    orderId: orderId,
    role: 'buyer',
    position: position,
    readAtMicros: readAt ?? takenAt,
    bondHash: bondHash,
    escrowHash: escrowHash,
    deadlineMicros: null,
    bondStepSeenAtMicros: bondStepSeenAt,
    bondStepDeadlineMicros: bondStepDeadline,
    breached: breached,
    historyUnknown: historyUnknown,
  );

  int at(int seconds) => takenAt + seconds * 1000000;

  late P2pDatabase database;
  late RobotBindingRepositoryImpl bindings;
  late TradeRecordRepositoryImpl trades;
  late TradeTrailRepositoryImpl trails;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = P2pDatabase.forTesting(NativeDatabase.memory());
    bindings = bindingsInMemory(database: database);
    trades = TradeRecordRepositoryImpl(database, clock: () => testNow);
    trails = TradeTrailRepositoryImpl(database);
  });

  tearDown(() => database.close());

  /// The pending take of order [orderId] by robot [index] of the key, on temple.
  Future<TradeRecord> pendingTake({int index = 0, int orderId = 7}) async {
    expect(await bindings.recordGeneratedKey(testnet, fingerprint), isA<Ok>());
    final reservation = switch (await trades.reserveForNewTrade(
      RobotSlot(testnet, fingerprint, index),
      temple,
    )) {
      Ok(value: final reservation?) => reservation,
      final other => fail('not reserved: $other'),
    };
    return switch (await trades.recordPendingTake(
      reservation,
      orderId: orderId,
      role: TradeRole.buyer,
    )) {
      Ok(:final value) => value,
      Err(:final failure) => fail('$failure'),
    };
  }

  /// A pending take with its terms and the first trail of [first].
  Future<TradeRecord> recorded([TradeTrailRecord? first]) async {
    final trade = await pendingTake();
    expect(await trails.recordTerms(trade, termsOf()), isA<Ok>());
    expect(
      await trails.storeTrail(trade, first ?? trailOf()),
      isA<Ok<TrailStoreOutcome, P2pFailure>>().having(
        (ok) => ok.value,
        'outcome',
        isA<TrailStored>(),
      ),
    );
    return trade;
  }

  Future<StoredTradeHistory> historyOf(TradeRecord trade) async =>
      switch (await trails.historyOf(trade)) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };

  Matcher storedTrail(TradeTrailRecord trail) =>
      isA<Ok<TrailStoreOutcome, P2pFailure>>().having(
        (ok) => ok.value,
        'outcome',
        isA<TrailStored>().having((s) => s.stored, 'stored', trail),
      );
  Matcher keptTrail(
    TradeTrailRecord stored, {
    required TrailReplacementRefusal? reason,
  }) => isA<Ok<TrailStoreOutcome, P2pFailure>>().having(
    (ok) => ok.value,
    'outcome',
    isA<TrailKept>()
        .having((k) => k.stored, 'stored', stored)
        .having((k) => k.reason, 'reason', reason),
  );
  Matcher refusedWith<T>() => isA<Err<Object?, P2pFailure>>().having(
    (err) => err.failure,
    'failure',
    isA<T>(),
  );

  group('the terms', () {
    test('are written once, read back as they were, and never again', () async {
      final trade = await pendingTake();
      expect(await historyOf(trade), const StoredTradeHistory(terms: null, trail: null));

      expect(await trails.recordTerms(trade, termsOf()), isA<Ok>());
      expect((await historyOf(trade)).terms, termsOf());

      expect(
        await trails.recordTerms(trade, termsOf(amount: 50)),
        refusedWith<TradeAlreadyRecordedFailure>(),
      );
      expect((await historyOf(trade)).terms, termsOf());
    });

    test('of another order, or of a closed trade, are refused by the database', () async {
      final trade = await pendingTake();
      expect(
        await trails.recordTerms(trade, termsOf(orderId: 8)),
        refusedWith<P2pStorageFailure>(),
      );
      final closed = switch (await trades.closeTrade(trade)) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(
        await trails.recordTerms(closed, termsOf()),
        refusedWith<P2pStorageFailure>(),
      );
      expect((await historyOf(trade)).terms, isNull);
    });
  });

  group('the trail', () {
    test('needs the terms of an open trade first', () async {
      final trade = await pendingTake();
      expect(
        await trails.storeTrail(trade, trailOf()),
        refusedWith<P2pStorageFailure>(),
      );
      expect((await historyOf(trade)).trail, isNull);
    });

    test('moves forward along the edges of the trade', () async {
      final trade = await recorded();
      final bondStep = trailOf(
        position: 'bondStep',
        readAt: at(10),
        bondHash: hashA,
        bondStepSeenAt: at(10),
        bondStepDeadline: at(200),
      );
      expect(await trails.storeTrail(trade, bondStep), storedTrail(bondStep));
      final locked = trailOf(
        position: 'waitingForBoth',
        readAt: at(20),
        bondHash: hashA,
        bondStepSeenAt: at(10),
        bondStepDeadline: at(200),
      );
      expect(await trails.storeTrail(trade, locked), storedTrail(locked));
      expect((await historyOf(trade)).trail, locked);
    });

    test('is never replaced as whyNotReplace refuses, and nothing is written', () async {
      final bondStep = trailOf(
        position: 'bondStep',
        readAt: at(10),
        bondHash: hashA,
        bondStepSeenAt: at(10),
        bondStepDeadline: at(200),
        breached: true,
      );
      final trade = await recorded(bondStep);
      for (final (label, trail, reason) in [
        (
          'an earlier read',
          trailOf(
            position: 'bondStep',
            readAt: at(5),
            bondHash: hashA,
            bondStepSeenAt: at(5),
            bondStepDeadline: at(200),
            breached: true,
          ),
          TrailReplacementRefusal.earlierRead,
        ),
        (
          'a breach cleared',
          trailOf(
            position: 'bondStep',
            readAt: at(20),
            bondHash: hashA,
            bondStepSeenAt: at(20),
            bondStepDeadline: at(200),
          ),
          TrailReplacementRefusal.breachCleared,
        ),
        (
          'another bond invoice',
          trailOf(
            position: 'bondStep',
            readAt: at(20),
            bondHash: hashB,
            bondStepSeenAt: at(20),
            bondStepDeadline: at(200),
            breached: true,
          ),
          TrailReplacementRefusal.hashChanged,
        ),
        (
          'the history made unknown',
          trailOf(
            position: 'bondStep',
            readAt: at(20),
            bondHash: hashA,
            bondStepSeenAt: at(20),
            bondStepDeadline: at(200),
            breached: true,
            historyUnknown: true,
          ),
          TrailReplacementRefusal.historyChanged,
        ),
        (
          'another order',
          trailOf(
            position: 'bondStep',
            readAt: at(20),
            bondHash: hashA,
            bondStepSeenAt: at(20),
            bondStepDeadline: at(200),
            breached: true,
            orderId: 8,
          ),
          TrailReplacementRefusal.otherTrade,
        ),
      ]) {
        expect(
          await trails.storeTrail(trade, trail),
          keptTrail(bondStep, reason: reason),
          reason: label,
        );
        expect((await historyOf(trade)).trail, bondStep, reason: label);
      }
    });

    test('moves along no edge only with a breach, and never out of an end', () async {
      final bondStep = trailOf(
        position: 'bondStep',
        readAt: at(10),
        bondHash: hashA,
        bondStepSeenAt: at(10),
        bondStepDeadline: at(200),
      );
      final trade = await recorded(bondStep);
      // Back to the start, which no edge reaches: refused without a breach.
      final skipped = trailOf(
        position: 'start',
        readAt: at(20),
        bondHash: hashA,
        bondStepSeenAt: at(10),
        bondStepDeadline: at(200),
      );
      expect(
        await trails.storeTrail(trade, skipped),
        keptTrail(bondStep, reason: TrailReplacementRefusal.positionMoved),
      );
      final ended = trailOf(
        position: 'publicAgain',
        readAt: at(30),
        bondHash: hashA,
        bondStepSeenAt: at(10),
        bondStepDeadline: at(200),
      );
      expect(await trails.storeTrail(trade, ended), storedTrail(ended));
      final revived = trailOf(
        position: 'bondStep',
        readAt: at(40),
        bondHash: hashA,
        bondStepSeenAt: at(40),
        bondStepDeadline: at(200),
        breached: true,
      );
      expect(
        await trails.storeTrail(trade, revived),
        keptTrail(ended, reason: TrailReplacementRefusal.positionMoved),
      );
    });

    test('a write that lost a race to another is refused, not applied', () async {
      final trade = await recorded();
      final first = trailOf(
        position: 'bondStep',
        readAt: at(10),
        bondHash: hashA,
        bondStepSeenAt: at(10),
        bondStepDeadline: at(200),
      );
      final second = trailOf(
        position: 'bondStep',
        readAt: at(20),
        bondHash: hashA,
        bondStepSeenAt: at(20),
        bondStepDeadline: at(200),
      );
      // Both read the same stored trail before either writes.
      final outcomes = await Future.wait([
        trails.storeTrail(trade, first),
        trails.storeTrail(trade, second),
      ]);
      final stored = [
        for (final outcome in outcomes)
          if (outcome case Ok(value: TrailStored(:final stored))) stored,
      ];
      final kept = [
        for (final outcome in outcomes)
          if (outcome case Ok(value: final TrailKept kept)) kept,
      ];
      expect(stored, hasLength(1));
      expect(kept, hasLength(1));
      expect(kept.single.reason, isNull);
      expect(kept.single.stored, stored.single);
      expect((await historyOf(trade)).trail, stored.single);
    });

    test('of a closed trade is never written again', () async {
      final trade = await recorded();
      expect(await trades.closeTrade(trade), isA<Ok>());
      final later = trailOf(position: 'publicAgain', readAt: at(10));
      expect(await trails.storeTrail(trade, later), keptTrail(trailOf(), reason: null));
      expect((await historyOf(trade)).trail, trailOf());
    });

    test('is watched with the terms, by robot', () async {
      final trade = await recorded();
      final first = await trails.watchHistories(testnet).first;
      expect(
        first,
        isA<Ok<Map<RobotSlot, StoredTradeHistory>, P2pFailure>>().having(
          (ok) => ok.value,
          'histories',
          {trade.robot: StoredTradeHistory(terms: termsOf(), trail: trailOf())},
        ),
      );
      expect(
        await trails.watchHistories(RobosatsNetwork.mainnet).first,
        isA<Ok<Map<RobotSlot, StoredTradeHistory>, P2pFailure>>().having(
          (ok) => ok.value,
          'histories',
          isEmpty,
        ),
      );
    });

    test('a row of another type than this code writes is read as unreadable', () async {
      final trade = await recorded();
      // A REAL in an INTEGER column passes the bounds, and is not a time this code writes.
      await database.customStatement(
        'UPDATE trade_trails SET read_at = ? WHERE robot_index = 0',
        [at(10) + 0.5],
      );
      final history = await historyOf(trade);
      expect(history.unreadable, isTrue);
      expect(history.trail, isNull);
      expect(
        await trails.storeTrail(trade, trailOf(readAt: at(20))),
        refusedWith<P2pStorageFailure>(),
      );
    });
  });

  group('the database refuses, whatever the code,', () {
    Matcher refusedBy(String code) =>
        throwsA(predicate((error) => '$error'.contains('SqliteException($code)')));
    const trigger = '1811';
    const check = '275';

    Future<Map<String, Object?>> row(String table) async =>
        (await database.customSelect('SELECT * FROM $table').getSingle()).data;

    test('any delete or update of the terms, and a second insert', () async {
      await recorded();
      final before = await row('trade_terms');
      await expectLater(
        database.customStatement('DELETE FROM trade_terms'),
        refusedBy(trigger),
      );
      for (final change in [
        'amount = 50.0',
        'taker_fee = 0.001',
        'book_price = 1.0',
        'version = 2',
        'order_id = 8',
      ]) {
        await expectLater(
          database.customStatement('UPDATE trade_terms SET $change'),
          refusedBy(trigger),
          reason: change,
        );
      }
      for (final insert in ['INSERT OR REPLACE', 'REPLACE']) {
        await database.customStatement(
          '$insert INTO trade_terms SELECT key_fingerprint, robot_index, '
          'version, network, coordinator_alias, order_id, role, order_type, '
          'currency_id, 50.0, is_range, premium_percent, explicit_satoshis, '
          'bond_size_percent, escrow_seconds, book_price, taker_fee '
          'FROM trade_terms',
        );
      }
      expect(await row('trade_terms'), before);
    });

    test('terms of no trade', () async {
      await expectLater(
        database.customStatement(
          "INSERT INTO trade_terms VALUES (?, 0, 1, 'testnet', 'temple', 7, "
          "'buyer', 1, 2, 100.0, 0, 2.0, NULL, 3.0, 10800, 93545.0, 0.00175)",
          [fingerprint.hex],
        ),
        refusedBy(trigger),
      );
    });

    test('terms out of their bounds', () async {
      final trade = await pendingTake();
      for (final (label, values) in [
        ('a text amount', "'many', 0, 2.0, NULL, 3.0, 10800, 93545.0, 0.00175"),
        ('an infinite amount', '9e999, 0, 2.0, NULL, 3.0, 10800, 93545.0, 0.00175'),
        ('a taker fee above 1 %', '100.0, 0, 2.0, NULL, 3.0, 10800, 93545.0, 0.02'),
        ('a bond of 20 %', '100.0, 0, 2.0, NULL, 20.0, 10800, 93545.0, 0.00175'),
        ('an escrow of a minute', '100.0, 0, 2.0, NULL, 3.0, 60, 93545.0, 0.00175'),
        ('a price of zero', '100.0, 0, 2.0, NULL, 3.0, 10800, 0.0, 0.00175'),
        ('no sats', '100.0, 0, 2.0, 0, 3.0, 10800, 93545.0, 0.00175'),
      ]) {
        await expectLater(
          database.customStatement(
            "INSERT INTO trade_terms VALUES (?, 0, 1, 'testnet', 'temple', 7, "
            "'buyer', 1, 2, $values)",
            [trade.robot.keyFingerprint.hex],
          ),
          refusedBy(check),
          reason: label,
        );
      }
      // A seller of a sell order: refused, by its trigger (not the trade's role) or its CHECK.
      await expectLater(
        database.customStatement(
          "INSERT INTO trade_terms VALUES (?, 0, 1, 'testnet', 'temple', 7, "
          "'seller', 1, 2, 100.0, 0, 2.0, NULL, 3.0, 10800, 93545.0, 0.00175)",
          [trade.robot.keyFingerprint.hex],
        ),
        anyOf(refusedBy(trigger), refusedBy(check)),
      );
    });

    test('any delete of the trail, and a second insert', () async {
      await recorded();
      final before = await row('trade_trails');
      await expectLater(
        database.customStatement('DELETE FROM trade_trails'),
        refusedBy(trigger),
      );
      await database.customStatement(
        "INSERT OR REPLACE INTO trade_trails SELECT key_fingerprint, robot_index, "
        "version, network, coordinator_alias, order_id, role, 'bondStep', "
        'read_at + 1, bond_hash, escrow_hash, deadline, bond_step_seen_at, '
        'bond_step_deadline, breached, history_unknown FROM trade_trails',
      );
      expect(await row('trade_trails'), before);
    });

    test('any update of the trail that goes back', () async {
      await recorded(
        trailOf(
          position: 'bondStep',
          readAt: at(10),
          bondHash: hashA,
          bondStepSeenAt: at(10),
          bondStepDeadline: at(200),
          breached: true,
        ),
      );
      final before = await row('trade_trails');
      for (final change in [
        'breached = 0',
        'history_unknown = 1',
        'bond_hash = NULL',
        "bond_hash = '$hashB'",
        'read_at = read_at - 1',
        'version = 0',
        'order_id = 8',
        "network = 'mainnet'",
        "role = 'seller'",
        "coordinator_alias = 'lake'",
        'robot_index = 1',
        'bond_step_seen_at = NULL',
        'bond_step_seen_at = bond_step_seen_at - 1',
        'bond_step_deadline = NULL',
      ]) {
        await expectLater(
          database.customStatement('UPDATE trade_trails SET $change'),
          refusedBy(trigger),
          reason: change,
        );
      }
      expect(await row('trade_trails'), before);
      // Forward, whatever the code: allowed.
      await database.customStatement(
        "UPDATE trade_trails SET escrow_hash = '$hashB', read_at = read_at + 1",
      );
    });

    test('an end left, and a change of the escrow hash once pinned', () async {
      await recorded(
        trailOf(position: 'publicAgain', readAt: at(10), escrowHash: hashA),
      );
      for (final change in [
        "position = 'bondStep'",
        'escrow_hash = NULL',
        "escrow_hash = '$hashB'",
      ]) {
        await expectLater(
          database.customStatement('UPDATE trade_trails SET $change'),
          refusedBy(trigger),
          reason: change,
        );
      }
    });

    test('a trail of a closed trade is left as it is', () async {
      final trade = await recorded();
      expect(await trades.closeTrade(trade), isA<Ok>());
      final before = await row('trade_trails');
      await database.customStatement(
        "UPDATE trade_trails SET position = 'bondStep', read_at = read_at + 1",
      );
      expect(await row('trade_trails'), before);
    });

    test('a trail out of its bounds', () async {
      final trade = await pendingTake();
      expect(await trails.recordTerms(trade, termsOf()), isA<Ok>());
      for (final (label, values) in [
        ('an unknown position', "'nowhere', 0, NULL, NULL, NULL, NULL, NULL, 0, 0"),
        ('an uppercase hash', "'start', 0, '${hashA.toUpperCase()}', NULL, NULL, NULL, NULL, 0, 0"),
        ('a short hash', "'start', 0, 'abc', NULL, NULL, NULL, NULL, 0, 0"),
        ('a read before the epoch', "'start', -1, NULL, NULL, NULL, NULL, NULL, 0, 0"),
        ('the pre-take seen after the read', "'start', 5, NULL, NULL, NULL, 6, NULL, 0, 0"),
        ('a flag of 2', "'start', 0, NULL, NULL, NULL, NULL, NULL, 2, 0"),
      ]) {
        await expectLater(
          database.customStatement(
            "INSERT INTO trade_trails VALUES (?, 0, 1, 'testnet', 'temple', 7, "
            "'buyer', $values)",
            [trade.robot.keyFingerprint.hex],
          ),
          refusedBy(check),
          reason: label,
        );
      }
    });

    test('a trail of another order than its trade', () async {
      final trade = await pendingTake();
      expect(await trails.recordTerms(trade, termsOf()), isA<Ok>());
      await expectLater(
        database.customStatement(
          "INSERT INTO trade_trails VALUES (?, 0, 1, 'testnet', 'temple', 8, "
          "'buyer', 'start', 0, NULL, NULL, NULL, NULL, NULL, 0, 0)",
          [trade.robot.keyFingerprint.hex],
        ),
        refusedBy(trigger),
      );
    });
  });
}
