import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/trade_chat_step.dart';
import '../../domain/trade/trade_status.dart';
import '../../domain/trade/trade_watch.dart';
import '../../presentation/p2p_formats.dart';
import '../../presentation/trade_cubit.dart';
import '../../presentation/trade_l10n.dart';
import '../../presentation/trade_summary_export.dart';
import '../widgets/coordinator_avatar.dart';
import '../widgets/robot_avatar.dart';
import '../widgets/word_fit_text.dart';
import 'chat_step_panel.dart';

/// The buyer's « Trade finished! » at 14 (`TradeBox/Prompts/Successful.tsx`, commit ff1998c; #95), from the top: « Rate your trade experience » and its five stars, « Rate your host » ([hostRating]), « Your TXID » or « Sending coins » for an on-chain payout, then the « Trade Summary » ([TradeSummaryCard]).
///
/// A tap on a star sends `rate_platform` once through the trade's cubit, for the status shown (`TradeCubit.rate`), as the reference sends each change of its stars; while it runs the stars are off and a line says what it waits for; what it gave is said under them, nothing when it was recorded (the reference says nothing either).
/// The two ratings are one under the other, where the reference puts them side by side, for the width of a phone.
/// Left out, each declared in `AGENTS.md`: « Start Again » and « Renew », whose order creation does not exist here.
/// The copies are made on the user's tap only; nothing here opens a link.
class SuccessfulPanel extends StatefulWidget {
  final TradeSeen seen;
  final Succeeded status;
  final CoordinatorOrder? order;

  /// The long alias of the trade's coordinator.
  final String coordinator;
  final ChatStepState chatStep;

  /// Whether another action of the trade runs (a cancel, a payout): the stars are off meanwhile.
  final bool otherActionRunning;

  /// Whether the screen may send the rating (`TradeCubit.offersRating`).
  final bool offersRating;

  /// « Rate your host » (`HostRatingSection`), shown under « Rate your trade experience » when the screen offers that one; `null` where the feature holds no robot.
  final Widget? hostRating;

  const SuccessfulPanel({
    super.key,
    required this.seen,
    required this.status,
    required this.order,
    required this.coordinator,
    required this.chatStep,
    required this.otherActionRunning,
    required this.offersRating,
    this.hostRating,
  });

  @override
  State<SuccessfulPanel> createState() => _SuccessfulPanelState();
}

class _SuccessfulPanelState extends State<SuccessfulPanel> {
  /// The star last tapped, kept by the panel as the reference's `Rating` keeps its own.
  int? _stars;

  /// What was copied last, for « Copied! » under it.
  String? _copied;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  void _rate(int stars) {
    final rating = PlatformRating.of(stars);
    if (rating == null) return;
    setState(() => _stars = stars);
    unawaited(context.read<TradeCubit>().rate(widget.seen, rating));
  }

