import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:robosats/robosats.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/trade_chat.dart';
import '../../presentation/chat_cubit.dart';
import '../coordinator_details_dialog.dart';
import '../widgets/trade_button.dart';

/// « Audit Chat » of the reference's « Order options » (`TradeBox/Prompts/Chat.tsx`, commit ff1998c): opens « Don't trust, verify ». The dialog of the chat step's options (#95) places it; the chat panel does not show it.
class ChatAuditButton extends StatelessWidget {
  final ChatCubit cubit;
  final ChatShare share;

  const ChatAuditButton({super.key, required this.cubit, required this.share});

  @override
  Widget build(BuildContext context) => TradeButton(
    label: P2pLocalizations.of(context).p2pChatAuditChat,
    icon: Icons.key,
    onPressed: () =>
        unawaited(ChatAuditDialog.show(context, cubit: cubit, share: share)),
  );
}

/// « Export » of the reference's « Order options » (`TradeBox/Prompts/Chat.tsx:288`): hands `complete_log_chat_<order id>.json` to the share sheet, the public keys and the messages, never the token nor the private key (`AGENTS.md`). The dialog of the chat step's options (#95) places it.
class ChatExportButton extends StatelessWidget {
  final ChatCubit cubit;
  final ChatShare share;

  const ChatExportButton({super.key, required this.cubit, required this.share});

  @override
  Widget build(BuildContext context) => TradeButton(
    label: P2pLocalizations.of(context).p2pChatExport,
    icon: Icons.ios_share,
    onPressed: () => unawaited(share(cubit.exportFileName, cubit.exportJson())),
  );
}

/// « Don't trust, verify » (`components/Dialogs/AuditPGP.tsx`, its PGP tab): the reference's text, this robot's public key and the peer's, each with its fingerprint in groups of four and a copy, and « Keys » and « Messages », which hand their parts of the export to the share sheet.
///
/// Unlike the reference, it shows neither the encrypted private key nor its passphrase, the robot's token, and « Keys » leaves them out (`AGENTS.md`); its link « Learn how to verify » is not shown.
class ChatAuditDialog extends StatelessWidget {
  final PgpPublicKey? own;

  /// The peer's key pinned for the trade, kept after a change.
  final PgpPublicKey? peer;
  final VoidCallback onKeys;
  final VoidCallback onMessages;

  const ChatAuditDialog({
    super.key,
    required this.own,
    required this.peer,
    required this.onKeys,
    required this.onMessages,
  });

  /// Opens it with the keys [cubit]'s chat knows; « Keys » and « Messages » hand their files to [share].
  static Future<void> show(
    BuildContext context, {
    required ChatCubit cubit,
    required ChatShare share,
  }) {
    final view = cubit.state.view;
    return BullDialog.show<void>(
      context: context,
      builder: (_) => ChatAuditDialog(
        own: view.ownKey,
        peer: switch (view.peerKey) {
          ChatPeerKeyPinned(:final key) => key,
          ChatPeerKeyBreach(:final pinned) => pinned,
          ChatPeerKeyAwaited() => null,
        },
        onKeys: () => unawaited(share(cubit.keysFileName, cubit.keysJson())),
        onMessages: () =>
            unawaited(share(cubit.messagesFileName, cubit.messagesJson())),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final styles = Theme.of(context).textTheme;
    final own = this.own;
    final peer = this.peer;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            header: true,
            child: Text(
              l10n.p2pChatAuditTitle,
              style: styles.titleLarge?.copyWith(color: colors.onSurface),
            ),
          ),
          const Gap(BullSpacing.sm),
          Text(
            l10n.p2pChatAuditText,
            style: styles.bodyMedium?.copyWith(color: colors.onSurface),
          ),
          const Gap(BullSpacing.md),
          if (own != null)
            _KeyField(
              label: l10n.p2pChatYourPublicKey,
              tooltip: l10n.p2pChatYourPublicKeyTooltip,
              publicKey: own,
            ),
          if (peer != null) ...[
            const Gap(BullSpacing.sm),
            _KeyField(
              label: l10n.p2pChatPeerPublicKey,
              tooltip: l10n.p2pChatPeerPublicKeyTooltip,
              publicKey: peer,
            ),
          ],
          const Gap(BullSpacing.md),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: l10n.p2pChatSaveKeysTooltip,
                  child: TradeButton(
                    label: l10n.p2pChatSaveKeys,
                    icon: Icons.ios_share,
                    onPressed: onKeys,
                  ),
                ),
              ),
              const Gap(BullSpacing.sm),
              Expanded(
                child: Tooltip(
                  message: l10n.p2pChatSaveMessagesTooltip,
                  child: TradeButton(
                    label: l10n.p2pChatSaveMessages,
                    icon: Icons.ios_share,
                    onPressed: onMessages,
                  ),
                ),
              ),
            ],
          ),
          const Gap(BullSpacing.sm),
          TradeButton(
            label: l10n.p2pCommonGoBack,
            outlined: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// A key of « Don't trust, verify » (`CredentialTextfield`): its label with the reference's tooltip, its fingerprint, the armored key, and a copy of it.
class _KeyField extends StatefulWidget {
  final String label;
  final String tooltip;
  final PgpPublicKey publicKey;

  const _KeyField({
    required this.label,
    required this.tooltip,
    required this.publicKey,
  });

  @override
  State<_KeyField> createState() => _KeyFieldState();
}

class _KeyFieldState extends State<_KeyField> {
  bool _copied = false;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.publicKey.armored));
    } on PlatformException {
      return;
    }
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final styles = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(BullSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(BullRadius.xxs),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: widget.tooltip,
                  triggerMode: TooltipTriggerMode.tap,
                  child: Text(
                    widget.label,
                    style: styles.labelLarge?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: _copied ? l10n.p2pCommonCopied : l10n.p2pCommonCopy,
                onPressed: () => unawaited(_copy()),
                icon: Icon(Icons.content_copy, color: colors.textMuted),
              ),
            ],
          ),
          Text(
            l10n.p2pChatFingerprint(
              CoordinatorContacts.groupFingerprint(
                widget.publicKey.fingerprint,
              ),
            ),
            style: styles.bodyMedium?.copyWith(color: colors.onSurface),
          ),
          const Gap(BullSpacing.xs),
          SizedBox(
            height: 64,
            child: SingleChildScrollView(
              child: Text(
                widget.publicKey.armored,
                style: styles.bodySmall?.copyWith(color: colors.textMuted),
              ),
            ),
          ),
          if (_copied)
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.p2pCommonCopied,
                style: styles.bodySmall?.copyWith(color: colors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
