import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade_record.dart';
import '../../presentation/last_orders_cubit.dart';
import '../trade/trade_record_row.dart';

/// « Last order #N » on the Garage profile, under the robot navigator (#216), as the reference shows its robot's last order there (`basic/GaragePage/GarageKeyProfile.tsx:214-230`, commit ff1998c), whose tap opens the order again so that it can still be renewed.
///
/// The reference's line is the robot shown's; here each trade has a robot of its own, so the lines come from the device's records ([LastOrdersCubit]): the last finished order made here and the last finished trade taken here, the newest end first, each with its coordinator, a tap opening its trade screen ([onOpen]). Nothing while the records are read or when there is none (the reference's « No existing orders found » stays the robot panel's, which reads the robot shown); when they cannot be read, the app's line that says so.
/// One tap opens one screen (security review of #220, R4): another tap does nothing until the Garage is shown again, or the screen opened is left; so one tap also shows its order's robot once (#227, `GarageProfile`).
class LastOrderLines extends StatefulWidget {
  final Future<void> Function(TradeRecord record) onOpen;

  const LastOrderLines({super.key, required this.onOpen});

  @override
  State<LastOrderLines> createState() => _LastOrderLinesState();
}

class _LastOrderLinesState extends State<LastOrderLines> {
  /// Whether a screen was opened by a tap and the Garage has not been shown again since.
  bool _opening = false;

  /// Whether the Garage was covered by another page since the tap.
  bool _covered = false;

  void _open(TradeRecord record, {required bool current}) {
    if (_opening || !current) return;
    _opening = true;
    unawaited(
      widget.onOpen(record).whenComplete(() {
        if (mounted) setState(() => _opening = false);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    // The Garage shown again after the page a tap opened: taps open again, even when that page was replaced rather than left.
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (!current) {
      _covered = true;
    } else if (_covered) {
      _covered = false;
      _opening = false;
    }
    return BlocBuilder<LastOrdersCubit, LastOrdersState>(
      builder: (context, state) => switch (state) {
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
      },
    );
  }
}
