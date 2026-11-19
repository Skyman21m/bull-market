import 'dart:async';
import 'dart:typed_data';

import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/follow_made_orders_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

/// The device's trades not closed, as `ListActiveTradesUsecase` gives them, played by the test.
final class _Active {
  final StreamController<Result<List<ActiveTrade>, P2pFailure>> trades =
      StreamController();
  final List<RobosatsNetwork> asked = [];

  Stream<Result<List<ActiveTrade>, P2pFailure>> call(RobosatsNetwork network) {
    asked.add(network);
    return trades.stream;
  }
}

/// The robot the Garage shows of the orders made here (#227): the newest one whose bond was seen locked when it opens, then each one seen locked while it is shown; never one waiting for its bond, never one of another key or network.
void main() {
  GarageKey keyOf(int first) => switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => first + i)),
  )) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  };
  // Fixed test bytes: not keys anyone uses.
  final key = NetworkGarageKey(RobosatsNetwork.testnet, keyOf(1));
  final other = NetworkGarageKey(RobosatsNetwork.testnet, keyOf(100));

  RobotSlot slot(int index, {NetworkGarageKey? of, RobosatsNetwork? network}) {
    final from = of ?? key;
    return RobotSlot(network ?? from.network, switch (from.fingerprint) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    }, index);
  }

  /// An order made here by [robot], its record not closed.
  TradeRecord open(
    RobotSlot robot, {
    TradeOrigin origin = TradeOrigin.madeHere,
  }) => TradeRecord(
    robot: robot,
    coordinatorAlias: 'temple',
    coordinatorOnion:
        Federation.robosats.byAlias('temple')?.testnet.onion ??
        (throw StateError('temple')),
    orderId: 100 + robot.accountIndex,
    role: TradeRole.buyer,
    origin: origin,
    takenAt: DateTime.utc(2026, 11, 19, 9),
    confirmedAt: DateTime.utc(2026, 11, 19, 9),
    closedAt: null,
  );

  /// The trades not closed: an order made here by each robot at its stored position, `null` for records that cannot be restored.
  Result<List<ActiveTrade>, P2pFailure> made(
    Map<RobotSlot, TradePosition?> positions,
  ) => Ok([
    for (final MapEntry(key: robot, value: position) in positions.entries)
      ActiveTrade(
        open(robot),
        position == null
            ? const ActiveTradeUnrestorable(TradeRecordMalformed())
            : ActiveTradeAt(
                position,
                deadline: null,
                breached: false,
                historyUnknown: false,
              ),
      ),
  ]);

  /// A finished order of [robot], as a « Last order #N » line shows it.
  TradeRecord lastOrder(RobotSlot robot) => TradeRecord(
    robot: robot,
    coordinatorAlias: 'temple',
    coordinatorOnion:
        Federation.robosats.byAlias('temple')?.testnet.onion ??
        (throw StateError('temple')),
    orderId: 43,
    role: TradeRole.buyer,
    origin: TradeOrigin.madeHere,
    takenAt: DateTime.utc(2026, 11, 19, 9),
    confirmedAt: DateTime.utc(2026, 11, 19, 9),
    closedAt: DateTime.utc(2026, 11, 19, 10),
  );

  /// What the use case gives while [lists] are read one after the other, the « Last order #N » lines being [lines].
  Future<List<RobotSlot?>> follow(
    List<Result<List<ActiveTrade>, P2pFailure>> lists, {
    Result<List<TradeRecord>, P2pFailure> lines = const Ok([]),
  }) async {
    final active = _Active();
    final given = <RobotSlot?>[];
    final linesAsked = <RobosatsNetwork>[];
    final listening = FollowMadeOrdersUsecase(active.call, (network) {
      linesAsked.add(network);
      return Stream.value(lines);
    }).execute(key).listen(given.add);
    for (final list in lists) {
      active.trades.add(list);
    }
    await pumpEventQueue();
    expect(active.asked, [RobosatsNetwork.testnet]);
    expect(linesAsked, hasLength(lessThanOrEqualTo(1)));
    await listening.cancel();
    return given;
  }

  const public = TradePosition.public;
  const waiting = TradePosition.makerBondStep;

  group('when the Garage opens', () {
    test('the newest order whose bond is locked, by index', () async {
      expect(
        await follow([
          made({
            slot(1): public,
            slot(4): TradePosition.chatting,
            slot(2): public,
          }),
        ]),
        [slot(4)],
      );
    });

    test(
      'none: an order waiting for its bond, at 5, after 1043, with no trail, of another key or network',
      () async {
        expect(
          await follow([
            made({
              slot(1): waiting,
              slot(2): TradePosition.expired,
              slot(3): TradePosition.cancelled,
              slot(4): null,
              slot(5): TradePosition.start,
              slot(6, of: other): public,
              slot(7, network: RobosatsNetwork.mainnet): public,
            }),
          ]),
          [null],
        );
      },
    );

    test('records that cannot be read: none', () async {
      expect(await follow([const Err(P2pStorageFailure())]), [null]);
    });
  });

  group('when the Garage opens with no order made here locked (review of #229, C1)', () {
    test(
      'the robot of the first « Last order #N » line, an order expired or cancelled since',
      () async {
        expect(
          await follow([
            made({slot(3): TradePosition.expired, slot(1): waiting}),
          ], lines: Ok([lastOrder(slot(3)), lastOrder(slot(2))])),
          [slot(3)],
        );
      },
    );

    test(
      'status by status: an order in progress whose bond was locked counts, 13 and 15 included; one over is closed, and counts only through the line (review of #229, C3)',
      () async {
        // The positions where an order made here is not closed and its bond was locked: it wins over the line.
        for (final inProgress in [
          TradePosition.public,
          TradePosition.paused,
          TradePosition.waitingForBoth,
          TradePosition.waitingForEscrow,
          TradePosition.waitingForPayout,
          TradePosition.chatting,
          TradePosition.fiatSent,
          TradePosition.inDispute,
          TradePosition.sendingSats,
          TradePosition.routingFailed,
          TradePosition.waitingDisputeResolution,
        ]) {
          expect(
            await follow([
              made({slot(1): inProgress}),
            ], lines: Ok([lastOrder(slot(2))])),
            [slot(1)],
            reason: inProgress.name,
          );
        }
        // Not closed, its bond never locked or not known to have been: the line.
        for (final notLocked in [
          null,
          TradePosition.start,
          TradePosition.makerBondStep,
          TradePosition.expired,
          TradePosition.cancelled,
        ]) {
          expect(
            await follow([
              made({slot(1): notLocked}),
            ], lines: Ok([lastOrder(slot(2))])),
            [slot(2)],
            reason: '$notLocked',
          );
        }
        // Over (14, 17, 18, 5, 1043): its record closed, it is in no list of trades not closed, only in the line's records: the line, and the line only.
        expect(await follow([made({})], lines: Ok([lastOrder(slot(1))])), [
          slot(1),
        ]);
        // A record closed is never in progress, wherever it is listed.
        final closed = open(slot(1));
        expect(
          await follow([
            Ok([
              ActiveTrade(
                TradeRecord(
                  robot: closed.robot,
                  coordinatorAlias: closed.coordinatorAlias,
                  coordinatorOnion: closed.coordinatorOnion,
                  orderId: closed.orderId,
                  role: closed.role,
                  origin: closed.origin,
                  takenAt: closed.takenAt,
                  confirmedAt: closed.confirmedAt,
                  closedAt: DateTime.utc(2026, 11, 19, 11),
                ),
                const ActiveTradeAt(
                  TradePosition.succeeded,
                  deadline: null,
                  breached: false,
                  historyUnknown: false,
                ),
              ),
            ]),
          ], lines: Ok([lastOrder(slot(2))])),
          [slot(2)],
        );
        // A taken trade in progress is not an order made here.
        expect(
          await follow([
            Ok([
              ActiveTrade(
                open(slot(1), origin: TradeOrigin.takenHere),
                const ActiveTradeAt(
                  TradePosition.chatting,
                  deadline: null,
                  breached: false,
                  historyUnknown: false,
                ),
              ),
            ]),
          ], lines: Ok([lastOrder(slot(2))])),
          [slot(2)],
        );
      },
    );

    test('an order locked wins over the line', () async {
      expect(
        await follow([
          made({slot(1): public, slot(3): TradePosition.cancelled}),
        ], lines: Ok([lastOrder(slot(3))])),
        [slot(1)],
      );
    });

    test(
      'none: a line of another key or network, no line, lines that cannot be read',
      () async {
        for (final lines in <Result<List<TradeRecord>, P2pFailure>>[
          Ok([lastOrder(slot(3, of: other))]),
          Ok([lastOrder(slot(3, network: RobosatsNetwork.mainnet))]),
          const Ok([]),
          const Err(P2pStorageFailure()),
        ]) {
          expect(await follow([made({})], lines: lines), [
            null,
          ], reason: '$lines');
        }
      },
    );

    test('only at the opening: later lists never read the lines', () async {
      expect(
        await follow([
          made({}),
          made({slot(1): waiting}),
          made({slot(1): public}),
        ], lines: Ok([lastOrder(slot(4))])),
        [slot(4), slot(1)],
      );
    });
  });

  group('while the Garage is shown', () {
    test('an order whose bond locks gives its robot, once', () async {
      expect(
        await follow([
          made({}),
          made({slot(1): waiting}),
          made({slot(1): waiting}),
          made({slot(1): public}),
          made({slot(1): TradePosition.paused}),
        ]),
        [null, slot(1)],
      );
    });

    test('one already locked when it opened is not given again', () async {
      expect(
        await follow([
          made({slot(1): public}),
          made({slot(1): public, slot(2): waiting}),
          made({slot(1): public, slot(2): public}),
        ]),
        [slot(1), slot(2)],
      );
    });

    test('two seen locked at once give the newest, and never again', () async {
      expect(
        await follow([
          made({}),
          made({slot(1): public, slot(2): public}),
          made({slot(1): public, slot(2): public, slot(3): waiting}),
          made({slot(1): public, slot(2): public, slot(3): public}),
        ]),
        [null, slot(2), slot(3)],
      );
    });

    test(
      'an order closed leaves the list, and moves nothing; one at 13 or 15 still counts',
      () async {
        expect(
          await follow([
            made({}),
            made({slot(1): TradePosition.routingFailed}),
            made({}),
            made({slot(2): TradePosition.sendingSats}),
          ]),
          [null, slot(1), slot(2)],
        );
      },
    );

    test('another key\'s or network\'s order locking gives nothing', () async {
      expect(
        await follow([
          made({}),
          made({
            slot(1, of: other): public,
            slot(1, network: RobosatsNetwork.mainnet): public,
          }),
        ]),
        [null],
      );
    });

    test(
      'records that cannot be read give nothing; after an unreadable first list, the first one read only sets what is known',
      () async {
        expect(
          await follow([
            made({}),
            const Err(P2pStorageFailure()),
            made({slot(1): public}),
          ]),
          [null, slot(1)],
        );
        expect(
          await follow([
            const Err(P2pStorageFailure()),
            made({slot(1): public}),
            made({slot(1): public, slot(2): public}),
          ]),
          [null, slot(2)],
        );
      },
    );

    test('stops reading the records when its listener stops', () async {
      final active = _Active();
      final listening = FollowMadeOrdersUsecase(
        active.call,
        (_) => Stream.value(const Ok([])),
      ).execute(key).listen((_) {});
      active.trades.add(made({}));
      await pumpEventQueue();
      expect(active.trades.hasListener, isTrue);
      await listening.cancel();
      expect(active.trades.hasListener, isFalse);
    });
  });

  test(
    'a maker bond was locked from the order public on, never while it waits for it, never at an end that may come before it',
    () {
      const locked = {
        TradePosition.public,
        TradePosition.paused,
        TradePosition.waitingForBoth,
        TradePosition.waitingForEscrow,
        TradePosition.waitingForPayout,
        TradePosition.chatting,
        TradePosition.fiatSent,
        TradePosition.inDispute,
        TradePosition.sendingSats,
        TradePosition.succeeded,
        TradePosition.routingFailed,
        TradePosition.waitingDisputeResolution,
        TradePosition.makerLostDispute,
        TradePosition.takerLostDispute,
      };
      for (final position in TradePosition.values) {
        expect(
          position.makerBondLocked,
          locked.contains(position),
          reason: position.name,
        );
      }
    },
  );
}
