import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:primitives/primitives.dart' show Sats;
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/taker_estimate.dart';
import '../domain/trade/trade_take.dart';
import '../domain/trade_record.dart';
import '../presentation/coordinator_details_cubit.dart';
import '../presentation/order_details_cubit.dart';
import '../presentation/p2p_formats.dart';
import 'coordinator_details_dialog.dart';
import 'take_order_section.dart';
import 'widgets/offer_row.dart';
import 'widgets/order_detail_row.dart';
import 'widgets/reversible_payments_dialog.dart';
import 'widgets/testnet_banner.dart';

/// The details of a public order, in the order of the official client: host and number, fees, then the order details, the maker and « Take Order ».
///
/// The host opens the dialog of its coordinator, as in the official client.
/// « Take Order » is [TakeOrderSection] (#88): with [canTake], a `TakeOrderCubit` above this screen takes the order, and [onTaken] opens its trade; once the robot that takes it read the order, the order details show that read ([TakeOrderDetailsCard], #119).
class OrderDetailsScreen extends StatefulWidget {
  final DateTime Function() now;

  /// Builds the cubit of the coordinator dialog.
  final CoordinatorDetailsCubit Function(CoordinatorDetailsRequest request)
  coordinatorDetails;

  /// Whether a `TakeOrderCubit` is above this screen: the feature holds robots only when it was set up with the vault's handle.
  final bool canTake;

  /// Whether the records of this device's trades could not be read when the page was opened (#182, security review R3): the order may be one this device made, so « Take Order » is not offered and one line says why (#207).
  final bool recordsUnreadable;

  /// Opens the Garage from « You do not have a Garage Key », when the tab has one.
  final VoidCallback? onOpenGarage;

  /// Opens the trade a take started: always given by the route, which [canTake] needs.
  final ValueChanged<TradeRecord>? onTaken;