  Future<void> _copy(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
    } on PlatformException {
      return;
    }
    if (!mounted) return;
    setState(() => _copied = value);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final body = Theme.of(context).textTheme.bodyMedium;
    final seen = widget.seen;
    final chatStep = widget.chatStep;
    final offered = widget.offersRating && ChatStepAction.rate.offeredAt(seen);
    final busy = chatStep is ChatStepRunning || widget.otherActionRunning;
    final waiting = switch (chatStep) {
      ChatStepRunning(:final progress, :final action) => progress.toText(
        context,
        coordinator: widget.coordinator,
        action: action,
      ),
      _ => null,
    };
    final payout = widget.status.onchainPayout;
    final summary = widget.status.summary;
    final order = widget.order;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.offersRating) ...[
          WordFitText(
            l10n.p2pEndRateTrade,
            textAlign: TextAlign.center,
            style: body?.copyWith(color: colors.text),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (
                var star = PlatformRating.min;
                star <= PlatformRating.max;
                star++
              )
                Semantics(
                  selected: _stars == star,
                  child: IconButton(
                    key: ValueKey('trade-rate-star-$star'),
                    tooltip: l10n.p2pEndRateStar('$star'),
                    onPressed: offered && !busy ? () => _rate(star) : null,
                    icon: Icon(
                      star <= (_stars ?? 0) ? Icons.star : Icons.star_border,
                      size: 32,
                      color: offered && !busy
                          ? colors.warning
                          : colors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          if (!offered)
            _Live(l10n.p2pEndNeedsRead, color: colors.textMuted)
          else if (waiting != null) ...[
            _Live(waiting, color: colors.textMuted),
            const Gap(BullSpacing.xs),
            LinearProgressIndicator(
              color: colors.primary,
              semanticsLabel: waiting,
            ),
            if (chatStep case ChatStepRunning(waitedLong: true)) ...[
              const Gap(BullSpacing.xs),
              _Live(
                l10n.p2pRobotStillWaiting(widget.coordinator),
                color: colors.textMuted,
              ),
            ],
          ],
          if (chatStep case ChatStepIdle(:final notice?, :final action)) ...[
            const Gap(BullSpacing.sm),
            ChatStepNoticeLine(
              notice: notice,
              coordinator: widget.coordinator,
              action: action,
            ),
          ],
          if (widget.hostRating case final hostRating?) ...[
            const Gap(BullSpacing.md),
            Divider(color: colors.outlineVariant, height: 1),
            const Gap(BullSpacing.sm),
            hostRating,
          ],
        ],
        // The transaction once it is in the mempool, or the payment waiting in the coordinator's queue, each with its copy (`Successful.tsx:229-270`).
        if (payout case OnchainPayout(:final txid?)) ...[
          const Gap(BullSpacing.md),
          _CopyLine(
            key: const ValueKey('trade-onchain-txid'),
            text: l10n.p2pEndYourTxid,
            color: colors.success,
            leading: Icon(Icons.check_circle_outline, color: colors.success),
            copyLabel: l10n.p2pEndCopyTxid,
            onCopy: () => unawaited(_copy(txid)),
            copied: _copied == txid,
          ),
        ] else if (payout case OnchainPayout(
          queued: true,
          :final address?,
        )) ...[
          const Gap(BullSpacing.md),
          _CopyLine(
            key: const ValueKey('trade-onchain-queued'),
            text: l10n.p2pEndSendingCoins,
            color: colors.info,
            leading: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.info,
              ),
            ),
            copyLabel: l10n.p2pEndCopyAddress,
            onCopy: () => unawaited(_copy(address)),
            copied: _copied == address,
          ),
        ],
        if (summary != null && order != null) ...[
          const Gap(BullSpacing.md),
          TradeSummaryCard(
            summary: summary,
            order: order,
            coordinator: widget.coordinator,
          ),
        ],
      ],
    );
  }
}

/// A line of the reference's alerts with its copy button and, once copied, « Copied! ».
class _CopyLine extends StatelessWidget {
  final String text;
  final Color color;
  final Widget leading;
  final String copyLabel;
  final VoidCallback onCopy;
  final bool copied;

