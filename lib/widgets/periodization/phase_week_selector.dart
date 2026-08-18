import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';

/// Week context header for the phase form target section.
///
/// This is the *parent* of every target card below it: the stepper picks
/// which week the cards edit. Weeks are 0-indexed: index 0 is the base
/// week (always shown as such), indexes in [customizedWeeks] carry their
/// own override and the remaining ones inherit from the nearest previous
/// customized week. Weeks in [lockedWeeks] already ended and are
/// view-only.
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
  final VoidCallback? onCopy;

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
    this.onCopy,
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
            _stepperButton(
              context,
              icon: Icons.chevron_left_rounded,
              onPressed: selected > 0 ? () => onSelect(selected - 1) : null,
              semanticLabel: loc.periodizationWeekPrevious,
              buttonKey: const Key('weekStepperPrev'),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    loc.periodizationWeekOf(selected + 1, weekCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatter.format(weekStart(selected))}'
                    ' – ${formatter.format(weekEnd(selected))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            _stepperButton(
              context,
              icon: Icons.chevron_right_rounded,
              onPressed: selected < weekCount - 1
                  ? () => onSelect(selected + 1)
                  : null,
              semanticLabel: loc.periodizationWeekNext,
              buttonKey: const Key('weekStepperNext'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.center,
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
        ),
        const SizedBox(height: 14),
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

  Widget _stepperButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback? onPressed,
    String? semanticLabel,
    Key? buttonKey,
  }) {
    final theme = Theme.of(context);
    return IconButton(
      key: buttonKey,
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: semanticLabel,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(
          90,
        ),
        disabledBackgroundColor: Colors.transparent,
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
      if (onCopy != null && !locked && weekCount > 1 && (selected == 0 || customized))
        _WeekActionButton(
          icon: Icons.copy_all_rounded,
          label: loc.periodizationWeekCopyTo,
          onPressed: onCopy!,
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
