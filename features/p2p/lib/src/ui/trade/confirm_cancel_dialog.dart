import 'package:bull_ui/bull_ui.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/trade_cancel.dart';
import '../../domain/trade/trade_watch.dart';
import '../../domain/trade_record.dart';
import '../widgets/trade_dialog_body.dart';

/// « Cancel the order? » once the taker bond is locked, at 6 and 7, where a cancel alone loses the bond (`TradeBox/Dialogs/ConfirmCancel.tsx`, commit ff1998c): « If the order is cancelled now you will lose your bond. », « Go back » / « Confirm Cancel ».
///
/// The only place of the app that builds a [BondLossAcknowledged], which `CancelTradeUsecase` needs to send such a cancel: on « Confirm Cancel » alone, bound to the trade [record] and the status [seen] this dialog was opened for (an acknowledgement of another status is refused, `CancelAcknowledgementMismatch`); « Go back », a system back or a tap outside give `null`, and nothing is sent (`trade_screen_architecture_test.dart` pins that no other file names its constructor).
class ConfirmCancelDialog extends StatelessWidget {
  final TradeRecord record;
  final TradeSeen seen;

  /// A line of the app under the reference's text: a payment of the bond on its way from this wallet (#100).
  final String? note;

  const ConfirmCancelDialog({
    super.key,
    required this.record,
    required this.seen,
    this.note,
  });

  /// The acknowledgement of the bond's loss, when the user pressed « Confirm Cancel » on the dialog opened for [record] at [seen].
  static Future<BondLossAcknowledged?> show(
    BuildContext context, {
    required TradeRecord record,
    required TradeSeen seen,
    String? note,
  }) => BullDialog.show<BondLossAcknowledged>(
    context: context,
    builder: (_) => ConfirmCancelDialog(record: record, seen: seen, note: note),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return TradeDialogBody(
      title: l10n.p2pTradeCancelTitle,
      text: l10n.p2pTradeCancelBondText,
      backLabel: l10n.p2pCommonGoBack,
      onBack: () => Navigator.of(context).pop(),
      goLabel: l10n.p2pTradeConfirmCancel,
      backFirst: true,
      note: note,
      // The tap that loses the bond: a second tap on « Cancel » can land on it as the dialog opens, with a large text (#298).
      guardsGo: true,
      onGo: () => Navigator.of(
        context,
      ).pop(BondLossAcknowledged.fromConfirmationDialog(record, seen)),
    );
  }
}
