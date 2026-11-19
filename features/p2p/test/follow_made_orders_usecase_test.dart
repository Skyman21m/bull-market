import 'dart:async';
import 'dart:typed_data';

import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/follow_made_orders_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

/// The made histories of the tests, played by the test: nothing else of the repository is used.
final class _Trails implements TradeTrailRepository {
  final StreamController<Result<Map<RobotSlot, StoredMadeHistory>, P2pFailure>>
  made = StreamController();
  final List<RobosatsNetwork> asked = [];

  @override
  Stream<Result<Map<RobotSlot, StoredMadeHistory>, P2pFailure>>
  watchMadeHistories(RobosatsNetwork network) {
    asked.add(network);
    return made.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
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

  StoredMadeHistory at(TradePosition? position) => StoredMadeHistory(
    terms: null,
    trail: position == null
        ? null
        : TradeTrailRecord(
            version: TradeTrailRecord.currentVersion,
            network: RobosatsNetwork.testnet.name,
            coordinatorAlias: 'temple',
            orderId: 42,
            role: 'buyer',
            position: position.name,
            readAtMicros: 0,
            bondHash: null,
            escrowHash: null,
            deadlineMicros: null,
            bondStepSeenAtMicros: null,
            bondStepDeadlineMicros: null,
            breached: false,
            historyUnknown: false,
          ),
  );

  Result<Map<RobotSlot, StoredMadeHistory>, P2pFailure> made(
    Map<RobotSlot, TradePosition?> positions,
  ) => Ok({
    for (final MapEntry(key: robot, value: position) in positions.entries)
      robot: at(position),
  });

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
    List<Result<Map<RobotSlot, StoredMadeHistory>, P2pFailure>> lists, {
    Result<List<TradeRecord>, P2pFailure> lines = const Ok([]),
  }) async {
    final trails = _Trails();
    final given = <RobotSlot?>[];
    final linesAsked = <RobosatsNetwork>[];
    final listening = FollowMadeOrdersUsecase(trails, (network) {
      linesAsked.add(network);
      return Stream.value(lines);
    }).execute(key).listen(given.add);
    for (final list in lists) {
      trails.made.add(list);
    }
    await pumpEventQueue();
    expect(trails.asked, [RobosatsNetwork.testnet]);
    expect(linesAsked, hasLength(lessThanOrEqualTo(1)));
    await listening.cancel();
    return given;
  }

  const public = TradePosition.public;
  const waiting = TradePosition.makerBondStep;

  group('when the Garage opens', () {
    test('the newest order whose bond was seen locked, by index', () async {
      expect(
        await follow([
          made({
            slot(1): public,
            slot(4): TradePosition.succeeded,
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

  group(
    'when the Garage opens with no order made here locked (review of #229, C1)',
    () {
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
    },
  );

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
      final trails = _Trails();
      final listening = FollowMadeOrdersUsecase(
        trails,
        (_) => Stream.value(const Ok([])),
      ).execute(key).listen((_) {});
      trails.made.add(made({}));
      await pumpEventQueue();
      expect(trails.made.hasListener, isTrue);
      await listening.cancel();
      expect(trails.made.hasListener, isFalse);
    });
  });

  test(
    'a maker bond is locked from the order public on, never while it waits for it, never at an end that may come before it',
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
