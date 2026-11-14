import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:test/test.dart';

import 'support/key_output.dart';
import 'support/trade_harness.dart';

/// The take in two steps (#119): prepared up to a read of the order by the robot that will take it, the maker's description and the read's figures shown, then confirmed, or abandoned with nothing more sent.
void main() {
  const take = ScriptedRequest.take;
  int count(TradeHarness app, ScriptedRequest kind) =>
      app.coordinator.received.where((k) => k == kind).length;
  Future<int> bindings(TradeHarness app) async =>
      (await app.database.customSelect('SELECT * FROM robot_bindings').get())
          .length;

  Matcher refused<T>() => isA<Err<Object?, TakeRefusal>>().having(
    (err) => err.failure,
    'refusal',
    isA<T>(),
  );

  Future<(TradeHarness, PreparedTake)> prepareOne({
    String? description = 'Revolut only, no notes in the transfer.',
    bool range = false,
  }) async {
    final app = await TradeHarness.start(range: range);
    app.coordinator.description = description;
    final shown = await app.shownOrder();
    final result = await app.take.prepare(
      shown,
      network: app.network,
      amount: range ? TakeAmount.tryCreate(120) : null,
    );
    return switch (result) {
      Ok(:final value) => (app, value),
      Err(:final failure) => fail('not prepared: $failure'),
    };
  }

  group('prepare', () {
    test(
      'reads the order with the fresh robot, shows its description, writes no trade and sends no take',
      () async {
        final (app, prepared) = await prepareOne();
        expect(prepared.description, 'Revolut only, no notes in the transfer.');
        expect(
          prepared.order.satoshisNow?.value.toInt(),
          app.coordinator.satoshisNow,
        );
        expect(prepared.terms.orderId, 42);
        expect(prepared.readAt, app.now);
        expect(prepared.expectedBond, closeTo(3207, 1));
        // The page's book, the fresh book and info, the robot read back then its first contact, the robot's read of the order: no take.
        expect(app.coordinator.received, [
          ScriptedRequest.book,
          ScriptedRequest.book,
          ScriptedRequest.info,
          ScriptedRequest.robot,
          ScriptedRequest.robot,
          ScriptedRequest.order,
        ]);
        expect(await app.allTrades(), isEmpty);
        expect(await bindings(app), 1);
        expect(app.coordinator.holdsPreTake(app.robot(0)), isFalse);
      },
    );

    test('a buy order is refused before anything is sent', () async {
      final app = await TradeHarness.start(orderType: 0);
      final shown = await app.shownOrder();
      final before = app.coordinator.requests.length;
      expect(
        await app.take.prepare(shown, network: app.network),
        refused<TakeOfBuyOrderRefused>(),
      );
      expect(app.coordinator.requests, hasLength(before));
    });

    test(
      'a coordinator that answers the robot otherwise than the book is refused, and the robot is spent',
      () async {
        for (final (label, change) in [
          ('premium', {'premium': '5.00'}),
          ('bond', {'bond_size': '4.00'}),
          ('escrow', {'escrow_duration': 7200}),
          ('sats', {'satoshis_now': 110107}),
        ]) {
          final app = await TradeHarness.start();
          app.coordinator.robotView.addAll(change);
          final shown = await app.shownOrder();
          expect(
            await app.take.prepare(shown, network: app.network),
            refused<TakeOrderChanged>(),
            reason: label,
          );
          expect(count(app, take), 0, reason: label);
          expect(await app.allTrades(), isEmpty, reason: label);
        }
      },
    );

    test(
      'the robot\'s sats within the tolerance of the book\'s but beyond it of the page\'s are refused',
      () async {
        final app = await TradeHarness.start();
        final shown = await app.shownOrder();
        // The book 1.9 % above the page, the robot's read 1.8 % above the book: 3.7 % above what the user saw.
        app.coordinator.satoshisNow = 108900;
        app.coordinator.robotView['satoshis_now'] = 110900;
        expect(
          await app.take.prepare(shown, network: app.network),
          refused<TakeOrderChanged>(),
        );
        expect(count(app, take), 0);
      },
    );

    test(
      'a second preparation of the order reuses its robot, and replaces the first',
      () async {
        final (app, first) = await prepareOne();
        final again = switch (await app.take.prepare(
          await app.shownOrder(),
          network: app.network,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(await bindings(app), 1);
        expect(count(app, ScriptedRequest.robot), 2);
        expect(await app.take.confirm(first), refused<TakePreparationGone>());
        expect(
          await app.take.confirm(again),
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeStarted>(),
          ),
        );
        expect(count(app, take), 1);
      },
    );

    test(
      'a read by the robot that fails keeps the robot for the next preparation',
      () async {
        final app = await TradeHarness.start();
        final shown = await app.shownOrder();
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.unreachable,
        );
        expect(
          await app.take.prepare(shown, network: app.network),
          refused<TakeCoordinatorUnreadable>(),
        );
        expect(
          await app.take.prepare(shown, network: app.network),
          isA<Ok<PreparedTake, TakeRefusal>>(),
        );
        expect(await bindings(app), 1);
      },
    );

    test('an order with an open trade here is not prepared', () async {
      final app = await TradeHarness.start();
      final record = TradeHarness.recordOf(await app.takeShown());
      expect(
        await app.take.prepare(await app.shownOrder(), network: app.network),
        isA<Err<PreparedTake, TakeRefusal>>().having(
          (err) => err.failure,
          'refusal',
          isA<TakeOrderAlreadyTraded>().having(
            (r) => r.record,
            'record',
            record,
          ),
        ),
      );
    });
  });

  group('confirm', () {
    test('sends the take once, on the terms the user saw', () async {
      final (app, prepared) = await prepareOne();
      final taken = await app.take.confirm(prepared);
      final started = switch (taken) {
        Ok(value: final TakeStarted started) => started,
        final other => fail('$other'),
      };
      expect(started.stored, isTrue);
      expect(started.status, isA<WaitingForTakerBond>());
      expect(count(app, take), 1);
      // The robot read again just before the take.
      expect(count(app, ScriptedRequest.order), 2);
      final history = switch (await app.trails.historyOf(started.record)) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(history.terms, prepared.terms.record);
      // Used once.
      expect(
        await app.take.confirm(prepared),
        refused<TakeOrderAlreadyTraded>(),
      );
      expect(count(app, take), 1);
    });

    test('a range order is taken for the amount prepared', () async {
      final (app, prepared) = await prepareOne(range: true);
      expect(prepared.terms.amount.value, 120);
      expect(
        await app.take.confirm(prepared),
        isA<Ok<TakeOutcome, TakeRefusal>>().having(
          (ok) => ok.value,
          'outcome',
          isA<TakeStarted>(),
        ),
      );
    });

    test(
      'figures moved beyond the price tolerance since the read: refused, then prepared again with the same robot',
      () async {
        final (app, prepared) = await prepareOne();
        app.coordinator.satoshisNow = 110107; // 3 % more
        expect(await app.take.confirm(prepared), refused<TakeOrderChanged>());
        expect(count(app, take), 0);
        expect(
          await app.take.confirm(prepared),
          refused<TakePreparationGone>(),
        );
        final again = switch (await app.take.prepare(
          await app.shownOrder(),
          network: app.network,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(await bindings(app), 1);
        expect(
          await app.take.confirm(again),
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeStarted>(),
          ),
        );
      },
    );

    test(
      'figures moved within the price tolerance: taken, on the terms the user saw',
      () async {
        final (app, prepared) = await prepareOne();
        app.coordinator.satoshisNow = 108900; // 1.9 % more
        final taken = await app.take.confirm(prepared);
        expect(taken, isA<Ok<TakeOutcome, TakeRefusal>>());
        final history = switch (await app.trails.historyOf(
          TradeHarness.recordOf(taken),
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(history.terms, prepared.terms.record);
      },
    );

    test('a description changed since the read is refused', () async {
      final (app, prepared) = await prepareOne();
      app.coordinator.description = 'Now pay first to this other account.';
      expect(await app.take.confirm(prepared), refused<TakeOrderChanged>());
      expect(count(app, take), 0);
    });

    test('an order taken by another since the read is gone', () async {
      final (app, prepared) = await prepareOne();
      app.coordinator.takenByAnother();
      expect(await app.take.confirm(prepared), refused<TakeOrderGone>());
      expect(count(app, take), 0);
      expect(await app.allTrades(), isEmpty);
    });

    test('two confirmations at once send one take', () async {
      final (app, prepared) = await prepareOne();
      final both = await Future.wait([
        app.take.confirm(prepared),
        app.take.confirm(prepared),
      ]);
      expect(both.whereType<Ok<TakeOutcome, TakeRefusal>>(), hasLength(1));
      expect(count(app, take), 1);
    });

    test(
      'after a restart nothing is prepared, and the robot stays unused',
      () async {
        final (app, prepared) = await prepareOne();
        final again = app.restart();
        expect(
          await again.take.confirm(prepared),
          refused<TakePreparationGone>(),
        );
        expect(count(app, take), 0);
      },
    );
  });

  group('abandon', () {
    test(
      'sends nothing; the robot is never used again; a later take uses another',
      () async {
        final (app, prepared) = await prepareOne();
        final before = app.coordinator.requests.length;
        app.take.abandon(prepared);
        expect(app.coordinator.requests, hasLength(before));
        expect(
          await app.take.confirm(prepared),
          refused<TakePreparationGone>(),
        );
        final taken = await app.takeShown();
        expect(TradeHarness.recordOf(taken).robot.accountIndex, isNot(0));
        expect(await bindings(app), 2);
        expect(app.coordinator.hasPenalty(app.robot(0)), isFalse);
      },
    );
  });

  test(
    'nothing is printed or logged through a preparation, its confirmation and an abandon',
    () async {
      final output = await captureKeyOutput(() async {
        final (app, first) = await prepareOne();
        app.take.abandon(first);
        final (other, second) = await prepareOne();
        await other.take.confirm(second);
        expect(app, isNotNull);
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
