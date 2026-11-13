import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:robosats/robosats.dart';

import 'domain/p2p_clock.dart';
import 'domain/p2p_shuffle.dart';
import 'presentation/book_cubit.dart';
import 'presentation/coordinator_details_cubit.dart';
import 'presentation/garage_cubit.dart';
import 'presentation/order_details_cubit.dart';
import 'presentation/robot_coordinator_cubit.dart';
import 'ui/garage/garage_reauthentication.dart';
import 'ui/garage/garage_view.dart';
import 'ui/order_details_screen.dart';
import 'ui/p2p_tab_screen.dart';
import 'ui/widgets/garage_key_clipboard.dart';

/// What the page of an order needs: the order as the book listed it, and the network of its book.
///
/// The page of an order is reached from the book only: without these, as after a deep link or a restored session, it sends back to the book.
final class P2pOrderRouteArgs {
  final PublicOrder order;
  final RobosatsNetwork network;

  const P2pOrderRouteArgs(this.order, this.network);
}

/// The routes of the P2P tab: the book and the Garage, and the page of an order above them.
final class P2pRouter {
  static const path = '/p2p';
  static const name = 'p2p';
  static const orderName = 'p2pOrder';

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
          final P2pOrderRouteArgs args => BlocProvider(
            create: (_) => locator<OrderDetailsCubit>(
              param1: args.order,
              param2: args.network,
            )..load(),
            child: OrderDetailsScreen(
              now: locator<P2pClock>().now,
              coordinatorDetails: (request) =>
                  locator<CoordinatorDetailsCubit>(param1: request),
            ),
          ),
          _ => const SizedBox.shrink(),
        },
      ),
    ],
  );
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

  @override
  Widget build(BuildContext context) {
    final locator = widget.locator;
    final current = widget.network(context);
    // Registered only when the shell gave the feature the vault's handle: otherwise the Garage is disabled and nothing reads the vault.
    final hasGarage = locator.isRegistered<GarageCubit>();
    return BlocProvider(
      key: ValueKey(current),
      create: (_) => locator<BookCubit>(param1: current)..start(),
      child: P2pTabScreen(
        now: locator<P2pClock>().now,
        shuffle: locator<P2pShuffle>(),
        onOpenOrder: (order) => context.pushNamed(
          P2pRouter.orderName,
          extra: P2pOrderRouteArgs(order, current),
        ),
        destination: _destination,
        onDestination: _show,
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
                      locator<RobotCoordinatorCubit>(
                        param1: key,
                        param2: index,
                      ),
                  coordinatorDetails: (request) =>
                      locator<CoordinatorDetailsCubit>(param1: request),
                ),
              )
            : null,
      ),
    );
  }
}
