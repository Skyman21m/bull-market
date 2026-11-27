import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/tor_coordinator_transport.dart'
    show coordinatorRequestDeadline;
import 'package:p2p/src/data/robot_binding_repository_impl.dart';
import 'package:p2p/src/data/trade_record_repository_impl.dart';
import 'package:p2p/src/data/trade_payout_repository_impl.dart';
import 'package:p2p/src/data/trade_trail_repository_impl.dart';
import 'package:p2p/src/domain/garage_key_fingerprint.dart';
import 'package:p2p/src/domain/interim_trade_robots.dart';
import 'package:p2p/src/domain/network_garage_key.dart';
import 'package:p2p/src/domain/order_history.dart' show ClosedTrade;
import 'package:p2p/src/domain/p2p_failure.dart';
import 'package:p2p/src/domain/p2p_waits.dart';
import 'package:p2p/src/domain/repositories/garage_key_repository.dart';
import 'package:p2p/src/domain/repositories/trade_record_repository.dart';
import 'package:p2p/src/domain/repositories/trade_trail_repository.dart';
import 'package:p2p/src/domain/robot_binding.dart';
import 'package:p2p/src/domain/robot_request_limiter.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/make_price_check.dart';
import 'package:p2p/src/domain/trade/trade_make.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/put_robot_on_coordinator_usecase.dart';
import 'package:p2p/src/domain/usecases/read_robot_on_coordinator_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/cancel_trade_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/chat_step_action_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/list_active_trades_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/make_order_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/pause_order_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/pauses_in_flight.dart';
import 'package:p2p/src/domain/usecases/trade/submit_payout_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/trade_keyring.dart';
import 'package:p2p/src/domain/usecases/trade/trade_make_locks.dart';
import 'package:p2p/src/domain/usecases/trade/trade_read_order.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/src/domain/usecases/trade/trade_take_locks.dart';
import 'package:p2p/src/domain/usecases/trade/wallet_payout_destinations.dart';
import 'package:p2p/src/domain/usecases/trade/trade_watch_session.dart';
import 'package:p2p/src/domain/usecases/trade/watch_trade_usecase.dart';
import 'package:p2p/testing.dart' show ScriptedMakerCoordinator;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';
import 'garage_words.dart';

import 'trade_harness.dart'
    show
        AppKilled,
        HarnessKeys,
        HarnessTimer,
        NoteHooks,
        TradeHarness,
        WatchRun,
        otherTradeKey,
        tradeKey;

/// Where the make tests stop the app (#179): after each write of a make, and between its answer and its confirmation.
enum MakeKillAt {
  none,

  /// After the robot was reserved and bound, before its first contact.
  afterReservation,

  /// After the pending make, before its terms.
  afterPendingMake,

  /// After the terms, before the make's request.
  afterMakerTerms,

  /// After the answer and the read that shows this robot as the maker, before the make is confirmed.
  beforeConfirm,

  /// After the confirmation, before the first trail.
  beforeFirstTrail,
}

/// One run of the app over a database the runs share, for the make: the real repositories, robot layer, limiter, reader and use cases, the coordinator played by [ScriptedMakerCoordinator], a clock and timers the test moves.
final class MakeHarness {
  final RobosatsNetwork network;
  final P2pDatabase database;
  final ScriptedMakerCoordinator coordinator;
  final _Clock _clock;
  MakeKillAt kill = MakeKillAt.none;

  late final RobotBindingRepositoryImpl bindings;
  late final MakeRecords records;
  late final MakeTrails trails;
  late final InterimTradeRobots robots;
  late final RobotRequestLimiter limiter;

  /// Where each contract's payout came from (schema 9, #204), in this run's database.
  late final TradePayoutRepositoryImpl payouts;

  /// The invoices and addresses the wallet gave during this run, in memory: lost at a restart, as in the app.
  final WalletPayoutDestinations walletPayouts = WalletPayoutDestinations();

  late final TradeReader reader;
  late final MakeOrderUsecase make;

  /// The make use case of this run over another federation list than the app's ([federation]): a coordinator removed from the list since (#185, functional review R2).
  late final MakeOrderUsecase Function(Federation federation) makeOn;
  late final WatchTradeUsecase watch;
  late final CancelTradeUsecase cancel;
  late final ListActiveTradesUsecase list;

  /// The pause and « Unpause Order » of a public order made here (#184).
  late final PauseOrderUsecase pause;

