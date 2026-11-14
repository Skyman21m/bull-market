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
    final leading = widget.leading;
    return _SheetFrame(
      title: widget.title,
      rows: widget.options.length + 1,
      row: (index) {
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
    );
  }
}

/// The list of a selector of the book that takes one choice (the order type), drawn as [FilterSheet]: a tap chooses and closes it, as the official client's select does.
class FilterPickerSheet<T extends Object> extends StatelessWidget {
  final String title;
  final List<T> options;
  final T selected;
  final String Function(T) label;

  const FilterPickerSheet({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.label,
  });

  /// Opens the sheet; completes with the option chosen, or `null` when it is closed without a choice.
  static Future<T?> show<T extends Object>(
    BuildContext context, {
    required String title,
    required List<T> options,
    required T selected,
    required String Function(T) label,
  }) => BullBottomSheet.show<T>(
    context: context,
    child: FilterPickerSheet<T>(
      title: title,
      options: options,
      selected: selected,
      label: label,
    ),
  );

  @override
  Widget build(BuildContext context) => _SheetFrame(
    title: title,
    rows: options.length,
    row: (index) {
      final option = options[index];
      return _FilterRow(
        label: label(option),
        checked: option == selected,
        exclusive: true,
        onTap: () => Navigator.of(context).pop(option),
      );
    },
  );
}

/// The frame of the sheets of the filter: the title, centred with the close button beside it, then the rows, in the design of `BullPickerSheet`.
///
/// The title scrolls with the rows rather than staying above them, so that on a small phone with large text, where the title alone can be taller than the sheet, the rows can still be reached.
class _SheetFrame extends StatelessWidget {
  final String title;
  final int rows;
  final Widget Function(int index) row;

  const _SheetFrame({
    required this.title,
    required this.rows,
    required this.row,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final text = Theme.of(context).textTheme;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        // The system's bottom inset too, which a list given its own padding no longer adds: shown without the app's bottom bar, which takes the inset in the tab, the last row stays above the system bar.
        padding: EdgeInsets.only(
          top: BullSpacing.md,
          bottom: BullSpacing.lg + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: rows + 1,
        itemBuilder: (context, index) {
          if (index > 0) return row(index - 1);
          final close = IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            iconSize: 20,
            onPressed: () => Navigator.of(context).pop(),
            color: colors.onSurface,
            icon: const Icon(Icons.close),
          );
          final heading = Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: text.headlineMedium?.copyWith(color: colors.onSurface),
            ),
          );
          // With very large text the close button goes above the title, which then has the whole width: beside it, « Sélectionner » no longer fits on a line of a small phone and breaks in the middle.
          if (_SheetFrame.isLargeText(context)) {
            return Padding(
              padding: const EdgeInsets.only(
                left: BullSpacing.md,
                right: BullSpacing.md,
                bottom: BullSpacing.md,
              ),
              child: Column(
                children: [
                  Align(alignment: AlignmentDirectional.centerEnd, child: close),
                  heading,
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: BullSpacing.md),
            child: Row(
              children: [
                const Gap(48),
                Expanded(child: heading),
                close,
                const Gap(BullSpacing.md),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Whether the text is at least two and a half times its size, where the sheets give their words more room; the normal sizes keep the design of `BullPickerSheet`.
  static bool isLargeText(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1) >= 2.5;
}

/// One row of a sheet of the filter: its label, in the primary colour with a check when it is chosen, as `BullPickerSheet` draws its selected row.
class _FilterRow extends StatelessWidget {
  final String label;
  final Widget? leading;
  final bool checked;
  final VoidCallback onTap;

  /// Whether the row is one of options of which only one is chosen, as a radio button is.
  final bool exclusive;

  const _FilterRow({
    required this.label,
    required this.checked,
    required this.onTap,
    this.leading,
    this.exclusive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    final leading = this.leading;
    return MergeSemantics(
      child: Semantics(
        checked: checked,
        inMutuallyExclusiveGroup: exclusive,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            // The padding of the rows of `BullPickerSheet`, narrower with very large text, so that more of a word fits on a line.
            padding: EdgeInsets.symmetric(
              vertical: BullSpacing.md + BullSpacing.xxs,
              horizontal: _SheetFrame.isLargeText(context)
                  ? BullSpacing.lg
                  : BullSpacing.xl + BullSpacing.xs,
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
