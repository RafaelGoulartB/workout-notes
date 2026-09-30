import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/run_today_service.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Monday-to-Sunday strip for the current week. Each day is a small vertical
/// track filled proportionally to the distance run that day, so gaps and
/// long-run days are readable at a glance.
///
/// With a plan, [planned] adds the sessions the plan expects: a dashed "ghost"
/// for what is still ahead, a filled bar once it is done and a tinted marker
/// for a planned day that passed without a run.
class RunWeekStrip extends StatelessWidget {
  final List<RunDayBucket> days;
  final DateTime today;
  final List<RunPlannedDay> planned;

  const RunWeekStrip({
    super.key,
    required this.days,
    required this.today,
    this.planned = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final weekdayFormat = DateFormat.E(locale);

    RunPlannedDay? plannedOn(DateTime date) {
      for (final p in planned) {
        if (_isSameDay(p.date, date)) return p;
      }
      return null;
    }

    var maxDistance = 0.0;
    for (final day in days) {
      if (day.distanceMeters > maxDistance) maxDistance = day.distanceMeters;
    }
    for (final p in planned) {
      if (p.plannedMeters > maxDistance) maxDistance = p.plannedMeters;
    }

    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _DayColumn(
              day: days[i],
              plan: plannedOn(days[i].date),
              isToday: _isSameDay(days[i].date, today),
              isFuture: days[i].date.isAfter(today),
              maxDistance: maxDistance,
              label: weekdayFormat
                  .format(days[i].date)
                  .replaceAll('.', '')
                  .toUpperCase(),
              loc: loc,
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
  final RunPlannedDay? plan;
  final bool isToday;
  final bool isFuture;
  final double maxDistance;
  final String label;
  final AppLocalizations loc;
  final ColorScheme colors;
  final ThemeData theme;

  const _DayColumn({
    required this.day,
    required this.plan,
    required this.isToday,
    required this.isFuture,
    required this.maxDistance,
    required this.label,
    required this.loc,
    required this.colors,
    required this.theme,
  });

  double _ratio(double meters) =>
      maxDistance <= 0 ? 0 : (meters / maxDistance).clamp(0.18, 1.0);

  String get _tooltip {
    final p = plan;
    if (day.hasRun) return RunFormatters.distanceWithUnit(day.distanceMeters);
    if (p == null) return label;
    return switch (p.state) {
      RunPlannedDayState.missed => loc.runHomeWeekDayMissed(p.name),
      RunPlannedDayState.skipped => loc.runHomeWeekDaySkipped(p.name),
      _ => loc.runHomeWeekDayPlanned(
        p.name,
        RunPlanUi.distanceLabel(p.plannedMeters),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final muted = colors.onSurfaceVariant;
    final p = plan;
    // A planned session is a ghost until it is run; a run on that day (even
    // an unplanned one) fills the track.
    final ghost =
        !day.hasRun &&
        p != null &&
        (p.state == RunPlannedDayState.pending ||
            p.state == RunPlannedDayState.missed ||
            p.state == RunPlannedDayState.skipped);
    final missed = ghost && p.state == RunPlannedDayState.missed;
    final skipped = ghost && p.state == RunPlannedDayState.skipped;
    final ghostColor = missed
        ? colors.error
        : skipped
        ? muted.withValues(alpha: 0.6)
        : colors.primary;
    final barColor = isToday
        ? colors.primary
        : colors.primary.withValues(alpha: 0.7);

    final String? topLabel = day.hasRun
        ? RunFormatters.distanceKmShort(day.distanceMeters)
        : ghost && p.plannedMeters > 0
        ? RunFormatters.distanceKmShort(p.plannedMeters)
        : null;

    return AppWeekStripDay(
      tooltip: _tooltip,
      label: label,
      isToday: isToday,
      isFuture: isFuture,
      topLabel: topLabel,
      topLabelWeight: day.hasRun ? FontWeight.w800 : FontWeight.w600,
      topLabelColor: day.hasRun
          ? colors.onSurface
          : ghostColor.withValues(alpha: 0.9),
      barRatio: day.hasRun ? _ratio(day.distanceMeters) : null,
      barColor: barColor,
      ghostColor: ghost ? ghostColor : null,
      ghostRatio: ghost ? _ratio(p.plannedMeters) : 1,
      ghostIcon: !ghost
          ? null
          : Icon(
              missed
                  ? Icons.close_rounded
                  : skipped
                  ? Icons.remove_rounded
                  : RunPlanUi.kindIcon(p.kind),
              size: 14,
              color: missed || skipped
                  ? ghostColor
                  : ghostColor.withValues(alpha: 0.85),
            ),
    );
  }
}
