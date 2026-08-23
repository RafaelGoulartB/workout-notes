import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';

/// Monday-to-Sunday strip for the current week. Each day is a small vertical
/// track filled proportionally to the distance run that day, so gaps and
/// long-run days are readable at a glance.
class RunWeekStrip extends StatelessWidget {
  final List<RunDayBucket> days;
  final DateTime today;
  final double trackHeight;

  const RunWeekStrip({
    super.key,
    required this.days,
    required this.today,
    this.trackHeight = 56,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final weekdayFormat = DateFormat.E(locale);
    final maxDistance = days.fold<double>(
      0,
      (value, day) => day.distanceMeters > value ? day.distanceMeters : value,
    );

    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _DayColumn(
              day: days[i],
              isToday: _isSameDay(days[i].date, today),
              isFuture: days[i].date.isAfter(today),
              fill: maxDistance <= 0
                  ? 0
                  : (days[i].distanceMeters / maxDistance).clamp(0.0, 1.0),
              label: weekdayFormat
                  .format(days[i].date)
                  .replaceAll('.', '')
                  .toUpperCase(),
              trackHeight: trackHeight,
              colors: colors,
              theme: theme,
            ),
          ),
        ],
      ],
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayColumn extends StatelessWidget {
  final RunDayBucket day;
  final bool isToday;
  final bool isFuture;
  final double fill;
  final String label;
  final double trackHeight;
  final ColorScheme colors;
  final ThemeData theme;

  const _DayColumn({
    required this.day,
    required this.isToday,
    required this.isFuture,
    required this.fill,
    required this.label,
    required this.trackHeight,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // A day with a run always shows a visible sliver, even when another day
    // of the week was much longer.
    final ratio = day.hasRun ? fill.clamp(0.18, 1.0) : 0.0;
    final barColor = isToday ? colors.primary : colors.primary.withValues(alpha: 0.7);

    return Tooltip(
      message: day.hasRun
          ? RunFormatters.distanceWithUnit(day.distanceMeters)
          : label,
      child: Column(
        children: [
          Container(
            height: trackHeight,
            decoration: BoxDecoration(
              color: isFuture
                  ? colors.surfaceContainerHighest.withValues(alpha: 0.3)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              widthFactor: 1,
              heightFactor: ratio,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
              color: isToday ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
