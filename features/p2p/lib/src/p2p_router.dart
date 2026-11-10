import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:robosats/robosats.dart';

import 'domain/p2p_clock.dart';
import 'presentation/book_cubit.dart';
import 'presentation/order_details_cubit.dart';
import 'ui/order_details_screen.dart';
import 'ui/p2p_tab_screen.dart';

/// What the page of an order needs: the order as the book listed it, and the network of its book.
///
/// The page of an order is reached from the book only: without these, as after a deep link or a restored session, it sends back to the book.
final class P2pOrderRouteArgs {
  final PublicOrder order;
  final RobosatsNetwork network;

  const P2pOrderRouteArgs(this.order, this.network);
}

/// The routes of the P2P tab: the book, and the page of an order above it.
final class P2pRouter {
  static const path = '/p2p';
  static const name = 'p2p';
  static const orderName = 'p2pOrder';

  /// Whether [location] is a page of the P2P tab.
  static bool isP2pPath(String location) =>
      location == path || location.startsWith('$path/');

  /// [network] is read from the context of the page each time it builds, so the book follows a change of network.
  static GoRoute route(
    GetIt locator,
    RobosatsNetwork Function(BuildContext context) network,
  ) => GoRoute(
    name: name,
    path: path,
    builder: (context, state) => _BookPage(locator: locator, network: network),
    routes: [
      GoRoute(
        name: orderName,
        path: 'order',
        redirect: (context, state) =>
            state.extra is P2pOrderRouteArgs ? null : path,
        builder: (context, state) => switch (state.extra) {
          final P2pOrderRouteArgs args => BlocProvider(
            create: (_) => locator<OrderDetailsCubit>(
              param1: args.order,
              param2: args.network,
            )..load(),
            child: OrderDetailsScreen(now: locator<P2pClock>().now),
          ),
          _ => const SizedBox.shrink(),
        },
      ),
    ],
  );
}

class _BookPage extends StatelessWidget {
  final GetIt locator;
  final RobosatsNetwork Function(BuildContext context) network;

  const _BookPage({required this.locator, required this.network});

  @override
  Widget build(BuildContext context) {
    final current = network(context);
    return BlocProvider(
      key: ValueKey(current),
      create: (_) => locator<BookCubit>(param1: current)..start(),
      child: P2pTabScreen(
        now: locator<P2pClock>().now,
        onOpenOrder: (order) => context.pushNamed(
          P2pRouter.orderName,
          extra: P2pOrderRouteArgs(order, current),
        ),
      ),
    );
  }
}
