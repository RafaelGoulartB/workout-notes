import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Shared building blocks for the running screens so cards, headers, metric
/// tiles and pills look the same everywhere.
abstract final class RunUi {
  static const double cardRadius = 16;
  static const double heroRadius = 20;
  static const double tileRadius = 12;
  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(16, 12, 16, 110);

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static Color divider(ColorScheme colors) =>
      colors.outlineVariant.withAlpha(80);
}

/// Uppercase, letter-spaced section label with an optional trailing action.
class RunSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsets padding;

  const RunSectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 22, 0, 10),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Compact text button used as a section header action ("See all").
class RunHeaderAction extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const RunHeaderAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// Flat outlined surface card used for every section.
class RunSectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  const RunSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(RunUi.cardRadius),
      side: BorderSide(color: RunUi.divider(colors)),
    );
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: color,
      clipBehavior: Clip.antiAlias,
      shape: shape,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

/// Gradient hero container for the headline numbers of a screen.
class RunHeroCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const RunHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 14),
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.surfaceContainerHighest.withAlpha(200),
            colors.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(RunUi.heroRadius),
        border: Border.all(color: RunUi.divider(colors)),
      ),
      child: child,
    );
  }
}

/// Rounded tinted square holding an icon.
class RunIconBadge extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;

  const RunIconBadge(
    this.icon, {
    super.key,
    this.color,
    this.size = 34,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: iconSize, color: tint),
    );
  }
}

/// A big number followed by a smaller unit, aligned on the baseline.
class RunValueUnit extends StatelessWidget {
  final String value;
  final String? unit;
  final TextStyle? valueStyle;
  final TextStyle? unitStyle;

  const RunValueUnit({
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
        Text(value, style: baseValue?.copyWith(fontFeatures: RunUi.tabular)),
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
class RunStatTile extends StatelessWidget {
  final IconData? icon;
  final Color? color;
  final String label;
  final String value;
  final String? unit;

  const RunStatTile({
    super.key,
    this.icon,
    this.color,
    required this.label,
    required this.value,
    this.unit,
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
                Icon(icon, size: 15, color: color ?? theme.colorScheme.primary),
                const SizedBox(width: 4),
              ],
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  fontFeatures: RunUi.tabular,
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
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Row of [RunStatTile]s separated by thin vertical dividers.
class RunStatRow extends StatelessWidget {
  final List<Widget> children;

  const RunStatRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final divider = RunUi.divider(Theme.of(context).colorScheme);
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 34,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: divider,
            ),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

/// Left-aligned metric box (label above value) for detail grids.
class RunMetricBox extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String value;
  final String? unit;
  final bool highlighted;
  final String? caption;

  const RunMetricBox({
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
        borderRadius: BorderRadius.circular(RunUi.tileRadius),
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
                  child: RunValueUnit(
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

/// Two-column grid of [RunMetricBox]es (or any widgets).
class RunMetricGrid extends StatelessWidget {
  final List<Widget> children;
  final double spacing;

  const RunMetricGrid({super.key, required this.children, this.spacing = 8});

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
              SizedBox(width: spacing),
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
          if (i > 0) SizedBox(height: spacing),
          rows[i],
        ],
      ],
    );
  }
}

/// Small coloured pill for deltas, streaks and statuses.
class RunPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;

  const RunPill({super.key, required this.label, this.icon, this.color});

  /// Green-ish (primary) for good news, error colour otherwise.
  factory RunPill.trend({
    Key? key,
    required BuildContext context,
    required String label,
    required bool positive,
    IconData? icon,
  }) {
    final colors = Theme.of(context).colorScheme;
    return RunPill(
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tint.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: tint),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: tint,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented pill row (e.g. chart tabs).
class RunSegmentedTabs<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  const RunSegmentedTabs({
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

/// List row: icon badge, title + subtitle, trailing value and chevron.
class RunListRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? titleTrailing;
  final String? value;
  final String? valueCaption;
  final VoidCallback? onTap;

  const RunListRow({
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
                      fontFeatures: RunUi.tabular,
                    ),
                  ),
                  if (valueCaption != null)
                    Text(
                      valueCaption!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: RunUi.tabular,
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

/// Divided column of rows inside a [RunSectionCard].
class RunDividedList extends StatelessWidget {
  final List<Widget> children;

  const RunDividedList({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant.withAlpha(70);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, color: color),
          children[i],
        ],
      ],
    );
  }
}

/// Short legend entry (swatch + label) for charts and maps.
class RunLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;

  const RunLegendItem({
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

/// Soft headline surface shared with the nutrition "day summary" card: a
/// subtle neutral diagonal gradient, no border and a 20 px radius.
class RunSoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const RunSoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 16, 16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final body = Padding(padding: padding, child: child);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(RunUi.heroRadius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.surfaceContainerHighest.withAlpha(200),
              colors.surfaceContainerLow,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(RunUi.heroRadius),
        ),
        child: onTap == null ? body : InkWell(onTap: onTap, child: body),
      ),
    );
  }
}

/// "Today · Tue, Sep 29" title row of the hub "today" cards.
class RunTodayHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  /// Appends today's date; off where the screen already shows it.
  final bool showDate;

  const RunTodayHeader({
    super.key,
    required this.title,
    this.icon = Icons.today_rounded,
    this.showDate = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final date = DateFormat.MMMEd(
      Localizations.localeOf(context).toString(),
    ).format(DateTime.now());
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 6),
        if (showDate)
          Expanded(
            child: Text(
              '· $date',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Bottom row of a "today" card: where the session comes from on the left
/// and a compact start button on the right.
class RunTodayFooter extends StatelessWidget {
  final String? caption;
  final IconData captionIcon;
  final Key? actionKey;
  final String actionLabel;
  final VoidCallback onAction;

  const RunTodayFooter({
    super.key,
    this.caption,
    this.captionIcon = Icons.event_note_rounded,
    this.actionKey,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final button = FilledButton.icon(
      key: actionKey,
      onPressed: onAction,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text(actionLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    if (caption == null) {
      return Align(alignment: Alignment.centerRight, child: button);
    }
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(captionIcon, size: 15, color: colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    caption!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
            child: button,
          ),
        ],
      ),
    );
  }
}
