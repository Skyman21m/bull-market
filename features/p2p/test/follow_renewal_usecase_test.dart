import 'dart:async';
import 'dart:typed_data';

import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_renewal.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/follow_renewal_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/make_harness.dart';

/// The robot the Garage moves to after a renewal of the order of a « Last order #N » the user tapped (#227): a renewal whose bond this device sees locked after the Garage started following, never one waiting for its bond.
void main() {
  // Fixed test bytes, 0x01 to 0x20: not a key anyone uses.
  final fingerprint = switch (GarageKey.fromBytes(
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
  )) {
    Ok(:final value) => switch (GarageKeyFingerprint.of(value)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    },
    Err(:final failure) => throw StateError('$failure'),
  };
  final madeAt = DateTime.utc(2026, 11, 19, 9);
  final onion =
      Federation.robosats.byAlias('temple')?.testnet.onion ??
      (throw StateError('temple'));

  TradeRecord recordOf(int index, {DateTime? closedAt}) => TradeRecord(
    robot: RobotSlot(RobosatsNetwork.testnet, fingerprint, index),
    coordinatorAlias: 'temple',
    coordinatorOnion: onion,
    orderId: 100 + index,
    role: TradeRole.buyer,
    origin: TradeOrigin.madeHere,
    takenAt: madeAt.add(Duration(hours: index)),
    confirmedAt: madeAt.add(Duration(hours: index)),
    closedAt: closedAt,
  );

  final followed = recordOf(0, closedAt: madeAt.add(const Duration(days: 1)));

  /// The orders made since [followed], each by its robot's index, its bond seen locked or not.
  Result<OrderRenewals, P2pFailure> since(Map<int, bool> made) => Ok(
    OrderRenewals(MakeHarness.request(), [
      for (final MapEntry(key: index, value: locked) in made.entries)
        OrderMadeSince(
          recordOf(index),
          MadeSinceStands.running,
          bondLocked: locked,
        ),
    ]),
  );

  RobotSlot slot(int index) =>
      RobotSlot(RobosatsNetwork.testnet, fingerprint, index);

  /// The robots the use case gives while [lists] are read one after the other.
  Future<List<RobotSlot>> follow(
    List<Result<OrderRenewals, P2pFailure>> lists,
  ) async {
    final asked = <TradeRecord>[];
    final usecase = FollowRenewalUsecase((record) {
      asked.add(record);
      return Stream.fromIterable(lists);
    });
    final robots = await usecase.execute(followed).toList();
    expect(asked, [followed]);
    return robots;
  }

  group('follows the renewals of an order', () {
    test('a renewal whose bond locks gives its robot, once', () async {
      expect(
        await follow([
          since({}),
          since({1: false}),
          since({1: false}),
          since({1: true}),
          since({1: true}),
        ]),
        [slot(1)],
      );
    });

    test('a renewal waiting for its bond gives nothing', () async {
      expect(
        await follow([
          since({}),
          since({1: false}),
          since({1: false}),
        ]),
        isEmpty,
      );
    });

    test(
      'one already locked when the following starts is left alone, a later one is not',
      () async {
        expect(
          await follow([
            since({1: true}),
            since({1: true, 2: false}),
            since({1: true, 2: true}),
          ]),
          [slot(2)],
        );
      },
    );

    test('two seen locked at once give the newest, and never again', () async {
      expect(
        await follow([
          since({}),
          since({1: true, 2: true}),
          since({1: true, 2: true, 3: false}),
          since({1: true, 2: true, 3: true}),
        ]),
        [slot(2), slot(3)],
      );
    });

    test(
      'records that cannot be read give nothing, and the first list read is the one the following starts from',
      () async {
        expect(
          await follow([
            const Err(P2pStorageFailure()),
            since({1: true}),
            const Err(P2pStorageFailure()),
            since({1: true, 2: true}),
          ]),
          [slot(2)],
        );
        expect(
          await follow([const Err(P2pStorageFailure()), since({})]),
          isEmpty,
        );
      },
    );

    test('stops reading the records when its listener stops', () async {
      final lists = StreamController<Result<OrderRenewals, P2pFailure>>();
      final robots = <RobotSlot>[];
      final listening = FollowRenewalUsecase(
        (_) => lists.stream,
      ).execute(followed).listen(robots.add);
      lists
        ..add(since({}))
        ..add(since({1: true}));
      await pumpEventQueue();
      expect(robots, [slot(1)]);
      expect(lists.hasListener, isTrue);
      await listening.cancel();
      expect(lists.hasListener, isFalse);
      await lists.close();
    });
  });

  test(
    'a bond is locked from the order public on, never while it waits for it, never at an end that may come before it',
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
          OrderMadeSince.bondLockedAt(position),
          locked.contains(position),
          reason: position.name,
        );
      }
      expect(OrderMadeSince.bondLockedAt(null), isFalse);
      for (final position in [
        TradePosition.start,
        TradePosition.makerBondStep,
        TradePosition.expired,
        TradePosition.cancelled,
      ]) {
        expect(locked, isNot(contains(position)));
      }
    },
  );
}