  /// A maker buyer's payout and « fiat sent » (#182): the phase 2 use cases over this run's records.
  late final SubmitPayoutUsecase payout;
  late final ChatStepActionUsecase chat;

  /// The keyring of the trades, whose leases sign every request of a robot that changes a state (GHSA-22q8-9ghc-jg3h).
  late final TradeKeyring keyring;

  /// The key work of this run.
  final HarnessKeys keys = HarnessKeys();

  /// Every timer the watch started, in order.
  final List<HarnessTimer> timers = [];

  final TradeTakeLocks locks = TradeTakeLocks();

  /// The pauses running in this run (#184, functional review R1), their uncertainty on [elapsed] (#214).
  late final PausesInFlight pausesInFlight = PausesInFlight(
    elapsed: () => elapsed,
    requestDeadline: coordinatorRequestDeadline,
  );

  /// The time that only moves forward of this run: moved with the clock by [elapse], never by [setClockOnly] (a device's clock set forward or back).
  Duration elapsed = Duration.zero;
  final TradeMakeLocks makeLocks = TradeMakeLocks();
  final TradeWatchRegistry watchRegistry = TradeWatchRegistry();
  final _MakeVault _vault;
  final GarageKeyRepository Function(P2pDatabase database)? _garageOver;

  /// The recovery notes of this run (#81), when the test gave them: told of each confirmation, and awaited before each reservation, as the locator wires them.
  final NoteHooks? _notes;

  MakeHarness._(
    this.network,
    this.database,
    this.coordinator,
    this._clock, {
    GarageKeyRepository Function(P2pDatabase database)? garageOver,
    NoteHooks? notes,
  }) : _garageOver = garageOver,
       _notes = notes,
       _vault = _MakeVault(NetworkGarageKey(network, tradeKey)) {
    DateTime clock() => _clock.now;
    bindings = RobotBindingRepositoryImpl(database, clock: clock);
    final TradeRecordRepository stored = TradeRecordRepositoryImpl(
      database,
      clock: clock,
    );
    records = MakeRecords(stored, () => kill);
    payouts = TradePayoutRepositoryImpl(database);
    trails = MakeTrails(TradeTrailRepositoryImpl(database), () => kill);
    robots = InterimTradeRobots(
      garageOver?.call(database) ?? _vault,
      records,
      beforeNewTrade: notes?.beforeNewTrade,
    );
    limiter = RobotRequestLimiter(
      elapsed: () => _clock.now.difference(DateTime.utc(2026)),
      delay: (_) async {},
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
      requestOrder: TradeReadOrder(),
      payouts: payouts,
      confirmed: notes?.confirmed,
    );
    final fetch = FetchRobotUsecase(client, bindings, keys);
    final put = PutRobotOnCoordinatorUsecase(fetch, bindings, limiter);
    final readRobot = ReadRobotOnCoordinatorUsecase(
      fetch,
      bindings,
      limiter,
      Federation.robosats,
    );
    keyring = TradeKeyring(readRobot, keys);
    payout = SubmitPayoutUsecase(
      client,
      reader,
      limiter,
      keyring,
      locks,
      invoices,
      payouts: payouts,
      fromWallet: walletPayouts,
    );
    chat = ChatStepActionUsecase(client, reader, limiter, locks, keyring);
    makeOn = (federation) => MakeOrderUsecase(
      client,
      robots,
      put,
      readRobot,
      records,
      trails,
      reader,
      limiter,
      invoices,
      makeLocks,
      federation,
      keyring,
    );
    make = makeOn(Federation.robosats);
    watch = WatchTradeUsecase(
      reader,
      limiter,
      P2pWaits(
        start: (duration, callback) {
          final timer = HarnessTimer(
            _clock.now.add(duration),
            duration,
            callback,
          );
          timers.add(timer);
          return timer;
        },
        random: () => 0.5,
      ),
      watchRegistry,
    );
    cancel = CancelTradeUsecase(client, reader, limiter, locks, keyring);
    pause = PauseOrderUsecase(
      client,
      reader,
      limiter,
      locks,
      pausesInFlight,
      keyring,
    );
    list = ListActiveTradesUsecase(robots, trails, clock: clock);
  }

