import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:primitives/primitives.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/payout_breakdown.dart';
import '../../presentation/p2p_formats.dart';
import '../widgets/amount_row.dart';
import '../widgets/detail_toggle.dart';
import '../widgets/price_check_lines.dart';
import '../widgets/word_fit_text.dart';

/// What the owner's payment rule said at the payout step (6 and 8, and since #237 15) of the sats [given] by the coordinator (#182, #249), as the breakdown draws it (#228, #250): a comparison with the Bull wallet's price ([PayoutCheckCompared]), a price that could not be read ([PayoutCheckUnverified]), a currency the Bull wallet does not price ([PayoutCheckNotPriced], with the alert of #237 for an order made here) or the trade's records that could not be read ([PayoutCheckTermsUnread], #237).
///
/// The trade screen, which holds the rule, builds it from the rule's state (`PayoutRateLines.checkOf`); the payout panel only draws it. Never for a price being read, amounts that do not agree, a comparison within the threshold beside an alert of the screen (`PayoutRateAlertAlone`: the alert speaks alone), the chat step, nor a figure of the creation's price (#234).
@immutable
sealed class PayoutCheck {
  /// The sats the rule compared: the payout panel draws the check in the breakdown only for the very sats the breakdown shows as paid ([PayoutBreakdownView.drawnOf]).
  final Sats given;

  /// At 15 only, what the rule said of [given] against the invoice asked at 6 or 8 for the same contract (#281): fewer sats ([PayoutFirstFewer], a red alert of its own) or nothing kept to compare with ([PayoutFirstUnknown]); `null` at 6 and 8, and at 15 for as many sats or more.
  final PayoutFirstInvoice? first;

  const PayoutCheck(this.given, {this.first});

  /// Whether the comparison with the Bull wallet's price is itself an alert (red beyond the threshold, orange for a price not read, the orange alert since the order was made).
  bool get priceAlert;

  /// Whether at 15 the sats are fewer than at 6 or 8 for the same contract (#281).
  bool get fewer => first is PayoutFirstFewer;

  /// Whether it is an alert ([priceAlert], or [fewer]): drawn above the panel's form when no breakdown can draw it, never left out ([PayoutCheckLines]).
  bool get alert => priceAlert || fewer;
}

/// What the rule said at 15 (the payout failed, a new invoice asked) of the sats now asked against the invoice asked at 6 or 8 for the same contract (#281; design note `docs/design/phase-3-making-an-order.md` § 3.3 bis, point 4): in the reference both are the same sum, to the sat.
@immutable
sealed class PayoutFirstInvoice {
  const PayoutFirstInvoice();
}

/// Fewer sats than [first], the largest the payout panel asked at 6 or 8 for the contract, as this run of the app kept it: a red alert in two lines, its explanation in the detail; beside it no line that reassures (« A small gap is normal », the gap « (indicative) »).
final class PayoutFirstFewer extends PayoutFirstInvoice {
  final Sats first;

  const PayoutFirstFewer(this.first);

  @override
  bool operator ==(Object other) =>
      other is PayoutFirstFewer && other.first == first;

  @override
  int get hashCode => Object.hash(PayoutFirstFewer, first);
}

/// Nothing kept of the invoice asked at 6 or 8 for the contract (the app started again since, or the trade screen not shown then): « Not compared with the first invoice », and never « A small gap is normal ».
final class PayoutFirstUnknown extends PayoutFirstInvoice {
  const PayoutFirstUnknown();

  @override
  bool operator ==(Object other) => other is PayoutFirstUnknown;

  @override
  int get hashCode => 9;
}

/// The comparison with the Bull wallet's price: [expected] the sats the contract's amount is worth at it with the order's premium, rounded down; [price] its line (the amount, the price and the premium, written by the trade screen); [gap] the gap of [given] from it, written with its sign; [warns] beyond the owner's threshold ([threshold], written), the red alert; [small] whether the gap is within the threshold both ways (`PriceCheckLines.smallGap`), the only case where « A small gap is normal » is said.
final class PayoutCheckCompared extends PayoutCheck {
  final Sats expected;
  final String price;
  final String gap;
  final bool warns;
  final String threshold;
  final bool small;

