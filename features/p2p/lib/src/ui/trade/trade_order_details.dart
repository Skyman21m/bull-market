import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/taker_estimate.dart';
import '../../presentation/p2p_formats.dart';
import '../widgets/offer_row.dart';
import '../widgets/order_detail_row.dart';
import '../widgets/reversible_payments_dialog.dart';

/// The « Order » tab of the trade screen: the order as its coordinator describes it to the trade's robot, as the official client's order details on the order page (`components/OrderDetails/index.tsx` at commit ff1998c), read from the last read of the trade, nothing asked for it.
///
/// Host and number, the coordinator's fees, then « Order Details »: the amount (the amount taken once there is one), what the taker sends and receives (the sats once the coordinator gives them, `invoice_amount` or `trade_satoshis` for a buyer, `trade_satoshis` or `escrow_satoshis` for a seller, and until then the reference's estimate with the coordinator's taker fee, `TakerEstimate.ofTrade` or `ofTradeAsSeller`), the payment methods, the price and premium, then, while the order's status expires (`:494`: not 4, 5, 12 to 18), « Expires in » with the countdown (orange under a quarter of the time, red under a tenth, bold under a quarter), « Deposit » and the bar of the time left; then the maker with how recently its coordinator saw it, as the order details of the book show them (`OrderFeeRow`, `OrderMakerRow`).
class TradeOrderDetails extends StatelessWidget {
  final CoordinatorOrder order;
  final DateTime now;

  /// What the coordinator says about itself, `null` until it answers: the fee row stays empty and the estimate counts no fee, as the reference does without its info.
  final CoordinatorInfo? info;

  /// Opens the dialog of the coordinator, as a tap on the host does in the official client.
  final VoidCallback? onOpenCoordinator;

  const TradeOrderDetails({
    super.key,
    required this.order,
    required this.now,
    this.info,
    this.onOpenCoordinator,
  });

  /// The statuses whose order shows no countdown (`components/OrderDetails/index.tsx:494`).
  static const _noCountdown = {4, 5, 12, 13, 14, 15, 16, 17, 18};

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final code = order.currency.code;
    final taken = order.takenAmount;
    final amount = order.currency.isBitcoin
        ? l10n.p2pAmountSats(
            taken == null
                ? formats.btcAmountInSats(order.amount)
                : formats.sats((taken.value * 100000000).round()),
          )
        : '${taken == null ? formats.orderAmount(order.amount) : formats.amount(taken)} $code';
    // The taker of a buy order sells (#96): it sends the sats and receives the fiat (`components/OrderDetails/index.tsx:237-265`).
    final seller = order.type == OrderType.buy;
    final given = seller
        ? order.tradeSatoshis ?? order.escrowInvoice?.satoshis
        : order.payoutInvoiceAmount ?? order.tradeSatoshis;
    final takerFee = info?.takerFee ?? 0;
    final estimate = given != null
        ? null
        : seller
        ? TakerEstimate.ofTradeAsSeller(order, takerFee: takerFee)
        : TakerEstimate.ofTrade(order, takerFee: takerFee);
    final sats = given != null
        ? formats.sats(given.value.toInt())
        : estimate != null
        ? formats.estimate(estimate)
        : null;
    final methods = order.paymentMethods.text;
    final fiat = OrderSentence.split(
      seller
          ? l10n.p2pOrderYouReceiveVia(methods, OrderSentence.mark)
          : l10n.p2pOrderYouSendVia(methods, OrderSentence.mark),
      amount,
    );
    final bitcoin = sats == null
        ? null
        : OrderSentence.split(
            seller
                ? l10n.p2pOrderYouSendLightning(OrderSentence.mark)
                : l10n.p2pOrderYouReceiveSats(OrderSentence.mark),
            sats,
          );
    // What is sent first, then what is received, as the reference lists them.
    final (send, receive) = seller ? (bitcoin, fiat) : (fiat, bitcoin);
    final price = order.priceNow;
    final premium = order.premiumNow ?? order.premium;
    final explicit = order.explicitSatoshis;
    final (priceLabel, priceValue) = price != null && premium != null
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
        : premium != null
        ? (l10n.p2pOrderPremiumOverMarket, formats.premiumOverMarket(premium))
        : (null, null);
    final total = order.stepDuration;
    final left = order.expiresAt.difference(now);
    final share = total.inMilliseconds <= 0 || left.isNegative
        ? 0.0
        : (left.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final countdown = !_noCountdown.contains(order.status.wire);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrderHostRow(
          coordinator: order.coordinator,
          orderId: order.id,
          onTap: onOpenCoordinator,
        ),
        const Gap(BullSpacing.sm),
        OrderFeeRow(info: info),
        const Gap(BullSpacing.sm),
        Text(
          l10n.p2pOrderDetailsDivider,
          style: text.labelLarge?.copyWith(color: colors.textMuted),
        ),
        const Gap(BullSpacing.xs),
        BullDetailsTable(
          items: [
            OrderDetailRow(
              taken == null && order.amount is RangeOrderAmount
                  ? l10n.p2pOrderAmountRange
                  : l10n.p2pBookColumnAmount,
              amount,
            ),
            if (send != null) OrderDetailRow(send.label, send.value),
            if (receive != null) OrderDetailRow(receive.label, receive.value),
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
            if (priceLabel != null && priceValue != null)
              OrderDetailRow(priceLabel, priceValue),
            if (countdown) ...[
              OrderDetailRow(
                l10n.p2pOrderExpiresIn,
                left.isNegative
                    ? l10n.p2pOrderExpired
                    : formats.countdown(left),
                color: share < 0.10
                    ? colors.error
                    : share < 0.25
                    ? colors.warning
                    : null,
                bold: share < 0.25,
              ),
              Column(
                children: [
                  OrderDetailRow(
                    l10n.p2pOrderDeposit,
                    formats.depositTime(order.escrowDuration),
                  ),
                  const Gap(BullSpacing.sm),
                  // The bar repeats the countdown above it: a screen reader reads the countdown, not the bar.
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(BullRadius.xxs),
                      child: LinearProgressIndicator(
                        value: share,
                        minHeight: 4,
                        color: share < 0.25 ? colors.secondary : colors.primary,
                        backgroundColor: colors.surfaceContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        const Gap(BullSpacing.md),
        OrderMakerRow(maker: order.maker, activity: order.makerActivity),
      ],
    );
  }
}
