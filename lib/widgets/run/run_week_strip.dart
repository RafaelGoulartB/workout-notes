import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/run_today_service.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

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

    return Tooltip(
      message: _tooltip,
      child: Column(
        children: [
          SizedBox(
            height: 14,
            child: topLabel == null
                ? null
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      topLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontWeight: day.hasRun
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: day.hasRun
                            ? colors.onSurface
                            : ghostColor.withValues(alpha: 0.9),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
          ),
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: isFuture
                  ? colors.surfaceContainerHighest.withValues(alpha: 0.3)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.bottomCenter,
            child: day.hasRun
                ? FractionallySizedBox(
                    widthFactor: 1,
                    heightFactor: _ratio(day.distanceMeters),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  )
                : ghost
                ? FractionallySizedBox(
                    widthFactor: 1,
                    heightFactor: _ratio(p.plannedMeters),
                    child: CustomPaint(
                      painter: _DashedRRectPainter(
                        color: ghostColor.withValues(alpha: 0.75),
                        fill: ghostColor.withValues(alpha: 0.08),
                      ),
                      child: missed || skipped
                          ? Center(
                              child: Icon(
                                missed
                                    ? Icons.close_rounded
                                    : Icons.remove_rounded,
                                size: 14,
                                color: ghostColor,
                              ),
                            )
                          : Center(
                              child: Icon(
                                RunPlanUi.kindIcon(p.kind),
                                size: 14,
                                color: ghostColor.withValues(alpha: 0.85),
                              ),
                            ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
              color: isToday ? colors.primary : muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashed rounded rectangle outline with a faint fill.
class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final Color fill;

  const _DashedRRectPainter({required this.color, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.75),
      const Radius.circular(6),
    );
    canvas.drawRRect(rrect, Paint()..color = fill);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.fill != fill;
}
