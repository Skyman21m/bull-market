import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../generated/l10n/p2p_localizations.dart';

/// A link or a contact of a coordinator, shown in full with a button that copies it.
///
/// Where the official client opens a link, a mail app or a Nostr gateway, Troc shows what it would open and lets the user copy it: nothing leaves Tor, and nothing is opened.
/// The value is coordinator text, shown as plain text.
class CoordinatorLinkSheet extends StatelessWidget {
  final String title;
  final String value;

  const CoordinatorLinkSheet({
    super.key,
    required this.title,
    required this.value,
  });

  /// Opens the sheet of [value], under [title].
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String value,
  }) => BullBottomSheet.show<void>(
    context: context,
    child: CoordinatorLinkSheet(title: title, value: value),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(BullSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: text.headlineLarge?.copyWith(color: colors.text)),
          const Gap(BullSpacing.sm),
          SelectableText(
            value,
            style: text.bodyLarge?.copyWith(color: colors.text),
          ),
          const Gap(BullSpacing.lg),
          BullButton.big(
            label: l10n.p2pCommonCopy,
            iconData: Icons.copy,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              BullSnackBar.show(context, message: l10n.p2pCommonCopied);
              Navigator.of(context).pop();
            },
            bgColor: colors.primary,
            textColor: colors.onPrimary,
          ),
        ],
      ),
    );
  }
}
