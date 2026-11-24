import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:primitives/primitives.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../../public/p2p_wallet_port.dart';
import '../../domain/trade/shown_alerts.dart';
import '../../domain/trade/trade_tolerances.dart';
import '../../domain/trade/trade_watch.dart';
import '../../domain/trade/wallet_rate_check.dart';
import '../../presentation/bond_payment_cubit.dart';
import '../../presentation/p2p_formats.dart';
import '../widgets/amount_row.dart';
import '../widgets/detail_toggle.dart';
import '../widgets/price_check_lines.dart';
import '../widgets/trade_button.dart';
import '../widgets/word_fit_text.dart';
import 'escrow_contract_lines.dart';
import 'wallet_payment_section.dart';

/// The confirmation of « Pay with this wallet », lean (#250; layout and words validated by the owner on 2026-11-24, each screen following its mock-up), one card for the four payments: a maker's bond (#180), a taker's bond and a taker seller's collateral (#249), a maker seller's collateral with the contract it states (#188).
///
/// On arrival, from the top: the invoice's sats (« Bond » or « Collateral »), « Swap and network fees », a rule, « Total to pay » in bold, then the owner's payment rule ([PriceCheckLines]: the gap to the Bull price « (indicative) », the red alert in two lines, « Amount not checked » with « Retry », or the grey « not quoted »); under a rule, the alerts of the confirmation itself, each in two lines where the owner validated its words (the order taken again meanwhile, the amounts changed, an earlier collateral not back, the order's bond out too, a collateral kept) and the neutral « New contract »; then « Go back » and « Pay {total} sats », the only tap that pays, and under them « Show details ». The detail opens under the link, **the buttons never moving**: the swap fees, the network fee, the balance after payment, the comparison's paragraph or the alert's explanation, the earlier collateral's explanation, for a collateral the swap service's facts, and the reference's sentence on the hold invoice in grey.
///
/// Every alert is visible without a tap, with its figures, above the buttons; only its explanation is in the detail. Beside an alert (the screen's, `ShownAlerts`, or this confirmation's own) the comparison within the threshold is not drawn, nor « A small gap is normal »; an alert never silences another. « Pay » pays exactly the quote shown ([confirming]); it stays offered with every alert but a stale confirmation, whose « Pay » would pay nothing.
class PayConfirmationCard extends StatefulWidget {
  final BondPayConfirming confirming;

  /// Whether the invoice is the collateral's rather than the bond's.
  final bool escrow;

  /// The trade as the screen shows it, for the alerts of the screen beside which no comparison within the threshold is drawn (`ShownAlerts`).
  final TradeSeen seen;

  /// The order's currency, for the reference's sentence on the collateral's hold invoice; `null` when not known.
  final RobosatsCurrency? currency;

  /// For a maker seller's collateral, whether the order's bond was paid with this wallet: said beside the alert of the earlier collaterals, whose total leaves it out (#188, security review of #187, C5).
  final WalletPaidHere bondPaidHere;

  /// The trade's coordinator, named in the alert of a collateral it kept.
  final String coordinator;

  /// The key of « Pay », brought into view when the confirmation opens.
  final GlobalKey payKey;
  final VoidCallback onCancel;
  final VoidCallback onPay;
  final VoidCallback onRetry;

  const PayConfirmationCard({
    super.key,
    required this.confirming,
    required this.escrow,
    required this.seen,
    required this.currency,
    required this.coordinator,
    required this.payKey,
    required this.onCancel,
    required this.onPay,
    required this.onRetry,
    this.bondPaidHere = WalletPaidHere.no,
  });

