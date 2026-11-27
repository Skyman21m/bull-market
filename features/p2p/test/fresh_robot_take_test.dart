import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/garage_opening.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/follow_trades_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/garage_robot_usecase.dart';
import 'package:p2p/src/presentation/take_order_cubit.dart';
import 'package:p2p/src/presentation/unlisted_order_cubit.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart' show coordinator;
import 'support/history_records.dart';
import 'support/trade_harness.dart';
import 'support/garage_words.dart';

/// The vault of the tests: [tradeKey] on the harness's network.
final class _Vault with KeysFromRead implements GarageKeyRepository {
  final NetworkGarageKey key;

  _Vault(this.key);

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> read(
    RobosatsNetwork network,
  ) async =>
      network == key.network ? Ok(key) : const Err(GarageKeyMissingFailure());

  @override
  Future<Result<void, P2pFailure>> import(
    RobosatsNetwork network,
    GarageKey key,
  ) => throw UnimplementedError();

  @override
  Future<Result<bool, P2pFailure>> exists(RobosatsNetwork network) =>
      throw UnimplementedError();

  @override
  Future<Result<NetworkRobot, P2pFailure>> firstUsableRobot(
    RobosatsNetwork network,
  ) => throw UnimplementedError();
}

/// The line « A fresh robot for this order » of the order page (#251, design note `docs/design/phase-3-fresh-robot.md` § 4.2): the robot of a take is always a fresh one, reserved as before; the line says it only when that robot is not the one the Garage showed before the reservation, a verdict kept with the robot for every preparation of the order. Over the real use cases, records and robots of the harness, the coordinator played by `ScriptedCoordinator`.
void main() {
  final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };

  ({TakeCalls calls, GarageNavigation navigation, GarageRobotUsecase garage})
  wiring(TradeHarness app) {
    final navigation = GarageNavigation();
    final garage = GarageRobotUsecase(
      _Vault(NetworkGarageKey(app.network, tradeKey)),
      FollowTradesUsecase(
        app.list.execute,
        app.records.watchClosedTrades,
        app.records.newTradeStandingOf,
      ),
      navigation,
    );
    return (
      calls: TakeCalls(
        prepare: app.take.prepare,
        prepareUnlisted: app.take.prepareUnlisted,
        confirm: app.take.confirm,
        abandon: app.take.abandon,
        abandonOrder: app.take.abandonOrder,
        garageRobot: garage.execute,
      ),
      navigation: navigation,
      garage: garage,
    );
  }

  RobotSlot slot(TradeHarness app, int index) =>
      RobotSlot(app.network, fingerprint, index);

  HistoryRecords history(TradeHarness app) =>
      HistoryRecords(app.records, app.trails, app.network);

  /// « Take Order » on the order of the book: the read shown.
  Future<PreparedTake> take(TradeHarness app, TakeCalls calls) async {
    final cubit = TakeOrderCubit(
      await app.shownOrder(),
      app.network,
      calls,
      (network) async => const Ok(true),
    );
    await cubit.take();
    final state = cubit.state;
    expect(state, isA<TakeReady>());
    // Left without sending: the reservation stays, never used again.
    return (state as TakeReady).prepared;
  }

  /// The robot indexes of the key in use: bound or recorded.
  Future<Set<int>> inUse(TradeHarness app) async =>
      switch (await app.records.newTradeStandingOf(app.network, fingerprint)) {
        Ok(:final value) => value.indexesInUse,
        Err(:final failure) => fail('$failure'),
      };

  /// « Take Order » with what is in use before and after: the index the take reserved.
  Future<(PreparedTake, int)> takeWithRobot(
    TradeHarness app,
    TakeCalls calls,
  ) async {
    final before = await inUse(app);
    final prepared = await take(app, calls);
    final reserved = (await inUse(app)).difference(before);
    expect(reserved, hasLength(1));
    return (prepared, reserved.single);
  }

  test(
    'the ordinary case: the Garage shows the robot the take reserves, nothing said',
    () async {
      final app = await TradeHarness.start();
      final wired = wiring(app);
      expect(await wired.garage.execute(app.network), slot(app, 0));
      final (prepared, reserved) = await takeWithRobot(app, wired.calls);
      expect(prepared.freshRobot, isNull);
      // The robot reserved is the one the Garage showed.
      expect(reserved, 0);
    },
  );

  test('after a trade that served: the fresh robot, nothing said', () async {
    final app = await TradeHarness.start();
    final wired = wiring(app);
    await history(app).taken(slot(app, 0), orderId: 900);
    expect(await wired.garage.execute(app.network), slot(app, 1));
    expect((await take(app, wired.calls)).freshRobot, isNull);
  });

  test(
    'after an expiry, with another trade in progress, after a move by hand, after « Select Host »: the line, with the robot of the take',
    () async {
      final robots = TradeHarness.robotsOf(RobosatsNetwork.testnet);
      for (final (name, arrange)
          in <
            (
              String,
              Future<void> Function(
                TradeHarness app,
                GarageNavigation navigation,
              ),
            )
          >[
            (
              'expired',
              (app, navigation) async => history(
                app,
              ).made(slot(app, 0), orderId: 900, position: 'expired'),
            ),
            (
              'in progress',
              (app, navigation) async => history(app).taken(
                slot(app, 0),
                orderId: 900,
                position: 'chatting',
                closed: false,
              ),
            ),
            (
              'by hand',
              (app, navigation) async => navigation.leave(
                NetworkGarageKey(app.network, tradeKey),
                slot(app, 3),
                null,
              ),
            ),
            (
              'Select Host',
              (app, navigation) async {
                expect(
                  await app.bindings.bind(
                    slot(app, 0),
                    switch (CoordinatorIdentity.of(
                      coordinator('lake'),
                      app.network,
                    )) {
                      final identity? => identity,
                      null => fail('lake'),
                    },
                  ),
                  isA<Ok<void, P2pFailure>>(),
                );
              },
            ),
          ]) {
        final app = await TradeHarness.start();
        final wired = wiring(app);
        await arrange(app, wired.navigation);
        final shown = await wired.garage.execute(app.network);
        final (prepared, reserved) = await takeWithRobot(app, wired.calls);
        final expected = name == 'by hand' ? 0 : 1;
        expect(reserved, expected, reason: name);
        expect(prepared.freshRobot, robots[expected].nickname, reason: name);
        expect(shown?.accountIndex, isNot(expected), reason: name);
      }
    },
  );

  test(
    'the same verdict when the same order is prepared again, whatever the Garage shows then',
    () async {
      final app = await TradeHarness.start();
      final order = await app.shownOrder();
      // First prepared with the Garage on the robot it reserves: nothing said, then again with another robot in the Garage.
      final first = switch (await app.take.prepare(
        order,
        network: app.network,
        garageRobot: slot(app, 0),
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(first.freshRobot, isNull);
      final again = switch (await app.take.prepare(
        order,
        network: app.network,
        garageRobot: slot(app, 4),
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(again.freshRobot, isNull);

      // Another app: first said, then prepared again with the Garage on that very robot, now in use: still said.
      final other = await TradeHarness.start();
      final otherOrder = await other.shownOrder();
      final said = switch (await other.take.prepare(
        otherOrder,
        network: other.network,
        garageRobot: slot(other, 4),
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(said.freshRobot, TradeHarness.robotsOf(other.network)[0].nickname);
      final saidAgain = switch (await other.take.prepare(
        otherOrder,
        network: other.network,
        garageRobot: slot(other, 1),
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(saidAgain.freshRobot, said.freshRobot);
      // The Garage's robot not told: nothing said.
      final third = await TradeHarness.start();
      final unknown = switch (await third.take.prepare(
        await third.shownOrder(),
        network: third.network,
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      expect(unknown.freshRobot, isNull);
    },
  );

  test(
    'an order opened by its URL: the read reserves the robot and keeps the verdict for its take',
    () async {
      final app = await TradeHarness.start(password: 'sesame');
      final wired = wiring(app);
      await history(app).made(slot(app, 0), orderId: 900, position: 'expired');
      final reader = UnlistedOrderCubit(
        app.coordinator.coordinator,
        42,
        app.network,
        app.take.readUnlisted,
        app.take.abandonRead,
        garageRobot: wired.garage.execute,
      );
      await reader.load();
      final shown = switch (reader.state) {
        UnlistedOrderShown(:final order) => order,
        final other => fail('$other'),
      };
      final cubit = TakeOrderCubit.unlisted(
        shown,
        wired.calls,
        (network) async => const Ok(true),
      );
      await cubit.take();
      final prepared = (cubit.state as TakeReady).prepared;
      expect(
        prepared.freshRobot,
        TradeHarness.robotsOf(app.network)[1].nickname,
      );
      await cubit.close();
      await reader.close();
    },
  );

  test(
    'the take\'s robot is never the Garage\'s when that one is bound or recorded',
    () async {
      final app = await TradeHarness.start();
      final wired = wiring(app);
      final TradeRecord expired = await history(
        app,
      ).made(slot(app, 0), orderId: 900, position: 'expired');
      expect(await wired.garage.execute(app.network), expired.robot);
      final (_, reserved) = await takeWithRobot(app, wired.calls);
      expect(reserved, isNot(expired.robot.accountIndex));
    },
  );
}
