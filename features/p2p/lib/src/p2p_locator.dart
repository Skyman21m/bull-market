import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;

import 'package:bull_tor/tor.dart';
import 'package:get_it/get_it.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';
import 'package:secrets/secrets.dart' show GarageKeys;

import '../public/p2p_garage_key_port.dart';
import '../public/p2p_wallet_port.dart';
import 'data/garage_key_book_repository_impl.dart';
import 'data/garage_key_repository_impl.dart';
import 'data/isolate_robot_key_compute.dart';
import 'data/osm_map_tile_adapter.dart';
import 'data/p2p_database.dart';
import 'data/robot_binding_repository_impl.dart';
import 'data/tor_coordinator_transport.dart';
import 'data/trade_chat_pin_repository_impl.dart';
import 'data/trade_payment_repository_impl.dart';
import 'data/trade_payout_repository_impl.dart';
import 'data/trade_record_repository_impl.dart';
import 'data/trade_trail_repository_impl.dart';
import 'domain/book_requests_in_flight.dart';
import 'domain/coordinator_lottery.dart';
import 'domain/coordinator_sessions_port.dart';
import 'domain/garage_opening.dart';
import 'domain/meeting_point.dart';
import 'domain/map_tiles.dart';
import 'domain/p2p_clock.dart';
import 'domain/p2p_shuffle.dart';
import 'domain/p2p_waits.dart';
import 'domain/repositories/garage_key_repository.dart';
import 'domain/interim_trade_robots.dart';
import 'domain/repositories/robot_binding_repository.dart';
import 'domain/repositories/trade_chat_pin_repository.dart';
import 'domain/repositories/trade_payment_repository.dart';
import 'domain/repositories/trade_payout_repository.dart';
import 'domain/repositories/trade_record_repository.dart';
import 'domain/repositories/trade_trail_repository.dart';
import 'domain/network_garage_key.dart';
import 'domain/robot_key_compute_port.dart';
import 'domain/robot_request_limiter.dart';
import 'domain/trade/bolt11.dart';
import 'domain/trade/trade_status.dart';
import 'domain/trade/trade_take.dart';
import 'domain/trade_record.dart';
import 'domain/trade_robots.dart';
import 'domain/usecases/acknowledge_garage_key_history_usecase.dart';
import 'domain/usecases/close_coordinator_sessions_usecase.dart';
import 'domain/usecases/close_robot_sessions_usecase.dart';
import 'domain/usecases/delete_garage_key_usecase.dart';
import 'domain/usecases/derive_first_robot_usecase.dart';
import 'domain/usecases/fetch_coordinator_info_usecase.dart';
import 'domain/usecases/fetch_coordinator_limits_usecase.dart';
import 'domain/usecases/fetch_robot_usecase.dart';
import 'domain/usecases/find_public_order_usecase.dart';
import 'domain/usecases/has_garage_key_usecase.dart';
import 'domain/usecases/import_garage_key_usecase.dart';
import 'domain/usecases/list_robot_hosts_usecase.dart';
import 'domain/usecases/load_federation_books_usecase.dart';
import 'domain/usecases/needs_pin_to_delete_garage_key_usecase.dart';
import 'domain/usecases/new_garage_key_usecase.dart';
import 'domain/usecases/open_map_tiles_usecase.dart';
import 'domain/usecases/put_robot_on_coordinator_usecase.dart';
import 'domain/usecases/read_garage_key_usecase.dart';
import 'domain/usecases/read_robot_on_coordinator_usecase.dart';
import 'domain/usecases/read_robot_standing_usecase.dart';
import 'domain/usecases/release_robot_usecase.dart';
import 'domain/usecases/request_federation_books_usecase.dart';
import 'domain/usecases/retry_p2p_tor_usecase.dart';
import 'domain/usecases/start_p2p_tor_usecase.dart';
import 'domain/usecases/trade/bond_payments_in_flight.dart';
import 'domain/usecases/trade/cancel_trade_usecase.dart';
import 'domain/usecases/trade/chat_step_action_usecase.dart';
import 'domain/usecases/trade/check_make_price_usecase.dart';
import 'domain/usecases/trade/check_payout_rate_usecase.dart';
import 'domain/usecases/trade/follow_trades_usecase.dart';
import 'domain/usecases/trade/garage_robot_usecase.dart';
import 'domain/usecases/trade/hold_trade_key_usecase.dart';
import 'domain/usecases/trade/list_active_trades_usecase.dart';
import 'domain/usecases/trade/list_last_orders_usecase.dart';
import 'domain/usecases/trade/list_order_history_usecase.dart';
import 'domain/usecases/trade/make_order_usecase.dart';
import 'domain/usecases/trade/pause_order_usecase.dart';
import 'domain/usecases/trade/pauses_in_flight.dart';
import 'domain/usecases/trade/pay_bond_from_wallet_usecase.dart';
import 'domain/usecases/trade/payout_from_wallet_usecase.dart';
import 'domain/usecases/trade/prepared_takes.dart';
import 'domain/usecases/trade/rate_host_usecase.dart';
import 'domain/usecases/trade/export_chat_usecase.dart';
import 'domain/usecases/trade/send_chat_message_usecase.dart';
import 'domain/usecases/trade/submit_payout_usecase.dart';
import 'domain/usecases/trade/take_order_usecase.dart';
import 'domain/usecases/trade/trade_chats.dart';
import 'domain/usecases/trade/trade_keyring.dart';
import 'domain/usecases/trade/trade_read_order.dart';
import 'domain/usecases/trade/trade_reader.dart';
import 'domain/usecases/trade/trade_make_locks.dart';
import 'domain/usecases/trade/trade_take_locks.dart';
import 'domain/usecases/trade/wallet_payout_destinations.dart';
import 'domain/usecases/trade/trade_watch_session.dart';
import 'domain/usecases/trade/watch_chat_usecase.dart';
import 'domain/usecases/trade/watch_trade_usecase.dart';
import 'domain/usecases/watch_p2p_tor_state_usecase.dart';
import 'presentation/active_trades_cubit.dart';
import 'presentation/last_orders_cubit.dart';
import 'presentation/order_history_cubit.dart';
import 'presentation/bond_payment_cubit.dart';
import 'presentation/book_cubit.dart';
import 'presentation/chat_cubit.dart';
import 'presentation/host_rating_cubit.dart';
import 'presentation/coordinator_details_cubit.dart';
import 'presentation/garage_cubit.dart';
import 'presentation/make_order_cubit.dart';
import 'presentation/order_details_cubit.dart';
import 'presentation/payout_cubit.dart';
import 'presentation/payout_rate_cubit.dart';
import 'presentation/payout_wallet_cubit.dart';
import 'presentation/pending_makes_cubit.dart';
import 'presentation/unlisted_order_cubit.dart';
import 'presentation/renewals_cubit.dart';
import 'presentation/robot_coordinator_cubit.dart';
import 'presentation/take_order_cubit.dart';
import 'presentation/trade_cubit.dart';
import 'presentation/trade_order_page_cubit.dart';
import 'ui/widgets/garage_key_clipboard.dart';

