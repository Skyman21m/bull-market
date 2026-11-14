import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:get_it/get_it.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/list_active_trades_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/src/domain/usecases/trade/trade_take_locks.dart';
import 'package:p2p/src/domain/usecases/trade/trade_watch_session.dart';
import 'package:p2p/src/p2p_locator.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/trade_harness.dart';
import 'support/two_connections.dart';

/// The fixes of the security review of #117: one open trade per order (the take's check, the lock, the database), no status of an unstored trail, a take that never happened, the guards the review's mutants found untested, and its probes P1 to P13, each ending as decided.
void main() {
  const take = ScriptedRequest.take;
  int takes(TradeHarness app) =>
      app.coordinator.received.where((kind) => kind == take).length;
  int reads(TradeHarness app) =>
      app.coordinator.received.where((kind) => kind == ScriptedRequest.order).length;
  final everything = Sats.fromInt(100000000);

  Matcher refused<T>() => isA<Err<TakeOutcome, TakeRefusal>>().having(
    (err) => err.failure,
    'refusal',
    isA<T>(),
  );
  Matcher outcome<T>() => isA<Ok<TakeOutcome, TakeRefusal>>().having(
    (ok) => ok.value,
    'outcome',
    isA<T>(),
  );

  Future<(TradeHarness, TradeRecord)> takenTrade({bool range = false}) async {
    final app = await TradeHarness.start(range: range);
    final taken = await app.takeShown(
      amount: range ? TakeAmount.tryCreate(120) : null,
    );
    expect(taken, outcome<TakeStarted>());
    return (app, TradeHarness.recordOf(taken));
  }

  group('B1: one open trade per order', () {
    test('P1: the order taken again is refused with its trade, no second robot', () async {
      final app = await TradeHarness.start();
      final first = TradeHarness.recordOf(await app.takeShown());
      final second = await app.takeShown();
      expect(
        second,
        isA<Err<TakeOutcome, TakeRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<TakeOrderAlreadyTraded>().having((r) => r.record, 'record', first),
        ),
      );
      expect(takes(app), 1);
      expect(await app.activeRecords(), [first]);
      expect(app.coordinator.holdsPreTake(app.robot(1)), isFalse);
      expect(
        await app.database.customSelect('SELECT * FROM robot_bindings').get(),
        hasLength(1),
      );
    });

    test('P2: two takes at once: one takes, the other finds its trade', () async {
      final app = await TradeHarness.start();
      final shown = await app.shownOrder();
      final both = await Future.wait([
        app.take.execute(shown, network: app.network),
        app.take.execute(shown, network: app.network),
      ]);
      expect(both, containsAll([outcome<TakeStarted>(), refused<TakeOrderAlreadyTraded>()]));
      expect(takes(app), 1);
      expect(await app.activeRecords(), hasLength(1));
      // One robot only: the second take waited for the first, then found its trade.
      expect(
        await app.database.customSelect('SELECT * FROM robot_bindings').get(),
        hasLength(1),
      );
    });

    test('P3: after an outcome unknown, the order taken again is refused', () async {
      final app = await TradeHarness.start();
      app.coordinator.failNext(take, ScriptedFault.answerLost);
      expect(await app.takeShown(), outcome<TakeOutcomeUnknown>());
      expect(await app.takeShown(), refused<TakeOrderAlreadyTraded>());
      expect(takes(app), 1);
    });

    test('a take not made leaves the order free to take again', () async {
      final app = await TradeHarness.start();
      app.coordinator.takesNotMade = true;
      expect(await app.takeShown(), outcome<TakeNotMade>());
      app.coordinator.takesNotMade = false;
      expect(await app.takeShown(), outcome<TakeStarted>());
      expect(takes(app), 2);
    });

    test('the lock runs the takes of one order in turn, and those of two orders apart', () async {
      final locks = TradeTakeLocks();
      final temple = coordinator('temple');
      final events = <String>[];
      final gate = Completer<void>();
      final a = locks.run(RobosatsNetwork.testnet, temple, 1, () async {
        events.add('a starts');
        await gate.future;
        events.add('a ends');
      });
      final b = locks.run(RobosatsNetwork.testnet, temple, 1, () async {
        events.add('b starts');
      });
      final c = locks.run(RobosatsNetwork.testnet, temple, 2, () async {
        events.add('c starts');
      });
      await pumpEventQueue();
      expect(events, ['a starts', 'c starts']);
      gate.complete();
      await Future.wait([a, b, c]);
      expect(events, ['a starts', 'c starts', 'a ends', 'b starts']);
      // A take that throws releases the order.
      await expectLater(
        locks.run(RobosatsNetwork.testnet, temple, 1, () async => throw StateError('x')),
        throwsStateError,
      );
      expect(await locks.run(RobosatsNetwork.testnet, temple, 1, () async => 7), 7);
    });

    test('the composition holds one lock and one registry for every use case it makes', () {
      final locator = GetIt.asNewInstance();
      P2pLocator.registerTrades(
        locator,
        transport: () => throw StateError('no transport'),
        clock: DateTime.now,
      );
      expect(identical(locator<TradeTakeLocks>(), locator<TradeTakeLocks>()), isTrue);
      expect(
        identical(locator<TradeWatchRegistry>(), locator<TradeWatchRegistry>()),
        isTrue,
      );
    });

    group('the database', () {
      final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };
      final temple = switch (CoordinatorIdentity.of(
        coordinator('temple'),
        RobosatsNetwork.testnet,
      )) {
        final identity? => identity,
        null => throw StateError('temple is not on testnet'),
      };

      Future<TradeReservation> reserve(TradeRecordRepositoryImpl trades, int index) async =>
          switch (await trades.reserveForNewTrade(
            RobotSlot(RobosatsNetwork.testnet, fingerprint, index),
            temple,
          )) {
            Ok(value: final reservation?) => reservation,
            final other => fail('not reserved: $other'),
          };

      test('refuses a second open trade of an order, whatever the code, and not once the first is closed', () async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        final database = P2pDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        final bindings = RobotBindingRepositoryImpl(database, clock: () => testNow);
        final trades = TradeRecordRepositoryImpl(database, clock: () => testNow);
        expect(await bindings.recordGeneratedKey(RobosatsNetwork.testnet, fingerprint), isA<Ok>());
        final first = switch (await trades.recordPendingTake(
          await reserve(trades, 0),
          orderId: 42,
          role: TradeRole.buyer,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        final secondReservation = await reserve(trades, 1);
        expect(
          await trades.recordPendingTake(secondReservation, orderId: 42, role: TradeRole.buyer),
          isA<Err<TradeRecord, P2pFailure>>(),
        );
        // Raw SQL, a take-over of the same order: refused by the trigger.
        await expectLater(
          database.customStatement(
            "INSERT INTO trades VALUES ('testnet', ?, 1, 'temple', ?, 42, 'buyer', 'recovered', 0, 0, NULL)",
            [fingerprint.hex, temple.onion],
          ),
          throwsA(predicate((error) => '$error'.contains('SqliteException(1811)'))),
        );
        // Another order of the coordinator is free.
        expect(
          await trades.recordPendingTake(secondReservation, orderId: 43, role: TradeRole.buyer),
          isA<Ok<TradeRecord, P2pFailure>>(),
        );
        expect(await trades.closeTrade(first), isA<Ok>());
        expect(
          await trades.recordPendingTake(await reserve(trades, 2), orderId: 42, role: TradeRole.buyer),
          isA<Ok<TradeRecord, P2pFailure>>(),
        );
      });

      test('two connections recording a take of one order at once: one only', () async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        final directory = await Directory.systemTemp.createTemp('p2p-one-open-');
        addTearDown(() => directory.delete(recursive: true));
        final a = P2pDatabase.open(() async => directory);
        final b = P2pDatabase.open(() async => directory);
        await openInTurn([a, b]);
        addTearDown(a.close);
        addTearDown(b.close);
        final bindings = RobotBindingRepositoryImpl(a, clock: () => testNow);
        expect(await bindings.recordGeneratedKey(RobosatsNetwork.testnet, fingerprint), isA<Ok>());
        final tradesA = TradeRecordRepositoryImpl(a, clock: () => testNow);
        final tradesB = TradeRecordRepositoryImpl(b, clock: () => testNow);
        for (var round = 0; round < 5; round++) {
          final orderId = 100 + round;
          final ra = await reserve(tradesA, round * 2);
          final rb = await reserve(tradesB, round * 2 + 1);
          final both = await Future.wait([
            untilNotBusy(() => tradesA.recordPendingTake(ra, orderId: orderId, role: TradeRole.buyer)),
            untilNotBusy(() => tradesB.recordPendingTake(rb, orderId: orderId, role: TradeRole.buyer)),
          ]);
          expect(both.whereType<Ok<TradeRecord, P2pFailure>>(), hasLength(1), reason: '$round');
        }
      });
    });
  });

  group('B2: no status of a trail that was not stored', () {
    const failUpdates =
        "CREATE TEMP TRIGGER probe_fail BEFORE UPDATE ON main.trade_trails BEGIN SELECT RAISE(ABORT, 'probe'); END";

    test('P4: the take\'s trail cannot be stored: nothing payable, before and after a restart', () async {
      final app = await TradeHarness.start();
      await app.database.customStatement(failUpdates);
      final taken = await app.takeShown();
      final started = switch (taken) {
        Ok(value: final TakeStarted started) => started,
        final other => fail('$other'),
      };
      expect(started.recordProblem, isA<P2pStorageFailure>());
      expect(started.status, isA<StatusUnknown>());
      expect(started.status.invoice, isNull);
      expect(
        walletPaymentFor(accepted: everything, status: started.status, step: InvoiceStep.bond, now: app.now),
        isA<WalletPaymentRefused>(),
      );
      final firstHash = app.coordinator.bondOf(app.robot(0))?.facts.paymentHash;

      // Restarted with the disk still failing, a hostile coordinator hands another invoice: still nothing payable.
      app.coordinator.replaceBondInvoice(app.robot(0));
      final again = app.restart();
      final run = again.watchOf(started.record);
      await again.settle();
      expect(run.lastStatus.recordProblem, isA<P2pStorageFailure>());
      expect(run.lastStatus.seen.status.invoice, isNull);
      expect(
        walletPaymentFor(accepted: everything, status: run.lastStatus.seen.status, step: InvoiceStep.bond, now: again.now),
        isA<WalletPaymentRefused>(),
      );
      await run.subscription.cancel();

      // The disk mended: the invoice now stored is the first this app ever offers, and the first was never offered.
      await app.database.customStatement('DROP TRIGGER temp.probe_fail');
      final third = again.restart();
      final next = third.watchOf(started.record);
      await third.settle();
      final status = next.lastStatus.seen.status;
      final offered = walletPaymentFor(accepted: everything, status: status, step: InvoiceStep.bond, now: third.now);
      expect(offered, isA<WalletPaymentOffered>());
      expect(
        (status.invoice as CheckedInvoice?)?.paymentHash,
        isNot(firstHash),
      );
      await next.subscription.cancel();
    });

    test('P5: the watch whose trail cannot be stored emits the stored trail\'s status', () async {
      final (app, record) = await takenTrade();
      await app.database.customStatement(failUpdates);
      app.coordinator.lockBond(app.robot(0));
      final run = app.watchOf(record);
      await app.settle();
      expect(run.lastStatus.recordProblem, isA<P2pStorageFailure>());
      // The stored trail is the pre-take's: its status, never the 6 the read computed.
      expect(run.lastStatus.seen.status.position.name, 'bondStep');
      await run.subscription.cancel();
    });

    test('M09: an end whose trail cannot be stored leaves the record open', () async {
      final (app, record) = await takenTrade();
      final run = app.watchOf(record);
      await app.settle();
      app.coordinator.lockBond(app.robot(0));
      await app.elapse(const Duration(seconds: 5));
      await app.database.customStatement(failUpdates);
      app.coordinator.backToPublic();
      await app.elapse(const Duration(seconds: 10));
      expect(run.lastStatus.recordProblem, isA<P2pStorageFailure>());
      expect(run.lastStatus.seen.status, isA<WaitingForBoth>());
      expect(await app.activeRecords(), hasLength(1));
      await run.subscription.cancel();
    });
  });

  group('I5: a take that never happened', () {
    test('P13: taken by another before the take arrives: 1044 until the pre-take is certainly gone, then a take not made, never a bond lost', () async {
      final app = await TradeHarness.start();
      final shown = await app.shownOrder();
      app.coordinator.onRequest = (request) {
        if (request.url.path == '/api/robot/') app.coordinator.takenByAnother();
      };
      final taken = await app.take.execute(shown, network: app.network);
      app.coordinator.onRequest = null;
      expect(taken, outcome<TakeOutcomeUnknown>());
      final run = app.watchOf(TradeHarness.recordOf(taken));
      await app.settle();
      expect(run.lastStatus.seen.status, isA<PreTakeUnavailable>());
      expect(run.lastStatus.seen.status.invoice, isNull);
      await app.elapse(const Duration(minutes: 32));
      expect(
        run.last,
        isA<TradeWatchTakeNotMade>().having((s) => s.closed, 'closed', isTrue),
      );
      expect(run.states.whereType<TradeWatchStatus>().map((s) => s.seen.status), everyElement(isNot(isA<TakenByAnother>())));
    });

    test('a take of a paused order: 1044, outcome unknown, then a take not made', () async {
      final app = await TradeHarness.start();
      final shown = await app.shownOrder();
      app.coordinator.onRequest = (request) {
        if (request.url.path == '/api/robot/') app.coordinator.pause();
      };
      expect(await app.take.execute(shown, network: app.network), outcome<TakeOutcomeUnknown>());
    });

    test('an order cancelled after a lost take answer: a take not made at once', () async {
      final app = await TradeHarness.start();
      app.coordinator.failNext(take, ScriptedFault.timedOut);
      final record = TradeHarness.recordOf(await app.takeShown());
      app.coordinator.cancelByMaker();
      final run = app.watchOf(record);
      await app.settle();
      expect(run.last, isA<TradeWatchTakeNotMade>());
    });
  });

  group('I1: the guards the review\'s mutants found untested', () {
    test('M15: a cancel at 7 loses the bond, and needs the acknowledgement', () async {
      final (app, record) = await takenTrade();
      final run = app.watchOf(record);
      await app.settle();
      app.coordinator.lockBond(app.robot(0));
      await app.elapse(const Duration(seconds: 5));
      app.coordinator.moveTo(7);
      await app.elapse(const Duration(seconds: 10));
      final seen = run.lastStatus.seen;
      expect(seen.status, isA<WaitingForEscrow>());
      await run.subscription.cancel();
      expect(
        await app.cancel.execute(record, seen),
        isA<Err<CancelOutcome, CancelRefusal>>().having((e) => e.failure, 'refusal', isA<CancelLosesTheBond>()),
      );
      expect(app.coordinator.received, isNot(contains(ScriptedRequest.cancel)));
      final done = await app.cancel.execute(
        record,
        seen,
        bondLoss: BondLossAcknowledged.fromConfirmationDialog(record, seen),
      );
      expect(done, isA<Ok<CancelOutcome, CancelRefusal>>().having((o) => o.value.seen.status, 'status', isA<BondForfeited>()));
      final post = app.coordinator.requests.lastWhere((r) => r.method == CoordinatorHttpMethod.post);
      expect(jsonDecode(utf8.decode(post.body ?? const [])), {'action': 'cancel', 'cancel_status': 7});
    });

    test('M03: an order changed since the page was shown is refused', () async {
      final app = await TradeHarness.start();
      final [shown] = await parseOrders([bookOrder(id: 42, premium: 5)]);
      expect(await app.take.execute(shown, network: app.network), refused<TakeOrderChanged>());
      expect(takes(app), 0);
    });

    test('I4: sats moved beyond the price tolerance since the page are refused, within it taken', () async {
      final app = await TradeHarness.start();
      final shown = await app.shownOrder();
      app.coordinator.satoshisNow = 110107; // 3 % more
      expect(await app.take.execute(shown, network: app.network), refused<TakeOrderChanged>());
      app.coordinator.satoshisNow = 104762; // 2 % less, at the bound
      expect(await app.take.execute(shown, network: app.network), outcome<TakeStarted>());
    });

    test('M02: a robot the coordinator already knew with an order is not used', () async {
      for (final fields in [
        {'active_order_id': 7},
        {'last_order_id': 7},
      ]) {
        final app = await TradeHarness.start();
        app.coordinator.robotAnswerHas(app.robot(0), fields);
        expect(
          await app.takeShown(),
          isA<Err<TakeOutcome, TakeRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<TakeRobotRefused>().having((r) => r.failure, 'failure', isA<RobotNotForNewTradeFailure>()),
          ),
          reason: '$fields',
        );
        expect(takes(app), 0);
      }
    });

    test('M11: a record whose onion address is not the coordinator\'s is not read', () async {
      final (app, record) = await takenTrade();
      final moved = TradeRecord(
        robot: record.robot,
        coordinatorAlias: record.coordinatorAlias,
        coordinatorOnion: 'http://another.onion',
        orderId: record.orderId,
        role: record.role,
        origin: record.origin,
        takenAt: record.takenAt,
        confirmedAt: record.confirmedAt,
        closedAt: record.closedAt,
      );
      final before = reads(app);
      final run = app.watchOf(moved);
      await app.settle();
      expect(
        run.last,
        isA<TradeWatchUnavailable>().having((u) => u.failure, 'failure', isA<RobotCoordinatorChangedFailure>()),
      );
      expect(reads(app), before);
    });

    test('M16 and M10: an order of another trade is never cancelled, nor shows this robot as taker', () async {
      final (app, record) = await takenTrade();
      final other = await TradeHarness.start(orderId: 43);
      final otherRecord = TradeHarness.recordOf(await other.takeShown());
      final otherRun = other.watchOf(otherRecord);
      await other.settle();
      final seenElsewhere = otherRun.lastStatus.seen;
      await otherRun.subscription.cancel();
      expect(
        await app.cancel.execute(record, seenElsewhere),
        isA<Err<CancelOutcome, CancelRefusal>>().having((e) => e.failure, 'refusal', isA<CancelOfAnotherTrade>()),
      );
      expect(app.coordinator.received, isNot(contains(ScriptedRequest.cancel)));
      final opened = switch (await app.reader.open(record)) {
        TradeOpened(:final trade) => trade,
        final other => fail('$other'),
      };
      expect(
        TradeReader.showsTaker(TradeOrderRead(seenElsewhere.order ?? fail('no order')), opened.terms),
        isFalse,
      );
    });

    test('M04: a range takes its upper bound, and refuses beyond it', () async {
      final app = await TradeHarness.start(range: true);
      expect(await app.takeShown(amount: TakeAmount.tryCreate(200.5)), refused<TakeAmountRefused>());
      expect(await app.takeShown(amount: TakeAmount.tryCreate(200)), outcome<TakeStarted>());
    });

    test('M21: the list shows a history it cannot read as such', () async {
      final (app, record) = await takenTrade();
      final list = ListActiveTradesUsecase(app.robots, _UnreadableTrails(app.trails), clock: () => app.now);
      expect(
        await list.execute(app.network).first,
        isA<Ok<List<ActiveTrade>, P2pFailure>>().having(
          (ok) => ok.value.single.standing,
          'standing',
          isA<ActiveTradeUnrestorable>(),
        ),
      );
      expect(record.isActive, isTrue);
    });
  });

  group('I2: the acknowledgement of a bond lost is bound to its trade and status', () {
    test('given at 6, it does not cover 7; given for one trade, not for another', () async {
      final (app, record) = await takenTrade();
      final run = app.watchOf(record);
      await app.settle();
      app.coordinator.lockBond(app.robot(0));
      await app.elapse(const Duration(seconds: 5));
      final atSix = run.lastStatus.seen;
      final acknowledged = BondLossAcknowledged.fromConfirmationDialog(record, atSix);
      app.coordinator.moveTo(7);
      await app.elapse(const Duration(seconds: 10));
      final atSeven = run.lastStatus.seen;
      await run.subscription.cancel();
      expect(
        await app.cancel.execute(record, atSeven, bondLoss: acknowledged),
        isA<Err<CancelOutcome, CancelRefusal>>().having((e) => e.failure, 'refusal', isA<CancelAcknowledgementMismatch>()),
      );
      final other = TradeRecord(
        robot: RobotSlot(record.network, record.robot.keyFingerprint, record.robot.accountIndex + 1),
        coordinatorAlias: record.coordinatorAlias,
        coordinatorOnion: record.coordinatorOnion,
        orderId: record.orderId,
        role: record.role,
        origin: record.origin,
        takenAt: record.takenAt,
        confirmedAt: record.confirmedAt,
        closedAt: null,
      );
      expect(
        await app.cancel.execute(
          record,
          atSeven,
          bondLoss: BondLossAcknowledged.fromConfirmationDialog(other, atSeven),
        ),
        isA<Err<CancelOutcome, CancelRefusal>>().having((e) => e.failure, 'refusal', isA<CancelAcknowledgementMismatch>()),
      );
      expect(app.coordinator.received, isNot(contains(ScriptedRequest.cancel)));
    });
  });

  group('the minors', () {
    test('P6: a second subscription to a trade reads nothing', () async {
      final (app, record) = await takenTrade();
      final before = reads(app);
      final a = app.watchOf(record);
      final b = app.watchOf(record);
      await app.settle();
      expect(reads(app), before + 1);
      expect(b.last, isA<TradeWatchAlreadyWatched>());
      expect(b.done, isTrue);
      await a.subscription.cancel();
      // Free again once the first is cancelled.
      final c = app.watchOf(record);
      await app.settle();
      expect(c.last, isA<TradeWatchStatus>());
      await c.subscription.cancel();
    });

    test('P7: a watch left open across a cancel at 6 ends on the forfeited bond', () async {
      final (app, record) = await takenTrade();
      final run = app.watchOf(record);
      await app.settle();
      app.coordinator.lockBond(app.robot(0));
      await app.elapse(const Duration(seconds: 5));
      final seen = run.lastStatus.seen;
      expect(
        await app.cancel.execute(
          record,
          seen,
          bondLoss: BondLossAcknowledged.fromConfirmationDialog(record, seen),
        ),
        isA<Ok<CancelOutcome, CancelRefusal>>(),
      );
      await app.elapse(const Duration(seconds: 10));
      expect(run.lastStatus.seen.status, isA<BondForfeited>());
      expect(run.done, isTrue);
      expect(
        run.states.whereType<TradeWatchStatus>().where((s) => s.recordProblem != null),
        isEmpty,
      );
    });

    test('a newer read that lost to an older write is read again over the stored trail, once', () async {
      final (app, record) = await takenTrade();
      final kept = _KeptOnce(app.trails);
      final reader = TradeReader(
        app.robots,
        app.records,
        kept,
        app.bindings,
        CoordinatorClient(app.coordinator),
        Federation.robosats,
        Bolt11Reader(app.coordinator.decoder),
        clock: () => app.now,
      );
      final opened = switch (await reader.open(record)) {
        TradeOpened(:final trade) => trade,
        final other => fail('$other'),
      };
      app.coordinator.lockBond(app.robot(0));
      await app.elapse(const Duration(seconds: 10));
      final read = await CoordinatorClient(app.coordinator).fetchOrder(
        app.coordinator.coordinator,
        app.network,
        identity: app.robot(0),
        orderId: record.orderId,
      );
      final step = await reader.advance(
        opened,
        TradeAnswer.ofRead(read) ?? fail('no answer'),
        at: app.now,
      );
      expect(kept.calls, 2);
      expect(step.stored, isTrue);
      expect(step.trade.seen.status, isA<WaitingForBoth>());
      final history = switch (await app.trails.historyOf(record)) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(history.trail?.position, 'waitingForBoth');
    });

    test('the scripted coordinator refuses takes as the reference does, and the take says so', () async {
      for (final (code, cause) in [
        (1001, isA<RobotHasActiveOrder>()),
        (1012, isA<OrderTakePenalty>()),
        (1045, isA<OrderWrongPassword>()),
        (1011, isA<OrderAmountOutOfRange>()),
      ]) {
        final app = await TradeHarness.start();
        app.coordinator.refuseNextTake(code);
        expect(
          await app.takeShown(),
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeNotMade>().having((n) => n.refusal, 'refusal', cause),
          ),
          reason: '$code',
        );
        expect(await app.activeRecords(), isEmpty, reason: '$code');
      }
    });

    test('a protected order: a wrong password is refused, the right one takes', () async {
      final app = await TradeHarness.start(password: 'sesame');
      expect(
        await app.takeShown(password: OrderPassword.tryCreate('open')),
        isA<Ok<TakeOutcome, TakeRefusal>>().having(
          (ok) => ok.value,
          'outcome',
          isA<TakeNotMade>().having((n) => n.refusal, 'refusal', isA<OrderWrongPassword>()),
        ),
      );
      expect(await app.takeShown(password: OrderPassword.tryCreate('sesame')), outcome<TakeStarted>());
    });

    test('a pre-taker\'s cancel costs its robot a penalty at the coordinator', () async {
      final (app, record) = await takenTrade();
      final run = app.watchOf(record);
      await app.settle();
      final seen = run.lastStatus.seen;
      await run.subscription.cancel();
      expect(await app.cancel.execute(record, seen), isA<Ok<CancelOutcome, CancelRefusal>>());
      expect(app.coordinator.hasPenalty(app.robot(0)), isTrue);
    });

    test('a paused order is not shown to a robot that is no participant', () async {
      final app = await TradeHarness.start();
      app.coordinator.pause();
      final read = await CoordinatorClient(app.coordinator).fetchOrder(
        app.coordinator.coordinator,
        app.network,
        identity: app.robot(3),
        orderId: 42,
      );
      expect(read, isA<Err<CoordinatorOrder, CoordinatorFailure>>().having((e) => e.failure, 'failure', isA<OrderNotAvailable>()));
    });

    test('P9: a value of another storage class is refused', () async {
      final (app, _) = await takenTrade();
      await expectLater(
        app.database.customStatement('UPDATE trade_trails SET read_at = read_at + 0.5'),
        throwsA(predicate((error) => '$error'.contains('SqliteException(275)'))),
      );
    });
  });
}

