import 'package:bull_ui/bull_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/trade_status.dart';
import '../../presentation/trade_cubit.dart';
import '../widgets/trade_dialog_body.dart';

/// « Collaborative cancel the order? » (`TradeBox/Dialogs/ConfirmCollabCancel.tsx`, commit ff1998c): « The trade escrow has been posted. The order can be cancelled only if both, maker and taker, agree to cancel. », with « Your peer has asked for cancellation » when the peer asked; « Go back » (the reference's focus) and « Ask for Cancel », or « Accept Cancelation » when the peer asked.
///
/// Whether the peer asked is read live from the trade's cubit while the dialog is open, as the reference passes its `pending_cancel`: a peer's ask that arrives meanwhile turns the button into « Accept Cancelation » before it can be pressed as « Ask for Cancel ». The peer's ask is accepted only by this tap: nothing is sent by itself.
class ConfirmCollabCancelDialog extends StatelessWidget {
  /// The cubit of the trade's screen: a dialog's route does not see the screen's providers.
  final TradeCubit cubit;

  const ConfirmCollabCancelDialog({super.key, required this.cubit});

  /// Whether the user pressed « Ask for Cancel » or « Accept Cancelation ».
  static Future<bool> show(
    BuildContext context, {
    required TradeCubit cubit,
  }) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => ConfirmCollabCancelDialog(cubit: cubit),
      ) ??
      false;

  /// Whether the status shown says the peer asked (`pending_cancel`).
  static bool peerAskedIn(TradeScreenState state) =>
      switch (state.seen?.status) {
        Chatting(:final peerAskedToCancel) => peerAskedToCancel,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return BlocSelector<TradeCubit, TradeScreenState, bool>(
      bloc: cubit,
      selector: peerAskedIn,
      builder: (context, peerAsked) => TradeDialogBody(
        title: l10n.p2pEndCollabTitle,
        text: peerAsked
            ? '${l10n.p2pEndCollabText} ${l10n.p2pEndCollabPeerAsked}'
            : l10n.p2pEndCollabText,
        backLabel: l10n.p2pCommonGoBack,
        onBack: () => Navigator.of(context).pop(false),
        goLabel: peerAsked ? l10n.p2pEndCollabAccept : l10n.p2pEndCollabAsk,
        backFirst: true,
        // The ask, or the acceptance that cancels the trade: a second tap on « Collaborative Cancel » can land on it as the dialog opens (#298).
        guardsGo: true,
        onGo: () => Navigator.of(context).pop(true),
      ),
    );
  }
}
