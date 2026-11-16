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
import 'chat_step_panel.dart';

/// The buyer's « Trade finished! » at 14 (`TradeBox/Prompts/Successful.tsx`, commit ff1998c; #95), from the top: « Rate your trade experience » and its five stars, « Your TXID » or « Sending coins » for an on-chain payout, then the « Trade Summary » ([TradeSummaryCard]).
///
/// A tap on a star sends `rate_platform` once through the trade's cubit, for the status shown (`TradeCubit.rate`), as the reference sends each change of its stars; while it runs the stars are off and a line says what it waits for; what it gave is said under them, nothing when it was recorded (the reference says nothing either).
/// Left out, each declared in `AGENTS.md`: « Rate your host », which the reference publishes on Nostr only, and its thanks; « Start Again » and « Renew », whose order creation does not exist here.
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

  const SuccessfulPanel({
    super.key,
    required this.seen,
    required this.status,
    required this.order,
    required this.coordinator,
    required this.chatStep,
    required this.otherActionRunning,
    required this.offersRating,
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
          Text(
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
                  child: Text(
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
                child: Text(
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
                  child: Text(
                    l10n.p2pSummaryTitle,
                    textAlign: TextAlign.center,
                    style: text.titleMedium?.copyWith(color: colors.textMuted),
                  ),
                ),
                IconButton(
                  key: const ValueKey('trade-summary-export'),
                  tooltip: l10n.p2pSummaryExport,
                  onPressed: () => unawaited(_export()),
                  icon: Icon(Icons.ios_share, size: 20, color: colors.primary),
                ),
              ],
            ),
            if (_exported case final outcome?)
              Semantics(
                liveRegion: true,
                child: Text(
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
            SegmentedButton<_SummaryView>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: _SummaryView.maker,
                  icon: RobotAvatar(seed: order.maker.hex, size: 20),
                  label: Text(l10n.p2pOrderFeeMaker),
                ),
                ButtonSegment(
                  value: _SummaryView.platform,
                  tooltip: widget.coordinator,
                  label: Semantics(
                    label: widget.coordinator,
                    child: CoordinatorAvatar(
                      coordinator: order.coordinator,
                      size: 20,
                    ),
                  ),
                ),
                ButtonSegment(
                  value: _SummaryView.taker,
                  icon: switch (order.taker) {
                    final taker? => RobotAvatar(seed: taker.hex, size: 20),
                    null => null,
                  },
                  label: Text(l10n.p2pOrderFeeTaker),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (views) =>
                  setState(() => _view = views.first),
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
    Widget item((String, String?)? item, {Color? color, bool bold = false}) =>
        Expanded(
          child: switch (item) {
            (final primary, final secondary) => MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    primary,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: color ?? colors.text,
                      fontWeight: bold ? FontWeight.bold : null,
                    ),
                  ),
                  if (secondary != null)
                    Text(
                      secondary,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                ],
              ),
            ),
            null => const SizedBox.shrink(),
          },
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BullSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: ExcludeSemantics(
              child: Icon(icon, color: iconColor ?? colors.onSurfaceVariant),
            ),
          ),
          item(first),
          if (second != null || secondColor != null)
            item(second, color: secondColor, bold: secondColor != null),
        ],
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
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
    ),
  );
}
