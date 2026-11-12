import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';

/// What the robot step of the wizard and the profile say right after a draw whose history this device could not record: its robots are treated as those of a key from elsewhere, and a new key avoids that.
///
/// The key is stored all the same: the feature's database refused the record, which only the draw can write.
class GarageKeyHistoryNotRecorded extends StatelessWidget {
  const GarageKeyHistoryNotRecorded({super.key});

  @override
  Widget build(BuildContext context) => BullInfoBar(
    message: P2pLocalizations.of(context).p2pGarageKeyHistoryNotRecorded,
    tone: BullInfoTone.warning,
    icon: Icons.info_outline,
  );
}
