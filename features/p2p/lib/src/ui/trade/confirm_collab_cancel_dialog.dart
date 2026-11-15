import 'package:bull_ui/bull_ui.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../widgets/trade_dialog_body.dart';

/// « Collaborative cancel the order? » (`TradeBox/Dialogs/ConfirmCollabCancel.tsx`, commit ff1998c): « The trade escrow has been posted. The order can be cancelled only if both, maker and taker, agree to cancel. », with « Your peer has asked for cancellation » when the peer asked; « Go back » (the reference's focus) and « Ask for Cancel », or « Accept Cancelation » when the peer asked.
///
/// The peer's ask is accepted only by this tap: nothing is sent by itself.
class ConfirmCollabCancelDialog extends StatelessWidget {
  /// Whether the peer asked first, as the status shown says (`pending_cancel`).
  final bool peerAsked;

  const ConfirmCollabCancelDialog({super.key, required this.peerAsked});

  /// Whether the user pressed « Ask for Cancel » or « Accept Cancelation ».
  static Future<bool> show(
    BuildContext context, {
    required bool peerAsked,
  }) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => ConfirmCollabCancelDialog(peerAsked: peerAsked),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return TradeDialogBody(
      title: l10n.p2pEndCollabTitle,
      text: peerAsked
          ? '${l10n.p2pEndCollabText} ${l10n.p2pEndCollabPeerAsked}'
          : l10n.p2pEndCollabText,
      backLabel: l10n.p2pCommonGoBack,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: peerAsked ? l10n.p2pEndCollabAccept : l10n.p2pEndCollabAsk,
      backFirst: true,
      onGo: () => Navigator.of(context).pop(true),
    );
  }
}
