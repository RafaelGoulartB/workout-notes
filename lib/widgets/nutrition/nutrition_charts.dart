import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:workout_notes/utils/progress_helpers.dart';

/// A single bar of the nutrition bar charts.
class NutritionBarPoint {
  final String label;
  final double value;
  final String tooltip;

  const NutritionBarPoint({
    required this.label,
    required this.value,
    required this.tooltip,
  });
}

/// Horizontal-bar chart of daily/weekly calories with an optional
/// goal line, matching the workout module chart conventions
/// (dashed grid, gradient rods, inverse-surface tooltips).
class NutritionBarChart extends StatelessWidget {
  final List<NutritionBarPoint> points;
  final double? goalValue;
  final Color color;
  final String Function(double value) formatValue;
  final int maxLabels;

  const NutritionBarChart({
    super.key,
    required this.points,
    this.goalValue,
    required this.color,
    required this.formatValue,
    this.maxLabels = 12,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.isEmpty) {
      return const SizedBox(height: 130, child: Center(child: Text('—')));
    }
    final maxValue = points.fold<double>(
      0,
      (acc, p) => p.value > acc ? p.value : acc,
    );
    final goal = goalValue ?? 0;
    final chartMax = (maxValue > goal ? maxValue : goal) * 1.25;
    final labelStep = (points.length / maxLabels).ceil().clamp(1, 99);
    return SizedBox(
      height: 150,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceBetween,
          maxY: chartMax,
          minY: 0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 10,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              getTooltipColor: (_) => theme.colorScheme.inverseSurface,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final point = points[groupIndex];
                return BarTooltipItem(
                  '${point.tooltip}\n${formatValue(point.value)}',
                  TextStyle(
                    color: theme.colorScheme.onInverseSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                );
              },
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
                reservedSize: 34,
                getTitlesWidget: (value, meta) {
                  return Text(
                    formatValue(value),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: labelStep.toDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 ||
                      index >= points.length ||
                      index % labelStep != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      points[index].label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: niceInterval(chartMax / 4),
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withAlpha(70),
              strokeWidth: 1,
              dashArray: const [3, 4],
            ),
          ),
          extraLinesData: goalValue == null
              ? ExtraLinesData()
              : ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: goalValue!,
                      color: theme.colorScheme.error.withAlpha(180),
                      strokeWidth: 1.4,
                      dashArray: const [6, 4],
                    ),
                  ],
                ),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: points[i].value,
                    width: 9,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                    gradient: LinearGradient(
                      colors: [color.withAlpha(160), color],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: chartMax,
                      color: theme.colorScheme.surfaceContainerHighest
                          .withAlpha(60),
                    ),
                  ),
                ],
                showingTooltipIndicators: const [],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

/// A single weekly macro point (protein/carbs/fat in grams).
class WeeklyMacroPoint {
  final String label;
  final double protein;
  final double carbs;
  final double fat;