  const _CopyLine({
    super.key,
    required this.text,
    required this.color,
    required this.leading,
    required this.copyLabel,
    required this.onCopy,
    required this.copied,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BullSpacing.sm,
          vertical: BullSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ExcludeSemantics(child: leading),
                const Gap(BullSpacing.sm),
                Expanded(
                  child: WordFitText(
                    text,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: colors.text),
                  ),
                ),
                IconButton(
                  tooltip: copyLabel,
                  onPressed: onCopy,
                  icon: Icon(Icons.copy, size: 18, color: color),
                ),
              ],
            ),
            if (copied)
              Semantics(
                liveRegion: true,
                child: WordFitText(
                  l10n.p2pCommonCopied,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The views of the reference's toggle: the maker's side, the coordinator's figures, the taker's side.
enum _SummaryView { maker, platform, taker }

/// « Trade Summary » (`TradeBox/TradeSummary.tsx`, commit ff1998c; #95): « Export trade summary », which copies the summary as JSON as the reference does on a phone ([TradeSummaryExport]), the toggle « Maker » / the coordinator / « Taker », this robot's side first, and the rows of the side or of the coordinator.
///
/// Every figure is the coordinator's, as read and bounded by `CoordinatorOrder`; a figure it did not give is left out, where the reference writes its unit alone.
class TradeSummaryCard extends StatefulWidget {
  final TradeSummary summary;
  final CoordinatorOrder order;

  /// The long alias of the trade's coordinator.
  final String coordinator;

  const TradeSummaryCard({
    super.key,
    required this.summary,
    required this.order,
    required this.coordinator,
  });

  @override
  State<TradeSummaryCard> createState() => _TradeSummaryCardState();
}

/// What the last export gave.
enum _ExportOutcome { copied, copyFailed }

class _TradeSummaryCardState extends State<TradeSummaryCard> {
  late _SummaryView _view = widget.summary.isMaker
      ? _SummaryView.maker
      : _SummaryView.taker;
  _ExportOutcome? _exported;

  Future<void> _export() async {
    final order = widget.order;
    final robot = order.isMaker ? order.maker : order.taker;
    final text = TradeSummaryExport.text(
      TradeSummaryExport.of(
        widget.summary,
        coordinator: widget.coordinator,
        orderId: order.id,
        currencyCode: order.currency.code,
        robot: robot?.nickname ?? '',
      ),
    );
    _ExportOutcome outcome;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      outcome = _ExportOutcome.copied;
    } on PlatformException {
      outcome = _ExportOutcome.copyFailed;
    }
    if (mounted) setState(() => _exported = outcome);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final summary = widget.summary;
    final order = widget.order;
    final side = switch (_view) {
      _SummaryView.maker => summary.maker,
      _SummaryView.taker => summary.taker,
      _SummaryView.platform => null,
    };
    return DecoratedBox(
      key: const ValueKey('trade-summary'),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BullSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: WordFitText(
                    l10n.p2pSummaryTitle,
                    textAlign: TextAlign.center,
                    style: text.titleMedium?.copyWith(color: colors.textMuted),
                  ),
                ),
                // Offered only with both sides read: an export without the peer's would say « Copied! » for half a summary.
                if (summary.peer != null)
                  IconButton(
                    key: const ValueKey('trade-summary-export'),
                    tooltip: l10n.p2pSummaryExport,
                    onPressed: () => unawaited(_export()),
                    icon: Icon(
                      Icons.ios_share,
                      size: 20,
                      color: colors.primary,
                    ),
                  ),
              ],
            ),
            if (_exported case final outcome?)
              Semantics(
                liveRegion: true,
                child: WordFitText(
                  switch (outcome) {
                    _ExportOutcome.copied => l10n.p2pCommonCopied,
                    _ExportOutcome.copyFailed =>
                      l10n.p2pSummaryExportCopyFailed,
                  },
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: outcome == _ExportOutcome.copied
                        ? colors.textMuted
                        : colors.error,
                  ),
                ),
              ),
            const Gap(BullSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The peer's side only when the coordinator gave a valid one.
                if (summary.maker != null)
                  Expanded(
                    child: _ToggleTile(
                      key: const ValueKey('trade-summary-maker'),
                      selected: _view == _SummaryView.maker,
                      onTap: () => setState(() => _view = _SummaryView.maker),
                      avatar: RobotAvatar(seed: order.maker.hex, size: 20),
                      label: l10n.p2pOrderFeeMaker,
                    ),
                  ),
                Expanded(
                  child: Tooltip(
                    message: widget.coordinator,
                    child: _ToggleTile(
                      key: const ValueKey('trade-summary-platform'),
                      selected: _view == _SummaryView.platform,
                      onTap: () =>
                          setState(() => _view = _SummaryView.platform),
                      avatar: CoordinatorAvatar(
                        coordinator: order.coordinator,
                        size: 20,
                      ),
                      semanticLabel: widget.coordinator,
                    ),
                  ),
                ),
                if (summary.taker != null)
                  Expanded(
                    child: _ToggleTile(
                      key: const ValueKey('trade-summary-taker'),
                      selected: _view == _SummaryView.taker,
                      onTap: () => setState(() => _view = _SummaryView.taker),
                      avatar: switch (order.taker) {
                        final taker? => RobotAvatar(seed: taker.hex, size: 20),
                        null => null,
                      },
                      label: l10n.p2pOrderFeeTaker,
                    ),
                  ),
              ],
            ),
            const Gap(BullSpacing.sm),
            if (_view == _SummaryView.platform)
              ..._platformRows(context)
            else if (side != null)
              ..._sideRows(context, side, maker: _view == _SummaryView.maker),
          ],
        ),
      ),
    );
  }

  List<Widget> _sideRows(
    BuildContext context,
    TradeSideSummary side, {
    required bool maker,
  }) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final colors = context.bull;
    final buyer = side.isBuyer;
    final btc = buyer ? side.receivedSats : side.sentSats;
    String satsPercent(int sats, String percent) =>
        l10n.p2pSummarySatsPercent(formats.sats(sats), percent);
    return [
      _SummaryRow(
        icon: Icons.account_box,
        first: (
          buyer ? l10n.p2pBookRoleBuyer : l10n.p2pBookRoleSeller,
          l10n.p2pSummaryUserRole,
        ),
        second: switch (side.fiatAmount) {
          final fiat? => (
            '${formats.summaryNumber(fiat)} ${widget.order.currency.code}',
            buyer ? l10n.p2pSummarySent : l10n.p2pSummaryReceived,
          ),
          null => null,
        },
      ),
      _SummaryRow(
        icon: Icons.currency_bitcoin,
        first: switch (btc) {
          final sats? => (
            l10n.p2pSummarySats(formats.sats(sats.value.toInt())),
            buyer ? l10n.p2pSummaryBtcReceived : l10n.p2pSummaryBtcSent,
          ),
          null => null,
        },
        second: switch ((side.tradeFeeSats, side.tradeFeeFraction)) {
          (final fee?, final fraction?) => (
            satsPercent(fee, formats.summaryFeePercent(fraction)),
            l10n.p2pSummaryTradeFee,
          ),
          _ => null,
        },
      ),
      if (side.isSwap)
        _SummaryRow(
          icon: Icons.link,
          first: switch ((side.swapFeeSats, side.swapFeePercent)) {
            (final fee?, final percent?) => (
              satsPercent(fee.value.toInt(), formats.summaryNumber(percent)),
              l10n.p2pSummaryOnchainSwapFee,
            ),
            _ => null,
          },
          second: switch (side.miningFeeSats) {
            final fee? => (
              l10n.p2pSummarySats(formats.sats(fee.value.toInt())),
              l10n.p2pPayoutMiningFee,
            ),
            null => null,
          },
        ),
      _SummaryRow(
        icon: Icons.lock_open,
        iconColor: colors.success,
        first: switch ((side.bondSats, side.bondPercent)) {
          (final bond?, final percent?) => (
            satsPercent(bond.value.toInt(), formats.summaryNumber(percent)),
            maker ? l10n.p2pSummaryMakerBond : l10n.p2pTakerBond,
          ),
          _ => null,
        },
        second: (l10n.p2pSummaryUnlocked, null),
        secondColor: colors.success,
      ),
    ];
  }

  List<Widget> _platformRows(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final formats = P2pFormats.of(context);
    final summary = widget.summary;
    return [
      if (summary.tradeRevenueSats case final revenue?)
        _SummaryRow(
          icon: Icons.account_balance,
          first: (
            l10n.p2pSummarySats(formats.sats(revenue)),
            l10n.p2pSummaryRevenue,
          ),
        ),
      if (summary.routingBudgetSats case final budget?)
        _SummaryRow(
          icon: Icons.route,
          first: (
            l10n.p2pSummarySats(formats.summaryNumber(budget)),
            l10n.p2pSummaryRoutingBudget,
          ),
        ),
      if (summary.contractExchangeRate case final rate?)
        _SummaryRow(
          icon: Icons.price_change,
          first: (
            l10n.p2pSummaryRate(
              formats.summaryRate(rate),
              widget.order.currency.code,
            ),
            l10n.p2pSummaryContractRate,
          ),
        ),
    ];
  }
}

