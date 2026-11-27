import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart';

import '../../domain/trade_record.dart';
import '../../presentation/coordinator_text.dart';
import '../widgets/coordinator_avatar.dart';
import '../widgets/word_fit_text.dart';

/// One trade of this device as a row: [label] (« Active order #N », « Last order #N », the official client's words in its Garage, `GaragePage/GarageKeyProfile.tsx:209`, `:226`), the coordinator's name, or [subtitle], and the coordinator's image, a chevron; a tap calls [onTap].
///
/// The rows of « Active trades » (#88), the « Last order #N » lines of the Garage (#216), and its « Trade in progress #N » lines of another Garage Key than the one shown (#81).
/// Its texts break between words only ([WordFitText], #273), so that a large text never cuts an order's number or a coordinator's name.
class TradeRecordRow extends StatelessWidget {
  final TradeRecord record;
  final String label;
  final VoidCallback onTap;

  /// The grey line under [label] in place of the coordinator's name, `null` for the name: « External Garage Key · Robot #3 · LibreBazaar » (#81).
  final String? subtitle;

  const TradeRecordRow({
    super.key,
    required this.record,
    required this.label,
    required this.onTap,
    this.subtitle,
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
                // Words never broken inside, at any text size: « #N » and a coordinator's name shrink just enough to fit the row (#273); at the normal size, plain texts as before.
                children: [
                  WordFitText(
                    label,
                    style: text.bodyLarge?.copyWith(color: colors.text),
                  ),
                  WordFitText(
                    subtitle ?? name,
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
