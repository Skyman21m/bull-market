import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/garage_key_text.dart';
import '../../presentation/p2p_failure_l10n.dart';

/// The field where the user pastes or types a Garage Key, as the official client's (`GarageKeyInput.tsx` at commit ff1998c): whitespace removed and lower case as it is typed, and the validator's error under it, or [helper].
///
/// The keyboard is told not to learn, suggest or correct it, as for a password.
/// The text stays in [controller], which the screen that owns it disposes with it; it is never put in a state, a failure or a log, and it is kept out of the semantics tree, which hears [label] only, as the wallet keeps its recovery phrase out of it.
class GarageKeyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? helper;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  const GarageKeyField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.enabled = true,
    this.onSubmitted,
  });

  /// The longest text the field takes: a Garage Key is 63 characters, and a text pasted with spaces a little more.
  static const maxLength = 256;

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(BullRadius.xxs),
      borderSide: BorderSide(color: color),
    );
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final error = garageKeyTextError(value.text, l10n);
        return Semantics(
          label: label,
          hint: error ?? helper,
          textField: true,
          excludeSemantics: true,
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            textCapitalization: TextCapitalization.none,
            autofillHints: null,
            inputFormatters: [
              LengthLimitingTextInputFormatter(maxLength),
              const _GarageKeyFormatter(),
            ],
            onSubmitted: onSubmitted,
            style: text.bodyMedium?.copyWith(
              color: colors.text,
              // No monospace token in the theme yet: the family is the platform's own, as on the Silent Payments settings.
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: text.bodyMedium?.copyWith(
                color: error == null ? colors.textMuted : colors.error,
              ),
              helperText: error == null ? helper : null,
              helperMaxLines: 2,
              helperStyle: text.labelMedium?.copyWith(color: colors.textMuted),
              errorText: error,
              errorMaxLines: 2,
              errorStyle: text.labelMedium?.copyWith(color: colors.error),
              filled: true,
              fillColor: colors.surface,
              enabledBorder: border(colors.outline),
              focusedBorder: border(colors.primary),
              errorBorder: border(colors.error),
              focusedErrorBorder: border(colors.error),
              disabledBorder: border(colors.outlineVariant),
            ),
          ),
        );
      },
    );
  }
}

/// Removes every whitespace and lowers the case as the user types or pastes, as the official client does, keeping the cursor at the end of what was entered.
final class _GarageKeyFormatter extends TextInputFormatter {
  const _GarageKeyFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = normalizeGarageKeyText(newValue.text);
    if (cleaned == newValue.text) return newValue;
    final cursor = normalizeGarageKeyText(
      newValue.text.substring(
        0,
        newValue.selection.end.clamp(0, newValue.text.length),
      ),
    ).length;
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}
