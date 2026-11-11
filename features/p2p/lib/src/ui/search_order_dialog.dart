import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../generated/l10n/p2p_localizations.dart';
import '../domain/order_search.dart';

/// « Search order », opened by « Search » below the book, as in the official client (`components/Dialogs/GoToOrder.tsx` at commit ff1998c): an order URL, « Cancel » and « Search ».
///
/// A text that is not an order URL turns the field red and keeps the dialog open; otherwise the dialog closes with what the search found, for the book to open the order or to say that a robot is needed.
class SearchOrderDialog extends StatefulWidget {
  final OrderSearchOutcome Function(String url) search;

  const SearchOrderDialog({super.key, required this.search});

  /// The longest text the field takes: an order URL is far shorter.
  static const maxLength = 2048;

  /// Opens the dialog; completes with the order found or the need of a robot, or `null` when it is closed without a search.
  static Future<OrderSearchOutcome?> show(
    BuildContext context,
    OrderSearchOutcome Function(String url) search,
  ) => BullDialog.show<OrderSearchOutcome>(
    context: context,
    builder: (_) => SearchOrderDialog(search: search),
  );

  @override
  State<SearchOrderDialog> createState() => _SearchOrderDialogState();
}

class _SearchOrderDialogState extends State<SearchOrderDialog> {
  final _url = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _search() {
    final outcome = widget.search(_url.text);
    if (outcome is OrderSearchInvalidUrl) {
      setState(() => _error = true);
      return;
    }
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final l10n = P2pLocalizations.of(context);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(BullRadius.xxs),
      borderSide: BorderSide(color: color),
    );
    final edge = _error ? colors.error : colors.outline;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.p2pSearchOrderTitle,
            style: text.headlineLarge?.copyWith(color: colors.text),
          ),
          const Gap(BullSpacing.md),
          Text(
            l10n.p2pSearchOrderText,
            style: text.bodyMedium?.copyWith(color: colors.textMuted),
          ),
          const Gap(BullSpacing.md),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            // Not the kit's text field, which has no label nor error state; like it, no personalised learning, and no suggestion, correction or smart punctuation: an order URL is not for the keyboard to learn or to retype.
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            textAlign: TextAlign.center,
            inputFormatters: [
              LengthLimitingTextInputFormatter(SearchOrderDialog.maxLength),
            ],
            style: text.bodyLarge?.copyWith(color: colors.text),
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: l10n.p2pSearchOrderUrlLabel,
              labelStyle: text.bodyMedium?.copyWith(
                color: _error ? colors.error : colors.textMuted,
              ),
              filled: true,
              fillColor: colors.surface,
              enabledBorder: border(edge),
              focusedBorder: border(_error ? colors.error : colors.primary),
            ),
          ),
          const Gap(BullSpacing.md),
          // Side by side when they fit, else one above the other, as the actions of a Material dialog: on a narrow screen or with a large text size the two labels are wider than the dialog.
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  l10n.p2pCommonCancel,
                  style: text.labelLarge?.copyWith(color: colors.primary),
                ),
              ),
              TextButton(
                onPressed: _search,
                child: Text(
                  l10n.p2pCommonSearch,
                  style: text.labelLarge?.copyWith(color: colors.primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
