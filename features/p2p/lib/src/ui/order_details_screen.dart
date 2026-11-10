import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:robosats/robosats.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../presentation/order_details_cubit.dart';
import '../presentation/p2p_formats.dart';
import 'widgets/offer_row.dart';
import 'widgets/robot_avatar.dart';
import 'widgets/testnet_banner.dart';

/// The details of a public order, in the order of the official client: host and number, fees, then the order details, the maker and « Take Order ».
///
/// Phase 1 is read-only: « Take Order » is shown disabled.
class OrderDetailsScreen extends StatefulWidget {
  final DateTime Function() now;

  const OrderDetailsScreen({super.key, required this.now});

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
                  _HostRow(order: order),
                  const Gap(BullSpacing.sm),
                  _FeeRow(info: state.info),
                  const Gap(BullSpacing.sm),
                  _DetailsCard(state: state, now: _now),
                  const Gap(BullSpacing.md),
                  _MakerRow(order: order),
                  const Gap(BullSpacing.md),
                  BullButton.big(
                    label: l10n.p2pTakeOrder,
                    onPressed: () {},
                    disabled: true,
                    bgColor: colors.primary,
                    textColor: colors.onPrimary,
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

/// The coordinator that hosts the order, and the number of the order on it.
class _HostRow extends StatelessWidget {
  final PublicOrder order;

  const _HostRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return Row(
      children: [
        RobotAvatar(seed: order.coordinator.shortAlias, size: 44),
        const Gap(BullSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.coordinator.longAlias,
                style: text.headlineLarge?.copyWith(color: colors.text),
              ),
              Text(
                l10n.p2pOrderHost,
                style: text.labelMedium?.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
        Semantics(
          label: l10n.p2pOrderId,
          child: Text(
            '# ${order.id}',
            style: text.headlineMedium?.copyWith(
              color: colors.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
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
                  label: formats.rate(swapRate),
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
    final amount = '${formats.orderAmount(order.amount)} $code';
    final estimate = state.estimate;
    final sats = estimate == null ? '-' : formats.estimate(estimate);
    final methods = order.paymentMethods.text;
    final (send, receive) = switch (order.type) {
      // The taker of a sell order buys bitcoin: pays fiat, receives sats.
      OrderType.sell => (
        _Sentence.split(
          l10n.p2pOrderYouSendVia(methods, _Sentence.mark),
          amount,
        ),
        _Sentence.split(l10n.p2pOrderYouReceiveSats(_Sentence.mark), sats),
      ),
      OrderType.buy => (
        _Sentence.split(l10n.p2pOrderYouSendLightning(_Sentence.mark), sats),
        _Sentence.split(
          l10n.p2pOrderYouReceiveVia(methods, _Sentence.mark),
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
        : (l10n.p2pOrderPremiumOverMarket, formats.premium(order.premium));
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
            _row(
              context,
              order.amount is RangeOrderAmount
                  ? l10n.p2pOrderAmountRange
                  : l10n.p2pBookColumnAmount,
              amount,
            ),
            _row(context, send.label, send.value),
            _row(context, receive.label, receive.value),
            _row(
              context,
              order.currency.isBitcoin
                  ? l10n.p2pOrderSwapDestination
                  : l10n.p2pOrderAcceptedMethods,
              OfferRow.paymentMethodsLine(order.paymentMethods, l10n),
            ),
            _row(context, priceLabel, priceValue),
            _row(
              context,
              l10n.p2pOrderExpiresIn,
              left.isNegative ? l10n.p2pOrderExpired : formats.countdown(left),
              color: share < 0.10
                  ? colors.error
                  : share < 0.25
                  ? colors.warning
                  : null,
              bold: share < 0.25,
            ),
            _row(
              context,
              l10n.p2pOrderDeposit,
              formats.depositTime(order.escrowDuration),
            ),
          ],
        ),
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
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    Color? color,
    bool bold = false,
  }) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BullSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: colors.textMuted),
            ),
          ),
          const Gap(BullSpacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.bodyLarge?.copyWith(
                color: color ?? colors.text,
                fontWeight: bold ? FontWeight.w700 : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A sentence of the official client cut where its value starts, so that « You send via Revolut 100 EUR » reads as a label and a value.
final class _Sentence {
  final String label;
  final String value;

  const _Sentence(this.label, this.value);

  /// Stands for the value in the translated sentence: a control character, which no coordinator text can contain.
  static const mark = '\u0001';

  /// [sentence] translated with [mark] in place of [value]: the text before it is the label, the rest is the value.
  static _Sentence split(String sentence, String value) {
    final at = sentence.indexOf(mark);
    if (at <= 0) return _Sentence(sentence.replaceAll(mark, value), '');
    return _Sentence(
      sentence.substring(0, at).trim(),
      sentence.substring(at).replaceAll(mark, value).trim(),
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
