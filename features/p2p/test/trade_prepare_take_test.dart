import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/trade/trade_status.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/prepared_takes.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/testing.dart'
    show ScriptedCoordinator, ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart'
    show CoordinatorHttpMethod, OrderType, RobotHashId, RobotIdentity;
import 'package:test/test.dart';

import 'support/key_output.dart';
import 'support/prepared_takes.dart';
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
        // The most the state machine takes of the bond invoice: 3,207 and 2 % of it, plus one sat (3,272.14).
        expect(prepared.bondCeiling, 3272);
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

    test(
      'a buy order is prepared as a sell order is: its taker sells (#96)',
      () async {
        final app = await TradeHarness.start(orderType: 0);
        final shown = await app.shownOrder();
        final prepared = switch (await app.take.prepare(
          shown,
          network: app.network,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('not prepared: $failure'),
        };
        expect(prepared.terms.role, TradeRole.seller);
        expect(prepared.terms.type, OrderType.buy);
        expect(app.coordinator.received.last, ScriptedRequest.order);
        expect(await app.allTrades(), isEmpty);
      },
    );

    test(
      'a coordinator that answers the robot otherwise than the book is refused; nothing is taken, and a new preparation of the order reuses the robot',
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
          app.coordinator.robotView.clear();
          expect(
            await app.take.prepare(shown, network: app.network),
            isA<Ok<PreparedTake, TakeRefusal>>(),
            reason: label,
          );
          expect(await bindings(app), 1, reason: label);
          expect(count(app, take), 0, reason: label);
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

  group('the page against the book read again (security review of #133, I1)', () {
    final maker = switch (RobotHashId.parse(
      '0ddba11c0ffee5ca1ab1e0ddba11c0ffee5ca1ab1e0ddba11c0ffee5ca1ab1e0',
    )) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    for (final (label, book, robot)
        in <(String, Map<String, Object?>, Map<String, Object?>)>[
          (
            'payment methods',
            {'payment_method': 'Wise'},
            {'payment_method': 'Wise'},
          ),
          (
            'maker',
            {'maker_hash_id': maker.hex},
            {'maker_hash_id': maker.hex, 'maker_nick': maker.nickname},
          ),
        ]) {
      test(
        'the $label of the book read again other than the page\'s: the order changed, before any robot, in both ways of taking',
        () async {
          final app = await TradeHarness.start();
          final shown = await app.shownOrder();
          app.coordinator.bookView.addAll(book);
          app.coordinator.robotView.addAll(robot);
          expect(
            await app.take.prepare(shown, network: app.network),
            refused<TakeOrderChanged>(),
          );
          expect(
            await app.take.execute(shown, network: app.network),
            refused<TakeOrderChanged>(),
          );
          expect(count(app, ScriptedRequest.robot), 0);
          expect(count(app, take), 0);
        },
      );
    }
  });

  group('the steps a take says (#119)', () {
    test(
      'a first preparation: the order checked, the robot built, the order read; a confirmation: read again, the take sent',
      () async {
        final app = await TradeHarness.start();
        final steps = <TakeStep>[];
        final prepared = switch (await app.take.prepare(
          await app.shownOrder(),
          network: app.network,
          onStep: steps.add,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(steps, [
          TakeStep.checkingOrder,
          TakeStep.creatingRobot,
          TakeStep.readingOrder,
        ]);
        steps.clear();
        await app.take.confirm(prepared, onStep: steps.add);
        expect(steps, [TakeStep.readingOrderAgain, TakeStep.sendingTake]);
      },
    );

    test('a preparation that reuses its robot builds none', () async {
      final (app, _) = await prepareOne();
      final steps = <TakeStep>[];
      await app.take.prepare(
        await app.shownOrder(),
        network: app.network,
        onStep: steps.add,
      );
      expect(steps, [TakeStep.checkingOrder, TakeStep.readingOrder]);
    });

    test(
      'a take refused before its robot says no later step; a confirmation refused at its read sends no take step',
      () async {
        final app = await TradeHarness.start(takerFee: 0.05);
        final steps = <TakeStep>[];
        await app.take.prepare(
          await app.shownOrder(),
          network: app.network,
          onStep: steps.add,
        );
        expect(steps, [TakeStep.checkingOrder]);

        final (other, prepared) = await prepareOne();
        other.coordinator.takenByAnother();
        steps.clear();
        await other.take.confirm(prepared, onStep: steps.add);
        expect(steps, [TakeStep.readingOrderAgain]);
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

  group('orders priced in sats (review of #126, I1)', () {
    Future<TradeHarness> explicitOrder() async {
      final app = await TradeHarness.start();
      app.coordinator.explicitSatoshis = 106900;
      return app;
    }

    test(
      'prepared from the robot\'s read, whose premium is null, then taken: the premium is the coordinator\'s at the price now',
      () async {
        final app = await explicitOrder();
        final prepared = switch (await app.take.prepare(
          await app.shownOrder(),
          network: app.network,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('not prepared: $failure'),
        };
        expect(prepared.order.premium, isNull);
        expect(prepared.terms.explicitSatoshis?.value.toInt(), 106900);
        expect(prepared.terms.premium.percent, 2.0);
        final taken = await app.take.confirm(prepared);
        final started = switch (taken) {
          Ok(value: final TakeStarted started) => started,
          final other => fail('$other'),
        };
        expect(started.stored, isTrue);
        expect(started.status, isA<WaitingForTakerBond>());
        // The terms stored are read back, and the trade is followed.
        final history = switch (await app.trails.historyOf(started.record)) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(history.terms, prepared.terms.record);
        expect(await app.reader.open(started.record), isA<TradeOpened>());
      },
    );

    test('taken in one step as before', () async {
      final app = await explicitOrder();
      final taken = await app.takeShown();
      expect(
        taken,
        isA<Ok<TakeOutcome, TakeRefusal>>().having(
          (ok) => ok.value,
          'outcome',
          isA<TakeStarted>(),
        ),
      );
      expect(
        await app.reader.open(TradeHarness.recordOf(taken)),
        isA<TradeOpened>(),
      );
    });

    test(
      'the robot\'s sats of the order otherwise than the book\'s are refused, at the preparation and at the confirmation',
      () async {
        final app = await explicitOrder();
        app.coordinator.robotView['satoshis'] = 107000;
        expect(
          await app.take.prepare(await app.shownOrder(), network: app.network),
          refused<TakeOrderChanged>(),
        );
        app.coordinator.robotView.clear();
        final prepared = switch (await app.take.prepare(
          await app.shownOrder(),
          network: app.network,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('not prepared: $failure'),
        };
        app.coordinator.robotView['satoshis'] = 107000;
        expect(await app.take.confirm(prepared), refused<TakeOrderChanged>());
        expect(count(app, take), 0);
      },
    );
  });

  group('a refusal that needs no robot costs none (review of #126, I2)', () {
    // Each case: how to start, what to do to the coordinator once the page is shown, and the amount taken.
    final cases =
        <
          (
            String,
            Future<TradeHarness> Function(),
            void Function(TradeHarness),
            TakeAmount?,
          )
        >[
          (
            'a taker fee above the ceiling',
            () => TradeHarness.start(takerFee: 0.05),
            (_) {},
            null,
          ),
          (
            'no sats at the current price',
            TradeHarness.start,
            (app) => app.coordinator.bookView['satoshis_now'] = null,
            null,
          ),
          (
            'figures changed since the page',
            TradeHarness.start,
            (app) => app.coordinator.bookView['premium'] = '5.00',
            null,
          ),
          (
            'an order gone from the book',
            TradeHarness.start,
            (app) => app.coordinator.takenByAnother(),
            null,
          ),
          (
            'an amount out of the range',
            () => TradeHarness.start(range: true),
            (_) {},
            TakeAmount.tryCreate(300),
          ),
          (
            'a coordinator that cannot be read',
            TradeHarness.start,
            (app) => app.coordinator.failNext(
              ScriptedRequest.info,
              ScriptedFault.unreachable,
            ),
            null,
          ),
        ];
    for (final (label, start, change, amount) in cases) {
      test(label, () async {
        final one = await start();
        final shownOne = await one.shownOrder();
        change(one);
        final executed = await one.take.execute(
          shownOne,
          network: one.network,
          amount: amount,
        );
        final two = await start();
        final shownTwo = await two.shownOrder();
        change(two);
        final prepared = await two.take.prepare(
          shownTwo,
          network: two.network,
          amount: amount,
        );
        final refusalOne = switch (executed) {
          Err(:final failure) => failure,
          Ok() => fail('taken'),
        };
        final refusalTwo = switch (prepared) {
          Err(:final failure) => failure,
          Ok() => fail('prepared'),
        };
        expect(refusalTwo.runtimeType, refusalOne.runtimeType);
        if ((refusalOne, refusalTwo) case (
          TakeTermsRefused(reason: final a),
          TakeTermsRefused(reason: final b),
        )) {
          expect(b.runtimeType, a.runtimeType);
        }
        for (final app in [one, two]) {
          expect(await bindings(app), 0);
          expect(count(app, ScriptedRequest.robot), 0);
          expect(count(app, ScriptedRequest.order), 0);
        }
      });
    }
  });

  group('the Garage Key changed since the preparation (review of #126, I3)', () {
    for (final (label, change) in [
      ('deleted', (TradeHarness app) => app.deleteKey()),
      ('replaced by another', (TradeHarness app) => app.replaceKey()),
    ]) {
      test(
        '$label: the take is not sent, and the preparation is gone',
        () async {
          final (app, prepared) = await prepareOne();
          change(app);
          expect(
            await app.take.confirm(prepared),
            refused<TakePreparationGone>(),
          );
          expect(count(app, take), 0);
          expect(await app.allTrades(), isEmpty);
          expect(
            await app.take.confirm(prepared),
            refused<TakePreparationGone>(),
          );
          // No second read: the preparation was forgotten.
          expect(count(app, ScriptedRequest.order), 2);
        },
      );
    }

    test(
      'deleted while a take in one step puts its robot on the coordinator: not sent',
      () async {
        final app = await TradeHarness.start();
        final shown = await app.shownOrder();
        app.coordinator.onRequest = (request) {
          if (request.url.path == '/api/robot/') app.deleteKey();
        };
        expect(
          await app.take.execute(shown, network: app.network),
          isA<Err<TakeOutcome, TakeRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<TakeRobotRefused>().having(
              (r) => r.failure,
              'failure',
              isA<TradeKeyMissingFailure>(),
            ),
          ),
        );
        expect(count(app, take), 0);
        expect(await app.allTrades(), isEmpty);
      },
    );

    for (final (label, change, refusal) in [
      (
        'deleted',
        (TradeHarness app) => app.deleteKey(),
        isA<GarageKeyMissingFailure>(),
      ),
    ]) {
      test(
        '$label: a new preparation of the order does not use the robot kept for it (second review of #126, n1)',
        () async {
          final (app, _) = await prepareOne();
          final reads = count(app, ScriptedRequest.order);
          change(app);
          expect(
            await app.take.prepare(
              await app.shownOrder(),
              network: app.network,
            ),
            isA<Err<PreparedTake, TakeRefusal>>().having(
              (err) => err.failure,
              'refusal',
              isA<TakeRobotRefused>().having(
                (r) => r.failure,
                'failure',
                refusal,
              ),
            ),
          );
          // The robot of the earlier key read nothing more.
          expect(count(app, ScriptedRequest.order), reads);
        },
      );
    }
  });

  group('the robot\'s read again at the confirmation (review of #126, I4)', () {
    final maker = switch (RobotHashId.parse(
      '0ddba11c0ffee5ca1ab1e0ddba11c0ffee5ca1ab1e0ddba11c0ffee5ca1ab1e0',
    )) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    for (final (label, change) in <(String, Map<String, Object?>)>[
      ('bond size', {'bond_size': '4.00'}),
      ('amount', {'amount': '101.00000000'}),
      ('premium', {'premium': '2.50', 'premium_now': 2.5}),
      ('escrow duration', {'escrow_duration': 7200}),
      ('currency', {'currency': 1}),
      ('type', {'type': 0}),
      ('payment methods', {'payment_method': 'Wise'}),
      ('maker', {'maker_hash_id': maker.hex, 'maker_nick': maker.nickname}),
    ]) {
      test(
        'a $label changed since the read is refused, and the robot kept for a new preparation',
        () async {
          final (app, prepared) = await prepareOne();
          app.coordinator.robotView.addAll(change);
          expect(await app.take.confirm(prepared), refused<TakeOrderChanged>());
          expect(count(app, take), 0);
          expect(await app.allTrades(), isEmpty);
          app.coordinator.robotView.clear();
          expect(
            await app.take.prepare(
              await app.shownOrder(),
              network: app.network,
            ),
            isA<Ok<PreparedTake, TakeRefusal>>(),
          );
          expect(await bindings(app), 1);
        },
      );
    }
  });

  group('the robot\'s read against the book (review of #126, I4, m4)', () {
    final maker = switch (RobotHashId.parse(
      '0ddba11c0ffee5ca1ab1e0ddba11c0ffee5ca1ab1e0ddba11c0ffee5ca1ab1e0',
    )) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    for (final (label, change) in <(String, Map<String, Object?>)>[
      ('type', {'type': 0}),
      ('currency', {'currency': 1}),
      ('amount', {'amount': '101.00000000'}),
      (
        'range',
        {
          'has_range': true,
          'amount': null,
          'min_amount': '50.00000000',
          'max_amount': '200.00000000',
        },
      ),
      ('payment methods', {'payment_method': 'Wise'}),
      ('maker', {'maker_hash_id': maker.hex, 'maker_nick': maker.nickname}),
    ]) {
      test('a $label otherwise than the book\'s is refused', () async {
        final app = await TradeHarness.start();
        app.coordinator.robotView.addAll(change);
        expect(
          await app.take.prepare(await app.shownOrder(), network: app.network),
          refused<TakeOrderChanged>(),
        );
        expect(count(app, take), 0);
      });
    }

    test(
      'the robot\'s sats beyond the tolerance of the book\'s, though each is within it of the page\'s, are refused',
      () async {
        final app = await TradeHarness.start();
        final shown = await app.shownOrder();
        // The book 1.9 % above the page, the robot's read 1.8 % below it: 3.6 % apart.
        app.coordinator.satoshisNow = 108900;
        app.coordinator.robotView['satoshis_now'] = 104950;
        expect(
          await app.take.prepare(shown, network: app.network),
          refused<TakeOrderChanged>(),
        );
        expect(count(app, take), 0);
      },
    );

    // A read of an order that is not public by a robot that takes no part in it is refused by the package itself (`CoordinatorOrder`): only a participant's read can show one.
    for (final (label, change)
        in <(String, Map<String, Object?> Function(RobotIdentity))>[
          (
            'a public order the robot is said to have taken',
            (robot) => {
              'is_participant': true,
              'is_taker': true,
              'taker': 8,
              'taker_hash_id': robot.hashId.hex,
              'taker_nick': robot.nickname,
              'is_buyer': true,
              'is_seller': false,
              'ur_nick': robot.nickname,
            },
          ),
          ('an order with a password', (_) => {'has_password': true}),
        ]) {
      test('$label is gone, and its robot is never used again', () async {
        final app = await TradeHarness.start();
        app.coordinator.robotView.addAll(change(app.robot(0)));
        expect(
          await app.take.prepare(await app.shownOrder(), network: app.network),
          refused<TakeOrderGone>(),
        );
        app.coordinator.robotView.clear();
        expect(
          await app.take.prepare(await app.shownOrder(), network: app.network),
          isA<Ok<PreparedTake, TakeRefusal>>(),
        );
        expect(await bindings(app), 2);
      });
    }
  });

  group('the robot of a preparation (review of #126, I4, m1, m2, m3)', () {
    test(
      'a take refused after its confirmation: a new preparation takes a fresh robot',
      () async {
        final (app, prepared) = await prepareOne();
        app.coordinator.takesNotMade = true;
        expect(
          await app.take.confirm(prepared),
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeNotMade>(),
          ),
        );
        app.coordinator.takesNotMade = false;
        expect(
          await app.take.prepare(await app.shownOrder(), network: app.network),
          isA<Ok<PreparedTake, TakeRefusal>>(),
        );
        expect(await bindings(app), 2);
      },
    );

    test(
      'an order gone at the confirmation: the preparation is forgotten with its robot',
      () async {
        final (app, prepared) = await prepareOne();
        app.coordinator.takenByAnother();
        expect(await app.take.confirm(prepared), refused<TakeOrderGone>());
        expect(
          await app.take.confirm(prepared),
          refused<TakePreparationGone>(),
        );
        expect(count(app, ScriptedRequest.order), 2);
        app.coordinator.backToPublic();
        expect(
          await app.take.prepare(await app.shownOrder(), network: app.network),
          isA<Ok<PreparedTake, TakeRefusal>>(),
        );
        expect(await bindings(app), 2);
      },
    );

    test(
      'an order gone from the book at a new preparation: its robot is forgotten',
      () async {
        final (app, _) = await prepareOne();
        final shown = await app.shownOrder();
        app.coordinator.takenByAnother();
        expect(
          await app.take.prepare(shown, network: app.network),
          refused<TakeOrderGone>(),
        );
        app.coordinator.backToPublic();
        expect(
          await app.take.prepare(await app.shownOrder(), network: app.network),
          isA<Ok<PreparedTake, TakeRefusal>>(),
        );
        expect(await bindings(app), 2);
      },
    );

    test(
      'a preparation, then a take in one step, then its confirmation: already traded, nothing more sent',
      () async {
        final (app, prepared) = await prepareOne();
        final record = TradeHarness.recordOf(await app.takeShown());
        final orderReads = count(app, ScriptedRequest.order);
        expect(
          await app.take.confirm(prepared),
          isA<Err<TakeOutcome, TakeRefusal>>().having(
            (err) => err.failure,
            'refusal',
            isA<TakeOrderAlreadyTraded>().having(
              (r) => r.record,
              'record',
              record,
            ),
          ),
        );
        expect(count(app, ScriptedRequest.order), orderReads);
        expect(count(app, take), 1);
        // Its robot was forgotten: once that trade is closed, a new preparation takes a third robot.
        expect(
          await app.records.closeTrade(record),
          isA<Ok<Object?, Object?>>(),
        );
        expect(
          await app.take.prepare(await app.shownOrder(), network: app.network),
          isA<Ok<PreparedTake, TakeRefusal>>(),
        );
        expect(await bindings(app), 3);
      },
    );

    test(
      'a confirmation behind a take in one step of the same order waits for it, and sends nothing',
      () async {
        final (app, prepared) = await prepareOne();
        final shown = await app.shownOrder();
        final orderReads = count(app, ScriptedRequest.order);
        final results = await Future.wait([
          app.take.execute(shown, network: app.network),
          app.take.confirm(prepared),
        ]);
        expect(results.first, isA<Ok<TakeOutcome, TakeRefusal>>());
        expect(results.last, refused<TakeOrderAlreadyTraded>());
        expect(count(app, ScriptedRequest.order), orderReads);
        expect(count(app, take), 1);
      },
    );

    test(
      'abandoned while the confirmation reads the order: the take is not sent',
      () async {
        final (app, prepared) = await prepareOne();
        app.coordinator.onRequest = (request) {
          if (request.url.path == '/api/order/' &&
              request.method == CoordinatorHttpMethod.get) {
            app.take.abandon(prepared);
          }
        };
        expect(
          await app.take.confirm(prepared),
          refused<TakePreparationGone>(),
        );
        expect(count(app, take), 0);
        expect(await app.allTrades(), isEmpty);
      },
    );

    test(
      'the abandon of a preparation replaced by a newer one leaves the newer one',
      () async {
        final (app, first) = await prepareOne();
        final second = switch (await app.take.prepare(
          await app.shownOrder(),
          network: app.network,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        app.take.abandon(first);
        expect(
          await app.take.confirm(second),
          isA<Ok<TakeOutcome, TakeRefusal>>().having(
            (ok) => ok.value,
            'outcome',
            isA<TakeStarted>(),
          ),
        );
      },
    );

    test(
      'the abandon of a preparation refused at its confirmation forgets its robot',
      () async {
        final (app, prepared) = await prepareOne();
        app.coordinator.satoshisNow = 110107;
        expect(await app.take.confirm(prepared), refused<TakeOrderChanged>());
        app.take.abandon(prepared);
        app.coordinator.satoshisNow = ScriptedCoordinator.bookSats;
        expect(
          await app.take.prepare(await app.shownOrder(), network: app.network),
          isA<Ok<PreparedTake, TakeRefusal>>(),
        );
        expect(await bindings(app), 2);
      },
    );

    test(
      'a screen that leaves after a preparation that failed abandons the order: its robot is forgotten',
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
        app.take.abandonOrder(shown, network: app.network);
        expect(
          await app.take.prepare(shown, network: app.network),
          isA<Ok<PreparedTake, TakeRefusal>>(),
        );
        expect(await bindings(app), 2);
      },
    );

    test(
      'abandoned while it reads the order: the preparation is gone, and its robot not kept',
      () async {
        final app = await TradeHarness.start();
        final shown = await app.shownOrder();
        app.coordinator.onRequest = (request) {
          if (request.url.path == '/api/order/') {
            app.take.abandonOrder(shown, network: app.network);
          }
        };
        expect(
          await app.take.prepare(shown, network: app.network),
          refused<TakePreparationGone>(),
        );
        app.coordinator.onRequest = null;
        expect(
          await app.take.prepare(shown, network: app.network),
          isA<Ok<PreparedTake, TakeRefusal>>(),
        );
        expect(await bindings(app), 2);
      },
    );

    test(
      'one order prepared at a time: another order\'s forgets the first\'s robot',
      () async {
        final app = await TradeHarness.start();
        final coordinator = app.coordinator.coordinator;
        final first = switch (await app.robots.robotForNewTrade(
          app.network,
          coordinator,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        final second = switch (await app.robots.robotForNewTrade(
          app.network,
          coordinator,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        final takes = PreparedTakes()
          ..keepRobot(
            app.network,
            coordinator.shortAlias,
            42,
            first,
            garageRobot: null,
          );
        expect(takes.robotFor(app.network, coordinator.shortAlias, 42), first);
        takes.keepRobot(
          app.network,
          coordinator.shortAlias,
          43,
          second,
          garageRobot: null,
        );
        expect(takes.robotFor(app.network, coordinator.shortAlias, 42), isNull);
        expect(takes.robotFor(app.network, coordinator.shortAlias, 43), second);
        takes.releaseOrder(app.network, coordinator.shortAlias, 42);
        expect(takes.robotFor(app.network, coordinator.shortAlias, 43), second);
        takes.releaseOrder(app.network, coordinator.shortAlias, 43);
        expect(takes.robotFor(app.network, coordinator.shortAlias, 43), isNull);
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

  group('PreparedTake.showsTheSameAs (second security review of #133)', () {
    test('the same read shows the same', () async {
      expect(
        (await preparedTake()).showsTheSameAs(await preparedTake()),
        isTrue,
      );
    });

    test(
      'another taker fee alone does not: the sats shown depend on it',
      () async {
        expect(
          (await preparedTake()).showsTheSameAs(await preparedTake(fee: 0.002)),
          isFalse,
        );
      },
    );

    test('another price and sats alone do not', () async {
      final figures = await preparedTake(
        changes: {'price_now': 95000.0, 'satoshis_now': 105263},
      );
      expect((await preparedTake()).showsTheSameAs(figures), isFalse);
    });

    test('another expiry alone does not', () async {
      final read = await preparedTake();
      final later = await preparedTake(
        changes: {
          'expires_at': read.order.expiresAt
              .add(const Duration(hours: 1))
              .toIso8601String(),
        },
      );
      expect(read.showsTheSameAs(later), isFalse);
    });
  });
}
