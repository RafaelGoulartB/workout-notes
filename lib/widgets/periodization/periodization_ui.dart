import 'package:flutter/material.dart';

import 'package:workout_notes/models/periodization_phase.dart';

class PeriodizationSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const PeriodizationSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.35,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class PeriodizationSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? accentColor;
  final bool selected;

  const PeriodizationSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.accentColor,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;
    final borderColor = selected
        ? accent.withAlpha(150)
        : theme.colorScheme.outlineVariant.withAlpha(110);
    final background = selected
        ? Color.alphaBlend(
            accent.withAlpha(22),
            theme.colorScheme.surfaceContainerLow,
          )
        : theme.colorScheme.surfaceContainerLow;
    final content = Ink(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
      ),
      child: Padding(padding: padding, child: child),
    );
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(18),
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              child: content,
            ),
    );
  }
}

class PeriodizationMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? supportingText;

  const PeriodizationMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.supportingText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Semantics(
      label: '$label: $value',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.withAlpha(18),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: accent),
            const Spacer(),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (supportingText != null) ...[
              const SizedBox(height: 2),
              Text(
                supportingText!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PeriodizationPhaseTimeline extends StatelessWidget {
  final List<PeriodizationPhase> phases;
  final DateTime referenceDate;
  final String? selectedPhaseId;
  final ValueChanged<PeriodizationPhase>? onPhaseTap;
  final bool showLabels;

  const PeriodizationPhaseTimeline({
    super.key,
    required this.phases,
    required this.referenceDate,
    this.selectedPhaseId,
    this.onPhaseTap,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    if (phases.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final first = phases.first.startDate;
    final last = phases.last.endDate;
    final totalDays = last.difference(first).inDays + 1;
    final elapsed = referenceDate.isBefore(first)
        ? 0
        : referenceDate.isAfter(last)
        ? totalDays
        : referenceDate.difference(first).inDays + 1;
    final progress = (elapsed / totalDays).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 12,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  children: [
                    for (var index = 0; index < phases.length; index++)
                      Expanded(
                        flex: phases[index].totalDays,
                        child: Container(
                          margin: EdgeInsets.only(
                            right: index == phases.length - 1 ? 0 : 2,
                          ),
                          color: Color(phases[index].color).withAlpha(78),
                        ),
                      ),
                  ],
                ),
                FractionallySizedBox(
                  widthFactor: progress,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      for (var index = 0; index < phases.length; index++)
                        Expanded(
                          flex: phases[index].totalDays,
                          child: Container(
                            margin: EdgeInsets.only(
                              right: index == phases.length - 1 ? 0 : 2,
                            ),
                            color: Color(phases[index].color),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showLabels) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: phases.map((phase) {
              final selected = phase.id == selectedPhaseId;
              final active = phase.contains(referenceDate);
              final color = Color(phase.color);
              return Semantics(
                button: onPhaseTap != null,
                selected: selected || active,
                child: InkWell(
                  onTap: onPhaseTap == null ? null : () => onPhaseTap!(phase),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: (selected || active)
                          ? color.withAlpha(30)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: (selected || active)
                            ? color.withAlpha(150)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          phase.name,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: selected || active
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class PeriodizationStatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const PeriodizationStatusPill({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withAlpha(22),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withAlpha(90)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class PeriodizationEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const PeriodizationEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 100),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.secondaryContainer.withAlpha(130),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(
                icon,
                size: 52,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 26),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onPrimary,
              icon: const Icon(Icons.add_rounded),
              label: Text(primaryLabel),
            ),
            if (secondaryLabel != null && onSecondary != null)
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ),
      ),
    );
  }
}

class PeriodizationBottomBar extends StatelessWidget {
  final Widget primary;
  final Widget? secondary;

  const PeriodizationBottomBar({
    super.key,
    required this.primary,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(100),
            ),
          ),
        ),
        child: Row(
          children: [
            if (secondary != null) ...[
              Expanded(child: secondary!),
              const SizedBox(width: 10),
            ],
            Expanded(flex: 2, child: primary),
          ],
        ),
      ),
    );
  }
}
