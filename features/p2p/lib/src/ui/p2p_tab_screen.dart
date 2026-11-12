import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/tor_wait.dart';
import '../presentation/book_cubit.dart';
import '../presentation/book_state.dart';
import 'book_view.dart';
import 'tor_wait_view.dart';
import 'widgets/testnet_banner.dart';

/// The destinations of the P2P tab that can be shown: « Create » comes in a later phase.
enum P2pDestination { offers, garage }

/// The P2P tab: « Offers », « Create » and « Garage » at the top, as the official client's bottom bar, then the destination chosen.
///
/// « Offers » is the wait for Tor, then the book; « Create » is disabled; « Garage » is [garage], which needs no network and so is there while Tor connects.
/// Without [garage], when the feature was set up without the vault's handle, « Garage » is disabled.
class P2pTabScreen extends StatelessWidget {
  final DateTime Function() now;
  final ValueChanged<PublicOrder> onOpenOrder;
  final P2pDestination destination;
  final ValueChanged<P2pDestination> onDestination;
  final WidgetBuilder? garage;

  const P2pTabScreen({
    super.key,
    required this.now,
    required this.onOpenOrder,
    required this.destination,
    required this.onDestination,
    required this.garage,
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
              child: BullSegmented(
                items: {
                  l10n.p2pNavOffers,
                  l10n.p2pNavCreate,
                  l10n.p2pNavGarage,
                },
                initialValue: showsGarage
                    ? l10n.p2pNavGarage
                    : l10n.p2pNavOffers,
                disabledItems: {
                  l10n.p2pNavCreate,
                  if (garage == null) l10n.p2pNavGarage,
                },
                onSelected: (item) {
                  if (item == l10n.p2pNavOffers) {
                    onDestination(P2pDestination.offers);
                  } else if (item == l10n.p2pNavGarage) {
                    onDestination(P2pDestination.garage);
                  }
                },
              ),
            ),
            const Gap(BullSpacing.sm),
            Expanded(
              child: showsGarage
                  ? garage(context)
                  : BlocBuilder<BookCubit, BookState>(
                      buildWhen: (previous, current) =>
                          previous.tor != current.tor,
                      builder: (context, state) => switch (state.tor) {
                        TorWait.ready => BookView(
                          now: now,
                          onOpenOrder: onOpenOrder,
                          onOpenGarage: garage == null
                              ? null
                              : () => onDestination(P2pDestination.garage),
                        ),
                        final tor => TorWaitView(
                          tor: tor,
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
