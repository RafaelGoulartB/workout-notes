import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';

/// Weekly chip strip + heading row for the phase form target section.
///
/// Weeks are 0-indexed: index 0 is the base week (always shown as such),
/// indexes in [customizedWeeks] carry their own override and the remaining
/// ones inherit from the nearest previous customized week. Weeks in
/// [lockedWeeks] already ended and are view-only.
class PhaseWeekSelector extends StatelessWidget {
  final int weekCount;
  final int selected;
  final DateTime firstWeekStart;
  final DateTime phaseEnd;
  final Set<int> customizedWeeks;
  final Set<int> lockedWeeks;
  final int? currentWeek;
  final ValueChanged<int> onSelect;
  final VoidCallback? onCustomize;
  final VoidCallback? onUseInheritance;
  final VoidCallback? onApplyToFollowing;

  const PhaseWeekSelector({
    super.key,
    required this.weekCount,
    required this.selected,
    required this.firstWeekStart,
    required this.phaseEnd,
    required this.customizedWeeks,
    required this.lockedWeeks,
    required this.currentWeek,
    required this.onSelect,
    this.onCustomize,
    this.onUseInheritance,
    this.onApplyToFollowing,
  });

  DateTime weekStart(int index) =>
      firstWeekStart.add(Duration(days: 7 * index));

  DateTime weekEnd(int index) {
    final nominal = weekStart(index).add(const Duration(days: 6));
    return index == weekCount - 1 && nominal.isAfter(phaseEnd)
        ? phaseEnd
        : nominal;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locked = lockedWeeks.contains(selected);
    final customized = customizedWeeks.contains(selected);
    final formatter = DateFormat.MMMd(Intl.defaultLocale);

    final statusInfo = _statusInfo(context, locked, customized);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(125),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.calendar_view_week_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.periodizationWeekHeading(
                      selected + 1,
                      formatter.format(weekStart(selected)),
                      formatter.format(weekEnd(selected)),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _WeekStatusPill(
                        label: statusInfo.label,
                        icon: statusInfo.icon,
                        color: statusInfo.color,
                      ),
                      if (currentWeek == selected)
                        _WeekStatusPill(
                          label: loc.periodizationWeekCurrent,
                          icon: Icons.play_arrow_rounded,
                          color: theme.colorScheme.primary,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: weekCount,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) =>
                _weekTab(context, index, formatter, theme),
          ),
        ),
        const SizedBox(height: 12),
        _actionRow(context),
        if (locked) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.periodizationWeekLockedHelp,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _weekTab(
    BuildContext context,
    int index,
    DateFormat formatter,
    ThemeData theme,
  ) {
    final isSelected = index == selected;
    final isLocked = lockedWeeks.contains(index);
    final isCustomized = customizedWeeks.contains(index);
    final isCurrent = index == currentWeek;
    final accent = isLocked
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.primary;
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: () => onSelect(index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minWidth: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withAlpha(28)
                : theme.colorScheme.surfaceContainerHighest.withAlpha(60),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? accent.withAlpha(160)
                  : theme.colorScheme.outlineVariant.withAlpha(70),
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'S${index + 1}',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isLocked
                      ? theme.colorScheme.onSurfaceVariant
                      : isSelected
                      ? accent
                      : theme.colorScheme.onSurface,
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 4),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ] else if (isCustomized && !isLocked) ...[
                const SizedBox(width: 4),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              if (isLocked) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.lock_rounded,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _StatusInfo _statusInfo(BuildContext context, bool locked, bool customized) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (locked) {
      return _StatusInfo(
        loc.periodizationWeekLocked,
        Icons.lock_rounded,
        theme.colorScheme.onSurfaceVariant,
      );
    }
    if (selected == 0) {
      return _StatusInfo(
        loc.periodizationWeekBase,
        Icons.flag_rounded,
        theme.colorScheme.primary,
      );
    }
    if (customized) {
      return _StatusInfo(
        loc.periodizationWeekCustomized,
        Icons.tune_rounded,
        theme.colorScheme.tertiary,
      );
    }
    var source = selected - 1;
    while (source > 0 && !customizedWeeks.contains(source)) {
      source--;
    }
    return _StatusInfo(
      loc.periodizationWeekInheritedFrom(source + 1),
      Icons.subdirectory_arrow_right_rounded,
      theme.colorScheme.secondary,
    );
  }

  Widget _actionRow(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locked = lockedWeeks.contains(selected);
    final customized = customizedWeeks.contains(selected);
    final actions = <Widget>[
      if (onCustomize != null && !locked && selected > 0 && !customized)
        _WeekActionButton(
          icon: Icons.edit_rounded,
          label: loc.periodizationWeekCustomize,
          onPressed: onCustomize!,
          color: theme.colorScheme.primary,
        ),
      if (onUseInheritance != null && !locked && selected > 0 && customized)
        _WeekActionButton(
          icon: Icons.undo_rounded,
          label: loc.periodizationWeekUseInheritance,
          onPressed: onUseInheritance!,
          color: theme.colorScheme.secondary,
        ),
      if (onApplyToFollowing != null &&
          !locked &&
          weekCount > 1 &&
          selected < weekCount - 1 &&
          (selected == 0 || customized))
        _WeekActionButton(
          icon: Icons.content_copy_rounded,
          label: loc.periodizationApplyToFollowing,
          onPressed: onApplyToFollowing!,
          color: theme.colorScheme.tertiary,
        ),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: actions);
  }
}

class _StatusInfo {
  final String label;
  final IconData icon;
  final Color color;
  const _StatusInfo(this.label, this.icon, this.color);
}

class _WeekStatusPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _WeekStatusPill({
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

class _WeekActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;

  const _WeekActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color.withAlpha(22),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withAlpha(90)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
