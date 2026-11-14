import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;

import 'package:bull_tor/tor.dart';
import 'package:get_it/get_it.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeys;

import '../public/p2p_wallet_port.dart';
import 'data/garage_key_repository_impl.dart';
import 'data/isolate_robot_key_compute.dart';
import 'data/p2p_database.dart';
import 'data/robot_binding_repository_impl.dart';
import 'data/tor_coordinator_transport.dart';
import 'data/trade_record_repository_impl.dart';
import 'data/trade_trail_repository_impl.dart';
import 'domain/book_requests_in_flight.dart';
import 'domain/coordinator_sessions_port.dart';
import 'domain/p2p_clock.dart';
import 'domain/p2p_shuffle.dart';
import 'domain/p2p_waits.dart';
import 'domain/repositories/garage_key_repository.dart';
import 'domain/interim_trade_robots.dart';
import 'domain/repositories/robot_binding_repository.dart';
import 'domain/repositories/trade_record_repository.dart';
import 'domain/repositories/trade_trail_repository.dart';
import 'domain/network_garage_key.dart';
import 'domain/robot_key_compute_port.dart';
import 'domain/robot_request_limiter.dart';
import 'domain/trade/bolt11.dart';
import 'domain/trade_robots.dart';
import 'domain/usecases/acknowledge_garage_key_history_usecase.dart';
import 'domain/usecases/close_coordinator_sessions_usecase.dart';
import 'domain/usecases/close_robot_sessions_usecase.dart';
import 'domain/usecases/delete_garage_key_usecase.dart';
import 'domain/usecases/derive_first_robot_usecase.dart';
import 'domain/usecases/fetch_coordinator_info_usecase.dart';
import 'domain/usecases/fetch_robot_usecase.dart';
import 'domain/usecases/generate_garage_key_usecase.dart';
import 'domain/usecases/has_garage_key_usecase.dart';
import 'domain/usecases/import_garage_key_usecase.dart';
import 'domain/usecases/list_robot_hosts_usecase.dart';
import 'domain/usecases/load_federation_books_usecase.dart';
import 'domain/usecases/needs_pin_to_delete_garage_key_usecase.dart';
import 'domain/usecases/put_robot_on_coordinator_usecase.dart';
import 'domain/usecases/read_garage_key_usecase.dart';
import 'domain/usecases/read_robot_on_coordinator_usecase.dart';
import 'domain/usecases/read_robot_standing_usecase.dart';
import 'domain/usecases/release_robot_usecase.dart';
import 'domain/usecases/request_federation_books_usecase.dart';
import 'domain/usecases/retry_p2p_tor_usecase.dart';
import 'domain/usecases/start_p2p_tor_usecase.dart';
import 'domain/usecases/trade/cancel_trade_usecase.dart';
import 'domain/usecases/trade/list_active_trades_usecase.dart';
import 'domain/usecases/trade/take_order_usecase.dart';
import 'domain/usecases/trade/trade_reader.dart';
import 'domain/usecases/trade/trade_take_locks.dart';
import 'domain/usecases/trade/trade_watch_session.dart';
import 'domain/usecases/trade/watch_trade_usecase.dart';
import 'domain/usecases/watch_p2p_tor_state_usecase.dart';
import 'presentation/book_cubit.dart';
import 'presentation/coordinator_details_cubit.dart';
import 'presentation/garage_cubit.dart';
import 'presentation/order_details_cubit.dart';
import 'presentation/robot_coordinator_cubit.dart';
import 'ui/widgets/garage_key_clipboard.dart';

