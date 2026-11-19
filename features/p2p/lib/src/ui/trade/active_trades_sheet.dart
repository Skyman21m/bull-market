import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/active_trade.dart';
import '../../domain/trade_record.dart';
import '../../presentation/pending_makes_cubit.dart';
import '../widgets/trade_button.dart';
import 'pending_make_lines.dart';
import 'trade_record_row.dart';

/// The active trades of the network: one line « Active order #{{orderID}} » each (the official client's words in its Garage, `GaragePage/GarageKeyProfile.tsx:209`), with its coordinator; a tap opens the trade.
///
/// The official client follows one robot at a time and its « Order » button opens that robot's order; here each trade has a robot of its own, so the robots' orders are listed (a deviation: the reference's « current robot » does not exist here). With no list ([active] `null`), the records could not be read, and the sheet says so.
/// Since #182 (design note § 7, proposal 9): « Create order » at its top ([onCreate]), where the official client switches robot in its Garage to make another order, and the lines of the network's pending makes ([pending], « Creating your order… »), each resolved once when the sheet opens and when the app comes back while it is shown, never in a loop; a make a resolution confirms closes the sheet and opens its trade.
class ActiveTradesSheet extends StatefulWidget {
  final List<ActiveTrade>? active;
  final ValueChanged<TradeRecord> onOpen;

  /// Opens the create form; `null` where the feature cannot make an order.
  final VoidCallback? onCreate;

  /// The network's pending makes; `null` where the feature cannot make an order.
  final PendingMakesCubit? pending;

  const ActiveTradesSheet({
    super.key,
    required this.active,
    required this.onOpen,
    this.onCreate,
    this.pending,
  });

  static Future<void> show(
    BuildContext context, {
    required List<ActiveTrade>? active,
    required ValueChanged<TradeRecord> onOpen,
    VoidCallback? onCreate,
    PendingMakesCubit? pending,
  }) => BullBottomSheet.show<void>(
    context: context,
    child: ActiveTradesSheet(
      active: active,
      onOpen: onOpen,
      onCreate: onCreate,
      pending: pending,
    ),
  );

  @override
  State<ActiveTradesSheet> createState() => _ActiveTradesSheetState();
}

class _ActiveTradesSheetState extends State<ActiveTradesSheet>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.pending?.resolveAll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.pending?.resolveAll());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final active = widget.active;
    final onCreate = widget.onCreate;
    final pending = widget.pending;
    final content = SingleChildScrollView(
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
          if (onCreate != null) ...[
            TradeButton(
              label: l10n.p2pMakeCreateOrder,
              outlined: true,
              onPressed: () {
                Navigator.of(context).pop();
                onCreate();
              },
            ),
            const Gap(BullSpacing.sm),
          ],
          if (pending != null) const PendingMakeLines(),
          if (active == null)
            Text(
              l10n.p2pRobotRecordsUnreadable,
              style: text.bodyMedium?.copyWith(color: colors.error),
            )
          else
            for (final trade in active)
              TradeRecordRow(
                record: trade.record,
                label: l10n.p2pActiveOrder('${trade.record.orderId}'),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onOpen(trade.record);
                },
              ),
        ],
      ),
    );
    if (pending == null) return content;
    return BlocProvider.value(
      value: pending,
      child: BlocListener<PendingMakesCubit, PendingMakesState>(
        listenWhen: (previous, current) =>
            current.started != null && previous.started != current.started,
        listener: (context, state) {
          if (state.started case final record?) {
            Navigator.of(context).pop();
            widget.onOpen(record);
          }
        },
        child: content,
      ),
    );
  }
}
