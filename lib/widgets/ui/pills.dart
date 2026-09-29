import 'package:flutter/material.dart';

/// Small coloured pill for deltas, streaks and statuses.
class AppPill extends StatelessWidget {
  final String label;
  final IconData? icon;

  /// Text and icon colour; the fill is a faint tint of it unless
  /// [background] is given.
  final Color? color;
  final Color? background;
  final EdgeInsetsGeometry padding;
  final double iconSize;
  final FontWeight fontWeight;

  const AppPill({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.background,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    this.iconSize = 14,
    this.fontWeight = FontWeight.w700,
  });

  /// Green-ish (primary) for good news, error colour otherwise.
  factory AppPill.trend({
    Key? key,
    required BuildContext context,
    required String label,
    required bool positive,
    IconData? icon,
  }) {
    final colors = Theme.of(context).colorScheme;
    return AppPill(
      key: key,
      label: label,
      icon:
          icon ??
          (positive ? Icons.trending_up_rounded : Icons.trending_down_rounded),
      color: positive ? colors.primary : colors.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? tint.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconSize, color: tint),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: tint,
                fontWeight: fontWeight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Neutral rounded chip with a short "value label" text and an optional icon,
/// for compact summaries (macros of a proposal, counts of a routine).
class AppMetricChip extends StatelessWidget {
  final String text;
  final IconData? icon;

  const AppMetricChip({super.key, required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 15), const SizedBox(width: 4)],
          Text(text, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

/// Segmented pill row (e.g. chart tabs).
class AppSegmentedTabs<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  const AppSegmentedTabs({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: Semantics(
                selected: value == selected,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onChanged(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: value == selected
                          ? colors.primary.withAlpha(45)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          labelOf(value),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: value == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: value == selected
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Short legend entry (swatch + label) for charts and maps.
class AppLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;

  const AppLegendItem({
    super.key,
    required this.color,
    required this.label,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: dashed ? 2 : 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(dashed ? 0 : 3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
