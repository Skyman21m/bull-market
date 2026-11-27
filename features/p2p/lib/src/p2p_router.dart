import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:robosats/robosats.dart';

import 'domain/p2p_clock.dart';
import 'domain/book_filter.dart';
import 'domain/p2p_shuffle.dart';
import 'domain/recovery_note_sync.dart';
import 'domain/trade/trade_take.dart';
import 'domain/trade/trade_watch.dart';
import 'domain/trade_record.dart';
import 'domain/meeting_point.dart';
import 'domain/usecases/open_map_tiles_usecase.dart';
import 'p2p_locator.dart';
import 'presentation/active_trades_cubit.dart';
import 'presentation/bond_payment_cubit.dart';
import 'presentation/book_cubit.dart';
import 'presentation/book_state.dart';
import 'presentation/chat_cubit.dart';
import 'presentation/coordinator_details_cubit.dart';
import 'presentation/garage_cubit.dart';
import 'presentation/host_rating_cubit.dart';
import 'presentation/last_orders_cubit.dart';
import 'presentation/order_history_cubit.dart';
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
import 'ui/create_order_screen.dart';
import 'ui/garage/garage_reauthentication.dart';
import 'ui/garage/garage_view.dart';
import 'ui/order_details_screen.dart';
import 'ui/p2p_tab_screen.dart';
import 'ui/unlisted_order_screen.dart';
import 'ui/trade/active_trades_sheet.dart';
import 'ui/trade/bond_payment_panel.dart';
import 'ui/trade/earlier_escrow_lines.dart';
import 'ui/trade/chat_actions.dart';
import 'ui/trade/chat_panel.dart';
import 'ui/trade/host_rating_section.dart';
import 'ui/trade/payout_panel.dart';
import 'ui/trade/payout_wallet_section.dart';
import 'ui/trade/trade_screen.dart';
import 'ui/widgets/garage_key_clipboard.dart';

/// What the page of an order needs: the order as the book listed it, and the network of its book.
///
/// The page of an order is reached from the book only: without these, as after a deep link or a restored session, it sends back to the book.
final class P2pOrderRouteArgs {
  final PublicOrder order;
  final RobosatsNetwork network;

  /// Whether « Take Order » may be offered: not when the records of the active trades could not be read, which may hold an order this device made (security review of #182, R3).
  final bool takeable;

  const P2pOrderRouteArgs(this.order, this.network, {this.takeable = true});
}

/// What the page of an order the books do not list needs (#245): its coordinator and number, from « Search order », and the network of the tab; its robot reads it there.
final class P2pUnlistedOrderRouteArgs {
  final Coordinator coordinator;
  final int orderId;
  final RobosatsNetwork network;

  const P2pUnlistedOrderRouteArgs(this.coordinator, this.orderId, this.network);
}

/// What the page of a trade needs: the trade's record, from a take, a make or the list of the active trades.
///
/// The page of a trade is reached from those only: without it, as after a deep link or a restored session, it sends back to the tab, whose « Order » entry lists the active trades.
final class P2pTradeRouteArgs {
  final TradeRecord record;

  /// Every order the book of the tab received when the page was opened, for the figures of a maker's public order (`TradeScreen.book`, #182); `null` when none was received.
  final List<PublicOrder>? book;

  const P2pTradeRouteArgs(this.record, {this.book});
}

/// What the create page needs (#181): the network of the tab, and the book's choices it starts from, as the reference's form starts from the book's (`fav`): « Buy » chosen when the book shows the orders a buyer takes, the currency the book shows first, USD when it shows any (`MakerForm.tsx:98-100`); and the coordinators the book could not reach.
final class P2pCreateRouteArgs {
  final RobosatsNetwork network;
  final OrderType? initialType;
  final RobosatsCurrency currency;
  final Set<String> offline;

  /// The book of the tab, handed to the trade of the order made ([P2pTradeRouteArgs.book], #182).
  final List<PublicOrder>? book;

  /// The trade of the order made here that the page renews (#185), `null` for a creation.
  final TradeRecord? renewing;

  const P2pCreateRouteArgs(
    this.network, {
    required this.currency,
    this.initialType,
    this.offline = const {},
    this.book,
  }) : renewing = null;

