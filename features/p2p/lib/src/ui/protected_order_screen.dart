import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/trade/trade_take.dart';
import '../domain/trade_record.dart';
import '../presentation/coordinator_text.dart';
import '../presentation/protected_order_cubit.dart';
import '../presentation/take_order_cubit.dart';
import '../presentation/trade_l10n.dart';
import 'widgets/order_detail_row.dart';
import 'widgets/testnet_banner.dart';
import 'widgets/trade_button.dart';

/// The page of an order that the public book does not list, such as a password-protected one, reached by its URL (« Search order », #245), as the reference's order page reads it with the user's robot (`basic/OrderPage/index.tsx:75-96`).
///
/// While the robot that will take the order reads it: the host and the number, a bar named « Take Order » and a line for each step (« Building your robot! », the reference's words for a robot made, then the order read), and after 30 s that it still waits.
/// Once read, [details] builds the page of the order as its robot read it, the order details of an order of the book with « Password » and « Take Order » ([ProtectedOrderShown]).
/// An order with an open trade here opens that trade ([onTraded]); a read refused says why under the host, in words of the app, with « Retry » when another read may give the order (never for an order gone: « This order is not available »).
class ProtectedOrderScreen extends StatelessWidget {
  final Widget Function(ProtectedOrder order) details;
  final ValueChanged<TradeRecord> onTraded;

  const ProtectedOrderScreen({
    super.key,
    required this.details,
    required this.onTraded,
  });

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProtectedOrderCubit, ProtectedOrderState>(
      listenWhen: (_, current) => current is ProtectedOrderTraded,
      listener: (_, state) {
        if (state is ProtectedOrderTraded) onTraded(state.record);
      },
      buildWhen: (previous, current) =>
          current is! ProtectedOrderShown || previous is! ProtectedOrderShown,
      builder: (context, state) => switch (state) {
        ProtectedOrderShown(:final order) => details(order),
        _ => _Reading(state: state),
      },
    );
  }
}

/// The page before the order is shown: its host and number, the read in progress or why it failed.
class _Reading extends StatelessWidget {
  final ProtectedOrderState state;

  const _Reading({required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final cubit = context.read<ProtectedOrderCubit>();
    final coordinator = CoordinatorText.of(
      cubit.coordinator.longAlias,
      maxCodePoints: CoordinatorText.name,
    );
    Widget line(String value, {Color? color}) => Semantics(
      container: true,
      liveRegion: true,
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: text.bodyMedium?.copyWith(color: color ?? colors.textMuted),
      ),
    );
    final state = this.state;
    return Material(
      color: colors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (cubit.network == RobosatsNetwork.testnet) const TestnetBanner(),
            const Gap(BullSpacing.xs),
            BullTopBar(
              title: l10n.p2pNavOrder,
              onBack: () {
                if (context.canPop()) context.pop();
              },
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(BullSpacing.md),
                children: [
                  OrderHostRow(
                    coordinator: cubit.coordinator,
                    orderId: cubit.orderId,
                  ),
                  const Gap(BullSpacing.lg),
                  ...switch (state) {
                    ProtectedOrderReading(:final step, :final slow) => [
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: LinearProgressIndicator(
                          color: colors.primary,
                          semanticsLabel: l10n.p2pTakeOrder,
                        ),
                      ),
                      if (step != null) ...[
                        const Gap(BullSpacing.xs),
                        line(step.toText(context, coordinator: coordinator)),
                      ],
                      if (slow) ...[
                        const Gap(BullSpacing.xs),
                        line(l10n.p2pRobotStillWaiting(coordinator)),
                      ],
                    ],
                    final ProtectedOrderRefused refused => [
                      line(
                        TakeWasRefused(
                          refused.refusal,
                        ).toText(context, coordinator: coordinator),
                        color: colors.error,
                      ),
                      if (refused.canRetry) ...[
                        const Gap(BullSpacing.md),
                        TradeButton(
                          label: l10n.p2pCommonRetry,
                          outlined: true,
                          onPressed: cubit.retry,
                        ),
                      ],
                    ],
                    ProtectedOrderShown() || ProtectedOrderTraded() => [
                      const Center(child: CircularProgressIndicator()),
                    ],
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
