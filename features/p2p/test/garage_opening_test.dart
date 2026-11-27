import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/data/trade_trail_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/garage_opening.dart';
import 'package:p2p/src/domain/interim_trade_robots.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/next_trade_robot.dart';
import 'package:p2p/src/domain/order_history.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/active_trade.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/follow_trades_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/garage_robot_usecase.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/history_records.dart';
import 'support/robot_bindings.dart';
import 'support/garage_words.dart';

GarageKey _keyOf(int first) => switch (GarageKey.fromBytes(
  Uint8List.fromList(List<int>.generate(32, (i) => first + i)),
)) {
  Ok(:final value) => value,
  Err(:final failure) => throw StateError('$failure'),
};

GarageKeyFingerprint _fingerprintOf(GarageKey key) =>
    switch (GarageKeyFingerprint.of(key)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };

/// The vault as the robot layer and the Garage read it: one key per network.
final class _Vault with KeysFromRead implements GarageKeyRepository {
  final Map<RobosatsNetwork, Result<NetworkGarageKey, P2pFailure>> slots;

  _Vault(this.slots);

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> read(
    RobosatsNetwork network,
  ) async => slots[network] ?? const Err(GarageKeyMissingFailure());

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

/// The robot the Garage shows by the device's records (#251, design note `docs/design/phase-3-fresh-robot.md` § 3, § 4.1): « served » from how a finished trade's trail stopped, the fresh robot the next trade would reserve, the pure rule of the opening, and where the user left the Garage by hand.
void main() {
  const testnet = RobosatsNetwork.testnet;
  // Fixed test bytes: not keys anyone uses.
  final key = NetworkGarageKey(testnet, _keyOf(1));
  final fingerprint = _fingerprintOf(_keyOf(1));
  final otherFingerprint = _fingerprintOf(_keyOf(90));

  RobotSlot slot(int index, {GarageKeyFingerprint? of}) =>
      RobotSlot(testnet, of ?? fingerprint, index);

  final base = DateTime.utc(2026, 11, 20, 9);

  TradeRecord record(
    int index, {
    TradeOrigin origin = TradeOrigin.takenHere,
    bool confirmed = true,
    int? closedAfterHours,
    GarageKeyFingerprint? of,
  }) => TradeRecord(
    robot: slot(index, of: of),
    coordinatorAlias: 'temple',
    coordinatorOnion: 'http://temple.onion',
    orderId: 40000 + index,
    role: TradeRole.buyer,
    origin: origin,
    takenAt: base.add(Duration(hours: index)),
    confirmedAt: confirmed ? base.add(Duration(hours: index)) : null,
    closedAt: closedAfterHours == null
        ? null
        : base.add(Duration(hours: closedAfterHours)),
  );

  ActiveTrade inProgress(
    int index,
    TradePosition position, {
    TradeOrigin origin = TradeOrigin.takenHere,
    bool confirmed = true,
  }) => ActiveTrade(
    record(index, origin: origin, confirmed: confirmed),
    ActiveTradeAt(
      position,
      deadline: null,
      breached: false,
      historyUnknown: false,
    ),
  );

  ClosedTrade finished(
    int index,
    TradePosition? position, {
    TradeOrigin origin = TradeOrigin.takenHere,
    bool confirmed = true,
    int? at,
    GarageKeyFingerprint? of,
  }) => ClosedTrade(
    record(
      index,
      origin: origin,
      confirmed: confirmed,
      closedAfterHours: at ?? 100 + index,
      of: of,
    ),
    position,
  );

  GarageRecords recordsOf({
    List<ActiveTrade> active = const [],
    List<ClosedTrade> closed = const [],
    int? fresh = 9,
  }) => GarageRecords(
    inProgress: active,
    closed: closed,
    fresh: fresh == null ? null : slot(fresh),
  );

  group('« served », from how the trail of a finished trade stopped (§ 3)', () {
    test(
      'a trade, a dispute, a cancellation, an end unknown serve; an expiry and a take that never started do not',
      () {
        const notServed = {
          TradePosition.expired,
          TradePosition.publicAgain,
          TradePosition.notAvailable,
        };
        for (final position in TradePosition.values) {
          expect(
            OrderEnd.served(position),
            !notServed.contains(position),
            reason: position.name,
          );
        }
        // No trail, or one not read back: the end is not known, as a status unknown in the reference.
        expect(OrderEnd.served(null), isTrue);
      },
    );

    test('what the history says of each end is unchanged', () {
      expect(OrderEnd.of(TradePosition.publicAgain), OrderEnd.unknown);
      expect(OrderEnd.of(TradePosition.notAvailable), OrderEnd.unknown);
      expect(OrderEnd.of(null), OrderEnd.unknown);
    });
  });

  group('the rule of the opening, row by row of § 3 (§ 4.1, steps 1 to 3)', () {
    for (final origin in [TradeOrigin.madeHere, TradeOrigin.takenHere]) {
      final made = origin == TradeOrigin.madeHere;
      group(made ? 'a trade made here' : 'a trade taken here', () {
        for (final (position, moves) in [
          (TradePosition.succeeded, true),
          (TradePosition.makerLostDispute, true),
          (TradePosition.takerLostDispute, true),
          (TradePosition.cancelled, true),
          (null, true),
          // A closed record whose trail stops where no end is: an end unknown.
          (TradePosition.chatting, true),
          (TradePosition.expired, false),
          if (!made) (TradePosition.publicAgain, false),
          if (!made) (TradePosition.notAvailable, false),
        ]) {
          test(
            '${position?.name ?? 'no trail'}: ${moves ? 'the fresh robot' : 'its own robot'}',
            () {
              final records = recordsOf(
                closed: [finished(3, position, origin: origin)],
              );
              expect(GarageOpening.of(key, records), moves ? slot(9) : slot(3));
            },
          );
        }

        test(
          'in progress, its bond locked: its robot, never the fresh one',
          () {
            for (final position in [
              if (made) TradePosition.public,
              if (made) TradePosition.paused,
              TradePosition.waitingForBoth,
              TradePosition.chatting,
              TradePosition.fiatSent,
              TradePosition.inDispute,
              TradePosition.sendingSats,
              TradePosition.routingFailed,
              TradePosition.waitingDisputeResolution,
            ]) {
              final records = recordsOf(
                active: [inProgress(5, position, origin: origin)],
                closed: [finished(3, TradePosition.succeeded, origin: origin)],
              );
              expect(
                GarageOpening.of(key, records),
                slot(5),
                reason: position.name,
              );
            }
          },
        );
      });
    }

    test(
      'the newest of the trades in progress whose bond is locked, made or taken, by index',
      () {
        final records = recordsOf(
          active: [
            inProgress(7, TradePosition.public, origin: TradeOrigin.madeHere),
            inProgress(4, TradePosition.chatting),
            inProgress(2, TradePosition.waitingForEscrow),
          ],
        );
        expect(GarageOpening.of(key, records), slot(7));
        expect(GarageOpening.lockedOf(key, records), [
          slot(2),
          slot(4),
          slot(7),
        ]);
      },
    );

    test(
      'a pending take, a pre-take, a make waiting for its bond and a take never sent are never opened on',
      () {
        final records = recordsOf(
          active: [
            inProgress(5, TradePosition.start, confirmed: false),
            inProgress(6, TradePosition.bondStep),
            inProgress(7, TradePosition.preTakeUnavailable),
            inProgress(
              8,
              TradePosition.makerBondStep,
              origin: TradeOrigin.madeHere,
            ),
            ActiveTrade(
              record(10, confirmed: false),
              const ActiveTradeTakeNeverSent(),
            ),
            ActiveTrade(
              record(11, origin: TradeOrigin.madeHere),
              const ActiveTradeUnrestorable(TradeRecordMalformed()),
            ),
          ],
          closed: [finished(3, TradePosition.expired)],
        );
        expect(GarageOpening.of(key, records), slot(3));
        // A take that never happened is no « Last order #N » line: nothing to open on.
        expect(
          GarageOpening.of(
            key,
            recordsOf(
              closed: [
                finished(4, TradePosition.publicAgain, confirmed: false),
              ],
            ),
          ),
          isNull,
        );
      },
    );

    test('a trade recovered is never followed, nor a line', () {
      final records = recordsOf(
        active: [
          inProgress(5, TradePosition.chatting, origin: TradeOrigin.recovered),
        ],
        closed: [
          finished(6, TradePosition.succeeded, origin: TradeOrigin.recovered),
        ],
      );
      expect(GarageOpening.of(key, records), isNull);
    });

    test(
      'the newest line counts: a trade after an expiry moves, an expiry after a trade does not',
      () {
        expect(
          GarageOpening.of(
            key,
            recordsOf(
              closed: [
                finished(2, TradePosition.expired, at: 10),
                finished(3, TradePosition.succeeded, at: 20),
              ],
            ),
          ),
          slot(9),
        );
        expect(
          GarageOpening.of(
            key,
            recordsOf(
              closed: [
                finished(2, TradePosition.succeeded, at: 10),
                finished(3, TradePosition.expired, at: 20),
              ],
            ),
          ),
          slot(3),
        );
      },
    );

    test(
      'no trade of the key: the first usable robot (null); a line of another key: the same',
      () {
        expect(GarageOpening.of(key, recordsOf()), isNull);
        expect(
          GarageOpening.of(
            key,
            recordsOf(
              closed: [
                finished(3, TradePosition.succeeded, of: otherFingerprint),
              ],
            ),
          ),
          isNull,
        );
      },
    );

    test(
      'a key imported or acknowledged follows the same rule since 2026-11-26 (#81): a trade taken here counts as one made here',
      () {
        final records = recordsOf(
          fresh: null,
          active: [inProgress(5, TradePosition.chatting)],
          closed: [finished(3, TradePosition.succeeded)],
        );
        expect(GarageOpening.of(key, records), slot(5));
        final made = recordsOf(
          fresh: null,
          active: [
            inProgress(5, TradePosition.public, origin: TradeOrigin.madeHere),
          ],
          closed: [finished(3, TradePosition.succeeded)],
        );
        expect(GarageOpening.of(key, made), slot(5));
      },
    );

    test('no fresh robot left: the Garage stays on the robot of the trade', () {
      expect(
        GarageOpening.of(
          key,
          recordsOf(
            fresh: null,
            closed: [finished(3, TradePosition.succeeded)],
          ),
        ),
        slot(3),
      );
    });
  });

  group(
    'the sentence on a robot involved in a trade, and the record read once',
    () {
      test(
        'the orders of a robot held here with an end that has not served',
        () {
          final records = recordsOf(
            closed: [
              finished(3, TradePosition.expired),
              finished(4, TradePosition.succeeded),
              finished(5, TradePosition.publicAgain),
              finished(6, TradePosition.expired, confirmed: false),
            ],
          );
          expect(records.ordersNotServedOf(slot(3)), {('temple', 40003)});
          expect(records.ordersNotServedOf(slot(4)), isEmpty);
          expect(records.ordersNotServedOf(slot(5)), {('temple', 40005)});
          expect(records.ordersNotServedOf(slot(6)), isEmpty);
          expect(records.ordersNotServedOf(slot(7)), isEmpty);
        },
      );

      test('the open record of a robot, never a recovered one', () {
        final records = recordsOf(
          active: [
            inProgress(5, TradePosition.chatting),
            inProgress(
              6,
              TradePosition.chatting,
              origin: TradeOrigin.recovered,
            ),
          ],
        );
        expect(records.openRecordOf(slot(5))?.orderId, 40005);
        expect(records.openRecordOf(slot(6)), isNull);
        expect(records.openRecordOf(slot(7)), isNull);
      });
    },
  );

  group('where the user left the Garage by hand (§ 4.1, step 4)', () {
    final served = recordsOf(closed: [finished(3, TradePosition.succeeded)]);

    test(
      'the rule applies until the user moves by hand; then the robot left stays, records read again or not',
      () {
        final navigation = GarageNavigation();
        expect(navigation.robotOf(key, Ok(served)), slot(9));
        navigation.leave(key, slot(3), Ok(served));
        expect(navigation.robotOf(key, Ok(served)), slot(3));
        expect(
          navigation.robotOf(key, const Err(P2pStorageFailure())),
          slot(3),
        );
        expect(navigation.leftByHand(key), slot(3));
      },
    );

    test(
      'a trade of the key ending at 14, 17 or 18 after it was left: the rule again',
      () {
        for (final position in [
          TradePosition.succeeded,
          TradePosition.makerLostDispute,
          TradePosition.takerLostDispute,
        ]) {
          final navigation = GarageNavigation()
            ..leave(key, slot(3), Ok(served));
          final ended = recordsOf(
            closed: [...served.closed, finished(5, position, at: 300)],
          );
          expect(
            navigation.robotOf(key, Ok(ended)),
            slot(9),
            reason: position.name,
          );
          expect(navigation.leftByHand(key), isNull);
        }
      },
    );

    test(
      'an expiry, a cancellation, an end unknown after it was left: it stays',
      () {
        for (final position in [
          TradePosition.expired,
          TradePosition.cancelled,
          null,
          TradePosition.publicAgain,
        ]) {
          final navigation = GarageNavigation()
            ..leave(key, slot(3), Ok(served));
          final ended = recordsOf(
            closed: [...served.closed, finished(5, position, at: 300)],
          );
          expect(
            navigation.robotOf(key, Ok(ended)),
            slot(3),
            reason: '$position',
          );
        }
      },
    );

    test(
      'a trade of the key whose bond locks after it was left: the rule again, as the « Last order #N » tap since #227',
      () {
        final navigation = GarageNavigation()..leave(key, slot(1), Ok(served));
        final locked = recordsOf(
          active: [inProgress(9, TradePosition.waitingForBoth)],
          closed: served.closed,
          fresh: 10,
        );
        expect(navigation.robotOf(key, Ok(locked)), slot(9));
        expect(navigation.leftByHand(key), isNull);
      },
    );

    test(
      'a trade already in progress when it was left, and its end without a trade, keep it',
      () {
        final running = recordsOf(
          active: [inProgress(5, TradePosition.chatting)],
          closed: served.closed,
        );
        final navigation = GarageNavigation()..leave(key, slot(1), Ok(running));
        expect(navigation.robotOf(key, Ok(running)), slot(1));
        final expired = recordsOf(
          closed: [
            ...served.closed,
            finished(5, TradePosition.expired, at: 300),
          ],
        );
        expect(navigation.robotOf(key, Ok(expired)), slot(1));
      },
    );

    test(
      'left before the records could be read: the first records read are taken as those of that moment',
      () {
        final navigation = GarageNavigation()..leave(key, slot(1), null);
        expect(navigation.robotOf(key, Ok(served)), slot(1));
        final ended = recordsOf(
          closed: [
            ...served.closed,
            finished(5, TradePosition.succeeded, at: 300),
          ],
        );
        expect(navigation.robotOf(key, Ok(ended)), slot(9));
      },
    );

    test('another key on the network, or the key deleted: forgotten', () {
      final navigation = GarageNavigation()..leave(key, slot(3), Ok(served));
      final other = NetworkGarageKey(testnet, _keyOf(90));
      expect(navigation.leftByHand(other), isNull);
      expect(navigation.robotOf(other, Ok(recordsOf())), isNull);
      expect(navigation.leftByHand(key), isNull);
      navigation
        ..leave(key, slot(3), Ok(served))
        ..forget(testnet);
      expect(navigation.robotOf(key, Ok(served)), slot(9));
    });
  });

  group('the fresh robot: the robot the next trade reserves, without reserving it', () {
    late P2pDatabase database;
    late RobotBindingRepositoryImpl bindings;
    late TradeRecordRepositoryImpl trades;
    late InterimTradeRobots robots;
    late HistoryRecords history;
    final temple = coordinator('temple');

    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      database = P2pDatabase.forTesting(NativeDatabase.memory());
      bindings = bindingsInMemory(database: database);
      trades = TradeRecordRepositoryImpl(database, clock: () => testNow);
      robots = InterimTradeRobots(_Vault({testnet: Ok(key)}), trades);
      history = HistoryRecords(
        trades,
        TradeTrailRepositoryImpl(database),
        testnet,
      );
      expect(
        await bindings.recordGeneratedKey(testnet, fingerprint),
        isA<Ok>(),
      );
    });

    tearDown(() => database.close());

    Future<RobotSlot?> fresh() async {
      final standing = switch (await trades.newTradeStandingOf(
        testnet,
        fingerprint,
      )) {
        Ok(:final value) => value,
        Err(:final failure) => fail('$failure'),
      };
      return switch (NextTradeRobot.of(key, standing)) {
        Ok(:final value) => value.slot,
        Err() => null,
      };
    }

    Future<RobotSlot> reserveNext() async =>
        switch (await robots.robotForNewTrade(testnet, temple)) {
          Ok(:final value) => value.robot.slot,
          Err(:final failure) => fail('$failure'),
        };

    Future<void> bindByHand(int index) async {
      expect(
        await bindings.bind(slot(index), switch (CoordinatorIdentity.of(
          coordinator('lake'),
          testnet,
        )) {
          final identity? => identity,
          null => fail('lake'),
        }),
        isA<Ok>(),
      );
    }

    test(
      'equal to the robot the next reservation takes, after trades, a reservation never sent, and robots bound by « Select Host » above and below the last trade',
      () async {
        expect(await fresh(), slot(0));
        expect(await reserveNext(), slot(0));
        // A trade that ended, a reservation never sent, a robot bound by hand below and above it.
        await history.taken(slot(1), orderId: 7001);
        await bindByHand(2);
        final ended = await history.taken(slot(3), orderId: 7003);
        await bindByHand(4);
        final before = await fresh();
        expect(before, slot(5));
        expect(before?.accountIndex, greaterThan(ended.robot.accountIndex));
        expect(await reserveNext(), before);
        expect(await fresh(), slot(6));
      },
    );

    test('a key from elsewhere has one too, since 2026-11-26 (#81)', () async {
      expect(
        NextTradeRobot.of(key, NewTradeStanding(indexesInUse: const [0])),
        isA<Ok<NetworkRobot, P2pFailure>>().having(
          (ok) => ok.value.accountIndex,
          'index',
          greaterThan(0),
        ),
      );
    });

    test('skipped indexes: the same search as the reservation', () {
      // No Garage Key is known with an index to skip: robots are played by their indexes, and index 3 is skipped (its first usable robot from 3 is 4).
      Result<int, P2pFailure> firstUsable(int from) => switch (from) {
        3 => const Ok(4),
        > 9 => const Err(GarageRobotUnavailableFailure()),
        _ => Ok(from),
      };
      for (final inUse in [
        <int>{},
        {0, 1, 2},
        {0, 1, 2, 4},
        {0, 1, 2, 4, 5, 6, 7, 8, 9},
      ]) {
        final shown = NextTradeRobot.firstFreeAmong(
          inUse,
          firstUsable,
          (index) => index,
        );
        final reserved = InterimTradeRobots.firstFreeAmong(
          inUse,
          firstUsable,
          (index) => index,
        );
        expect('$shown', '$reserved', reason: '$inUse');
      }
    });

    test(
      'the records the Garage reads, after each write, and the robot it would show',
      () async {
        final follow = FollowTradesUsecase(
          (network) => trades
              .watchActiveTrades(network)
              .map(
                (result) => switch (result) {
                  Ok(:final value) => Ok([
                    for (final record in value)
                      ActiveTrade(
                        record,
                        const ActiveTradeAt(
                          TradePosition.chatting,
                          deadline: null,
                          breached: false,
                          historyUnknown: false,
                        ),
                      ),
                  ]),
                  Err(:final failure) => Err(failure),
                },
              ),
          trades.watchClosedTrades,
          trades.newTradeStandingOf,
        );
        final seen = <Result<GarageRecords, P2pFailure>>[];
        final listening = follow.execute(key).listen(seen.add);
        await pumpEventQueue();
        expect(seen, hasLength(1));
        expect(switch (seen.last) {
          Ok(:final value) => GarageOpening.of(key, value),
          Err() => fail('unreadable'),
        }, isNull);
        await history.taken(slot(0), orderId: 7000);
        await pumpEventQueue();
        final last = switch (seen.last) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(last.fresh, slot(1));
        expect(GarageOpening.of(key, last), slot(1));
        final navigation = GarageNavigation();
        final garage = GarageRobotUsecase(
          _Vault({testnet: Ok(key)}),
          follow,
          navigation,
        );
        expect(await garage.execute(testnet), slot(1));
        navigation.leave(key, slot(0), seen.last);
        expect(await garage.execute(testnet), slot(0));
        expect(await garage.execute(RobosatsNetwork.mainnet), isNull);
        await listening.cancel();
      },
    );

    test(
      'records that cannot be read: a failure, never empty records',
      () async {
        final follow = FollowTradesUsecase(
          (network) => Stream.value(const Err(P2pStorageFailure())),
          trades.watchClosedTrades,
          trades.newTradeStandingOf,
        );
        expect(
          await follow.execute(key).first,
          isA<Err<GarageRecords, P2pFailure>>(),
        );
        final garage = GarageRobotUsecase(
          _Vault({testnet: Ok(key)}),
          follow,
          GarageNavigation(),
        );
        expect(await garage.execute(testnet), isNull);
      },
    );

    test('cancelled: the watches of the records stop at once', () async {
      final active = StreamController<Result<List<ActiveTrade>, P2pFailure>>();
      final closed = StreamController<Result<List<ClosedTrade>, P2pFailure>>();
      final follow = FollowTradesUsecase(
        (network) => active.stream,
        (network) => closed.stream,
        trades.newTradeStandingOf,
      );
      final listening = follow.execute(key).listen((_) {});
      await pumpEventQueue();
      expect(active.hasListener, isTrue);
      expect(closed.hasListener, isTrue);
      await listening.cancel();
      expect(active.hasListener, isFalse);
      expect(closed.hasListener, isFalse);
      await active.close();
      await closed.close();
    });
  });
}
