import 'package:bull_ui/bull_ui.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../widgets/trade_dialog_body.dart';

/// « Do you want to open a dispute? » (`TradeBox/Dialogs/ConfirmDispute.tsx`, commit ff1998c): the reference's two texts (the staff examines the statements, the winner gets the escrow and the loser loses the bond; export the chat log), « Disagree » (the reference's focus) and « Agree and open dispute ».
///
/// As deliberate as in the reference, never easier: « Open Dispute » is reached through « Order options » and only from 18 hours before the chat's end, then this dialog; « Disagree », a system back or a tap outside send nothing. « Agree and open dispute » ignores a tap less than 0.7 s (`MovedTapGuard.afterMove`) after the dialog is shown or its layout moved it (`TradeDialogBody.guardsGo`, #301), said nowhere, the next tap going through.
class ConfirmDisputeDialog extends StatelessWidget {
  const ConfirmDisputeDialog({super.key});

  /// Whether the user pressed « Agree and open dispute ».
  static Future<bool> show(BuildContext context) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => const ConfirmDisputeDialog(),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return TradeDialogBody(
      title: l10n.p2pEndDisputeTitle,
      text: l10n.p2pEndDisputeText,
      afterWarning: l10n.p2pEndDisputeExport,
      backLabel: l10n.p2pEndDisagree,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: l10n.p2pEndAgreeDispute,
      backFirst: true,
      // The tap that settles the escrow and both bonds at the coordinator at once: no second tap on « Open Dispute » was seen landing on it (#301), yet a tap within a moment of the dialog's showing, or of a move of its layout, is ignored, at no cost, as on the four dialogs of #298.
      guardsGo: true,
      onGo: () => Navigator.of(context).pop(true),
    );
  }
}
