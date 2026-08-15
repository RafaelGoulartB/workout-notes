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
    final formatter = DateFormat.MMMd(Intl.defaultLocale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: weekCount,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
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
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 56,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? accent.withAlpha(28)
                          : theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isCurrent
                            ? accent.withAlpha(160)
                            : isSelected
                            ? accent.withAlpha(120)
                            : theme.colorScheme.outlineVariant.withAlpha(90),
                        width: isCurrent ? 1.6 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              loc.periodizationWeekChip(index + 1),
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: isLocked
                                    ? theme.colorScheme.onSurfaceVariant
                                    : null,
                              ),
                            ),
                            if (isLocked) ...[
                              const SizedBox(width: 2),
                              Icon(
                                Icons.lock_rounded,
                                size: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ] else if (isCustomized) ...[
                              const SizedBox(width: 3),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.tertiary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatter.format(weekStart(index)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
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
            ),
            if (currentWeek == selected) ...[
              const SizedBox(width: 8),
              _WeekStatusPill(
                label: loc.periodizationWeekCurrent,
                icon: Icons.play_arrow_rounded,
                color: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        _statusRow(context),
        if (locked) ...[
          const SizedBox(height: 8),
          Text(
            loc.periodizationWeekLockedHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _statusRow(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locked = lockedWeeks.contains(selected);
    final customized = customizedWeeks.contains(selected);

    String status;
    IconData icon;
    Color color;
    if (locked) {
      status = loc.periodizationWeekLocked;
      icon = Icons.lock_rounded;
      color = theme.colorScheme.onSurfaceVariant;
    } else if (selected == 0) {
      status = loc.periodizationWeekBase;
      icon = Icons.flag_rounded;
      color = theme.colorScheme.primary;
    } else if (customized) {
      status = loc.periodizationWeekCustomized;
      icon = Icons.tune_rounded;
      color = theme.colorScheme.tertiary;
    } else {
      var source = selected - 1;
      while (source > 0 && !customizedWeeks.contains(source)) {
        source--;
      }
      status = loc.periodizationWeekInheritedFrom(source + 1);
      icon = Icons.subdirectory_arrow_right_rounded;
      color = theme.colorScheme.secondary;
    }

    final actions = <Widget>[
      if (onCustomize != null && !locked && selected > 0 && !customized)
        ActionChip(
          avatar: const Icon(Icons.edit_rounded, size: 16),
          label: Text(loc.periodizationWeekCustomize),
          onPressed: onCustomize,
        ),
      if (onUseInheritance != null && !locked && selected > 0 && customized)
        ActionChip(
          avatar: const Icon(Icons.undo_rounded, size: 16),
          label: Text(loc.periodizationWeekUseInheritance),
          onPressed: onUseInheritance,
        ),
      if (onApplyToFollowing != null &&
          !locked &&
          weekCount > 1 &&
          selected < weekCount - 1 &&
          (selected == 0 || customized))
        ActionChip(
          avatar: const Icon(Icons.content_copy_rounded, size: 16),
          label: Text(loc.periodizationApplyToFollowing),
          onPressed: onApplyToFollowing,
        ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _WeekStatusPill(label: status, icon: icon, color: color),
        ...actions,
      ],
    );
  }
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
