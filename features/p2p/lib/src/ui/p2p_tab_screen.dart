import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/p2p_shuffle.dart';
import '../domain/tor_wait.dart';
import '../presentation/book_cubit.dart';
import '../presentation/book_state.dart';
import '../presentation/coordinator_details_cubit.dart';
import 'book_view.dart';
import 'tor_wait_view.dart';
import 'widgets/testnet_banner.dart';

/// The destinations of the P2P tab that can be shown: « Create » opens a page of its own (#182).
enum P2pDestination { offers, garage }

/// The P2P tab: « Offers », « Create » and « Garage » at the top, as the official client's bottom bar, then the destination chosen.
///
/// « Offers » is the wait for Tor, then the book; « Create » opens the create form ([onCreate], #182), disabled where the feature cannot make an order; « Garage » is [garage], which needs no network and so is there while Tor connects.
/// Without [garage], when the feature was set up without the vault's handle, « Garage » is disabled.
/// With an active trade on the network ([onOpenTrades] set), the middle entry is « Order » instead of « Create », as the middle button of the official client's phone bar becomes the order of the robot that has one (`basic/NavBar/AppBar/index.tsx:54-73`): it opens the trade, and is not a destination of its own.
class P2pTabScreen extends StatelessWidget {
  final DateTime Function() now;

  /// The order of the phrases of the Tor wait.
  final P2pShuffle shuffle;
  final ValueChanged<PublicOrder> onOpenOrder;

  /// The cubit of the dialog of a coordinator, which a tap on its image above the book opens.
  final CoordinatorDetailsCubit Function(CoordinatorDetailsRequest request)
  coordinatorDetails;
  final P2pDestination destination;
  final ValueChanged<P2pDestination> onDestination;
  final WidgetBuilder? garage;

  /// Opens the active trade, or the list of them: set while the network has one.
  final VoidCallback? onOpenTrades;

  /// Opens the create form (#182): set where the feature can make an order and the network has no active trade nor pending make (« Create order » is then in the list « Order » opens).
  final VoidCallback? onCreate;

  const P2pTabScreen({
    super.key,
    required this.now,
    required this.shuffle,
    required this.onOpenOrder,
    required this.coordinatorDetails,
    required this.destination,
    required this.onDestination,
    required this.garage,
    this.onOpenTrades,
    this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final network = context.select((BookCubit cubit) => cubit.state.network);
    final garage = this.garage;
    final showsGarage = destination == P2pDestination.garage && garage != null;
    return Material(
      color: colors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (network == RobosatsNetwork.testnet) const TestnetBanner(),
            const Gap(BullSpacing.xs),
            BullTopBar(title: l10n.p2pTabLabel),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: BullSpacing.md),
              child: _Entries(
                showsGarage: showsGarage,
                hasGarage: garage != null,
                onDestination: onDestination,
                onOpenOrder: onOpenTrades,
                onCreate: onCreate,
              ),
            ),
            const Gap(BullSpacing.sm),
            Expanded(
              child: showsGarage
                  ? garage(context)
                  : BlocBuilder<BookCubit, BookState>(
                      buildWhen: (previous, current) =>
                          previous.tor != current.tor ||
                          previous.torPercent != current.torPercent,
                      builder: (context, state) => switch (state.tor) {
                        TorWait.ready => BookView(
                          now: now,
                          onOpenOrder: onOpenOrder,
                          coordinatorDetails: coordinatorDetails,
                          onOpenGarage: garage == null
                              ? null
                              : () => onDestination(P2pDestination.garage),
                        ),
                        final tor => TorWaitView(
                          tor: tor,
                          percent: state.torPercent,
                          shuffle: shuffle,
                          onRetry: context.read<BookCubit>().retryTor,
                        ),
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The entries at the top of the tab; « Order », which opens a page rather than showing a destination, puts the bar back on the destination shown once chosen.
class _Entries extends StatefulWidget {
  final bool showsGarage;
  final bool hasGarage;
  final ValueChanged<P2pDestination> onDestination;
  final VoidCallback? onOpenOrder;
  final VoidCallback? onCreate;

  const _Entries({
    required this.showsGarage,
    required this.hasGarage,
    required this.onDestination,
    required this.onOpenOrder,
    required this.onCreate,
  });

  @override
  State<_Entries> createState() => _EntriesState();
}

class _EntriesState extends State<_Entries> {
  /// How many times « Order » or « Create » was chosen, the key that puts the bar back on the destination shown.
  int _orders = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final onOpenOrder = widget.onOpenOrder;
    final onCreate = widget.onCreate;
    final middle = onOpenOrder == null ? l10n.p2pNavCreate : l10n.p2pNavOrder;
    return BullSegmented(
      key: ValueKey(_orders),
      items: {l10n.p2pNavOffers, middle, l10n.p2pNavGarage},
      initialValue: widget.showsGarage ? l10n.p2pNavGarage : l10n.p2pNavOffers,
      disabledItems: {
        if (onOpenOrder == null && onCreate == null) l10n.p2pNavCreate,
        if (!widget.hasGarage) l10n.p2pNavGarage,
      },
      onSelected: (item) {
        if (item == l10n.p2pNavOffers) {
          widget.onDestination(P2pDestination.offers);
        } else if (item == l10n.p2pNavGarage) {
          widget.onDestination(P2pDestination.garage);
        } else if (onOpenOrder != null && item == l10n.p2pNavOrder) {
          setState(() => _orders++);
          onOpenOrder();
        } else if (onCreate != null && item == l10n.p2pNavCreate) {
          setState(() => _orders++);
          onCreate();
        }
      },
    );
  }
}
