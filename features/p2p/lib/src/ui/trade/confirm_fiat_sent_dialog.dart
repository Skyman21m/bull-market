import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/widgets.dart';

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

  /// A maker buyer's lines (#182): the owner's payment rule (the comparison with the Bull wallet's price, its red warning, or why it was not made) or, without a comparison, the gap from the creation's rate; information, « Confirm » unchanged; none for a taker. Built from the rule's state and the status the screen shows when the dialog opens and again whenever either changes while open (security review of #208, C1, #209); the alerts the screen shows said first, under the title (security review of #219, C2).
  final LiveDialogLines? lines;

  const ConfirmFiatSentDialog({
    super.key,
    required this.amount,
    required this.currencyCode,
    this.lines,
  });

  /// Whether the user pressed « Confirm ».
  static Future<bool> show(
    BuildContext context, {
    required String amount,
    required String currencyCode,
    LiveDialogLines? lines,
  }) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => ConfirmFiatSentDialog(
          amount: amount,
          currencyCode: currencyCode,
          lines: lines,
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final lines = this.lines;
    if (lines == null) return _body(context, const []);
    return StreamBuilder<Object?>(
      stream: lines.changes,
      builder: (context, _) => _body(
        context,
        lines.of(context),
        alerts: lines.alerts?.call(context) ?? const [],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<TradeDialogLine> lines, {
    List<TradeDialogLine> alerts = const [],
  }) {
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
      lines: lines,
      alerts: alerts,
      backLabel: l10n.p2pCommonGoBack,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: l10n.p2pEndConfirm,
      backFirst: true,
      onGo: () => Navigator.of(context).pop(true),
    );
  }
}
