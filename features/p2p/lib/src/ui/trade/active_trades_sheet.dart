import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/active_trade.dart';
import '../../domain/trade_record.dart';
import '../../presentation/coordinator_text.dart';
import '../widgets/coordinator_avatar.dart';

/// The active trades of the network, when there are several: one line « Active order #{{orderID}} » each (the official client's words in its Garage, `GaragePage/GarageKeyProfile.tsx:209`), with its coordinator; a tap opens the trade.
///
/// The official client follows one robot at a time and its « Order » button opens that robot's order; here each trade has a robot of its own, so the robots' orders are listed (a deviation: the reference's « current robot » does not exist here). With no list ([trades] `null`), the records could not be read, and the sheet says so.
class ActiveTradesSheet extends StatelessWidget {
  final List<ActiveTrade>? trades;
  final ValueChanged<TradeRecord> onOpen;

  const ActiveTradesSheet({
    super.key,
    required this.trades,
    required this.onOpen,
  });

  static Future<void> show(
    BuildContext context, {
    required List<ActiveTrade>? trades,
    required ValueChanged<TradeRecord> onOpen,
  }) => BullBottomSheet.show<void>(
    context: context,
    child: ActiveTradesSheet(trades: trades, onOpen: onOpen),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final trades = this.trades;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BullSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            header: true,
            child: Text(
              l10n.p2pNavOrder,
              style: text.headlineLarge?.copyWith(color: colors.text),
            ),
          ),
          const Gap(BullSpacing.sm),
          if (trades == null)
            Text(
              l10n.p2pRobotRecordsUnreadable,
              style: text.bodyMedium?.copyWith(color: colors.error),
            )
          else
            for (final trade in trades) _Line(trade: trade, onOpen: onOpen),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final ActiveTrade trade;
  final ValueChanged<TradeRecord> onOpen;

  const _Line({required this.trade, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final record = trade.record;
    final coordinator = Federation.robosats.byAlias(record.coordinatorAlias);
    final name = CoordinatorText.of(
      coordinator?.longAlias ?? record.coordinatorAlias,
      maxCodePoints: CoordinatorText.name,
    );
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onOpen(record);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BullSpacing.sm),
        child: Row(
          children: [
            if (coordinator != null) ...[
              ExcludeSemantics(
                child: CoordinatorAvatar(coordinator: coordinator, size: 32),
              ),
              const Gap(BullSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.p2pActiveOrder('${record.orderId}'),
                    style: text.bodyLarge?.copyWith(color: colors.text),
                  ),
                  Text(
                    name,
                    style: text.labelMedium?.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
            ExcludeSemantics(
              child: Icon(Icons.chevron_right, color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