/// Registers the internals of the feature: one Tor transport, shared by every request to the coordinators, the use-cases and the cubits of the screens.
final class P2pLocator {
  /// [garageKeys] is the vault's handle on the Garage Keys, [derivedGarageKeys] the shell's port of the keys of the words (#81) and [databaseDirectory] gives the directory of the feature's database: without them, nothing that reads or writes a Garage Key, a binding or the database is registered.
  /// [wallet] gives the wallet's port: without it, no port is registered.
  /// [bolt11Decoder] gives the shell's BOLT11 decoder, which the trade's checks read every invoice with: without it, the trade use cases decode no invoice, so that none is ever shown or paid.
  static void setup(
    GetIt locator, {
    required GarageKeys? garageKeys,
    required P2pGarageKeyPort? derivedGarageKeys,
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
      // The draws of the reference's lottery of the create form's default coordinator (#181), `Math.random()`'s: nothing secret depends on them.
      lotteryDraws: Random().nextDouble,
      // The draws that move a meeting point pinned (#189): they hide the place pinned, so the secure source.
      locationDraws: Random.secure().nextDouble,
      // The tiles of the maps (#246): OpenStreetMap's, outside Tor, the one connection the feature opens itself outside Tor (the wallet's price and swap service also leave outside Tor, through the wallet's port); nothing is created before a map's « Show tiles » is on and acknowledged.
      tiles: () => const OsmMapTileAdapter(),
    );
    if (garageKeys != null &&
        derivedGarageKeys != null &&
        databaseDirectory != null) {
      registerGarageKeys(
        locator,
        garageKeys,
        derivedGarageKeys,
        database: () => P2pDatabase.open(databaseDirectory),
        transport: () => locator<TorCoordinatorTransport>(),
        relays: () => locator<TorCoordinatorTransport>(),
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

  /// Registers the Garage Keys of each network, the keys of the default wallet's words that [derivedGarageKeys] derives (#81) and the external key that the vault keeps behind [garageKeys], the use-cases that read them, activate the next key of the words, and import or delete the external key, the Garage that shows them, and the bindings of their robots in the database [database] makes, with the request of a robot that checks them over [transport].
  ///
  /// Registering touches no key and no file: the keystore and the database are read or written only when a use-case runs, and the Garage runs them only once the user opens it, and the book asks the vault whether a key is stored only when « Search order » found no order in the books received.
  static void registerGarageKeys(
    GetIt locator,
    GarageKeys garageKeys,
    P2pGarageKeyPort derivedGarageKeys, {
    required P2pDatabase Function() database,
    required CoordinatorTransport Function() transport,
    required NostrRelayTransport Function() relays,
    required DateTime Function() clock,
  }) {
    // The vault's handle and the port of the keys of the words stay inside the repository: neither is registered in the container.
    locator.registerLazySingleton<GarageKeyRepository>(
      () => GarageKeyRepositoryImpl(
        garageKeys,
        derivedGarageKeys,
        GarageKeyBookRepositoryImpl(locator(), clock: clock),
      ),
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
    locator.registerFactory<ImportGarageKeyUsecase>(
      () => ImportGarageKeyUsecase(locator(), locator()),
    );
    locator.registerFactory<ReadGarageKeyUsecase>(
      () => ReadGarageKeyUsecase(locator()),
    );
    locator.registerFactory<DeriveFirstRobotUsecase>(
      () => DeriveFirstRobotUsecase(locator()),
    );
    locator.registerFactory<NewGarageKeyUsecase>(
      () => NewGarageKeyUsecase(locator()),
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
    // Where the user left the Garage of each network by hand (#251), in memory, for the whole run of the app.
    locator.registerLazySingleton<GarageNavigation>(GarageNavigation.new);
    locator.registerFactoryParam<GarageCubit, RobosatsNetwork, void>(
      (network, _) => GarageCubit(
        network,
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        // The records the robot shown follows (#227, #251), where the feature holds trades.
        tradesOf: locator.isRegistered<FollowTradesUsecase>()
            ? locator<FollowTradesUsecase>().execute
            : null,
        navigation: locator<GarageNavigation>(),
        // One read of an open record whose robot has no active order, once per visit (#251, step 0), where the feature holds trades.
        readOnce: locator.isRegistered<WatchTradeUsecase>()
            ? locator<WatchTradeUsecase>().readOnce
            : null,
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
    registerTrades(locator, transport: transport, relays: relays, clock: clock);
  }

  /// Registers the trades (#87): their records, terms and trails in the database, the robot layer that reserves a fresh robot for each take, and the trade use cases, the only callers of the coordinator's money members; the trade screens (#88) are their only callers.
  ///
  /// The invoices of a trade are decoded by the [Bolt11Decoder] the shell registered ([setup]); without one, every invoice is refused, so that none is shown or paid.
  /// Whether the bond of a trade can be paid from the wallet: the wallet's port was lent and the trades are registered.
  static bool paysBondFromWallet(GetIt locator) =>
      locator.isRegistered<P2pWalletPort>() &&
      locator.isRegistered<TradeReader>();

  static void registerTrades(
    GetIt locator, {
    required CoordinatorTransport Function() transport,
    required NostrRelayTransport Function() relays,
    required DateTime Function() clock,
  }) {
    locator.registerLazySingleton<TradeRecordRepository>(
      () => TradeRecordRepositoryImpl(locator(), clock: clock),
    );
    locator.registerLazySingleton<TradeTrailRepository>(
      () => TradeTrailRepositoryImpl(locator()),
    );
    locator.registerLazySingleton<TradePaymentRepository>(
      () => TradePaymentRepositoryImpl(locator()),
    );
    // Where each contract's payout of a buyer came from (schema 9, #204), and the invoices and addresses the wallet gave during this run, which tell a payout from this wallet from one pasted: one for the feature, in memory.
    locator.registerLazySingleton<TradePayoutRepository>(
      () => TradePayoutRepositoryImpl(locator()),
    );
    locator.registerLazySingleton<WalletPayoutDestinations>(
      WalletPayoutDestinations.new,
    );
    // The peer's public key each trade's chat pinned, with its fingerprints, and its Nostr keys (#139, part of #159).
    locator.registerLazySingleton<TradeChatPinRepository>(
      () => TradeChatPinRepositoryImpl(locator()),
    );
    locator.registerLazySingleton<TradeRobots>(
      () => InterimTradeRobots(locator(), locator()),
    );
    Bolt11Reader invoices() => Bolt11Reader(
      locator.isRegistered<Bolt11Decoder>()
          ? locator<Bolt11Decoder>()
          : const _NoBolt11Decoder(),
    );
    // One for the feature: every reader orders the answers of a trade by when their requests left, whichever use case sent them (#141).
    locator.registerLazySingleton<TradeReadOrder>(TradeReadOrder.new);
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
        requestOrder: locator(),
        payouts: locator(),
      ),
    );
    // One for the feature: the takes and the payouts of an order run one at a time, whichever use case object runs them.
    locator.registerLazySingleton<TradeTakeLocks>(TradeTakeLocks.new);
    // One for the feature: a take prepared through one use case object is confirmed or abandoned through another (#119).
    locator.registerLazySingleton<PreparedTakes>(PreparedTakes.new);
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
        preparedTakes: locator(),
      ),
    );
    // One for the feature: the makes and the resolutions of pending makes of a network run one at a time, whichever use case object runs them (#179). No screen calls the make yet: the create screen does (#181, #182).
    locator.registerLazySingleton<TradeMakeLocks>(TradeMakeLocks.new);
    locator.registerFactory<MakeOrderUsecase>(
      () => MakeOrderUsecase(
        CoordinatorClient(transport(), clock: clock),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        invoices(),
        locator(),
        Federation.robosats,
      ),
    );
    // The create form (#181): the chosen coordinator's limits, read anonymously as the book; the Bull wallet's price for comparison, only where the wallet's port was lent; and the form's cubit, the only caller of the make. No route opens the form yet: « Create » is enabled by #182.
    locator.registerFactory<FetchCoordinatorLimitsUsecase>(
      () => FetchCoordinatorLimitsUsecase(
        CoordinatorClient(transport(), clock: clock),
      ),
    );
    locator.registerFactory<CheckMakePriceUsecase>(
      () => CheckMakePriceUsecase(locator<P2pWalletPort>()),
    );
    locator.registerFactoryParam<
      MakeOrderCubit,
      RobosatsNetwork,
      RobosatsCurrency
    >(
      (network, currency) => MakeOrderCubit(
        network,
        currency: currency,
        listHosts: locator<ListRobotHostsUsecase>().execute,
        fetchInfo: locator<FetchCoordinatorInfoUsecase>().execute,
        fetchLimits: locator<FetchCoordinatorLimitsUsecase>().execute,
        make: locator<MakeOrderUsecase>().execute,
        hasGarageKey: locator<HasGarageKeyUsecase>().execute,
        lottery: locator<CoordinatorLottery>(),
        now: clock,
        checkPrice: paysBondFromWallet(locator)
            ? locator<CheckMakePriceUsecase>().execute
            : null,
      ),
    );
    // The renewal of an order made here (#185): the same form's cubit, its fields read from the order's kept terms, on its coordinator.
    locator.registerFactoryParam<MakeOrderCubit, TradeRecord, void>(
      (record, _) => MakeOrderCubit.renewal(
        record,
        placeholder:
            RobosatsCurrency.fromCode('USD') ??
            (throw StateError('USD is in the RoboSats currencies')),
        readRenewal: locator<MakeOrderUsecase>().renewal,
        madeAsRenewal: locator<MakeOrderUsecase>().madeAsRenewal,
        listHosts: locator<ListRobotHostsUsecase>().execute,
        fetchInfo: locator<FetchCoordinatorInfoUsecase>().execute,
        fetchLimits: locator<FetchCoordinatorLimitsUsecase>().execute,
        make: locator<MakeOrderUsecase>().execute,
        hasGarageKey: locator<HasGarageKeyUsecase>().execute,
        lottery: locator<CoordinatorLottery>(),
        now: clock,
        checkPrice: paysBondFromWallet(locator)
            ? locator<CheckMakePriceUsecase>().execute
            : null,
      ),
      instanceName: MakeOrderCubit.renewalInstance,
    );
    // The owner's payment rule on a maker buyer's side (#182): one cubit per shown trade, built only where the wallet's port was lent.
    locator.registerFactory<CheckPayoutRateUsecase>(
      () => CheckPayoutRateUsecase(locator(), locator<P2pWalletPort>()),
    );
    // What the rule keeps beyond one page of a trade, until the app stops: the invoice's sats asked per contract, the last price read (security review of #182, C2).
    locator.registerLazySingleton<PayoutRateMemory>(PayoutRateMemory.new);
    locator.registerFactoryParam<PayoutRateCubit, TradeRecord, void>(
      (record, _) => PayoutRateCubit(
        record,
        terms: locator<CheckPayoutRateUsecase>().termsOf,
        price: locator<CheckPayoutRateUsecase>().priceOf,
        memory: locator<PayoutRateMemory>(),
        now: clock,
      ),
    );
    // The renewals of an order made here (#217): the orders made here since with its kept terms, read from the device, one cubit per trade screen that offers its renewal.
    locator.registerFactoryParam<RenewalsCubit, TradeRecord, void>(
      (record, _) =>
          RenewalsCubit(record, locator<MakeOrderUsecase>().renewalsOf),
    );
    // The records the Garage shows its robot from (#251): the trades in progress, the finished ones with their end, and the robot the next trade would reserve, read from the device only.
    locator.registerFactory<FollowTradesUsecase>(
      () => FollowTradesUsecase(
        locator<ListActiveTradesUsecase>().execute,
        locator<TradeRecordRepository>().watchClosedTrades,
        locator<TradeRecordRepository>().newTradeStandingOf,
      ),
    );
    // The robot the Garage would show, for the line of the order page only (#251): no trade takes its robot from it.
    locator.registerFactory<GarageRobotUsecase>(
      () => GarageRobotUsecase(locator(), locator(), locator()),
    );
    // The pending makes of a network (#182): their lines in « Active trades » and above the create form, one cubit per screen that shows them.
    locator.registerFactoryParam<PendingMakesCubit, RobosatsNetwork, void>(
      (network, _) => PendingMakesCubit(
        network,
        locator<MakeOrderUsecase>().pendingMakes,
        locator<MakeOrderUsecase>().resolve,
        locator<MakeOrderUsecase>().dismiss,
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
        locator(),
      ),
    );
    // The chat step's actions (#95): « fiat sent », as the cancel, under the order's lock.
    locator.registerFactory<ChatStepActionUsecase>(
      () => ChatStepActionUsecase(
        CoordinatorClient(transport(), clock: clock),
        locator(),
        locator(),
        locator(),
      ),
    );
    // The pause and « Unpause Order » of a public order made here (#184), as the cancel, under the order's lock.
    // One for the feature: the pauses running now, so that a trade screen opened again meanwhile shows its order's pause running (functional review of #184, R1); what stays uncertain after one settles on a time that only moves forward, as the limiter's busy window (#214).
    locator.registerLazySingleton<PausesInFlight>(() {
      final running = Stopwatch()..start();
      return PausesInFlight(
        elapsed: () => running.elapsed,
        requestDeadline: coordinatorRequestDeadline,
      );
    });
    locator.registerFactory<PauseOrderUsecase>(
      () => PauseOrderUsecase(
        CoordinatorClient(transport(), clock: clock),
        locator(),
        locator(),
        locator(),
        locator(),
      ),
    );
    locator.registerFactory<ListActiveTradesUsecase>(
      () => ListActiveTradesUsecase(locator(), locator(), clock: clock),
    );
    // One for the feature: the unlocked keys of the trades' robots, kept while a screen holds them or a signature leases them (#90).
    locator.registerLazySingleton<TradeKeyring>(
      () => TradeKeyring(locator(), locator()),
    );
    locator.registerFactory<HoldTradeKeyUsecase>(
      () => HoldTradeKeyUsecase(locator()),
    );
    locator.registerFactory<SubmitPayoutUsecase>(
      () => SubmitPayoutUsecase(
        CoordinatorClient(transport(), clock: clock),
        locator(),
        locator(),
        locator(),
        locator(),
        invoices(),
        payouts: locator(),
        fromWallet: locator(),
      ),
    );
    // One for the feature: the chats of the trades, in memory only, so that a peer's key stays pinned when a trade screen is opened again (#93).
    locator.registerLazySingleton<TradeChats>(TradeChats.new);
    locator.registerFactory<WatchChatUsecase>(
      () => WatchChatUsecase(
        CoordinatorClient(transport(), clock: clock),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
      ),
    );
    // The chat as the reference exports it (#93), the robot's token included: on the user's tap only, through the chat panel's cubit.
    locator.registerFactory<ExportChatUsecase>(
      () => ExportChatUsecase(locator(), locator(), locator()),
    );
    locator.registerFactory<SendChatMessageUsecase>(
      () => SendChatMessageUsecase(
        CoordinatorClient(transport(), clock: clock),
        locator(),
        locator(),
        locator(),
        locator(),
        locator(),
        relays(),
        Federation.robosats,
        Random.secure(),
        locator(),
      ),
    );
    // « Rate your host » (#95): the coordinator's token and the rating published on Nostr, over the robot's sessions as the chat's copies.
    locator.registerFactory<RateHostUsecase>(
      () => RateHostUsecase(
        CoordinatorClient(transport(), clock: clock),
        locator(),
        locator(),
        locator(),
        relays(),
        Federation.robosats,
        Random.secure(),
      ),
    );
    // The screens of the trades (#88), their only callers: the take of an order of the book, in two steps (#119), one trade shown, and the list of the active trades of a network.
    TakeCalls takeCalls() {
      final take = locator<TakeOrderUsecase>();
      return TakeCalls(
        prepare: take.prepare,
        prepareUnlisted: take.prepareUnlisted,
        confirm: take.confirm,
        abandon: take.abandon,
        abandonOrder: take.abandonOrder,
        // The robot the Garage would show, for the line of the order page only (#251).
        garageRobot: locator<GarageRobotUsecase>().execute,
      );
    }

    // The owner's payment rule before the take (#249, slice 4): the read shown compared with the Bull wallet's price, only where the wallet's port was lent.
    CheckTakePrice? takePrice() => paysBondFromWallet(locator)
        ? locator<CheckMakePriceUsecase>().execute
        : null;

    locator.registerFactoryParam<TakeOrderCubit, PublicOrder, RobosatsNetwork>(
      (order, network) => TakeOrderCubit(
        order,
        network,
        takeCalls(),
        locator<HasGarageKeyUsecase>().execute,
        checkPrice: takePrice(),
        now: clock,
      ),
    );
    // The take of an order no book received, reached by its URL and read by its robot (#245): a password-protected one, or a public one the book in memory does not hold yet; and the read itself.
    locator.registerFactoryParam<TakeOrderCubit, UnlistedOrder, void>(
      (order, _) => TakeOrderCubit.unlisted(
        order,
        takeCalls(),
        locator<HasGarageKeyUsecase>().execute,
        checkPrice: takePrice(),
        now: clock,
      ),
      instanceName: TakeOrderCubit.unlistedOrder,
    );
    locator.registerFactoryParam<
      UnlistedOrderCubit,
      (Coordinator, int),
      RobosatsNetwork
    >((order, network) {
      final take = locator<TakeOrderUsecase>();
      final (coordinator, orderId) = order;
      return UnlistedOrderCubit(
        coordinator,
        orderId,
        network,
        take.readUnlisted,
        take.abandonRead,
        garageRobot: locator<GarageRobotUsecase>().execute,
      );
    });
    // The same, from the trade screen of an order public again: the trade shown is given, so that a take refused for that very trade is not opened over itself.
    locator.registerFactoryParam<TakeOrderCubit, PublicOrder, TradeRecord>(
      (order, shown) => TakeOrderCubit(
        order,
        shown.network,
        takeCalls(),
        locator<HasGarageKeyUsecase>().execute,
        shownTrade: shown,
        checkPrice: takePrice(),
        now: clock,
      ),
      instanceName: TakeOrderCubit.fromTrade,
    );
    locator.registerFactoryParam<TradeCubit, TradeRecord, void>(
      (record, _) => TradeCubit(
        record,
        locator<WatchTradeUsecase>().execute,
        locator<CancelTradeUsecase>().execute,
        confirmFiatSent: locator<ChatStepActionUsecase>().confirmFiatSent,
        confirmFiatReceived:
            locator<ChatStepActionUsecase>().confirmFiatReceived,
        lastStored: locator<WatchTradeUsecase>().lastStored,
        undoFiatSent: locator<ChatStepActionUsecase>().undoFiatSent,
        startDispute: locator<ChatStepActionUsecase>().startDispute,
        rate: locator<ChatStepActionUsecase>().rate,
        pause: locator<PauseOrderUsecase>().execute,
        pauseRunning: locator<PauseOrderUsecase>().running,
        pauseUncertainty: locator<PauseOrderUsecase>().uncertainty,
      ),
    );
    // The payout panel of one shown trade (#91), the only caller of the payout use case and of the key's hold.
    locator.registerFactoryParam<PayoutCubit, TradeRecord, void>((record, _) {
      final payout = locator<SubmitPayoutUsecase>();
      return PayoutCubit(
        record,
        payout.ask,
        payout.check,
        payout.execute,
        (record) => locator<HoldTradeKeyUsecase>().execute(record).release,
        now: locator<P2pClock>().now,
      );
    });
    // The chat panel of one shown trade (#93), the only caller of the chat use cases and, for the chat, of the key's hold.
    locator.registerFactoryParam<ChatCubit, TradeRecord, void>((record, _) {
      final watch = locator<WatchChatUsecase>();
      final send = locator<SendChatMessageUsecase>();
      return ChatCubit(
        record,
        watch.read,
        send.send,
        send.sendAgain,
        watch.readNewerOnly,
        watch.current,
        locator<ExportChatUsecase>().execute,
        (record) => locator<HoldTradeKeyUsecase>().execute(record).release,
      );
    });
    // « Rate your host » of one shown trade (#95), the only caller of its use case.
    locator.registerFactoryParam<HostRatingCubit, TradeRecord, void>((
      record,
      _,
    ) {
      final rate = locator<RateHostUsecase>();
      return HostRatingCubit(record, rate.fetchToken, rate.publish);
    });
    // The bond paid from the wallet (#100), the escrow's below (#97): resolved only where the wallet's port was lent (`P2pFeature.setup(wallet:)`), which the route checks before it builds the panel.
    locator.registerFactory<PayBondFromWalletUsecase>(
      () => PayBondFromWalletUsecase(
        locator(),
        locator(),
        locator(),
        locator<P2pWalletPort>(),
        locator(),
        locator(),
      ),
    );
    // The seller's escrow paid from the wallet (#97): the same use case for the escrow's step.
    locator.registerFactory<PayBondFromWalletUsecase>(
      () => PayBondFromWalletUsecase(
        locator(),
        locator(),
        locator(),
        locator<P2pWalletPort>(),
        locator(),
        locator(),
        step: InvoiceStep.escrow,
      ),
      instanceName: InvoiceStep.escrow.name,
    );
    // One for the feature, each step apart: a screen opened again while a payment runs knows of it.
    locator.registerLazySingleton<BondPaymentsInFlight>(
      BondPaymentsInFlight.new,
    );
    locator.registerFactoryParam<BondPaymentCubit, TradeRecord, void>((
      record,
      _,
    ) {
      final payments = locator<PayBondFromWalletUsecase>();
      return BondPaymentCubit(
        record,
        payments.watchBalance,
        payments.checkBond,
        payments.quoteBond,
        payments.payBond,
        payments.followBond,
        payments.bondPaymentRunning,
        step: payments.step,
        // The maker bond's comparison with the wallet's own price (#180).
        rate: payments.rateOfBond,
      );
    });
    locator.registerFactoryParam<EscrowPaymentCubit, TradeRecord, void>((
      record,
      _,
    ) {
      final payments = locator<PayBondFromWalletUsecase>(
        instanceName: InvoiceStep.escrow.name,
      );
      return EscrowPaymentCubit(
        record,
        payments.watchBalance,
        payments.checkBond,
        payments.quoteBond,
        payments.payBond,
        payments.followBond,
        payments.bondPaymentRunning,
        step: payments.step,
        // A maker seller's escrow (#188): the comparison with the wallet's own price, the contract its confirmation states, and every escrow of the trade followed; each gives nothing for a taker.
        rate: payments.rateOfBond,
        contract: payments.escrowContractOf,
        escrowsFollower: payments.followEscrows,
      );
    });
    // The buyer's payout from the wallet (#90): the wallet's invoice and address in the payout panel, resolved only where the wallet's port was lent, as the bond's payment; one use case for the run, which remembers at which step it gave each invoice.
    locator.registerLazySingleton<PayoutFromWalletUsecase>(
      () => PayoutFromWalletUsecase(
        locator<P2pWalletPort>(),
        given: locator<WalletPayoutDestinations>(),
      ),
    );
    locator.registerFactory<PayoutWalletCubit>(
      () => PayoutWalletCubit(locator()),
    );
    locator.registerFactoryParam<ActiveTradesCubit, RobosatsNetwork, void>(
      (network, _) => ActiveTradesCubit(
        network,
        locator<ListActiveTradesUsecase>().execute,
      ),
    );
    // « Last order #N » of the Garage (#216): the last finished orders of the network, read from the device only.
    locator.registerFactory<ListLastOrdersUsecase>(
      () => ListLastOrdersUsecase(locator()),
    );
    locator.registerFactoryParam<LastOrdersCubit, RobosatsNetwork, void>(
      (network, _) =>
          LastOrdersCubit(network, locator<ListLastOrdersUsecase>().execute),
    );
    // The history of finished orders of the Garage (#253): the orders of every Garage Key of the network (#81), read from the device only; the cubit keeps no key.
    locator.registerFactory<ListOrderHistoryUsecase>(
      () => ListOrderHistoryUsecase(locator()),
    );
    locator.registerFactoryParam<OrderHistoryCubit, NetworkGarageKey, void>(
      (key, _) => OrderHistoryCubit(
        key.network,
        locator<ListOrderHistoryUsecase>().execute,
      ),
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
    required double Function() lotteryDraws,
    required double Function() locationDraws,
    required MapTilePort Function() tiles,
    P2pShuffle shuffle = P2pShuffle.random,
  }) {
    locator.registerSingleton<P2pClock>(P2pClock(clock));
    locator.registerSingleton<MeetingPointDraws>(
      MeetingPointDraws(locationDraws),
    );
    locator.registerSingleton<CoordinatorLottery>(
      CoordinatorLottery(lotteryDraws),
    );
    locator.registerSingleton<P2pShuffle>(shuffle);
    locator.registerSingleton<P2pWaits>(waits);
    // The tiles of the two maps (#246): its only callers are the maps, through the routes that build them.
    locator.registerFactory<OpenMapTilesUsecase>(
      () => OpenMapTilesUsecase(tiles()),
    );
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
    // Its only caller is the trade screen's order tab (#88), for an order public again.
    locator.registerFactory<FindPublicOrderUsecase>(
      () =>
          FindPublicOrderUsecase(CoordinatorClient(transport(), clock: clock)),
    );
    // What the order tab of a trade shows besides the order: read without a robot, as the order details of the book.
    locator.registerFactoryParam<TradeOrderPageCubit, TradeRecord, void>(
      (record, _) => TradeOrderPageCubit(
        Federation.robosats.byAlias(record.coordinatorAlias),
        record.network,
        locator<FetchCoordinatorInfoUsecase>().execute,
        locator<FindPublicOrderUsecase>().execute,
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
      (network, _) => BookCubit(
        network,
        locator(),
        locator(),
        locator(),
        locator(),
        // Registered with the Garage only, which may come after this: read when a book is made, it touches no key until « Search order » asks it.
        hasGarageKey: locator.isRegistered<HasGarageKeyUsecase>()
            ? locator()
            : null,
      ),
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
