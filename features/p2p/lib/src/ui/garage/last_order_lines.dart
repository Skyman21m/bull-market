import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/garage_key_fingerprint.dart';
import '../../domain/network_garage_key.dart';
import '../../domain/order_history.dart';
import '../../domain/robot_binding.dart';
import '../../domain/trade_record.dart';
import '../../presentation/coordinator_text.dart';
import '../../presentation/last_orders_cubit.dart';
import '../../presentation/order_history_cubit.dart';
import '../../presentation/p2p_formats.dart';
import '../trade/trade_record_row.dart';
import '../widgets/detail_toggle.dart';
import '../widgets/word_fit_text.dart';

/// « Last order #N » on the Garage profile, under the robot navigator (#216), as the reference shows its robot's last order there (`basic/GaragePage/GarageKeyProfile.tsx:214-230`, commit ff1998c), whose tap opens the order again so that it can still be renewed.
///
/// The reference's line is the robot shown's; here each trade has a robot of its own, so the lines come from the device's records ([LastOrdersCubit]): the last finished order made here and the last finished trade taken here, the newest end first, each with its coordinator, a tap opening its trade screen ([onOpen]). Nothing while the records are read or when there is none (the reference's « No existing orders found » stays the robot panel's, which reads the robot shown); when they cannot be read, the app's line that says so.
/// One tap opens one screen (security review of #220, R4): another tap does nothing until the Garage is shown again, or the screen opened is left; so one tap also shows its order's robot once (#227, `GarageProfile`).
/// With [historyKey] and an [OrderHistoryCubit] above, under the lines, « See history » (#253, design note `docs/design/phase-3-order-history.md`), an addition of Bull Market: only when the history holds an order the lines do not show; open, every finished order of every key of the network (#81), the newest end first, ten then « See more », each line its order number and coordinator, its side, made or taken here, the day of its end, its robot, and how it ended; a tap opens its order as a line above does, under the same guard. Folded at each arrival: when the Garage is covered by a page (a line tapped included) and when the app is hidden or paused, as the Garage Key shown is hidden then.
class LastOrderLines extends StatefulWidget {
  final Future<void> Function(TradeRecord record) onOpen;

  /// The Garage Key whose history is shown under the lines, which names each line's robot; `null` for no history.
  final NetworkGarageKey? historyKey;

  /// The number of each key of the words of the network, by its fingerprint (#81): each line of the history, which covers every key, says its key.
  final Map<GarageKeyFingerprint, int> keyNumbers;

  /// The fingerprint of the external Garage Key of the network, `null` when the vault keeps none or it cannot be read: its lines say « External Garage Key ». A robot of a key in neither says its robot alone.
  final GarageKeyFingerprint? externalKey;

  /// The trades in progress of another Garage Key than the one shown (#81, decided on 2026-11-26): each has a line « Trade in progress #N » above the « Last order #N » lines, its key, robot and coordinator in grey, which opens it as they do.
  final List<TradeRecord> inProgressElsewhere;

  const LastOrderLines({
    super.key,
    required this.onOpen,
    this.historyKey,
    this.keyNumbers = const {},
    this.externalKey,
    this.inProgressElsewhere = const [],
  });

  @override
  State<LastOrderLines> createState() => _LastOrderLinesState();
}

class _LastOrderLinesState extends State<LastOrderLines> {
  /// Whether a screen was opened by a tap and the Garage has not been shown again since.
  bool _opening = false;

  /// Whether the Garage was covered by another page since the tap.
  bool _covered = false;

  /// The nicknames of the robots of the history's lines drawn, by index, `null` for an index the key does not give back as it is: derived once each, never kept beyond this visit.
  final Map<int, String?> _nicknames = {};

