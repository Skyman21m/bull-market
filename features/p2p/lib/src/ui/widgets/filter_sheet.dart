import 'dart:collection';

import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

/// The list of a selector of the book that takes several choices (currencies, payment methods, hosts), in the design of `BullPickerSheet`: its title, a close button, then [anyLabel] at the top and one row per option, each chosen one checked.
///
/// A tap on an option adds it or takes it back, a tap on [anyLabel] clears the choice, and each tap applies at once through [onChanged], as the official client applies a change of its filter as soon as it is made (`AutocompletePayments`, `onChange`); the sheet stays open for more choices, and closing it, by its button, a tap outside or the back gesture, keeps what was chosen.
/// The choices keep the order they were made in, the first one being the one the sentence names.
/// For a screen reader each row is one node, its label and whether it is checked.
class FilterSheet<T extends Object> extends StatefulWidget {
  final String title;

  /// The entry at the top that clears the choice, checked while nothing is chosen.
  final String anyLabel;

  final List<T> options;

  /// The choices made when the sheet opens, in the order they were made.
  final Iterable<T> selected;

  final String Function(T) label;

  /// What a row shows before its label, such as the image of a coordinator.
  final Widget Function(T)? leading;

  /// Called after each tap with every choice now made, in the order they were made, none for any.
  final ValueChanged<List<T>> onChanged;

  const FilterSheet({
    super.key,
    required this.title,
    required this.anyLabel,
    required this.options,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.leading,
  });

  /// Opens the sheet; completes when it is closed, every choice already applied.
  static Future<void> show<T extends Object>(
    BuildContext context, {
    required String title,
    required String anyLabel,
    required List<T> options,
    required Iterable<T> selected,
    required String Function(T) label,
    required ValueChanged<List<T>> onChanged,
    Widget Function(T)? leading,
  }) => BullBottomSheet.show<void>(
    context: context,
    child: FilterSheet<T>(
      title: title,
      anyLabel: anyLabel,
      options: options,
      selected: selected,
      label: label,
      leading: leading,
      onChanged: onChanged,
    ),
  );

  @override
  State<FilterSheet<T>> createState() => _FilterSheetState<T>();
}

class _FilterSheetState<T extends Object> extends State<FilterSheet<T>> {
  late final LinkedHashSet<T> _chosen = LinkedHashSet.of(widget.selected);

  void _toggle(T option) {
    setState(() {
      if (!_chosen.remove(option)) _chosen.add(option);
    });
    widget.onChanged(List.unmodifiable(_chosen));
  }

  void _clear() {
    if (_chosen.isEmpty) return;
    setState(_chosen.clear);
    widget.onChanged(const []);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    final leading = widget.leading;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Gap(BullSpacing.md),
          Row(
            children: [
              const Gap(48),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: text.headlineMedium?.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                iconSize: 20,
                onPressed: () => Navigator.of(context).pop(),
                color: colors.onSurface,
                icon: const Icon(Icons.close),
              ),
              const Gap(BullSpacing.md),
            ],
          ),
          const Gap(BullSpacing.md),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.options.length + 1,
              itemBuilder: (_, index) {
                if (index == 0) {
                  return _FilterRow(
                    label: widget.anyLabel,
                    checked: _chosen.isEmpty,
                    onTap: _clear,
                  );
                }
                final option = widget.options[index - 1];
                return _FilterRow(
                  label: widget.label(option),
                  leading: leading?.call(option),
                  checked: _chosen.contains(option),
                  onTap: () => _toggle(option),
                );
              },
            ),
          ),
          const Gap(BullSpacing.lg),
        ],
      ),
    );
  }
}

/// One row of [FilterSheet]: its label, in the primary colour with a check when it is chosen, as `BullPickerSheet` draws its selected row.
class _FilterRow extends StatelessWidget {
  final String label;
  final Widget? leading;
  final bool checked;
  final VoidCallback onTap;

  const _FilterRow({
    required this.label,
    required this.checked,
    required this.onTap,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final leading = this.leading;
    return MergeSemantics(
      child: Semantics(
        checked: checked,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            // The padding of the rows of `BullPickerSheet`, which the order type's list uses.
            padding: const EdgeInsets.symmetric(
              vertical: BullSpacing.md + BullSpacing.xxs,
              horizontal: BullSpacing.xl + BullSpacing.xs,
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading, const Gap(BullSpacing.sm)],
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: checked ? colors.primary : colors.onSurface,
                      fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                const Gap(BullSpacing.sm),
                // The place of the check is kept on every row, so that a label does not move when it is checked.
                Icon(
                  Icons.check,
                  color: checked ? colors.primary : colors.transparent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
