import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';

/// Weekly distance bars for the run stats dashboard.
class RunWeeklyDistanceChart extends StatelessWidget {
  final List<RunWeekBucket> buckets;
  final String emptyLabel;

  const RunWeeklyDistanceChart({
    super.key,
    required this.buckets,
    required this.emptyLabel,
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
    final showEvery = buckets.length > 12
        ? 4
        : buckets.length > 8
            ? 2
            : 1;

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          minY: 0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
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
                reservedSize: 36,
                interval: _niceInterval(maxY),
                getTitlesWidget: (value, meta) {
                  if (value <= 0 || value >= maxY) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    value >= 10
                        ? value.toStringAsFixed(0)
                        : value.toStringAsFixed(1),
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= buckets.length) {
                    return const SizedBox.shrink();
                  }
                  if (i % showEvery != 0 && i != buckets.length - 1) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
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
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
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
                    width: buckets.length > 20
                        ? 6
                        : buckets.length > 12
                            ? 10
                            : 14,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(5),
                    ),
                    color: primary,
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

    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), -points[i].paceSecPerKm),
    ];

    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    final showEvery = points.length > 10 ? (points.length / 5).ceil() : 1;

    return SizedBox(
      height: 200,
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
              getTooltipItems: (touched) {
                return touched.map((t) {
                  final i = t.x.round();
                  if (i < 0 || i >= points.length) return null;
                  final p = points[i];
                  final date = DateFormat.MMMd().format(p.date);
                  return LineTooltipItem(
                    '$date\n${RunFormatters.paceWithUnit(p.paceSecPerKm)}',
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
            getDrawingHorizontalLine: (value) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
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
                reservedSize: 44,
                getTitlesWidget: (value, meta) {
                  final pace = -value;
                  if (pace < chartMin || pace > chartMax) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    RunFormatters.pace(pace),
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= points.length) {
                    return const SizedBox.shrink();
                  }
                  if (i % showEvery != 0 && i != points.length - 1) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
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

    final maxCount = buckets
        .map((b) => b.runCount)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = (maxCount + 1).toDouble().clamp(3.0, double.infinity);
    final secondary = theme.colorScheme.secondary;
    final muted = theme.colorScheme.onSurfaceVariant;
    final showEvery = buckets.length > 12
        ? 4
        : buckets.length > 8
            ? 2
            : 1;

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          minY: 0,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
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
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  if (value <= 0 || value != value.roundToDouble()) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    value.toInt().toString(),
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= buckets.length) {
                    return const SizedBox.shrink();
                  }
                  if (i % showEvery != 0 && i != buckets.length - 1) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
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
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
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
                    width: buckets.length > 20
                        ? 6
                        : buckets.length > 12
                            ? 10
                            : 14,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(5),
                    ),
                    color: secondary,
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

double _niceInterval(double maxY) {
  if (maxY <= 2) return 0.5;
  if (maxY <= 5) return 1;
  if (maxY <= 10) return 2;
  if (maxY <= 25) return 5;
  return 10;
}