  /// Folds the history when the app is hidden or paused.
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    if (widget.historyKey != null) {
      _lifecycle = AppLifecycleListener(onHide: _fold, onPause: _fold);
    }
  }

  @override
  void didUpdateWidget(LastOrderLines oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.historyKey, widget.historyKey)) {
      _nicknames.clear();
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  void _fold() {
    if (mounted && widget.historyKey != null) {
      context.read<OrderHistoryCubit>().fold();
    }
  }

  void _open(TradeRecord record, {required bool current}) {
    if (_opening || !current) return;
    _opening = true;
    unawaited(
      widget.onOpen(record).whenComplete(() {
        if (mounted) setState(() => _opening = false);
      }),
    );
  }

  /// The nickname of [robot] from the key shown, as « Last order #N » finds the robot it shows (#227).
  String? _nicknameOf(NetworkGarageKey key, RobotSlot robot) =>
      _nicknames.putIfAbsent(
        robot.accountIndex,
        () => key.robotOf(robot)?.identity.nickname,
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    // The Garage shown again after the page a tap opened: taps open again, even when that page was replaced rather than left.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (!current) {
      _covered = true;
      // A page over the Garage folds the history, so that coming back finds it folded (#253): after this frame, never while building.
      if (widget.historyKey != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fold());
      }
    } else if (_covered) {
      _covered = false;
      _opening = false;
    }
    final elsewhere = widget.inProgressElsewhere;
    return BlocBuilder<LastOrdersCubit, LastOrdersState>(
      builder: (context, state) {
        final last = switch (state) {
          LastOrdersLoading() ||
          LastOrdersListed(orders: []) => const SizedBox.shrink(),
          LastOrdersUnreadable() => Padding(
            padding: const EdgeInsets.only(top: BullSpacing.sm),
            child: Text(
              l10n.p2pRobotRecordsUnreadable,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: colors.error),
            ),
          ),
          LastOrdersListed(:final orders) => Padding(
            padding: const EdgeInsets.only(top: BullSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final record in orders)
                  TradeRecordRow(
                    key: ValueKey(('last-order', record.robot)),
                    record: record,
                    label: l10n.p2pRobotLastOrder('${record.orderId}'),
                    onTap: () => _open(record, current: current),
                  ),
              ],
            ),
          ),
        };
        final lines = elsewhere.isEmpty
            ? last
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: BullSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final record in elsewhere)
                          TradeRecordRow(
                            key: ValueKey(('in-progress', record.robot)),
                            record: record,
                            label: l10n.p2pGarageTradeInProgress(
                              '${record.orderId}',
                            ),
                            subtitle: _elsewhereLine(context, record),
                            onTap: () => _open(record, current: current),
                          ),
                      ],
                    ),
                  ),
                  last,
                ],
              );
        final key = widget.historyKey;
        if (key == null) return lines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            lines,
            _history(context, state, key, current: current),
          ],
        );
      },
    );
  }

  /// « External Garage Key · Robot #3 · LibreBazaar », « Internal Garage Key #1 · Robot #0 · TheBigLake »: the grey line of a trade in progress of another key (#81).
  String _elsewhereLine(BuildContext context, TradeRecord record) {
    final l10n = P2pLocalizations.of(context);
    final fingerprint = record.robot.keyFingerprint;
    final keyName = switch (widget.keyNumbers[fingerprint]) {
      final number? => l10n.p2pGarageKeyNumber(number),
      null when widget.externalKey == fingerprint => l10n.p2pGarageExternalKey,
      null => null,
    };
    final robot = '${l10n.p2pGarageRobotLabel} #${record.robot.accountIndex}';
    final coordinator = Federation.robosats.byAlias(record.coordinatorAlias);
    final name = CoordinatorText.of(
      coordinator?.longAlias ?? record.coordinatorAlias,
      maxCodePoints: CoordinatorText.name,
    );
    return [?keyName, robot, name].join(' · ');
  }

  /// « See history » and, open, its lines (#253): no link while the lines are read or cannot be (they say so), nor when the history holds nothing they do not show.
  Widget _history(
    BuildContext context,
    LastOrdersState last,
    NetworkGarageKey key, {
    required bool current,
  }) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final cubit = context.read<OrderHistoryCubit>();
    return BlocBuilder<OrderHistoryCubit, OrderHistoryState>(
      builder: (context, history) {
        final shownAbove = switch (last) {
          LastOrdersListed(:final orders) => {
            for (final record in orders) record.robot,
          },
          LastOrdersLoading() || LastOrdersUnreadable() => null,
        };
        final more =
            shownAbove != null &&
            switch (history.read) {
              OrderHistoryListed(:final orders) => orders.any(
                (order) => !shownAbove.contains(order.record.robot),
              ),
              // Never shown as « nothing more »: opened, it says the records cannot be read.
              OrderHistoryUnreadable() => true,
              OrderHistoryLoading() => false,
            };
        if (!history.open && !more) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DetailToggle(
              open: history.open,
              showLabel: l10n.p2pHistoryShow,
              hideLabel: l10n.p2pHistoryHide,
              onPressed: history.open ? cubit.fold : cubit.open,
            ),
            if (history.open)
              switch (history.read) {
                OrderHistoryUnreadable() => Text(
                  l10n.p2pRobotRecordsUnreadable,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: colors.error),
                ),
                OrderHistoryLoading() || OrderHistoryListed() => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, order) in history.lines.indexed) ...[
                      if (index > 0)
                        Divider(height: 1, color: colors.outlineVariant),
                      _HistoryRow(
                        key: ValueKey(('history', order.record.robot)),
                        order: order,
                        nickname: _nicknameOf(key, order.record.robot),
                        keyNumber: widget
                            .keyNumbers[order.record.robot.keyFingerprint],
                        external:
                            widget.externalKey ==
                            order.record.robot.keyFingerprint,
                        onTap: () => _open(order.record, current: current),
                      ),
                    ],
                    if (history.hasMore)
                      Center(
                        child: TextButton(
                          onPressed: cubit.showMore,
                          child: WordFitText(
                            l10n.p2pHistorySeeMore,
                            textAlign: TextAlign.center,
                            style: text.labelLarge?.copyWith(
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              },
          ],
        );
      },
    );
  }
}

