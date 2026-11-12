import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/garage_key_text.dart';
import '../../presentation/p2p_failure_l10n.dart';

/// The field where the user pastes or types a Garage Key, as the official client's (`GarageKeyInput.tsx` at commit ff1998c): whitespace removed and lower case as it is typed, and the validator's error under it, or [helper].
///
/// The text cannot be selected from the app's own interface or a hardware keyboard, and the field has no text menu, as the wallet's recovery phrase fields: no Copy or Cut, which would put the key on the clipboard without the clearing of `GarageKeyClipboard`, and no Share or text actions (Android's « Translate » and the like), which would hand it to another app.
/// The system keyboard is another matter: while the field has focus, Android's input connection performs its Select all, Cut and Copy itself, without asking Flutter (`InputConnectionAdaptor` of the engine), so a keyboard's own editing panel can still copy a typed key, and the keyboard receives the text of the field.
/// So a « Paste » button reads the clipboard once, when the user taps it, takes the focus away from the field so that the keyboard is closed, then puts the text in the field through the same cleaning and checks: a pasted key is never sent to the keyboard, unless the user focuses the field again.
/// « Clear » empties the field.
/// The key can also be typed, from a copy on paper: the keyboard is told not to learn, suggest, correct or autofill it, as for a password, but it sees what is typed, where the wallet keeps its recovery phrase off the system keyboard; a field with an in-app keyboard, as the wallet's, is issue #56.
/// The text stays in [controller], which the screen that owns it disposes with it; it is never put in a state, a failure or a log, and it is kept out of the semantics tree, which hears [label], the error and the two buttons, not the text, as the wallet keeps its recovery phrase out of it.
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
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Semantics(
                label: label,
                hint: error ?? helper,
                textField: true,
                excludeSemantics: true,
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  // No selection and no text menu: nothing of the key is copied, cut, shared or sent to another app from here.
                  enableInteractiveSelection: false,
                  contextMenuBuilder: (_, _) => const SizedBox.shrink(),
                  keyboardType: TextInputType.visiblePassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  textCapitalization: TextCapitalization.none,
                  // `null`, not the default empty list: the field takes no part in autofill.
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
                    helperStyle: text.labelMedium?.copyWith(
                      color: colors.textMuted,
                    ),
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
              ),
            ),
            IconButton(
              tooltip: l10n.p2pCommonPaste,
              onPressed: enabled ? () => _paste(context) : null,
              icon: const Icon(Icons.content_paste),
              color: colors.primary,
              disabledColor: colors.textMuted,
            ),
            IconButton(
              tooltip: l10n.p2pCommonClear,
              onPressed: enabled && value.text.isNotEmpty
                  ? controller.clear
                  : null,
              icon: const Icon(Icons.clear),
              color: colors.primary,
              disabledColor: colors.textMuted,
            ),
          ],
        );
      },
    );
  }

  /// Reads the clipboard once, on the user's tap, and puts its text in the field, cleaned and bounded as if it had been typed; an empty or unreadable clipboard changes nothing.
  ///
  /// The focus leaves the field first, and the text is written only once the field has closed its connection to the keyboard: the keyboard never receives a pasted key.
  Future<void> _paste(BuildContext context) async {
    final String? held;
    try {
      held = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on Exception {
      return;
    }
    final cleaned = normalizeGarageKeyText(held ?? '');
    if (cleaned.isEmpty || !context.mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    // The change of focus applies after this turn: the field closes its connection to the keyboard then.
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;
    final bounded = cleaned.length > maxLength
        ? cleaned.substring(0, maxLength)
        : cleaned;
    controller.value = TextEditingValue(
      text: bounded,
      selection: TextSelection.collapsed(offset: bounded.length),
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
