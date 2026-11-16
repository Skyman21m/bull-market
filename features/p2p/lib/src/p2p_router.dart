import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:robosats/robosats.dart';

import 'domain/p2p_clock.dart';
import 'domain/p2p_shuffle.dart';
import 'domain/trade/trade_watch.dart';
import 'domain/trade_record.dart';
import 'p2p_locator.dart';
import 'presentation/active_trades_cubit.dart';
import 'presentation/bond_payment_cubit.dart';
import 'presentation/book_cubit.dart';
import 'presentation/chat_cubit.dart';
import 'presentation/coordinator_details_cubit.dart';
import 'presentation/garage_cubit.dart';
import 'presentation/order_details_cubit.dart';
import 'presentation/payout_cubit.dart';
import 'presentation/payout_wallet_cubit.dart';
import 'presentation/robot_coordinator_cubit.dart';
import 'presentation/take_order_cubit.dart';
import 'presentation/trade_cubit.dart';
import 'presentation/trade_order_page_cubit.dart';
import 'ui/garage/garage_reauthentication.dart';
import 'ui/garage/garage_view.dart';
import 'ui/order_details_screen.dart';
import 'ui/p2p_tab_screen.dart';
import 'ui/trade/active_trades_sheet.dart';
import 'ui/trade/bond_payment_panel.dart';
import 'ui/trade/chat_actions.dart';
import 'ui/trade/chat_panel.dart';
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

  const P2pOrderRouteArgs(this.order, this.network);
}

/// What the page of a trade needs: the trade's record, from a take or the list of the active trades.
///
/// The page of a trade is reached from those only: without it, as after a deep link or a restored session, it sends back to the tab, whose « Order » entry lists the active trades.
final class P2pTradeRouteArgs {
  final TradeRecord record;

  const P2pTradeRouteArgs(this.record);
}

/// What the page of an order gives back when it is left for the Garage (« I have a Garage Key »).
enum P2pOrderExit { garage }

/// The routes of the P2P tab: the book and the Garage, and the page of an order and the page of a trade above them.
final class P2pRouter {
  static const path = '/p2p';
  static const name = 'p2p';
  static const orderName = 'p2pOrder';
  static const tradeName = 'p2pTrade';

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
    ],
  );

  /// The page of a trade: its watch, its order's page, and, when the feature holds robots, its payout panel's cubit, each one per shown trade and closed with the page (which lets the robot's key go).
  @visibleForTesting
  static Widget tradePage(GetIt locator, P2pTradeRouteArgs args) {
    final payouts = locator.isRegistered<PayoutCubit>();
    final chats = locator.isRegistered<ChatCubit>();
    return MultiBlocProvider(
      providers: [
        // The wallet's payment of the bond (#100), only where the wallet's port was lent: without it the screen is as before, « Pay with another wallet » alone.
        if (P2pLocator.paysBondFromWallet(locator))
          BlocProvider(
            create: (_) =>
                locator<BondPaymentCubit>(param1: args.record)..start(),
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
            coordinatorDetails: (request) =>
                locator<CoordinatorDetailsCubit>(param1: request),
            payout: payouts
                ? (context, request) => PayoutPanel(
                    request: request,
                    wallet: P2pLocator.paysBondFromWallet(locator)
                        ? PayoutWalletSection.slotFor
                        : null,
                  )
                : null,
            chat: chats
                ? (context, request) => ChatPanel(request: request)
                : null,
            // « Audit Chat » and « Export » in « Order options » (#157), over the same chat cubit as the panel.
            chatOptions: chats ? chatOptionsOf : null,
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
          ),
        ),
      ),
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

  /// The page of an order: « Take Order » takes it when the feature holds robots (the vault's handle was given), and a take that was sent replaces the page by its trade, as the official client's order page becomes the trade at the same address.
  static Widget _orderPage(GetIt locator, P2pOrderRouteArgs args) {
    final canTake = locator.isRegistered<TakeOrderCubit>();
    final details = Builder(
      builder: (context) => OrderDetailsScreen(
        now: locator<P2pClock>().now,
        coordinatorDetails: (request) =>
            locator<CoordinatorDetailsCubit>(param1: request),
        canTake: canTake,
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
            create: (_) => locator<TakeOrderCubit>(
              param1: args.order,
              param2: args.network,
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

  void _show(P2pDestination destination) =>
      setState(() => _destination = destination);

  /// Opens the page of [order], and the Garage when that page is left for it (« I have a Garage Key »).
  Future<void> _openOrder(
    BuildContext context,
    PublicOrder order,
    RobosatsNetwork network,
  ) async {
    final exit = await context.pushNamed<P2pOrderExit>(
      P2pRouter.orderName,
      extra: P2pOrderRouteArgs(order, network),
    );
    if (exit == P2pOrderExit.garage && mounted) _show(P2pDestination.garage);
  }

  /// « Order »: the active trade, or the list of them when there are several or the records cannot be read.
  void _openTrades(BuildContext context, ActiveTradesState active) {
    Future<void> open(TradeRecord record) async {
      final exit = await context.pushNamed<P2pOrderExit>(
        P2pRouter.tradeName,
        extra: P2pTradeRouteArgs(record),
      );
      if (exit == P2pOrderExit.garage && mounted) {
        _show(P2pDestination.garage);
      }
    }

    switch (active) {
      case ActiveTradesListed(active: [final only]):
        unawaited(open(only.record));
      case ActiveTradesListed(:final active):
        unawaited(
          ActiveTradesSheet.show(
            context,
            active: active,
            onOpen: (record) => unawaited(open(record)),
          ),
        );
      case ActiveTradesUnreadable():
        unawaited(
          ActiveTradesSheet.show(
            context,
            active: null,
            onOpen: (record) => unawaited(open(record)),
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
    // Registered only when the shell gave the feature the vault's handle: otherwise the Garage is disabled and nothing reads the vault.
    final hasGarage = locator.isRegistered<GarageCubit>();
    final hasTrades = locator.isRegistered<ActiveTradesCubit>();
    Widget tab({VoidCallback? onOpenTrades}) => P2pTabScreen(
      now: locator<P2pClock>().now,
      shuffle: locator<P2pShuffle>(),
      onOpenOrder: (order) => unawaited(_openOrder(context, order, current)),
      coordinatorDetails: (request) =>
          locator<CoordinatorDetailsCubit>(param1: request),
      destination: _destination,
      onDestination: _show,
      onOpenTrades: onOpenTrades,
      garage: hasGarage
          ? (context) => BlocProvider(
              // A new Garage for each network, which reads the key of that network only when it is shown.
              key: ValueKey(current),
              create: (_) => locator<GarageCubit>(param1: current)..load(),
              child: GarageView(
                clipboard: locator<GarageKeyClipboard>(),
                reauthenticate: widget.reauthenticate,
                onBrowseOffers: () => _show(P2pDestination.offers),
                robotCoordinator: (key, index) =>
                    locator<RobotCoordinatorCubit>(param1: key, param2: index),
                coordinatorDetails: (request) =>
                    locator<CoordinatorDetailsCubit>(param1: request),
              ),
            )
          : null,
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
              child: BlocBuilder<ActiveTradesCubit, ActiveTradesState>(
                builder: (context, active) => tab(
                  onOpenTrades: switch (active) {
                    ActiveTradesListed(active: []) ||
                    ActiveTradesLoading() => null,
                    _ => () => _openTrades(context, active),
                  },
                ),
              ),
            )
          : tab(),
    );
  }
}
