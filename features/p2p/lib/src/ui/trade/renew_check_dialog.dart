import 'package:bull_ui/bull_ui.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../widgets/trade_dialog_body.dart';

/// « Renew this order? » (#217, security review of #220, not in the reference): « Renew Order » or « Renew » of an order made here when something should be known before making one more order: its end not confirmed by its coordinator, or shown otherwise, or still running there; an order with the same terms made here since, or one still being created; or records that could not tell. [reasons] say which, in the app's words, then that renewing makes one more order with a new bond. Information, never a lock: « Renew anyway » opens the renewal's page as the first tap would have, where the user still sees and confirms everything before « Create order »; « Go back » (the emphasized one), a system back or a tap outside open nothing.
///
/// The reference renews with the same robot, so its coordinator refuses a second order while the first one is active (`api/logics.py:75-100`, error 1000); each renewal has a fresh robot here, so nothing refuses it, and this one tap more says it instead.
class RenewCheckDialog extends StatelessWidget {
  final List<String> reasons;

  const RenewCheckDialog({super.key, required this.reasons});

  /// Whether the user pressed « Renew anyway ».
  static Future<bool> show(
    BuildContext context, {
    required List<String> reasons,
  }) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => RenewCheckDialog(reasons: reasons),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return TradeDialogBody(
      title: l10n.p2pRenewSameTermsTitle,
      text: [...reasons, l10n.p2pRenewOneMore].join(' '),
      backLabel: l10n.p2pCommonGoBack,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: l10n.p2pRenewSameTermsGo,
      backFirst: true,
      // A second tap on « Renew Order » can land on it as the dialog opens, past the reasons unread (#298).
      guardsGo: true,
      onGo: () => Navigator.of(context).pop(true),
    );
  }
}
