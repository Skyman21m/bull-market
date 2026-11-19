import 'package:bull_ui/bull_ui.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../widgets/trade_dialog_body.dart';

/// « Renew this order again? » (#217, not in the reference): « Renew Order » or « Renew » of an order made here when an order was already made here since with its kept terms ([orderId], the newest of them). Information, never a lock: « Renew again » opens the renewal's page as the first tap would have, where the user still sees and confirms everything before « Create order »; « Go back » (the emphasized one), a system back or a tap outside open nothing.
///
/// The reference renews with the same robot, so its coordinator refuses a second order while the first one is active (`api/logics.py:75-100`, error 1000); each renewal has a fresh robot here, so nothing refuses it, and this one tap more says it instead.
class RenewAgainDialog extends StatelessWidget {
  /// The newest order made here since with the terms of the one renewed.
  final int orderId;

  const RenewAgainDialog({super.key, required this.orderId});

  /// Whether the user pressed « Renew again ».
  static Future<bool> show(
    BuildContext context, {
    required int orderId,
  }) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => RenewAgainDialog(orderId: orderId),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return TradeDialogBody(
      title: l10n.p2pRenewAgainTitle,
      text: l10n.p2pRenewAgainText('$orderId'),
      backLabel: l10n.p2pCommonGoBack,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: l10n.p2pRenewAgain,
      backFirst: true,
      onGo: () => Navigator.of(context).pop(true),
    );
  }
}
