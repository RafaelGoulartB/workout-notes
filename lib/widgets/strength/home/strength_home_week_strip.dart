import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/utils/strength_week_analytics.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_format.dart';

/// Monday-to-Sunday strip of the current week. A trained day is a track
/// filled in proportion to its working sets and tinted with the muscle group
/// trained the most; a planned strength day still ahead is a dashed ghost and
/// one that passed untrained is marked as missed.
class StrengthWeekStrip extends StatelessWidget {
  final List<StrengthDayBucket> days;
  final DateTime today;

  /// ISO weekdays (1 = Monday) with a planned strength session.
  final List<int> plannedWeekdays;
  final Map<String, StrengthCategoryInfo> categories;
  final double trackHeight;

  const StrengthWeekStrip({
    super.key,
    required this.days,
    required this.today,
    this.plannedWeekdays = const [],
    this.categories = const {},
    this.trackHeight = 56,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final weekdayFormat = DateFormat.E(
      Localizations.localeOf(context).toString(),
    );
    final todayDate = DateTime(today.year, today.month, today.day);

    var maxSets = 0;
    for (final day in days) {
      if (day.workingSets > maxSets) maxSets = day.workingSets;
    }

    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _DayColumn(
              day: days[i],
              planned: plannedWeekdays.contains(days[i].date.weekday),
              isToday: days[i].date == todayDate,
              isFuture: days[i].date.isAfter(todayDate),
              maxSets: maxSets,
              tint: days[i].categoryId == null
                  ? colors.primary
                  : Color(
                      categories[days[i].categoryId]?.color ??
                          colors.primary.toARGB32(),
                    ),
              label: weekdayFormat
                  .format(days[i].date)
                  .replaceAll('.', '')
                  .toUpperCase(),
              trackHeight: trackHeight,
              loc: loc,
              theme: theme,
            ),
          ),
        ],
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  final StrengthDayBucket day;
  final bool planned;
  final bool isToday;
  final bool isFuture;
  final int maxSets;
  final Color tint;
  final String label;
  final double trackHeight;
  final AppLocalizations loc;
  final ThemeData theme;

  const _DayColumn({
    required this.day,
    required this.planned,
    required this.isToday,
    required this.isFuture,
    required this.maxSets,
    required this.tint,
    required this.label,
    required this.trackHeight,
    required this.loc,
    required this.theme,
  });

  double get _ratio =>
      maxSets <= 0 ? 0.5 : (day.workingSets / maxSets).clamp(0.22, 1.0);

  @override
  Widget build(BuildContext context) {
    final colors = theme.colorScheme;
    final ghost = !day.hasSession && planned;
    final missed = ghost && !isFuture && !isToday;
    final ghostColor = missed ? colors.error : colors.primary;

    final tooltip = day.hasSession
        ? loc.strengthHomeDayTrained(
            loc.strengthHomeSetsCount(day.workingSets),
            StrengthHomeFormat.volume(day.volumeKg),
          )
        : ghost
        ? (missed ? loc.strengthHomeDayMissed : loc.strengthHomeDayPlanned)
        : label;

    return Tooltip(
      message: tooltip,
      child: Column(
        children: [
          SizedBox(
            height: 14,
            child: day.hasSession
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${day.workingSets}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  )
                : null,
          ),
          Container(
            height: trackHeight,
            decoration: BoxDecoration(
              color: isFuture
                  ? colors.surfaceContainerHighest.withValues(alpha: 0.3)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.bottomCenter,
            child: day.hasSession
                ? FractionallySizedBox(
                    widthFactor: 1,
                    heightFactor: _ratio,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isToday ? tint : tint.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  )
                : ghost
                ? SizedBox.expand(
                    child: CustomPaint(
                      painter: _DashedRRectPainter(
                        color: ghostColor.withValues(alpha: 0.75),
                        fill: ghostColor.withValues(alpha: 0.08),
                      ),
                      child: Center(
                        child: Icon(
                          missed
                              ? Icons.close_rounded
                              : Icons.fitness_center_rounded,
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
              color: isToday ? colors.primary : colors.onSurfaceVariant,
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
