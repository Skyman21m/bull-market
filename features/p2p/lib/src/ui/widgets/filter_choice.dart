import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';

/// A choice of the book, such as one of the filter sentence or the axis of the depth chart: the current value in a box that opens its list.
class FilterChoice extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const FilterChoice({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.bull;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BullRadius.xxs),
        side: BorderSide(color: colors.outline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BullRadius.xxs),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BullSpacing.sm,
            vertical: BullSpacing.xxs + 2,
          ),
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: colors.text),
          ),
        ),
      ),
    );
  }
}
