import 'package:bull_ui/bull_ui.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../widgets/trade_dialog_body.dart';

/// « Renew this order? » (#217, not in the reference): « Renew Order » or « Renew » of an order made here when an order with the same terms was made here after it ([orderId], where this device saw it stand: [stands], already worded). It says only what is established (functional review of #220, R1): that order may be a renewal or one made again by hand, still running or ended. Information, never a lock: « Renew anyway » opens the renewal's page as the first tap would have, where the user still sees and confirms everything before « Create order »; « Go back » (the emphasized one), a system back or a tap outside open nothing.
///
/// The reference renews with the same robot, so its coordinator refuses a second order while the first one is active (`api/logics.py:75-100`, error 1000); each renewal has a fresh robot here, so nothing refuses it, and this one tap more says it instead.
class RenewSameTermsDialog extends StatelessWidget {
  final int orderId;
  final String stands;

  const RenewSameTermsDialog({
    super.key,
    required this.orderId,
    required this.stands,
  });

  /// Whether the user pressed « Renew anyway ».
  static Future<bool> show(
    BuildContext context, {
    required int orderId,
    required String stands,
  }) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => RenewSameTermsDialog(orderId: orderId, stands: stands),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return TradeDialogBody(
      title: l10n.p2pRenewSameTermsTitle,
      text: l10n.p2pRenewSameTermsText('$orderId', stands),
      backLabel: l10n.p2pCommonGoBack,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: l10n.p2pRenewSameTermsGo,
      backFirst: true,
      onGo: () => Navigator.of(context).pop(true),
    );
  }
}
