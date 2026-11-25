import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/testing.dart' show ScriptedRequest;
import 'package:test/test.dart';

import 'support/trade_harness.dart';

/// The Garage's one read of an order that ended while the app did not read it (#251, design note `docs/design/phase-3-fresh-robot.md` § 4.1, step 0): `WatchTradeUsecase.readOnce`, over the real reader, records and trails of the harness, the coordinator played by `ScriptedCoordinator`.
void main() {
  int readsOf(TradeHarness app) =>
      app.coordinator.received.where((k) => k == ScriptedRequest.order).length;

  Future<TradeHarness> lockedTrade() async {
    final app = await TradeHarness.start();
    final record = TradeHarness.recordOf(await app.takeShown());
    app.coordinator.lockBond(app.robot(0));
    expect(record.closedAt, isNull);
    return app;
  }

  test(
    'an order ended at the coordinator: one read, the record closed at its end, no read after',
    () async {
      for (final (name, end) in <(String, void Function(TradeHarness app))>[
        ('expired', (app) => app.coordinator.expire()),
        ('cancelled', (app) => app.coordinator.cancelByMaker()),
        ('traded', (app) => app.coordinator.moveTo(14)),
      ]) {
        final app = await lockedTrade();
        final record = (await app.activeRecords()).single;
        end(app);
        final before = readsOf(app);
        await app.watch.readOnce(record);
        await app.settle();
        expect(await app.activeRecords(), isEmpty, reason: name);
        // At an end the reader may read a successful end or an expiry once more, as the page does when it opens: never more than that, and nothing on a timer.
        expect(readsOf(app) - before, lessThanOrEqualTo(2), reason: name);
        final after = readsOf(app);
        await app.elapse(const Duration(minutes: 10));
        expect(readsOf(app), after, reason: name);
      }
    },
  );

  test(
    'an order still in progress: one read, the record kept open, and nothing read on a timer',
    () async {
      final app = await lockedTrade();
      final record = (await app.activeRecords()).single;
      final before = readsOf(app);
      await app.watch.readOnce(record);
      await app.settle();
      expect(readsOf(app) - before, 1);
      expect(await app.activeRecords(), hasLength(1));
      await app.elapse(const Duration(minutes: 10));
      expect(readsOf(app) - before, 1);
      expect(app.activeTimers, isEmpty);
    },
  );

  test(
    'a trade another subscription reads already: nothing sent, the subscription left alone',
    () async {
      final app = await lockedTrade();
      final record = (await app.activeRecords()).single;
      final run = app.watchOf(record);
      await app.settle();
      final before = readsOf(app);
      await app.watch.readOnce(record);
      await app.settle();
      expect(readsOf(app), before);
      expect(run.states.whereType<TradeWatchSuperseded>(), isEmpty);
      await run.subscription.cancel();
    },
  );
}
