import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';

/// Weekly distance bars for the run stats dashboard. The last bucket is the
/// week in progress and is highlighted; [averageMeters] draws a reference
/// line so the current volume can be read against the period average.
class RunWeeklyDistanceChart extends StatelessWidget {
  final List<RunWeekBucket> buckets;
  final String emptyLabel;
  final double? averageMeters;

  const RunWeeklyDistanceChart({
    super.key,
    required this.buckets,
    required this.emptyLabel,
    this.averageMeters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = buckets.any((b) => b.distanceMeters > 0);
    if (!hasData) {
      return _EmptyChart(label: emptyLabel);
    }

    final maxKm = buckets
        .map((b) => b.distanceMeters / 1000.0)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final maxY = (maxKm * 1.2).clamp(1.0, double.infinity);
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    final averageKm = (averageMeters ?? 0) / 1000.0;

    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          minY: 0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.surfaceContainerHighest,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                if (groupIndex < 0 || groupIndex >= buckets.length) {
                  return null;
                }
                final b = buckets[groupIndex];
                final label = DateFormat.Md().format(b.weekStart);
                return BarTooltipItem(
                  '$label\n${RunFormatters.distanceWithUnit(b.distanceMeters)}',
                  TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (averageKm > 0 && averageKm < maxY)
                HorizontalLine(
                  y: averageKm,
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.7),
                  strokeWidth: 1.4,
                  dashArray: const [5, 4],
                ),
            ],
          ),
          titlesData: FlTitlesData(
            show: true,
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
                interval: _niceInterval(maxY),
                getTitlesWidget: (value, meta) {
                  if (value <= 0 || value >= maxY) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    child: Text(
                      value >= 10
                          ? value.toStringAsFixed(0)
                          : value.toStringAsFixed(1),
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
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
                  if (!_showBucketTick(i, buckets.length)) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                    child: Text(
                      DateFormat.Md().format(buckets[i].weekStart),
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _niceInterval(maxY),
            getDrawingHorizontalLine: (value) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < buckets.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: buckets[i].distanceMeters / 1000.0,
                    width: _barWidth(buckets.length),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(5),
                    ),
                    color: i == buckets.length - 1
                        ? primary
                        : primary.withValues(alpha: 0.5),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: maxY,
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Pace-over-time line (faster pace plotted higher).
class RunPaceTrendChart extends StatelessWidget {
  final List<RunPacePoint> points;
  final String emptyLabel;

  const RunPaceTrendChart({
    super.key,
    required this.points,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.length < 2) {
      return _EmptyChart(label: emptyLabel);
    }

    var minPace = points.first.paceSecPerKm;
    var maxPace = points.first.paceSecPerKm;
    for (final p in points) {
      if (p.paceSecPerKm < minPace) minPace = p.paceSecPerKm;
      if (p.paceSecPerKm > maxPace) maxPace = p.paceSecPerKm;
    }
    final pad = ((maxPace - minPace) * 0.15).clamp(10.0, 60.0);
    final chartMin = (minPace - pad).clamp(30.0, maxPace);
    final chartMax = maxPace + pad;
    final range = (chartMax - chartMin).abs();
    // Keep the pace labels on round steps so they never overlap.
    final paceInterval = _nicePaceInterval(range);
    final edgeGuard = range * 0.08;

    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), -points[i].paceSecPerKm),
    ];

    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;

    return SizedBox(
      height: 190,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: -chartMax,
          maxY: -chartMin,
          clipData: const FlClipData.all(),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.surfaceContainerHighest,
              getTooltipItems: (touched) {
                return touched.map((t) {
                  final i = t.x.round();
                  if (i < 0 || i >= points.length) return null;
                  final p = points[i];
                  final date = DateFormat.MMMd().format(p.date);
                  return LineTooltipItem(
                    '$date\n${RunFormatters.paceWithUnit(p.paceSecPerKm)}'
                    '\n${RunFormatters.distanceWithUnit(p.distanceMeters)}',
                    TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: paceInterval,
            getDrawingHorizontalLine: (value) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
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
                reservedSize: 42,
                interval: paceInterval,
                getTitlesWidget: (value, meta) {
                  final pace = -value;
                  if (pace < chartMin + edgeGuard ||
                      pace > chartMax - edgeGuard) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    child: Text(
                      RunFormatters.pace(pace),
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
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
                  final i = value.round();
                  if (!_showBucketTick(i, points.length, maxTicks: 5)) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                    child: Text(
                      DateFormat.Md().format(points[i].date),
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: primary,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: points.length <= 16,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: 3.5,
                  color: primary,
                  strokeWidth: 1.5,
                  strokeColor: theme.colorScheme.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    primary.withValues(alpha: 0.22),
                    primary.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Weekly run-count bars.
class RunWeeklyFrequencyChart extends StatelessWidget {
  final List<RunWeekBucket> buckets;
  final String emptyLabel;

  const RunWeeklyFrequencyChart({
    super.key,
    required this.buckets,
    required this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = buckets.any((b) => b.runCount > 0);
    if (!hasData) {
      return _EmptyChart(label: emptyLabel);
    }

    final maxCount =
        buckets.map((b) => b.runCount).fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = (maxCount + 1).toDouble().clamp(3.0, double.infinity);
    final secondary = theme.colorScheme.secondary;
    final muted = theme.colorScheme.onSurfaceVariant;
    final countInterval = maxY > 8 ? 2.0 : 1.0;

    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          minY: 0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.surfaceContainerHighest,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                if (groupIndex < 0 || groupIndex >= buckets.length) {
                  return null;
                }
                final b = buckets[groupIndex];
                final label = DateFormat.Md().format(b.weekStart);
                return BarTooltipItem(
                  '$label\n${b.runCount}',
                  TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: countInterval,
                getTitlesWidget: (value, meta) {
                  if (value <= 0 || value != value.roundToDouble()) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    child: Text(
                      value.toInt().toString(),
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
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
                  if (!_showBucketTick(i, buckets.length)) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                    child: Text(
                      DateFormat.Md().format(buckets[i].weekStart),
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: countInterval,
            getDrawingHorizontalLine: (value) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < buckets.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: buckets[i].runCount.toDouble(),
                    width: _barWidth(buckets.length),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(5),
                    ),
                    color: i == buckets.length - 1
                        ? secondary
                        : secondary.withValues(alpha: 0.5),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: maxY,
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  final String label;

  const _EmptyChart({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 160,
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

double _barWidth(int count) {
  if (count > 26) return 5;
  if (count > 20) return 6;
  if (count > 12) return 9;
  return 14;
}

/// Ticks are spaced counting back from the newest bucket, so the most recent
/// label is always shown and never collides with its neighbour.
bool _showBucketTick(int index, int length, {int maxTicks = 6}) {
  if (index < 0 || index >= length) return false;
  final step = (length / maxTicks).ceil().clamp(1, length);
  return (length - 1 - index) % step == 0;
}

double _niceInterval(double maxY) {
  if (maxY <= 2) return 0.5;
  if (maxY <= 5) return 1;
  if (maxY <= 10) return 2;
  if (maxY <= 25) return 5;
  if (maxY <= 60) return 10;
  return 20;
}

/// Pace steps in seconds, chosen so at most ~4 gridlines are drawn.
double _nicePaceInterval(double range) {
  const steps = <double>[10, 15, 30, 60, 120, 300, 600];
  for (final step in steps) {
    if (range / step <= 4) return step;
  }
  return (range / 4).ceilToDouble();
}
