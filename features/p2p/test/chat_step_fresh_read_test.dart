import 'package:p2p/src/domain/trade/trade_chat_step.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/src/presentation/trade_cubit.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// An action of the chat step refused by its fresh read (« too early », the chat's end moved later; « status moved »), then the watch's next read fails (review of #161): the screen never goes back to a status older than that fresh read, and the notice stays while it is true; over the real watch and the coordinator the tests play, never a real coordinator.
void main() {
  /// A trade taken, its bond locked, at [status] with the chat's end in an hour, shown by a trade cubit over the real watch; the read of the watch that follows « Open Dispute » fails (Tor).
  Future<(TradeHarness, TradeCubit)> shownAt(int status) async {
    final app = await TradeHarness.start();
    final record = TradeHarness.recordOf(await app.takeShown());
    late final TradeCubit cubit;
    cubit = TradeCubit(
      record,
      app.watch.execute,
      app.cancel.execute,
      startDispute: (record, seen, {onProgress}) async {
        final result = await app.chat.startDispute(
          record,
          seen,
          onProgress: onProgress,
        );
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.unreachable,
        );
        return result;
      },
      lastStored: app.watch.lastStored,
    );
    addTearDown(cubit.close);
    cubit.start();
    await app.settle();
    app.coordinator
      ..lockBond(app.robot(0))
      ..moveTo(status)
      ..moveDeadline(app.now.add(const Duration(hours: 1)));
    cubit.signal(TradeWatchSignal.readNow);
    await app.settle();
    return (app, cubit);
  }

  TradeSeen shown(TradeCubit cubit) =>
      cubit.state.seen ?? (throw StateError('nothing shown'));

  DateTime? deadlineOf(TradeSeen seen) => switch (seen.status) {
    Chatting(:final deadline) => deadline,
    _ => null,
  };

  /// When « Open Dispute » becomes possible by [seen], as the panel and « Order options » judge it.
  DateTime? opensAt(TradeSeen seen) => switch (seen.status) {
    final Chatting chatting => ChatStepAction.disputeOpensAt(chatting),
    _ => null,
  };

  int failedReads(TradeCubit cubit) => switch (cubit.state.watch) {
    TradeWatchStatus(:final failedReads) => failedReads,
    _ => -1,
  };

  ChatStepRefusal? refusalOf(TradeCubit cubit) =>
      switch (cubit.state.chatStep) {
        ChatStepIdle(notice: ChatStepWasRefused(:final refusal)) => refusal,
        _ => null,
      };

  test(
    '« too early » from the fresh read, then the watch\'s read fails: the fresh end stays shown, so does the notice, « Open Dispute » stays off',
    () async {
      final (app, cubit) = await shownAt(9);
      final before = shown(cubit);
      expect(ChatStepAction.dispute.offeredAt(before), isTrue);
      expect(opensAt(before)?.isBefore(app.now), isTrue);
      // The coordinator moves the chat's end later.
      final later = app.now.add(const Duration(hours: 30));
      app.coordinator.moveDeadline(later);
      await cubit.startDispute(before);
      expect(refusalOf(cubit), isA<ChatStepTooEarly>());
      // Shown at once with the fresh read the refusal carries, before the watch reads again.
      expect(failedReads(cubit), 0);
      expect(
        deadlineOf(shown(cubit))?.difference(later).abs(),
        lessThan(const Duration(seconds: 1)),
      );
      await app.settle();
      await app.elapse(const Duration(seconds: 1));
      // The watch's read failed: the status is the fresh read's, never the one from before the action.
      expect(failedReads(cubit), 1);
      final after = shown(cubit);
      expect(
        deadlineOf(after)?.difference(later).abs(),
        lessThan(const Duration(seconds: 1)),
      );
      expect(opensAt(after)?.isAfter(app.now), isTrue);
      expect(refusalOf(cubit), isA<ChatStepTooEarly>());
      expect(
        app.coordinator.received.contains(ScriptedRequest.dispute),
        isFalse,
      );
    },
  );

  test(
    '« status moved » from the fresh read, then the watch\'s read fails: the fresh status stays shown, so does the notice',
    () async {
      final (app, cubit) = await shownAt(10);
      final before = shown(cubit);
      expect(ChatStepAction.dispute.offeredAt(before), isTrue);
      // The seller confirmed meanwhile.
      app.coordinator.moveTo(13);
      await cubit.startDispute(before);
      expect(refusalOf(cubit), isA<ChatStepStatusMoved>());
      expect(shown(cubit).status, isNot(isA<Chatting>()));
      await app.settle();
      await app.elapse(const Duration(seconds: 1));
      expect(failedReads(cubit), 1);
      // Not back at 10, where « Open Dispute » would be offered again.
      expect(shown(cubit).status, isNot(isA<Chatting>()));
      expect(ChatStepAction.dispute.offeredAt(shown(cubit)), isFalse);
      expect(refusalOf(cubit), isA<ChatStepStatusMoved>());
      expect(
        app.coordinator.received.contains(ScriptedRequest.dispute),
        isFalse,
      );
    },
  );

  // An end read by the action's fresh read: the watch never goes back to an open status (security review of #161).
  for (final (end, status, ended) in [
    ('the trade succeeded (14)', 14, isA<Succeeded>()),
    ('the trade was cancelled (12)', 12, isA<Cancelled>()),
  ]) {
    test(
      '« status moved » to an end, $end, then the watch\'s read fails: the end stays shown, the record closed, the notice stays, nothing offered, the watch ends',
      () async {
        final (app, cubit) = await shownAt(10);
        final before = shown(cubit);
        expect(ChatStepAction.dispute.offeredAt(before), isTrue);
        app.coordinator.moveTo(status);
        await cubit.startDispute(before);
        expect(refusalOf(cubit), isA<ChatStepStatusMoved>());
        expect(shown(cubit).status, ended);
        await app.settle();
        await app.elapse(const Duration(seconds: 1));
        expect(failedReads(cubit), 1);
        expect(shown(cubit).status, ended);
        expect(cubit.state.record.closedAt, isNotNull);
        for (final action in ChatStepAction.values) {
          expect(action.offeredAt(shown(cubit)), isFalse, reason: '$action');
        }
        expect(refusalOf(cubit), isA<ChatStepStatusMoved>());
        // At an end the watch has ended: it reads no more, not even when the screen asks.
        final reads = app.coordinator.received
            .where((kind) => kind == ScriptedRequest.order)
            .length;
        cubit.signal(TradeWatchSignal.readNow);
        await app.settle();
        await app.elapse(const Duration(minutes: 10));
        expect(
          app.coordinator.received
              .where((kind) => kind == ScriptedRequest.order)
              .length,
          reads,
        );
        expect(
          app.coordinator.received.contains(ScriptedRequest.dispute),
          isFalse,
        );
      },
    );
  }

  test(
    'the dispute opened (11) by the action, then the watch\'s read fails: the watch goes on from 11, at its cadence, not 9\'s',
    () async {
      final (app, cubit) = await shownAt(9);
      final before = shown(cubit);
      expect(ChatStepAction.dispute.offeredAt(before), isTrue);
      await cubit.startDispute(before);
      expect(shown(cubit).status, isA<InDispute>());
      await app.settle();
      await app.elapse(const Duration(seconds: 1));
      expect(failedReads(cubit), 1);
      expect(shown(cubit).status, isA<InDispute>());
      int orderReads() => app.coordinator.received
          .where((kind) => kind == ScriptedRequest.order)
          .length;
      final reads = orderReads();
      // 9 is read every 10 s (50 s off screen), 11 every 100 s (500 s off screen).
      await app.elapse(const Duration(seconds: 90));
      expect(orderReads(), reads);
    },
  );

  group('the watch\'s rule, at the reader (security review of #161)', () {
    /// The trade of [record] opened from what is stored.
    Future<OpenTrade> opened(TradeHarness app, TradeRecord record) async =>
        switch (await app.reader.open(record)) {
          TradeOpened(:final trade) => trade,
          final other => throw StateError('$other'),
        };

    /// A trade at 9 whose « Open Dispute » an action refused from its fresh read, which it stored.
    Future<(TradeHarness, OpenTrade)> afterAnAction() async {
      final (app, cubit) = await shownAt(9);
      app.coordinator.moveDeadline(app.now.add(const Duration(hours: 30)));
      await cubit.startDispute(shown(cubit));
      expect(refusalOf(cubit), isA<ChatStepTooEarly>());
      return (app, await opened(app, cubit.state.record));
    }

    test('the status stored for this trade is taken', () async {
      final (app, trade) = await afterAnAction();
      final newest = app.reader.newestStored(trade);
      expect(identical(newest, trade), isFalse);
      expect(newest.seen.stored, isTrue);
    });

    test(
      'a status stored for another trade of the same robot is never taken',
      () async {
        final (app, trade) = await afterAnAction();
        final record = trade.record;
        final other = OpenTrade(
          record: TradeRecord(
            robot: record.robot,
            coordinatorAlias: record.coordinatorAlias,
            coordinatorOnion: record.coordinatorOnion,
            orderId: record.orderId + 1,
            role: record.role,
            origin: record.origin,
            takenAt: record.takenAt,
            confirmedAt: record.confirmedAt,
            closedAt: null,
          ),
          robot: trade.robot,
          coordinator: trade.coordinator,
          terms: trade.terms,
          seen: trade.seen,
        );
        expect(identical(app.reader.newestStored(other), other), isTrue);
      },
    );

    test(
      'a trail on disk read after the status kept in memory: the watch keeps its own, as the return to the app checks (#152)',
      () async {
        final (app, trade) = await afterAnAction();
        final newer = OpenTrade(
          record: trade.record,
          robot: trade.robot,
          coordinator: trade.coordinator,
          terms: trade.terms,
          seen: TradeSeen(
            TradeStatus.beforeFirstRead(
              TradeTrail.recovered(
                trade.terms,
                app.now.add(const Duration(minutes: 1)),
              ),
            ),
            order: null,
          ),
        );
        expect(identical(app.reader.newestStored(newer), newer), isTrue);
      },
    );
  });

  test(
    'a failed read with no action meanwhile: the watch keeps its own status, as before',
    () async {
      final (app, cubit) = await shownAt(9);
      final before = shown(cubit);
      app.coordinator.failNext(
        ScriptedRequest.order,
        ScriptedFault.unreachable,
      );
      cubit.signal(TradeWatchSignal.readNow);
      await app.settle();
      expect(failedReads(cubit), 1);
      expect(deadlineOf(shown(cubit)), deadlineOf(before));
      expect(shown(cubit).status.position, before.status.position);
    },
  );
}