  const PayoutCheckCompared({
    required Sats given,
    required this.expected,
    required this.price,
    required this.gap,
    required this.warns,
    required this.threshold,
    required this.small,
    PayoutFirstInvoice? first,
  }) : super(given, first: first);

  @override
  bool get priceAlert => warns;

  @override
  bool operator ==(Object other) =>
      other is PayoutCheckCompared &&
      other.given == given &&
      other.expected == expected &&
      other.price == price &&
      other.gap == gap &&
      other.warns == warns &&
      other.threshold == threshold &&
      other.small == small &&
      other.first == first;

  @override
  int get hashCode =>
      Object.hash(given, expected, price, gap, warns, threshold, small, first);
}

/// The Bull wallet's price could not be read: « Amount not checked », in orange, with « Retry ».
final class PayoutCheckUnverified extends PayoutCheck {
  const PayoutCheckUnverified(super.given, {super.first});

  @override
  bool get priceAlert => true;

  @override
  bool operator ==(Object other) =>
      other is PayoutCheckUnverified &&
      other.given == given &&
      other.first == first;

  @override
  int get hashCode => Object.hash(PayoutCheckUnverified, given, first);
}

/// The Bull wallet does not price the order's currency: the grey « not quoted » line (the owner's decision of 2026-11-24, #250, #249); for an order made here whose contract's sats are more than the owner's threshold against the buyer since the order was made, [against] the gap written without its sign and the currency's code, the orange alert under it and its explanation in the detail (the owner's decision of 2026-11-20, #237); never for an order taken here.
final class PayoutCheckNotPriced extends PayoutCheck {
  final ({String gap, String currency})? against;

  const PayoutCheckNotPriced(super.given, {this.against, super.first});

  @override
  bool get priceAlert => against != null;

  @override
  bool operator ==(Object other) =>
      other is PayoutCheckNotPriced &&
      other.given == given &&
      other.against == against &&
      other.first == first;

  @override
  int get hashCode => Object.hash(PayoutCheckNotPriced, given, against, first);
}

/// This device's records of the trade could not be read, so nothing was compared (#237): « Amount not checked », in orange, with « Retry », and its own second line, the Bull wallet's price having never been asked.
final class PayoutCheckTermsUnread extends PayoutCheck {
  const PayoutCheckTermsUnread(super.given);

  @override
  bool get priceAlert => true;

  @override
  bool operator ==(Object other) =>
      other is PayoutCheckTermsUnread && other.given == given;

  @override
  int get hashCode => Object.hash(PayoutCheckTermsUnread, given);
}

/// The lean breakdown of the payout's sats, on arrival (#228; layout and words validated by the owner on 2026-11-24, #250): « Breakdown, in sats », the sats paid by the coordinator, the fees taken from them and, in bold, what the user will receive, then the gap to the Bull price ([PayoutCheckLines]). Under them, « Show details » opens the detail ([PayoutBreakdownDetail]) in the card, as the validated mock-up draws it (the owner's decision of 2026-11-24); what is under the card moves down.
///
/// On the Lightning tab ([lightning]) with an invoice: « Routing and swap fees » once this wallet made the invoice ([PayoutBreakdown.swap]), « Routing fees » before or for an invoice pasted from another wallet; « You will receive » their difference with the sats paid ([PayoutBreakdown.received]), so the lines add up by construction. On the Onchain tab, the sats paid and the gap only: the reference's table under the tabs says the swap's fees and the final amount.
///
/// Amounts aligned to the right in tabular figures, the total in bold under a rule; a label wraps rather than being cut, and under a large text the amount goes under its label. The project's own: the reference shows no breakdown.
class PayoutBreakdownView extends StatelessWidget {
  final PayoutBreakdown breakdown;
  final PayoutCheck? check;
  final bool lightning;

