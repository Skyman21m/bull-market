import 'package:bull_ui/bull_ui.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../widgets/trade_dialog_body.dart';
import 'chat_step_panel.dart' show withoutLeadingEmoji;

/// « ✅ Confirm you received {{amount}} {{currencyCode}}? » (`TradeBox/Dialogs/ConfirmFiatReceived.tsx`, commit ff1998c; #96): « Confirming will finalize the trade. », « ⚠️ This action cannot be undone! » in the warning colour, « The satoshis in the escrow will be released to the buyer: » and its three items (only confirm once the fiat arrived; not confirming a payment received risks the bond; some payment methods can reverse a payment for up to 80 days), then « Go back » (the reference's focus) and « Confirm ».
///
/// The seller's release of the escrow, which cannot be taken back: « Confirm » is the tap that sends, as the reference's (design note § 3.7: no gate of the app's own); « Go back », a system back or a tap outside send nothing.
class ConfirmFiatReceivedDialog extends StatelessWidget {
  /// The trade's amount and its currency, as the button that opened the dialog shows them.
  final String amount;
  final String currencyCode;

  const ConfirmFiatReceivedDialog({
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
        builder: (_) => ConfirmFiatReceivedDialog(
          amount: amount,
          currencyCode: currencyCode,
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final title = l10n.p2pEndConfirmReceivedTitle(amount, currencyCode);
    return TradeDialogBody(
      title: title,
      semanticTitle: withoutLeadingEmoji(title),
      text: l10n.p2pEndConfirmReceivedText,
      warning: l10n.p2pEndCannotBeUndone,
      semanticWarning: withoutLeadingEmoji(l10n.p2pEndCannotBeUndone),
      afterWarning: l10n.p2pEndEscrowReleased,
      bullets: [
        l10n.p2pEndOnlyConfirmAfter(amount, currencyCode),
        l10n.p2pEndNotConfirmingRisk,
        l10n.p2pEndFiatReversal,
      ],
      backLabel: l10n.p2pCommonGoBack,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: l10n.p2pEndConfirm,
      backFirst: true,
      onGo: () => Navigator.of(context).pop(true),
    );
  }
}
