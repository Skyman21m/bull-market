import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/trade_tolerances.dart';
import '../../domain/trade/trade_watch.dart';
import '../../domain/trade/wallet_rate_check.dart';
import '../../domain/usecases/trade/check_payout_rate_usecase.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/payout_rate_cubit.dart';
import '../widgets/trade_dialog_body.dart';
import 'payout_breakdown_view.dart';

/// The lines of the owner's payment rule on a maker buyer's side (#182, design note § 3.3), before « Submit » of the payout, before the chat step and in « Confirm … sent »: the comparison with the Bull wallet's price (information), the red warning beyond [TradeTolerances.walletRateGap] fewer sats (nothing blocked), one line without a figure for a currency the Bull wallet does not price, « rate not checked » with « Retry » for a price that could not be read, and « rate not checked » for a read that gives no sats: never nothing without saying it.
class PayoutRateLines extends StatelessWidget {
  final PayoutRateState state;
  final String coordinator;

  /// The contract's amount, written ([amountOf]).
  final String amount;

  /// « Retry » after a price that could not be read; `null` shows none.
  final VoidCallback? onRetry;

  /// Whether the payout panel's breakdown says the comparison at 6 and 8 (#228): its first line, the value at the Bull wallet's price, and its gap ([PayoutValuation]); the comparison's sentence is then not said here, its red warning still is.
  final bool comparisonInBreakdown;

  const PayoutRateLines({
    super.key,
    required this.state,
    required this.coordinator,
    required this.amount,
    this.onRetry,
    this.comparisonInBreakdown = false,
  });