  /// Whether nothing is compared at this step (15, a new invoice after a failed payout, on a page without the owner's rule, a composition the app does not use: since #237 the rule runs at 15 wherever it is on the page): a discreet line under the title says so, so that the breakdown does not look checked (security review of #228, C2).
  final bool notCompared;

  /// « Retry » of « Amount not checked »; `null` draws none.
  final VoidCallback? onRetry;

  /// Whether the detail is open; [onToggleDetail] opens or closes it, `null` draws no « Show details » and no detail.
  final bool detailOpen;
  final VoidCallback? onToggleDetail;

  /// Copies the invoice's amount, in the detail; `null` draws no copy.
  final VoidCallback? onCopy;

  /// Whether the amount was just copied: the icon then shows it.
  final bool copied;

  const PayoutBreakdownView({
    super.key,
    required this.breakdown,
    this.check,
    this.lightning = true,
    this.notCompared = false,
    this.onRetry,
    this.detailOpen = false,
    this.onToggleDetail,
    this.onCopy,
    this.copied = false,
  });

  /// The keys of « Show details » and of the detail, for the tests.
  static const detailToggle = ValueKey('payout-detail-toggle');
  static const detail = ValueKey('payout-detail');

  /// The keys of the rows, for the tests.
  static const notComparedLine = ValueKey('payout-breakdown-not-compared');
  static const givenRow = ValueKey('payout-breakdown-given');
  static const feesRow = ValueKey('payout-breakdown-fees');
  static const receivedRow = ValueKey('payout-breakdown-received');

  /// [check] when it is for the very sats [breakdown] shows as paid; `null` otherwise: a figure that changed since the rule compared is compared again by the rule, never drawn against an older comparison.
  static PayoutCheck? drawnOf(PayoutBreakdown? breakdown, PayoutCheck? check) =>
      breakdown != null && check != null && check.given == breakdown.given
      ? check
      : null;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final formats = P2pFormats.of(context);
    String sats(Sats sats) => formats.bigSats(sats.value);
    String less(Sats sats) => formats.bigSats(-sats.value);
    final drawn = drawnOf(breakdown, check);
    // The figure at fault: beyond the Bull wallet's threshold, or at 15 fewer sats than at 6 or 8 (#281).
    final warns =
        (drawn is PayoutCheckCompared && drawn.warns) ||
        (drawn?.fewer ?? false);
    final fees = breakdown.fees;
    final received = breakdown.received;
    return AmountCard(
      children: [
        WordFitText(
          l10n.p2pPayoutBreakdownTitle,
          style: text.labelMedium?.copyWith(color: colors.textMuted),
        ),
        if (notCompared && drawn == null)
          WordFitText(
            l10n.p2pPayoutBreakdownNotCompared,
            key: notComparedLine,
            style: text.bodySmall?.copyWith(color: colors.textMuted),
          ),
        const Gap(BullSpacing.xxs),
        // Beyond the rule's threshold the figure at fault in the alert colour, beside the gap's alert (the owner's choice of 2026-11-20, #250).
        AmountRow(
          key: givenRow,
          label: l10n.p2pPayoutBreakdownGiven,
          amount: sats(breakdown.given),
          tone: warns ? AmountRowTone.alert : AmountRowTone.plain,
        ),
        if (lightning && fees != null && received != null) ...[
          AmountRow(
            key: feesRow,
            label: breakdown.swap == null
                ? l10n.p2pPayoutBreakdownRoutingFees
                : l10n.p2pPayoutBreakdownFees,
            amount: less(fees),
          ),
          Divider(
            height: BullSpacing.xs,
            thickness: 1,
            color: colors.outlineVariant,
          ),
          AmountRow(
            key: receivedRow,
            label: l10n.p2pPayoutBreakdownReceived,
            amount: sats(received),
            tone: AmountRowTone.total,
          ),
        ],
        if (drawn != null) PayoutCheckLines(check: drawn, onRetry: onRetry),
        // In the card, under the gap's line (or the alert's two lines, or « not quoted »), as the validated mock-up draws it (the owner's decision of 2026-11-24).
        if (onToggleDetail case final toggle?) ...[
          DetailToggle(key: detailToggle, open: detailOpen, onPressed: toggle),
          if (detailOpen)
            PayoutBreakdownDetail(
              key: detail,
              breakdown: breakdown,
              check: drawn,
              lightning: lightning,
              onCopy: onCopy,
              copied: copied,
            ),
        ],
      ],
    );
  }
}

