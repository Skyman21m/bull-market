import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/maker_terms.dart';
import '../../domain/trade_record.dart';
import '../../presentation/p2p_formats.dart';

/// The line of a maker's trade that says how far the rate the coordinator fixed at the take is from the rate when the order was made (design note `docs/design/phase-3-making-an-order.md` § 3.3, « The gap », #182): before « Submit » of a maker buyer's payout and in its « Confirm … sent », information only, never a warning and never a gate.
///
/// In the warning colour when the gap is unfavourable to the maker's [role] (fewer sats to receive for a buyer, [TradeRateGap.effectFor]), never shown as neutral when it is not.
class RateGapLine extends StatelessWidget {
  final TradeRateGap gap;
  final TradeRole role;
  final String text;

  const RateGapLine({
    super.key,
    required this.gap,
    required this.role,
    required this.text,
  });

  /// The line for [gap], or `null` when the read gives no sats for it: [sats], the order's `satoshis_now` fixed at the take; [amount] and [currency], the contract's amount.
  static RateGapLine? of(
    BuildContext context, {
    required TradeRateGap? gap,
    required TradeRole role,
    required String coordinator,
    required Sats? sats,
    required FiatAmount? amount,
    required RobosatsCurrency currency,
  }) {
    if (gap == null || sats == null || amount == null) return null;
    final text = textOf(
      context,
      gap: gap,
      coordinator: coordinator,
      sats: sats,
      amount: amount,
      currency: currency,
    );
    return RateGapLine(gap: gap, role: role, text: text);
  }

  /// The words of the line, which « Confirm … sent » repeats.
  static String textOf(
    BuildContext context, {
    required TradeRateGap gap,
    required String coordinator,
    required Sats sats,
    required FiatAmount amount,
    required RobosatsCurrency currency,
  }) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    return l10n.p2pTradeRateGap(
      coordinator,
      formats.bigSats(sats.value),
      formats.amount(amount),
      currency.code,
      formats.orderRate(gap.fixedRate),
      formats.gap(hundredthsOf(gap.percent)),
      formats.orderRate(gap.createdRate),
    );
  }

  /// [percent] in hundredths of a percent, rounded away from zero (as the bond's gap is, #180), so that a gap shown at 0.00 % is exactly none: a figure within a billionth of a hundredth is that hundredth.
  static BigInt hundredthsOf(double percent) {
    final scaled = percent * 100;
    final nearest = scaled.roundToDouble();
    if ((scaled - nearest).abs() < 1e-9) return BigInt.from(nearest);
    return BigInt.from(scaled.isNegative ? scaled.floor() : scaled.ceil());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final unfavourable = gap.effectFor(role) == RateGapEffect.unfavourable;
    final color = unfavourable ? colors.warning : colors.text;
    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              unfavourable ? Icons.warning_amber_rounded : Icons.info_outline,
              size: 18,
              color: color,
            ),
          ),
          const Gap(BullSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
