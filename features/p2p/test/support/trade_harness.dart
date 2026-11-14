import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/data/trade_trail_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/interim_trade_robots.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/p2p_waits.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/trade_record_repository.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/robot_key_compute_port.dart';
import 'package:p2p/src/domain/robot_request_limiter.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/put_robot_on_coordinator_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/cancel_trade_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/list_active_trades_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/take_order_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/src/domain/usecases/trade/watch_trade_usecase.dart';
import 'package:p2p/testing.dart' show ScriptedCoordinator;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'robot_coordinators.dart' show pairOf;

/// A Garage Key made for the trade tests only.
final GarageKey tradeKey = switch (GarageKey.fromBytes(
  Uint8List.fromList(List<int>.generate(32, (i) => 101 + i)),
)) {
  Ok(:final value) => value,
  Err(:final failure) => throw StateError('$failure'),
};

/// The app stopped at a step: an `Error`, which no use case catches.
final class AppKilled extends Error {}

/// Where the tests stop the app.
enum KillAt {
  none,

  /// After the robot was reserved, as its first contact leaves.
  afterReservation,

  /// After the pending take, before its terms.
  afterPendingTake,

  /// After the terms, before the first trail.
  afterTerms,

  /// After the take's answer, before its trail is written.
  beforeTrailOfAnswer,
}

/// The robots' key pairs, made once for the whole run (one S2K of 32 MiB each).
final Map<RobotHashId, RobotPgpKey> _pairs = {};

final class _LazyPairs implements RobotKeyComputePort {
  @override
  Future<Result<RobotPgpKey, RobotKeyComputeFailure>> generate(
    RobotIdentity identity,
  ) async => Ok(_pairs.putIfAbsent(identity.hashId, () => pairOf(identity)));

  @override
  Future<
    Result<
      Result<CoordinatorRobot, RobotPgpKeyNotProven>,
      RobotKeyComputeFailure
    >
  >
  prove(UnprovenCoordinatorRobot robot) async => Ok(robot.prove());
}

final class _Vault implements GarageKeyRepository {
  final NetworkGarageKey key;

  _Vault(this.key);

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> read(
    RobosatsNetwork network,
  ) async =>
      network == key.network ? Ok(key) : const Err(GarageKeyMissingFailure());

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> create(
    RobosatsNetwork network,
  ) => throw UnimplementedError();

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

  @override
  Future<Result<void, P2pFailure>> delete(RobosatsNetwork network) =>
      throw UnimplementedError();
}

/// The trade records, stopping the app where [kill] says.
final class _KillingRecords implements TradeRecordRepository {
  final TradeRecordRepository _inner;
  final KillAt Function() _kill;

  _KillingRecords(this._inner, this._kill);

  @override
  Future<Result<NewTradeStanding, P2pFailure>> newTradeStandingOf(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) => _inner.newTradeStandingOf(network, key);

  @override
  Future<Result<TradeReservation?, P2pFailure>> reserveForNewTrade(
    RobotSlot robot,
    CoordinatorIdentity coordinator,
  ) => _inner.reserveForNewTrade(robot, coordinator);

  @override
  Future<Result<TradeRecord, P2pFailure>> recordPendingTake(
    TradeReservation reservation, {
    required int orderId,
    required TradeRole role,
  }) async {
    final written = await _inner.recordPendingTake(
      reservation,
      orderId: orderId,
      role: role,
    );
    if (_kill() == KillAt.afterPendingTake) throw AppKilled();
    return written;
  }

  @override
  Future<Result<TradeRecord, P2pFailure>> recordRecoveredTrade(
    RobotSlot robot,
    CoordinatorIdentity coordinator, {
    required int orderId,
    required TradeRole role,
  }) => _inner.recordRecoveredTrade(
    robot,
    coordinator,
    orderId: orderId,
    role: role,
  );

  @override
  Future<Result<TradeRecord, P2pFailure>> confirmTake(TradeRecord record) =>
      _inner.confirmTake(record);

  @override
  Future<Result<TradeRecord, P2pFailure>> closeTrade(TradeRecord record) =>
      _inner.closeTrade(record);

  @override
  Stream<Result<List<TradeRecord>, P2pFailure>> watchActiveTrades(
    RobosatsNetwork network,
  ) => _inner.watchActiveTrades(network);
}

/// The terms and trails, stopping the app, or failing a write, where the test says.
final class TestTrails implements TradeTrailRepository {
  final TradeTrailRepository _inner;
  final KillAt Function() _kill;