  /// The keys of the card's parts, for the tests.
  static const amountRow = ValueKey('pay-confirmation-amount');
  static const feesRow = ValueKey('pay-confirmation-fees');
  static const totalRow = ValueKey('pay-confirmation-total');
  static const alerts = ValueKey('pay-confirmation-alerts');
  static const staleBlock = ValueKey('pay-confirmation-stale');
  static const againBlock = ValueKey('pay-confirmation-again');
  static const earlierBlock = ValueKey('pay-confirmation-earlier');
  static const newContractBlock = ValueKey('pay-confirmation-new-contract');
  static const goBack = ValueKey('pay-confirmation-go-back');
  static const detailToggle = ValueKey('pay-confirmation-detail-toggle');
  static const detail = ValueKey('pay-confirmation-detail');
  static const swapFeeRow = ValueKey('pay-confirmation-swap-fee');
  static const networkFeeRow = ValueKey('pay-confirmation-network-fee');
  static const balanceRow = ValueKey('pay-confirmation-balance');
  static const rateParagraph = ValueKey('pay-confirmation-rate');
  static const smallGap = ValueKey('pay-confirmation-small-gap');
  static const earlierDetail = ValueKey('pay-confirmation-earlier-detail');
  static const heldParagraph = ValueKey('pay-confirmation-held');
  static const holdInvoice = ValueKey('pay-confirmation-hold-invoice');

  @override
  State<PayConfirmationCard> createState() => _PayConfirmationCardState();
}

