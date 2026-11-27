import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:p2p/src/data/garage_key_book_repository_impl.dart';
import 'package:p2p/src/data/p2p_database.dart';
import 'package:p2p/src/data/trade_chat_pin_repository_impl.dart';
import 'package:p2p/src/domain/repositories/trade_chat_pin_repository.dart';
import 'package:p2p/src/domain/trade/trade_chat_pin.dart';
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
import 'package:p2p/src/domain/robot_key_compute_port.dart';
import 'package:p2p/src/domain/robot_request_limiter.dart';
import 'package:p2p/src/domain/trade/bolt11.dart';
import 'package:p2p/src/domain/trade/trade_storable.dart';
import 'package:p2p/src/domain/trade/trade_take.dart';
import 'package:p2p/src/domain/trade/trade_watch.dart';
import 'package:p2p/src/domain/trade_record.dart';
import 'package:p2p/src/domain/usecases/fetch_robot_usecase.dart';
import 'package:p2p/src/domain/usecases/put_robot_on_coordinator_usecase.dart';
import 'package:p2p/src/domain/usecases/read_robot_on_coordinator_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/rate_host_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/cancel_trade_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/chat_step_action_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/hold_trade_key_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/list_active_trades_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/send_chat_message_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/submit_payout_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/take_order_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/export_chat_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/trade_chats.dart';
import 'package:p2p/src/domain/usecases/trade/trade_keyring.dart';
import 'package:p2p/src/domain/usecases/trade/trade_read_order.dart';
import 'package:p2p/src/domain/usecases/trade/trade_reader.dart';
import 'package:p2p/src/domain/usecases/trade/trade_take_locks.dart';
import 'package:p2p/src/domain/usecases/trade/wallet_payout_destinations.dart';
import 'package:p2p/src/domain/usecases/trade/trade_watch_session.dart';
import 'package:p2p/src/domain/usecases/trade/watch_chat_usecase.dart';
import 'package:p2p/src/domain/usecases/trade/watch_trade_usecase.dart';
import 'package:p2p/testing.dart' show ScriptedCoordinator;
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:test/test.dart';

import 'robot_coordinators.dart' show pairOf;
import 'garage_words.dart';

/// A Garage Key made for the trade tests only.
final GarageKey tradeKey = switch (GarageKey.fromBytes(
  Uint8List.fromList(List<int>.generate(32, (i) => 101 + i)),
)) {
  Ok(:final value) => value,
  Err(:final failure) => throw StateError('$failure'),
};

