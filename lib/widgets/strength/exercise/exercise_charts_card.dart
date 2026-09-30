import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_insights_format.dart';
import 'package:workout_notes/widgets/run/insights/run_insight_card.dart';
import 'package:workout_notes/widgets/strength/exercise/exercise_history_list.dart';
import 'package:workout_notes/widgets/strength/insights/strength_charts.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// What the chart plots for each workout.
enum ExerciseChartMetric { e1rm, weight, volume, reps }

extension on ExerciseChartMetric {
  double? valueOf(ExerciseSession s) => switch (this) {
    ExerciseChartMetric.e1rm => s.e1rm,
    ExerciseChartMetric.weight => s.maxWeight > 0 ? s.maxWeight : null,
    ExerciseChartMetric.volume => s.volume > 0 ? s.volume : null,
    ExerciseChartMetric.reps => s.totalReps > 0 ? s.totalReps.toDouble() : null,
  };

  bool get isReps => this == ExerciseChartMetric.reps;
}

/// Metric selector plus a trend chart of the exercise over its workouts,
/// styled like the running charts (dd/MM axis, tooltips, trend line).
class ExerciseChartsCard extends StatefulWidget {
  final List<ExerciseSession> sessions;

  const ExerciseChartsCard({super.key, required this.sessions});

  @override
  State<ExerciseChartsCard> createState() => _ExerciseChartsCardState();
}

class _ExerciseChartsCardState extends State<ExerciseChartsCard> {
  ExerciseChartMetric? _metric;

  List<ExerciseChartMetric> get _available => [
    for (final m in ExerciseChartMetric.values)
      if (m == ExerciseChartMetric.reps ||
          widget.sessions.any((s) => m.valueOf(s) != null))
        m,
  ];

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final available = _available;
    final metric = available.contains(_metric) ? _metric! : available.first;

    String label(ExerciseChartMetric m) => switch (m) {
      ExerciseChartMetric.e1rm => loc.exerciseDetailMetricE1rm,
      ExerciseChartMetric.weight => loc.exerciseDetailMetricWeight,
      ExerciseChartMetric.volume => loc.exerciseDetailMetricVolume,
      ExerciseChartMetric.reps => loc.exerciseDetailMetricReps,
    };
    String format(ExerciseChartMetric m, double v) => switch (m) {
      ExerciseChartMetric.e1rm ||
      ExerciseChartMetric.weight => '${StrengthFormat.weight(v)} kg',
      ExerciseChartMetric.volume => StrengthFormat.volumeWithUnit(v),
      ExerciseChartMetric.reps => RunFormatters.decimal(v, 0),
    };

    final points = <StrengthTrendPoint>[
      for (final s in widget.sessions)
        if (metric.valueOf(s) != null)
          StrengthTrendPoint(
            date: s.date,
            value: metric.valueOf(s)!,
            tooltip: [
              DateFormat.yMMMd(locale).format(s.date),
              format(metric, metric.valueOf(s)!),
              ExerciseSession.setLabel(loc, s.bestSetWeight, s.bestSetReps),
              loc.exerciseDetailSessionSets(s.sets.length),
            ].join('\n'),
          ),
    ];

    final values = [for (final p in points) p.value];
    final best = values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
    final info = switch (metric) {
      ExerciseChartMetric.e1rm => loc.exerciseDetailChartInfoE1rm,
      ExerciseChartMetric.weight => loc.exerciseDetailChartInfoWeight,
      ExerciseChartMetric.volume => loc.exerciseDetailChartInfoVolume,
      ExerciseChartMetric.reps => loc.exerciseDetailChartInfoReps,
    };

    return RunInsightCard(
      icon: Icons.show_chart_rounded,
      title: label(metric),
      subtitle: loc.exerciseDetailWorkoutCount(points.length),
      info: info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (available.length > 1) ...[
            AppSegmentedTabs<ExerciseChartMetric>(
              values: available,
              selected: metric,
              labelOf: label,
              onChanged: (m) => setState(() => _metric = m),
            ),
            const SizedBox(height: 14),
          ],
          StrengthTrendChart(
            points: points,
            unit: metric.isReps ? loc.exerciseDetailMetricReps : 'kg',
            emptyLabel: loc.exerciseDetailNoChartData,
            showTrend: true,
            zeroBased: metric.isReps || metric == ExerciseChartMetric.volume,
            pointsLabel: loc.exerciseDetailChartPoints,
            trendLabel: loc.exerciseDetailChartTrend,
          ),
          if (best != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                AppPill(
                  label: loc.exerciseDetailChartBest(format(metric, best)),
                  icon: Icons.emoji_events_rounded,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                AppPill(
                  label: loc.exerciseDetailChartLatest(
                    format(metric, values.last),
                  ),
                  icon: Icons.flag_outlined,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
