import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../generated/l10n/p2p_localizations.dart';
import '../../domain/trade/maker_form.dart';
import 'trade_button.dart';

/// « Add custom payment method », the official client's dialog (`components/Dialogs/AddNewPaymentMethodDialog.tsx`, commit ff1998c), in the wallet's look: its question, its text, the field « Payment method », « Cancel » and « Add payment method ».
///
/// The reference refuses only an empty field (« Can't be empty »); here the field keeps what other robots would see as typed ([CustomPaymentMethod], #181): a text that is only spaces says « Can't be empty », one that holds a character others would not see as typed says so, and « Add payment method » stays disabled for both. The reference's last line, a link to ask RoboSats for the method on its GitHub, is left out: the P2P screens open no link.
class AddPaymentMethodDialog extends StatefulWidget {
  const AddPaymentMethodDialog({super.key});

  /// Opens the dialog; completes with the method kept, or `null` when it is closed without one.
  static Future<CustomPaymentMethod?> show(BuildContext context) =>
      BullDialog.show<CustomPaymentMethod>(
        context: context,
        builder: (_) => const AddPaymentMethodDialog(),
      );

  @override
  State<AddPaymentMethodDialog> createState() => _AddPaymentMethodDialogState();
}

class _AddPaymentMethodDialogState extends State<AddPaymentMethodDialog> {
  final _field = TextEditingController();

  /// Whether something was typed: the reference says « Can't be empty » only once the field changed.
  bool _touched = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    final typed = _field.text;
    final method = CustomPaymentMethod.tryCreate(typed);
    final error = !_touched
        ? null
        : CustomPaymentMethod.isEmpty(typed)
        ? l10n.p2pMakeCustomMethodEmpty
        : method == null
        ? l10n.p2pMakeCustomMethodNotShown
        : null;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(BullRadius.xxs),
      borderSide: BorderSide(color: color),
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.p2pMakeAddCustomMethod,
              style: text.headlineLarge?.copyWith(color: colors.text),
            ),
          ),
          const Gap(BullSpacing.md),
          Text(
            l10n.p2pMakeCustomMethodQuestion,
            style: text.bodyLarge?.copyWith(color: colors.text),
          ),
          const Gap(BullSpacing.sm),
          Text(
            l10n.p2pMakeCustomMethodText,
            style: text.bodyMedium?.copyWith(color: colors.textMuted),
          ),
          const Gap(BullSpacing.md),
          TextField(
            controller: _field,
            autofocus: true,
            maxLines: 1,
            // A name, not a sentence to learn: no suggestion, correction or learning by the keyboard.
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            // The coordinator keeps at most 70 characters of the methods' text; a longer field would say nothing more.
            inputFormatters: [LengthLimitingTextInputFormatter(70)],
            style: text.bodyLarge?.copyWith(color: colors.text),
            onChanged: (_) => setState(() => _touched = true),
            decoration: InputDecoration(
              labelText: '${l10n.p2pMakeCustomMethodLabel} *',
              errorText: error,
              errorMaxLines: 3,
              filled: true,
              fillColor: colors.surface,
              enabledBorder: border(colors.outline),
              focusedBorder: border(colors.primary),
              errorBorder: border(colors.error),
              focusedErrorBorder: border(colors.error),
            ),
          ),
          const Gap(BullSpacing.lg),
          TradeButton(
            label: l10n.p2pCommonCancel,
            outlined: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Gap(BullSpacing.sm),
          TradeButton(
            label: l10n.p2pMakeAddPaymentMethod,
            onPressed: method == null
                ? null
                : () => Navigator.of(context).pop(method),
          ),
        ],
      ),
    );
  }
}