  /// The comparison of [state] as the payout panel's breakdown draws it (#228), with [amount] the contract's amount written ([amountOf]): only at 6 and 8 for a comparison with the Bull wallet's price; `null` otherwise (« rate not checked », a currency the Bull wallet does not price, a price being read, amounts that do not agree, the chat step).
  static PayoutValuation? valuationOf(
    BuildContext context,
    PayoutRateState? state, {
    required String amount,
  }) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    return switch (state) {
      PayoutRateChecked(
        :final step,
        check: final WalletRateCompared check,
        basis: PayoutRateAskedNow(),
      )
          when !step.fiatSent =>
        PayoutValuation(
          given: check.asked,
          value: check.expected,
          price: l10n.p2pPayoutBreakdownPrice(
            amount,
            check.currency.code,
            formats.orderRate(check.price),
          ),
          gap: formats.gap(check.gapHundredths),
          warns: check.warns,
        ),
      _ => null,
    };
  }

  /// The words of [state], each with its tone, for the panel as for the dialog of « Confirm … sent »; empty where the rule says nothing. With [comparisonInBreakdown], the comparison's sentence at 6 and 8 is left to the payout panel's breakdown (#228), its red warning said here as before.
  static List<TradeDialogLine> linesOf(
    BuildContext context,
    PayoutRateState state, {
    required String coordinator,
    required String amount,
    bool comparisonInBreakdown = false,
  }) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    return switch (state) {
      PayoutRateNone() => const [],
      PayoutRateReading() => [
        (text: l10n.p2pPayoutRateReading, tone: TradeDialogTone.plain),
      ],
      PayoutRateSatsMissing(:final notSeen) => [
        // At 9, a contract seen late whose invoice was never seen here: said first, in the alert colour, whatever the coordinator's figures say (third security pass of #182, R13, #207).
        if (notSeen)
          (text: l10n.p2pPayoutRateNotSeen, tone: TradeDialogTone.alert),
        (
          text: l10n.p2pPayoutRateSatsMissing(coordinator),
          tone: TradeDialogTone.warning,
        ),
      ],
      // The state machine's warning says it alone: no comparison beside amounts that do not agree (security review of #182, C1 bis); for a contract seen late whose invoice was never seen here, its alert beside it (R13, #207).
      // Within the threshold beside an alert of the state machine: the alert alone (C1 of the functional review of #249).
      PayoutRateAlertAlone() => const [],
      PayoutRateAmountsDisagree(:final notSeen) => [
        if (notSeen)
          (text: l10n.p2pPayoutRateNotSeen, tone: TradeDialogTone.alert),
      ],
      PayoutRateChecked(:final check, :final basis) => [
        // At 9, a coordinator's figure that moved since the invoice it asked: said first, in the alert colour (security review of #182, C2).
        if (basis case PayoutRateTold(:final told, :final asked))
          (
            text: l10n.p2pPayoutRateToldMoved(
              coordinator,
              formats.bigSats(told.value),
              formats.bigSats(asked.value),
            ),
            tone: TradeDialogTone.alert,
          ),
        // At 9, a contract seen late whose invoice was never seen here: said first, in the alert colour (second security review of #182, R9).
        if (basis is PayoutRateNotSeen)
          (text: l10n.p2pPayoutRateNotSeen, tone: TradeDialogTone.alert),
        ...switch (check) {
          WalletRateCompared(:final price, :final expected, :final gapHundredths) => [
            // At 9, the invoice this app kept compared alone (`PayoutRateAskedOnly`) arises only beside the state machine's alert (a read refused, the coordinator's figures missing or not agreeing): its neutral line is not said beside that alert, on the screen as in « Confirm … sent »; its red warning still is, and the line comes back with the coordinator's figures once the alert goes (#228, the ticket's comment; R4 of the security review of #219). At 6 and 8 the payout panel's breakdown says the comparison when it draws it (#228).
            if (basis is! PayoutRateAskedOnly &&
                !(comparisonInBreakdown && basis is PayoutRateAskedNow))
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
            // At 9 with nothing kept (most often a restart between 8 and 9, a normal case): the figure compared is the coordinator's of now, said plainly, the user asked to compare it with the invoice (functional review of #182, U3, #207).
            if (basis is PayoutRateToldNow)
              (
                text: l10n.p2pPayoutRateToldNow(coordinator),
                tone: TradeDialogTone.plain,
              ),
            // Worded to stand alone (#228, functional review C1): at 6 and 8 the comparison's sentence is not said above it; for the sats kept at 6 or 8 compared alone at 9, they are named as what the coordinator gave at the payout step, kept by this app (before the routing budget, so not « Your invoice »), never as a figure of the coordinator now beside its alert (security review of #228, C1).
            if (check.warns)
              (
                text: basis is PayoutRateAskedOnly
                    ? l10n.p2pPayoutRateWarningAsked(
                        coordinator,
                        formats.threshold(TradeTolerances.walletRateGap),
                        formats.bigSats(check.asked.value),
                        formats.bigSats(expected.value),
                      )
                    : l10n.p2pPayoutRateWarning(
                        formats.threshold(TradeTolerances.walletRateGap),
                        formats.bigSats(check.asked.value),
                        formats.bigSats(expected.value),
                      ),
                tone: TradeDialogTone.alert,
              ),
          ],
          WalletRateNotPriced() => [
            (
              text: l10n.p2pPayoutRateNotPriced(
                check.currency.code,
                coordinator,
              ),
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
      ],
    };
  }

  /// The contract's amount as the rule's line writes it: the one the rule compares, as asked here ([TradeSeen.contractAmount]: a range's amount kept with the contract, or the terms' fixed amount), never the read's alone (#183, its security review C4); the order's own only where nothing was asked here ([TradeSeen.asked] unknown), as before; nothing while the amount read does not agree, when no line names it.
  static String amountOf(BuildContext context, TradeSeen seen) {
    final formats = P2pFormats.of(context);
    if (seen.contractAmount case final amount?) return formats.amount(amount);
    final order = seen.order;
    if (order == null || seen.asked != null || seen.contractAmountMoved) {
      return '';
    }
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
      comparisonInBreakdown: comparisonInBreakdown,
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
