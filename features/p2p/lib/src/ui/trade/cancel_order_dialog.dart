import 'package:bull_ui/bull_ui.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../widgets/trade_dialog_body.dart';

/// « Cancel the order? » of the pre-take, where no bond is locked yet (`components/Dialogs/CancelOrder.tsx`, opened by `TradeBox/CancelButton.tsx` for a taker at 3, commit ff1998c): « Confirm cancellation » cancels, « Back » or a tap outside sends nothing.
class CancelOrderDialog extends StatelessWidget {
  /// A line of the app under the reference's text: a payment of the bond on its way from this wallet (#100).
  final String? note;

  const CancelOrderDialog({super.key, this.note});

  /// Whether the user pressed « Confirm cancellation ».
  static Future<bool> show(BuildContext context, {String? note}) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => CancelOrderDialog(note: note),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return TradeDialogBody(
      title: l10n.p2pTradeCancelTitle,
      text: l10n.p2pTradeCancelPreTakeText,
      backLabel: l10n.p2pTradeCancelBack,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: l10n.p2pTradeConfirmCancellation,
      // The tap that cancels the order, which cannot be undone: a second tap on « Cancel » can land on it as the dialog opens (#298).
      guardsGo: true,
      onGo: () => Navigator.of(context).pop(true),
      note: note,
    );
  }
}
