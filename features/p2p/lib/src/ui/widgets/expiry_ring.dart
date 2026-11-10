import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../presentation/p2p_formats.dart';

/// The expiry ring of an order in the book: the share of a day left before the order leaves the book, with the time left in the middle.
///
/// As in the official client, it is red under 15 %, orange under 30 % and green above.
class ExpiryRing extends StatelessWidget {
  final DateTime expiresAt;
  final DateTime now;
  final double size;

  const ExpiryRing({
    super.key,
    required this.expiresAt,
    required this.now,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final left = expiresAt.difference(now);
    final share = left.isNegative
        ? 0.0
        : (left.inMilliseconds / Duration.millisecondsPerDay).clamp(0.0, 1.0);
    final color = share < 0.15
        ? colors.error
        : share < 0.30
        ? colors.warning
        : colors.success;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: size,
            child: CircularProgressIndicator(
              value: share,
              strokeWidth: 3,
              color: color,
              backgroundColor: colors.surfaceContainer,
            ),
          ),
          Text(
            P2pFormats.of(context).ringTime(left),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
