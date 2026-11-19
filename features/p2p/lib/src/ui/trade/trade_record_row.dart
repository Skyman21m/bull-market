import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../domain/trade_record.dart';
import '../../presentation/coordinator_text.dart';
import '../widgets/coordinator_avatar.dart';

/// One trade of this device as a row: [label] (« Active order #N », « Last order #N », the official client's words in its Garage, `GaragePage/GarageKeyProfile.tsx:209`, `:226`), the coordinator's name and image under it, a chevron; a tap calls [onTap].
///
/// The rows of « Active trades » (#88) and the « Last order #N » lines of the Garage (#216).
class TradeRecordRow extends StatelessWidget {
  final TradeRecord record;
  final String label;
  final VoidCallback onTap;

  const TradeRecordRow({
    super.key,
    required this.record,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final coordinator = Federation.robosats.byAlias(record.coordinatorAlias);
    final name = CoordinatorText.of(
      coordinator?.longAlias ?? record.coordinatorAlias,
      maxCodePoints: CoordinatorText.name,
    );
    return InkWell(
      onTap: onTap,
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
                    label,
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
