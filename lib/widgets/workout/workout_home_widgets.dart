import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// What happened (or is planned) on one day of the current week.
class WorkoutDayMark {
  final DateTime date;
  final bool strengthDone;
  final bool runDone;
  final bool strengthPlanned;
  final bool runPlanned;

  const WorkoutDayMark({
    required this.date,
    this.strengthDone = false,
    this.runDone = false,
    this.strengthPlanned = false,
    this.runPlanned = false,
  });
}

/// "Your week": one progress ring per sport, the Monday–Sunday strip with a
/// bubble per day (filled when done, dashed when only planned) and active
/// time + streak.
class WorkoutWeekHero extends StatelessWidget {
  final int strengthDone;
  final int? strengthGoal;
  final double runMeters;
  final double? runGoalMeters;
  final int activeSeconds;
  final int streakWeeks;
  final List<WorkoutDayMark> days;
  final DateTime today;
  final VoidCallback onOpenStrength;
  final VoidCallback onOpenRun;

  const WorkoutWeekHero({
    super.key,
    required this.strengthDone,
    required this.strengthGoal,
    required this.runMeters,
    required this.runGoalMeters,
    required this.activeSeconds,
    required this.streakWeeks,
    required this.days,
    required this.today,
    required this.onOpenStrength,
    required this.onOpenRun,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final strengthColor = colors.primary;
    final runColor = colors.tertiary;

    return AppHeroCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _SportRing(
                  key: const Key('workout-home-ring-strength'),
                  color: strengthColor,
                  icon: Icons.fitness_center,
                  progress: strengthGoal == null || strengthGoal! <= 0
                      ? (strengthDone > 0 ? 1 : 0)
                      : strengthDone / strengthGoal!,
                  value: '$strengthDone',
                  caption: loc.strengthHomeWorkoutsUnit(strengthDone),
                  goal: strengthGoal == null
                      ? null
                      : loc.workoutHomeRingOfGoal('$strengthGoal'),
                  onTap: onOpenStrength,
                ),
              ),
              Container(width: 1, height: 44, color: AppUi.divider(colors)),
              Expanded(
                child: _SportRing(
                  key: const Key('workout-home-ring-run'),
                  color: runColor,
                  icon: Icons.directions_run,
                  progress: runGoalMeters == null || runGoalMeters! <= 0
                      ? (runMeters > 0 ? 1 : 0)
                      : runMeters / runGoalMeters!,
                  value: RunFormatters.distanceKmShort(runMeters),
                  caption: loc.workoutHomeRingRunCaption,
                  goal: runGoalMeters == null
                      ? null
                      : loc.workoutHomeRingOfGoal(
                          RunFormatters.distanceKmShort(runGoalMeters!),
                        ),
                  onTap: onOpenRun,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _WeekDots(
            days: days,
            today: today,
            strengthColor: strengthColor,
            runColor: runColor,
          ),
          const SizedBox(height: 14),
          Divider(height: 1, thickness: 1, color: AppUi.divider(colors)),
          const SizedBox(height: 10),
          // Legend on the left, active time and streak on the right.
          Row(
            children: [
              _LegendMark(
                color: colors.onSurfaceVariant,
                label: loc.workoutHomeLegendDone,
              ),
              const SizedBox(width: 12),
              _LegendMark(
                color: colors.onSurfaceVariant,
                label: loc.workoutHomeLegendPlanned,
                outlined: true,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  // Shrinks instead of overflowing on narrow screens or with
                  // large system fonts.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppPill(
                          icon: Icons.timer_outlined,
                          label: RunFormatters.durationHoursMinutes(
                            activeSeconds,
                          ),
                          color: colors.onSurfaceVariant,
                          background: colors.surfaceContainerHighest.withAlpha(
                            140,
                          ),
                        ),
                        if (streakWeeks > 0) ...[
                          const SizedBox(width: 6),
                          AppPill(
                            icon: Icons.local_fire_department_rounded,
                            label: '$streakWeeks ${loc.workoutHomeWeeksShort}',
                            color: Colors.orange,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One sport's weekly progress: the ring, the value and the "of goal"
/// caption.
class _SportRing extends StatelessWidget {
  final Color color;
  final IconData icon;
  final double progress;
  final String value;
  final String caption;
  final String? goal;
  final VoidCallback onTap;

  const _SportRing({
    super.key,
    required this.color,
    required this.icon,
    required this.progress,
    required this.value,
    required this.caption,
    required this.goal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final clamped = progress.clamp(0.0, 1.0);
    final reached = goal != null && clamped >= 1;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppUi.tileRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CustomPaint(
                painter: RingPainter(
                  progress: clamped,
                  color: color,
                  track: color.withAlpha(45),
                  strokeWidth: 4,
                ),
                child: Center(
                  child: Icon(
                    reached ? Icons.check_rounded : icon,
                    color: color,
                    size: reached ? 24 : 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        fontFeatures: AppUi.tabular,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Shrinks the "of goal" caption instead of cutting it.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        text: caption,
                        children: [
                          if (goal != null)
                            TextSpan(
                              text: ' $goal',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Monday–Sunday, one column per day: the weekday letter over one small
/// circle per sport (filled when done, dashed when only planned, overlapped
/// when both sports fall on the day), today's column tinted.
class _WeekDots extends StatelessWidget {
  final List<WorkoutDayMark> days;
  final DateTime today;
  final Color strengthColor;
  final Color runColor;

  const _WeekDots({
    required this.days,
    required this.today,
    required this.strengthColor,
    required this.runColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();

    return Row(
      children: [
        for (final day in days)
          Expanded(
            child: Builder(
              builder: (context) {
                final isToday = DateUtils.isSameDay(day.date, today);
                final label = DateFormat.E(locale)
                    .format(day.date)
                    .replaceAll('.', '')
                    .substring(0, 1)
                    .toUpperCase();
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: isToday
                        ? colors.primary.withAlpha(28)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppUi.tileRadius),
                  ),
                  child: Column(
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: isToday
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: isToday
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _DayMarks(
                        day: day,
                        strengthColor: strengthColor,
                        runColor: runColor,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// One day's sport circles; a second sport overlaps the first.
class _DayMarks extends StatelessWidget {
  static const double _size = 22;
  static const double _overlap = 5;

  final WorkoutDayMark day;
  final Color strengthColor;
  final Color runColor;

  const _DayMarks({
    required this.day,
    required this.strengthColor,
    required this.runColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final marks = [
      if (day.strengthDone || day.strengthPlanned)
        _SportMark(
          done: day.strengthDone,
          icon: Icons.fitness_center,
          color: strengthColor,
          onColor: colors.onPrimary,
        ),
      if (day.runDone || day.runPlanned)
        _SportMark(
          done: day.runDone,
          icon: Icons.directions_run,
          color: runColor,
          onColor: colors.onTertiary,
        ),
    ];

    if (marks.isEmpty) {
      return SizedBox(
        height: _size,
        child: Center(
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: colors.onSurfaceVariant.withAlpha(70),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }
    if (marks.length == 1) {
      return SizedBox.square(dimension: _size, child: marks.single);
    }
    const offset = _size - _overlap;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: offset + _size,
        height: _size,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: _size,
              height: _size,
              child: marks[0],
            ),
            Positioned(
              left: offset,
              top: 0,
              width: _size,
              height: _size,
              child: marks[1],
            ),
          ],
        ),
      ),
    );
  }
}

class _SportMark extends StatelessWidget {
  final bool done;
  final IconData icon;
  final Color color;
  final Color onColor;

  const _SportMark({
    required this.done,
    required this.icon,
    required this.color,
    required this.onColor,
  });

  @override
  Widget build(BuildContext context) {
    if (done) {
      return DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: 12, color: onColor),
      );
    }
    return CustomPaint(
      painter: DashedRRectPainter(
        color: color.withAlpha(170),
        fill: color.withAlpha(20),
        radius: _DayMarks._size / 2,
      ),
      child: Icon(icon, size: 11, color: color.withAlpha(170)),
    );
  }
}

/// One activity in the "Today" agenda.
class WorkoutTodayItem {
  final Key? key;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool done;
  final String startTooltip;
  final VoidCallback onStart;
  final VoidCallback onOpen;

  const WorkoutTodayItem({
    this.key,
    required this.startTooltip,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onStart,
    required this.onOpen,
    this.done = false,
  });
}

/// Today's agenda: every planned session with its own start button, or a
/// rest/free-day message with quick start buttons.
class WorkoutTodayCard extends StatelessWidget {
  final List<WorkoutTodayItem> items;

  /// Shown when [items] is empty.
  final String emptyTitle;
  final String emptySubtitle;
  final IconData emptyIcon;
  final VoidCallback onQuickStrength;
  final VoidCallback onQuickRun;

  const WorkoutTodayCard({
    super.key,
    required this.items,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.emptyIcon,
    required this.onQuickStrength,
    required this.onQuickRun,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (items.isEmpty) {
      return AppSectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppIconBadge(
                  emptyIcon,
                  color: colors.secondary,
                  size: 44,
                  iconSize: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        emptyTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        emptySubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const Key('workout-home-quick-strength'),
                    onPressed: onQuickStrength,
                    icon: const Icon(Icons.fitness_center, size: 18),
                    label: Text(loc.workoutHomeQuickStrength),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    key: const Key('workout-home-quick-run'),
                    onPressed: onQuickRun,
                    icon: const Icon(Icons.directions_run, size: 18),
                    label: Text(loc.workoutHomeQuickRun),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return AppSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: AppDividedList(
        children: [for (final item in items) _TodayRow(item: item)],
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  final WorkoutTodayItem item;

  const _TodayRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return InkWell(
      onTap: item.onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            AppIconBadge(item.icon, color: item.color, size: 44, iconSize: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (item.done)
              AppPill(
                icon: Icons.check_rounded,
                color: item.color,
                label: loc.workoutHomeTodayDone,
              )
            else
              IconButton.filled(
                key: item.key,
                style: IconButton.styleFrom(
                  backgroundColor: item.color,
                  foregroundColor: colors.surface,
                ),
                tooltip: item.startTooltip,
                onPressed: item.onStart,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact entry to a training area (Musculação / Corrida).
class WorkoutAreaTile extends StatelessWidget {
  final Key? tileKey;
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  const WorkoutAreaTile({
    super.key,
    this.tileKey,
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AppSectionCard(
      key: tileKey,
      onTap: onTap,
      color: Color.alphaBlend(color.withAlpha(14), colors.surfaceContainerLow),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          AppIconBadge(icon, color: color, size: 40, iconSize: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the recent activity list (gym or cardio).
class WorkoutRecentItem {
  final IconData icon;
  final Color color;
  final String title;
  final DateTime date;
  final String? duration;
  final String value;
  final String? valueCaption;
  final VoidCallback onTap;

  const WorkoutRecentItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.date,
    required this.duration,
    required this.value,
    this.valueCaption,
    required this.onTap,
  });
}

class WorkoutRecentList extends StatelessWidget {
  final List<WorkoutRecentItem> items;

  const WorkoutRecentList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return AppSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: AppDividedList(
        children: [
          for (final item in items)
            AppListRow(
              leading: AppIconBadge(item.icon, color: item.color, size: 40),
              title: item.title,
              subtitle: [
                toBeginningOfSentenceCase(
                  DateFormat.MMMEd(locale).format(item.date),
                ),
                ?item.duration,
              ].join(' · '),
              value: item.value,
              valueCaption: item.valueCaption,
              onTap: item.onTap,
            ),
        ],
      ),
    );
  }
}

class _LegendMark extends StatelessWidget {
  final Color color;
  final String label;

  /// Hollow ring (planned) instead of a filled dot (done).
  final bool outlined;

  const _LegendMark({
    required this.color,
    required this.label,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: outlined ? null : color,
            shape: BoxShape.circle,
            border: outlined ? Border.all(color: color, width: 1.5) : null,
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
