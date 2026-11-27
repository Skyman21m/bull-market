import 'dart:async';
import 'dart:io' show FileSystemException;
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/data/trade_trail_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/order_history.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/trade/trade_edges.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/trade/list_order_history_usecase.dart';
import 'package:p2p/src/presentation/order_history_cubit.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'support/history_records.dart';
import 'support/robot_bindings.dart';

GarageKeyFingerprint _fingerprintOf(int seed) => switch (GarageKey.fromBytes(
  Uint8List.fromList(List<int>.generate(32, (i) => seed + i)),
)) {
  Ok(value: final key) => switch (GarageKeyFingerprint.of(key)) {
    Ok(:final value) => value,
    Err(:final failure) => throw StateError('$failure'),
  },
  Err(:final failure) => throw StateError('$failure'),
};

/// A record as the repository reads one back, for the pure tests: test values only.
TradeRecord recordForTests({
  required RobotSlot robot,
  required int orderId,
  required TradeOrigin origin,
  required DateTime? confirmedAt,
  required DateTime? closedAt,
}) => TradeRecord(
  robot: robot,
  coordinatorAlias: 'temple',
  coordinatorOnion: 'http://temple.onion',
  orderId: orderId,
  role: TradeRole.buyer,
  origin: origin,
  takenAt: DateTime.utc(2026, 11, 1),
  confirmedAt: confirmedAt,
  closedAt: closedAt,
);