  const WeeklyMacroPoint({
    required this.label,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

/// Grouped bar chart of the average weekly macros (three rods per
/// week: protein, carbs, fat — all in grams, so one axis fits).
class WeeklyMacroBarChart extends StatelessWidget {
  final List<WeeklyMacroPoint> points;
  final Color proteinColor;
  final Color carbsColor;
  final Color fatColor;

  const WeeklyMacroBarChart({
    super.key,
    required this.points,
    required this.proteinColor,
    required this.carbsColor,
    required this.fatColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.isEmpty) {
      return const SizedBox(height: 150, child: Center(child: Text('—')));
    }
    final maxValue = points.fold<double>(
      0,
      (acc, p) => [
        p.protein,
        p.carbs,
        p.fat,
        acc,
      ].reduce((a, b) => a > b ? a : b),
    );
    final chartMax = maxValue * 1.25;
    final labelStep = (points.length / 12).ceil().clamp(1, 99);
    return SizedBox(
      height: 150,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceBetween,
          maxY: chartMax,
          minY: 0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 10,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              getTooltipColor: (_) => theme.colorScheme.inverseSurface,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final point = points[groupIndex];
                final label = switch (rodIndex) {
                  0 => 'P',
                  1 => 'C',
                  _ => 'G',
                };
                final value = switch (rodIndex) {
                  0 => point.protein,
                  1 => point.carbs,
                  _ => point.fat,
                };
                return BarTooltipItem(
                  '${point.label}\n$label ${_format(value)} g',
                  TextStyle(
                    color: theme.colorScheme.onInverseSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                );
              },
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
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toInt()}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: labelStep.toDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 ||
                      index >= points.length ||
                      index % labelStep != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      points[index].label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: niceInterval(chartMax / 4),
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withAlpha(70),
              strokeWidth: 1,
              dashArray: const [3, 4],
            ),
          ),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 3,
                barRods: [
                  BarChartRodData(
                    toY: points[i].protein,
                    width: 7,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                    color: proteinColor,
                  ),
                  BarChartRodData(
                    toY: points[i].carbs,
                    width: 7,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                    color: carbsColor,
                  ),
                  BarChartRodData(
                    toY: points[i].fat,
                    width: 7,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                    color: fatColor,
                  ),
                ],
                showingTooltipIndicators: const [],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}

/// A point of a nutrient trend line.
class NutrientTrendPoint {
  final String label;
  final double value;
  final String tooltip;

  const NutrientTrendPoint({
    required this.label,
    required this.value,
    required this.tooltip,
  });
}

/// One series of a multi-series nutrient trend chart.
class NutrientTrendSeries {
  final String label;
  final Color color;
  final List<NutrientTrendPoint> points;

  const NutrientTrendSeries({
    required this.label,
    required this.color,
    required this.points,
  });
}

/// Multi-series line chart of weekly nutrient trends (e.g. fiber and
/// sugars in grams, or sodium in milligrams).
class NutrientTrendChart extends StatelessWidget {
  final List<NutrientTrendSeries> series;
  final String Function(double value) formatValue;

  const NutrientTrendChart({
    super.key,
    required this.series,
    required this.formatValue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flat = [
      for (final s in series) ...s.points,
    ];
    if (flat.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text('—')));
    }
    final maxValue = flat.fold<double>(
      0,
      (acc, p) => p.value > acc ? p.value : acc,
    );
    final chartMax = maxValue * 1.2;
    final pointCount = series.fold<int>(
      0,
      (acc, s) => s.points.length > acc ? s.points.length : acc,
    );
    final labelStep = (pointCount / 12).ceil().clamp(1, 99);
    return SizedBox(
      height: 120,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: chartMax,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              tooltipRoundedRadius: 10,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              getTooltipColor: (_) => theme.colorScheme.inverseSurface,
              getTooltipItems: (spots) =>
                  spots.map((spot) {
                    final index = spot.x.toInt();
                    if (spot.barIndex < 0 ||
                        spot.barIndex >= series.length ||
                        index < 0 ||
                        index >= series[spot.barIndex].points.length) {
                      return null;
                    }
                    final point = series[spot.barIndex].points[index];
                    return LineTooltipItem(
                      '${point.tooltip}\n${formatValue(point.value)}',
                      TextStyle(
                        color: theme.colorScheme.onInverseSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    );
                  }).toList(),
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
                reservedSize: 38,
                getTitlesWidget: (value, meta) {
                  return Text(
                    formatValue(value),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: labelStep.toDouble(),
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  final any = series.any(
                    (s) =>
                        index >= 0 &&
                        index < s.points.length &&
                        index % labelStep == 0,
                  );
                  if (!any) return const SizedBox.shrink();
                  final label = series
                      .where((s) => index < s.points.length)
                      .map((s) => s.points[index].label)
                      .firstOrNull;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label ?? '',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: niceInterval(chartMax / 4),
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withAlpha(70),
              strokeWidth: 1,
              dashArray: const [3, 4],
            ),
          ),
          lineBarsData: [
            for (final s in series)
              LineChartBarData(
                spots: [
                  for (var i = 0; i < s.points.length; i++)
                    FlSpot(i.toDouble(), s.points[i].value),
                ],
                isCurved: true,
                curveSmoothness: 0.3,
                barWidth: 2.5,
                color: s.color,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      s.color.withAlpha(70),
                      s.color.withAlpha(10),
                    ],
                  ),
                ),
              ),
          ],
        ),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}
