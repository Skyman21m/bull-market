import 'dart:convert';

import 'package:p2p/testing.dart'
    show ScriptedCoordinator, ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/trade_harness.dart' show TradeHarness, unlockedPairOf;

/// The scripted coordinator plays the actions of the chat step as the reference backend answers them (#95), through the package's client: what the trade's use cases will meet.
void main() {
  const network = RobosatsNetwork.testnet;
  final robots = TradeHarness.robotsOf(network);
  final taker = robots[0];
  final other = robots[1];
  late DateTime now;
  late ScriptedCoordinator coordinator;
  late CoordinatorClient client;

  Future<ScriptedCoordinator> traded({int orderType = 1}) async {
    now = DateTime.utc(2026, 11, 14, 9);
    coordinator = ScriptedCoordinator(
      network: network,
      robots: robots,
      clock: () => now,
      orderType: orderType,
    );
    client = CoordinatorClient(coordinator, clock: () => now);
    final take = await client.takeOrder(
      coordinator.coordinator,
      network,
      identity: taker,
      key: unlockedPairOf(taker),
      orderId: coordinator.orderId,
    );
    expect(take, isA<Ok<TakeOrderOutcome, OrderActionFailure>>());
    coordinator.lockBond(taker);
    return coordinator;
  }

  Future<CoordinatorOrder> read([RobotIdentity? robot]) async =>
      switch (await client.fetchOrder(
        coordinator.coordinator,
        network,
        identity: robot ?? taker,
        orderId: coordinator.orderId,
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };

  /// What the coordinator answers [robot]'s POST of [body], sent as is: its own checks, which the client's checks from a last read would otherwise stop first.
  Future<(int, Object?)> raw(
    RobotIdentity robot,
    Map<String, Object?> body,
  ) async {
    final answer = await coordinator.send(
      CoordinatorRequest(
        method: CoordinatorHttpMethod.post,
        url: Uri.parse(
          'http://${coordinator.coordinator.shortAlias}.onion/api/order/?order_id=${coordinator.orderId}',
        ),
        headers: const {},
        body: utf8.encode(jsonEncode(body)),
        maxResponseBytes: CoordinatorReadBounds.orderBytes,
        robot: robot.sessionKey,
      ),
    );
    return switch (answer) {
      Ok(:final value) => (
        value.statusCode,
        value.body.isEmpty ? null : jsonDecode(utf8.decode(value.body)),
      ),
      Err(:final failure) => fail('$failure'),
    };
  }

  Object? codeOf((int, Object?) answer) => switch (answer.$2) {
    final Map<String, Object?> body => body['error_code'],
    _ => null,
  };

  CoordinatorFailure refusedCause(
    Result<TradeActionOutcome, OrderActionFailure> result,
  ) => switch (result) {
    Err(failure: OrderActionRefused(:final cause)) => cause,
    _ => fail('expected a refusal, got $result'),
  };

  CoordinatorOrder accepted(
    Result<TradeActionOutcome, OrderActionFailure> result,
  ) => switch (result) {
    Ok(:final value) => value.order,
    Err(:final failure) => fail('$failure'),
  };

  group('« fiat sent » and its undo', () {
    test('9 → 10 and back, the step\'s deadline kept', () async {
      await traded();
      coordinator.moveTo(9);
      final chat = await read();
      // « fiat sent » an hour into the chat: its deadline is the chat's, not restarted (`api/logics.py:1693-1699`).
      now = now.add(const Duration(hours: 1));
      final sent = accepted(
        await client.confirmFiat(
          identity: taker,
          key: unlockedPairOf(taker),
          lastRead: chat,
        ),
      );
      expect(sent.status, CoordinatorOrderStatus.fiatSent);
      expect(sent.isFiatSent, isTrue);
      expect(sent.expiresAt, chat.expiresAt);
      final back = accepted(
        await client.undoConfirmFiat(
          identity: taker,
          key: unlockedPairOf(taker),
          lastRead: sent,
        ),
      );
      expect(back.status, CoordinatorOrderStatus.sendingFiat);
      expect(back.isFiatSent, isFalse);
      expect(coordinator.revertedFiatSent, isTrue);
      expect(coordinator.received.where((r) => r == ScriptedRequest.confirm), [
        ScriptedRequest.confirm,
      ]);
    });

    test('a second « fiat sent » at 10 changes nothing', () async {
      await traded();
      coordinator.moveTo(9);
      final chat = await read();
      accepted(
        await client.confirmFiat(
          identity: taker,
          key: unlockedPairOf(taker),
          lastRead: chat,
        ),
      );
      // Sent from a stale read of 9, the coordinator at 10 already.
      final again = accepted(
        await client.confirmFiat(
          identity: taker,
          key: unlockedPairOf(taker),
          lastRead: chat,
        ),
      );
      expect(again.status, CoordinatorOrderStatus.fiatSent);
      expect(coordinator.status, 10);
    });

    test('refused with the reference\'s codes once the order moved', () async {
      await traded();
      coordinator.moveTo(9);
      final chat = await read();
      coordinator.moveTo(11);
      expect(
        refusedCause(
          await client.confirmFiat(
            identity: taker,
            key: unlockedPairOf(taker),
            lastRead: chat,
          ),
        ),
        isA<TradeActionNotNow>().having(
          (f) => f.fromLastRead,
          'fromLastRead',
          isFalse,
        ),
      );
      coordinator.moveTo(10);
      final sent = await read();
      coordinator.moveTo(9);
      expect(
        refusedCause(
          await client.undoConfirmFiat(
            identity: taker,
            key: unlockedPairOf(taker),
            lastRead: sent,
          ),
        ),
        isA<TradeActionNotNow>(),
      );
      expect(coordinator.status, 9);
    });

    test('the seller may not undo, and confirms only after it', () async {
      await traded(orderType: 0);
      coordinator.moveTo(9);
      expect(codeOf(await raw(taker, {'action': 'confirm'})), 1027);
      coordinator.moveTo(10);
      expect(codeOf(await raw(taker, {'action': 'undo_confirm'})), 1030);
      expect(coordinator.status, 10);
      expect((await raw(taker, {'action': 'confirm'})).$1, 200);
      expect(coordinator.status, 13);
    });

    test(
      'a request that lands late: the read after still shows 9, then 10 once it lands, and a second tap changes nothing',
      () async {
        await traded();
        coordinator.moveTo(9);
        final chat = await read();
        coordinator.failNext(ScriptedRequest.confirm, ScriptedFault.landsLate);
        final first = await client.confirmFiat(
          identity: taker,
          key: unlockedPairOf(taker),
          lastRead: chat,
        );
        expect(
          (first as Err<TradeActionOutcome, OrderActionFailure>).failure,
          isA<OrderActionOutcomeUnknown>(),
        );
        final before = await read();
        expect(before.status, CoordinatorOrderStatus.sendingFiat);
        coordinator.landLate();
        expect(coordinator.status, 10);
        // A second tap from the read that showed 9: one confirmed state, no error.
        final second = accepted(
          await client.confirmFiat(
            identity: taker,
            key: unlockedPairOf(taker),
            lastRead: before,
          ),
        );
        expect(second.status, CoordinatorOrderStatus.fiatSent);
        expect(coordinator.status, 10);
      },
    );

    test('an answer lost after the coordinator acted: a read tells', () async {
      await traded();
      coordinator.moveTo(9);
      final chat = await read();
      coordinator.failNext(ScriptedRequest.confirm, ScriptedFault.answerLost);
      final lost = await client.confirmFiat(
        identity: taker,
        key: unlockedPairOf(taker),
        lastRead: chat,
      );
      expect(lost, isA<Err<TradeActionOutcome, OrderActionFailure>>());
      expect(
        (lost as Err<TradeActionOutcome, OrderActionFailure>).failure,
        isA<OrderActionOutcomeUnknown>(),
      );
      final after = await read();
      expect(after.status, CoordinatorOrderStatus.fiatSent);
      expect(after.isFiatSent, isTrue);
    });
  });

  group('the collaborative cancel', () {
    test(
      'asked by this robot first: its flag raised, the order going on',
      () async {
        await traded();
        coordinator.moveTo(9);
        final chat = await read();
        expect(chat.askedToCancel, isFalse);
        final asked = switch (await client.cancelOrder(
          identity: taker,
          key: unlockedPairOf(taker),
          lastRead: chat,
        )) {
          Ok(value: OrderCancelAccepted(:final order)) => order,
          final other => fail('$other'),
        };
        expect(asked.askedToCancel, isTrue);
        expect(asked.peerAskedToCancel, isNull);
        expect(coordinator.takerAskedCancel, isTrue);
      },
    );

    test(
      'asked by the peer first: pending, then ended by this robot\'s ask',
      () async {
        await traded();
        coordinator.moveTo(9);
        coordinator.peerAsksToCancel();
        final chat = await read();
        expect(chat.peerAskedToCancel, isTrue);
        expect(chat.askedToCancel, isNull);
        final ended = await client.cancelOrder(
          identity: taker,
          key: unlockedPairOf(taker),
          lastRead: chat,
        );
        expect(
          ended,
          isA<Ok<CancelOrderOutcome, OrderActionFailure>>().having(
            (r) => r.value,
            'value',
            isA<OrderCancelEnded>().having(
              (o) => o.status,
              'status',
              CoordinatorOrderStatus.collaborativelyCancelled,
            ),
          ),
        );
        expect(coordinator.status, 12);
        expect(
          await client.fetchOrder(
            coordinator.coordinator,
            network,
            identity: taker,
            orderId: coordinator.orderId,
          ),
          isA<Err<CoordinatorOrder, CoordinatorFailure>>().having(
            (r) => r.failure,
            'failure',
            isA<OrderCancelled>(),
          ),
        );
      },
    );

    test('asked by this robot, accepted by the peer: 12 for both', () async {
      await traded();
      coordinator.moveTo(9);
      final chat = await read();
      expect(
        await client.cancelOrder(
          identity: taker,
          key: unlockedPairOf(taker),
          lastRead: chat,
        ),
        isA<Ok<CancelOrderOutcome, OrderActionFailure>>(),
      );
      coordinator.peerAcceptsCancel();
      expect(coordinator.status, 12);
      expect(
        await client.fetchOrder(
          coordinator.coordinator,
          network,
          identity: taker,
          orderId: coordinator.orderId,
        ),
        isA<Err<CoordinatorOrder, CoordinatorFailure>>().having(
          (r) => r.failure,
          'failure',
          isA<OrderCancelled>(),
        ),
      );
    });

    test('the peer cannot accept what was not asked', () async {
      await traded();
      coordinator.moveTo(9);
      expect(coordinator.peerAcceptsCancel, throwsStateError);
      expect(coordinator.status, 9);
    });

    test('refused once the fiat is sent: the guard, then 1021', () async {
      await traded();
      coordinator.moveTo(9);
      final chat = await read();
      coordinator.moveTo(10);
      expect(
        await client.cancelOrder(
          identity: taker,
          key: unlockedPairOf(taker),
          lastRead: chat,
        ),
        isA<Err<CancelOrderOutcome, OrderActionFailure>>().having(
          (r) => r.failure.cause,
          'cause',
          isA<OrderStatusChanged>(),
        ),
      );
      final sent = await read();
      expect(
        await client.cancelOrder(
          identity: taker,
          key: unlockedPairOf(taker),
          lastRead: sent,
        ),
        isA<Err<CancelOrderOutcome, OrderActionFailure>>().having(
          (r) => r.failure.cause,
          'cause',
          isA<OrderNotCancellable>(),
        ),
      );
      expect(coordinator.status, 10);
    });
  });

  group('the dispute', () {
    test('not before 18 hours before the chat ends, then 11', () async {
      await traded();
      coordinator.moveTo(9);
      final chat = await read();
      // The coordinator's own clock decides: this client's clock is ahead.
      final early = CoordinatorClient(
        coordinator,
        clock: () => now.add(const Duration(hours: 6)),
      );
      expect(
        refusedCause(
          await early.openDispute(
            identity: taker,
            key: unlockedPairOf(taker),
            lastRead: chat,
          ),
        ),
        isA<DisputeTooEarly>().having(
          (f) => f.fromLastRead,
          'fromLastRead',
          isFalse,
        ),
      );
      expect(coordinator.status, 9);
      now = now.add(const Duration(hours: 6));
      final open = accepted(
        await client.openDispute(
          identity: taker,
          key: unlockedPairOf(taker),
          lastRead: chat,
        ),
      );
      expect(open.status, CoordinatorOrderStatus.inDispute);
      expect(open.statementSubmitted, isFalse);
      // The dispute's own time: a day from its opening (`api/logics.py:510-512`, `t_to_expire(11)`).
      expect(open.expiresAt, now.add(const Duration(days: 1)));
    });

    test('refused outside 9 and 10', () async {
      await traded();
      coordinator.moveTo(9);
      now = now.add(const Duration(hours: 7));
      final chat = await read();
      coordinator.moveTo(13);
      expect(
        refusedCause(
          await client.openDispute(
            identity: taker,
            key: unlockedPairOf(taker),
            lastRead: chat,
          ),
        ),
        isA<TradeActionNotNow>(),
      );
    });
  });

  group('the rating', () {
    test('kept, the latest one wins', () async {
      await traded();
      coordinator.moveTo(14);
      final done = await read();
      for (final stars in [4, 2]) {
        accepted(
          await client.ratePlatform(
            identity: taker,
            key: unlockedPairOf(taker),
            lastRead: done,
            rating: PlatformRating.of(stars)!,
          ),
        );
        expect(coordinator.platformRating, stars);
      }
    });
  });

  test(
    'a robot that is no participant gets 1047, a bad rating an empty 400',
    () async {
      await traded();
      coordinator.moveTo(9);
      for (final action in ['confirm', 'undo_confirm', 'dispute']) {
        final answer = await raw(other, {'action': action});
        expect(answer.$1, 403);
        expect(codeOf(answer), 1047);
      }
      expect(coordinator.status, 9);
      final unrated = await raw(taker, {'action': 'rate_platform'});
      expect(unrated.$1, 501);
      expect(codeOf(unrated), 1049);
      final blank = await raw(taker, {'action': 'rate_platform', 'rating': ''});
      expect(blank.$1, 501);
      expect(codeOf(blank), 1049);
      final unknown = await raw(taker, {'action': 'rate_user', 'rating': 5});
      expect(unknown, (400, null));
      for (final rating in [0, 6, 'five']) {
        final answer = await raw(taker, {
          'action': 'rate_platform',
          'rating': rating,
        });
        expect(answer, (400, null), reason: '$rating');
      }
      expect(coordinator.platformRating, isNull);
    },
  );
}
