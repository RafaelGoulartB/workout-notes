import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/strength_week_analytics.dart';
import 'package:workout_notes/widgets/run/run_progress_charts.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Bottom label of a bucket: `d/M` for weeks, the month for month buckets.
String strengthBucketLabel(StrengthTrendBucket bucket, String locale) =>
    bucket.isMonthly
    ? DateFormat.MMM(locale).format(bucket.start)
    : DateFormat.Md(locale).format(bucket.start);

/// Tooltip heading of a bucket.
String strengthBucketHeading(
  AppLocalizations loc,
  StrengthTrendBucket bucket,
  String locale,
) => bucket.isMonthly
    ? DateFormat.yMMM(locale).format(bucket.start)
    : loc.runStatsChartTooltipWeek(
        DateFormat.MMMd(locale).format(bucket.start),
      );

/// Round gridline step giving roughly four lines for any magnitude.
double strengthNiceInterval(double maxY, {double minStep = 0}) {
  if (maxY <= 0) return 1;
  final raw = maxY / 4;
  final magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  double step = magnitude;
  for (final factor in const [1, 2, 5, 10]) {
    step = magnitude * factor;
    if (step >= raw) break;
  }
  return math.max(step, minStep);
}

/// Bars per weekly (or monthly) bucket in the same style as the running
/// charts: the last bar (the period in progress) is highlighted, a dashed
/// line marks the [average] whose legend is [averageLabel], and a touch shows
/// the [tooltipLines] of the bucket. Buckets without a value draw no bar.
class StrengthBucketBarChart extends StatelessWidget {
  final List<StrengthTrendBucket> buckets;
  final String emptyLabel;
  final String unit;

  /// Height of a bar in chart units (tonnes, workouts, minutes...).
  final double Function(StrengthTrendBucket bucket) valueOf;
  final List<String> Function(StrengthTrendBucket bucket) tooltipLines;
  final double? average;
  final String? averageLabel;

  /// Smallest gridline step (1 for whole workouts).
  final double minStep;

  const StrengthBucketBarChart({
    super.key,
    required this.buckets,
    required this.emptyLabel,
    required this.unit,
    required this.valueOf,
    required this.tooltipLines,
    this.average,
    this.averageLabel,
    this.minStep = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (!buckets.any((b) => valueOf(b) > 0)) {
      return RunChartEmpty(label: emptyLabel);
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    final maxValue = buckets.map(valueOf).fold<double>(0, math.max);
    final maxY = math.max(maxValue * 1.2, minStep * 2);
    final interval = strengthNiceInterval(maxY, minStep: minStep);
    final avg = average ?? 0;
    final showAverage = avg > 0 && avg < maxY;
    final averageColor = colors.tertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RunChartUnit(unit),
        SizedBox(
          height: RunChartStyle.height,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              minY: 0,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => colors.surfaceContainerHighest,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    if (groupIndex < 0 || groupIndex >= buckets.length) {
                      return null;
                    }
                    final b = buckets[groupIndex];
                    return BarTooltipItem(
                      [
                        strengthBucketHeading(loc, b, locale),
                        ...tooltipLines(b),
                      ].join('\n'),
                      RunChartStyle.tooltip(theme),
                    );
                  },
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  if (showAverage)
                    HorizontalLine(
                      y: avg,
                      color: averageColor.withValues(alpha: 0.8),
                      strokeWidth: 1.4,
                      dashArray: const [5, 4],
                    ),
                ],
              ),
              titlesData: FlTitlesData(
                topTitles: RunChartStyle.noSideTitles.topTitles,
                rightTitles: RunChartStyle.noSideTitles.rightTitles,
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: interval,
                    getTitlesWidget: (value, meta) {
                      if (value <= 0 || value >= maxY) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        child: Text(
                          RunChartStyle.axisNumber(value),
                          style: RunChartStyle.axis(theme),
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (!RunChartStyle.showBucketTick(i, buckets.length)) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          strengthBucketLabel(buckets[i], locale),
                          style: RunChartStyle.axis(theme),
                        ),
                      );
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => RunChartStyle.gridLine(colors),
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                for (var i = 0; i < buckets.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: valueOf(buckets[i]),
                        width: RunChartStyle.barWidth(buckets.length),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                        ),
                        color: i == buckets.length - 1
                            ? colors.primary
                            : colors.primary.withValues(alpha: 0.5),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxY,
                          color: RunChartStyle.track(colors),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (showAverage && averageLabel != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: RunLegendItem(
              color: averageColor,
              label: averageLabel!,
              dashed: true,
            ),
          ),
        ],
      ],
    );
  }
}