  const OrderDetailsScreen({
    super.key,
    required this.now,
    required this.coordinatorDetails,
    this.canTake = false,
    this.recordsUnreadable = false,
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
                  TakeOrderFeeRow(info: state.info, canTake: widget.canTake),
                  const Gap(BullSpacing.sm),
                  TakeOrderDetailsCard(
                    order: order,
                    estimate: state.estimate,
                    now: _now,
                    canTake: widget.canTake,
                  ),
                  const Gap(BullSpacing.md),
                  TakeOrderMakerRow(order: order, canTake: widget.canTake),
                  const Gap(BullSpacing.md),
                  // The records unread, the order may be this device's: why « Take Order » is not there, rather than « You do not have a Garage Key » at its press (#207).
                  if (widget.recordsUnreadable)
                    Semantics(
                      container: true,
                      liveRegion: true,
                      child: Text(
                        l10n.p2pOrderRecordsUnreadable,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: colors.warning),
                      ),
                    )
                  else
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

/// « Order Details » of an order of the book: the amount, what the taker sends and receives, the payment methods, price and premium, expiry and deposit time; also the trade screen's for an order public again, so that what it shows and what « Take Order » takes are the same order.
///
/// With [read], the take prepared (#119), the figures are those the robot that takes the order read (`GET /api/order/`): its price and premium, its sats, its expiry and deposit time; the maker's description follows the payment methods when there is one, as plain text, the bond the take asks follows the price, and the time of the read, read out when it arrives, closes the card.
/// With [previous], the read the user saw before, when the order changed at the confirmation, the rows that differ from it are marked as the official client marks the time left: in colour and bold.
class PublicOrderDetailsCard extends StatelessWidget {
  final PublicOrder order;

  /// The sats a taker would trade ([TakerEstimate.of]), `null` when the order gives none.
  final TakerEstimate? estimate;
  final DateTime now;

  /// The take prepared, whose read the card shows.
  final PreparedTake? read;

  /// The read the user saw before [read], when the order changed.
  final PreparedTake? previous;

  const PublicOrderDetailsCard({
    super.key,
    required this.order,
    required this.estimate,
    required this.now,
    this.read,
    this.previous,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final code = order.currency.code;
    final read = this.read;
    final readOrder = read?.order;
    // A swap order is given in BTC, which the official client writes in sats.
    final amount = order.currency.isBitcoin
        ? l10n.p2pAmountSats(formats.btcAmountInSats(order.amount))
        : '${formats.orderAmount(order.amount)} $code';
    final shown = read == null
        ? _Figures.ofBook(order, estimate, l10n, formats)
        : _Figures.ofRead(read, l10n, formats);
    final before = switch (previous) {
      final previous? when read != null => _Figures.ofRead(
        previous,
        l10n,
        formats,
      ),
      _ => null,
    };
    // A row whose value differs from the read the user saw before is marked as the reference marks the time left, in colour and bold, its label too, and said to a screen reader (`OrderDetailRow.changed`).
    bool differs(Object? Function(_Figures figures) of) =>
        before != null && of(before) != of(shown);
    // The payment methods the take goes out on: the read's, once there is one (security review of #133).
    final paymentMethods = readOrder?.paymentMethods ?? order.paymentMethods;
    final methods = paymentMethods.text;
    final methodsChanged = differs((f) => f.methods);
    final (send, receive) = switch (order.type) {
      // The taker of a sell order buys bitcoin: pays fiat, receives sats.
      OrderType.sell => (
        OrderSentence.split(
          l10n.p2pOrderYouSendVia(methods, OrderSentence.mark),
          amount,
        ),
        OrderSentence.split(
          l10n.p2pOrderYouReceiveSats(OrderSentence.mark),
          shown.sats,
        ),
      ),
      OrderType.buy => (
        OrderSentence.split(
          l10n.p2pOrderYouSendLightning(OrderSentence.mark),
          shown.sats,
        ),
        OrderSentence.split(
          l10n.p2pOrderYouReceiveVia(methods, OrderSentence.mark),
          amount,
        ),
      ),
    };
    final satsChanged = differs((f) => f.sats);
    final total = shown.expiresAt.difference(
      readOrder?.createdAt ?? order.createdAt,
    );
    final left = shown.expiresAt.difference(now);
    final share = total.inMilliseconds <= 0 || left.isNegative
        ? 0.0
        : (left.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final expiryChanged = differs((f) => f.expiresAt);
    final description = shown.description;
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
            OrderDetailRow(
              send.label,
              send.value,
              changed:
                  (order.type == OrderType.buy && satsChanged) ||
                  (order.type == OrderType.sell && methodsChanged),
            ),
            OrderDetailRow(
              receive.label,
              receive.value,
              changed:
                  (order.type == OrderType.sell && satsChanged) ||
                  (order.type == OrderType.buy && methodsChanged),
            ),
            OrderDetailRow(
              order.currency.isBitcoin
                  ? l10n.p2pOrderSwapDestination
                  : l10n.p2pOrderAcceptedMethods,
              OfferRow.paymentMethodsLine(paymentMethods, l10n),
              changed: methodsChanged,
              warning: paymentMethods.hasReversible
                  ? () => ReversiblePaymentsDialog.show(context, paymentMethods)
                  : null,
            ),
            if (description != null && description.trim().isNotEmpty)
              OrderDescriptionRow(
                description,
                changed: differs((f) => f.description),
              ),
            OrderDetailRow(
              shown.priceLabel,
              shown.priceValue,
              changed: differs((f) => f.priceValue),
            ),
            if (read != null)
              OrderDetailRow(
                l10n.p2pTakerBond,
                shown.bond ?? '',
                changed: differs((f) => f.bond),
              ),
            OrderDetailRow(
              l10n.p2pOrderExpiresIn,
              left.isNegative ? l10n.p2pOrderExpired : formats.countdown(left),
              color: share < 0.10
                  ? colors.error
                  : share < 0.25
                  ? colors.warning
                  : null,
              bold: share < 0.25,
              changed: expiryChanged,
            ),
            // The time left closes the card, under its last row, as in the official client.
            Column(
              children: [
                OrderDetailRow(
                  l10n.p2pOrderDeposit,
                  shown.deposit,
                  changed: differs((f) => f.deposit),
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
        if (read != null) ...[
          const Gap(BullSpacing.xs),
          // Read out when a read arrives, so that a screen reader hears that the order details now show it.
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              l10n.p2pTakeReadAt(
                DateFormat.Hms(l10n.localeName).format(read.readAt.toLocal()),
              ),
              style: text.labelMedium?.copyWith(color: colors.textMuted),
            ),
          ),
        ],
      ],
    );
  }
}

/// The values the order details show of the book's order, or of a robot's read, as text: what tells two reads apart.
final class _Figures {
  final String methods;
  final String sats;
  final String priceLabel;
  final String priceValue;
  final DateTime expiresAt;
  final String deposit;
  final String? description;
  final String? bond;

  const _Figures({
    required this.methods,
    required this.sats,
    required this.priceLabel,
    required this.priceValue,
    required this.expiresAt,
    required this.deposit,
    required this.description,
    required this.bond,
  });

  static (String, String) _price(
    double? price,
    Premium premium,
    Sats? explicit,
    String code,
    P2pLocalizations l10n,
    P2pFormats formats,
  ) => price != null
      ? (
          l10n.p2pOrderPriceAndPremium,
          l10n.p2pOrderPriceAndPremiumValue(
            formats.price(price),
            code,
            formats.premiumNumber(premium),
          ),
        )
      : explicit != null
      ? (l10n.p2pOrderAmountOfSatoshis, formats.sats(explicit.value.toInt()))
      : (l10n.p2pOrderPremiumOverMarket, formats.premiumOverMarket(premium));

  static _Figures ofBook(
    PublicOrder order,
    TakerEstimate? estimate,
    P2pLocalizations l10n,
    P2pFormats formats,
  ) {
    final (label, value) = _price(
      order.price,
      order.premium,
      order.explicitSatoshis,
      order.currency.code,
      l10n,
      formats,
    );
    return _Figures(
      methods: order.paymentMethods.text,
      sats: estimate == null ? '-' : formats.estimate(estimate),
      priceLabel: label,
      priceValue: value,
      expiresAt: order.expiresAt,
      deposit: formats.depositTime(order.escrowDuration),
      description: null,
      bond: null,
    );
  }

  /// The robot's read (#119): its own sats (the taker fee of the terms), price, premium, expiry, deposit time, description and the bond the take asks.
  static _Figures ofRead(
    PreparedTake read,
    P2pLocalizations l10n,
    P2pFormats formats,
  ) {
    final order = read.order;
    // The taker of a buy order sells (#96): the reference counts its sats with the taker fee off and no routing budget, before the take as after it (`components/OrderDetails/index.tsx:237-258`), as the book's figure above does.
    final estimate = order.type == OrderType.buy
        ? TakerEstimate.ofTradeAsSeller(order, takerFee: read.terms.takerFee)
        : TakerEstimate.ofTrade(order, takerFee: read.terms.takerFee);
    final (label, value) = _price(
      order.priceNow,
      read.terms.premium,
      read.terms.explicitSatoshis,
      order.currency.code,
      l10n,
      formats,
    );
    return _Figures(
      methods: order.paymentMethods.text,
      sats: estimate == null ? '-' : formats.estimate(estimate),
      priceLabel: label,
      priceValue: value,
      expiresAt: order.expiresAt,
      deposit: formats.depositTime(order.escrowDuration),
      description: order.description,
      bond: l10n.p2pTakeBondEstimate(
        formats.sats(read.expectedBond.round()),
        formats.sats(read.bondCeiling),
      ),
    );
  }
}