/// What the rule said of the sats paid, in the breakdown or, when no breakdown can draw it, alone above the payout panel's form (an alert is never left out), drawn by [PriceCheckLines]: the gap to the Bull price as information; beyond the threshold the red alert in two lines, its bold line in the gap's place and the two figures under it (« the coordinator pays »); « Amount not checked » in orange with « Retry » and its second line; the grey « not quoted » line. Always visible without a tap; the explanations are in the detail ([PayoutBreakdownDetail]).
class PayoutCheckLines extends StatelessWidget {
  final PayoutCheck check;
  final VoidCallback? onRetry;

  /// Whether the alert's explanation is said under its two lines: where the check is drawn alone above the form, with no breakdown and so no detail to hold it (#250).
  final bool explained;

  const PayoutCheckLines({
    super.key,
    required this.check,
    this.onRetry,
    this.explained = false,
  });

  static const explanation = PriceCheckLines.explanationLine;

  static const gapRow = PriceCheckLines.gapRow;
  static const alertRow = PriceCheckLines.alertRow;
  static const alertFigures = PriceCheckLines.alertFigures;
  static const unverifiedRow = PriceCheckLines.unverifiedRow;
  static const unverifiedLine = PriceCheckLines.unverifiedLine;
  static const notPricedRow = PriceCheckLines.notPricedRow;

  /// The keys of the lines of 15 against the invoice of 6 or 8 (#281), for the tests.
  static const fewerRow = ValueKey('payout-first-fewer');
  static const fewerFigures = ValueKey('payout-first-fewer-figures');
  static const fewerExplanation = ValueKey('payout-first-fewer-explanation');
  static const unknownLine = ValueKey('payout-first-unknown');
  static const unknownExplanation = ValueKey(
    'payout-first-unknown-explanation',
  );

