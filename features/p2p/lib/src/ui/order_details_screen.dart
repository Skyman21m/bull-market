import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/trade_record.dart';
import '../presentation/coordinator_details_cubit.dart';
import '../presentation/order_details_cubit.dart';
import '../presentation/p2p_formats.dart';
import 'coordinator_details_dialog.dart';
import 'take_order_section.dart';
import 'widgets/offer_row.dart';
import 'widgets/order_detail_row.dart';
import 'widgets/reversible_payments_dialog.dart';
import 'widgets/robot_avatar.dart';
import 'widgets/testnet_banner.dart';

/// The details of a public order, in the order of the official client: host and number, fees, then the order details, the maker and « Take Order ».
///
/// The host opens the dialog of its coordinator, as in the official client.
/// « Take Order » is [TakeOrderSection] (#88): with [canTake], a `TakeOrderCubit` above this screen takes the order, and [onTaken] opens its trade.
class OrderDetailsScreen extends StatefulWidget {
  final DateTime Function() now;

  /// Builds the cubit of the coordinator dialog.
  final CoordinatorDetailsCubit Function(CoordinatorDetailsRequest request)
  coordinatorDetails;

  /// Whether a `TakeOrderCubit` is above this screen: the feature holds robots only when it was set up with the vault's handle.
  final bool canTake;

  /// Opens the Garage from « You do not have a Garage Key », when the tab has one.
  final VoidCallback? onOpenGarage;

  /// Opens the trade a take started: always given by the route, which [canTake] needs.
  final ValueChanged<TradeRecord>? onTaken;