  /// The renewal's page of the order of [record] (#185), from its trade's page: the form filled with that order's kept terms, on its coordinator; [currency] stands until those terms are read, and is shown nowhere.
  P2pCreateRouteArgs.renewal(TradeRecord record, {this.book})
    : network = record.network,
      currency =
          RobosatsCurrency.fromCode('USD') ??
          (throw StateError('USD is in the RoboSats currencies')),
      initialType = null,
      offline = const {},
      renewing = record;

  /// The create page's start from [book], the book of the tab (#182): « Buy » when it shows the orders a buyer takes and « Sell » when it shows a seller's, as the reference's form takes its side from the book's filter (`fav.type`, `MakerForm.tsx:258`); the first currency it shows, USD for any (`MakerForm.tsx:98-100`); the coordinators it could not reach; and every order it received.
  static P2pCreateRouteArgs fromBook(BookState book) {
    final usd = RobosatsCurrency.fromCode('USD');
    return P2pCreateRouteArgs(
      book.network,
      initialType: switch (book.filter.side) {
        BookSide.buy => OrderType.buy,
        BookSide.sell => OrderType.sell,
        BookSide.any => null,
      },
      currency:
          book.filter.currencies.where((c) => !c.isBitcoin).firstOrNull ??
          usd ??
          (throw StateError('USD is in the RoboSats currencies')),
      offline: {
        for (final MapEntry(:key, :value) in book.coordinators.entries)
          if (value case CoordinatorBookFailed(
            failure: CoordinatorNotOnNetwork() ||
                CoordinatorUnreachable() ||
                CoordinatorTimedOut() ||
                CoordinatorResponseTooLarge() ||
                CoordinatorTransportFailed(),
          ))
            key.shortAlias,
      },
      book: book.hasBookReceived ? book.receivedOrders.toList() : null,
    );
  }
}

/// What the page of an order gives back when it is left for the Garage (« I have a Garage Key »).
enum P2pOrderExit { garage }

/// The routes of the P2P tab: the book and the Garage, and the page of an order and the page of a trade above them.
final class P2pRouter {
  static const path = '/p2p';
  static const name = 'p2p';
  static const orderName = 'p2pOrder';
  static const unlistedOrderName = 'p2pProtectedOrder';
  static const tradeName = 'p2pTrade';
  static const createName = 'p2pCreate';

  /// Whether [location] is a page of the P2P tab.
  static bool isP2pPath(String location) =>
      location == path || location.startsWith('$path/');

  /// [network] is read from the context of the page each time it builds, so the book and the Garage follow a change of network.
  /// [reauthenticate] is what the Garage asks before it shows a stored key; without it, a stored key is never shown.
  static GoRoute route(
    GetIt locator,
    RobosatsNetwork Function(BuildContext context) network, {
    P2pReauthentication? reauthenticate,
  }) => GoRoute(
    name: name,
    path: path,
    builder: (context, state) => _P2pPage(
      locator: locator,
      network: network,
      reauthenticate: reauthenticate,
    ),
    routes: [
      GoRoute(
        name: orderName,
        path: 'order',
        redirect: (context, state) =>
            state.extra is P2pOrderRouteArgs ? null : path,
        builder: (context, state) => switch (state.extra) {
          final P2pOrderRouteArgs args => _orderPage(locator, args),
          _ => const SizedBox.shrink(),
        },
      ),
      // The page of an order the books do not list, reached by its URL (#245): only from « Search order », which hands it what it needs.
      GoRoute(
        name: unlistedOrderName,
        path: 'unlisted',
        redirect: (context, state) =>
            state.extra is P2pUnlistedOrderRouteArgs ? null : path,
        builder: (context, state) => switch (state.extra) {
          final P2pUnlistedOrderRouteArgs args => _unlistedOrderPage(
            locator,
            args,
          ),
          _ => const SizedBox.shrink(),
        },
      ),
      GoRoute(
        name: tradeName,
        path: 'trade',
        redirect: (context, state) =>
            state.extra is P2pTradeRouteArgs ? null : path,
        builder: (context, state) => switch (state.extra) {
          final P2pTradeRouteArgs args => tradePage(locator, args),
          _ => const SizedBox.shrink(),
        },
      ),
      // The create form (#181), reachable since the maker's panels exist (#182): from « Create » of the tab and « Create order » of « Active trades » only, which hand it what it needs.
      GoRoute(
        name: createName,
        path: 'create',
        redirect: (context, state) =>
            state.extra is P2pCreateRouteArgs ? null : path,
        builder: (context, state) => switch (state.extra) {
          final P2pCreateRouteArgs args => createPage(locator, args),
          _ => const SizedBox.shrink(),
        },
      ),
    ],
  );

