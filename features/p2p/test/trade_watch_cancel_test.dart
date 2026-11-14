import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemException;

import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/data/trade_trail_repository_impl.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/repositories/trade_record_repository.dart';
import 'package:p2p/src/domain/trade_robots.dart';
import 'package:p2p/src/domain/usecases/trade/list_active_trades_usecase.dart';

import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_cadence.dart';
import 'package:p2p/src/domain/trade/trade_cancel.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade/wallet_payment.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/key_output.dart';
import 'support/trade_harness.dart';

/// The watch of a trade, its cancel and the list of the active trades (#87), over the coordinator the tests play: the cadence on the test's clock, the reads in flight, the abnormal answers, and nothing printed.
void main() {
  const read = ScriptedRequest.order;

  /// A trade taken on a fresh run, at the pre-take.
  Future<(TradeHarness, TradeRecord)> takenTrade() async {
    final app = await TradeHarness.start();
    final taken = await app.takeShown();
    expect(
      taken,
      isA<Ok<TakeOutcome, TakeRefusal>>().having(
        (ok) => ok.value,
        'outcome',
        isA<TakeStarted>(),
      ),
    );
    return (app, TradeHarness.recordOf(taken));
  }

  int readsOf(TradeHarness app) =>
      app.coordinator.received.where((kind) => kind == read).length;

  group('the cadence', () {
    test(
      'is the reference\'s, on its tick of 5 s, five times slower off-screen, and none at an end',
      () {
        Duration? on(TradePosition p) =>
            TradeCadence.delayAfter(p, onScreen: true);
        Duration? off(TradePosition p) =>
            TradeCadence.delayAfter(p, onScreen: false);
        const s = Duration(seconds: 1);
        for (final (position, onScreen, offScreen) in [
          (TradePosition.start, s * 5, s * 15),
          (TradePosition.bondStep, s * 5, s * 15),
          (TradePosition.preTakeUnavailable, s * 5, s * 15),
          (TradePosition.waitingForBoth, s * 10, s * 40),
          (TradePosition.waitingForEscrow, s * 10, s * 40),
          (TradePosition.waitingForPayout, s * 10, s * 40),
          (TradePosition.chatting, s * 10, s * 50),
          (TradePosition.fiatSent, s * 10, s * 50),
          (TradePosition.sendingSats, s * 10, s * 50),
          (TradePosition.routingFailed, s * 30, s * 150),
          (TradePosition.inDispute, s * 100, s * 500),
          (TradePosition.waitingDisputeResolution, s * 300, s * 1500),
        ]) {
          expect(on(position), onScreen, reason: position.name);
          expect(off(position), offScreen, reason: position.name);
        }
        for (final position in TradePosition.values.where(
          (p) => p.isTerminal,
        )) {
          expect(on(position), isNull, reason: position.name);
          expect(off(position), isNull, reason: position.name);
        }
        // The reference's own table, before its tick (`GarageContext.tsx:40-60`).
        expect(TradeCadence.referenceDelay(TradePosition.bondStep), s * 3);
        expect(
          TradeCadence.referenceDelay(TradePosition.waitingForBoth),
          s * 8,
        );
        expect(TradeCadence.referenceDelay(TradePosition.chatting), s * 10);
        expect(
          TradeCadence.referenceDelay(TradePosition.routingFailed),
          s * 30,
        );
        expect(TradeCadence.referenceDelay(TradePosition.inDispute), s * 100);
        expect(
          TradeCadence.referenceDelay(TradePosition.waitingDisputeResolution),
          s * 300,
        );
      },
    );

    test(
      'drives the reads of a watch, at once when listened to, then after each read ends',
      () async {
        final (app, record) = await takenTrade();
        final signals = StreamController<TradeWatchSignal>();
        final before = readsOf(app);
        final run = app.watchOf(record, signals: signals.stream);
        await app.settle();
        expect(readsOf(app), before + 1);
        expect(app.activeTimers.single.duration, const Duration(seconds: 5));

        await app.elapse(const Duration(seconds: 5));
        expect(readsOf(app), before + 2);

        // Off-screen: the next read is due 15 s after the last one ended.
        signals.add(TradeWatchSignal.offScreen);
        await app.settle();
        expect(app.activeTimers.single.duration, const Duration(seconds: 15));
        await app.elapse(const Duration(seconds: 14));
        expect(readsOf(app), before + 2);
        await app.elapse(const Duration(seconds: 1));
        expect(readsOf(app), before + 3);

        // Back to the screen: due 5 s after the last read; and a read on demand, at once.
        signals.add(TradeWatchSignal.onScreen);
        await app.settle();
        signals.add(TradeWatchSignal.readNow);
        await app.settle();
        expect(readsOf(app), before + 4);

        // Bond locked: 10 s at 6.
        app.coordinator.lockBond(app.robot(0));
        await app.elapse(const Duration(seconds: 5));
        expect(
          run.lastStatus.seen.status.position,
          TradePosition.waitingForBoth,
        );
        expect(app.activeTimers.single.duration, const Duration(seconds: 10));
        await run.subscription.cancel();
        await signals.close();
      },
    );

    test(
      'keeps at most one read in flight, and reads again right after it when asked meanwhile',
      () async {
        final (app, record) = await takenTrade();
        final signals = StreamController<TradeWatchSignal>();
        final gate = Completer<void>();
        app.coordinator.hold = gate.future;
        final before = readsOf(app);
        final run = app.watchOf(record, signals: signals.stream);
        await app.settle();
        expect(readsOf(app), before + 1);
        signals
          ..add(TradeWatchSignal.readNow)
          ..add(TradeWatchSignal.readNow);
        await app.elapse(const Duration(seconds: 30));
        expect(readsOf(app), before + 1);
        app.coordinator.hold = null;
        gate.complete();
        await app.settle();
        // The one asked meanwhile, once.
        expect(readsOf(app), before + 2);
        await run.subscription.cancel();
        await signals.close();
      },
    );

    test(
      'a cancelled subscription leaves no timer, starts no read, and a read in flight writes nothing',
      () async {
        final (app, record) = await takenTrade();
        final gate = Completer<void>();
        final run = app.watchOf(record);
        await app.settle();
        final stores = app.trails.stores;
        app.coordinator.hold = gate.future;
        app.coordinator.lockBond(app.robot(0));
        await app.elapse(const Duration(seconds: 5));
        final reads = readsOf(app);
        await run.subscription.cancel();
        app.coordinator.hold = null;
        gate.complete();
        await app.settle();
        await app.elapse(const Duration(minutes: 10));
        expect(readsOf(app), reads);
        expect(app.activeTimers, isEmpty);
        expect(app.trails.stores, stores);
        final history = switch (await app.trails.historyOf(record)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(history.trail?.position, 'bondStep');
      },
    );

    test('a busy answer waits as the limiter says, then reads', () async {
      final (app, record) = await takenTrade();
      app.coordinator
        ..failNext(read, ScriptedFault.busy)
        ..failNext(read, ScriptedFault.busy);
      final run = app.watchOf(record);
      await app.settle();
      expect(app.busyWaits, [
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      ]);
      expect(run.lastStatus.seen.status, isA<WaitingForTakerBond>());
      expect(run.lastStatus.failedReads, 0);
      await run.subscription.cancel();
    });

    test('a read that fails keeps the last status and counts', () async {
      final (app, record) = await takenTrade();
      final run = app.watchOf(record);
      await app.settle();
      for (var i = 0; i < 3; i++) {
        app.coordinator.failNext(read, ScriptedFault.unreachable);
      }
      await app.elapse(const Duration(seconds: 5));
      await app.elapse(const Duration(seconds: 5));
      await app.elapse(const Duration(seconds: 5));
      expect(run.lastStatus.failedReads, 3);
      expect(run.lastStatus.lastReadFailure, isA<CoordinatorUnreachable>());
      expect(run.lastStatus.seen.status, isA<WaitingForTakerBond>());
      await app.elapse(const Duration(seconds: 5));
      expect(run.lastStatus.failedReads, 0);
      await run.subscription.cancel();
    });
  });

  group('the scenarios of a trade', () {
    test(
      '3 → timeout: the pre-take ends, nothing taken, the record closed and the reads stop',
      () async {
        final (app, record) = await takenTrade();
        final run = app.watchOf(record);
        await app.settle();
        await app.elapse(const Duration(seconds: 195));
        expect(
          run.lastStatus.seen.status,
          isA<PreTakeEnded>().having(
            (s) => s.bondMayHaveBeenLost,
            'bond may have been lost',
            isFalse,
          ),
        );
        expect(run.lastStatus.record.closedAt, isNotNull);
        expect(run.done, isTrue);
        expect(app.activeTimers, isEmpty);
      },
    );

    test(
      '3 → taken by another: 1044 is not an end until the pre-take is certainly gone',
      () async {
        final (app, record) = await takenTrade();
        final run = app.watchOf(record);
        await app.settle();
        app.coordinator.takenByAnother();
        await app.elapse(const Duration(seconds: 5));
        expect(run.lastStatus.seen.status, isA<PreTakeUnavailable>());
        expect(run.done, isFalse);
        // The pre-take's deadline and the coordinator's loops.
        await app.elapse(const Duration(minutes: 5));
        expect(run.lastStatus.seen.status, isA<TakenByAnother>());
        expect(run.lastStatus.record.closedAt, isNotNull);
        expect(run.done, isTrue);
      },
    );

    test('3 → 1044 (paused) → 3 again, with the same invoice', () async {
      final (app, record) = await takenTrade();
      final run = app.watchOf(record);
      await app.settle();
      app.coordinator.pause();
      await app.elapse(const Duration(seconds: 5));
      expect(run.lastStatus.seen.status, isA<PreTakeUnavailable>());
      app.coordinator.pause(paused: false);
      await app.elapse(const Duration(seconds: 5));
      expect(run.lastStatus.seen.status, isA<WaitingForTakerBond>());
      expect(run.lastStatus.seen.status.warnings, isEmpty);
      await run.subscription.cancel();
    });

    test(
      '3 → 6 → public again: the bond is forfeited, the trade over',
      () async {
        final (app, record) = await takenTrade();
        final run = app.watchOf(record);
        await app.settle();
        app.coordinator.lockBond(app.robot(0));
        await app.elapse(const Duration(seconds: 5));
        expect(run.lastStatus.seen.status, isA<WaitingForBoth>());
        app.coordinator.backToPublic();
        await app.elapse(const Duration(seconds: 10));
        expect(run.lastStatus.seen.status, isA<BondForfeited>());
        expect(run.lastStatus.record.closedAt, isNotNull);
        expect(run.done, isTrue);
      },
    );

    test(
      '3 → 6 → 1043 (the maker cancelled): cancelled, the record closed',
      () async {
        final (app, record) = await takenTrade();
        final run = app.watchOf(record);
        await app.settle();
        app.coordinator.lockBond(app.robot(0));
        await app.elapse(const Duration(seconds: 5));
        app.coordinator.cancelByMaker();
        await app.elapse(const Duration(seconds: 10));
        expect(run.lastStatus.seen.status, isA<Cancelled>());
        expect(run.done, isTrue);
        expect(await app.activeRecords(), isEmpty);
      },
    );
  });

  group('the cancel', () {
    test(
      '3 → cancel: free, guarded with the stored status 1, the record closed',
      () async {
        final (app, record) = await takenTrade();
        final run = app.watchOf(record);
        await app.settle();
        final seen = run.lastStatus.seen;
        await run.subscription.cancel();

        final cancelled = await app.cancel.execute(record, seen);

        expect(
          cancelled,
          isA<Ok<CancelOutcome, CancelRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<CancelDone>().having(
              (d) => d.seen.status,
              'status',
              isA<PreTakeEnded>(),
            ),
          ),
        );
        final post = app.coordinator.requests.lastWhere(
          (r) => r.method == CoordinatorHttpMethod.post,
        );
        expect(jsonDecode(utf8.decode(post.body ?? const [])), {
          'action': 'cancel',
          'cancel_status': 1,
        });
        expect(await app.activeRecords(), isEmpty);
      },
    );

    test(
      '3 → 6 → cancel: refused without the acknowledgement, the bond lost with it',
      () async {
        final (app, record) = await takenTrade();
        final run = app.watchOf(record);
        await app.settle();
        app.coordinator.lockBond(app.robot(0));
        await app.elapse(const Duration(seconds: 5));
        final seen = run.lastStatus.seen;
        expect(seen.status, isA<WaitingForBoth>());
        await run.subscription.cancel();
        final posts = app.coordinator.received
            .where((kind) => kind == ScriptedRequest.cancel)
            .length;

        expect(
          await app.cancel.execute(record, seen),
          isA<Err<CancelOutcome, CancelRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<CancelLosesTheBond>(),
          ),
        );
        expect(
          app.coordinator.received.where(
            (kind) => kind == ScriptedRequest.cancel,
          ),
          hasLength(posts),
        );

        final cancelled = await app.cancel.execute(
          record,
          seen,
          bondLoss: const BondLossAcknowledged.fromConfirmationDialog(),
        );
        expect(
          cancelled,
          isA<Ok<CancelOutcome, CancelRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<CancelDone>().having(
              (d) => d.seen.status,
              'status',
              isA<BondForfeited>(),
            ),
          ),
        );
        final post = app.coordinator.requests.lastWhere(
          (r) => r.method == CoordinatorHttpMethod.post,
        );
        expect(jsonDecode(utf8.decode(post.body ?? const [])), {
          'action': 'cancel',
          'cancel_status': 6,
        });
        expect(await app.activeRecords(), isEmpty);
      },
    );

    test(
      'a cancel seen at 3 that arrives after the bond locked is refused, and the read after shows 6',
      () async {
        final (app, record) = await takenTrade();
        final run = app.watchOf(record);
        await app.settle();
        final seen = run.lastStatus.seen;
        await run.subscription.cancel();
        app.coordinator.lockBond(app.robot(0));

        final cancelled = await app.cancel.execute(record, seen);

        expect(
          cancelled,
          isA<Ok<CancelOutcome, CancelRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<CancelNotDone>()
                .having((n) => n.cause, 'cause', isA<OrderStatusChanged>())
                .having((n) => n.seen.status, 'status', isA<WaitingForBoth>()),
          ),
        );
        expect(app.coordinator.status, 6);
        expect(await app.activeRecords(), hasLength(1));
      },
    );

    test('an outcome unknown is said, and the read after it tells', () async {
      final (app, record) = await takenTrade();
      final run = app.watchOf(record);
      await app.settle();
      final seen = run.lastStatus.seen;
      await run.subscription.cancel();
      app.coordinator.failNext(ScriptedRequest.cancel, ScriptedFault.timedOut);

      expect(
        await app.cancel.execute(record, seen),
        isA<Ok<CancelOutcome, CancelRefusal>>().having(
          (ok) => ok.value,
          'outcome',
          isA<CancelOutcomeUnknown>().having(
            (u) => u.seen.status,
            'status',
            isA<WaitingForTakerBond>(),
          ),
        ),
      );
    });

    test(
      'with the escrow locked, only together (a later slice); with no order seen, a read first',
      () async {
        final (app, record) = await takenTrade();
        final run = app.watchOf(record);
        await app.settle();
        app.coordinator.lockBond(app.robot(0));
        await app.elapse(const Duration(seconds: 5));
        app.coordinator.moveTo(8);
        await app.elapse(const Duration(seconds: 10));
        expect(run.lastStatus.seen.status, isA<WaitingForPayout>());
        expect(
          await app.cancel.execute(record, run.lastStatus.seen),
          isA<Err<CancelOutcome, CancelRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<CancelOnlyTogether>(),
          ),
        );
        await run.subscription.cancel();
        expect(
          await app.cancel.execute(
            record,
            TradeSeen(run.lastStatus.seen.status, order: null),
          ),
          isA<Err<CancelOutcome, CancelRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<CancelNeedsARead>(),
          ),
        );
      },
    );
  });

  group('a hostile or confused coordinator', () {
    test(
      'another bond invoice after a restart is never offered, and the breach stays across restarts',
      () async {
        final (app, record) = await takenTrade();
        final again = app.restart();
        app.coordinator.replaceBondInvoice(app.robot(0));
        final run = again.watchOf(record);
        await again.settle();
        final status = run.lastStatus.seen.status;
        expect(status.has<InvoiceHashChanged>(), isTrue);
        expect(
          walletPaymentFor(
            accepted: Sats.fromInt(1000000),
            status: status,
            step: InvoiceStep.bond,
            now: again.now,
          ),
          isA<WalletPaymentRefused>(),
        );
        await run.subscription.cancel();

        final third = again.restart();
        final next = third.watchOf(record);
        await third.settle();
        expect(next.states.first, isA<TradeWatchStatus>());
        expect(
          (next.states.first as TradeWatchStatus).seen.status
              .has<CoordinatorInconsistent>(),
          isTrue,
        );
        expect(
          next.lastStatus.seen.status.has<CoordinatorInconsistent>(),
          isTrue,
        );
        await next.subscription.cancel();
      },
    );

    test('a status going backwards is refused, and remembered', () async {
      final (app, record) = await takenTrade();
      final run = app.watchOf(record);
      await app.settle();
      app.coordinator.lockBond(app.robot(0));
      await app.elapse(const Duration(seconds: 5));
      app.coordinator.moveTo(9);
      await app.elapse(const Duration(seconds: 10));
      expect(run.lastStatus.seen.status, isA<Chatting>());
      app.coordinator.moveTo(6);
      await app.elapse(const Duration(seconds: 10));
      expect(run.lastStatus.seen.status.has<TradeStatusUnexpected>(), isTrue);
      // Every later status carries the breach.
      await app.elapse(const Duration(seconds: 10));
      expect(run.lastStatus.seen.status.has<CoordinatorInconsistent>(), isTrue);
      final history = switch (await app.trails.historyOf(record)) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(history.trail?.breached, isTrue);
      await run.subscription.cancel();
    });

    test(
      'two reads racing: the late one\'s trail is refused, and the stored trail wins',
      () async {
        final (app, record) = await takenTrade();
        final opened = switch (await app.reader.open(record)) {
          TradeOpened(:final trade) => trade,
          final other => fail('not opened: $other'),
        };
        // The early read, sent at the pre-take, ends after a later one that saw the bond locked.
        final early = await CoordinatorClient(app.coordinator).fetchOrder(
          app.coordinator.coordinator,
          app.network,
          identity: app.robot(0),
          orderId: record.orderId,
        );
        app.coordinator.lockBond(app.robot(0));
        await app.elapse(const Duration(seconds: 10));
        final late = await CoordinatorClient(app.coordinator).fetchOrder(
          app.coordinator.coordinator,
          app.network,
          identity: app.robot(0),
          orderId: record.orderId,
        );
        final later = await app.reader.advance(
          opened,
          TradeAnswer.ofRead(late) ?? fail('no answer'),
          at: app.now,
        );
        expect(later.trade.seen.status, isA<WaitingForBoth>());
        final stale = await app.reader.advance(
          opened,
          TradeAnswer.ofRead(early) ?? fail('no answer'),
          at: app.now.subtract(const Duration(seconds: 10)),
        );
        expect(stale.trade.seen.status.position, TradePosition.waitingForBoth);
        expect(stale.trade.seen.order, isNull);
        final history = switch (await app.trails.historyOf(record)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(history.trail?.position, 'waitingForBoth');
      },
    );

    test(
      'records that cannot be restored are shown so, and nothing is sent',
      () async {
        final (app, record) = await takenTrade();
        await app.database.customStatement(
          'UPDATE trade_trails SET read_at = read_at + 0.5',
        );
        final reads = readsOf(app);
        final run = app.restart().watchOf(record);
        await app.settle();
        expect(
          run.last,
          isA<TradeWatchUnrestorable>().having(
            (u) => u.reason,
            'reason',
            isA<TradeRecordMalformed>(),
          ),
        );
        expect(run.done, isTrue);
        expect(readsOf(app), reads);
      },
    );
  });

  group('the active trades', () {
    test(
      'each with where its stored trail stands, a new list after each write',
      () async {
        final (app, record) = await takenTrade();
        final first = await app.list.execute(app.network).first;
        expect(
          first,
          isA<Ok<List<ActiveTrade>, P2pFailure>>()
              .having((ok) => ok.value, 'trades', [
                isA<ActiveTrade>()
                    .having((t) => t.record, 'record', record)
                    .having(
                      (t) => t.standing,
                      'standing',
                      isA<ActiveTradeAt>().having(
                        (a) => a.position,
                        'position',
                        TradePosition.bondStep,
                      ),
                    ),
              ]),
        );
      },
    );

    test(
      'a trade whose records cannot be restored is listed as such',
      () async {
        final (app, record) = await takenTrade();
        await app.database.customStatement(
          'UPDATE trade_trails SET read_at = read_at + 0.5',
        );
        final listed = await app.list.execute(app.network).first;
        expect(
          listed,
          isA<Ok<List<ActiveTrade>, P2pFailure>>().having(
            (ok) => ok.value.single.standing,
            'standing',
            isA<ActiveTradeUnrestorable>(),
          ),
        );
      },
    );

    test(
      'a database that cannot be read is a failure, never an empty list',
      () async {
        final broken = P2pDatabase.forTesting(
          NativeDatabase.memory(
            setup: (_) => throw const FileSystemException('unavailable'),
          ),
        );
        final list = ListActiveTradesUsecase(
          _RecordsOnly(TradeRecordRepositoryImpl(broken, clock: DateTime.now)),
          TradeTrailRepositoryImpl(broken),
          clock: DateTime.now,
        );
        final listed = await list.execute(RobosatsNetwork.testnet).first;
        expect(
          listed,
          isA<Err<List<ActiveTrade>, P2pFailure>>().having(
            (err) => err.failure,
            'failure',
            isA<P2pStorageFailure>(),
          ),
        );
        await broken.close();
      },
    );
  });

  test(
    'nothing is printed or logged, through a take, its reads and its cancel',
    () async {
      final output = await captureKeyOutput(() async {
        final (app, record) = await takenTrade();
        final run = app.watchOf(record);
        await app.settle();
        await app.cancel.execute(record, run.lastStatus.seen);
        await run.subscription.cancel();
      });
      expect(
        output
            .trim()
            .split('\n')
            .where(
              (line) =>
                  line.trim().isNotEmpty &&
                  !line.contains('print capture works') &&
                  !line.contains('logger capture works'),
            ),
        isEmpty,
      );
    },
  );
}

/// The robot layer of the list: the active records of [_records], nothing else.
final class _RecordsOnly implements TradeRobots {
  final TradeRecordRepository _records;

  _RecordsOnly(this._records);

  @override
  Stream<Result<List<TradeRecord>, P2pFailure>> activeTrades(
    RobosatsNetwork network,
  ) => _records.watchActiveTrades(network);

  @override
  Future<Result<ReservedRobot, P2pFailure>> robotForNewTrade(
    RobosatsNetwork network,
    Coordinator coordinator,
  ) => throw UnimplementedError();

  @override
  Future<Result<NetworkRobot, P2pFailure>> robotOfTrade(TradeRecord record) =>
      throw UnimplementedError();
}
