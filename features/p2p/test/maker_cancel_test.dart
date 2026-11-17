import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/testing.dart' show ScriptedMakerRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';
import 'support/trade_harness.dart' show TradeHarness;

/// The maker's cancel (#179, design note `docs/design/phase-3-making-an-order.md` § 1.7, § 3.2): free at 0, 1 and 2, the bond lost at 6 and 7, the guard the status shown; the answer that ends the order is no read of it; the bond returned at 1 and 2 said by the cancel, which the state machine cannot know.
void main() {
  T valueOf<T>(Result<T, Failure> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => fail('$failure'),
  };

  /// An order made, moved by [move] at the coordinator, then read by the watch: its record and the status the user sees.
  Future<(MakeHarness, TradeRecord, TradeSeen)> madeAndSeen({
    bool sell = false,
    void Function(MakeHarness harness)? move,
  }) async {
    final harness = await MakeHarness.start();
    final made = valueOf(
      await harness.makeOrder(MakeHarness.request(sell: sell)),
    );
    final record = (made as MakeStarted).record;
    move?.call(harness);
    final run = harness.watchOf(record);
    await harness.settle();
    final seen = run.lastStatus.seen;
    expect(seen.stored, isTrue);
    await run.subscription.cancel();
    return (harness, record, seen);
  }

  int cancels(MakeHarness harness) => harness.coordinator.received
      .where((kind) => kind == ScriptedMakerRequest.cancel)
      .length;

  test(
    'at 0, free: the order cancelled, the bond invoice with it, the trade closed',
    () async {
      final (harness, record, seen) = await madeAndSeen();
      expect(seen.status, isA<WaitingForMakerBond>());
      final done = valueOf(await harness.cancel.execute(record, seen));
      expect(done, isA<CancelDone>());
      expect((done as CancelDone).makerBondReturned, isFalse);
      expect(done.seen.status, isA<Cancelled>());
      expect(done.record.closedAt, isNotNull);
      expect(harness.coordinator.order(42).status, 4);
      expect(cancels(harness), 1);
    },
  );

  for (final paused in [false, true]) {
    test(
      'at ${paused ? 2 : 1}, free: the maker bond returned, said by the cancel where the state machine says it may have been lost',
      () async {
        final (harness, record, seen) = await madeAndSeen(
          move: (harness) {
            harness.coordinator.lockMakerBond(42);
            if (paused) harness.coordinator.pause(42);
          },
        );
        expect(
          seen.status,
          isA<MakerOrderPublic>().having((s) => s.paused, 'paused', paused),
        );
        final done = valueOf(await harness.cancel.execute(record, seen));
        expect(done, isA<CancelDone>());
        expect((done as CancelDone).makerBondReturned, isTrue);
        final cancelled = done.seen.status as Cancelled;
        // The state machine cannot tell this cancel from one made elsewhere after a take (#178); the cancel can.
        expect(cancelled.bondMayHaveBeenLost, isTrue);
        expect(cancelled.has<TradeStatusRegressed>(), isFalse);
        expect(cancelled.trail.breached, isFalse);
        expect(harness.coordinator.order(42).bondReturned, isTrue);
        expect(done.record.closedAt, isNotNull);
      },
    );
  }

  for (final sell in [false, true]) {
    test(
      'at 6 as a maker ${sell ? 'seller' : 'buyer'}: the bond lost, sent only with the user\'s acknowledgement, never returned',
      () async {
        final (harness, record, seen) = await madeAndSeen(
          sell: sell,
          move: (harness) {
            harness.coordinator
              ..lockMakerBond(42)
              ..take(42, harness.robot(5));
          },
        );
        expect(seen.status, isA<WaitingForBoth>());
        expect(
          await harness.cancel.execute(record, seen),
          isA<Err<CancelOutcome, CancelRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<CancelLosesTheBond>(),
          ),
        );
        expect(cancels(harness), 0);
        final done = valueOf(
          await harness.cancel.execute(
            record,
            seen,
            bondLoss: BondLossAcknowledged.fromConfirmationDialog(record, seen),
          ),
        );
        expect(done, isA<CancelDone>());
        expect((done as CancelDone).makerBondReturned, isFalse);
        expect(harness.coordinator.order(42).bondSettled, isTrue);
        expect((done.seen.status as Cancelled).bondMayHaveBeenLost, isTrue);
      },
    );
  }

  test(
    'the guard is the status shown: a bond locked since the read at 0 makes the cancel refused, nothing cancelled',
    () async {
      final (harness, record, seen) = await madeAndSeen();
      harness.coordinator.lockMakerBond(42);
      final outcome = valueOf(await harness.cancel.execute(record, seen));
      expect(outcome, isA<CancelNotDone>());
      expect(harness.coordinator.order(42).status, 1);
      expect(outcome.seen.status, isA<MakerOrderPublic>());
      expect(outcome.record.closedAt, isNull);
    },
  );

  test(
    'an order answered whole at 4 is the order\'s end, never read as a status a maker is never shown (no breach)',
    () async {
      final (harness, record, seen) = await madeAndSeen(
        move: (harness) => harness.coordinator.lockMakerBond(42),
      );
      harness.coordinator.cancelAnswersWholeOrder = true;
      final done = valueOf(await harness.cancel.execute(record, seen));
      expect(done, isA<CancelDone>());
      expect((done as CancelDone).makerBondReturned, isTrue);
      final cancelled = done.seen.status as Cancelled;
      expect(cancelled.has<TradeStatusRegressed>(), isFalse);
      expect(cancelled.has<CoordinatorInconsistent>(), isFalse);
      expect(cancelled.trail.breached, isFalse);
    },
  );

  for (final paused in [false, true]) {
    test(
      'at ${paused ? 2 : 1}, a cancel answered with the order unchanged: the record stays open and followed, the live status kept, no bond said returned',
      () async {
        // Security review of #179: an answer that is the order as it was, alive, is no end of it, and nothing was returned.
        final (harness, record, seen) = await madeAndSeen(
          move: (harness) {
            harness.coordinator.lockMakerBond(42);
            if (paused) harness.coordinator.pause(42);
          },
        );
        harness.coordinator.cancelAnswersUnchanged = true;
        final done = valueOf(await harness.cancel.execute(record, seen));
        expect(done, isA<CancelDone>());
        expect((done as CancelDone).makerBondReturned, isFalse);
        expect(done.record.closedAt, isNull);
        expect(
          done.seen.status,
          isA<MakerOrderPublic>().having((s) => s.paused, 'paused', paused),
        );
        expect(harness.coordinator.order(42).status, paused ? 2 : 1);
        expect(harness.coordinator.order(42).bondReturned, isFalse);
        expect(await harness.activeRecords(), [done.record]);
        // Still followed: the watch reads it as it is.
        final run = harness.watchOf(done.record);
        await harness.settle();
        expect(run.lastStatus.seen.status, isA<MakerOrderPublic>());
        await run.subscription.cancel();
      },
    );
  }

  group('the guards, each alone (functional review of #179)', () {
    TradeRecord withOrigin(TradeRecord record, TradeOrigin origin) =>
        TradeRecord(
          robot: record.robot,
          coordinatorAlias: record.coordinatorAlias,
          coordinatorOnion: record.coordinatorOnion,
          orderId: record.orderId,
          role: record.role,
          origin: origin,
          takenAt: record.takenAt,
          confirmedAt: record.confirmedAt,
          closedAt: record.closedAt,
        );

    test(
      'a taker\'s record whose read says this robot is the maker of a public order: no cancel, nothing sent',
      () async {
        final (harness, record, seen) = await madeAndSeen(
          move: (harness) => harness.coordinator.lockMakerBond(42),
        );
        expect(seen.order?.isMaker, isTrue);
        final taker = withOrigin(record, TradeOrigin.takenHere);
        expect(
          await harness.cancel.execute(taker, seen),
          isA<Err<CancelOutcome, CancelRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<CancelNotPossible>(),
          ),
        );
        expect(cancels(harness), 0);
      },
    );

    test(
      'an order made here whose read says this robot is not its maker: no cancel, nothing sent',
      () async {
        final (harness, record, seen) = await madeAndSeen(
          move: (harness) => harness.coordinator.lockMakerBond(42),
        );
        // The same public order, as another robot reads it.
        final other = switch (await CoordinatorClient(
          harness.coordinator,
        ).fetchOrder(
          harness.host,
          harness.network,
          identity: harness.robot(5),
          orderId: 42,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(other.isMaker, isFalse);
        expect(other.status, CoordinatorOrderStatus.public);
        expect(
          await harness.cancel.execute(
            record,
            TradeSeen(seen.status, order: other, stored: true),
          ),
          isA<Err<CancelOutcome, CancelRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<CancelNotPossible>(),
          ),
        );
        expect(cancels(harness), 0);
      },
    );

    test(
      'an order made here read at 3, which a maker never sees: no cancel, nothing sent',
      () async {
        final app = await TradeHarness.start();
        final taken = TradeHarness.recordOf(await app.takeShown());
        final run = app.watchOf(taken);
        await app.settle();
        final seen = run.lastStatus.seen;
        await run.subscription.cancel();
        expect(seen.order?.status, CoordinatorOrderStatus.waitingForTakerBond);
        final sent = app.coordinator.requests.length;
        expect(
          await app.cancel.execute(
            withOrigin(taken, TradeOrigin.madeHere),
            seen,
          ),
          isA<Err<CancelOutcome, CancelRefusal>>().having(
            (e) => e.failure,
            'failure',
            isA<CancelNotPossible>(),
          ),
        );
        expect(app.coordinator.requests.length, sent);
      },
    );

    test(
      'a taker\'s cancel answered with the whole order at 4 stays what it was before #179: a read refused as a breach',
      () async {
        final app = await TradeHarness.start();
        final taken = TradeHarness.recordOf(await app.takeShown());
        final run = app.watchOf(taken);
        await app.settle();
        final seen = run.lastStatus.seen;
        await run.subscription.cancel();
        expect(seen.order?.status, CoordinatorOrderStatus.waitingForTakerBond);
        app.coordinator.cancelAnswersWholeOrderAt4 = true;
        final done = valueOf(await app.cancel.execute(taken, seen));
        expect(done, isA<CancelDone>());
        expect((done as CancelDone).makerBondReturned, isFalse);
        expect(done.seen.status.trail.breached, isTrue);
        expect(done.seen.status, isNot(isA<Cancelled>()));
      },
    );
  });
}