/// Registers the internals of the feature: one Tor transport, shared by every request to the coordinators, the use-cases and the cubits of the screens.
final class P2pLocator {
  /// [garageKeys] is the vault's handle on the Garage Keys and [databaseDirectory] gives the directory of the feature's database: without them, nothing that reads or writes a Garage Key, a binding or the database is registered.
  /// [wallet] gives the wallet's port: without it, no port is registered.
  /// [bolt11Decoder] gives the shell's BOLT11 decoder, which the trade's checks read every invoice with: without it, the trade use cases decode no invoice, so that none is ever shown or paid.
  static void setup(
    GetIt locator, {
    required GarageKeys? garageKeys,
    required Future<Directory> Function()? databaseDirectory,
    required P2pWalletPort Function()? wallet,
    Bolt11Decoder Function()? bolt11Decoder,
  }) {
    // `Tor` and its HTTP client factory are read lazily, so this runs whether or not the Tor package is registered yet.
    locator.registerLazySingleton<TorCoordinatorTransport>(
      () => TorCoordinatorTransport(
        () => locator<Tor>(),
        locator<TorHttpClientFactory>(),
      ),
      dispose: (transport) => transport.closeSessions(),
    );
    registerOver(
      locator,
      transport: () => locator<TorCoordinatorTransport>(),
      sessions: () => locator<TorCoordinatorTransport>(),
      tor: () => locator<Tor>(),
      clock: DateTime.now,
      // The book's waits before it asks a coordinator again: real timers, spread by a random draw that nothing secret depends on.
      waits: P2pWaits(start: Timer.new, random: Random().nextDouble),
    );
    if (garageKeys != null && databaseDirectory != null) {
      registerGarageKeys(
        locator,
        garageKeys,
        database: () => P2pDatabase.open(databaseDirectory),
        transport: () => locator<TorCoordinatorTransport>(),
        clock: DateTime.now,
      );
    }
    if (bolt11Decoder != null) {
      locator.registerLazySingleton<Bolt11Decoder>(bolt11Decoder);
    }
    if (wallet != null) {
      // Only the trade use cases may read it: `wallet_port_architecture_test.dart`.
      locator.registerLazySingleton<P2pWalletPort>(wallet);
    }
  }