  /// What the next [recordTerms] gives instead of writing, when set.
  P2pFailure? termsFailure;

  /// How many trails were asked to be stored.
  int stores = 0;

  TestTrails(this._inner, this._kill);

  @override
  Future<Result<void, P2pFailure>> recordTerms(
    TradeRecord trade,
    TradeTermsRecord terms,
  ) async {
    if (termsFailure case final failure?) return Err(failure);
    final written = await _inner.recordTerms(trade, terms);
    if (_kill() == KillAt.afterTerms) throw AppKilled();
    return written;
  }

  @override
  Future<Result<TrailStoreOutcome, P2pFailure>> storeTrail(
    TradeRecord trade,
    TradeTrailRecord trail,
  ) {
    stores++;
    if (stores == 2 && _kill() == KillAt.beforeTrailOfAnswer) {
      throw AppKilled();
    }
    return _inner.storeTrail(trade, trail);
  }

  @override
  Future<Result<StoredTradeHistory, P2pFailure>> historyOf(TradeRecord trade) =>
      _inner.historyOf(trade);

  @override
  Stream<Result<Map<RobotSlot, StoredTradeHistory>, P2pFailure>> watchHistories(
    RobosatsNetwork network,
  ) => _inner.watchHistories(network);
}

/// A timer of the watch, which the harness fires when its time comes.
final class HarnessTimer implements Timer {
  final DateTime due;
  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  HarnessTimer(this.due, this.duration, this._callback);

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}

/// One run of the app over a database the runs share: the real repositories, robot layer, limiter and use cases, the coordinator played by [ScriptedCoordinator], a clock and timers the test moves.
final class TradeHarness {
  final RobosatsNetwork network;
  final P2pDatabase database;
  final ScriptedCoordinator coordinator;
  DateTime now;
  KillAt kill = KillAt.none;

  /// Every timer the watch started, in order.
  final List<HarnessTimer> timers = [];

  /// Every wait of the limiter after a busy answer.
  final List<Duration> busyWaits = [];

  late final RobotBindingRepositoryImpl bindings;
  late final TradeRecordRepository records;
  late final TestTrails trails;
  late final InterimTradeRobots robots;
  late final RobotRequestLimiter limiter;
  late final TradeReader reader;
  late final TakeOrderUsecase take;
  late final WatchTradeUsecase watch;
  late final CancelTradeUsecase cancel;
  late final ListActiveTradesUsecase list;

  TradeHarness._(this.network, this.database, this.coordinator, this.now) {
    DateTime clock() => now;
    bindings = RobotBindingRepositoryImpl(database, clock: clock);
    records = _KillingRecords(
      TradeRecordRepositoryImpl(database, clock: clock),
      () => kill,
    );
    trails = TestTrails(TradeTrailRepositoryImpl(database), () => kill);
    robots = InterimTradeRobots(
      _Vault(NetworkGarageKey(network, tradeKey)),
      records,
    );
    limiter = RobotRequestLimiter(
      elapsed: () => now.difference(DateTime.utc(2026)),
      delay: (wait) async => busyWaits.add(wait),
      random: () => 0.5,
    );
    final client = CoordinatorClient(coordinator, clock: clock);
    final invoices = Bolt11Reader(coordinator.decoder);
    reader = TradeReader(
      robots,
      records,
      trails,
      bindings,
      client,
      Federation.robosats,
      invoices,
      clock: clock,
    );
    final put = PutRobotOnCoordinatorUsecase(
      FetchRobotUsecase(client, bindings, _LazyPairs()),
      bindings,
      limiter,
    );
    take = TakeOrderUsecase(
      client,
      robots,
      put,
      records,
      trails,
      reader,
      limiter,
      invoices,
    );
    watch = WatchTradeUsecase(
      reader,
      limiter,
      P2pWaits(
        start: (duration, callback) {
          final timer = HarnessTimer(now.add(duration), duration, callback);
          timers.add(timer);
          return timer;
        },
        random: () => 0.5,
      ),
    );
    cancel = CancelTradeUsecase(client, reader, limiter);
    list = ListActiveTradesUsecase(robots, trails, clock: clock);
  }

