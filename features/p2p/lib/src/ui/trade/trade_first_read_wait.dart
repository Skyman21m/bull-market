import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';

/// The trade screen before its first read (`TradeWaiting`): the spinner, and what it waits for, the order read by the trade's robot from [coordinator] over Tor, then, after [stillWaitingAfter], that it still waits (review of #133).
///
/// The reference has no such line: its trade page opens on an order it has already read.
class TradeFirstReadWait extends StatefulWidget {
  /// After how long the wait says it still waits, as the take's wait does.
  static const stillWaitingAfter = Duration(seconds: 30);

  /// The coordinator's long alias, made safe to show already.
  final String coordinator;

  const TradeFirstReadWait({super.key, required this.coordinator});

  @override
  State<TradeFirstReadWait> createState() => _TradeFirstReadWaitState();
}

class _TradeFirstReadWaitState extends State<TradeFirstReadWait> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(TradeFirstReadWait.stillWaitingAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: colors.textMuted);
    return Padding(
      padding: const EdgeInsets.all(BullSpacing.xl),
      child: Column(
        children: [
          CircularProgressIndicator(color: colors.primary),
          const Gap(BullSpacing.md),
          // Read out when it shows, as the lines of the take's wait are.
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              l10n.p2pTradeFirstRead(widget.coordinator),
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
          if (_slow) ...[
            const Gap(BullSpacing.xs),
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                l10n.p2pRobotStillWaiting(widget.coordinator),
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
