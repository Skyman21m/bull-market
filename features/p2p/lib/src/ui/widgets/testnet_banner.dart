import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';

/// The thin italic line of the official client above every P2P page when the book is on testnet.
class TestnetBanner extends StatelessWidget {
  const TestnetBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Container(
      width: double.infinity,
      color: colors.surface,
      padding: const EdgeInsets.symmetric(vertical: BullSpacing.xxs),
      child: Text(
        P2pLocalizations.of(context).p2pTestnetBanner,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.textMuted,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
