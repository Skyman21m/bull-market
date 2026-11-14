import 'package:bull_ui/bull_ui.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import 'trade_dialog_body.dart';

/// « Store your garage key », the official client's reminder before a take (`components/Dialogs/StoreToken.tsx`, opened by `Dialogs/Confirmation.tsx` from `OrderDetails/TakeButton.tsx:378-390`, at commit ff1998c): « Done » goes on with the take, « Go back » or a tap outside takes nothing.
///
/// The reference shows the Garage Key itself in a field « Back it up! » with a copy button; here the key is not shown: it is shown only in the Garage, behind the PIN (`AGENTS.md`, « The Garage »), a deviation for security.
class StoreTokenDialog extends StatelessWidget {
  const StoreTokenDialog({super.key});

  /// Whether the user pressed « Done ».
  static Future<bool> show(BuildContext context) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => const StoreTokenDialog(),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return TradeDialogBody(
      title: l10n.p2pStoreKeyTitle,
      text: l10n.p2pStoreKeyText,
      backLabel: l10n.p2pCommonGoBack,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: l10n.p2pCommonDone,
      onGo: () => Navigator.of(context).pop(true),
    );
  }
}