  /// A first run: a new database, the key recorded as drawn here, and [coordinator] playing the order.
  static Future<TradeHarness> start({
    RobosatsNetwork network = RobosatsNetwork.testnet,
    int orderType = 1,
    double takerFee = 0.00175,
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final now = DateTime.utc(2026, 11, 14, 9);
    final database = P2pDatabase.forTesting(NativeDatabase.memory());
    final coordinator = ScriptedCoordinator(
      network: network,
      robots: robotsOf(network),
      clock: () => _clockOf[database] ?? now,
      orderType: orderType,
      takerFee: takerFee,
    );
    final harness = TradeHarness._(network, database, coordinator, now);
    _clockOf[database] = now;
    harness._track();
    final fingerprint = switch (GarageKeyFingerprint.of(tradeKey)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    expect(
      await harness.bindings.recordGeneratedKey(network, fingerprint),
      isA<Ok>(),
    );
    return harness;
  }

  /// The app started again over the same database and coordinator, at the same time: nothing kept in memory.
  TradeHarness restart() {
    final again = TradeHarness._(network, database, coordinator, now);
    again._track();
    return again;
  }

  static final Map<P2pDatabase, DateTime> _clockOf = {};

  void _track() => _clockOf[database] = now;

  /// Moves the clock by [by], and fires the timers whose time has come, in order.
  Future<void> elapse(Duration by) async {
    now = now.add(by);
    _track();
    while (true) {
      final due = timers.where((t) => t.isActive && !t.due.isAfter(now));
      if (due.isEmpty) break;
      due.first.fire();
      await settle();
    }
    await settle();
  }

  /// Lets every pending future run: the database and the fake coordinator answer on the event queue.
  Future<void> settle() => pumpEventQueue(times: 200);

  /// The active timers.
  List<HarnessTimer> get activeTimers => [
    for (final timer in timers)
      if (timer.isActive) timer,
  ];

  /// The robots of [tradeKey] on [network] the coordinator may meet: its first usable ones.
  static List<RobotIdentity> robotsOf(RobosatsNetwork network) {
    final key = NetworkGarageKey(network, tradeKey);
    final found = <RobotIdentity>[];
    var from = 0;
    while (found.length < 6) {
      switch (key.firstUsableRobot(from)) {
        case Ok(:final value):
          found.add(value.identity);
          from = value.accountIndex + 1;
        case Err(:final failure):
          throw StateError('$failure');
      }
    }
    return found;
  }

  /// The robot of index [index] among [robotsOf].
  RobotIdentity robot(int index) => robotsOf(network)[index];

  /// The coordinator's order as its book lists it now.
  Future<PublicOrder> shownOrder() async {
    final book = await CoordinatorClient(
      coordinator,
      clock: () => now,
    ).fetchBook(coordinator.coordinator, network);
    return switch (book) {
      Ok(value: OrderBook(orders: [final order])) => order,
      final other => throw StateError('no order shown: $other'),
    };
  }

  /// Takes the order shown, and returns what the take gave.
  Future<Result<TakeOutcome, TakeRefusal>> takeShown({
    TakeAmount? amount,
  }) async =>
      take.execute(await shownOrder(), network: network, amount: amount);

  /// The record of a take that was sent.
  static TradeRecord recordOf(Result<TakeOutcome, TakeRefusal> taken) =>
      switch (taken) {
        Ok(:final value) => value.record,
        Err(:final failure) => throw StateError('refused: $failure'),
      };

  /// The active trades, as the database holds them.
  Future<List<TradeRecord>> activeRecords() async =>
      switch (await records.watchActiveTrades(network).first) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
      };

  /// Every record, closed ones included.
  Future<List<Map<String, Object?>>> allTrades() async => [
    for (final row
        in await database
            .customSelect('SELECT * FROM trades ORDER BY robot_index')
            .get())
      row.data,
  ];

  /// Listens to the watch of [record] and collects what it emits.
  WatchRun watchOf(
    TradeRecord record, {
    Stream<TradeWatchSignal> signals = const Stream.empty(),
    bool onScreen = true,
  }) {
    final run = WatchRun();
    run.subscription = watch
        .execute(record, signals: signals, onScreen: onScreen)
        .listen(run.states.add, onDone: () => run.done = true);
    return run;
  }
}

/// What a watch emitted.
final class WatchRun {
  final List<TradeWatchState> states = [];
  late final StreamSubscription<TradeWatchState> subscription;
  bool done = false;

  TradeWatchState get last => states.last;

  /// The status of the last state, when it is one.
  TradeWatchStatus get lastStatus => switch (states.last) {
    final TradeWatchStatus status => status,
    final other => throw StateError('not a status: $other'),
  };
}