  /// The page of a trade: its watch, its order's page, and, when the feature holds robots, its payout panel's cubit, each one per shown trade and closed with the page (which lets the robot's key go).
  @visibleForTesting
  static Widget tradePage(GetIt locator, P2pTradeRouteArgs args) {
    final payouts = locator.isRegistered<PayoutCubit>();
    final chats = locator.isRegistered<ChatCubit>();
    final hostRatings = locator.isRegistered<HostRatingCubit>();
    // The owner's payment rule on a maker buyer's side (#182): with the wallet's port, where the composition registered its cubit.
    final checksPayoutRate =
        P2pLocator.paysBondFromWallet(locator) &&
        locator.isRegistered<PayoutRateCubit>();
    // « Renew Order » and « Renew » (#185), where the feature can make an order; with them, what the records say of the order's renewals (#217), for an order made here.
    final renews =
        locator.isRegistered<MakeOrderCubit>(
          instanceName: MakeOrderCubit.renewalInstance,
        ) &&
        locator.isRegistered<PendingMakesCubit>();
    final readsRenewals =
        renews &&
        args.record.origin == TradeOrigin.madeHere &&
        locator.isRegistered<RenewalsCubit>();
    return MultiBlocProvider(
      providers: [
        // The wallet's payment of the bond (#100), only where the wallet's port was lent: without it the screen is as before, « Pay with another wallet » alone.
        if (P2pLocator.paysBondFromWallet(locator))
          BlocProvider(
            create: (_) =>
                locator<BondPaymentCubit>(param1: args.record)..start(),
          ),
        // The owner's payment rule on a maker buyer's side (#182), on the same condition: the Bull wallet's price is read through the port.
        if (checksPayoutRate)
          BlocProvider(
            create: (_) => locator<PayoutRateCubit>(param1: args.record),
          ),
        // The wallet's payment of a seller's escrow (#97), on the same condition.
        if (P2pLocator.paysBondFromWallet(locator))
          BlocProvider(
            create: (_) =>
                locator<EscrowPaymentCubit>(param1: args.record)..start(),
          ),
        BlocProvider(
          create: (_) => locator<TradeCubit>(param1: args.record)..start(),
        ),
        BlocProvider(
          create: (_) =>
              locator<TradeOrderPageCubit>(param1: args.record)..loadInfo(),
        ),
        // One payout panel per shown trade, closed with its page, which lets the robot's key go.
        if (payouts)
          BlocProvider(
            create: (_) => locator<PayoutCubit>(param1: args.record),
          ),
        // The wallet's invoice and address in the payout panel (#90), only where the wallet's port was lent.
        if (payouts && P2pLocator.paysBondFromWallet(locator))
          BlocProvider(create: (_) => locator<PayoutWalletCubit>()),
        // One chat panel per shown trade, closed with its page, which stops its reads and lets the robot's key go.
        if (chats)
          BlocProvider(create: (_) => locator<ChatCubit>(param1: args.record)),
        // « Rate your host » of the shown trade (#95), closed with its page: the token is asked again when the page is opened again.
        if (hostRatings)
          BlocProvider(
            create: (_) => locator<HostRatingCubit>(param1: args.record),
          ),
        // The terms kept of an order made here and the orders made since with them (#216, #217), read from the device for the page's life.
        if (readsRenewals)
          BlocProvider(
            create: (_) => locator<RenewalsCubit>(param1: args.record)..start(),
          ),
      ],
      child: Builder(
        builder: (context) => _toldReads(
          payouts,
          context,
          TradeScreen(
            now: locator<P2pClock>().now,
            walletPayment: P2pLocator.paysBondFromWallet(locator)
                ? BondPaymentPanel.slotFor
                : null,
            walletBond: P2pLocator.paysBondFromWallet(locator)
                ? BondPaymentPanel.bondOf
                : null,
            walletBondLine: P2pLocator.paysBondFromWallet(locator)
                ? (_, bondHeld) => BondPaymentLine(bondHeld: bondHeld)
                : null,
            walletEscrowLine: P2pLocator.paysBondFromWallet(locator)
                ? (_, escrowHeld) =>
                      BondPaymentLine(bondHeld: escrowHeld, escrow: true)
                : null,
            // The escrows of a maker seller's other contracts (#188).
            walletEarlierEscrows: P2pLocator.paysBondFromWallet(locator)
                ? (_) => const EarlierEscrowLines()
                : null,
            coordinatorDetails: (request) =>
                locator<CoordinatorDetailsCubit>(param1: request),
            payout: payouts
                ? (context, request) => PayoutPanel(
                    request: request,
                    wallet: P2pLocator.paysBondFromWallet(locator)
                        ? PayoutWalletSection.slotFor
                        : null,
                    walletReceipt: P2pLocator.paysBondFromWallet(locator)
                        ? PayoutWalletSection.receiptOf
                        : null,
                  )
                : null,
            chat: chats
                ? (context, request) => ChatPanel(request: request)
                : null,
            // « Audit Chat » and « Export » in « Order options » (#157), over the same chat cubit as the panel.
            chatOptions: chats ? chatOptionsOf : null,
            hostRating: hostRatings
                ? (context, seen, coordinator) =>
                      HostRatingSection(seen: seen, coordinator: coordinator)
                : null,
            moneyActionRunning: payouts
                ? (context) =>
                      context.watch<PayoutCubit>().state.phase is PayoutSending
                : null,
            // An order public again is taken as from the book: a fresh robot, the same single caller of the take.
            takeCubitFor:
                locator.isRegistered<TakeOrderCubit>(
                  instanceName: TakeOrderCubit.fromTrade,
                )
                ? (order) => locator<TakeOrderCubit>(
                    param1: order,
                    param2: args.record,
                    instanceName: TakeOrderCubit.fromTrade,
                  )
                : null,
            onOpenGarage: locator.isRegistered<GarageCubit>()
                ? () => context.pop(P2pOrderExit.garage)
                : null,
            onTaken: (record) => context.pushReplacementNamed(
              tradeName,
              extra: P2pTradeRouteArgs(record),
            ),
            book: args.book,
            checksPayoutRate: checksPayoutRate,
            // « Renew Order » and « Renew » (#185): the renewal's page above the trade, where the feature can make an order; the Garage, when that page is left for it, through this page.
            onRenew: renews
                ? (record) => openRenewal(context, record, book: args.book)
                : null,
            // An order made since with the terms of this one (#217): said, and opened in place of this page, as a renewal made opens its new trade.
            readsRenewals: readsRenewals,
            onOpenTrade: readsRenewals
                ? (record) => context.pushReplacementNamed(
                    tradeName,
                    extra: P2pTradeRouteArgs(record, book: args.book),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  /// The create page (#181): the form over its cubit, with the network's pending makes above it (#182), a made order, or a pending make a resolution confirms, replacing the page by its trade as a take does.
  ///
  /// Built by the route `create` (#182), which « Create » of the tab and « Create order » of « Active trades » open, and by the testing seam (`createOrderPageForTesting`) for the app's captures, as `trade_screen_architecture_test.dart` pins.
  static Widget createPage(
    GetIt locator,
    P2pCreateRouteArgs args,
  ) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => switch (args.renewing) {
          // A renewal (#185): the form's cubit built from the record of the order renewed.
          final record? => locator<MakeOrderCubit>(
            param1: record,
            instanceName: MakeOrderCubit.renewalInstance,
          ),
          null => locator<MakeOrderCubit>(
            param1: args.network,
            param2: args.currency,
          ),
        }..start(),
      ),
      // The pending makes resolved once when the form opens: the form makes nothing while one is listed (security review of #181, S2).
      BlocProvider(
        create: (_) {
          final pending = locator<PendingMakesCubit>(param1: args.network)
            ..start();
          unawaited(pending.resolveAll());
          return pending;
        },
      ),
    ],
    child: Builder(
      builder: (context) {
        Widget screen(ActiveTradesState? active) => CreateOrderScreen(
          initialType: args.initialType,
          offline: args.offline,
          coordinatorDetails: (request) =>
              locator<CoordinatorDetailsCubit>(param1: request),
          onOpenGarage: locator.isRegistered<GarageCubit>()
              ? () => context.pop(P2pOrderExit.garage)
              : null,
          onMade: (record) => openMade(context, args, record),
          // « Existing orders match yours! » (#186): the book the tab received, searched on the device, and the device's trades, so that none of its orders is offered.
          book: active == null ? null : args.book,
          activeTrades: active,
          onOpenOrder: (order) => unawaited(openMatch(context, args, order)),
          now: locator<P2pClock>().now,
          // The draws that move a meeting point pinned (#189).
          locationDraws: locator<MeetingPointDraws>().next,
          // The tiles of the meeting point's map (#246), opened only once its « Show tiles » is on and acknowledged.
          openTiles: locator<OpenMapTilesUsecase>().execute,
        );
        return _searchesBook(locator, args)
            ? BlocProvider(
                // The device's trades of the network, read from the device only, for the page's life.
                create: (_) =>
                    locator<ActiveTradesCubit>(param1: args.network)..start(),
                child: BlocBuilder<ActiveTradesCubit, ActiveTradesState>(
                  builder: (_, active) => screen(active),
                ),
              )
            : screen(null);
      },
    ),
  );

  /// Whether the create page of [args] looks for « Existing orders match yours! » (#186): a creation (the reference renews an order without its create page, `TradeBox/index.tsx:146-200`) from a book the tab received, where the feature lists the device's trades.
  static bool _searchesBook(GetIt locator, P2pCreateRouteArgs args) =>
      args.renewing == null &&
      args.book != null &&
      locator.isRegistered<ActiveTradesCubit>();

  /// An order of « Existing orders match yours! » (#186): its page above the create page, as the reference navigates to it (`MakerPage/index.tsx:61-79`), « Take Order » offered as from the book (the order is none of this device's trades, which the search leaves out); left for the Garage, the create page is left for it too.
  ///
  /// Used by [createPage], and by the tests that play the app's navigation.
  @visibleForTesting
  static Future<void> openMatch(
    BuildContext context,
    P2pCreateRouteArgs args,
    PublicOrder order,
  ) async {
    final exit = await context.pushNamed<P2pOrderExit>(
      orderName,
      extra: P2pOrderRouteArgs(order, args.network),
    );
    if (exit == P2pOrderExit.garage && context.mounted) {
      context.pop(P2pOrderExit.garage);
    }
  }

  /// « Renew Order » and « Renew » of the page of the trade of [record] (#185, functional review C1): the renewal's page above it; when that page made the new order, it closes with the new trade's record and the page of the renewed order is replaced by the new trade's, as the reference navigates to the new order (`TradeBox/index.tsx:186-188`), so that no page of the renewed order stays behind with its button; when it is left for the Garage, this page is left for it too; left otherwise (going back, nothing sent, a refusal, a make whose outcome is unknown, now a pending make), the future completes and the page of the renewed order is shown again.
  ///
  /// Used by [tradePage], and by the tests that play the app's navigation.
  @visibleForTesting
  static Future<void> openRenewal(
    BuildContext context,
    TradeRecord record, {
    List<PublicOrder>? book,
  }) async {
    final exit = await context.pushNamed<Object>(
      createName,
      extra: P2pCreateRouteArgs.renewal(record, book: book),
    );
    if (!context.mounted) return;
    switch (exit) {
      case P2pOrderExit.garage:
        context.pop(P2pOrderExit.garage);
      case final TradeRecord made:
        context.pushReplacementNamed(
          tradeName,
          extra: P2pTradeRouteArgs(made, book: book),
        );
      case _:
        break;
    }
  }

  /// The order [record] the create page made, or a pending make of its network confirmed there: a creation's page is replaced by the new trade's (#182); a renewal's page closes with [record], which [openRenewal] opens in place of the renewed order's page (#185).
  ///
  /// Used by [createPage], and by the tests that play the app's navigation.
  @visibleForTesting
  static void openMade(
    BuildContext context,
    P2pCreateRouteArgs args,
    TradeRecord record,
  ) {
    if (args.renewing != null) {
      context.pop(record);
      return;
    }
    context.pushReplacementNamed(
      tradeName,
      extra: P2pTradeRouteArgs(record, book: args.book),
    );
  }

  /// [screen], under the payout panel's listener when there is one: once a payout given told something, the trade's watch reads at once, whichever tab is shown.
  static Widget _toldReads(bool payouts, BuildContext context, Widget screen) =>
      payouts
      ? PayoutTold(
          onTold: () =>
              context.read<TradeCubit>().signal(TradeWatchSignal.readNow),
          child: screen,
        )
      : screen;

  /// The page of an order the books do not list (#245): its robot reads it, and once read the page is the order's ([_orderPage]'s, with « Password » for a protected order); an order with an open trade here opens that trade in its place, and so does a take sent.
  static Widget _unlistedOrderPage(
    GetIt locator,
    P2pUnlistedOrderRouteArgs args,
  ) => BlocProvider(
    create: (_) => locator<UnlistedOrderCubit>(
      param1: (args.coordinator, args.orderId),
      param2: args.network,
    )..load(),
    child: Builder(
      builder: (context) => UnlistedOrderScreen(
        onTraded: (record) => context.pushReplacementNamed(
          tradeName,
          extra: P2pTradeRouteArgs(record),
        ),
        details: (order) => _orderPage(
          locator,
          P2pOrderRouteArgs(order.order, order.network),
          unlisted: order,
        ),
      ),
    ),
  );

  /// The page of an order: « Take Order » takes it when the feature holds robots (the vault's handle was given), and a take that was sent replaces the page by its trade, as the official client's order page becomes the trade at the same address.
  /// [unlisted], an order no book received, which its robot read (#245): its take is that order's.
  static Widget _orderPage(
    GetIt locator,
    P2pOrderRouteArgs args, {
    UnlistedOrder? unlisted,
  }) {
    final canTake = args.takeable && locator.isRegistered<TakeOrderCubit>();
    final details = Builder(
      builder: (context) => OrderDetailsScreen(
        now: locator<P2pClock>().now,
        coordinatorDetails: (request) =>
            locator<CoordinatorDetailsCubit>(param1: request),
        canTake: canTake,
        recordsUnreadable: !args.takeable,
        onOpenGarage: locator.isRegistered<GarageCubit>()
            ? () => context.pop(P2pOrderExit.garage)
            : null,
        onTaken: (record) => context.pushReplacementNamed(
          tradeName,
          extra: P2pTradeRouteArgs(record),
        ),
      ),
    );
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => locator<OrderDetailsCubit>(
            param1: args.order,
            param2: args.network,
          )..load(),
        ),
        if (canTake)
          BlocProvider(
            create: (_) => unlisted == null
                ? locator<TakeOrderCubit>(
                    param1: args.order,
                    param2: args.network,
                  )
                : locator<TakeOrderCubit>(
                    param1: unlisted,
                    instanceName: TakeOrderCubit.unlistedOrder,
                  ),
          ),
      ],
      child: details,
    );
  }
}