/// The stored histories, each read as unreadable.
final class _UnreadableTrails implements TradeTrailRepository {
  final TradeTrailRepository _inner;

  _UnreadableTrails(this._inner);

  @override
  Future<Result<void, P2pFailure>> recordTerms(TradeRecord trade, TradeTermsRecord terms) =>
      _inner.recordTerms(trade, terms);

  @override
  Future<Result<TrailStoreOutcome, P2pFailure>> storeTrail(TradeRecord trade, TradeTrailRecord trail) =>
      _inner.storeTrail(trade, trail);

  @override
  Future<Result<StoredTradeHistory, P2pFailure>> historyOf(TradeRecord trade) =>
      _inner.historyOf(trade);

  @override
  Stream<Result<Map<RobotSlot, StoredTradeHistory>, P2pFailure>> watchHistories(
    RobosatsNetwork network,
  ) => _inner.watchHistories(network).map(
    (result) => switch (result) {
      Ok(:final value) => Ok({
        for (final entry in value.entries)
          entry.key: StoredTradeHistory(
            terms: entry.value.terms,
            trail: entry.value.trail,
            unreadable: true,
          ),
      }),
      Err() => result,
    },
  );
}

/// The trails, the first write answered as kept over the trail stored (as when another write came first), the next ones written.
final class _KeptOnce implements TradeTrailRepository {
  final TradeTrailRepository _inner;
  int calls = 0;

  _KeptOnce(this._inner);

  @override
  Future<Result<void, P2pFailure>> recordTerms(TradeRecord trade, TradeTermsRecord terms) =>
      _inner.recordTerms(trade, terms);

  @override
  Future<Result<TrailStoreOutcome, P2pFailure>> storeTrail(TradeRecord trade, TradeTrailRecord trail) async {
    calls++;
    if (calls == 1) {
      return switch (await _inner.historyOf(trade)) {
        Ok(value: StoredTradeHistory(trail: final stored?)) => Ok(TrailKept(stored, reason: null)),
        _ => const Err(P2pStorageFailure()),
      };
    }
    return _inner.storeTrail(trade, trail);
  }

  @override
  Future<Result<StoredTradeHistory, P2pFailure>> historyOf(TradeRecord trade) =>
      _inner.historyOf(trade);

  @override
  Stream<Result<Map<RobotSlot, StoredTradeHistory>, P2pFailure>> watchHistories(
    RobosatsNetwork network,
  ) => _inner.watchHistories(network);
}
