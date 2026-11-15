import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../../generated/l10n/p2p_localizations.dart';
import '../widgets/trade_dialog_body.dart';

/// « Revert the confirmation of fiat sent? » (`TradeBox/Dialogs/ConfirmUndoFiatSent.tsx`, commit ff1998c): the reference's « READ. … » in full, « Go back » (the reference's focus), and the button that sends, « Wait ({{time}}) » while its counter runs, then « Confirm ».
///
/// The counter is the reference's: it starts at 60 seconds, runs only while the dialog is open, and is not set back when it opens again, since the reference's dialog stays mounted with the trade's page (`useState(60)`); after « Confirm » it is set to 300, so that another « Payment failed? » on the same page waits five minutes. It lives in [left], which the chat step's panel keeps for its page.
/// Information, not a gate (design note § 3.7): the reference's own wait, kept as it is; « Go back », a system back or a tap outside send nothing.
class ConfirmUndoFiatSentDialog extends StatefulWidget {
  /// The reference's counter at the page's opening (`useState<number>(60)`), and after « Confirm » (`setTime(300)`).
  static const firstWait = 60;
  static const afterConfirm = 300;

  /// The seconds left before « Confirm », kept by the page across openings.
  final ValueNotifier<int> left;

  const ConfirmUndoFiatSentDialog({super.key, required this.left});

  /// Whether the user pressed « Confirm »; [left] then holds [afterConfirm].
  static Future<bool> show(
    BuildContext context, {
    required ValueNotifier<int> left,
  }) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => ConfirmUndoFiatSentDialog(left: left),
      ) ??
      false;

  @override
  State<ConfirmUndoFiatSentDialog> createState() =>
      _ConfirmUndoFiatSentDialogState();
}

class _ConfirmUndoFiatSentDialogState extends State<ConfirmUndoFiatSentDialog> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // The counter runs only while the dialog is open, as the reference's (`time > 0 && open`).
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (widget.left.value > 0) {
        setState(() => widget.left.value--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final left = widget.left.value;
    final waiting = left > 0;
    return TradeDialogBody(
      title: l10n.p2pEndUndoTitle,
      text: l10n.p2pEndUndoText,
      backLabel: l10n.p2pCommonGoBack,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: waiting ? l10n.p2pEndWaitCountdown('$left') : l10n.p2pEndConfirm,
      // « Wait 42 seconds » rather than « Wait (42) », and « Confirm » announced as the counter ends.
      goSemanticLabel: waiting ? l10n.p2pEndWaitSeconds('$left') : null,
      goLive: true,
      backFirst: true,
      onGo: waiting
          ? null
          : () {
              widget.left.value = ConfirmUndoFiatSentDialog.afterConfirm;
              Navigator.of(context).pop(true);
            },
    );
  }
}