/// A row of the summary, as the reference's `ListItem`: an icon, then one or two figures, each above its label.
class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final (String, String?)? first;
  final (String, String?)? second;
  final Color? secondColor;

  /// From this text scale on, a row's two figures are stacked rather than side by side, so that each has the row's whole width.
  static const stackedFrom = 1.5;

  const _SummaryRow({
    required this.icon,
    this.iconColor,
    required this.first,
    this.second,
    this.secondColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final textTheme = Theme.of(context).textTheme;
    final stacked =
        MediaQuery.textScalerOf(context).scale(14) / 14 >= stackedFrom;
    Widget? item((String, String?)? item, {Color? color, bool bold = false}) =>
        switch (item) {
          (final primary, final secondary) => MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WordFitText(
                  primary,
                  style: textTheme.bodyMedium?.copyWith(
                    color: color ?? colors.text,
                    fontWeight: bold ? FontWeight.bold : null,
                  ),
                ),
                if (secondary != null)
                  WordFitText(
                    secondary,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          null => null,
        };
    final items = [
      ?item(first),
      if (second != null || secondColor != null)
        ?item(second, color: secondColor, bold: secondColor != null),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BullSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: ExcludeSemantics(
              child: Icon(icon, color: iconColor ?? colors.onSurfaceVariant),
            ),
          ),
          if (stacked)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, child) in items.indexed) ...[
                    if (index > 0) const Gap(BullSpacing.xs),
                    child,
                  ],
                ],
              ),
            )
          else
            for (final child in items) Expanded(child: child),
        ],
      ),
    );
  }
}

/// One view of the summary's toggle, as the reference's `ToggleButton`: an avatar and, for a side, its label, which wraps at word boundaries only.
class _ToggleTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget? avatar;
  final String? label;
  final String? semanticLabel;

  const _ToggleTile({
    super.key,
    required this.selected,
    required this.onTap,
    required this.avatar,
    this.label,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final label = this.label;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: selected ? colors.surfaceContainerHighest : colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BullSpacing.xs,
              vertical: BullSpacing.xs,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ?avatar,
                if (label != null)
                  WordFitText(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? colors.text : colors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A line read out as it changes.
class _Live extends StatelessWidget {
  final String text;
  final Color color;

  const _Live(this.text, {required this.color});

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: WordFitText(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
    ),
  );
}
