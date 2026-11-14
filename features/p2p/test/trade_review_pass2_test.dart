import 'dart:async';

import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/trade_harness.dart';

/// The fixes of the second security pass on #117: a status shows an invoice only when this read stored it (Q2), the newest subscription takes a trade over (Q4), and the guards its mutants found untested.
void main() {
  const take = ScriptedRequest.take;
  final everything = Sats.fromInt(100000000);
  int reads(TradeHarness app) => app.coordinator.received
      .where((kind) => kind == ScriptedRequest.order)
      .length;
  const failTrailUpdates =
      "CREATE TEMP TRIGGER probe_fail BEFORE UPDATE ON main.trade_trails BEGIN SELECT RAISE(ABORT, 'probe'); END";
  const failTradeUpdates =
      "CREATE TEMP TRIGGER probe_trades BEFORE UPDATE ON main.trades BEGIN SELECT RAISE(ABORT, 'probe'); END";

  Future<(TradeHarness, TradeRecord)> takenTrade() async {
    final app = await TradeHarness.start();
    final taken = await app.takeShown();
    expect(
      taken,
      isA<Ok<TakeOutcome, TakeRefusal>>().having(
        (ok) => ok.value,
        'outcome',
        isA<TakeStarted>().having((s) => s.stored, 'stored', isTrue),
      ),
    );
    return (app, TradeHarness.recordOf(taken));
  }

  Future<TradeRecord> lostAnswerTake(TradeHarness app) async {
    app.coordinator.failNext(take, ScriptedFault.answerLost);
    return TradeHarness.recordOf(await app.takeShown());
  }

  group('I-a: an invoice only from a status this read stored', () {
    test(
      'Q2: the bond locked, the next trail not stored: the stale invoice is not offered again',
      () async {
        final (app, record) = await takenTrade();
        final run = app.watchOf(record);
        await app.settle();
        final before = run.lastStatus;
        expect(before.stored, isTrue);
        expect(before.seen.status, isA<WaitingForTakerBond>());
        expect(
          walletPaymentFor(
            accepted: everything,
            status: before.seen.status,
            step: InvoiceStep.bond,
            now: app.now,
          ),
          isA<WalletPaymentOffered>(),
        );

        app.coordinator.lockBond(app.robot(0));
        await app.database.customStatement(failTrailUpdates);
        await app.elapse(const Duration(seconds: 5));
        final after = run.lastStatus;
        expect(after.recordProblem, isA<P2pStorageFailure>());
        expect(after.stored, isFalse);
        expect(after.seen.status, isA<StatusUnknown>());
        expect(after.seen.status.invoice, isNull);
        expect(after.seen.order, isNull);
        expect(
          walletPaymentFor(
            accepted: everything,
            status: after.seen.status,
            step: InvoiceStep.bond,
            now: app.now,
          ),
          isA<WalletPaymentRefused>(),
        );
        await run.subscription.cancel();
      },
    );

    test('the three causes of a record problem are told apart', () async {
      // A trail not stored: unmarked, the trail on disk's own status.
      final (app, record) = await takenTrade();
      await app.database.customStatement(failTrailUpdates);
      final notStored = app.watchOf(record);
      await app.settle();
      expect(notStored.lastStatus.recordProblem, isA<P2pStorageFailure>());
      expect(notStored.lastStatus.stored, isFalse);
      await notStored.subscription.cancel();

      // A confirmation that fails: the status stored and marked, its invoice payable.
      final other = await TradeHarness.start();
      final pending = await lostAnswerTake(other);
      await other.database.customStatement(failTradeUpdates);
      final confirmFails = other.watchOf(pending);
      await other.settle();
      expect(confirmFails.lastStatus.recordProblem, isA<P2pStorageFailure>());
      expect(confirmFails.lastStatus.stored, isTrue);
      expect(confirmFails.lastStatus.seen.status, isA<WaitingForTakerBond>());
      await confirmFails.subscription.cancel();

      // A record closed that the coordinator shows taken: the sticky failure, and no trail written on a closed trade.
      final third = await TradeHarness.start();
      final lost = await lostAnswerTake(third);
      expect(await third.records.closeTrade(lost), isA<Ok>());
      final closedButTaken = third.watchOf(lost);
      await third.settle();
      expect(
        closedButTaken.lastStatus.recordProblem,
        isA<TradeClosedFailure>(),
      );
      expect(closedButTaken.lastStatus.stored, isFalse);
      await closedButTaken.subscription.cancel();
    });
  });

  group('I-b: the newest subscription takes the trade over', () {
    test(
      'two in a row: the second reads at once, the first ends superseded, one read in flight',
      () async {
        final (app, record) = await takenTrade();
        final first = app.watchOf(record);
        await app.settle();
        final gate = Completer<void>();
        app.coordinator.hold = gate.future;
        await app.elapse(const Duration(seconds: 5));
        final readsBefore = reads(app);
        // The first's read is in flight: the second waits for it, sends nothing meanwhile.
        final second = app.watchOf(record);
        await app.settle();
        expect(first.last, isA<TradeWatchSuperseded>());
        expect(first.done, isTrue);
        expect(reads(app), readsBefore);
        app.coordinator.hold = null;
        gate.complete();
        await app.settle();
        expect(reads(app), readsBefore + 1);
        expect(second.last, isA<TradeWatchStatus>());
        await second.subscription.cancel();
      },
    );

    test(
      'three in a row: only the last reads; a subscription cancelled while superseded ends quietly',
      () async {
        final (app, record) = await takenTrade();
        final before = reads(app);
        final a = app.watchOf(record);
        final b = app.watchOf(record);
        await b.subscription.cancel();
        final c = app.watchOf(record);
        await app.settle();
        expect(reads(app), before + 1);
        expect(a.last, isA<TradeWatchSuperseded>());
        expect(b.states.whereType<TradeWatchStatus>(), isEmpty);
        expect(c.last, isA<TradeWatchStatus>());
        await c.subscription.cancel();
      },
    );

    test('the registry is released at every end', () async {
      final (app, record) = await takenTrade();
      final registry = app.watchRegistry;
      // On a cancel.
      final a = app.watchOf(record);
      await app.settle();
      expect(registry.isWatched(record.robot), isTrue);
      await a.subscription.cancel();
      expect(registry.isWatched(record.robot), isFalse);
      // Superseded, then the newest cancelled.
      final b = app.watchOf(record);
      final c = app.watchOf(record);
      await app.settle();
      expect(registry.isWatched(record.robot), isTrue);
      await c.subscription.cancel();
      expect(b.done, isTrue);
      expect(registry.isWatched(record.robot), isFalse);
      // At the end of the trade.
      final d = app.watchOf(record);
      await app.settle();
      await app.elapse(const Duration(seconds: 200));
      expect(d.done, isTrue);
      expect(registry.isWatched(record.robot), isFalse);
      // Records that cannot be read.
      final moved = TradeRecord(
        robot: record.robot,
        coordinatorAlias: record.coordinatorAlias,
        coordinatorOnion: 'http://another.onion',
        orderId: record.orderId,
        role: record.role,
        origin: record.origin,
        takenAt: record.takenAt,
        confirmedAt: record.confirmedAt,
        closedAt: null,
      );
      final e = app.watchOf(moved);
      await app.settle();
      expect(e.done, isTrue);
      expect(registry.isWatched(record.robot), isFalse);
    });
  });

  group('the guards the second pass\'s mutants found untested', () {
    test(
      'N08: a pre-take seen on a record whose confirmation failed ends as the state machine says, not as a take not made',
      () async {
        final app = await TradeHarness.start();
        final pending = await lostAnswerTake(app);
        await app.database.customStatement(failTradeUpdates);
        final run = app.watchOf(pending);
        await app.settle();
        expect(run.lastStatus.seen.status, isA<WaitingForTakerBond>());
        expect(run.lastStatus.record.confirmedAt, isNull);
        await app.database.customStatement('DROP TRIGGER temp.probe_trades');
        await app.elapse(const Duration(seconds: 200));
        expect(run.last, isA<TradeWatchStatus>());
        expect(run.lastStatus.seen.status, isA<PreTakeEnded>());
      },
    );

    test(
      'N19: the same order id on another coordinator stays free to take',
      () async {
        final app = await TradeHarness.start();
        final lake = switch (CoordinatorIdentity.of(
          coordinator('lake'),
          app.network,
        )) {
          final identity? => identity,
          null => fail('lake is not on testnet'),
        };
        final reservation = switch (await app.records.reserveForNewTrade(
          RobotSlot(app.network, _fingerprint(), 5),
          lake,
        )) {
          Ok(value: final reservation?) => reservation,
          final other => fail('not reserved: $other'),
        };
        expect(
          await app.records.recordPendingTake(
            reservation,
            orderId: 42,
            role: TradeRole.buyer,
          ),
          isA<Ok<TradeRecord, P2pFailure>>(),
        );
        expect(
          await app.takeShown(),
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeStarted>(),
          ),
        );
      },
    );

    test(
      'N02: a trade of the order recorded by another writer while the robot was put: refused with that trade',
      () async {
        final app = await TradeHarness.start();
        final temple = switch (CoordinatorIdentity.of(
          coordinator('temple'),
          app.network,
        )) {
          final identity? => identity,
          null => fail('temple is not on testnet'),
        };
        TradeRecord? theirs;
        var inserted = false;
        app.coordinator.onRequest = (request) {
          if (inserted || request.url.path != '/api/robot/') return;
          inserted = true;
          app.coordinator.hold = () async {
            final reservation = switch (await app.records.reserveForNewTrade(
              RobotSlot(app.network, _fingerprint(), 9),
              temple,
            )) {
              Ok(value: final reservation?) => reservation,
              final other => fail('not reserved: $other'),
            };
            theirs = switch (await app.records.recordPendingTake(
              reservation,
              orderId: 42,
              role: TradeRole.buyer,
            )) {
              Ok(:final value) => value,
              Err(:final failure) => fail('$failure'),
            };
            app.coordinator.hold = null;
          }();
        };
        final taken = await app.takeShown();
        expect(
          taken,
          isA<Err<TakeOutcome, TakeRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<TakeOrderAlreadyTraded>().having(
              (r) => r.record,
              'record',
              theirs,
            ),
          ),
        );
        expect(app.coordinator.received, isNot(contains(take)));
      },
    );
  });
}

/// The fingerprint of the trade tests' key.
GarageKeyFingerprint _fingerprint() =>
    switch (GarageKeyFingerprint.of(tradeKey)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