/// The history of finished orders of the Garage (#253, design note `docs/design/phase-3-order-history.md`): the table of the ends, what counts as finished, the order of the lines, the records whose end is unknown, the read of the records and the trails in one statement, and the cubit's pages.
void main() {
  const testnet = RobosatsNetwork.testnet;
  final key = _fingerprintOf(1);
  final otherKey = _fingerprintOf(40);

  group('the end of a finished order', () {
    test('five ends say how the order ended, every other position none', () {
      // The design note's table, position by position: only these five affirm an end.
      const said = {
        TradePosition.succeeded: OrderEnd.traded,
        TradePosition.expired: OrderEnd.expired,
        TradePosition.cancelled: OrderEnd.cancelled,
        TradePosition.makerLostDispute: OrderEnd.dispute,
        TradePosition.takerLostDispute: OrderEnd.dispute,
      };
      for (final position in TradePosition.values) {
        expect(
          OrderEnd.of(position),
          said[position] ?? OrderEnd.unknown,
          reason: position.name,
        );
      }
      expect(OrderEnd.of(null), OrderEnd.unknown);
    });

    test(
      'a robot that dropped out of its order is never given an affirmative end',
      () {
        // Public again without it, or no longer shown to it: its own part ended, not the order.
        expect(OrderEnd.of(TradePosition.publicAgain), OrderEnd.unknown);
        expect(OrderEnd.of(TradePosition.notAvailable), OrderEnd.unknown);
        // Every terminal position is either one of the four ends or unknown.
        for (final position in TradePosition.values.where(
          (p) => p.isTerminal,
        )) {
          expect(
            OrderEnd.of(position),
            isIn([
              OrderEnd.traded,
              OrderEnd.expired,
              OrderEnd.cancelled,
              OrderEnd.dispute,
              OrderEnd.unknown,
            ]),
          );
        }
      },
    );
  });

  group('what counts as finished, and the order of the lines', () {
    final base = DateTime.utc(2026, 11, 20, 12);

    TradeRecord record({
      int index = 0,
      int orderId = 1,
      GarageKeyFingerprint? of,
      TradeOrigin origin = TradeOrigin.takenHere,
      DateTime? confirmedAt,
      bool confirmed = true,
      DateTime? closedAt,
      bool closed = true,
    }) => recordForTests(
      robot: RobotSlot(testnet, of ?? key, index),
      orderId: orderId,
      origin: origin,
      confirmedAt: confirmed ? confirmedAt ?? base : null,
      closedAt: closed ? closedAt ?? base : null,
    );

    test(
      'only records closed after their order was confirmed, of the key, made or taken here',
      () {
        final finished = record(index: 1, orderId: 11);
        final made = record(
          index: 2,
          orderId: 12,
          origin: TradeOrigin.madeHere,
        );
        final history = OrderHistory.of([
          ClosedTrade(finished, TradePosition.succeeded),
          ClosedTrade(made, TradePosition.expired),
          // A take that never happened: closed, never confirmed.
          ClosedTrade(
            record(index: 3, orderId: 13, confirmed: false),
            TradePosition.publicAgain,
          ),
          // Still in progress: never in the history, whatever its trail says.
          ClosedTrade(
            record(index: 4, orderId: 14, closed: false),
            TradePosition.succeeded,
          ),
          // Another Garage Key.
          ClosedTrade(
            record(index: 5, orderId: 15, of: otherKey),
            TradePosition.succeeded,
          ),
          // Recovered from a pasted key: neither made nor taken here.
          ClosedTrade(
            record(index: 6, orderId: 16, origin: TradeOrigin.recovered),
            TradePosition.succeeded,
          ),
        ], key);
        expect([for (final order in history) order.record.orderId], [12, 11]);
        expect(history.first.end, OrderEnd.expired);
        expect(history.last.end, OrderEnd.traded);
        expect(history.first.endedAt, base);
      },
    );

    test(
      'without a key, the finished orders of every key of the network, the newest end first (#81)',
      () {
        final history = OrderHistory.of([
          ClosedTrade(record(index: 1, orderId: 11), TradePosition.succeeded),
          ClosedTrade(
            record(index: 5, orderId: 15, of: otherKey),
            TradePosition.succeeded,
          ),
        ]);
        expect({for (final order in history) order.record.orderId}, {11, 15});
      },
    );

    test(
      'the newest end first; equal ends by the higher order, then the higher robot',
      () {
        ClosedTrade at(int index, int orderId, int hours) => ClosedTrade(
          record(
            index: index,
            orderId: orderId,
            closedAt: base.add(Duration(hours: hours)),
          ),
          TradePosition.succeeded,
        );
        final rows = [
          at(1, 100, 1),
          at(2, 300, 5),
          at(3, 200, 5),
          at(4, 50, 9),
          at(5, 200, 5),
        ];
        final expected = [(4, 50), (2, 300), (5, 200), (3, 200), (1, 100)];
        for (final order in [rows, rows.reversed.toList()]) {
          expect([
            for (final line in OrderHistory.of(order, key))
              (line.record.robot.accountIndex, line.record.orderId),
          ], expected);
        }
      },
    );

    test(
      'a record whose trail is missing or not read back ends unknown, never dropped',
      () {
        final history = OrderHistory.of([
          ClosedTrade(record(index: 1, orderId: 1), null),
          ClosedTrade(record(index: 2, orderId: 2), TradePosition.chatting),
        ], key);
        expect(
          [for (final order in history) order.end],
          [OrderEnd.unknown, OrderEnd.unknown],
        );
      },
    );
  });

  test(
    'a closed trade and a finished order print their type only: no order number, coordinator or robot (#273)',
    () {
      final record = recordForTests(
        robot: RobotSlot(testnet, key, 731),
        orderId: 48213,
        origin: TradeOrigin.takenHere,
        confirmedAt: DateTime.utc(2026, 11, 2),
        closedAt: DateTime.utc(2026, 11, 3),
      );
      final closed = ClosedTrade(record, TradePosition.succeeded);
      final finished = OrderHistory.of([closed], key).single;
      expect('$closed', 'ClosedTrade');
      expect('$finished', 'FinishedOrder');
      for (final printed in [
        '$closed',
        '$finished',
        '${[finished]}',
      ]) {
        for (final part in ['48213', '731', 'temple', 'onion', 'buyer']) {
          expect(printed, isNot(contains(part)), reason: printed);
        }
      }
    },
  );

  group('the records and the trails, read in one statement', () {
    late P2pDatabase database;
    late RobotBindingRepositoryImpl bindings;
    late TradeRecordRepositoryImpl trades;
    late TradeTrailRepositoryImpl trails;
    late HistoryRecords records;
    var now = DateTime.utc(2026, 11, 20, 12);

    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      database = P2pDatabase.forTesting(NativeDatabase.memory());
      bindings = bindingsInMemory(database: database);
      trades = TradeRecordRepositoryImpl(database, clock: () => now);
      trails = TradeTrailRepositoryImpl(database);
      records = HistoryRecords(trades, trails, testnet);
      expect(await bindings.recordGeneratedKey(testnet, key), isA<Ok>());
    });

    tearDown(() => database.close());

    RobotSlot robot(int index) => RobotSlot(testnet, key, index);

    Future<List<ClosedTrade>> closed() async =>
        switch (await trades.watchClosedTrades(testnet).first) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };

    test(
      'each closed record with the last position of its trail, an open one left out',
      () async {
        final traded = await records.taken(robot(1), orderId: 101);
        now = now.add(const Duration(hours: 1));
        final expired = await records.made(
          robot(2),
          orderId: 102,
          position: 'expired',
        );
        now = now.add(const Duration(hours: 1));
        final dispute = await records.taken(
          robot(3),
          orderId: 103,
          role: TradeRole.seller,
          position: 'takerLostDispute',
        );
        await records.taken(robot(4), orderId: 104, closed: false);
        // A take that never happened: closed, never confirmed; read, then left out of the history.
        final notMade = await records.taken(
          robot(5),
          orderId: 105,
          position: 'publicAgain',
          confirmed: false,
        );
        expect(await closed(), [
          ClosedTrade(traded, TradePosition.succeeded),
          ClosedTrade(expired, TradePosition.expired),
          ClosedTrade(dispute, TradePosition.takerLostDispute),
          ClosedTrade(notMade, TradePosition.publicAgain),
        ]);
        final history = switch (await ListOrderHistoryUsecase(
          trades,
        ).execute(testnet).first) {
          Ok(:final value) => value,
          Err(:final failure) => fail('$failure'),
        };
        expect(
          [for (final order in history) (order.record.orderId, order.end)],
          [
            (103, OrderEnd.dispute),
            (102, OrderEnd.expired),
            (101, OrderEnd.traded),
          ],
        );
        expect(
          (await ListOrderHistoryUsecase(
            trades,
          ).execute(RobosatsNetwork.mainnet).first),
          isA<Ok<List<FinishedOrder>, P2pFailure>>().having(
            (ok) => ok.value,
            'value',
            isEmpty,
          ),
        );
        expect(
          (await trades.watchClosedTrades(RobosatsNetwork.mainnet).first),
          isA<Ok<List<ClosedTrade>, P2pFailure>>().having(
            (ok) => ok.value,
            'value',
            isEmpty,
          ),
        );
      },
    );

    test(
      'a closed record with no trail stored is read with no position',
      () async {
        final record = await records.taken(
          robot(1),
          orderId: 7,
          position: null,
        );
        expect(await closed(), [ClosedTrade(record, null)]);
      },
    );

    test(
      'a trail of an unknown version, or of another order, is read with no position, the list kept',
      () async {
        final kept = await records.taken(robot(1), orderId: 7);
        now = now.add(const Duration(hours: 1));
        final later = await records.taken(robot(2), orderId: 8);
        now = now.add(const Duration(hours: 1));
        final other = await records.taken(robot(3), orderId: 9);
        // A file a later version wrote, or a damaged one: the rows are changed under the triggers, which refuse it otherwise.
        for (final trigger in [
          'trade_trails_closed',
          'trade_trails_forward',
          'trade_trails_terms_trace',
        ]) {
          await database.customStatement('DROP TRIGGER IF EXISTS $trigger');
        }
        await database.customStatement(
          'UPDATE trade_trails SET version = 2 WHERE robot_index = 2',
        );
        await database.customStatement(
          'UPDATE trade_trails SET order_id = 99 WHERE robot_index = 3',
        );
        expect(await closed(), [
          ClosedTrade(kept, TradePosition.succeeded),
          ClosedTrade(later, null),
          ClosedTrade(other, null),
        ]);
      },
    );

    test(
      'a new list after each write of the records or of the trails',
      () async {
        final lists = <List<int>>[];
        final subscription = trades.watchClosedTrades(testnet).listen((result) {
          if (result case Ok(:final value)) {
            lists.add([for (final closed in value) closed.record.orderId]);
          }
        });
        addTearDown(subscription.cancel);
        await pumpEventQueue();
        await records.taken(robot(1), orderId: 7);
        await pumpEventQueue();
        expect(lists.first, isEmpty);
        expect(lists.last, [7]);
      },
    );

    test(
      'a database that cannot be read gives a failure, never an empty list',
      () async {
        final broken = P2pDatabase.forTesting(
          NativeDatabase.memory(
            setup: (_) =>
                throw const FileSystemException('unavailable for the test'),
          ),
        );
        addTearDown(broken.close);
        final result = await TradeRecordRepositoryImpl(
          broken,
          clock: () => now,
        ).watchClosedTrades(testnet).first;
        expect(result, isA<Err<List<ClosedTrade>, P2pFailure>>());
      },
    );
  });

  group('the cubit of the history', () {
    late StreamController<Result<List<FinishedOrder>, P2pFailure>> source;
    final asked = <RobosatsNetwork>[];

    setUp(() {
      source = StreamController.broadcast();
      asked.clear();
    });

    tearDown(() => source.close());

    OrderHistoryCubit cubit() => OrderHistoryCubit(testnet, (network) {
      asked.add(network);
      return source.stream;
    });

    List<FinishedOrder> orders(int count) => OrderHistory.of([
      for (var i = 0; i < count; i++)
        ClosedTrade(
          recordForTests(
            robot: RobotSlot(testnet, key, i),
            orderId: 1000 + i,
            origin: TradeOrigin.takenHere,
            confirmedAt: DateTime.utc(2026, 11, 1),
            closedAt: DateTime.utc(2026, 11, 1).add(Duration(minutes: i)),
          ),
          TradePosition.succeeded,
        ),
    ], key);

    test(
      'folded until opened, then ten, then ten more at each « See more »',
      () async {
        final history = cubit()..start();
        addTearDown(history.close);
        expect(asked, [testnet]);
        source.add(Ok(orders(23)));
        await pumpEventQueue();
        expect(history.state.open, isFalse);
        expect(history.state.lines, isEmpty);
        expect(history.state.hasMore, isFalse);
        history.open();
        expect(history.state.lines, hasLength(10));
        expect(history.state.lines.first.record.orderId, 1022);
        expect(history.state.hasMore, isTrue);
        history.showMore();
        expect(history.state.lines, hasLength(20));
        // No line skipped: the eleventh follows the tenth.
        expect(
          [for (final line in history.state.lines) line.record.orderId],
          [for (var id = 1022; id > 1002; id--) id],
        );
        history.showMore();
        expect(history.state.lines, hasLength(23));
        expect(history.state.hasMore, isFalse);
        history.showMore();
        expect(history.state.shown, 30);
        // Folded, then opened again: the first page only.
        history.fold();
        expect(history.state.open, isFalse);
        expect(history.state.lines, isEmpty);
        history.open();
        expect(history.state.lines, hasLength(10));
      },
    );

    test(
      'a new list after a write keeps the lines shown, the newest first',
      () async {
        final history = cubit()..start();
        addTearDown(history.close);
        source.add(Ok(orders(12)));
        await pumpEventQueue();
        history
          ..open()
          ..showMore();
        expect(history.state.lines, hasLength(12));
        source.add(Ok(orders(15)));
        await pumpEventQueue();
        expect(history.state.lines, hasLength(15));
        expect(history.state.lines.first.record.orderId, 1014);
      },
    );

    test('records that cannot be read are said, never « no order »', () async {
      final history = cubit()..start();
      addTearDown(history.close);
      source.add(const Err(P2pStorageFailure()));
      await pumpEventQueue();
      expect(history.state.read, isA<OrderHistoryUnreadable>());
      history.open();
      expect(history.state.lines, isEmpty);
      expect(history.state.hasMore, isFalse);
    });

    test('its state prints counts only', () async {
      final history = cubit()..start();
      addTearDown(history.close);
      source.add(Ok(orders(3)));
      await pumpEventQueue();
      expect('${history.state}', isNot(contains('100')));
      expect('${history.state}', contains('3 orders'));
    });
  });
}