class _PayConfirmationCardState extends State<PayConfirmationCard> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final confirming = widget.confirming;
    final quote = confirming.walletQuote;
    final escrow = widget.escrow;
    final contract = confirming.contract;
    String sats(Sats amount) =>
        l10n.p2pPayAmountSats(formats.bigSats(amount.value));
    final earlier = contract == null
        ? const <EarlierEscrowAlert>[]
        : earlierEscrowAlerts(
            context,
            contract,
            coordinator: widget.coordinator,
          );
    // The order's bond, which the total of the earlier collaterals leaves out (security review of #187, C5): beside the alert of the collaterals not back.
    final bondToo = contract != null && contract.notBack.isNotEmpty
        ? switch (widget.bondPaidHere) {
            WalletPaidHere.yes => l10n.p2pPayEscrowBondHeldToo,
            WalletPaidHere.cannotTell => l10n.p2pPayEscrowBondMaybeHeldToo,
            WalletPaidHere.no => null,
          }
        : null;
    // The alerts of this confirmation itself: beside them, as beside an alert of the screen (`ShownAlerts`), no comparison within the threshold is drawn (security review of #249, C1).
    final ownAlert =
        earlier.isNotEmpty ||
        bondToo != null ||
        confirming.stale ||
        confirming.again;
    final rate = switch (confirming.rate) {
      // A collateral's line names the amount whose sats are expected; its check always carries it (`WalletRateCheck.ofMakerEscrow`, `ofTakerEscrow`).
      WalletRateCompared(amount: null) when escrow => null,
      final rate?
          when !ShownAlerts.reassuresBeside(
            widget.seen,
            rate,
            besides: ownAlert,
          ) =>
        rate,
      _ => null,
    };
    final check = switch (rate) {
      null => null,
      WalletRateCompared(warns: false, :final gapHundredths) =>
        PriceCheckLines.gap(formats.gap(gapHundredths)),
      WalletRateCompared(:final gapHundredths, :final expected, :final asked) =>
        PriceCheckLines.against(
          formats.gap(gapHundredths),
          figures: l10n.p2pPayAgainstFigures(
            formats.bigSats(expected.value),
            formats.bigSats(asked.value),
          ),
        ),
      WalletRateUnverified() => PriceCheckLines.unverified(
        onRetry: widget.onRetry,
        retrying: confirming.retrying,
      ),
      WalletRateNotPriced() => const PriceCheckLines.notPriced(),
    };
    Widget block(
      Key key, {
      required String title,
      required String line,
      required AmountRowTone tone,
      IconData? icon,
    }) => Semantics(
      key: key,
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AmountRow(label: title, tone: tone, icon: icon),
          WordFitText(
            line,
            style: text.bodyMedium?.copyWith(
              color: switch (tone) {
                AmountRowTone.alert => colors.error,
                AmountRowTone.warning => colors.warning,
                _ => colors.text,
              },
            ),
          ),
        ],
      ),
    );
    Widget alertLine(String line) => Semantics(
      container: true,
      liveRegion: true,
      child: AmountRow(
        label: line,
        tone: AmountRowTone.alert,
        icon: Icons.warning_amber_rounded,
      ),
    );
    final blocks = <Widget>[
      if (confirming.stale)
        block(
          PayConfirmationCard.staleBlock,
          title: l10n.p2pPayConfirmStaleTitle,
          line: l10n.p2pPayConfirmStaleLine,
          tone: AmountRowTone.alert,
        )
      else if (confirming.again)
        block(
          PayConfirmationCard.againBlock,
          title: l10n.p2pPayConfirmAgainTitle,
          line: l10n.p2pPayConfirmAgainLine,
          tone: AmountRowTone.warning,
        ),
      for (final alert in earlier)
        if (alert.title case final title?)
          block(
            PayConfirmationCard.earlierBlock,
            title: title,
            line: alert.line,
            tone: AmountRowTone.alert,
            icon: Icons.warning_amber_rounded,
          )
        else
          alertLine(alert.line),
      if (bondToo != null) alertLine(bondToo),
      if (contract != null && contract.isNew)
        block(
          PayConfirmationCard.newContractBlock,
          title: l10n.p2pPayNewContractTitle,
          line: l10n.p2pPayNewContractLine,
          tone: AmountRowTone.total,
        ),
    ];
    return AmountCard(
      children: [
        AmountRow(
          key: PayConfirmationCard.amountRow,
          label: escrow ? l10n.p2pPayRowCollateral : l10n.p2pPayRowBond,
          amount: sats(quote.amount),
        ),
        AmountRow(
          key: PayConfirmationCard.feesRow,
          label: l10n.p2pPayRowFees,
          amount: sats(Sats(quote.serviceFee.value + quote.networkFee.value)),
        ),
        Divider(
          height: BullSpacing.xs,
          thickness: 1,
          color: colors.outlineVariant,
        ),
        AmountRow(
          key: PayConfirmationCard.totalRow,
          label: l10n.p2pPayRowTotal,
          amount: sats(quote.total),
          tone: AmountRowTone.total,
        ),
        ?check,
        // The alerts of the confirmation, under a rule, just above the buttons.
        if (blocks.isNotEmpty) ...[
          Divider(
            height: BullSpacing.md,
            thickness: 1,
            color: colors.outlineVariant,
          ),
          Column(
            key: PayConfirmationCard.alerts,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, block) in blocks.indexed) ...[
                if (index > 0) const Gap(BullSpacing.sm),
                block,
              ],
            ],
          ),
        ],
        const Gap(BullSpacing.md),
        // The reference's word for stepping back in its dialogs (#134): never the trade's « Cancel », a few rows below.
        TradeButton(
          key: PayConfirmationCard.goBack,
          label: l10n.p2pCommonGoBack,
          outlined: true,
          onPressed: widget.onCancel,
        ),
        const Gap(BullSpacing.sm),
        KeyedSubtree(
          key: widget.payKey,
          child: TradeButton(
            label: l10n.p2pPayConfirm(formats.sats(quote.total.value.toInt())),
            // A confirmation of a contract the order moved on from pays nothing: not offered.
            onPressed: confirming.stale ? null : widget.onPay,
          ),
        ),
        // Under the buttons, in the card: the detail opens under the link, so the buttons never move (the owner's decision of 2026-11-24).
        DetailToggle(
          key: PayConfirmationCard.detailToggle,
          open: _open,
          onPressed: () => setState(() => _open = !_open),
        ),
        if (_open)
          _Detail(
            key: PayConfirmationCard.detail,
            quote: quote,
            rate: rate,
            escrow: escrow,
            earlier: [for (final alert in earlier) ?alert.detail],
            currency: widget.currency,
          ),
      ],
    );
  }
}

/// The confirmation's detail, in this order: the swap fees, the network fee, the balance after payment; the comparison's paragraph and « A small gap is normal » (within the threshold only), or the red alert's explanation, or « Amount not checked »'s; the earlier collateral's explanation; for a collateral the swap service's facts; the reference's sentence on the hold invoice, word for word, in grey.
class _Detail extends StatelessWidget {
  final P2pWalletQuote quote;

  /// The rule's check as the card draws it: `null` when nothing is compared, or a comparison within the threshold beside an alert.
  final WalletRateCheck? rate;
  final bool escrow;
  final List<String> earlier;
  final RobosatsCurrency? currency;