  @override
  Widget build(BuildContext context) {
    final price = _priceLines(context);
    final first = _firstLines(context);
    if (first == null) return price ?? const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [?price, first],
    );
  }

  /// At 15, the lines against the invoice of 6 or 8 (#281): fewer sats, the red alert in two lines (its explanation under them where no detail holds it); nothing kept, the discreet line; `null` otherwise.
  Widget? _firstLines(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    Widget line(Key key, String words, Color color) => Padding(
      padding: const EdgeInsets.only(bottom: BullSpacing.xxs / 2),
      child: WordFitText(
        words,
        key: key,
        style: text.bodyMedium?.copyWith(color: color),
      ),
    );
    return switch (check.first) {
      PayoutFirstFewer(:final first) => Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AmountRow(
              key: fewerRow,
              label: l10n.p2pPayoutFirstFewer,
              tone: AmountRowTone.alert,
              icon: Icons.warning_amber_rounded,
            ),
            line(
              fewerFigures,
              l10n.p2pPayoutFirstFewerFigures(
                formats.bigSats(first.value),
                formats.bigSats(check.given.value),
              ),
              colors.error,
            ),
            if (explained)
              line(
                fewerExplanation,
                l10n.p2pPayoutFirstFewerDetail,
                colors.error,
              ),
          ],
        ),
      ),
      PayoutFirstUnknown() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WordFitText(
            l10n.p2pPayoutFirstUnknown,
            key: unknownLine,
            style: text.bodySmall?.copyWith(color: colors.textMuted),
          ),
          if (explained)
            line(
              unknownExplanation,
              l10n.p2pPayoutFirstUnknownDetail,
              colors.textMuted,
            ),
        ],
      ),
      null => null,
    };
  }

  /// The lines of the comparison with the Bull wallet's price; `null` for a gap within the threshold beside the alert of fewer sats than at 6 or 8, a line « (indicative) » that would reassure beside it (#281).
  Widget? _priceLines(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    return switch (check) {
      PayoutCheckCompared(:final warns) when !warns && check.fewer => null,
      PayoutCheckCompared(:final warns, :final gap) when !warns =>
        PriceCheckLines.gap(gap),
      PayoutCheckCompared(
        :final gap,
        :final expected,
        :final given,
        :final threshold,
      ) =>
        PriceCheckLines.against(
          gap,
          figures: l10n.p2pPayoutBreakdownAgainstFigures(
            formats.bigSats(expected.value),
            formats.bigSats(given.value),
          ),
          explanation: explained
              ? l10n.p2pPayoutBreakdownAgainstDetail(threshold)
              : null,
        ),
      PayoutCheckUnverified() => PriceCheckLines.unverified(
        onRetry: onRetry,
        explanation: explained ? l10n.p2pPayoutBreakdownUnverifiedDetail : null,
      ),
      PayoutCheckTermsUnread() => PriceCheckLines.unverified(
        onRetry: onRetry,
        line: l10n.p2pPayoutRateTermsUnreadLine,
        explanation: explained ? l10n.p2pPayoutRateTermsUnreadDetail : null,
      ),
      PayoutCheckNotPriced(:final against) => PriceCheckLines.notPriced(
        against: switch (against) {
          (:final gap, currency: _) => l10n.p2pRateAgainstSinceMade(gap),
          null => null,
        },
        explanation: switch (against) {
          (gap: _, :final currency) when explained =>
            l10n.p2pRateAgainstSinceMadeDetail(currency),
          _ => null,
        },
      ),
    };
  }
}

/// The breakdown's detail, opened by « Show details » inside the breakdown's card, under the gap's line (the validated mock-up of the payout screen, the owner's decision of 2026-11-24, #250), in this order: what Bull Wallet expected and its price's line, the coordinator's fee already deducted, on the Lightning tab the routing fees, « Your invoice » with the copy of its amount (the reference's copy beside « Submit invoice for … sats », `Forms/LightningPayout.tsx:556-577`) and the swap service's fee, then one paragraph: « A small gap is normal… » beside a gap within the threshold both ways only, never beside an alert; the red alert's explanation; « Amount not checked »'s.
class PayoutBreakdownDetail extends StatelessWidget {
  final PayoutBreakdown breakdown;

  /// The rule's check as the summary draws it ([PayoutBreakdownView.drawnOf]).
  final PayoutCheck? check;
  final bool lightning;

  /// Copies the invoice's amount; `null` draws no copy.
  final VoidCallback? onCopy;

  /// Whether the amount was just copied: the icon then shows it.
  final bool copied;

  const PayoutBreakdownDetail({
    super.key,
    required this.breakdown,
    this.check,
    this.lightning = true,
    this.onCopy,
    this.copied = false,
  });

