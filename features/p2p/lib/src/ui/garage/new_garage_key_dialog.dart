import 'package:bull_ui/bull_ui.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../widgets/trade_dialog_body.dart';

/// « New key? » (#81, design note `docs/design/garage-key-from-the-words.md` § 6): what « New key » does, then « Create key n° N » or « Cancel »; a plain confirmation, without the PIN, since nothing is erased.
///
/// The official client's « Generate new » replaces its key; here the earlier keys stay, behind the arrows of the Garage Key card, and finish their trades.
class NewGarageKeyDialog extends StatelessWidget {
  /// The index of the key « Create » activates.
  final int index;

  const NewGarageKeyDialog({super.key, required this.index});

  /// Whether the user confirmed the key of [index].
  static Future<bool> show(BuildContext context, {required int index}) async =>
      await BullDialog.show<bool>(
        context: context,
        builder: (_) => NewGarageKeyDialog(index: index),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return TradeDialogBody(
      title: l10n.p2pGarageNewKeyTitle,
      text: l10n.p2pGarageNewKeyText(index),
      note: l10n.p2pGarageNewKeyKept,
      backLabel: l10n.p2pCommonCancel,
      onBack: () => Navigator.of(context).pop(false),
      goLabel: l10n.p2pGarageNewKeyConfirm(index),
      onGo: () => Navigator.of(context).pop(true),
    );
  }
}
