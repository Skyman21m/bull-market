import 'package:bull_ui/bull_ui.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../widgets/trade_dialog_body.dart';
import 'chat_step_panel.dart' show withoutLeadingEmoji;

/// « ✅ Confirm you sent {{amount}} {{currencyCode}}? » (`TradeBox/Dialogs/ConfirmFiatSent.tsx`, commit ff1998c): « Confirming will allow your peer to finalize the trade. », « ⚠️ This action cannot be undone! » in the warning colour, « If you have not yet sent it and you still proceed to falsely confirm, you risk losing your bond. », then « Go back » (the reference's focus) and « Confirm ».
///
/// Information before an action that the buyer alone cannot take back once the seller acts on it, not a gate: « Confirm » is the tap that sends (design note § 3.7); « Go back », a system back or a tap outside send nothing.
class ConfirmFiatSentDialog extends StatelessWidget {
  /// The trade's amount and its currency, as the button that opened the dialog shows them.
  final String amount;
  final String currencyCode;

  const ConfirmFiatSentDialog({
    super.key,
    required this.amount,
    required this.currencyCode,
  });

  /// Whether the user pressed « Confirm ».
  static Future<bool> show(
    BuildContext context, {
    required String amount,
    required String currencyCode,
  }) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) =>
            ConfirmFiatSentDialog(amount: amount, currencyCode: currencyCode),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return TradeDialogBody(
      title: l10n.p2pEndConfirmSentTitle(amount, currencyCode),
      semanticTitle: withoutLeadingEmoji(
        l10n.p2pEndConfirmSentTitle(amount, currencyCode),
      ),
      text: l10n.p2pEndConfirmSentText,
      warning: l10n.p2pEndCannotBeUndone,
      semanticWarning: withoutLeadingEmoji(l10n.p2pEndCannotBeUndone),
      afterWarning: l10n.p2pEndFalseConfirmRisk,
      backLabel: l10n.p2pCommonGoBack,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: l10n.p2pEndConfirm,
      backFirst: true,
      onGo: () => Navigator.of(context).pop(true),
    );
  }
}
