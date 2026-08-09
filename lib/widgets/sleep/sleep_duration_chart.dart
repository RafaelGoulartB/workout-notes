import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';

class SleepDurationChart extends StatelessWidget {
  final List<SleepEntry> entries;
  final List<DateTime> days;

  const SleepDurationChart({
    super.key,
    required this.entries,
    required this.days,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final byDate = {
      for (final entry in entries) _dateString(entry.date): entry,
    };
    final groups = <BarChartGroupData>[];
    var maxHours = 0.0;
    for (var index = 0; index < days.length; index++) {
      final entry = byDate[_dateString(days[index])];
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

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.bar_chart_rounded, color: colors.primary, size: 21),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.sleepDurationChart,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        loc.sleepDurationChartSubtitle,
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
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _LegendItem(
                  color: colors.primary,
                  label: loc.sleepChartRecorded,
                ),
                _LegendItem(
                  color: colors.tertiary,
                  label: loc.sleepChartActualOrEstimated,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              label: loc.sleepDurationChartSemantics,
              child: SizedBox(
                height: 190,
                child: BarChart(
                  BarChartData(
                    minY: 0,
                    maxY: math.max(8, maxHours.ceilToDouble() + 1),
                    alignment: BarChartAlignment.spaceAround,
                    barGroups: groups,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => colors.inverseSurface,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          return BarTooltipItem(
                            _formatDuration(rod.toY),
                            TextStyle(
                              color: colors.onInverseSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        },
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 2,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: colors.outlineVariant.withAlpha(110),
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
                          reservedSize: 31,
                          interval: 2,
                          getTitlesWidget: (value, meta) => Text(
                            '${value.toInt()}h',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= days.length) {
                              return const SizedBox();
                            }
                            return SideTitleWidget(
                              meta: meta,
                              child: Text(
                                DateFormat(
                                  'E',
                                  Intl.defaultLocale,
                                ).format(days[index]).substring(0, 1),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static BarChartRodData _rod(double value, Color color) => BarChartRodData(
    toY: value,
    width: 9,
    color: color,
    borderRadius: BorderRadius.circular(4),
  );

  static String _formatDuration(double hours) {
    final minutes = (hours * 60).round();
    return '${minutes ~/ 60}h ${minutes % 60}min';
  }

  static String _dateString(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
