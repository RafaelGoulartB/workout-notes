import 'package:flutter/material.dart';

import 'package:workout_notes/widgets/ui/app_ui.dart';

/// A big number followed by a smaller unit, aligned on the baseline.
class AppValueUnit extends StatelessWidget {
  final String value;
  final String? unit;
  final TextStyle? valueStyle;
  final TextStyle? unitStyle;

  const AppValueUnit({
    super.key,
    required this.value,
    this.unit,
    this.valueStyle,
    this.unitStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseValue =
        valueStyle ??
        theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value, style: baseValue?.copyWith(fontFeatures: AppUi.tabular)),
        if (unit != null && unit!.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            unit!,
            style:
                unitStyle ??
                theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ],
    );
  }
}

/// Centered metric (icon + value + unit, label below) for hero grids.
class AppStatTile extends StatelessWidget {
  final IconData? icon;
  final Color? color;
  final String label;
  final String value;
  final String? unit;

  /// Smaller value and a label that may wrap to two lines (hero grids).
  final bool dense;

  const AppStatTile({
    super.key,
    this.icon,
    this.color,
    required this.label,
    required this.value,
    this.unit,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: dense ? 14 : 15,
                  color: color ?? theme.colorScheme.primary,
                ),
                SizedBox(width: dense ? 3 : 4),
              ],
              Text(
                value,
                style:
                    (dense
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.titleMedium)
                        ?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          fontFeatures: AppUi.tabular,
                        ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Text(
                  unit!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: dense ? 3 : 4),
        Text(
          label,
          maxLines: dense ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: dense ? 10 : 11,
            height: dense ? 1.2 : null,
          ),
        ),
      ],
    );
  }
}

/// Thin vertical divider between the columns of a stat row.
class AppStatDivider extends StatelessWidget {
  final double height;

  /// Horizontal margin on each side.
  final double margin;

  /// Defaults to the soft outline used by the nutrition macro rows.
  final Color? color;

  const AppStatDivider({
    super.key,
    this.height = 36,
    this.margin = 6,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: height,
      margin: EdgeInsets.symmetric(horizontal: margin),
      color:
          color ?? Theme.of(context).colorScheme.outlineVariant.withAlpha(70),
    );
  }
}

/// Row of equally wide stats separated by thin vertical dividers.
class AppStatRow extends StatelessWidget {
  final List<Widget> children;

  /// Divider between the stats; the soft 34 px one by default.
  final Widget? divider;

  const AppStatRow({super.key, required this.children, this.divider});

  @override
  Widget build(BuildContext context) {
    final separator =
        divider ??
        AppStatDivider(
          height: 34,
          margin: 8,
          color: AppUi.divider(Theme.of(context).colorScheme),
        );
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) separator,
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// Left-aligned stat: a value with an optional smaller [unit], its label and
/// an optional thin progress bar (macros, sleep efficiency...). Meant to sit
/// in an [AppStatRow].
class AppProgressStat extends StatelessWidget {
  final String value;
  final String? unit;
  final String label;

  /// 0..1 fill of the bar under the label; no bar when null.
  final double? progress;
  final Color? color;

  const AppProgressStat({
    super.key,
    required this.value,
    this.unit,
    required this.label,
    this.progress,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tint = color ?? colors.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  fontFeatures: AppUi.tabular,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Text(
                  unit!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        if (progress != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress!.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: tint.withAlpha(35),
              color: tint,
            ),
          ),
        ],
      ],
    );
  }
}

/// Left-aligned metric box (label above value) for detail grids.
class AppMetricBox extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String value;
  final String? unit;
  final bool highlighted;
  final String? caption;

  const AppMetricBox({
    super.key,
    this.icon,
    required this.label,
    required this.value,
    this.unit,
    this.highlighted = false,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: highlighted
            ? colors.primaryContainer.withAlpha(120)
            : colors.surfaceContainerHighest.withAlpha(110),
        borderRadius: BorderRadius.circular(AppUi.tileRadius),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: colors.primary),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AppValueUnit(
                    value: value,
                    unit: unit,
                    valueStyle: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    unitStyle: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (caption != null)
                  Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-column grid of [AppMetricBox]es (or any widgets).
class AppMetricGrid extends StatelessWidget {
  final List<Widget> children;

  const AppMetricGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: 8),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          rows[i],
        ],
      ],
    );
  }
}

/// List row: icon badge, title + subtitle, trailing value and chevron.
class AppListRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? titleTrailing;
  final String? value;
  final String? valueCaption;
  final VoidCallback? onTap;

  const AppListRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.titleTrailing,
    this.value,
    this.valueCaption,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (titleTrailing != null) ...[
                        const SizedBox(width: 6),
                        titleTrailing!,
                      ],
                    ],
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: AppUi.tabular,
                    ),
                  ),
                  if (valueCaption != null)
                    Text(
                      valueCaption!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: AppUi.tabular,
                      ),
                    ),
                ],
              ),
            ],
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant)
            else
              const SizedBox(width: 24),
          ],
        ),
      ),
    );
  }
}
