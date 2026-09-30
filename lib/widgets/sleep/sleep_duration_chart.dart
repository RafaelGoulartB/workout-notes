import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/sleep/sleep_schedule_chart.dart';
import 'package:workout_notes/widgets/sleep/sleep_ui.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Weekly sleep per night: recorded duration next to actual or estimated
/// sleep, against a dashed goal line.
class SleepDurationChart extends StatelessWidget {
  final List<SleepEntry> entries;
  final List<DateTime> days;
  final int goalMinutes;

  const SleepDurationChart({
    super.key,
    required this.entries,
    required this.days,
    required this.goalMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final byDate = {for (final entry in entries) dateKey(entry.date): entry};
    final goalHours = goalMinutes / 60;
    final groups = <BarChartGroupData>[];
    var maxHours = goalHours;
    for (var index = 0; index < days.length; index++) {
      final entry = byDate[dateKey(days[index])];
      final recorded = entry == null ? null : entry.sleepMinutes / 60;
      final actualMinutes =
          entry?.actualSleepMinutes ?? entry?.estimatedSleepMinutes;
      final actual = actualMinutes == null ? null : actualMinutes / 60;
      maxHours = math.max(maxHours, math.max(recorded ?? 0, actual ?? 0));
      groups.add(
        BarChartGroupData(
          x: index,
          barsSpace: 3,
          barRods: [
            if (recorded != null) _rod(recorded, colors.primary),
            if (actual != null) _rod(actual, colors.tertiary),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: loc.sleepDurationChartSemantics,
          child: SizedBox(
            height: 190,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: (maxHours + 1).ceilToDouble(),
                alignment: BarChartAlignment.spaceAround,
                barGroups: groups,
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
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (_) => colors.inverseSurface,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final index = group.x;
                      if (index < 0 || index >= days.length) return null;
                      final label = rodIndex == 0
                          ? loc.sleepChartRecorded
                          : loc.sleepChartActualOrEstimated;
                      return BarTooltipItem(
                        '${DateFormat.MMMEd(Intl.defaultLocale).format(days[index])}\n'
                        '$label: ${SleepUi.duration(loc, (rod.toY * 60).round())}',
                        TextStyle(
                          color: colors.onInverseSurface,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.left,
                      );
                    },
                  ),
                ),
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
                            fontFeatures: AppUi.tabular,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (value, meta) =>
                          SleepDayLabel(meta: meta, days: days, value: value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            AppLegendItem(color: colors.primary, label: loc.sleepChartRecorded),
            AppLegendItem(
              color: colors.tertiary,
              label: loc.sleepChartActualOrEstimated,
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
    );
  }

  static BarChartRodData _rod(double value, Color color) => BarChartRodData(
    toY: value,
    width: 9,
    color: color,
    borderRadius: BorderRadius.circular(4),
  );
}
