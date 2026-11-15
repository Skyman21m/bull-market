import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_privacy/screen_privacy.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../presentation/chat_cubit.dart';
import '../coordinator_details_dialog.dart';
import '../widgets/trade_button.dart';

/// Copies [text] to the clipboard, as the official client does on a phone; whether it was written.
Future<bool> _copy(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } on PlatformException {
    return false;
  }
}

/// « Audit Chat » of the reference's « Order options » (`TradeBox/Prompts/Chat.tsx`, commit ff1998c): opens « Don't trust, verify ». The dialog of the chat step's options (#95) places it; the chat panel does not show it.
class ChatAuditButton extends StatelessWidget {
  final ChatCubit cubit;

  const ChatAuditButton({super.key, required this.cubit});

  @override
  Widget build(BuildContext context) => TradeButton(
    label: P2pLocalizations.of(context).p2pChatAuditChat,
    icon: Icons.key,
    onPressed: () => unawaited(ChatAuditDialog.show(context, cubit: cubit)),
  );
}

/// « Export » of the reference's « Order options » (`TradeBox/Prompts/Chat.tsx:288`): on a phone the reference copies `complete_log_chat_<order id>.json` to the clipboard (`utils/saveFile.ts`), and so does this button: the keys, the encrypted private key, its passphrase, which is the robot's token, and the messages (the owner's choice, as the reference). The dialog of the chat step's options (#95) places it.
class ChatExportButton extends StatelessWidget {
  final ChatCubit cubit;

  const ChatExportButton({super.key, required this.cubit});

  @override
  Widget build(BuildContext context) => TradeButton(
    label: P2pLocalizations.of(context).p2pChatExport,
    icon: Icons.ios_share,
    onPressed: () async {
      if (await cubit.exported() case final exported?) {
        await _copy(ChatCubit.exportText(exported));
      }
    },
  );
}

/// « Don't trust, verify » (`components/Dialogs/AuditPGP.tsx`, its PGP tab), as the reference shows it: its text, this robot's public key, the peer's, the encrypted private key and its passphrase, which is the robot's token, each with its tooltip and a copy, then « Keys » and « Messages », which on a phone copy their JSON to the clipboard, as the reference does, and « Go back ».
///
/// Beyond the reference: each public key's fingerprint in groups of four, to compare with the peer outside the app (the rules of #92); the dialog is protected from screen capture as the Garage is, since it shows the token, and draws nothing until the protection is on; its link « Learn how to verify » is not shown (the trade screens open no link).
class ChatAuditDialog extends StatefulWidget {
  final ChatCubit cubit;

  const ChatAuditDialog({super.key, required this.cubit});

  /// Opens it for the chat of [cubit].
  static Future<void> show(BuildContext context, {required ChatCubit cubit}) =>
      BullDialog.show<void>(
        context: context,
        builder: (_) => ChatAuditDialog(cubit: cubit),
      );

  @override
  State<ChatAuditDialog> createState() => _ChatAuditDialogState();
}

class _ChatAuditDialogState extends State<ChatAuditDialog> with PrivacyScreen {
  late Future<bool> _protection = enableScreenPrivacy();
  late Future<Map<String, Object?>?> _exported = widget.cubit.exported();

  @override
  void dispose() {
    unawaited(disableScreenPrivacy());
    super.dispose();
  }