  /// A first run: a new database, the key recorded as drawn here, and [coordinator] answering the make.
  /// [key] is the key whose robots the coordinator knows, [tradeKey] unless given; with [garageOver], the robot layer takes its keys from the real Garage Keys it makes over the run's database (#81, review of #292, C-wiring).
  static Future<MakeHarness> start({
    RobosatsNetwork network = RobosatsNetwork.testnet,
    GarageKey? key,
    GarageKeyRepository Function(P2pDatabase database)? garageOver,
    NoteHooks? notes,
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final clock = _Clock(DateTime.utc(2026, 11, 14, 9));
    final database = P2pDatabase.forTesting(NativeDatabase.memory());
    final coordinator = ScriptedMakerCoordinator(
      network: network,
      robots: TradeHarness.robotsOf(network, key),
      clock: () => clock.now.add(clock.coordinatorSkew),
    );
    final harness = MakeHarness._(
      network,
      database,
      coordinator,
      clock,
      garageOver: garageOver,
      notes: notes,
    );
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
  MakeHarness restart() => MakeHarness._(
    network,
    database,
    coordinator,
    _clock,
    garageOver: _garageOver,
    notes: _notes,
  );

  DateTime get now => _clock.now;

  /// The coordinator's clock set [skew] from this device's (ahead when positive, behind when negative).
  void skewCoordinator(Duration skew) => _clock.coordinatorSkew = skew;

  /// The Garage Key deleted from the vault, as the Garage's delete does.
  void deleteKey() => _vault.key = null;

  /// The Garage Key of the tests back in the vault, after [deleteKey]: a vault that gave way for a while (#237).
  void restoreKey() => _vault.key = NetworkGarageKey(network, tradeKey);

  /// Another Garage Key in the vault in place of the one of the tests.
  void replaceKey() => _vault.key = NetworkGarageKey(network, otherTradeKey);

  /// The device's clock set forward (or back, [by] negative) at once, the time that only moves forward unchanged: no timer fires.
  void setClockOnly(Duration by) => _clock.now = _clock.now.add(by);

  /// Moves the clock by [by], and fires the timers whose time has come, in order.
  Future<void> elapse(Duration by) async {
    _clock.now = _clock.now.add(by);
    elapsed += by;
    while (true) {
      final due = timers.where((t) => t.isActive && !t.due.isAfter(_clock.now));
      if (due.isEmpty) break;
      due.first.fire();
      await settle();
    }
    await settle();
  }

  /// Lets every pending future run.
  Future<void> settle() => pumpEventQueue(times: 200);

  /// The robot of index [index] among `TradeHarness.robotsOf`.
  RobotIdentity robot(int index) => TradeHarness.robotsOf(network)[index];

  /// The coordinator of the make.
  Coordinator get host => coordinator.coordinator;

  /// The make of the tests' order: 100 EUR, a premium of 2 %, a bond of 3 %, three hours of escrow, a public duration of 23:59, Revolut Instant SEPA; buying unless [sell], with a description when given.
  static MakeOrderRequest request({
    bool sell = false,
    double amount = 100,
    String? description,
    double premium = 2,
    RobosatsCurrency? currency,
    (double, double)? range,
    Duration publicDuration = const Duration(seconds: 86340),
    Duration escrowDuration = const Duration(seconds: 10800),
    double bondSize = 3,
    String paymentMethod = 'Revolut Instant SEPA',
    OrderLocation? location,
    String? password,
  }) {
    T some<T>(T? value) => value ?? (throw StateError('missing'));
    final OrderAmount asked = switch (range) {
      (final min, final max) => some(
        RangeOrderAmount.tryCreate(
          some(FiatAmount.tryCreate(min)),
          some(FiatAmount.tryCreate(max)),
        ),
      ),
      null => FixedOrderAmount(some(FiatAmount.tryCreate(amount))),
    };
    return some(
      MakeOrderRequest.tryCreate(
        type: sell ? OrderType.sell : OrderType.buy,
        currency: currency ?? some(RobosatsCurrency.fromId(2)),
        amount: asked,
        paymentMethod: paymentMethod,
        premium: some(Premium.tryCreate(premium)),
        publicDuration: publicDuration,
        escrowDuration: escrowDuration,
        bondSize: some(BondSize.tryCreate(bondSize)),
        description: description,
        location: location,
        password: password == null ? null : OrderPasswordHash.of(password),
      ),
    );
  }

  /// Makes [request] (by default [MakeHarness.request]) on the coordinator, the price check seen at the press being [seen], by default none read at the coordinator's present price (#181).
  Future<Result<MakeOutcome, MakeRefusal>> makeOrder([
    MakeOrderRequest? request,
    MakePriceSeen? seen,
  ]) {
    final asked = request ?? MakeHarness.request();
    return make.execute(
      asked,
      coordinator: host,
      network: network,
      seen:
          seen ??
          MakePriceSeen.of(
            currency: asked.currency,
            coordinatorPrice: coordinator.prices[asked.currency.id] ?? 1,
          ),
    );
  }

  /// The pending makes, as the database holds them.
  Future<List<PendingMake>> pendingMakes() async =>
      switch (await records.watchPendingMakes(network).first) {
        Ok(:final value) => value,
        Err(:final failure) => throw StateError('$failure'),
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

  /// The stored trail of [record], if any.
  Future<TradeTrailRecord?> trailOf(TradeRecord record) async =>
      switch (await trails.historyOf(record)) {
        Ok(:final value) => value.trail,
        Err(:final failure) => throw StateError('$failure'),
      };

  /// Listens to the watch of [record] and collects what it emits.
  WatchRun watchOf(TradeRecord record, {bool onScreen = true}) {
    final run = WatchRun();
    run.subscription = watch
        .execute(record, signals: const Stream.empty(), onScreen: onScreen)
        .listen(run.states.add, onDone: () => run.done = true);
    return run;
  }
}

final class _Clock {
  DateTime now;

  /// How far the coordinator's clock is from this device's: ahead when positive.
  Duration coordinatorSkew = Duration.zero;

  _Clock(this.now);
}

final class _MakeVault with KeysFromRead implements GarageKeyRepository {
  /// The key the vault holds: `null` once deleted.
  NetworkGarageKey? key;

  _MakeVault(this.key);

  @override
  Future<Result<NetworkGarageKey, P2pFailure>> read(
    RobosatsNetwork network,
  ) async => switch (key) {
    final held? when held.network == network => Ok(held),
    _ => const Err(GarageKeyMissingFailure()),
  };

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

/// The trade records, stopping the app where the test says, or failing a write of a make.
final class MakeRecords implements TradeRecordRepository {
  final TradeRecordRepository _inner;
  final MakeKillAt Function() _kill;

  /// What the next [recordPendingMake], [confirmMake] or [closePendingMake] gives instead of writing, when set.
  P2pFailure? pendingFailure;
  P2pFailure? confirmFailure;
  P2pFailure? closeFailure;

  /// How many confirmations of a make were asked.
  int confirms = 0;

  /// When set, what [watchTrades] gives in place of each list stored: a database whose rows read otherwise.
  List<TradeRecord> Function(List<TradeRecord> stored)? trades;

  MakeRecords(this._inner, this._kill);

  @override
  Future<Result<NewTradeStanding, P2pFailure>> newTradeStandingOf(
    RobosatsNetwork network,
    GarageKeyFingerprint key,
  ) => _inner.newTradeStandingOf(network, key);

  @override
  Future<Result<Set<GarageKeyFingerprint>, P2pFailure>> keysInUse(
    RobosatsNetwork network,
  ) => _inner.keysInUse(network);

  @override
  Future<Result<TradeReservation?, P2pFailure>> reserveForNewTrade(
    RobotSlot robot,
    CoordinatorIdentity coordinator,
  ) async {
    final reserved = await _inner.reserveForNewTrade(robot, coordinator);
    if (_kill() == MakeKillAt.afterReservation) throw AppKilled();
    return reserved;
  }

  @override
  Future<Result<TradeRecord, P2pFailure>> recordPendingTake(
    TradeReservation reservation, {
    required int orderId,
    required TradeRole role,
  }) => _inner.recordPendingTake(reservation, orderId: orderId, role: role);

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
  Future<Result<PendingMake, P2pFailure>> recordPendingMake(
    TradeReservation reservation, {
    required TradeRole role,
  }) async {
    if (pendingFailure case final failure?) return Err(failure);
    final written = await _inner.recordPendingMake(reservation, role: role);
    if (_kill() == MakeKillAt.afterPendingMake) throw AppKilled();
    return written;
  }

  @override
  Future<Result<TradeRecord, P2pFailure>> confirmMake(
    PendingMake make, {
    required int orderId,
  }) async {
    confirms++;
    if (_kill() == MakeKillAt.beforeConfirm) throw AppKilled();
    if (confirmFailure case final failure?) return Err(failure);
    return _inner.confirmMake(make, orderId: orderId);
  }

  @override
  Future<Result<PendingMake, P2pFailure>> closePendingMake(
    PendingMake make,
  ) async {
    if (closeFailure case final failure?) return Err(failure);
    return _inner.closePendingMake(make);
  }

  @override
  Stream<Result<List<PendingMake>, P2pFailure>> watchPendingMakes(
    RobosatsNetwork network,
  ) => _inner.watchPendingMakes(network);

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

  @override
  Stream<Result<List<TradeRecord>, P2pFailure>> watchTrades(
    RobosatsNetwork network,
  ) => _inner
      .watchTrades(network)
      .map(
        (result) => switch ((result, trades)) {
          (Ok(:final value), final change?) => Ok(change(value)),
          _ => result,
        },
      );

  @override
  Stream<Result<List<ClosedTrade>, P2pFailure>> watchClosedTrades(
    RobosatsNetwork network,
  ) => _inner.watchClosedTrades(network);
}

/// The terms and trails, stopping the app, or failing a write, where the test says.
final class MakeTrails implements TradeTrailRepository {
  final TradeTrailRepository _inner;
  final MakeKillAt Function() _kill;

  /// What the next [recordMakerTerms] gives instead of writing, when set.
  P2pFailure? makerTermsFailure;

  /// What every [storeTrail] gives instead of writing, while set.
  P2pFailure? storeFailure;

  /// When set, what [makerTermsOf] gives instead of the record stored: a database that reads back otherwise than it wrote.
  MakerTermsRecord? Function(MakerTermsRecord? stored)? readBack;

  /// When set, what [watchMadeHistories] gives in place of each map stored: a database whose rows read otherwise.
  Map<RobotSlot, StoredMadeHistory> Function(
    Map<RobotSlot, StoredMadeHistory> stored,
  )?
  madeHistories;

  /// When set, what [historyOf] gives in place of the history stored: a database that reads back otherwise than it wrote (#187, a trail no trigger lets be written).
  StoredTradeHistory Function(StoredTradeHistory stored)? historyBack;

  /// How many trails were asked to be stored.
  int stores = 0;

  MakeTrails(this._inner, this._kill);

  @override
  Future<Result<void, P2pFailure>> recordTerms(
    TradeRecord trade,
    TradeTermsRecord terms,
  ) => _inner.recordTerms(trade, terms);

  @override
  Future<Result<void, P2pFailure>> recordMakerTerms(
    PendingMake make,
    MakerTermsRecord terms,
  ) async {
    if (makerTermsFailure case final failure?) return Err(failure);
    final written = await _inner.recordMakerTerms(make, terms);
    if (_kill() == MakeKillAt.afterMakerTerms) throw AppKilled();
    return written;
  }

  @override
  Future<Result<MakerTermsRecord?, P2pFailure>> makerTermsOf(
    RobotSlot robot,
  ) async {
    final stored = await _inner.makerTermsOf(robot);
    final change = readBack;
    if (change == null) return stored;
    return switch (stored) {
      Ok(:final value) => Ok(change(value)),
      Err() => stored,
    };
  }

  @override
  Future<Result<TrailStoreOutcome, P2pFailure>> storeTrail(
    TradeRecord trade,
    TradeTrailRecord trail,
  ) {
    stores++;
    if (_kill() == MakeKillAt.beforeFirstTrail) throw AppKilled();
    if (storeFailure case final failure?) return Future.value(Err(failure));
    return _inner.storeTrail(trade, trail);
  }

  @override
  Future<Result<StoredTradeHistory, P2pFailure>> historyOf(
    TradeRecord trade,
  ) async {
    final stored = await _inner.historyOf(trade);
    final change = historyBack;
    if (change == null) return stored;
    return switch (stored) {
      Ok(:final value) => Ok(change(value)),
      Err() => stored,
    };
  }

  @override
  Stream<Result<Map<RobotSlot, StoredTradeHistory>, P2pFailure>> watchHistories(
    RobosatsNetwork network,
  ) => _inner.watchHistories(network);

  @override
  Stream<Result<Map<RobotSlot, StoredMadeHistory>, P2pFailure>>
  watchMadeHistories(RobosatsNetwork network) => _inner
      .watchMadeHistories(network)
      .map(
        (result) => switch ((result, madeHistories)) {
          (Ok(:final value), final change?) => Ok(change(value)),
          _ => result,
        },
      );
}