  /// Registers the Garage Key of each network, kept by the vault behind [garageKeys], the use-cases that create, import, read and delete it, the Garage that shows it, and the bindings of its robots in the database [database] makes, with the request of a robot that checks them over [transport].
  ///
  /// Registering touches no key and no file: the keystore and the database are read or written only when a use-case runs, and the Garage runs them only once the user opens it.
  static void registerGarageKeys(
    GetIt locator,
    GarageKeys garageKeys, {
    required P2pDatabase Function() database,
    required CoordinatorTransport Function() transport,
    required DateTime Function() clock,
  }) {
    locator.registerLazySingleton<GarageKeyRepository>(
      () => GarageKeyRepositoryImpl(garageKeys),
    );
    locator.registerLazySingleton<P2pDatabase>(
      database,
      dispose: (database) => database.close(),
    );
    locator.registerLazySingleton<RobotBindingRepository>(
      () => RobotBindingRepositoryImpl(locator(), clock: clock),
    );
    // The hashing of a robot's key pair, away from the UI isolate.
    locator.registerLazySingleton<RobotKeyComputePort>(
      () => const IsolateRobotKeyCompute(),
    );
    // The request of a robot: its only callers are the two robot use cases below, and nothing outside the feature reaches it.
    locator.registerFactory<FetchRobotUsecase>(
      () => FetchRobotUsecase(
        CoordinatorClient(transport(), clock: clock),
        locator(),
        locator(),
      ),
    );
    // The places, retries and memory of the robot requests to each coordinator: one for the whole feature, in memory, for the run of the app, its busy window on a time that only moves forward.
    locator.registerLazySingleton<RobotRequestLimiter>(() {
      final running = Stopwatch()..start();
      return RobotRequestLimiter(
        elapsed: () => running.elapsed,
        delay: Future<void>.delayed,
        random: Random().nextDouble,
      );
    });
    // A robot put on a coordinator, read back from it, and let go: their only caller is the Garage's robot panel, and nothing outside the feature reaches them.
    locator.registerFactory<PutRobotOnCoordinatorUsecase>(
      () => PutRobotOnCoordinatorUsecase(locator(), locator(), locator()),
    );
    locator.registerFactory<ReadRobotOnCoordinatorUsecase>(
      () => ReadRobotOnCoordinatorUsecase(
        locator(),
        locator(),
        locator(),
        Federation.robosats,
      ),
    );
    locator.registerFactory<ReleaseRobotUsecase>(
      () => ReleaseRobotUsecase(locator(), locator()),
    );
    // The coordinators « Select Host » lists, and the one a binding names: the federation list and the refusal caps of the limiter, nothing sent.
    locator.registerFactory<ListRobotHostsUsecase>(
      () => ListRobotHostsUsecase(Federation.robosats, locator()),
    );
    locator.registerFactory<HasGarageKeyUsecase>(
      () => HasGarageKeyUsecase(locator()),
    );
    locator.registerFactory<GenerateGarageKeyUsecase>(
      () => GenerateGarageKeyUsecase(locator(), locator()),
    );
    locator.registerFactory<ImportGarageKeyUsecase>(
      () => ImportGarageKeyUsecase(locator(), locator()),
    );
    locator.registerFactory<ReadGarageKeyUsecase>(
      () => ReadGarageKeyUsecase(locator()),
    );
    locator.registerFactory<DeriveFirstRobotUsecase>(
      () => DeriveFirstRobotUsecase(locator()),
    );
    locator.registerFactory<DeleteGarageKeyUsecase>(
      () => DeleteGarageKeyUsecase(locator()),
    );
    locator.registerFactory<NeedsPinToDeleteGarageKeyUsecase>(
      () => NeedsPinToDeleteGarageKeyUsecase(locator()),
    );
    // The local reads and records of the Garage's robot panel: nothing outside the feature reaches them.
    locator.registerFactory<ReadRobotStandingUsecase>(
      () => ReadRobotStandingUsecase(locator()),
    );
    locator.registerFactory<AcknowledgeGarageKeyHistoryUsecase>(
      () => AcknowledgeGarageKeyHistoryUsecase(locator()),
    );
    // The Garage of a network, created when the user opens it.
    // The keys drawn and not acknowledged yet, in memory, for the whole run of the app.
    locator.registerLazySingleton<UnacknowledgedGarageKeys>(
      UnacknowledgedGarageKeys.new,
    );
    locator.registerFactoryParam<GarageCubit, RobosatsNetwork, void>(
      (network, _) => GarageCubit(
        network,
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
      ),
    );
    // The panel of one robot of the Garage, made from the Garage Key of the Garage and the robot's index: the only caller of the robot use cases and of the acknowledgement of a key's history.
    locator.registerFactoryParam<RobotCoordinatorCubit, NetworkGarageKey, int>(
      (key, index) => RobotCoordinatorCubit(
        key,
        index,
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
      ),
    );
    // One for the feature, so that a copied key is cleared even after the screen that copied it is gone.
    locator.registerLazySingleton<GarageKeyClipboard>(
      GarageKeyClipboard.new,
      dispose: (clipboard) => clipboard.dispose(),
    );
    registerTrades(locator, transport: transport, clock: clock);
  }

  /// Registers the trades (#87): their records, terms and trails in the database, the robot layer that reserves a fresh robot for each take, and the trade use cases, the only callers of the coordinator's money members; the trade screens (#88) are their only callers.
  ///
  /// The invoices of a trade are decoded by the [Bolt11Decoder] the shell registered ([setup]); without one, every invoice is refused, so that none is shown or paid.
  static void registerTrades(
    GetIt locator, {
    required CoordinatorTransport Function() transport,
    required DateTime Function() clock,
  }) {
    locator.registerLazySingleton<TradeRecordRepository>(
      () => TradeRecordRepositoryImpl(locator(), clock: clock),
    );
    locator.registerLazySingleton<TradeTrailRepository>(
      () => TradeTrailRepositoryImpl(locator()),
    );
    locator.registerLazySingleton<TradeRobots>(
      () => InterimTradeRobots(locator(), locator()),
    );
    Bolt11Reader invoices() => Bolt11Reader(
      locator.isRegistered<Bolt11Decoder>()
          ? locator<Bolt11Decoder>()
          : const _NoBolt11Decoder(),
    );
    locator.registerFactory<TradeReader>(
      () => TradeReader(
        locator(),
        locator(),
        locator(),
        locator(),
        CoordinatorClient(transport(), clock: clock),
        Federation.robosats,
        invoices(),
        clock: clock,
      ),
    );
    // One for the feature: the takes of an order run one at a time, whichever use case object runs them.
    locator.registerLazySingleton<TradeTakeLocks>(TradeTakeLocks.new);
    locator.registerFactory<TakeOrderUsecase>(
      () => TakeOrderUsecase(
        CoordinatorClient(transport(), clock: clock),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        invoices(),
        locator(),
      ),
    );
    // One for the feature: one subscription per trade, whichever use case object makes it.
    locator.registerLazySingleton<TradeWatchRegistry>(TradeWatchRegistry.new);
    locator.registerFactory<WatchTradeUsecase>(
      () => WatchTradeUsecase(locator(), locator(), locator(), locator()),
    );
    locator.registerFactory<CancelTradeUsecase>(
      () => CancelTradeUsecase(
        CoordinatorClient(transport(), clock: clock),
        locator(),
        locator(),
      ),
    );
    locator.registerFactory<ListActiveTradesUsecase>(
      () => ListActiveTradesUsecase(locator(), locator(), clock: clock),
    );
  }