  const OrderDetailsScreen({
    super.key,
    required this.now,
    required this.coordinatorDetails,
    this.canTake = false,
    this.onOpenGarage,
    this.onTaken,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  late DateTime _now;

  /// Moves the countdown on, every second as in the official client.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _now = widget.now();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = widget.now()),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final state = context.watch<OrderDetailsCubit>().state;
    final order = state.order;
    return Material(
      color: colors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (state.network == RobosatsNetwork.testnet) const TestnetBanner(),
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
                    coordinator: order.coordinator,
                    orderId: order.id,
                    // The fees the page already read are shown at once in the dialog, which asks the coordinator only when the page has none.
                    onTap: () => CoordinatorDetailsDialog.show(
                      context,
                      () => widget.coordinatorDetails(
                        CoordinatorDetailsRequest(
                          order.coordinator,
                          state.network,
                          known: context.read<OrderDetailsCubit>().state.info,
                        ),
                      ),
                    ),
                  ),
                  const Gap(BullSpacing.sm),
                  _FeeRow(info: state.info),
                  const Gap(BullSpacing.sm),
                  _DetailsCard(state: state, now: _now),
                  const Gap(BullSpacing.md),
                  _MakerRow(order: order),
                  const Gap(BullSpacing.md),
                  TakeOrderSection(
                    order: order,
                    takerFee: state.info?.takerFee ?? 0,
                    canTake: widget.canTake,
                    onOpenGarage: widget.onOpenGarage,
                    onTaken: widget.onTaken ?? (_) {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// « M 0.025% · T 0.175% » and the on-chain payout fee, as the coordinator announces them; nothing until it answers.
class _FeeRow extends StatelessWidget {
  final CoordinatorInfo? info;

  const _FeeRow({required this.info});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final info = this.info;
    final style = text.labelLarge?.copyWith(color: colors.textMuted);
    if (info == null) return SizedBox(height: style?.fontSize ?? 12);
    final swapRate = info.currentSwapFeeRate;
    return Wrap(
      spacing: BullSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Tooltip(
          message: l10n.p2pOrderFeeMakerTooltip,
          child: Text(
            '${_initial(l10n.p2pOrderFeeMaker)} ${formats.fee(info.makerFee)}',
            style: style,
          ),
        ),
        Text('·', style: style),
        Tooltip(
          message: l10n.p2pOrderFeeTakerTooltip,
          child: Text(
            '${_initial(l10n.p2pOrderFeeTaker)} ${formats.fee(info.takerFee)}',
            style: style,
          ),
        ),
        Text('·', style: style),
        Tooltip(
          message: info.swapEnabled
              ? l10n.p2pOrderOnchainEnabled
              : l10n.p2pOrderOnchainDisabled,
          child: info.swapEnabled && swapRate != null
              ? BullBadge(
                  label: formats.swapFee(swapRate),
                  icon: Icons.link,
                  background: colors.surfaceContainer,
                  foreground: colors.success,
                )
              : Icon(Icons.link_off, size: 16, color: colors.textMuted),
        ),
      ],
    );
  }

  /// The first letter of a role, as the official client writes the fee row.
  static String _initial(String word) =>
      word.isEmpty ? word : String.fromCharCode(word.runes.first);
}

/// « Order Details »: the amount, what the taker sends and receives, the payment methods, price and premium, expiry and deposit time.
class _DetailsCard extends StatelessWidget {
  final OrderDetailsState state;
  final DateTime now;

  const _DetailsCard({required this.state, required this.now});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final order = state.order;
    final code = order.currency.code;
    // A swap order is given in BTC, which the official client writes in sats.
    final amount = order.currency.isBitcoin
        ? l10n.p2pAmountSats(formats.btcAmountInSats(order.amount))
        : '${formats.orderAmount(order.amount)} $code';
    final estimate = state.estimate;
    final sats = estimate == null ? '-' : formats.estimate(estimate);
    final methods = order.paymentMethods.text;
    final (send, receive) = switch (order.type) {
      // The taker of a sell order buys bitcoin: pays fiat, receives sats.
      OrderType.sell => (
        OrderSentence.split(
          l10n.p2pOrderYouSendVia(methods, OrderSentence.mark),
          amount,
        ),
        OrderSentence.split(
          l10n.p2pOrderYouReceiveSats(OrderSentence.mark),
          sats,
        ),
      ),
      OrderType.buy => (
        OrderSentence.split(
          l10n.p2pOrderYouSendLightning(OrderSentence.mark),
          sats,
        ),
        OrderSentence.split(
          l10n.p2pOrderYouReceiveVia(methods, OrderSentence.mark),
          amount,
        ),
      ),
    };
    final total = order.expiresAt.difference(order.createdAt);
    final left = order.expiresAt.difference(now);
    final share = total.inMilliseconds <= 0 || left.isNegative
        ? 0.0
        : (left.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final price = order.price;
    final explicit = order.explicitSatoshis;
    final (priceLabel, priceValue) = price != null
        ? (
            l10n.p2pOrderPriceAndPremium,
            l10n.p2pOrderPriceAndPremiumValue(
              formats.price(price),
              code,
              formats.premiumNumber(order.premium),
            ),
          )
        : explicit != null
        ? (l10n.p2pOrderAmountOfSatoshis, formats.sats(explicit.value.toInt()))
        : (
            l10n.p2pOrderPremiumOverMarket,
            formats.premiumOverMarket(order.premium),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.p2pOrderDetailsDivider,
          style: text.labelLarge?.copyWith(color: colors.textMuted),
        ),
        const Gap(BullSpacing.xs),
        BullDetailsTable(
          items: [
            OrderDetailRow(
              order.amount is RangeOrderAmount
                  ? l10n.p2pOrderAmountRange
                  : l10n.p2pBookColumnAmount,
              amount,
            ),
            OrderDetailRow(send.label, send.value),
            OrderDetailRow(receive.label, receive.value),
            OrderDetailRow(
              order.currency.isBitcoin
                  ? l10n.p2pOrderSwapDestination
                  : l10n.p2pOrderAcceptedMethods,
              OfferRow.paymentMethodsLine(order.paymentMethods, l10n),
              warning: order.paymentMethods.hasReversible
                  ? () => ReversiblePaymentsDialog.show(
                      context,
                      order.paymentMethods,
                    )
                  : null,
            ),
            OrderDetailRow(priceLabel, priceValue),
            OrderDetailRow(
              l10n.p2pOrderExpiresIn,
              left.isNegative ? l10n.p2pOrderExpired : formats.countdown(left),
              color: share < 0.10
                  ? colors.error
                  : share < 0.25
                  ? colors.warning
                  : null,
              bold: share < 0.25,
            ),
            // The time left closes the card, under its last row, as in the official client.
            Column(
              children: [
                OrderDetailRow(
                  l10n.p2pOrderDeposit,
                  formats.depositTime(order.escrowDuration),
                ),
                const Gap(BullSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(BullRadius.xxs),
                  child: LinearProgressIndicator(
                    value: share,
                    minHeight: 4,
                    color: colors.primary,
                    backgroundColor: colors.surfaceContainer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// The maker of the order, with how recently its coordinator saw it.
class _MakerRow extends StatelessWidget {
  final PublicOrder order;

  const _MakerRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final activity = switch (order.makerActivity) {
      MakerActivity.active => l10n.p2pBookMakerStatusActive,
      MakerActivity.seenRecently => l10n.p2pBookMakerStatusSeenRecently,
      MakerActivity.inactive => l10n.p2pBookMakerStatusInactive,
      null => null,
    };
    return Row(
      children: [
        RobotAvatar(seed: order.maker.hex, size: 36),
        const Gap(BullSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.maker.nickname,
                style: text.headlineLarge?.copyWith(color: colors.text),
              ),
              Text(
                [l10n.p2pOrderMaker, ?activity].join(' · '),
                style: text.labelMedium?.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