/// One order of the history (#253), as the validated mock-up draws it: « #N · coordinator » over its side, made or taken here and the day of its end, how it ended on the right; then its robot, on a line of its own; a tap calls [onTap].
class _HistoryRow extends StatelessWidget {
  final FinishedOrder order;

  /// The robot's nickname, `null` when the key shown does not give it (a robot of another key): the line then says « Robot #N » alone.
  final String? nickname;

  /// The number of the robot's key (#81), `null` for a key that is not one of the words.
  final int? keyNumber;

  /// Whether the robot's key is the external key of the network (#81).
  final bool external;
  final VoidCallback onTap;

  const _HistoryRow({
    super.key,
    required this.order,
    required this.nickname,
    required this.keyNumber,
    required this.external,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final record = order.record;
    final coordinator = Federation.robosats.byAlias(record.coordinatorAlias);
    final name = CoordinatorText.of(
      coordinator?.longAlias ?? record.coordinatorAlias,
      maxCodePoints: CoordinatorText.name,
    );
    final side = switch (record.role) {
      TradeRole.seller => l10n.p2pHistorySell,
      TradeRole.buyer => l10n.p2pHistoryBuy,
    };
    final origin = switch (record.origin) {
      TradeOrigin.madeHere => l10n.p2pHistoryMadeHere,
      TradeOrigin.takenHere ||
      TradeOrigin.recovered => l10n.p2pHistoryTakenHere,
    };
    // « Robot #N » as the account navigator writes it.
    final number = '${l10n.p2pGarageRobotLabel} #${record.robot.accountIndex}';
    final named = switch (nickname) {
      final nickname? => l10n.p2pHistoryRobotNamed(number, nickname),
      null => number,
    };
    // « Internal Garage Key #2 », « External Garage Key », on a line of its own over the robot's: the history covers every key of the network (#81, decided on 2026-11-26).
    final keyName = switch (keyNumber) {
      final key? => l10n.p2pGarageKeyNumber(key),
      null when external => l10n.p2pGarageExternalKey,
      null => null,
    };
    final (end, endColor) = switch (order.end) {
      OrderEnd.traded => (l10n.p2pHistoryTraded, colors.text),
      OrderEnd.expired => (l10n.p2pHistoryExpired, colors.textMuted),
      OrderEnd.cancelled => (l10n.p2pHistoryCancelled, colors.textMuted),
      OrderEnd.dispute => (l10n.p2pHistoryDispute, colors.warning),
      OrderEnd.unknown => (l10n.p2pHistoryEndUnknown, colors.textMuted),
    };
    final muted = text.labelMedium?.copyWith(color: colors.textMuted);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BullSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, box) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WordFitText(
                          l10n.p2pHistoryTitle('${record.orderId}', name),
                          style: text.bodyLarge?.copyWith(
                            color: colors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        WordFitText(
                          l10n.p2pHistoryFacts(
                            side,
                            origin,
                            P2pFormats(l10n).day(order.endedAt),
                          ),
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  const Gap(BullSpacing.sm),
                  // At most 45 % of the line, so that the order's own words keep the rest at every text size, and « Cancelled » keeps one line at 320 points.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * 0.45),
                    child: WordFitText(
                      end,
                      textAlign: TextAlign.end,
                      style: text.bodyMedium?.copyWith(
                        color: endColor,
                        fontWeight: order.end == OrderEnd.dispute
                            ? FontWeight.w600
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // The key, then the robot, each on a line of its own, the whole width: a nickname is one long word.
            if (keyName != null) WordFitText(keyName, style: muted),
            WordFitText(named, style: muted),
          ],
        ),
      ),
    );
  }
}
