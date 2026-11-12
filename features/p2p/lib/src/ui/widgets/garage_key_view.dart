import 'dart:async';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:robosats/robosats.dart' show GarageKey;

import '../../../generated/l10n/p2p_localizations.dart';
import 'garage_key_clipboard.dart';

/// The Garage Key in its `robo1…` form, with a copy button: the only widget, and the only class, that turns a key into text.
///
/// The custody gate lets `GarageKey.revealBech32` be called in this class alone (`packages/secrets/tool/key_material_gate.dart`).
/// The text is drawn in one [Text], kept out of the semantics tree, as the wallet keeps its recovery phrase out of it: a screen reader, or an accessibility service, hears « Garage Key » and the copy button, never the key.
/// It goes nowhere else: not to a tooltip, a snack bar, a state, a log or a route, and to the clipboard only through [clipboard], which empties it after 30 seconds.
/// Show it only on a screen protected from capture, which the Garage is as a whole.
class GarageKeyView extends StatelessWidget {
  final GarageKey garageKey;
  final GarageKeyClipboard clipboard;

  const GarageKeyView({
    super.key,
    required this.garageKey,
    required this.clipboard,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.p2pGarageKeyLabel,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          BullSpacing.sm,
          BullSpacing.xs,
          0,
          BullSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(BullRadius.xxs),
          border: Border.all(color: colors.outline),
        ),
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  garageKey.revealBech32(),
                  style: text.bodyMedium?.copyWith(
                    color: colors.text,
                    // No monospace token in the theme yet: the family is the platform's own, as on the Silent Payments settings.
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            _CopyButton(
              onCopy: () => clipboard.copy(garageKey, garageKey.revealBech32()),
            ),
          ],
        ),
      ),
    );
  }
}

/// « Copy », then a check mark and « Copied! » for two seconds, as in the official client (`GarageKeyInput.tsx` at commit ff1998c).
class _CopyButton extends StatefulWidget {
  final Future<bool> Function() onCopy;

  const _CopyButton({required this.onCopy});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    if (!await widget.onCopy() || !mounted) return;
    _reset?.cancel();
    setState(() => _copied = true);
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final l10n = P2pLocalizations.of(context);
    return IconButton(
      tooltip: _copied ? l10n.p2pCommonCopied : l10n.p2pCommonCopy,
      onPressed: _copy,
      icon: Icon(
        _copied ? Icons.check : Icons.copy,
        color: _copied ? colors.success : colors.primary,
      ),
    );
  }
}