/// The tab itself: which destination is shown outlives a change of network, while the book and the Garage are those of the network.
class _P2pPage extends StatefulWidget {
  final GetIt locator;
  final RobosatsNetwork Function(BuildContext context) network;
  final P2pReauthentication? reauthenticate;

  const _P2pPage({
    required this.locator,
    required this.network,
    required this.reauthenticate,
  });

  @override
  State<_P2pPage> createState() => _P2pPageState();
}

class _P2pPageState extends State<_P2pPage> {
  P2pDestination _destination = P2pDestination.offers;

  /// How long a tap on an order of the book waits for the active trades' read.
  static const Duration _activeTradesWait = Duration(seconds: 10);

  /// Whether a tap on an order waits for the active trades' read: another tap meanwhile does nothing, so that one page opens (second security review of #182, R11); the tab shows the wait (#207).
  bool _waitingForTrades = false;

  void _show(P2pDestination destination) =>
      setState(() => _destination = destination);

  /// Opens the page of [order], and the Garage when that page is left for it (« I have a Garage Key »); an order this device made opens its trade instead, never « Take Order » ([ActiveTradesListed.madeHere], design note § 3.7, #182). While the active trades are being read, their read is awaited first (at most [_activeTradesWait]); records that cannot be read (or a read that does not end) open the order's page without « Take Order », since the order may be this device's (security review of #182, R3).
  Future<void> _openOrder(
    BuildContext context,
    PublicOrder order,
    RobosatsNetwork network,
    ActiveTradesState? active,
  ) async {
    if (_waitingForTrades) return;
    var known = active;
    if (known is ActiveTradesLoading) {
      final cubit = context.read<ActiveTradesCubit>();
      known = cubit.state;
      if (known is ActiveTradesLoading) {
        setState(() => _waitingForTrades = true);
        try {
          known = await cubit.stream
              .firstWhere((state) => state is! ActiveTradesLoading)
              .timeout(_activeTradesWait, onTimeout: () => cubit.state)
              .catchError((Object _) => cubit.state);
        } finally {
          _waitingForTrades = false;
          if (mounted) setState(() {});
        }
      }
      if (!mounted || !context.mounted) return;
    }
    if (known case ActiveTradesListed()) {
      if (known.madeHere(order, network) case final record?) {
        return _openTrade(context, record);
      }
    }
    final exit = await context.pushNamed<P2pOrderExit>(
      P2pRouter.orderName,
      extra: P2pOrderRouteArgs(
        order,
        network,
        takeable: known == null || known is ActiveTradesListed,
      ),
    );
    if (exit == P2pOrderExit.garage && mounted) _show(P2pDestination.garage);
  }