/// Another Garage Key made for the trade tests only, which a test puts in the vault in place of [tradeKey].
final GarageKey otherTradeKey = switch (GarageKey.fromBytes(
  Uint8List.fromList(List<int>.generate(32, (i) => 201 + i)),
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

/// The key work of the trade tests on the test's own isolate: the pairs made once for the run, the proofs the package's, and every unlock counted, failed or held back when the test says.
final class HarnessKeys implements RobotKeyComputePort {
  /// The robots whose key was unlocked, in order.
  final List<RobotHashId> unlocked = [];

  /// What the next unlocks give instead, when set: the work could not start.
  RobotKeyComputeFailure? unlockFailure;

  /// When set, each unlock waits for it before it is done: an unlock in flight, as long as the test wants.
  Future<void>? holdUnlock;

  /// What the next decryptions of the chat give instead, when set: the work could not run.
  RobotKeyComputeFailure? chatDecryptFailure;

  /// When set, each composition of a Nostr copy throws it: a bug in the work, or an error out of its isolate.
  Object? composeThrows;

  /// When set, each composition of a Nostr copy waits for it: a composition in flight, as long as the test wants.
  Future<void>? holdCompose;

  /// When set, the next unlocks throw it: a bug of the work, an `Error` no use case catches.
  Error? unlockError;

  /// What the next compositions of a coordinator's rating give instead, when set: the work could not start.
  RobotKeyComputeFailure? rateFailure;

  /// The ratings of a coordinator composed, in order.
  final List<OutgoingHostRating> rated = [];

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

  /// How many chat messages were decrypted, in how many works.
  int chatDecrypts = 0;

  @override
  Future<Result<OutgoingHostRating, RobotKeyComputeFailure>> composeHostRating(
    NostrKeyPair sender, {
    required HostReviewToken token,
    required Coordinator coordinator,
    required int orderId,
    required HostRating rating,
    required DateTime now,
  }) async {
    if (rateFailure case final failure?) return Err(failure);
    final composed = OutgoingHostRating.compose(
      sender,
      token: token,
      coordinator: coordinator,
      orderId: orderId,
      rating: rating,
      now: now,
      random: Random.secure(),
    );
    rated.add(composed);
    return Ok(composed);
  }

  @override
  Future<
    Result<
      Result<OutgoingNostrChatMessage, NostrChatFailure>,
      RobotKeyComputeFailure
    >
  >
  composeNostrChat(
    NostrKeyPair sender, {
    required CoordinatorOrder order,
    required Coordinator coordinator,
    required RobosatsNetwork network,
    required String text,
    required DateTime now,
  }) async {
    if (holdCompose case final gate?) await gate;
    return Ok(
      composeThrows != null
          ? throw composeThrows ?? StateError('unreachable')
          : OutgoingNostrChatMessage.composeFor(
              sender,
              order: order,
              coordinator: coordinator,
              network: network,
              text: text,
              now: now,
              random: Random.secure(),
            ),
    );
  }

  @override
  Future<
    Result<
      List<Result<DecryptedChatMessage, PgpFailure>>,
      RobotKeyComputeFailure
    >
  >
  decryptChat(
    UnlockedRobotPgpKey key,
    List<ChatDecryptJob> jobs, {
    required DateTime now,
  }) async {
    chatDecrypts++;
    if (chatDecryptFailure case final failure?) return Err(failure);
    return Ok([
      for (final job in jobs)
        key.decryptChatMessage(job.armored, sender: job.sender, now: now),
    ]);
  }

  @override
  Future<
    Result<Result<UnlockedRobotPgpKey, PgpFailure>, RobotKeyComputeFailure>
  >
  unlock(RobotPgpKey key, RobotIdentity identity) async {
    if (holdUnlock case final hold?) await hold;
    if (unlockError case final error?) throw error;
    if (unlockFailure case final failure?) return Err(failure);
    unlocked.add(identity.hashId);
    return Ok(key.unlock(identity));
  }
}

final class _Vault with KeysFromRead implements GarageKeyRepository {
  /// The key the vault holds: `null` once deleted.
  NetworkGarageKey? key;

  _Vault(this.key);

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
  Future<Result<Set<GarageKeyFingerprint>, P2pFailure>> keysInUse(
    RobosatsNetwork network,
  ) => _inner.keysInUse(network);

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
  Future<Result<PendingMake, P2pFailure>> recordPendingMake(
    TradeReservation reservation, {
    required TradeRole role,
  }) => _inner.recordPendingMake(reservation, role: role);

  @override
  Future<Result<TradeRecord, P2pFailure>> confirmMake(
    PendingMake make, {
    required int orderId,
  }) => _inner.confirmMake(make, orderId: orderId);

  @override
  Future<Result<PendingMake, P2pFailure>> closePendingMake(PendingMake make) =>
      _inner.closePendingMake(make);

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
  ) => _inner.watchTrades(network);

  @override
  Stream<Result<List<ClosedTrade>, P2pFailure>> watchClosedTrades(
    RobosatsNetwork network,
  ) => _inner.watchClosedTrades(network);
}

/// The terms and trails, stopping the app, or failing a write, where the test says.
final class TestTrails implements TradeTrailRepository {
  final TradeTrailRepository _inner;
  final KillAt Function() _kill;

  /// What the next [recordTerms] gives instead of writing, when set.
  P2pFailure? termsFailure;

  /// What [recordTerms] gives once it has written, when set: a write that reached the disk but answered a failure.
  P2pFailure? termsFailureAfterWrite;

  /// How many trails were asked to be stored.
  int stores = 0;

  /// What every [storeTrail] gives instead of writing, while set: the database refuses the write.
  P2pFailure? storeFailure;

  TestTrails(this._inner, this._kill);

  @override
  Future<Result<void, P2pFailure>> recordTerms(
    TradeRecord trade,
    TradeTermsRecord terms,
  ) async {
    if (termsFailure case final failure?) return Err(failure);
    final written = await _inner.recordTerms(trade, terms);
    if (_kill() == KillAt.afterTerms) throw AppKilled();
    if (termsFailureAfterWrite case final failure?) return Err(failure);
    return written;
  }

  @override
  Future<Result<TrailStoreOutcome, P2pFailure>> storeTrail(
    TradeRecord trade,
    TradeTrailRecord trail,
  ) {
    stores++;
    if (storeFailure case final failure?) return Future.value(Err(failure));
    if (stores == 2 && _kill() == KillAt.beforeTrailOfAnswer) {
      throw AppKilled();
    }
    return _inner.storeTrail(trade, trail);
  }

  @override
  Future<Result<void, P2pFailure>> recordMakerTerms(
    PendingMake make,
    MakerTermsRecord terms,
  ) => _inner.recordMakerTerms(make, terms);

  @override
  Future<Result<MakerTermsRecord?, P2pFailure>> makerTermsOf(RobotSlot robot) =>
      _inner.makerTermsOf(robot);

  @override
  Future<Result<StoredTradeHistory, P2pFailure>> historyOf(TradeRecord trade) =>
      _inner.historyOf(trade);

  @override
  Stream<Result<Map<RobotSlot, StoredTradeHistory>, P2pFailure>> watchHistories(
    RobosatsNetwork network,
  ) => _inner.watchHistories(network);

  @override
  Stream<Result<Map<RobotSlot, StoredMadeHistory>, P2pFailure>>
  watchMadeHistories(RobosatsNetwork network) =>
      _inner.watchMadeHistories(network);
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
/// The recovery notes a harness is wired to (#81), as the locator wires `RecoveryNoteSync`: told of each make and take confirmed, awaited before each reservation.
typedef NoteHooks = ({
  void Function(TradeRecord record) confirmed,
  Future<void> Function(NetworkGarageKey key) beforeNewTrade,
});

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

  /// When set, each wait of the limiter after a busy answer lasts until it completes.
  Future<void>? holdBusyWait;

  late final RobotBindingRepositoryImpl bindings;
  late final TradeRecordRepository records;
  late final TestTrails trails;
  late final InterimTradeRobots robots;
  late final RobotRequestLimiter limiter;

  /// Where each contract's payout came from (schema 9, #204), in this run's database.
  late final TradePayoutRepositoryImpl payouts;

  /// The invoices and addresses the wallet gave during this run, in memory: lost at a restart, as in the app.
  final WalletPayoutDestinations walletPayouts = WalletPayoutDestinations();

  late final TradeReader reader;
  late final TakeOrderUsecase take;
  late final WatchTradeUsecase watch;
  late final CancelTradeUsecase cancel;
  late final ChatStepActionUsecase chat;
  late final ListActiveTradesUsecase list;
  late final TradeKeyring keyring;
  late final HoldTradeKeyUsecase holdKey;
  late final SubmitPayoutUsecase payout;

  /// The chats of this run, in memory, and their use cases (#93).
  final TradeChats chats = TradeChats();
  late final WatchChatUsecase chatRead;
  late final SendChatMessageUsecase chatSend;
  late final ExportChatUsecase chatExport;

  /// « Rate your host » of this run (#95), publishing to [relays].
  late final RateHostUsecase rateHost;
  late final CoordinatorClient _client;

  /// The pins of the trades' chats, in this run's database (#139), whose reads and writes a test can refuse.
  late final TestPins pins;

  /// The chat's use cases of a new run of the app, the process killed and started again: a fresh [TradeChats], nothing of the chats kept, the same records, keys and coordinator.
  (WatchChatUsecase, SendChatMessageUsecase) chatAfterRestart() {
    final fresh = TradeChats();
    return (
      WatchChatUsecase(_client, reader, limiter, keyring, keys, fresh, pins),
      SendChatMessageUsecase(
        _client,
        reader,
        limiter,
        keyring,
        keys,
        fresh,
        relays,
        Federation.robosats,
        Random(7),
        pins,
      ),
    );
  }

  /// The Nostr relays of this run (#94): every publication of the chat, recorded.
  final RecordingRelays relays = RecordingRelays();

  /// The key work of this run: its unlocks are counted.
  final HarnessKeys keys = HarnessKeys();

  /// The actions of an order in turn, for this run.
  final TradeTakeLocks locks = TradeTakeLocks();

  /// The subscriptions reading each trade in this run.
  final TradeWatchRegistry watchRegistry = TradeWatchRegistry();

  final _Vault _vault;

  /// The Garage Key of this run: [tradeKey] unless the test gave another one, such as a key of the public test words (#81).
  final GarageKey key;

  /// The real Garage Keys of this run, when the test gave them (#81, review of #292, C-wiring): the robot layer then takes its keys from them, the internal and external Garage Keys distinct, in place of the one key of [_vault].
  final GarageKeyRepository Function(P2pDatabase database)? _garageOver;

  /// The recovery notes of this run (#81), when the test gave them: told of each confirmation, and awaited before each reservation, as the locator wires them.
  final NoteHooks? _notes;

  TradeHarness._(
    this.network,
    this.database,
    this.coordinator,
    this.now, {
    GarageKey? key,
    GarageKeyRepository Function(P2pDatabase database)? garageOver,
    NoteHooks? notes,
  }) : key = key ?? tradeKey,
       _garageOver = garageOver,
       _notes = notes,
       _vault = _Vault(NetworkGarageKey(network, key ?? tradeKey, index: 0)) {
    DateTime clock() => now;
    bindings = RobotBindingRepositoryImpl(database, clock: clock);
    final TradeRecordRepository stored = TradeRecordRepositoryImpl(
      database,
      clock: clock,
    );
    records = _KillingRecords(
      stored,
      () => kill,
    );
    payouts = TradePayoutRepositoryImpl(database);
    trails = TestTrails(TradeTrailRepositoryImpl(database), () => kill);
    robots = InterimTradeRobots(
      garageOver?.call(database) ?? _vault,
      records,
      beforeNewTrade: notes?.beforeNewTrade,
    );
    limiter = RobotRequestLimiter(
      elapsed: () => now.difference(DateTime.utc(2026)),
      delay: (wait) async {
        busyWaits.add(wait);
        if (holdBusyWait case final hold?) await hold;
      },
      random: () => 0.5,
    );
    final client = CoordinatorClient(coordinator, clock: clock);
    _client = client;
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
    take = TakeOrderUsecase(
      client,
      robots,
      put,
      records,
      trails,
      reader,
      limiter,
      invoices,
      locks,
    );
    keyring = TradeKeyring(
      ReadRobotOnCoordinatorUsecase(
        fetch,
        bindings,
        limiter,
        Federation.robosats,
      ),
      keys,
    );
    holdKey = HoldTradeKeyUsecase(keyring);
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
    pins = TestPins(TradeChatPinRepositoryImpl(database));
    chatRead = WatchChatUsecase(
      client,
      reader,
      limiter,
      keyring,
      keys,
      chats,
      pins,
    );
    chatExport = ExportChatUsecase(reader, keyring, chats);
    chatSend = SendChatMessageUsecase(
      client,
      reader,
      limiter,
      keyring,
      keys,
      chats,
      relays,
      Federation.robosats,
      Random(7),
      pins,
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
      watchRegistry,
    );
    cancel = CancelTradeUsecase(client, reader, limiter, locks);
    chat = ChatStepActionUsecase(client, reader, limiter, locks);
    rateHost = RateHostUsecase(
      client,
      reader,
      limiter,
      keys,
      relays,
      Federation.robosats,
      Random(7),
    );
    list = ListActiveTradesUsecase(robots, trails, clock: clock);
  }

  /// A first run: a new database, the key recorded as drawn here, and [coordinator] playing the order.
  static Future<TradeHarness> start({
    RobosatsNetwork network = RobosatsNetwork.testnet,
    int orderType = 1,
    double takerFee = 0.00175,
    int orderId = 42,
    bool range = false,
    String? password,
    String alias = 'temple',
    RobotIdentity? maker,
    GarageKey? key,
    bool activatedFromWords = false,
    GarageKeyRepository Function(P2pDatabase database)? garageOver,
    NoteHooks? notes,
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final now = DateTime.utc(2026, 11, 14, 9);
    final database = P2pDatabase.forTesting(NativeDatabase.memory());
    final coordinator = ScriptedCoordinator(
      network: network,
      robots: robotsOf(network, key ?? tradeKey),
      clock: () => _clockOf[database] ?? now,
      orderType: orderType,
      takerFee: takerFee,
      orderId: orderId,
      range: range,
      password: password,
      alias: alias,
      maker: maker,
    );
    final harness = TradeHarness._(
      network,
      database,
      coordinator,
      now,
      key: key,
      garageOver: garageOver,
      notes: notes,
    );
    _clockOf[database] = now;
    harness._track();
    final fingerprint = switch (GarageKeyFingerprint.of(harness.key)) {
      Ok(:final value) => value,
      Err(:final failure) => throw StateError('$failure'),
    };
    // A key of the words is recorded as drawn here by its activation, as the repository activates key 0 at the first opening (#81); otherwise as a key drawn here before #81.
    expect(
      activatedFromWords
          ? await GarageKeyBookRepositoryImpl(
              database,
              clock: () => now,
            ).activate(network, 0, fingerprint)
          : await harness.bindings.recordGeneratedKey(network, fingerprint),
      isA<Ok>(),
    );
    return harness;
  }

  /// The app started again over the same database and coordinator, at the same time: nothing kept in memory.
  TradeHarness restart() {
    final again = TradeHarness._(
      network,
      database,
      coordinator,
      now,
      key: key,
      garageOver: _garageOver,
      notes: _notes,
    );
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
  static List<RobotIdentity> robotsOf(
    RobosatsNetwork network, [
    GarageKey? garageKey,
  ]) {
    final key = NetworkGarageKey(network, garageKey ?? tradeKey);
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

  /// The Garage Key deleted from the vault, as the Garage's delete does.
  void deleteKey() => _vault.key = null;

  /// Another Garage Key in the vault in place of [tradeKey], as after a delete and a new key.
  void replaceKey() => _vault.key = NetworkGarageKey(network, otherTradeKey);

  /// The robot of index [index] among [robotsOf].
  RobotIdentity robot(int index) => robotsOf(network, key)[index];

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
    OrderPassword? password,
  }) async => take.execute(
    await shownOrder(),
    network: network,
    amount: amount,
    password: password,
  );

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

/// The pins of the trades' chats over the real repository, whose reads or writes a test refuses while [refuseReads] or [refuseWrites] is set (#139).
final class TestPins implements TradeChatPinRepository {
  final TradeChatPinRepository _pins;
  bool refuseReads = false;
  bool refuseWrites = false;

  /// Refuses the reads or the writes of the Nostr pins only (part of #159).
  bool refuseNostrReads = false;
  bool refuseNostrWrites = false;

  /// How many pins were asked to be kept.
  int keeps = 0;

  /// How many Nostr pins were asked to be kept.
  int nostrKeeps = 0;

  /// Runs before each pin is kept, when set: another write meanwhile.
  Future<void> Function()? beforeKeep;

  TestPins(this._pins);

  @override
  Future<Result<PgpPublicKey?, P2pFailure>> pinOf(TradeRecord trade) =>
      refuseReads
      ? Future.value(const Err(P2pStorageFailure()))
      : _pins.pinOf(trade);

  @override
  Future<Result<PgpPublicKey, P2pFailure>> keep(
    TradeRecord trade,
    PgpPublicKey key,
  ) async {
    keeps++;
    await beforeKeep?.call();
    if (refuseWrites) return const Err(P2pStorageFailure());
    return _pins.keep(trade, key);
  }

  @override
  Future<Result<ChatNostrPin?, P2pFailure>> nostrPinOf(TradeRecord trade) =>
      refuseNostrReads
      ? Future.value(const Err(P2pStorageFailure()))
      : _pins.nostrPinOf(trade);

  @override
  Future<Result<bool, P2pFailure>> keepNostr(
    TradeRecord trade,
    ChatNostrPin pin,
  ) async {
    nostrKeeps++;
    if (refuseNostrWrites) return const Err(P2pStorageFailure());
    return _pins.keepNostr(trade, pin);
  }
}

/// The Nostr relays of a run (#94): records each publication and answers [answer], or holds it until [hold] completes.
final class RecordingRelays implements NostrRelayTransport {
  /// Every publication, in order: the relay, the events and the robot.
  final List<
    ({Uri relay, NostrRelayPublication message, RobotSessionKey robot})
  >
  published = [];

  NostrRelayOutcome answer = const NostrRelayAccepted();

  /// When set, what each relay answers, in place of [answer]: relays that answer differently.
  NostrRelayOutcome Function(Uri relay)? answerFor;

  /// When set, each publication waits for it before answering: one that never completes is a relay that never answers.
  Future<void>? hold;

  /// When set, each publication throws it once it has waited: an adapter that breaks its contract.
  Object? thrown;

  @override
  Future<NostrRelayOutcome> publish(
    Uri relay,
    NostrRelayPublication message, {
    required RobotSessionKey robot,
  }) async {
    published.add((relay: relay, message: message, robot: robot));
    if (hold case final gate?) await gate;
    if (thrown case final error?) throw error;
    return answerFor?.call(relay) ?? answer;
  }

  /// The distinct chat messages published, in order.
  List<OutgoingNostrChatMessage> get messages {
    final distinct = <OutgoingNostrChatMessage>[];
    for (final p in published) {
      if (p.message case final OutgoingNostrChatMessage message
          when !distinct.any((m) => identical(m, message))) {
        distinct.add(message);
      }
    }
    return distinct;
  }

  /// The distinct ratings of a coordinator published, in order.
  List<OutgoingHostRating> get hostRatings {
    final distinct = <OutgoingHostRating>[];
    for (final p in published) {
      if (p.message case final OutgoingHostRating rating
          when !distinct.any((r) => identical(r, rating))) {
        distinct.add(rating);
      }
    }
    return distinct;
  }
}
