import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

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
/// dot per activity (hollow when only planned) and active time + streak.
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

    return RunHeroCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
              Container(width: 1, height: 52, color: RunUi.divider(colors)),
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
          const SizedBox(height: 12),
          _WeekDots(
            days: days,
            today: today,
            strengthColor: strengthColor,
            runColor: runColor,
          ),
          const SizedBox(height: 10),
          // Legend on the left, active time and streak on the right.
          Row(
            children: [
              _LegendMark(
                color: colors.onSurfaceVariant,
                label: loc.workoutHomeLegendDone,
              ),
              const SizedBox(width: 10),
              _LegendMark(
                color: colors.onSurfaceVariant.withAlpha(90),
                label: loc.workoutHomeLegendPlanned,
              ),
              const Spacer(),
              Icon(
                Icons.timer_outlined,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 3),
              Text(
                RunFormatters.durationHoursMinutes(activeSeconds),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: RunUi.tabular,
                ),
              ),
              if (streakWeeks > 0) ...[
                const SizedBox(width: 10),
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 14,
                  color: Colors.orange,
                ),
                const SizedBox(width: 2),
                Text(
                  '$streakWeeks ${loc.workoutHomeWeeksShort}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.orange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RunUi.tileRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: CustomPaint(
                painter: _RingPainter(
                  progress: progress.clamp(0.0, 1.0),
                  color: color,
                  track: color.withAlpha(40),
                ),
                child: Center(child: Icon(icon, color: color, size: 20)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        fontFeatures: RunUi.tabular,
                      ),
                    ),
                  ),
                  Text.rich(
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
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
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

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;

  const _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

/// Monday–Sunday, one column per day with a sport icon per activity: full
/// colour when done, faint when planned, today highlighted.
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

    // Sport icon per activity: full colour when done, faint when only
    // planned, nothing otherwise.
    Widget mark(bool done, bool planned, IconData icon, Color color) {
      if (!done && !planned) return const SizedBox(height: 14);
      return Icon(icon, size: 14, color: done ? color : color.withAlpha(90));
    }

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
                return Column(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isToday
                            ? colors.primary.withAlpha(45)
                            : Colors.transparent,
                      ),
                      child: Text(
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
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        mark(
                          day.strengthDone,
                          day.strengthPlanned,
                          Icons.fitness_center,
                          strengthColor,
                        ),
                        mark(
                          day.runDone,
                          day.runPlanned,
                          Icons.directions_run,
                          runColor,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
      ],
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
      return RunSectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RunIconBadge(
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

    return RunSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: RunDividedList(
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
            RunIconBadge(item.icon, color: item.color, size: 44, iconSize: 22),
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
              RunPill(
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
  final String line1;
  final String? line2;
  final VoidCallback onTap;

  const WorkoutAreaTile({
    super.key,
    this.tileKey,
    required this.icon,
    required this.color,
    required this.title,
    required this.line1,
    this.line2,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return RunSectionCard(
      key: tileKey,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RunIconBadge(icon, color: color),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            line1,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (line2 != null)
            Text(
              line2!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
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
    return RunSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: RunDividedList(
        children: [
          for (final item in items)
            RunListRow(
              leading: RunIconBadge(item.icon, color: item.color, size: 40),
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

  const _LegendMark({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