  /// The page of order [orderId] of [coordinator], which the books do not list, for its robot to read (#245), and the Garage when that page is left for it.
  Future<void> _openProtected(
    BuildContext context,
    Coordinator coordinator,
    int orderId,
    RobosatsNetwork network,
  ) async {
    final exit = await context.pushNamed<P2pOrderExit>(
      P2pRouter.unlistedOrderName,
      extra: P2pUnlistedOrderRouteArgs(coordinator, orderId, network),
    );
    if (exit == P2pOrderExit.garage && mounted) _show(P2pDestination.garage);
  }

  /// The page of the trade of [record], with the book the tab received for a maker's public order (#182), and the Garage when that page is left for it.
  Future<void> _openTrade(BuildContext context, TradeRecord record) async {
    final book = context.read<BookCubit>().state;
    final exit = await context.pushNamed<P2pOrderExit>(
      P2pRouter.tradeName,
      extra: P2pTradeRouteArgs(
        record,
        book: book.hasBookReceived ? book.receivedOrders.toList() : null,
      ),
    );
    if (exit == P2pOrderExit.garage && mounted) _show(P2pDestination.garage);
  }

  /// The create form (#182), started from the book of the tab, and the Garage when it is left for it.
  Future<void> _openCreate(BuildContext context) async {
    final exit = await context.pushNamed<P2pOrderExit>(
      P2pRouter.createName,
      extra: P2pCreateRouteArgs.fromBook(context.read<BookCubit>().state),
    );
    if (exit == P2pOrderExit.garage && mounted) _show(P2pDestination.garage);
  }