  /// Registers the use-cases and the cubits over [transport], [tor], [clock], [waits] and [shuffle], which tests replace.
  static void registerOver(
    GetIt locator, {
    required CoordinatorTransport Function() transport,
    required CoordinatorSessionsPort Function() sessions,
    required Tor Function() tor,
    required DateTime Function() clock,
    required P2pWaits waits,
    P2pShuffle shuffle = P2pShuffle.random,
  }) {
    locator.registerSingleton<P2pClock>(P2pClock(clock));
    locator.registerSingleton<P2pShuffle>(shuffle);
    locator.registerSingleton<P2pWaits>(waits);
    locator.registerFactory<RequestFederationBooksUsecase>(
      () => RequestFederationBooksUsecase(
        FederationBookReader(transport(), clock: clock),
        Federation.robosats,
      ),
    );
    // One for the feature: every book, of every visit to the tab, joins the book requests already in flight.
    locator.registerLazySingleton<BookRequestsInFlight>(
      BookRequestsInFlight.new,
    );
    // A factory: each book gets its own, which remembers the coordinators it reached.
    locator.registerFactory<LoadFederationBooksUsecase>(
      () => LoadFederationBooksUsecase(locator(), locator(), locator()),
    );
    locator.registerFactory<FetchCoordinatorInfoUsecase>(
      () => FetchCoordinatorInfoUsecase(
        CoordinatorClient(transport(), clock: clock),
      ),
    );
    // Its only caller is `ReleaseRobotUsecase`, registered with the Garage, and nothing outside the feature reaches it.
    locator.registerFactory<CloseRobotSessionsUsecase>(
      () => CloseRobotSessionsUsecase(sessions()),
    );
    locator.registerFactory<WatchP2pTorStateUsecase>(
      () => WatchP2pTorStateUsecase(tor),
    );
    locator.registerFactory<StartP2pTorUsecase>(() => StartP2pTorUsecase(tor));
    locator.registerFactory<RetryP2pTorUsecase>(() => RetryP2pTorUsecase(tor));
    locator.registerFactory<CloseCoordinatorSessionsUsecase>(
      () => CloseCoordinatorSessionsUsecase(sessions()),
    );
    locator.registerFactoryParam<BookCubit, RobosatsNetwork, void>(
      (network, _) =>
          BookCubit(network, locator(), locator(), locator(), locator()),
    );
    locator
        .registerFactoryParam<OrderDetailsCubit, PublicOrder, RobosatsNetwork>(
          (order, network) => OrderDetailsCubit(order, network, locator()),
        );
    locator.registerFactoryParam<
      CoordinatorDetailsCubit,
      CoordinatorDetailsRequest,
      void
    >(
      (request, _) => CoordinatorDetailsCubit(request, locator(), now: clock()),
    );
  }
}

/// The decoder of a composition that lent none: every invoice is refused, so that the trade's checks never show or pay one.
final class _NoBolt11Decoder implements Bolt11Decoder {
  const _NoBolt11Decoder();

  @override
  Result<Bolt11Invoice, Bolt11Refusal> decode(String invoice) =>
      const Err(Bolt11Malformed());
}
