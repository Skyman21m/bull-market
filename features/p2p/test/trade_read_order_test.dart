import 'dart:convert';

import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_answer.dart';
import 'package:p2p/src/domain/trade/trade_chat_step.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_payout.dart';
import 'package:p2p/src/domain/trade/trade_payout_outcome.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_warning.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/trade_read_order.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/testing.dart'
    show Bolt11TestInvoice, ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// The answers of a trade ordered by when their requests left (#141): a read overtaken in flight by a later one never replaces the status the later one stored, over the coordinator the tests play.
void main() {
  // The order of the scripted coordinator once the bond locks: the buyer receives 106,713 sats (`trade_payout_test.dart`).
  const buyerSats = 106713;

  /// A trade taken on a fresh run, its bond locked, at [status] as the watch stored it, the watch still running.
  Future<(TradeHarness, TradeRecord, TradeSeen, WatchRun)> watchedAt(
    int status,
  ) async {
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
    final record = TradeHarness.recordOf(taken);
    final run = app.watchOf(record);
    await app.settle();
    app.coordinator.lockBond(app.robot(0));
    app.coordinator.moveTo(status);
    await app.elapse(const Duration(seconds: 5));
    final last = run.lastStatus;
    expect(last.stored, isTrue);
    return (app, last.record, last.seen, run);
  }

  Future<OpenTrade> opened(TradeHarness app, TradeRecord record) async =>
      switch (await app.reader.open(record)) {
        TradeOpened(:final trade) => trade,
        final other => fail('not opened: $other'),
      };

  Future<TradeAnswer> readNow(TradeHarness app, TradeRecord record) async {
    final read = await CoordinatorClient(app.coordinator).fetchOrder(
      app.coordinator.coordinator,
      app.network,
      identity: app.robot(0),
      orderId: record.orderId,
    );
    return TradeAnswer.ofRead(read) ?? fail('no answer');
  }

  Future<String?> positionOnDisk(TradeHarness app, TradeRecord record) async =>
      switch (await app.trails.historyOf(record)) {
        Ok(:final value) => value.trail?.position,
        Err(:final failure) => fail('$failure'),
      };

  Future<bool?> breachOnDisk(TradeHarness app, TradeRecord record) async =>
      switch (await app.trails.historyOf(record)) {
        Ok(:final value) => value.trail?.breached,
        Err(:final failure) => fail('$failure'),
      };

  group('TradeReadOrder', () {
    test(
      'a request that leaves later ranks later, whatever the clock does, and keeps its own time',
      () {
        final order = TradeReadOrder();
        final t = DateTime.utc(2026, 11, 15, 12);
        final first = order.leaving(t);
        expect(first.at, t);
        // The same instant, then the clock moved back an hour: still later.
        final second = order.leaving(t);
        expect(second.at, t);
        expect(first.isBefore(second), isTrue);
        expect(second.isBefore(first), isFalse);
        expect(first.isBefore(first), isFalse);
        final back = t.subtract(const Duration(hours: 1));
        final third = order.leaving(back);
        expect(third.at, back);
        expect(second.isBefore(third), isTrue);
      },
    );

    test(
      'a status gives way only to one of a request that left strictly after it, and an older one never takes the place of a newer',
      () async {
        final app = await TradeHarness.start();
        final record = TradeHarness.recordOf(await app.takeShown());
        final trade = await opened(app, record);
        final order = TradeReadOrder();
        final t = DateTime.utc(2026, 11, 15, 12);
        final earlier = order.leaving(t);
        final middle = order.leaving(t);
        final later = order.leaving(t);
        expect(order.newerThan(record.robot, earlier), isNull);
        order.stored(record, trade.seen, middle);
        expect(order.newerThan(record.robot, middle), isNull);
        expect(order.newerThan(record.robot, later), isNull);
        final newer = order.newerThan(record.robot, earlier);
        expect(newer?.$2, same(trade.seen));
        expect(newer?.$1, record);
        // An older status stored after does not take its place.
        order.stored(
          record,
          TradeSeen(trade.seen.status, order: null),
          earlier,
        );
        expect(order.newerThan(record.robot, earlier)?.$2, same(trade.seen));
        // Another trade is not concerned.
        expect(
          order.newerThan(
            RobotSlot(
              record.robot.network,
              record.robot.keyFingerprint,
              record.robot.accountIndex + 1,
            ),
            earlier,
          ),
          isNull,
        );
      },
    );
  });

  group('two answers of a trade in the wrong order', () {
    for (final keepsTime in [true, false]) {
      test(
        'a read that left before the one stored, answered after it, never takes the trade back from 10 to 9 (an edge the trade may take), and nothing is written (its time ${keepsTime ? 'kept in the status, as the watch\'s' : 'not kept in the status, as the cancel\'s or the bond payment\'s'})',
        () async {
          final (app, record, _, run) = await watchedAt(9);
          await run.subscription.cancel();
          final trade = await opened(app, record);
          expect(trade.seen.status.position, TradePosition.chatting);
          // The edge back exists: by the time of the answers alone, the late 9 would be stored.
          expect(
            TradeEdges.allows(
              TradeRole.buyer,
              TradePosition.fiatSent,
              TradePosition.chatting,
            ),
            isTrue,
          );

          // The first read leaves at 9; « fiat sent » moves the order to 10; a second read leaves and is answered first.
          final firstLeft = app.reader.requestLeaves();
          final early = await readNow(app, record);
          app.coordinator.moveTo(10);
          await app.elapse(const Duration(seconds: 10));
          final secondLeft = app.reader.requestLeaves();
          final late = await readNow(app, record);
          final newer = await app.reader.advance(
            trade,
            late,
            at: app.now,
            sent: secondLeft,
            keepsTime: keepsTime,
          );
          expect(newer.stored, isTrue);
          expect(
            newer.trade.seen.status,
            isA<Chatting>().having(
              (c) => c.position,
              'position',
              TradePosition.fiatSent,
            ),
          );

          // The first read's answer comes now, later than the second's.
          await app.elapse(const Duration(seconds: 1));
          final stale = await app.reader.advance(
            trade,
            early,
            at: app.now,
            sent: firstLeft,
            keepsTime: keepsTime,
          );
          expect(stale.stored, isFalse);
          expect(stale.trade.seen, same(newer.trade.seen));
          expect(
            stale.trade.seen.status,
            isA<Chatting>().having(
              (c) => c.position,
              'position',
              TradePosition.fiatSent,
            ),
          );
          expect(stale.trade.record, newer.trade.record);
          expect(await positionOnDisk(app, record), 'fiatSent');

          // A read that leaves after it is stored as always: the undo of « fiat sent » shows.
          app.coordinator.moveTo(9);
          final thirdLeft = app.reader.requestLeaves();
          final undone = await app.reader.advance(
            stale.trade,
            await readNow(app, record),
            at: app.now.add(const Duration(seconds: 1)),
            sent: thirdLeft,
            keepsTime: keepsTime,
          );
          expect(undone.stored, isTrue);
          expect(undone.trade.seen.status.position, TradePosition.chatting);
          expect(await positionOnDisk(app, record), 'chatting');
        },
      );
    }

    test(
      'a read that left before the end, answered after it: the end stays, with its record closed',
      () async {
        final (app, record, _, run) = await watchedAt(9);
        await run.subscription.cancel();
        final trade = await opened(app, record);
        final firstLeft = app.reader.requestLeaves();
        final early = await readNow(app, record);
        app.coordinator.cancelByMaker();
        await app.elapse(const Duration(seconds: 10));
        final end = await app.reader.advance(
          trade,
          await readNow(app, record),
          at: app.now,
          sent: app.reader.requestLeaves(),
        );
        expect(end.trade.seen.status.isTerminal, isTrue);
        expect(end.trade.record.closedAt, isNotNull);
        await app.elapse(const Duration(seconds: 1));
        final stale = await app.reader.advance(
          trade,
          early,
          at: app.now,
          sent: firstLeft,
        );
        expect(stale.stored, isFalse);
        expect(stale.trade.seen, same(end.trade.seen));
        expect(stale.trade.record.closedAt, isNotNull);
      },
    );

    test(
      'a run started again remembers nothing: its first read is stored over what the previous run stored',
      () async {
        final (app, record, _, run) = await watchedAt(9);
        await run.subscription.cancel();
        // A later status of the previous run, from its reader.
        app.coordinator.moveTo(10);
        await app.elapse(const Duration(seconds: 10));
        final before = await app.reader.advance(
          await opened(app, record),
          await readNow(app, record),
          at: app.now,
          sent: app.reader.requestLeaves(),
        );
        expect(
          before.trade.seen.status,
          isA<Chatting>().having(
            (c) => c.position,
            'position',
            TradePosition.fiatSent,
          ),
        );
        // The next run reads at 9 (the undo): every request of a run leaves after what a previous run stored.
        app.coordinator.moveTo(9);
        await app.elapse(const Duration(seconds: 1));
        final again = app.restart();
        final step = await again.reader.advance(
          await opened(again, record),
          await readNow(again, record),
          at: again.now,
          sent: again.reader.requestLeaves(),
        );
        expect(step.stored, isTrue);
        expect(step.trade.seen.status.position, TradePosition.chatting);
      },
    );
  });

  group('the watch crossing an action', () {
    test(
      'the watch\'s read sent at 8, answered after the payout\'s read at 9: the watch shows 9, and no breach of trust is recorded',
      () async {
        final (app, record, seen, run) = await watchedAt(8);
        expect(seen.status, isA<WaitingForPayout>());
        final reads = app.coordinator.received
            .where((kind) => kind == ScriptedRequest.order)
            .length;

        // The watch's next read is answered at 8, and its answer held on the way back.
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.answerDelayed,
        );
        await app.elapse(const Duration(minutes: 1));
        expect(
          app.coordinator.received
              .where((kind) => kind == ScriptedRequest.order)
              .length,
          reads + 1,
        );

        // Meanwhile the payout: its fresh read at 8, the invoice, the coordinator at 9, its read after at 9.
        final invoice = Bolt11TestInvoice(
          network: Bolt11Network.testnet,
          sats: buyerSats,
          seed: 941,
          createdAt: app.now,
          expiry: const Duration(days: 2),
        );
        app.coordinator.decoder.add(invoice);
        final shown = switch (app.payout.check(
          record,
          seen,
          PayoutInvoiceText(
            invoice.text,
            budget: RoutingBudgetPpm.of(0) ?? RoutingBudgetPpm.referenceDefault,
          ),
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('refused: $failure'),
        };
        final given = await app.payout.execute(record, shown);
        expect(
          given,
          isA<Ok<PayoutSubmission, PayoutNotSent>>().having(
            (ok) => ok.value,
            'outcome',
            isA<PayoutGiven>().having(
              (g) => g.seen.status,
              'status',
              isA<Chatting>(),
            ),
          ),
        );
        expect(await positionOnDisk(app, record), 'chatting');

        // The watch's read at 8 arrives now, a second later than the payout's read after it: by the time of the answers alone, it would be read again over the trail at 9, along no edge, and recorded as a breach of trust.
        await app.elapse(const Duration(seconds: 1));
        app.coordinator.deliverDelayed();
        await app.settle();
        final last = run.lastStatus;
        expect(last.seen.status, isA<Chatting>());
        expect(last.seen.status.has<CoordinatorInconsistent>(), isFalse);
        expect(last.seen.status.has<TradeStatusUnexpected>(), isFalse);
        expect(last.stored, isTrue);
        expect(await positionOnDisk(app, record), 'chatting');
        expect(await breachOnDisk(app, record), isFalse);

        // The watch goes on from there: its next read is stored as always.
        await app.elapse(const Duration(minutes: 1));
        expect(run.lastStatus.seen.status, isA<Chatting>());
        expect(
          run.lastStatus.seen.status.has<CoordinatorInconsistent>(),
          isFalse,
        );
        await run.subscription.cancel();
      },
    );

    /// Whether [seen] shows « fiat sent » (10).
    bool fiatSentShown(TradeSeen seen) => switch (seen.status) {
      Chatting(:final fiatSent) => fiatSent,
      _ => false,
    };

    test(
      'the watch\'s read sent at 9, answered after « fiat sent » stored 10: 10 stays, nothing is written, « Confirm … sent » is not offered again, no breach',
      () async {
        final (app, record, seen, run) = await watchedAt(9);
        expect(fiatSentShown(seen), isFalse);
        expect(ChatStepAction.confirmFiatSent.offeredAt(seen), isTrue);

        // The watch's next read is answered at 9, and its answer held on the way back.
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.answerDelayed,
        );
        await app.elapse(const Duration(minutes: 1));

        // Meanwhile « fiat sent »: its fresh read at 9, the action, the coordinator at 10, its read after at 10.
        final confirmed = await app.chat.confirmFiatSent(record, seen);
        final done = switch (confirmed) {
          Ok(value: final ChatStepDone done) => done,
          final other => fail('$other'),
        };
        expect(fiatSentShown(done.seen), isTrue);
        expect(await positionOnDisk(app, record), 'fiatSent');
        final trailBefore = switch (await app.trails.historyOf(record)) {
          Ok(:final value) => value.trail,
          Err(:final failure) => fail('$failure'),
        };

        // The watch's read at 9 arrives now, a second later: by the time of the answers alone, the edge back (10 → 9) would store it.
        await app.elapse(const Duration(seconds: 1));
        app.coordinator.deliverDelayed();
        await app.settle();
        final last = run.lastStatus;
        expect(fiatSentShown(last.seen), isTrue);
        expect(last.seen, same(done.seen));
        expect(ChatStepAction.confirmFiatSent.offeredAt(last.seen), isFalse);
        expect(last.seen.status.has<CoordinatorInconsistent>(), isFalse);
        expect(await breachOnDisk(app, record), isFalse);
        // Nothing written: the trail on disk is the one « fiat sent » stored.
        final trailAfter = switch (await app.trails.historyOf(record)) {
          Ok(:final value) => value.trail,
          Err(:final failure) => fail('$failure'),
        };
        expect(trailAfter, trailBefore);
        await run.subscription.cancel();
      },
    );

    test(
      '« fiat sent » that landed late, found by a second tap\'s read: the watch\'s read sent at 9 before it, answered after, never takes 10 back',
      () async {
        final (app, record, seen, run) = await watchedAt(9);
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.answerDelayed,
        );
        await app.elapse(const Duration(minutes: 1));

        // The first tap: the action held up over Tor, its answer timed out; the read after still shows 9.
        app.coordinator.failNext(
          ScriptedRequest.confirm,
          ScriptedFault.landsLate,
        );
        final first = await app.chat.confirmFiatSent(record, seen);
        final unknown = switch (first) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(fiatSentShown(unknown.seen), isFalse);
        // It lands now; the second tap's fresh read finds it recorded.
        app.coordinator.landLate();
        expect(app.coordinator.status, 10);
        final second = await app.chat.confirmFiatSent(record, unknown.seen);
        final done = switch (second) {
          Ok(value: final ChatStepDone done) => done,
          final other => fail('$other'),
        };
        expect(fiatSentShown(done.seen), isTrue);

        // The watch's read, sent at 9 before both taps, arrives now.
        await app.elapse(const Duration(seconds: 1));
        app.coordinator.deliverDelayed();
        await app.settle();
        expect(fiatSentShown(run.lastStatus.seen), isTrue);
        expect(
          run.lastStatus.seen.status.has<CoordinatorInconsistent>(),
          isFalse,
        );
        expect(await positionOnDisk(app, record), 'fiatSent');
        await run.subscription.cancel();
      },
    );

    test(
      'a read of the trade that leaves between the payout and the payout\'s read after it, and answers after that read: the read after stays (its rank is its own, not the payout\'s)',
      () async {
        final (app, record, seen, run) = await watchedAt(8);
        await run.subscription.cancel();
        // An answer at 9, as the other read will give it (the coordinator at 9 once the payout is in).
        app.coordinator.moveTo(9);
        final atNine = await readNow(app, record);
        app.coordinator.moveTo(8);

        RequestLeft? otherLeft;
        var payoutIn = false;
        app.coordinator.onRequest = (request) {
          final body = request.body;
          final decoded = body == null ? null : jsonDecode(utf8.decode(body));
          if (decoded is Map<String, Object?> &&
              decoded['action'] == 'update_invoice') {
            // The other read leaves now, after the payout and before its read after.
            otherLeft = app.reader.requestLeaves();
            payoutIn = true;
          } else if (payoutIn &&
              body == null &&
              request.url.path.endsWith('/api/order/')) {
            // The maker's side moves on before the payout's read after is answered: it reads 10.
            app.coordinator.moveTo(10);
          }
        };
        final invoice = Bolt11TestInvoice(
          network: Bolt11Network.testnet,
          sats: buyerSats,
          seed: 943,
          createdAt: app.now,
          expiry: const Duration(days: 2),
        );
        app.coordinator.decoder.add(invoice);
        final shown = switch (app.payout.check(
          record,
          seen,
          PayoutInvoiceText(
            invoice.text,
            budget: RoutingBudgetPpm.of(0) ?? RoutingBudgetPpm.referenceDefault,
          ),
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('refused: $failure'),
        };
        final given = await app.payout.execute(record, shown);
        app.coordinator.onRequest = null;
        final after = switch (given) {
          Ok(value: PayoutGiven(:final seen)) => seen,
          final other => fail('$other'),
        };
        expect(after.status.position, TradePosition.fiatSent);
        expect(otherLeft, isNotNull);

        // The other read's answer at 9 comes now, after the read after.
        await app.elapse(const Duration(seconds: 1));
        final stale = await app.reader.advance(
          await opened(app, record),
          atNine,
          at: app.now,
          sent: otherLeft ?? fail('no read left'),
        );
        expect(stale.stored, isFalse);
        expect(stale.trade.seen.status.position, TradePosition.fiatSent);
        expect(await positionOnDisk(app, record), 'fiatSent');
      },
    );

    test(
      'a read of the trade that leaves between « fiat sent » and its read after, and answers after that read: the read after stays, and no breach is recorded',
      () async {
        final (app, record, seen, run) = await watchedAt(9);
        await run.subscription.cancel();
        // An answer at 10, as the other read will give it (the coordinator at 10 once « fiat sent » is in).
        app.coordinator.moveTo(10);
        final atTen = await readNow(app, record);
        app.coordinator.moveTo(9);

        RequestLeft? otherLeft;
        var confirmIn = false;
        app.coordinator.onRequest = (request) {
          final body = request.body;
          final decoded = body == null ? null : jsonDecode(utf8.decode(body));
          if (decoded is Map<String, Object?> &&
              decoded['action'] == 'confirm') {
            // The other read leaves now, after the action and before its read after.
            otherLeft = app.reader.requestLeaves();
            confirmIn = true;
          } else if (confirmIn &&
              body == null &&
              request.url.path.endsWith('/api/order/')) {
            // The seller confirms before the read after is answered: it reads 13.
            app.coordinator.moveTo(13);
          }
        };
        final confirmed = await app.chat.confirmFiatSent(record, seen);
        app.coordinator.onRequest = null;
        final after = switch (confirmed) {
          Ok(:final value) => value.seen,
          Err(:final failure) => fail('$failure'),
        };
        expect(after.status.position, TradePosition.sendingSats);
        expect(otherLeft, isNotNull);

        // The other read's answer at 10 comes now, after the read after: along no edge (13 → 10), it would be a breach.
        await app.elapse(const Duration(seconds: 1));
        final stale = await app.reader.advance(
          await opened(app, record),
          atTen,
          at: app.now,
          sent: otherLeft ?? fail('no read left'),
        );
        expect(stale.stored, isFalse);
        expect(stale.trade.seen.status.position, TradePosition.sendingSats);
        expect(await positionOnDisk(app, record), 'sendingSats');
        expect(await breachOnDisk(app, record), isFalse);
      },
    );
  });
}
