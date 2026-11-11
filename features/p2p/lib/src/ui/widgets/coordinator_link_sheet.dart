import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/l10n/p2p_localizations.dart';

/// A link or a contact of a coordinator, shown in full under a title of the app, in the kit's copy field.
///
/// Where the official client opens a link, a mail app or a Nostr gateway, Troc shows what it would open and lets the user copy it: nothing leaves Tor, and nothing is opened.
/// The value is coordinator text, already cleaned by `CoordinatorText.value`, shown as plain text.
class CoordinatorLinkSheet extends StatelessWidget {
  final String title;
  final String value;

  const CoordinatorLinkSheet({
    super.key,
    required this.title,
    required this.value,
  });

  /// Opens the sheet of [value], under [title], a text of the app.
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
          BullCopyField(text: value, copiedMessage: l10n.p2pCommonCopied),
        ],
      ),
    );
  }
}
