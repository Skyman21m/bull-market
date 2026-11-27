import 'dart:convert';

import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/presentation/unlisted_order_cubit.dart';
import 'package:p2p/src/presentation/take_order_cubit.dart';
import 'package:p2p/testing.dart' show ScriptedFault, ScriptedRequest;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart' show CoordinatorHttpMethod;
import 'package:test/test.dart';

import 'support/signed_bodies.dart';
import 'support/trade_harness.dart';

/// The cubits of a password-protected order (#245): the read of its page, and its take, over the real use case and a played coordinator.
void main() {
  const password = 'sesame';

  TakeCalls calls(TradeHarness app) => TakeCalls(
    prepare: app.take.prepare,
    prepareUnlisted: app.take.prepareUnlisted,
    confirm: app.take.confirm,
    abandon: app.take.abandon,
    abandonOrder: app.take.abandonOrder,
  );

  int takes(TradeHarness app) =>
      app.coordinator.received.where((k) => k == ScriptedRequest.take).length;

  UnlistedOrderCubit reader(TradeHarness app) => UnlistedOrderCubit(
    app.coordinator.coordinator,
    42,
    app.network,
    app.take.readUnlisted,
    app.take.abandonRead,
  );

  group('UnlistedOrderCubit', () {
    test('reads the order with its robot, once, and shows it', () async {
      final app = await TradeHarness.start(password: password);
      final cubit = reader(app);
      final steps = <TakeStep?>[];
      final listening = cubit.stream.listen((state) {
        if (state is UnlistedOrderReading) steps.add(state.step);
      });
      await cubit.load();
      expect(cubit.state, isA<UnlistedOrderShown>());
      expect(
        steps,
        containsAllInOrder([TakeStep.creatingRobot, TakeStep.readingOrder]),
      );
      // « Retry » reads nothing once the order is shown.
      final sent = List.of(app.coordinator.received);
      await cubit.retry();
      expect(app.coordinator.received, sent);
      await listening.cancel();
      await cubit.close();
    });

    test(
      'an order no longer takeable: « This order is not available », no « Retry », and its robot forgotten',
      () async {
        final app = await TradeHarness.start();
        app.coordinator.takenByAnother();
        final cubit = reader(app);
        await cubit.load();
        final state = cubit.state;
        expect(
          state,
          isA<UnlistedOrderRefused>().having(
            (refused) => refused.refusal,
            'refusal',
            isA<TakeOrderGone>(),
          ),
        );
        expect((state as UnlistedOrderRefused).canRetry, isFalse);
        await cubit.close();
      },
    );

    test(
      'a page left while it reads forgets the robot kept for the order',
      () async {
        final app = await TradeHarness.start(password: password);
        final cubit = reader(app);
        final read = cubit.load();
        await cubit.close();
        await read;
        // The robot of that read is never used again: a new read reserves another.
        final again = reader(app);
        await again.load();
        expect(again.state, isA<UnlistedOrderShown>());
        final bindings = await app.database
            .customSelect('SELECT * FROM robot_bindings')
            .get();
        expect(bindings, hasLength(2));
        await again.close();
      },
    );
  });

  group('UnlistedOrderCubit, a refusal that another read may change', () {
    test(
      'the page left after it: the robot kept for the order is forgotten, and a new read reserves another',
      () async {
        final app = await TradeHarness.start(password: password);
        app.coordinator.failNext(
          ScriptedRequest.order,
          ScriptedFault.unreachable,
        );
        final cubit = reader(app);
        await cubit.load();
        final state = cubit.state;
        expect(state, isA<UnlistedOrderRefused>());
        expect((state as UnlistedOrderRefused).canRetry, isTrue);
        await cubit.close();
        final again = reader(app);
        await again.load();
        expect(again.state, isA<UnlistedOrderShown>());
        final bindings = await app.database
            .customSelect('SELECT * FROM robot_bindings')
            .get();
        expect(bindings, hasLength(2));
        await again.close();
      },
    );

    test('« Retry » reads again with the same robot', () async {
      final app = await TradeHarness.start(password: password);
      app.coordinator.failNext(
        ScriptedRequest.order,
        ScriptedFault.unreachable,
      );
      final cubit = reader(app);
      await cubit.load();
      await cubit.retry();
      expect(cubit.state, isA<UnlistedOrderShown>());
      final bindings = await app.database
          .customSelect('SELECT * FROM robot_bindings')
          .get();
      expect(bindings, hasLength(1));
      await cubit.close();
    });
  });

  group('TakeOrderCubit.unlisted', () {
    test(
      'prepared as a protected order; « Done » without a password sends nothing; with it, the take carries its hash',
      () async {
        final app = await TradeHarness.start(password: password);
        final shown = switch (await app.take.readUnlisted(
          app.coordinator.coordinator,
          42,
          network: app.network,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('not read: $failure'),
        };
        final cubit = TakeOrderCubit.unlisted(
          shown,
          calls(app),
          (network) async => const Ok(true),
        );
        expect(cubit.unlisted, same(shown));
        expect(cubit.order, same(shown.order));
        await cubit.take();
        expect(cubit.state, isA<TakeReady>());
        await cubit.confirm();
        expect(cubit.state, isA<TakeReady>());
        expect(takes(app), 0);
        await cubit.confirm(password: OrderPassword.tryCreate(password));
        expect(cubit.state, isA<TakeSent>());
        expect(takes(app), 1);
        await cubit.close();
      },
    );

    test(
      'a wrong password: the take not made, said as the coordinator says it',
      () async {
        final app = await TradeHarness.start(password: password);
        final shown = switch (await app.take.readUnlisted(
          app.coordinator.coordinator,
          42,
          network: app.network,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('not read: $failure'),
        };
        final cubit = TakeOrderCubit.unlisted(
          shown,
          calls(app),
          (network) async => const Ok(true),
        );
        await cubit.take();
        await cubit.confirm(password: OrderPassword.tryCreate('open'));
        expect(
          cubit.state,
          isA<TakeIdle>().having(
            (idle) => idle.problem,
            'problem',
            isA<TakeWasNotMade>(),
          ),
        );
        expect((cubit.state as TakeIdle).orderGone, isFalse);
        // Taken again: a new preparation, then the right password.
        await cubit.take();
        await cubit.confirm(password: OrderPassword.tryCreate(password));
        expect(cubit.state, isA<TakeSent>());
        await cubit.close();
      },
    );

    test(
      'a protected order without its preparation is a bug of the composition',
      () async {
        final app = await TradeHarness.start(password: password);
        final shown = switch (await app.take.readUnlisted(
          app.coordinator.coordinator,
          42,
          network: app.network,
        )) {
          Ok(:final value) => value,
          Err(:final failure) => fail('not read: $failure'),
        };
        expect(
          () => TakeOrderCubit.unlisted(
            shown,
            TakeCalls(
              prepare: app.take.prepare,
              confirm: app.take.confirm,
              abandon: app.take.abandon,
              abandonOrder: app.take.abandonOrder,
            ),
            (network) async => const Ok(true),
          ),
          throwsArgumentError,
        );
      },
    );

    test('an order of the book: a password given is never sent', () async {
      final app = await TradeHarness.start();
      final cubit = TakeOrderCubit(
        await app.shownOrder(),
        app.network,
        calls(app),
        (network) async => const Ok(true),
      );
      await cubit.take();
      await cubit.confirm(password: OrderPassword.tryCreate(password));
      expect(cubit.state, isA<TakeSent>());
      final take = app.coordinator.requests.lastWhere(
        (request) => request.method == CoordinatorHttpMethod.post,
      );
      expect(
        unsignedBodyOf(take.body),
        '{"action":"take","amount":0}',
      );
      await cubit.close();
    });
  });
}