  const _Detail({
    super.key,
    required this.quote,
    required this.rate,
    required this.escrow,
    required this.earlier,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    String sats(Sats amount) =>
        l10n.p2pPayAmountSats(formats.bigSats(amount.value));
    final body = text.bodyMedium?.copyWith(color: colors.text);
    final rate = this.rate;
    final currency = this.currency;
    final (String, Color)? paragraph = switch (rate) {
      WalletRateCompared(warns: true, :final price, currency: final code) => (
        l10n.p2pPayAgainstDetail(
          formats.orderRate(price),
          code.code,
          formats.threshold(TradeTolerances.walletRateGap),
        ),
        colors.error,
      ),
      // A collateral asked above the sats expected: the validated paragraph, which says « … more, its fees included » (a collateral carries the coordinator's fee).
      WalletRateCompared(amount: final amount?) && final compared
          when escrow && compared.gapHundredths > BigInt.zero =>
        (
          l10n.p2pPayRateDetail(
            formats.amount(amount),
            compared.currency.code,
            formats.orderRate(compared.price),
            formats.bigSats(compared.expected.value),
            formats.gapSize(compared.gapHundredths),
          ),
          colors.text,
        ),
      // A collateral asked at or below the sats expected: the earlier sentence, which says the gap with its sign (the validated one says « more »).
      WalletRateCompared(amount: final amount?) && final compared when escrow =>
        (
          l10n.p2pPayRateWalletEscrow(
            formats.orderRate(compared.price),
            compared.currency.code,
            formats.amount(amount),
            formats.bigSats(compared.expected.value),
            formats.gap(compared.gapHundredths),
          ),
          colors.text,
        ),
      // A bond: the earlier sentence, the validated one being a collateral's (the value of the amount, and the coordinator's fee, which a bond does not carry).
      WalletRateCompared() && final compared => (
        l10n.p2pPayRateWallet(
          formats.orderRate(compared.price),
          compared.currency.code,
          formats.bigSats(compared.expected.value),
          formats.gap(compared.gapHundredths),
        ),
        colors.text,
      ),
      WalletRateUnverified() => (l10n.p2pPayUnverifiedDetail, colors.warning),
      WalletRateNotPriced() || null => null,
    };
    final reassures = rate is WalletRateCompared && !rate.warns;
    final paragraphs = <Widget>[
      if (paragraph case (final line, final color))
        WordFitText(
          line,
          key: PayConfirmationCard.rateParagraph,
          style: text.bodyMedium?.copyWith(color: color),
        ),
      // Beside a comparison within the threshold only, never beside an alert.
      if (reassures)
        WordFitText(
          l10n.p2pPayoutBreakdownSmallGap,
          key: PayConfirmationCard.smallGap,
          style: body,
        ),
      for (final line in earlier)
        WordFitText(
          line,
          key: PayConfirmationCard.earlierDetail,
          style: text.bodyMedium?.copyWith(color: colors.error),
        ),
      // The escrow's facts (#97): the whole trade stays with the swap service until it ends, and what a cancelled trade costs. Informed, not stopped.
      if (escrow)
        WordFitText(
          l10n.p2pPayEscrowHeld,
          key: PayConfirmationCard.heldParagraph,
          style: body,
        ),
      // The reference's sentence on a hold invoice, word for word (the owner's decision, #135).
      if (!escrow || currency != null)
        WordFitText(
          escrow && currency != null
              ? l10n.p2pTradeHoldInvoiceEscrow(currency.code)
              : l10n.p2pTradeHoldInvoiceBond,
          key: PayConfirmationCard.holdInvoice,
          style: text.bodySmall?.copyWith(color: colors.textMuted),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AmountRow(
          key: PayConfirmationCard.swapFeeRow,
          label: l10n.p2pPayRowSwapFees,
          amount: sats(quote.serviceFee),
        ),
        AmountRow(
          key: PayConfirmationCard.networkFeeRow,
          label: l10n.p2pPayRowNetworkFee,
          amount: sats(quote.networkFee),
        ),
        AmountRow(
          key: PayConfirmationCard.balanceRow,
          label: l10n.p2pPayRowLeft,
          amount: sats(quote.remaining),
        ),
        for (final paragraph in paragraphs) ...[
          const Gap(BullSpacing.xs),
          paragraph,
        ],
      ],
    );
  }
}
