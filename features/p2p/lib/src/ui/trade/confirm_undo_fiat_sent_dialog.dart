import 'dart:async';

import 'package:bull_ui/bull_ui.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../widgets/trade_dialog_body.dart';

/// « Revert the confirmation of fiat sent? » (`TradeBox/Dialogs/ConfirmUndoFiatSent.tsx`, commit ff1998c): the reference's « READ. … » in full, « Go back » (the reference's focus), and the button that sends, « Wait ({{time}}) » for 60 seconds from the dialog's opening, then « Confirm ».
///
/// Information, not a gate (design note § 3.7): the reference's own wait, kept as it is; « Go back », a system back or a tap outside send nothing.
class ConfirmUndoFiatSentDialog extends StatefulWidget {
  /// The reference's wait before « Confirm » (`useState<number>(60)`).
  static const wait = Duration(seconds: 60);

  const ConfirmUndoFiatSentDialog({super.key});

  /// Whether the user pressed « Confirm ».
  static Future<bool> show(BuildContext context) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => const ConfirmUndoFiatSentDialog(),
      ) ??
      false;

  @override
  State<ConfirmUndoFiatSentDialog> createState() =>
      _ConfirmUndoFiatSentDialogState();
}

class _ConfirmUndoFiatSentDialogState extends State<ConfirmUndoFiatSentDialog> {
  int _left = ConfirmUndoFiatSentDialog.wait.inSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) timer.cancel();
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
    final waiting = _left > 0;
    return TradeDialogBody(
      title: l10n.p2pEndUndoTitle,
      text: l10n.p2pEndUndoText,
      backLabel: l10n.p2pCommonGoBack,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: waiting
          ? l10n.p2pEndWaitCountdown('$_left')
          : l10n.p2pEndConfirm,
      backFirst: true,
      onGo: waiting ? null : () => Navigator.of(context).pop(true),
    );
  }
}
