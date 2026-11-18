import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/trade_tolerances.dart';
import '../../domain/trade/wallet_rate_check.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/payout_rate_cubit.dart';

/// The lines of the owner's payment rule on a maker buyer's side (#182, design note § 3.3), before « Submit » of the payout and in « Confirm … sent »: the comparison with the Bull wallet's price (information), the red warning beyond [TradeTolerances.walletRateGap] fewer sats (nothing blocked), one line without a figure for a currency the Bull wallet does not price, « rate not checked » with « Retry » for a price that could not be read.
class PayoutRateLines extends StatelessWidget {
  final PayoutRateState state;
  final String coordinator;

  /// The contract's amount, written ([amountOf]).
  final String amount;

  /// « Retry » after a price that could not be read; `null` shows none.
  final VoidCallback? onRetry;

  const PayoutRateLines({
    super.key,
    required this.state,
    required this.coordinator,
    required this.amount,
    this.onRetry,
  });

  /// The words of [check], each with whether it is the red warning, for the dialog of « Confirm … sent » as for the panel; [amount] is the contract's amount, written.
  static List<({String text, bool alert})> linesOf(
    BuildContext context,
    WalletRateCheck check, {
    required String coordinator,
    required String amount,
  }) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final code = check.currency.code;
    return switch (check) {
      WalletRateCompared(:final price, :final expected, :final gapHundredths) => [
        (
          text: l10n.p2pPayoutRateWallet(
            formats.orderRate(price),
            code,
            amount,
            formats.bigSats(expected.value),
            formats.bigSats(check.asked.value),
            formats.gap(gapHundredths),
          ),
          alert: false,
        ),
        if (check.warns)
          (
            text: l10n.p2pPayoutRateWarning(
              formats.threshold(TradeTolerances.walletRateGap),
              formats.bigSats(check.asked.value),
              formats.bigSats(expected.value),
            ),
            alert: true,
          ),
      ],
      WalletRateNotPriced() => [
        (text: l10n.p2pPayoutRateNotPriced(code, coordinator), alert: true),
      ],
      WalletRateUnverified() => [
        (text: l10n.p2pPayoutRateUnverified(code), alert: true),
      ],
    };
  }

  /// The contract's amount of [order] as the payout's prompt writes it.
  static String amountOf(BuildContext context, CoordinatorOrder? order) {
    if (order == null) return '';
    final formats = P2pFormats.of(context);
    final taken = order.takenAmount;
    return taken == null ? formats.orderAmount(order.amount) : formats.amount(taken);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final state = this.state;
    final List<({String text, bool alert})> lines;
    final bool retry;
    switch (state) {
      case PayoutRateNone():
        return const SizedBox.shrink();
      case PayoutRateReading():
        lines = [(text: l10n.p2pPayoutRateReading, alert: false)];
        retry = false;
      case PayoutRateChecked(:final check):
        lines = linesOf(
          context,
          check,
          coordinator: coordinator,
          amount: amount,
        );
        retry = check is WalletRateUnverified;
    }
    final onRetry = this.onRetry;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, line) in lines.indexed) ...[
            if (i > 0) const Gap(BullSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    line.alert ? Icons.warning_amber_rounded : Icons.info_outline,
                    size: 18,
                    color: line.alert ? _alertColour(context, state) : colors.text,
                  ),
                ),
                const Gap(BullSpacing.xs),
                Expanded(
                  child: Text(
                    line.text,
                    style: text.bodyMedium?.copyWith(
                      color: line.alert ? _alertColour(context, state) : colors.text,
                      fontWeight: line.alert ? FontWeight.bold : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (retry && onRetry != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onRetry,
                child: Text(
                  l10n.p2pCommonRetry,
                  style: text.labelLarge?.copyWith(color: colors.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Red for the warning of a comparison, the warning colour for a line without figures, as the bond's confirmation draws them (#180).
  static Color _alertColour(BuildContext context, PayoutRateState state) =>
      switch (state) {
        PayoutRateChecked(check: WalletRateCompared()) => context.bull.error,
        _ => context.bull.warning,
      };
}