  Widget _failure(BuildContext context, String text, VoidCallback onRetry) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.error),
        ),
        const Gap(BullSpacing.sm),
        TradeButton(
          label: l10n.p2pCommonRetry,
          outlined: true,
          onPressed: onRetry,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    return FutureBuilder<bool>(
      future: _protection,
      builder: (context, protection) {
        if (protection.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (protection.data != true) {
          return _failure(
            context,
            l10n.p2pChatScreenPrivacyUnavailable,
            () => setState(() {
              _protection = enableScreenPrivacy();
            }),
          );
        }
        return FutureBuilder<Map<String, Object?>?>(
          future: _exported,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final exported = snapshot.data;
            if (exported == null) {
              return _failure(
                context,
                l10n.p2pChatUnavailable,
                () => setState(() {
                  _exported = widget.cubit.exported();
                }),
              );
            }
            return _body(context, exported);
          },
        );
      },
    );
  }

  Widget _body(BuildContext context, Map<String, Object?> exported) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final styles = Theme.of(context).textTheme;
    final credentials = switch (exported['credentials']) {
      final Map<String, Object?> map => map,
      _ => const <String, Object?>{},
    };
    String? field(String name) => switch (credentials[name]) {
      final String value when value.isNotEmpty => value,
      _ => null,
    };
    final own = field('own_public_key');
    final peer = field('peer_public_key');
    final private = field('encrypted_private_key');
    final passphrase = field('passphrase');
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
            _CredentialField(
              label: l10n.p2pChatYourPublicKey,
              tooltip: l10n.p2pChatYourPublicKeyTooltip,
              value: own,
              fingerprint: widget.cubit.state.view.ownKey?.fingerprint,
            ),
          if (peer != null) ...[
            const Gap(BullSpacing.sm),
            _CredentialField(
              label: l10n.p2pChatPeerPublicKey,
              tooltip: l10n.p2pChatPeerPublicKeyTooltip,
              value: peer,
              fingerprint: widget.cubit.pinnedPeerFingerprint,
            ),
          ],
          if (private != null) ...[
            const Gap(BullSpacing.sm),
            _CredentialField(
              label: l10n.p2pChatYourEncryptedPrivateKey,
              tooltip: l10n.p2pChatYourEncryptedPrivateKeyTooltip,
              value: private,
            ),
          ],
          if (passphrase != null) ...[
            const Gap(BullSpacing.sm),
            _CredentialField(
              label: l10n.p2pChatPassphrase,
              tooltip: l10n.p2pChatPassphraseTooltip,
              value: passphrase,
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
                    icon: Icons.key,
                    onPressed: () =>
                        unawaited(_copy(ChatCubit.keysText(exported))),
                  ),
                ),
              ),
              const Gap(BullSpacing.sm),
              Expanded(
                child: Tooltip(
                  message: l10n.p2pChatSaveMessagesTooltip,
                  child: TradeButton(
                    label: l10n.p2pChatSaveMessages,
                    icon: Icons.forum,
                    onPressed: () =>
                        unawaited(_copy(ChatCubit.messagesText(exported))),
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

/// A field of « Don't trust, verify » (`CredentialTextfield`): its label with the reference's tooltip, the value and a copy with « Copied! »; for a public key, its fingerprint too.
class _CredentialField extends StatefulWidget {
  final String label;
  final String tooltip;
  final String value;
  final String? fingerprint;

  const _CredentialField({
    required this.label,
    required this.tooltip,
    required this.value,
    this.fingerprint,
  });

  @override
  State<_CredentialField> createState() => _CredentialFieldState();
}

class _CredentialFieldState extends State<_CredentialField> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final l10n = P2pLocalizations.of(context);
    final colors = context.bull;
    final styles = Theme.of(context).textTheme;
    final fingerprint = widget.fingerprint;
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
                onPressed: () async {
                  final copied = await _copy(widget.value);
                  if (copied && mounted) setState(() => _copied = true);
                },
                icon: Icon(Icons.content_copy, color: colors.textMuted),
              ),
            ],
          ),
          if (fingerprint != null)
            Text(
              l10n.p2pChatFingerprint(
                CoordinatorContacts.groupFingerprint(fingerprint),
              ),
              style: styles.bodyMedium?.copyWith(color: colors.onSurface),
            ),
          const Gap(BullSpacing.xs),
          SizedBox(
            height: 64,
            child: SingleChildScrollView(
              child: Text(
                widget.value,
                textDirection: TextDirection.ltr,
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
