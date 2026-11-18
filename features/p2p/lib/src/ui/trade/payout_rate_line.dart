import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/trade_tolerances.dart';
import '../../domain/trade/wallet_rate_check.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/payout_rate_cubit.dart';
import '../widgets/trade_dialog_body.dart';

/// The lines of the owner's payment rule on a maker buyer's side (#182, design note § 3.3), before « Submit » of the payout, before the chat step and in « Confirm … sent »: the comparison with the Bull wallet's price (information), the red warning beyond [TradeTolerances.walletRateGap] fewer sats (nothing blocked), one line without a figure for a currency the Bull wallet does not price, « rate not checked » with « Retry » for a price that could not be read, and « rate not checked » for a read that gives no sats: never nothing without saying it.
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

  /// The words of [state], each with its tone, for the panel as for the dialog of « Confirm … sent »; empty where the rule says nothing.
  static List<TradeDialogLine> linesOf(
    BuildContext context,
    PayoutRateState state, {
    required String coordinator,
    required String amount,
  }) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    return switch (state) {
      PayoutRateNone() => const [],
      PayoutRateReading() => [
        (text: l10n.p2pPayoutRateReading, tone: TradeDialogTone.plain),
      ],
      PayoutRateSatsMissing() => [
        (
          text: l10n.p2pPayoutRateSatsMissing(coordinator),
          tone: TradeDialogTone.warning,
        ),
      ],
      PayoutRateChecked(:final check) => switch (check) {
        WalletRateCompared(
          :final price,
          :final expected,
          :final gapHundredths,
        ) =>
          [
            (
              text: l10n.p2pPayoutRateWallet(
                formats.orderRate(price),
                check.currency.code,
                amount,
                formats.bigSats(expected.value),
                formats.bigSats(check.asked.value),
                formats.gap(gapHundredths),
              ),
              tone: TradeDialogTone.plain,
            ),
            if (check.warns)
              (
                text: l10n.p2pPayoutRateWarning(
                  formats.threshold(TradeTolerances.walletRateGap),
                  formats.bigSats(check.asked.value),
                  formats.bigSats(expected.value),
                ),
                tone: TradeDialogTone.alert,
              ),
          ],
        WalletRateNotPriced() => [
          (
            text: l10n.p2pPayoutRateNotPriced(check.currency.code, coordinator),
            tone: TradeDialogTone.warning,
          ),
        ],
        WalletRateUnverified() => [
          (
            text: l10n.p2pPayoutRateUnverified(check.currency.code),
            tone: TradeDialogTone.warning,
          ),
        ],
      },
    };
  }

  /// Whether [state] holds a comparison with the Bull wallet's price: the gap from the creation's rate is then not shown (decided by the coordinator of the work after the functional review of #182: one figure for one question).
  static bool compares(PayoutRateState? state) =>
      state is PayoutRateChecked && state.check is WalletRateCompared;

  /// The contract's amount of [order] as the payout's prompt writes it.
  static String amountOf(BuildContext context, CoordinatorOrder? order) {
    if (order == null) return '';
    final formats = P2pFormats.of(context);
    final taken = order.takenAmount;
    return taken == null
        ? formats.orderAmount(order.amount)
        : formats.amount(taken);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final lines = linesOf(
      context,
      state,
      coordinator: coordinator,
      amount: amount,
    );
    if (lines.isEmpty) return const SizedBox.shrink();
    final retry = switch (state) {
      PayoutRateChecked(check: WalletRateUnverified()) => true,
      _ => false,
    };
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
                    line.tone == TradeDialogTone.plain
                        ? Icons.info_outline
                        : Icons.warning_amber_rounded,
                    size: 18,
                    color: _colourOf(context, line.tone),
                  ),
                ),
                const Gap(BullSpacing.xs),
                Expanded(
                  child: Text(
                    line.text,
                    style: text.bodyMedium?.copyWith(
                      color: _colourOf(context, line.tone),
                      fontWeight: line.tone == TradeDialogTone.plain
                          ? null
                          : FontWeight.bold,
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

  static Color _colourOf(BuildContext context, TradeDialogTone tone) =>
      switch (tone) {
        TradeDialogTone.plain => context.bull.text,
        TradeDialogTone.warning => context.bull.warning,
        TradeDialogTone.alert => context.bull.error,
      };
}
