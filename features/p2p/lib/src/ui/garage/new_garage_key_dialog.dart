import 'package:bull_ui/bull_ui.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import 'garage_key_dialogs.dart';

/// « New Garage Key » (#81, design note `docs/design/garage-key-from-the-words.md` § 6, plate 2 of the mock-up decided on 2026-11-26): what « New internal Garage Key » does, then « Create internal Garage Key #N » or « Cancel »; a plain confirmation, without the PIN, since nothing is erased.
///
/// The official client's « Generate new » replaces its key; here the earlier Garage Keys stay in the Garage, and their trades finish with them.
class NewGarageKeyDialog extends StatelessWidget {
  /// The index of the internal Garage Key « Create » activates.
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
    return GarageDialogBody(
      title: l10n.p2pGarageNewKeyTitle,
      text: l10n.p2pGarageNewKeyText(index),
      goLabel: l10n.p2pGarageNewKeyConfirm(index),
      onGo: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
    );
  }
}