  static const valueRow = ValueKey('payout-breakdown-value');
  static const priceLine = ValueKey('payout-breakdown-price');
  static const feeRow = ValueKey('payout-breakdown-coordinator-fee');
  static const budgetRow = ValueKey('payout-breakdown-routing-budget');
  static const invoiceRow = ValueKey('payout-breakdown-invoice');
  static const swapRow = ValueKey('payout-breakdown-swap-fee');
  static const explanation = ValueKey('payout-breakdown-explanation');

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final formats = P2pFormats.of(context);
    String sats(Sats sats) => formats.bigSats(sats.value);
    String less(Sats sats) => formats.bigSats(-sats.value);
    final check = this.check;
    final fee = breakdown.coordinatorFee;
    final budget = breakdown.routingBudget;
    final invoice = breakdown.invoice;
    final swap = breakdown.swap;
    final paragraph = switch (check) {
      // Within the threshold both ways only (functional review of #268, C1); never at 15 when the sum is not known to be that of 6 or 8, fewer or not kept (#281).
      PayoutCheckCompared(warns: false, small: false) => null,
      PayoutCheckCompared(warns: false, first: PayoutFirstInvoice()) => null,
      PayoutCheckCompared(warns: false) => (
        l10n.p2pPayoutBreakdownSmallGap,
        colors.text,
      ),
      PayoutCheckCompared(:final threshold) => (
        l10n.p2pPayoutBreakdownAgainstDetail(threshold),
        colors.error,
      ),
      PayoutCheckUnverified() => (
        l10n.p2pPayoutBreakdownUnverifiedDetail,
        colors.warning,
      ),
      PayoutCheckTermsUnread() => (
        l10n.p2pPayoutRateTermsUnreadDetail,
        colors.warning,
      ),
      // The orange alert of #237: its explanation, the owner's words.
      PayoutCheckNotPriced(against: (gap: _, :final currency)) => (
        l10n.p2pRateAgainstSinceMadeDetail(currency),
        colors.warning,
      ),
      PayoutCheckNotPriced() || null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (check case PayoutCheckCompared(:final expected, :final price)) ...[
          AmountRow(
            key: valueRow,
            label: l10n.p2pPayoutBreakdownValue,
            amount: sats(expected),
          ),
          AmountRow(key: priceLine, label: price, tone: AmountRowTone.detail),
        ],
        if (fee != null)
          AmountRow(
            key: feeRow,
            label: l10n.p2pPayoutBreakdownCoordinatorFee,
            amount: sats(fee),
          ),
        if (lightning && budget != null && invoice != null) ...[
          AmountRow(
            key: budgetRow,
            label: l10n.p2pPayoutBreakdownRoutingBudget,
            amount: less(budget),
          ),
          AmountRow(
            key: invoiceRow,
            label: l10n.p2pPayoutBreakdownInvoice,
            amount: sats(invoice),
            trailing: switch (onCopy) {
              final onCopy? => IconButton(
                tooltip: copied
                    ? l10n.p2pCommonCopied
                    : l10n.p2pPayoutCopyAmount,
                onPressed: onCopy,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  copied ? Icons.check : Icons.content_copy,
                  size: 18,
                  color: colors.primary,
                ),
              ),
              null => null,
            },
          ),
          if (swap != null)
            AmountRow(
              key: swapRow,
              label: l10n.p2pPayoutBreakdownSwapFee,
              amount: less(swap.fee),
            ),
        ],
        if (paragraph case (final line, final color)) ...[
          const Gap(BullSpacing.xs),
          WordFitText(
            line,
            key: explanation,
            style: text.bodyMedium?.copyWith(color: color),
          ),
        ],
        // At 15, the explanation of the lines against the invoice of 6 or 8, after the Bull wallet's (#281): an alert never silences another.
        ...switch (check?.first) {
          PayoutFirstFewer() => [
            const Gap(BullSpacing.xs),
            WordFitText(
              l10n.p2pPayoutFirstFewerDetail,
              key: PayoutCheckLines.fewerExplanation,
              style: text.bodyMedium?.copyWith(color: colors.error),
            ),
          ],
          PayoutFirstUnknown() => [
            const Gap(BullSpacing.xs),
            WordFitText(
              l10n.p2pPayoutFirstUnknownDetail,
              key: PayoutCheckLines.unknownExplanation,
              style: text.bodyMedium?.copyWith(color: colors.text),
            ),
          ],
          null => const <Widget>[],
        },
      ],
    );
  }
}
