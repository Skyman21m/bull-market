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

/// The P2P tab: the wait for Tor, then the book.
class P2pTabScreen extends StatelessWidget {
  final DateTime Function() now;
  final ValueChanged<PublicOrder> onOpenOrder;

  const P2pTabScreen({super.key, required this.now, required this.onOpenOrder});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final network = context.select((BookCubit cubit) => cubit.state.network);
    return Material(
      color: colors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (network == RobosatsNetwork.testnet) const TestnetBanner(),
            BullTopBar(title: l10n.p2pTabLabel),
            Expanded(
              child: BlocBuilder<BookCubit, BookState>(
                buildWhen: (previous, current) => previous.tor != current.tor,
                builder: (context, state) => switch (state.tor) {
                  TorWait.ready => BookView(now: now, onOpenOrder: onOpenOrder),
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