  /// « Order »: the list of the active trades and pending makes, with « Create order » at its top where an order can be made (#182, design note § 7, proposal 9); without it, the active trade alone, or the list when there are several or the records cannot be read.
  void _openTrades(
    BuildContext context,
    ActiveTradesState active,
    PendingMakesCubit? pending,
  ) {
    void open(TradeRecord record) => unawaited(_openTrade(context, record));
    final onCreate = pending == null
        ? null
        : () => unawaited(_openCreate(context));
    switch (active) {
      case ActiveTradesListed(active: [final only]) when pending == null:
        open(only.record);
      case ActiveTradesListed(:final active):
        unawaited(
          ActiveTradesSheet.show(
            context,
            active: active,
            onOpen: open,
            onCreate: onCreate,
            pending: pending,
          ),
        );
      case ActiveTradesUnreadable():
        unawaited(
          ActiveTradesSheet.show(
            context,
            active: null,
            onOpen: open,
            onCreate: onCreate,
            pending: pending,
          ),
        );
      case ActiveTradesLoading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locator = widget.locator;
    final current = widget.network(context);
    // Once per network and run of the app, in the background, where the relays were lent (#81): the first reading of the recovery note of the key new trades take on this network, and the note of every Garage Key in use here written again on the relays; nothing waits for it, nothing is shown.
    if (locator.isRegistered<RecoveryNoteSync>()) {
      locator<RecoveryNoteSync>().opened(current);
    }
    // Registered only when the shell gave the feature the vault's handle: otherwise the Garage is disabled and nothing reads the vault.
    final hasGarage = locator.isRegistered<GarageCubit>();
    final hasTrades = locator.isRegistered<ActiveTradesCubit>();
    // Registered with the trades: the feature can make an order (#182).
    final makes = hasTrades && locator.isRegistered<PendingMakesCubit>();
    // Registered with the trades: « Last order #N » in the Garage (#216).
    final lastOrders = hasTrades && locator.isRegistered<LastOrdersCubit>();
    Widget tab(
      BuildContext context, {
      ActiveTradesState? active,
      VoidCallback? onOpenTrades,
      VoidCallback? onCreate,
    }) => P2pTabScreen(
      now: locator<P2pClock>().now,
      shuffle: locator<P2pShuffle>(),
      onOpenOrder: (order) =>
          unawaited(_openOrder(context, order, current, active)),
      onOpenProtected: hasTrades && locator.isRegistered<UnlistedOrderCubit>()
          ? (coordinator, orderId) => unawaited(
              _openProtected(context, coordinator, orderId, current),
            )
          : null,
      coordinatorDetails: (request) =>
          locator<CoordinatorDetailsCubit>(param1: request),
      // The tiles of the book's map (#246), opened only once its « Show tiles » is on and acknowledged.
      openTiles: locator<OpenMapTilesUsecase>().execute,
      destination: _destination,
      onDestination: _show,
      onOpenTrades: onOpenTrades,
      onCreate: onCreate,
      waitingForTrades: _waitingForTrades,
      garage: hasGarage
          ? (context) {
              final view = GarageView(
                clipboard: locator<GarageKeyClipboard>(),
                reauthenticate: widget.reauthenticate,
                robotCoordinator: (key, index) =>
                    locator<RobotCoordinatorCubit>(param1: key, param2: index),
                coordinatorDetails: (request) =>
                    locator<CoordinatorDetailsCubit>(param1: request),
                // « Last order #N » (#216): the trade of the last finished orders, opened above the tab as from « Active trades ».
                onOpenTrade: lastOrders
                    ? (record) => _openTrade(context, record)
                    : null,
                // The history of finished orders under those lines (#253), registered with them.
                orderHistory:
                    lastOrders && locator.isRegistered<OrderHistoryCubit>()
                    ? (key) => locator<OrderHistoryCubit>(param1: key)
                    : null,
              );
              return BlocProvider(
                // A new Garage for each network, which reads the key of that network only when it is shown.
                key: ValueKey(current),
                create: (_) => locator<GarageCubit>(param1: current)..load(),
                child: lastOrders
                    ? BlocProvider(
                        // The last finished orders of the network, read from the device only while the Garage is shown (#216).
                        key: ValueKey(('last', current)),
                        create: (_) =>
                            locator<LastOrdersCubit>(param1: current)..start(),
                        child: view,
                      )
                    : view,
              );
            }
          : null,
    );
    // The middle entry: « Order » while the network has an active trade or a pending make, which opens them; else « Create », which opens the form where an order can be made (#182).
    Widget middleEntry(
      BuildContext context,
      PendingMakesCubit? pending,
    ) => BlocBuilder<ActiveTradesCubit, ActiveTradesState>(
      builder: (context, active) {
        final pendingState = pending == null
            ? null
            : context.watch<PendingMakesCubit>().state;
        final hasPending =
            pendingState != null &&
            (pendingState.unreadable ||
                (pendingState.makes?.isNotEmpty ?? false));
        final opens = switch (active) {
          ActiveTradesListed(active: []) => hasPending,
          ActiveTradesLoading() => false,
          _ => true,
        };
        return tab(
          context,
          active: active,
          onOpenTrades: opens
              ? () => _openTrades(context, active, pending)
              : null,
          // Not while the records are being read: « Create » is for a network known to have no active trade nor pending make (functional review R8).
          onCreate:
              pending != null &&
                  !opens &&
                  active is! ActiveTradesLoading &&
                  pendingState?.makes != null
              ? () => unawaited(_openCreate(context))
              : null,
        );
      },
    );
    return BlocProvider(
      key: ValueKey(current),
      create: (_) => locator<BookCubit>(param1: current)..start(),
      child: hasTrades
          ? BlocProvider(
              // The active trades of the network, read from the device only: nothing is asked of a coordinator until a trade is opened, whose page holds the trade's only watch.
              key: ValueKey(('trades', current)),
              create: (_) =>
                  locator<ActiveTradesCubit>(param1: current)..start(),
              child: makes
                  ? BlocProvider(
                      // The pending makes of the network, read from the device only: resolved when « Active trades » or the form opens (#182).
                      key: ValueKey(('makes', current)),
                      create: (_) =>
                          locator<PendingMakesCubit>(param1: current)..start(),
                      child: Builder(
                        builder: (context) => middleEntry(
                          context,
                          context.read<PendingMakesCubit>(),
                        ),
                      ),
                    )
                  : Builder(builder: (context) => middleEntry(context, null)),
            )
          : Builder(builder: tab),
    );
  }
}
