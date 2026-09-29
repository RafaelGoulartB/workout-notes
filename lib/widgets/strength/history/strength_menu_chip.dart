import 'package:flutter/material.dart';

/// One option of a [StrengthMenuChip].
class StrengthMenuOption<T> {
  final T value;
  final String label;

  const StrengthMenuOption(this.value, this.label);
}

/// Filter chip that opens a single-choice popup menu.
class StrengthMenuChip<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final List<StrengthMenuOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  const StrengthMenuChip({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = active ? colors.onSecondaryContainer : null;
    return PopupMenuButton<T>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final option in options)
          CheckedPopupMenuItem<T>(
            value: option.value,
            checked: option.value == selected,
            child: Text(option.label),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? colors.secondaryContainer : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? Colors.transparent : colors.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(color: foreground),
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, size: 18, color: foreground),
          ],
        ),
      ),
    );
  }
}
