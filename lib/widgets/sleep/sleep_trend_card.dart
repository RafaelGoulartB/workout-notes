import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/sleep/sleep_ui.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Last 30 days of sleep per night against the goal, with the period average
/// and (when measured with enough confidence) estimated deep sleep.
class SleepTrendCard extends StatelessWidget {
  final List<SleepEntry> entries;
  final DateTime end;
  final int goalMinutes;

  /// Estimated deep sleep in minutes by entry id (only confident nights).
  final Map<String, int> deepMinutesByEntry;

  const SleepTrendCard({
    super.key,
    required this.entries,
    required this.end,
    required this.goalMinutes,
    this.deepMinutesByEntry = const {},
  });

  static const _days = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final last = dayOf(end);
    final start = addDays(last, -(_days - 1));
    final byDate = {for (final entry in entries) dateKey(entry.date): entry};
    final sleepSpots = <FlSpot>[];
    final deepSpots = <FlSpot>[];
    for (var index = 0; index < _days; index++) {
      final entry = byDate[dateKey(addDays(start, index))];
      if (entry == null) continue;
      sleepSpots.add(
        FlSpot(index.toDouble(), entry.effectiveSleepMinutes / 60),
      );
      final deep = deepMinutesByEntry[entry.id];
      if (deep != null) deepSpots.add(FlSpot(index.toDouble(), deep / 60));
    }

    if (sleepSpots.length < 2) {
      return AppSectionCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            loc.sleepNeedTwoEntries,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final goalHours = goalMinutes / 60;
    final average =
        sleepSpots.map((spot) => spot.y).reduce((a, b) => a + b) /
        sleepSpots.length;
    final onGoal = sleepSpots.where((spot) => spot.y >= goalHours).length;
    final maxY =
        (math.max(goalHours, sleepSpots.map((s) => s.y).reduce(math.max)) + 1)
            .ceilToDouble();

    return AppSectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.sleepAverageSleep,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      SleepUi.duration(loc, (average * 60).round()),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: AppUi.tabular,
                      ),
                    ),
                  ],
                ),
              ),
              AppPill(
                icon: Icons.flag_outlined,
                color: onGoal * 2 >= sleepSpots.length
                    ? colors.primary
                    : colors.tertiary,
                label: loc.sleepNightsOnGoal(onGoal, sleepSpots.length),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 170,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: _days - 1,
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 2,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: colors.outlineVariant.withAlpha(70),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: goalHours,
                      color: colors.onSurfaceVariant.withAlpha(150),
                      strokeWidth: 1.5,
                      dashArray: [5, 4],
                    ),
                  ],
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (_) => colors.inverseSurface,
                    getTooltipItems: (spots) => [
                      for (final spot in spots)
                        LineTooltipItem(
                          '${spot.barIndex == 0 ? '${DateFormat.MMMd(Intl.defaultLocale).format(start.add(Duration(days: spot.x.toInt())))}\n' : ''}'
                          '${SleepUi.duration(loc, (spot.y * 60).round())}',
                          TextStyle(
                            color: spot.bar.color ?? colors.onInverseSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 2,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max) return const SizedBox.shrink();
                        return Text(
                          '${value.toInt()}h',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        // Weekly ticks counted back from today, so the last
                        // label is always the current day and none overlap.
                        final fromEnd = (_days - 1) - value.toInt();
                        if (value != value.roundToDouble() ||
                            fromEnd % 7 != 0) {
                          return const SizedBox.shrink();
                        }
                        final date = start.add(Duration(days: value.toInt()));
                        return SideTitleWidget(
                          meta: meta,
                          fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                          child: Text(
                            DateFormat.Md(Intl.defaultLocale).format(date),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: sleepSpots,
                    isCurved: true,
                    curveSmoothness: 0.2,
                    preventCurveOverShooting: true,
                    color: colors.primary,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                        radius: 2.5,
                        color: spot.y >= goalHours
                            ? colors.primary
                            : colors.tertiary,
                        strokeWidth: 0,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.primary.withAlpha(60),
                          colors.primary.withAlpha(0),
                        ],
                      ),
                    ),
                  ),
                  if (deepSpots.isNotEmpty)
                    LineChartBarData(
                      spots: deepSpots,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: SleepUi.deep,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              AppLegendItem(color: colors.primary, label: loc.sleepMetricSleep),
              if (deepSpots.isNotEmpty)
                AppLegendItem(
                  color: SleepUi.deep,
                  label: loc.sleepStageDeepEstimated,
                ),
              AppLegendItem(
                color: colors.onSurfaceVariant,
                dashed: true,
                label:
                    '${loc.sleepGoalTarget} ${SleepUi.duration(loc, goalMinutes)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
